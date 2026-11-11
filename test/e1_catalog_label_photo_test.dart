// E1 §5.1 en Catálogos → Productos: «Foto de la etiqueta» sólo en la
// sección Productos; la hoja ofrece tomar o elegir sin foto, y reemplazar o
// quitar con foto; quitar pide confirmación y deja las columnas en NULL.
// Datos sintéticos; la cámara no se ejercita.
import 'dart:io';

import 'package:agroquimicos/presentation/widgets/identification_texts.dart';
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/presentation/screens/catalogs_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/e1_identification_fixtures.dart';

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

  testWidgets('foto de la etiqueta: ver, quitar con confirmación', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late Directory root;
    late AppDatabase database;
    final (repo, product) = (await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('agro_e1_cat_');
      database = AppDatabase(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      final documents = Directory(p.join(root.path, 'documentos'));
      await documents.create(recursive: true);
      final repo = AgroRepository(
        database,
        productPhotoDocuments: () async => documents,
      );
      final product = await repo.addProduct(name: 'Herbicida de prueba');
      return (repo, product);
    }))!;
    addTearDown(() async {
      await tester.runAsync(() async {
        await database.close();
        try {
          await root.delete(recursive: true);
        } on FileSystemException {
          // Temporal.
        }
      });
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          repositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: Scaffold(body: CatalogsScreen())),
      ),
    );
    await settle(tester);

    Future<void> openMenu() async {
      final row = find.ancestor(
        of: find.text('Herbicida de prueba'),
        matching: find.byType(ListTile),
      );
      await tester.tap(
        find.descendant(
          of: row,
          matching: find.byType(PopupMenuButton<String>),
        ),
      );
      await settle(tester);
    }

    // Sección Productos: sin foto todavía.
    await tester.tap(find.text('Productos'));
    await settle(tester);
    await openMenu();
    await tester.tap(find.text('Foto de la etiqueta'));
    await settle(tester);
    expect(find.textContaining('Sin foto.'), findsOneWidget);
    // Limitación B (2026-11-11): la hoja dice que las fotos de etiqueta no
    // entran en los respaldos.
    expect(find.text(labelPhotosNotInBackups), findsOneWidget);
    expect(find.text('Tomar foto'), findsOneWidget);
    expect(find.text('Elegir de la galería'), findsOneWidget);
    expect(find.text('Quitar'), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await settle(tester);

    // Con foto guardada (como la deja el selector): reemplazar o quitar.
    await tester.runAsync(() async {
      final source = File(p.join(root.path, 'galeria', 'a.jpg'));
      await source.parent.create(recursive: true);
      await source.writeAsBytes(labelJpeg());
      await repo.setProductPhoto(product, source.path);
    });
    await openMenu();
    await tester.tap(find.text('Foto de la etiqueta'));
    await settle(tester);
    expect(find.text('Reemplazar'), findsOneWidget);
    expect(find.text('Quitar'), findsOneWidget);
    await tester.tap(find.text('Quitar'));
    await settle(tester);
    expect(find.text('Quitar la foto'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Quitar').last);
    await settle(tester);
    final row = (await tester.runAsync(
      () async => (await (await database.database).query(
        'products',
        columns: ['photo_path', 'photo_sha256'],
      )).single,
    ))!;
    expect(row, {'photo_path': null, 'photo_sha256': null});
  });
}
