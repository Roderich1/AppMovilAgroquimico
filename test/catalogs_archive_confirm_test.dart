// A-05: «Archivar» en Catálogos actuaba con un solo toque, sin confirmación
// ni aviso, y no se deshace desde la aplicación. Ahora pide confirmación
// informada; cancelar no archiva. Sigue sin ser un borrado: `archiveCatalog`
// no cambia y el historial se conserva.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/presentation/screens/catalogs_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  Future<void> settle(WidgetTester tester) async {
    for (var round = 0; round < 6; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
  }

  Future<AgroRepository> openProducts(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = (await tester.runAsync(() async {
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      addTearDown(database.close);
      final repo = AgroRepository(database);
      await repo.addProduct(name: 'Herbicida de prueba', unit: 'L');
      return repo;
    }))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: Scaffold(body: CatalogsScreen())),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Productos'));
    await settle(tester);
    expect(find.text('Herbicida de prueba'), findsOneWidget);
    return repo;
  }

  Future<void> tapArchive(WidgetTester tester) async {
    final row = find.ancestor(
      of: find.text('Herbicida de prueba'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(of: row, matching: find.byType(PopupMenuButton<String>)),
    );
    await settle(tester);
    await tester.tap(find.text('Archivar'));
    await settle(tester);
    expect(find.text('¿Archivar Herbicida de prueba?'), findsOneWidget);
    expect(
      find.text(
        'Dejará de aparecer en las listas y formularios; su historial se '
        'conserva.',
      ),
      findsOneWidget,
    );
  }

  testWidgets('Archivar pide confirmación y cancelar no archiva', (
    tester,
  ) async {
    final repo = await openProducts(tester);
    await tapArchive(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
    await settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Herbicida de prueba'), findsOneWidget);
    expect(find.textContaining('archivado'), findsNothing);
    final products = (await tester.runAsync(repo.products))!;
    expect(products.map((p) => p['name']), contains('Herbicida de prueba'));
  });

  testWidgets('al confirmar se archiva, se avisa y deja de listarse', (
    tester,
  ) async {
    final repo = await openProducts(tester);
    await tapArchive(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Archivar'));
    await settle(tester);
    expect(find.text('Herbicida de prueba archivado.'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Herbicida de prueba'), findsNothing);
    final products = (await tester.runAsync(repo.products))!;
    expect(
      products.map((p) => p['name']),
      isNot(contains('Herbicida de prueba')),
    );
  });
}
