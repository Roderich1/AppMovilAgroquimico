import 'dart:io';

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/presentation/screens/inventory_screen.dart';
import 'package:agroquimicos/presentation/screens/persons_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// UIBUG-066 — `setState() callback argument returned a Future`.
///
/// `setState(() => future = next)` es una **expresión de asignación**: su valor
/// es el propio `Future` asignado, así que la lambda de flecha lo *devuelve*.
/// `State.setState` comprueba en modo depuración que el callback no devuelva un
/// `Future` y lanza un `FlutterError`; no corrompe datos, pero delata que el
/// callback no es realmente `void` y oculta cualquier `await` olvidado.
///
/// La corrección es un cuerpo de bloque, que no devuelve nada.
void main() {
  sqfliteFfiInit();

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<(AppDatabase, AgroRepository)> fixture() async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    final repo = AgroRepository(database);
    await repo.addPerson(name: 'José', role: PersonRole.family);
    await repo.addProduct(name: 'Glifosato');
    return (database, repo);
  }

  Future<void> pumpAndRefresh(WidgetTester tester, Widget screen) async {
    final (database, repo) = (await tester.runAsync(fixture))!;
    addTearDown(database.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        // `PageFrame` no trae `Scaffold`: lo pone `AppShell`. Sin él, los
        // `TextField` de la pantalla no encuentran Material y revientan.
        child: MaterialApp(home: Scaffold(body: screen)),
      ),
    );
    await settle(tester);
    // El botón de recarga es el que ejecuta `refresh()`, donde vivía el
    // callback que devolvía un `Future`.
    await tester.tap(find.byIcon(Icons.refresh));
    await settle(tester);
  }

  testWidgets('recargar Inventario no lanza el aviso de setState', (
    tester,
  ) async {
    await pumpAndRefresh(tester, const InventoryScreen());
    expect(tester.takeException(), isNull);
  });

  testWidgets('recargar Personas no lanza el aviso de setState', (
    tester,
  ) async {
    await pumpAndRefresh(tester, const PersonsScreen());
    expect(tester.takeException(), isNull);
  });

  test('ningún setState de lib/ devuelve un Future', () {
    // Guarda estática sobre todo el proyecto: las pantallas cuyo `refresh()`
    // sólo se alcanza tras navegar (Aplicaciones, Transferencias,
    // Planificación) no son cómodas de montar en un test de widget, pero el
    // defecto es textual y se puede impedir en origen.
    //
    // Se buscan las lambdas de flecha que asignan a un campo cuyo nombre
    // delata un `Future` en las pantallas del proyecto.
    final offenders = <String>[];
    final arrowSetState = RegExp(r'setState\(\(\)\s*=>\s*([^;]*?)\);');

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();

      // Campos declarados como Future en este archivo. El `.+` es voraz a
      // propósito: retrocede hasta el `>` que cierra genéricos anidados como
      // `Future<List<Map<String, Object?>>>`.
      final futureFields = RegExp(r'Future<.+>\s+(\w+)\s*[;=]')
          .allMatches(source)
          .map((match) => match.group(1)!)
          .toSet();
      if (futureFields.isEmpty) continue;

      for (final match in arrowSetState.allMatches(source)) {
        final body = match.group(1)!.trim();
        final assigned = RegExp(r'^(\w+)\s*=').firstMatch(body)?.group(1);
        if (assigned != null && futureFields.contains(assigned)) {
          offenders.add('${entity.path}: setState(() => $body)');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Un setState de flecha que asigna un Future DEVUELVE ese Future. '
          'Use un cuerpo de bloque: setState(() { campo = valor; });',
    );
  });
}
