import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/operation_mode_controller.dart';
import 'package:agroquimicos/presentation/widgets/adaptive_entity_picker.dart';
import 'package:agroquimicos/voice/port/speech_transcription_port.dart';
import 'package:agroquimicos/voice/voice_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/f04_mode_ui_harness.dart';
import '../support/purchase_form_driver.dart';
import '../support_rdm2/a_purchase_sheet.dart';
import '../voice/support/fake_speech_transcription_port.dart';

typedef Row = Map<String, Object?>;

/// Panel de voz nuevo (láminas I-13, I-14 e I-15) en el MODO CON VARIAS
/// PERSONAS (decisión A del autor, 2026-11-13): la misma presentación que el
/// modo individual, con la guía de cada formulario, y el mismo
/// comportamiento: cancelar descarta resultados tardíos, el destinatario
/// dictado se conserva con su validación y nada se guarda sin «Confirmar».
/// Texto inyectado por el puerto falso (sintético): integración, no audio.
void main() {
  sqfliteFfiInit();

  late FakeSpeechTranscriptionPort port;

  Future<({AppDatabase database, ProviderContainer c, int relative})> open(
    WidgetTester tester,
    String name,
    String route,
    List<FakeTurn> script,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, name);
    await tester.runAsync(
      () => s.household.repo.addSupplier(name: 'Agro Norte'),
    );
    port = FakeSpeechTranscriptionPort(script: script, repeatLast: false);
    final c = await pumpModeApp(
      tester,
      s.database,
      extraOverrides: [
        speechPortFactoryProvider.overrideWith(
          (ref) =>
              () => port,
        ),
        wholeTurnPortFactoryProvider.overrideWith(
          (ref) =>
              () => port,
        ),
      ],
    );
    expect(c.read(operationModeProvider), OperationMode.shared);
    c.read(routerProvider).push(route);
    await waitFor(tester, find.byKey(const Key('voz-panel')));
    await settle(tester);
    return (database: s.database, c: c, relative: s.household.relative);
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await prepareReachableKey(tester, key);
    await tester.ensureVisible(reachable(find.byKey(Key(key))));
    await tester.pump();
    await tester.tap(reachable(find.byKey(Key(key))));
    await settle(tester);
  }

  Future<List<Row>> rows(
    WidgetTester tester,
    AppDatabase database,
    String sql,
  ) async => (await tester.runAsync(
    () async => (await database.database).rawQuery(sql),
  ))!;

  Future<int> count(WidgetTester tester, AppDatabase db, String table) async =>
      (await rows(tester, db, 'SELECT id FROM $table')).length;

  /// «Escuchando» con la hoja nueva: guía del formulario, «Cancelar»
  /// contorneado y «Terminar» relleno, sin el ✕ del panel en reposo.
  void expectListening(String hint) {
    expect(find.text('Escuchando'), findsOneWidget);
    expect(find.text(hint), findsOneWidget);
    expect(
      find.text('Nada se guarda solo: usted revisa y confirma.'),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is OutlinedButton && w.key == const Key('voz-cancelar-dictado'),
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is FilledButton && w.key == const Key('voz-terminar'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('voz-panel-cerrar')), findsNothing);
    // La presentación anterior del modo con varias personas ya no se usa.
    expect(find.text('Micrófono encendido'), findsNothing);
  }

  group('compra con varias personas', () {
    testWidgets('Escuchando con la guía «para quién»; el destinatario dictado '
        'se conserva y nada se guarda hasta confirmar', (tester) async {
      final w = await open(tester, 'pv-compra', '/compras/voz', const [
        FakeTurn(
          segment:
              'compra de diez litros de Glifosato a 50 bolivianos el litro, '
              'proveedor Agro Norte, todo para Hermana',
          endsOnStop: true,
        ),
      ]);
      await tapKey(tester, 'voz-hablar');
      expectListening('Diga producto, cantidad, precio y para quién');
      await tapKey(tester, 'voz-terminar');

      // Lámina I-15: «Dictar más» relleno y «Deshacer» contorneado.
      expect(find.byKey(const Key('voz-resultado')), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is FilledButton && w.key == const Key('voz-dictar-mas'),
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is OutlinedButton && w.key == const Key('voz-deshacer'),
        ),
        findsOneWidget,
      );
      // El aviso del modo individual no aparece: aquí el destinatario vale.
      expect(
        find.textContaining('Parte del dictado no corresponde'),
        findsNothing,
      );

      // El destinatario quedó en «Toda para una persona» de la línea.
      await openPurchaseLine(tester);
      final person = tester.widget<AdaptiveEntityPicker<Row>>(
        find.byWidgetPredicate(
          (x) => x is AdaptiveEntityPicker<Row> && x.label == 'Persona',
        ),
      );
      expect(person.value?['name'], 'Hermana');
      await closePurchaseLine(tester);

      // Confirmación humana: nada se escribe hasta «Confirmar compra».
      expect(await count(tester, w.database, 'purchases'), 0);
      await tapKey(tester, 'purchase-continue');
      await tester.tap(find.byKey(const Key('purchase-paid-no')));
      await settle(tester);
      expect(await count(tester, w.database, 'purchases'), 0);
      await tapKey(tester, 'purchase-confirm');
      await tester.pump(const Duration(milliseconds: 500));
      await settle(tester);
      expect(await count(tester, w.database, 'purchases'), 1);
      final alloc = await rows(
        tester,
        w.database,
        'SELECT person_id FROM purchase_allocations',
      );
      expect(alloc, [
        {'person_id': w.relative},
      ]);
    });

    testWidgets('sin destinatario dictado, «Continuar» sigue pidiendo para '
        'quién es: la validación del selector de persona no cambia', (
      tester,
    ) async {
      final w = await open(tester, 'pv-sin-persona', '/compras/voz', const [
        FakeTurn(
          segment:
              'compra de diez litros de Glifosato a 50 bolivianos el litro, '
              'proveedor Agro Norte',
          endsOnStop: true,
        ),
      ]);
      await tapKey(tester, 'voz-hablar');
      await tapKey(tester, 'voz-terminar');
      expect(find.byKey(const Key('voz-resultado')), findsOneWidget);
      await tapKey(tester, 'purchase-continue');
      expect(
        find.textContaining('Indique para quién es Glifosato'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('purchase-confirm')), findsNothing);
      expect(await count(tester, w.database, 'purchases'), 0);
    });

    testWidgets('«Procesando tu voz» y Cancelar: el resultado tardío no llega '
        'al formulario', (tester) async {
      final w = await open(tester, 'pv-cancelar', '/compras/voz', const [
        FakeTurn(silent: true),
      ]);
      await tapKey(tester, 'voz-hablar');
      port.emitForTest(
        const TranscriptionStageChanged(TranscriptionStage.processing),
      );
      await settle(tester);
      expect(find.text('Procesando tu voz'), findsOneWidget);
      expect(
        find.text('Los datos aparecerán en el formulario para que los revise.'),
        findsOneWidget,
      );
      expect(
        find.text('Lo que ya escribió a mano se conserva.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('voz-terminar')), findsNothing);
      await tapKey(tester, 'voz-cancelar-dictado');
      port.emitForTest(
        const TranscriptionSegment(
          'diez litros de Glifosato a 50 bolivianos el litro',
          elapsed: Duration.zero,
        ),
      );
      await settle(tester);
      await closePurchaseLine(tester);
      expect(find.textContaining('Dictado cancelado'), findsWidgets);
      // De vuelta al panel en reposo, sin nada aplicado ni guardado.
      expect(find.byKey(const Key('voz-hablar')), findsOneWidget);
      await openPurchaseLine(tester);
      expect(
        tester
            .widget<TextField>(
              find.byWidgetPredicate(
                (x) =>
                    x is TextField &&
                    x.decoration?.labelText == 'Cantidad comprada',
              ),
            )
            .controller!
            .text,
        '',
      );
      expect(await count(tester, w.database, 'purchases'), 0);
    });
  });

  for (final (route, hint, table) in [
    (
      '/aplicaciones/voz',
      'Diga chaco, superficie, producto y cantidad',
      'applications',
    ),
    (
      '/planificacion/voz',
      'Diga chaco, superficie, producto y dosis',
      'application_plans',
    ),
  ]) {
    testWidgets('$route con varias personas: Escuchando con la guía del '
        'formulario; Cancelar vuelve al panel sin guardar', (tester) async {
      final w = await open(tester, 'pv-${route.hashCode}', route, const [
        FakeTurn(silent: true),
      ]);
      await tapKey(tester, 'voz-hablar');
      expectListening(hint);
      await tapKey(tester, 'voz-cancelar-dictado');
      expect(find.text('Escuchando'), findsNothing);
      expect(find.byKey(const Key('voz-hablar')), findsOneWidget);
      expect(find.textContaining('Dictado cancelado'), findsWidgets);
      expect(await count(tester, w.database, table), 0);
    });
  }
}
