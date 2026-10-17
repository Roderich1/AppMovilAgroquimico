import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/presentation/voice/voice_purchase_draft_screen.dart';
import 'package:agroquimicos/voice/port/speech_transcription_port.dart';
import 'package:agroquimicos/voice/voice_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/f04_mode_fixtures.dart';
import '../voice/support/fake_speech_transcription_port.dart';

/// Pantalla de compra por voz (#11 con el patrón #16), con la base real y el
/// puerto de transcripción fake. **No prueba el motor de reconocimiento**: eso
/// exige dictado real en el teléfono.
void main() {
  sqfliteFfiInit();

  const full =
      'compra de cincuenta litros de Bellator a 186 bolivianos el litro, '
      'proveedor Agro Norte, todo para Hermana';

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
    bool repeatLast = false,
  }) async {
    final repo = (await tester.runAsync(() async {
      database = openDb(inMemoryDatabasePath);
      final created = AgroRepository(database);
      await seedHousehold(created);
      await created.addSupplier(name: 'Agro Norte');
      await created.addProduct(name: 'Bellator');
      return created;
    }))!;
    port = FakeSpeechTranscriptionPort(script: script, repeatLast: repeatLast);
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
          home: Scaffold(body: VoicePurchaseDraftScreen()),
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

  Future<Map<String, List<Map<String, Object?>>>> dump(
    WidgetTester tester,
  ) async =>
      (await tester.runAsync(() async => dumpTables(await database.database)))!;

  Future<int> count(WidgetTester tester, String table) async =>
      (await tester.runAsync(
        () async => (await (await database.database).query(table)).length,
      ))!;

  bool registerEnabled(WidgetTester tester) =>
      tester
          .widget<ButtonStyleButton>(find.byKey(const Key('voz-registrar')))
          .onPressed !=
      null;

  testWidgets('lo provisional se ve aparte y no cambia el borrador', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      script: const [
        FakeTurn(
          partials: ['compra de cincuenta'],
          segment: full,
          endsOnStop: true,
        ),
      ],
    );
    await tap(tester, const Key('voz-boton-microfono'));
    expect(find.byKey(const Key('voz-parcial')), findsOneWidget);
    expect(find.byKey(const Key('voz-aplicado')), findsNothing);
    expect(find.byKey(const Key('voz-linea-1')), findsNothing);

    await tap(tester, const Key('voz-boton-microfono')); // detener
    expect(find.byKey(const Key('voz-aplicado')), findsOneWidget);
    expect(find.byKey(const Key('voz-linea-1')), findsOneWidget);
    expect(find.textContaining('Total calculado'), findsOneWidget);
    expect(registerEnabled(tester), isTrue);
  });

  testWidgets('dos toques en «Registrar compra» escriben una sola compra', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      script: const [FakeTurn(segment: full, endsOnStop: true)],
    );
    await tap(tester, const Key('voz-boton-microfono'));
    await tap(tester, const Key('voz-boton-microfono'));
    expect(await count(tester, 'purchases'), 0);

    await tester.ensureVisible(find.byKey(const Key('voz-registrar')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('voz-registrar')));
    await tester.tap(
      find.byKey(const Key('voz-registrar')),
      warnIfMissed: false,
    );
    await drain(tester);

    expect(await count(tester, 'purchases'), 1);
    expect(await count(tester, 'purchase_items'), 1);
  });

  testWidgets('cancelar no escribe nada y suelta el micrófono', (tester) async {
    await pumpScreen(
      tester,
      script: const [
        FakeTurn(segment: full, endsOnStop: true),
        FakeTurn(partials: ['y otra'], endsOnStop: true),
      ],
    );
    final before = await dump(tester);
    await tap(tester, const Key('voz-boton-microfono'));
    await tap(tester, const Key('voz-boton-microfono'));
    await tap(tester, const Key('voz-boton-microfono')); // vuelve a escuchar
    expect(port.microphoneOpen, isTrue);

    await tap(tester, const Key('voz-cancelar'));
    expect(port.microphoneOpen, isFalse);
    expect(await dump(tester), before);
  });

  testWidgets('salir sin confirmar libera el micrófono y no escribe', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      script: const [
        FakeTurn(segment: full, endsOnStop: true),
        FakeTurn(partials: ['y otra'], endsOnStop: true),
      ],
    );
    final before = await dump(tester);
    await tap(tester, const Key('voz-boton-microfono'));
    await tap(tester, const Key('voz-boton-microfono'));
    await tap(tester, const Key('voz-boton-microfono'));
    expect(port.microphoneOpen, isTrue);

    await tester.pumpWidget(const SizedBox());
    await drain(tester);
    expect(port.microphoneOpen, isFalse);
    expect(await dump(tester), before);
  });

  testWidgets('lo corregido a mano no lo cambia un dictado posterior', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      script: const [
        FakeTurn(segment: full, endsOnStop: true),
        FakeTurn(segment: 'sesenta litros de Bellator', endsOnStop: true),
      ],
    );
    await tap(tester, const Key('voz-boton-microfono'));
    await tap(tester, const Key('voz-boton-microfono'));

    await tester.enterText(find.byKey(const Key('voz-cantidad-1')), '30');
    await drain(tester);
    expect(find.text('Corregido a mano'), findsOneWidget);

    await tap(tester, const Key('voz-boton-microfono'));
    await tap(tester, const Key('voz-boton-microfono'));
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('voz-cantidad-1')))
          .controller!
          .text,
      '30',
    );
    // El dictado posterior sí llegó y se aplicó: no cambió lo corregido.
    expect(find.text('«sesenta litros de Bellator»'), findsOneWidget);

    await tap(tester, const Key('voz-registrar'));
    final items = (await tester.runAsync(
      () async => (await database.database).query('purchase_items'),
    ))!;
    expect(items.single['quantity_base'], 30000);
  });

  testWidgets('un producto que no está en el catálogo bloquea registrar', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      script: const [
        FakeTurn(
          segment:
              'compra de veinte litros de Paraquat a 50 bolivianos el litro, '
              'proveedor Agro Norte, todo para Hermana',
          endsOnStop: true,
        ),
      ],
    );
    await tap(tester, const Key('voz-boton-microfono'));
    await tap(tester, const Key('voz-boton-microfono'));
    expect(find.byKey(const Key('voz-bloqueos')), findsOneWidget);
    expect(find.textContaining('«paraquat»'), findsWidgets);
    expect(registerEnabled(tester), isFalse);
    expect(await count(tester, 'products'), 2);
  });

  testWidgets(
    'un tipo de cambio dictado después se ve y es lo que se escribe',
    (tester) async {
      await pumpScreen(
        tester,
        script: const [
          FakeTurn(
            segment:
                'compra de diez litros de Bellator a 25 dólares el litro, '
                'proveedor Agro Norte, todo para Hermana',
            endsOnStop: true,
          ),
          FakeTurn(segment: 'tipo de cambio 6,96', endsOnStop: true),
        ],
      );
      await tap(tester, const Key('voz-boton-microfono'));
      await tap(tester, const Key('voz-boton-microfono'));
      // El campo aparece vacío y bloquea.
      expect(find.byKey(const Key('voz-tipo-cambio')), findsOneWidget);
      expect(registerEnabled(tester), isFalse);

      await tap(tester, const Key('voz-boton-microfono'));
      await tap(tester, const Key('voz-boton-microfono'));
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('voz-tipo-cambio')))
            .controller!
            .text,
        '6,96',
      );
      expect(registerEnabled(tester), isTrue);

      await tap(tester, const Key('voz-registrar'));
      final items = (await tester.runAsync(
        () async => (await database.database).query('purchase_items'),
      ))!;
      expect(items.single['exchange_rate_scaled'], 6960000);
    },
  );

  testWidgets('Atrás con un borrador empezado pregunta antes de descartar', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      script: const [
        FakeTurn(segment: full, endsOnStop: true),
        FakeTurn(partials: ['y otra'], endsOnStop: true),
      ],
    );
    final before = await dump(tester);
    await tap(tester, const Key('voz-boton-microfono'));
    await tap(tester, const Key('voz-boton-microfono'));
    await tap(tester, const Key('voz-boton-microfono'));
    expect(port.microphoneOpen, isTrue);

    await tester.binding.handlePopRoute();
    await drain(tester);
    expect(find.text('¿Descartar el borrador?'), findsOneWidget);
    await tester.tap(find.text('Descartar'));
    await drain(tester);
    expect(port.microphoneOpen, isFalse);
    expect(await dump(tester), before);
  });

  testWidgets(
    'aceptado el reconocedor del sistema, el aviso de Internet queda',
    (tester) async {
      await pumpScreen(
        tester,
        script: const [
          FakeTurn(
            acceptsRoute: TranscriptionEngineRoute.systemDefault,
            failDetail: 'android-error-12',
            segment: full,
            endsOnStop: true,
          ),
        ],
        // Cada idioma de la lista es un turno: el mismo fallo para todos.
        repeatLast: true,
      );
      await tester.ensureVisible(find.byKey(const Key('voz-boton-microfono')));
      await tester.tap(find.byKey(const Key('voz-boton-microfono')));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await drain(tester);
      expect(find.byKey(const Key('voz-aviso-servicio-sistema')), findsNothing);
      await tap(tester, const Key('voz-usar-servicio-sistema'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(
        find.byKey(const Key('voz-aviso-servicio-sistema')),
        findsOneWidget,
      );
      expect(find.textContaining('podría usar Internet'), findsWidgets);
    },
  );
}
