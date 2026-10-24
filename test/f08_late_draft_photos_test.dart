// Fotografías de compras tardías pendientes (RF-03, columna
// `late_operation_drafts.invoice_image_path` del esquema v11 de A): viajan en
// el respaldo y se reapuntan al restaurar, igual que las de las compras. Aquí
// la tabla se crea a mano con sólo esa columna, porque v11 no está en esta
// rama; la consulta usa `rowid` y no depende de las demás columnas.
import 'dart:io';

import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory workspace;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('agro_f08_drafts_');
  });
  tearDown(() async {
    try {
      await workspace.delete(recursive: true);
    } on FileSystemException {
      // Temporal.
    }
  });

  test('la foto de un borrador tardío viaja en el respaldo y se reapunta al restaurar', () async {
    final sourceInvoices = await Directory(
      p.join(workspace.path, 'origen_facturas'),
    ).create();
    final source = AppDatabase(
      factory: databaseFactoryFfi,
      path: p.join(workspace.path, 'origen.db'),
    );
    addTearDown(source.close);
    await AgroRepository(source).addProduct(name: 'Producto');
    final photo = File(p.join(sourceInvoices.path, 'tardia_1.jpg'));
    await photo.writeAsBytes(List<int>.generate(500, (i) => i % 256));
    final db = await source.database;
    await db.execute(
      'CREATE TABLE late_operation_drafts (invoice_image_path TEXT)',
    );
    await db.insert('late_operation_drafts', {
      'invoice_image_path': photo.path,
    });
    final exported = await BackupService(
      source,
      invoicesDir: () async => sourceInvoices,
      exportDirectory: () async => workspace,
    ).export();
    expect(exported.attachmentCount, 1);
    expect(exported.warnings, isEmpty);

    // Otro teléfono con la misma tabla (v11) y otra carpeta de facturas.
    final targetInvoices = Directory(
      p.join(workspace.path, 'destino_facturas'),
    );
    final target = AppDatabase(
      factory: databaseFactoryFfi,
      path: p.join(workspace.path, 'destino.db'),
    );
    addTearDown(target.close);
    await target.database;
    final result = await BackupService(
      target,
      invoicesDir: () async => targetInvoices,
    ).restore(exported.path);
    expect(result.restoredAttachments, 1);
    final rows = await (await target.database).query('late_operation_drafts');
    expect(
      rows.single['invoice_image_path'],
      p.join(targetInvoices.path, 'tardia_1.jpg'),
    );
    expect(
      await File(p.join(targetInvoices.path, 'tardia_1.jpg')).readAsBytes(),
      await photo.readAsBytes(),
    );
  });

  test(
    'sin la tabla (bases anteriores a v11) la exportación no cambia',
    () async {
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        path: p.join(workspace.path, 'v10.db'),
      );
      addTearDown(database.close);
      await AgroRepository(database).addProduct(name: 'Producto');
      final exported = await BackupService(
        database,
        exportDirectory: () async => workspace,
      ).export();
      expect(exported.attachmentCount, 0);
    },
  );
}
