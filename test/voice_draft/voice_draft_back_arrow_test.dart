import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/presentation/voice/voice_entry_screen.dart';
import 'package:agroquimicos/presentation/voice/voice_purchase_draft_screen.dart';
import 'package:agroquimicos/voice/voice_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/f04_mode_ui_harness.dart';
import '../voice/support/fake_speech_transcription_port.dart';

/// D1 de la verificación en el emulador (2026-11-08, APK `a51d409`): la flecha
/// «Volver» de la cabecera (`PageFrame`) salía de un borrador de voz empezado
/// sin preguntar y lo perdía; el Atrás del sistema sí preguntaba. La flecha
/// debe respetar el `PopScope` de la pantalla, como el Atrás del sistema.
void main() {
  sqfliteFfiInit();

  Future<void> open(WidgetTester tester, String name) async {
    tester.view.physicalSize = const Size(500, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final s = await activatedHousehold(tester, name);
    final port = FakeSpeechTranscriptionPort(script: const []);
    final c = await pumpModeApp(
      tester,
      s.database,
      extraOverrides: <Override>[
        speechPortFactoryProvider.overrideWith(
          (ref) =>
              () => port,
        ),
        // La compra tiene su propio puerto (turno entero): el mismo simulado.
        wholeTurnPortFactoryProvider.overrideWith(
          (ref) =>
              () => port,
        ),
      ],
    );
    final router = c.read(routerProvider);
    router.go('/operaciones');
    await settle(tester);
    router.push(voiceEntryPath);
    await settle(tester);
    router.push(voicePurchasePath);
    await settle(tester);
    expect(find.byType(VoicePurchaseDraftScreen), findsOneWidget);
  }

  Future<void> finishTransition(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await settle(tester);
  }

  testWidgets('con un borrador empezado, la flecha «Volver» pregunta antes de '
      'descartar y «Cancelar» lo conserva', (tester) async {
    await open(tester, 'd1-flecha-pregunta');
    // Trabajo manual: responder la pregunta del pago ya es borrador empezado.
    await tapKey(tester, 'voz-pago-no');

    await tester.tap(find.byTooltip('Volver').first);
    await settle(tester);
    expect(find.text('¿Descartar el borrador?'), findsOneWidget);

    // Quedarse: el borrador sigue, con lo respondido.
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Cancelar'),
      ),
    );
    await settle(tester);
    await finishTransition(tester);
    expect(find.text('¿Descartar el borrador?'), findsNothing);
    expect(find.byType(VoicePurchaseDraftScreen), findsOneWidget);
  });

  testWidgets('con un borrador empezado, la flecha «Volver» y «Descartar» '
      'salen a la entrada de voz', (tester) async {
    await open(tester, 'd1-flecha-descarta');
    await tapKey(tester, 'voz-pago-no');
    await tester.tap(find.byTooltip('Volver').first);
    await settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Descartar'),
      ),
    );
    await settle(tester);
    await finishTransition(tester);
    expect(find.byType(VoicePurchaseDraftScreen), findsNothing);
    expect(find.byType(VoiceEntryScreen), findsOneWidget);
  });

  testWidgets('sin nada empezado, la flecha «Volver» sale sin preguntar', (
    tester,
  ) async {
    await open(tester, 'd1-flecha-vacio');
    await tester.tap(find.byTooltip('Volver').first);
    await settle(tester);
    await finishTransition(tester);
    expect(find.text('¿Descartar el borrador?'), findsNothing);
    expect(find.byType(VoicePurchaseDraftScreen), findsNothing);
    expect(find.byType(VoiceEntryScreen), findsOneWidget);
  });
}
