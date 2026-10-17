import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/presentation/voice/voice_application_draft_screen.dart';
import 'package:agroquimicos/voice/voice_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/f04_mode_fixtures.dart';
import '../voice/support/fake_speech_transcription_port.dart';

/// Pantalla de aplicación por voz (#15), con el mismo patrón que la compra y
/// la planificación (#16). Puerto fake: no prueba el reconocimiento real.
void main() {
  sqfliteFfiInit();

  const full =
      'apliqué dos litros de Glifosato en el chaco titular en media hectárea';

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
      await household.buy(household.titular, 5000);
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
        child: const MaterialApp(
          home: Scaffold(body: VoiceApplicationDraftScreen()),
        ),
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

  Future<int> applications(WidgetTester tester) async => (await tester.runAsync(
    () async => (await (await database.database).query('applications')).length,
  ))!;

  testWidgets(
    'dictar arma la aplicación con el stock; dos toques registran una',
    (tester) async {
      await pumpScreen(
        tester,
        script: const [FakeTurn(segment: full, endsOnStop: true)],
      );
      await tap(tester, const Key('voz-boton-microfono'));
      await tap(tester, const Key('voz-boton-microfono'));
      expect(find.byKey(const Key('voz-linea-1')), findsOneWidget);
      expect(find.textContaining('quedaría 3 L'), findsOneWidget);
      expect(await applications(tester), 0);

      await tester.ensureVisible(find.byKey(const Key('voz-registrar')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('voz-registrar')));
      await tester.tap(
        find.byKey(const Key('voz-registrar')),
        warnIfMissed: false,
      );
      await drain(tester);
      expect(await applications(tester), 1);
    },
  );

  testWidgets('cancelar no registra nada y suelta el micrófono', (
    tester,
  ) async {
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

  testWidgets('la cantidad corregida a mano no la cambia la voz', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      script: const [
        FakeTurn(segment: full, endsOnStop: true),
        FakeTurn(segment: 'cuatro litros de Glifosato', endsOnStop: true),
      ],
    );
    await tap(tester, const Key('voz-boton-microfono'));
    await tap(tester, const Key('voz-boton-microfono'));
    await tester.enterText(find.byKey(const Key('voz-cantidad-1')), '1,5');
    await drain(tester);
    await tap(tester, const Key('voz-boton-microfono'));
    await tap(tester, const Key('voz-boton-microfono'));
    expect(find.text('«cuatro litros de Glifosato»'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('voz-cantidad-1')))
          .controller!
          .text,
      '1,5',
    );
    expect(find.textContaining('quedaría 3,5 L'), findsOneWidget);
  });

  testWidgets('Atrás con una aplicación empezada pregunta y no registra', (
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
    expect(await applications(tester), 0);
  });

  testWidgets(
    'un área que no es múltiplo de 100 m² se ve exacta y no bloquea',
    (tester) async {
      await pumpScreen(
        tester,
        script: const [
          FakeTurn(
            segment: 'apliqué dos litros de Glifosato en el chaco Impar',
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
