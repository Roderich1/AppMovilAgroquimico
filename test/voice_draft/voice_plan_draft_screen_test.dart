import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/presentation/voice/voice_plan_draft_screen.dart';
import 'package:agroquimicos/voice/voice_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/f04_mode_fixtures.dart';
import '../voice/support/fake_speech_transcription_port.dart';

/// Pantalla de planificación por voz (#14), con el mismo patrón que la compra
/// (#16). Puerto fake: no prueba el reconocimiento real.
void main() {
  sqfliteFfiInit();

  const full =
      'planificar el chaco titular con dos litros por hectárea de Glifosato';

  late AppDatabase database;
  late FakeSpeechTranscriptionPort port;

  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      for (var f = 0; f < 6; f++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    }
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    required List<FakeTurn> script,
  }) async {
    final repo = (await tester.runAsync(() async {
      database = openDb(inMemoryDatabasePath);
      final created = AgroRepository(database);
      final household = await seedHousehold(created);
      // Un chaco cuya área no es múltiplo de 100 m² (M-1).
      await created.addFarm(
        ownerId: household.titular,
        name: 'Impar',
        areaM2: 12345,
      );
      return created;
    }))!;
    port = FakeSpeechTranscriptionPort(script: script, repeatLast: false);
    tester.view.physicalSize = const Size(500, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          speechPortFactoryProvider.overrideWith(
            (ref) =>
                () => port,
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: VoicePlanDraftScreen())),
      ),
    );
    await drain(tester);
  }

  Future<void> tap(WidgetTester tester, Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.pump();
    await tester.tap(find.byKey(key));
    await drain(tester);
  }

  Future<int> plans(WidgetTester tester) async => (await tester.runAsync(
    () async =>
        (await (await database.database).query('application_plans')).length,
  ))!;

  testWidgets('dictar arma el plan; dos toques crean un solo plan', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      script: const [FakeTurn(segment: full, endsOnStop: true)],
    );
    await tap(tester, const Key('voz-boton-microfono'));
    await tap(tester, const Key('voz-boton-microfono'));
    expect(find.byKey(const Key('voz-linea-1')), findsOneWidget);
    expect(find.textContaining('Necesita 2 L'), findsOneWidget);
    expect(await plans(tester), 0);

    await tester.ensureVisible(find.byKey(const Key('voz-registrar')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('voz-registrar')));
    await tester.tap(
      find.byKey(const Key('voz-registrar')),
      warnIfMissed: false,
    );
    await drain(tester);
    expect(await plans(tester), 1);
  });

  testWidgets('cancelar no crea plan y suelta el micrófono', (tester) async {
    await pumpScreen(
      tester,
      script: const [
        FakeTurn(segment: full, endsOnStop: true),
        FakeTurn(partials: ['y otra'], endsOnStop: true),
      ],
    );
    final before = (await tester.runAsync(
      () async => dumpTables(await database.database),
    ))!;
    await tap(tester, const Key('voz-boton-microfono'));
    await tap(tester, const Key('voz-boton-microfono'));
    await tap(tester, const Key('voz-boton-microfono'));
    expect(port.microphoneOpen, isTrue);
    await tap(tester, const Key('voz-cancelar'));
    expect(port.microphoneOpen, isFalse);
    expect(
      (await tester.runAsync(() async => dumpTables(await database.database)))!,
      before,
    );
  });

  testWidgets('la dosis corregida a mano no la cambia la voz', (tester) async {
    await pumpScreen(
      tester,
      script: const [
        FakeTurn(segment: full, endsOnStop: true),
        FakeTurn(
          segment: 'cinco litros por hectárea de Glifosato',
          endsOnStop: true,
        ),
      ],
    );
    await tap(tester, const Key('voz-boton-microfono'));
    await tap(tester, const Key('voz-boton-microfono'));
    await tester.enterText(find.byKey(const Key('voz-dosis-1')), '1,5');
    await drain(tester);
    await tap(tester, const Key('voz-boton-microfono'));
    await tap(tester, const Key('voz-boton-microfono'));
    expect(
      find.text('«cinco litros por hectárea de Glifosato»'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('voz-dosis-1')))
          .controller!
          .text,
      '1,5',
    );
    expect(find.textContaining('Necesita 1,5 L'), findsOneWidget);
  });

  testWidgets('Atrás con un plan empezado pregunta y no crea nada', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      script: const [FakeTurn(segment: full, endsOnStop: true)],
    );
    await tap(tester, const Key('voz-boton-microfono'));
    await tap(tester, const Key('voz-boton-microfono'));
    await tester.binding.handlePopRoute();
    await drain(tester);
    expect(find.text('¿Descartar el borrador?'), findsOneWidget);
    await tester.tap(find.text('Descartar'));
    await drain(tester);
    expect(await plans(tester), 0);
  });

  testWidgets(
    'un área que no es múltiplo de 100 m² se ve exacta y no bloquea',
    (tester) async {
      await pumpScreen(
        tester,
        script: const [
          FakeTurn(
            segment:
                'planificar el chaco Impar con dos litros por hectárea de '
                'Glifosato',
            endsOnStop: true,
          ),
        ],
      );
      await tap(tester, const Key('voz-boton-microfono'));
      await tap(tester, const Key('voz-boton-microfono'));
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('voz-area')))
            .controller!
            .text,
        '1,2345',
      );
      expect(find.textContaining('no coincide'), findsNothing);
      expect(
        tester
            .widget<ButtonStyleButton>(find.byKey(const Key('voz-registrar')))
            .onPressed,
        isNotNull,
      );
    },
  );
}
