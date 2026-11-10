import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/presentation/voice/voice_purchase_draft_screen.dart';
import 'package:agroquimicos/voice/voice_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/f04_mode_fixtures.dart';
import '../voice/support/fake_speech_transcription_port.dart';

/// Recorrido completo con texto **escrito** (sin micrófono ni modelo): puerto
/// de transcripción simulado → sesión → intérprete → borrador → pantalla
/// (F09, 2026-11-10). No prueba el reconocimiento: eso sólo se ve en el
/// teléfono. Nada se registra en estas pruebas.
void main() {
  sqfliteFfiInit();

  late AppDatabase database;

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

  Future<void> pumpScreen(WidgetTester tester, String segment) async {
    final repo = (await tester.runAsync(() async {
      database = openDb(inMemoryDatabasePath);
      final created = AgroRepository(database);
      await seedHousehold(created);
      await created.addSupplier(name: 'Agro insumos DEMO');
      await created.addProduct(name: 'Herbicida DEMO');
      await created.addProduct(name: 'Fungicida DEMO');
      await created.addProduct(name: 'Insecticida DEMO');
      return created;
    }))!;
    final port = FakeSpeechTranscriptionPort(
      script: [FakeTurn(segment: segment, endsOnStop: true)],
    );
    tester.view.physicalSize = const Size(500, 2600);
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
    // Hablar y detener: el segmento entra como texto cerrado.
    for (var i = 0; i < 2; i++) {
      await tester.ensureVisible(find.byKey(const Key('voz-boton-microfono')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('voz-boton-microfono')));
      await drain(tester);
    }
  }

  Future<void> tap(WidgetTester tester, Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.pump();
    await tester.tap(find.byKey(key));
    await drain(tester);
  }

  String fieldText(WidgetTester tester, String key) =>
      tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

  bool registerEnabled(WidgetTester tester) =>
      tester
          .widget<ButtonStyleButton>(find.byKey(const Key('voz-registrar')))
          .onPressed !=
      null;

  Future<int> purchases(WidgetTester tester) async => (await tester.runAsync(
    () async => (await (await database.database).query('purchases')).length,
  ))!;

  for (final said in const [
    'Compré fungicida demo',
    'Compré Fungicida DEMO.',
  ]) {
    testWidgets('R6 «$said»: una línea incompleta a la vista, sin poder '
        'registrar', (tester) async {
      await pumpScreen(tester, said);
      expect(find.byKey(const Key('voz-linea-1')), findsOneWidget);
      expect(find.byKey(const Key('voz-linea-2')), findsNothing);
      expect(find.text('Aplicado al borrador:'), findsOneWidget);
      expect(
        find.text('No cambió el borrador: no se reconoció nada que completar.'),
        findsNothing,
      );
      expect(find.textContaining('Fungicida DEMO'), findsWidgets);
      expect(fieldText(tester, 'voz-cantidad-1'), '');
      expect(fieldText(tester, 'voz-precio-1'), '');
      await tap(tester, const Key('voz-pago-no'));
      expect(registerEnabled(tester), isFalse);
      expect(await purchases(tester), 0);
    });
  }

  testWidgets('«por un total de cien bolivianos»: el importe se ve como '
      'candidato y «Total de la línea» da 50 por litro, confirmado por la '
      'persona', (tester) async {
    await pumpScreen(
      tester,
      'Compré dos litros de Fungicida DEMO por un total de cien bolivianos',
    );
    expect(find.byKey(const Key('voz-linea-1')), findsOneWidget);
    // El total no va en «Precio por L», pero su cifra está en el aviso.
    expect(fieldText(tester, 'voz-precio-1'), '');
    expect(find.textContaining('Importe total oído: 100 Bs'), findsOneWidget);
    // Un total no ofrece «Por L»: sólo repartirlo, o escribir el precio.
    expect(find.byKey(const Key('voz-precio-por-unidad-1')), findsNothing);
    expect(find.byKey(const Key('voz-precio-sin-linea')), findsNothing);
    await tap(tester, const Key('voz-precio-total-1'));
    expect(fieldText(tester, 'voz-precio-1'), '50');
    expect(find.textContaining('Total calculado'), findsOneWidget);
    expect(await purchases(tester), 0);
  });

  testWidgets('total sin cantidad: «Total de la línea» no borra el importe; '
      'con la cantidad escrita, se reparte', (tester) async {
    await pumpScreen(
      tester,
      'Compré fungicida demo por un total de cien bolivianos',
    );
    await tap(tester, const Key('voz-precio-total-1'));
    expect(
      find.textContaining('complete antes el producto y la cantidad'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('voz-precio-total-1')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('voz-cantidad-1')), '2');
    await drain(tester);
    await tap(tester, const Key('voz-precio-total-1'));
    expect(fieldText(tester, 'voz-precio-1'), '50');
    expect(await purchases(tester), 0);
  });
}
