import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/presentation/screens/purchase_form_screen.dart';
import 'package:agroquimicos/presentation/voice/voice_application_draft_screen.dart';
import 'package:agroquimicos/presentation/voice/voice_entry_screen.dart';
import 'package:agroquimicos/presentation/voice/voice_plan_draft_screen.dart';
import 'package:agroquimicos/presentation/voice/voice_purchase_draft_screen.dart';
import 'package:agroquimicos/voice/voice_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/f04_mode_ui_harness.dart';
import '../voice/support/fake_speech_transcription_port.dart';

/// Conexión de la voz con la app real (F09): entrada desde Operaciones,
/// formularios ↔ voz, FAB, modo propio y cambio de modalidad. El puerto de
/// voz es el fake: no prueba el reconocimiento real.
void main() {
  sqfliteFfiInit();

  late FakeSpeechTranscriptionPort port;

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await settle(tester);
  }

  Future<dynamic> openApp(WidgetTester tester, String name) async {
    tester.view.physicalSize = const Size(500, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final s = await activatedHousehold(tester, name);
    await tester.runAsync(
      () => s.household.repo.addSupplier(name: 'Agro Norte'),
    );
    port = FakeSpeechTranscriptionPort(
      script: const [
        FakeTurn(
          segment:
              'compra de diez litros de Glifosato a 50 bolivianos el litro, '
              'proveedor Agro Norte, todo para Hermana',
          endsOnStop: true,
        ),
      ],
      repeatLast: false,
    );
    final c = await pumpModeApp(
      tester,
      s.database,
      extraOverrides: [
        speechPortFactoryProvider.overrideWith(
          (ref) =>
              () => port,
        ),
      ],
    );
    return (c: c, s: s);
  }

  testWidgets('Operaciones → Registrar por voz → los tres borradores', (
    tester,
  ) async {
    final app = await openApp(tester, 'entrada');
    app.c.read(routerProvider).go('/operaciones');
    await settle(tester);

    await tapVisible(tester, find.text('Registrar por voz'));
    expect(find.byType(VoiceEntryScreen), findsOneWidget);

    for (final (key, screen) in [
      ('voz-entrada-compra', VoicePurchaseDraftScreen),
      ('voz-entrada-plan', VoicePlanDraftScreen),
      ('voz-entrada-aplicacion', VoiceApplicationDraftScreen),
    ]) {
      await tapVisible(tester, find.byKey(Key(key)));
      expect(find.byType(screen), findsOneWidget, reason: key);
      // Sin dictar nada, Atrás vuelve a la entrada sin preguntar.
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(VoiceEntryScreen), findsOneWidget, reason: key);
    }
  });

  testWidgets('en las pantallas de voz no aparece el FAB global', (
    tester,
  ) async {
    final app = await openApp(tester, 'fab');
    app.c.read(routerProvider).go('/compras/voz');
    await settle(tester);
    expect(find.byType(VoicePurchaseDraftScreen), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('formulario de compra → Dictar → borrador → formulario manual', (
    tester,
  ) async {
    final app = await openApp(tester, 'form');
    app.c.read(routerProvider).go('/compras');
    await settle(tester);
    app.c.read(routerProvider).push('/compras/nueva');
    await settle(tester);
    expect(find.byType(PurchaseFormScreen), findsOneWidget);

    await tapVisible(tester, find.byKey(const Key('form-dictar')));
    // El formulario recién abierto ya cuenta como empezado: se pregunta.
    if (find.text('Descartar y dictar').evaluate().isNotEmpty) {
      await tester.tap(find.text('Descartar y dictar'));
      await settle(tester);
    }
    expect(find.byType(VoicePurchaseDraftScreen), findsOneWidget);
    expect(find.byType(PurchaseFormScreen), findsNothing);

    await tapVisible(tester, find.byKey(const Key('voz-borrador-manual')));
    expect(find.byType(PurchaseFormScreen), findsOneWidget);
    expect(find.byType(VoicePurchaseDraftScreen), findsNothing);
    expect(port.microphoneOpen, isFalse);
  });

  testWidgets('propio: la compra por voz es del titular y la persona dictada '
      'se ignora; un cambio de modalidad bloquea registrar', (tester) async {
    final app = await openApp(tester, 'propio');
    await switchModeBehindScreen(
      tester,
      app.c,
      app.s.database,
      OperationMode.personal,
    );
    app.c.read(routerProvider).go('/compras/voz');
    await settle(tester);

    expect(find.byKey(const Key('voz-titular')), findsOneWidget);
    expect(find.byKey(const Key('voz-borrador-persona')), findsNothing);

    await tapVisible(tester, find.byKey(const Key('voz-boton-microfono')));
    await tapVisible(tester, find.byKey(const Key('voz-boton-microfono')));
    expect(find.textContaining('Se ignoró «hermana»'), findsOneWidget);
    ButtonStyleButton register() => tester.widget<ButtonStyleButton>(
      find.byKey(const Key('voz-registrar')),
    );
    expect(register().onPressed, isNotNull);

    await switchModeBehindScreen(
      tester,
      app.c,
      app.s.database,
      OperationMode.shared,
    );
    expect(find.byKey(const Key('mode-changed-notice')), findsOneWidget);
    expect(register().onPressed, isNull);
  });

  testWidgets('con un borrador dictado, pasar al formulario pregunta y no '
      'escribe', (tester) async {
    final app = await openApp(tester, 'manual');
    app.c.read(routerProvider).go('/compras/voz');
    await settle(tester);
    await tapVisible(tester, find.byKey(const Key('voz-boton-microfono')));
    await tapVisible(tester, find.byKey(const Key('voz-boton-microfono')));
    expect(find.byKey(const Key('voz-linea-1')), findsOneWidget);

    await tapVisible(tester, find.byKey(const Key('voz-borrador-manual')));
    expect(find.text('¿Descartar el borrador?'), findsOneWidget);
    await tester.tap(find.text('Descartar y abrir el formulario'));
    await settle(tester);
    expect(find.byType(PurchaseFormScreen), findsOneWidget);
    expect(port.microphoneOpen, isFalse);
    final purchases = await tester.runAsync(
      () async => (await app.s.database.database).query('purchases'),
    );
    expect(purchases, isEmpty);
  });
}
