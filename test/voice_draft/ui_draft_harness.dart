/// Arnés de las pruebas de presentación de los borradores de voz (hallazgos
/// del POCO, 2026-11-08): la pantalla con la base real en memoria y el puerto
/// de voz falso. El texto que entrega el puerto falso es **texto inyectado**,
/// no reconocimiento real.
library;

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/voice/voice_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/f04_mode_fixtures.dart';
import '../voice/support/fake_speech_transcription_port.dart';

final class UiDraftWorld {
  UiDraftWorld(this.database, this.household, this.port);
  final AppDatabase database;
  final Household household;
  final FakeSpeechTranscriptionPort port;
}

/// Deja correr la E/S real (sqflite) y bombea fotogramas. Sin el
/// `runAsync`, las lecturas de la base quedan esperando.
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

/// Abre [screen] sobre un hogar sembrado ([seedHousehold]) más lo que añada
/// [seed]. [script] es el texto inyectado por el puerto falso.
Future<UiDraftWorld> pumpDraftScreen(
  WidgetTester tester, {
  required Widget screen,
  required List<FakeTurn> script,
  Future<void> Function(AgroRepository repo, Household household)? seed,
}) async {
  sqfliteFfiInit();
  final (database, household) = (await tester.runAsync(() async {
    final database = openDb(inMemoryDatabasePath);
    final repo = AgroRepository(database);
    final household = await seedHousehold(repo);
    if (seed != null) await seed(repo, household);
    return (database, household);
  }))!;
  final port = FakeSpeechTranscriptionPort(script: script, repeatLast: false);
  tester.view.physicalSize = const Size(500, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(household.repo),
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
      child: MaterialApp(home: Scaffold(body: screen)),
    ),
  );
  await drain(tester);
  // La primera apertura de la base (FFI) puede tardar más que un `drain`:
  // sin borrador cargado, el texto inyectado esperaría y la prueba miraría
  // antes de tiempo.
  await until(
    tester,
    () => find.byKey(const Key('voz-registrar')).evaluate().isNotEmpty,
  );
  return UiDraftWorld(database, household, port);
}

/// Espera, con tope, a que [ready] se cumpla, dejando correr la E/S real.
Future<void> until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

/// Espera a que el texto de [key] cumpla [ready] (por ejemplo, el stock
/// leído del dueño del chaco).
Future<void> untilText(
  WidgetTester tester,
  String key,
  bool Function(String text) ready,
) => until(tester, () {
  final found = find.byKey(Key(key)).evaluate();
  return found.isNotEmpty && ready((found.single.widget as Text).data ?? '');
});

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await drain(tester);
}

/// Abre y cierra el micrófono: el puerto falso entrega el turno siguiente
/// del guion (texto inyectado).
Future<void> dictate(WidgetTester tester) async {
  await tapKey(tester, 'voz-boton-microfono');
  await tapKey(tester, 'voz-boton-microfono');
}

/// Elige [option] en la hoja del selector [key].
Future<void> pick(WidgetTester tester, String key, String option) async {
  await tapKey(tester, key);
  await tester.tap(
    find
        .descendant(of: find.byType(BottomSheet), matching: find.text(option))
        .last,
  );
  await drain(tester);
}

/// Abre la hoja del selector [key] y la cierra sin elegir.
Future<void> openAndDismiss(WidgetTester tester, String key) async {
  await tapKey(tester, key);
  expect(find.byType(BottomSheet), findsOneWidget);
  await tester.tapAt(const Offset(10, 10));
  await drain(tester);
  expect(find.byType(BottomSheet), findsNothing);
}

String fieldText(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

/// El estado que muestra la fila del campo (`voz-estado-<id>`).
String fieldState(WidgetTester tester, String id) =>
    tester.widget<Text>(find.byKey(Key('voz-estado-$id'))).data!;

bool registerEnabled(WidgetTester tester) =>
    tester
        .widget<ButtonStyleButton>(find.byKey(const Key('voz-registrar')))
        .onPressed !=
    null;

/// Lo que muestra el selector [key] como elegido.
bool pickerShows(String key, String name) => find
    .descendant(of: find.byKey(Key(key)), matching: find.text(name))
    .evaluate()
    .isNotEmpty;

Future<Map<String, List<Map<String, Object?>>>> dump(
  WidgetTester tester,
  AppDatabase database,
) async {
  await drain(tester);
  return (await tester.runAsync(
    () async => dumpTables(await database.database),
  ))!;
}

Future<List<Map<String, Object?>>> rows(
  WidgetTester tester,
  AppDatabase database,
  String table,
) async {
  await drain(tester);
  return (await tester.runAsync(
    () async => (await database.database).query(table, orderBy: 'id'),
  ))!;
}

/// Pulsa «Registrar …» dos veces seguidas (doble toque).
Future<void> doubleTapRegister(WidgetTester tester) async {
  final finder = find.byKey(const Key('voz-registrar'));
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.tap(finder, warnIfMissed: false);
  await drain(tester);
}
