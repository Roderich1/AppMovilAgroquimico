import 'dart:io';

import 'package:agroquimicos/data/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
    'migración V1 a V2 conserva filas y agrega planificado vs real',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'agro_migration_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = p.join(directory.path, 'v1.db');
      final legacy = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute('''CREATE TABLE application_items (
            id INTEGER PRIMARY KEY, application_id INTEGER NOT NULL,
            product_id INTEGER NOT NULL, quantity_base INTEGER NOT NULL,
            cost_bob_minor INTEGER NOT NULL DEFAULT 0)''');
            await db.insert('application_items', {
              'id': 7,
              'application_id': 1,
              'product_id': 2,
              'quantity_base': 42000,
              'cost_bob_minor': 470400,
            });
          },
        ),
      );
      await legacy.close();

      final database = AppDatabase(factory: databaseFactoryFfi, path: path);
      final upgraded = await database.database;
      addTearDown(database.close);
      final columns = await upgraded.rawQuery(
        'PRAGMA table_info(application_items)',
      );
      expect(
        columns.map((row) => row['name']),
        containsAll([
          'treated_area_m2',
          'dose_base_per_ha',
          'theoretical_quantity_base',
        ]),
      );
      expect(
        (await upgraded.query('application_items')).single['quantity_base'],
        42000,
      );
    },
  );

  test(
    'migración V3 a V4 agrega items de transferencia sin perder historial',
    () async {
      final directory = await Directory.systemTemp.createTemp('agro_v4_');
      addTearDown(() => directory.delete(recursive: true));
      final path = p.join(directory.path, 'v3.db');
      final legacy = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, _) async {
            await db.execute('''CREATE TABLE transfers (
            id INTEGER PRIMARY KEY, product_id INTEGER NOT NULL,
            from_person_id INTEGER NOT NULL, to_person_id INTEGER NOT NULL,
            transfer_date TEXT NOT NULL, quantity_base INTEGER NOT NULL,
            total_cost_bob_minor INTEGER NOT NULL, status TEXT NOT NULL,
            notes TEXT, reversed_at TEXT)''');
            await db.execute(
              '''CREATE TABLE transfer_lot_items (
            id INTEGER PRIMARY KEY, transfer_id INTEGER NOT NULL,
            source_lot_id INTEGER NOT NULL, destination_lot_id INTEGER NOT NULL,
            quantity_base INTEGER NOT NULL, cost_bob_minor INTEGER NOT NULL)''',
            );
            await db.insert('transfers', {
              'id': 9,
              'product_id': 2,
              'from_person_id': 1,
              'to_person_id': 3,
              'transfer_date': '2026-01-01',
              'quantity_base': 5000,
              'total_cost_bob_minor': 1000,
              'status': 'CONFIRMED',
            });
          },
        ),
      );
      await legacy.close();
      final database = AppDatabase(factory: databaseFactoryFfi, path: path);
      final upgraded = await database.database;
      addTearDown(database.close);
      expect((await upgraded.query('transfers')).single['id'], 9);
      expect(
        (await upgraded.rawQuery('PRAGMA table_info(transfer_lot_items)'))
            .map((row) => row['name']),
        contains('transfer_item_id'),
      );
      expect(
        await upgraded.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='transfer_items'",
        ),
        isNotEmpty,
      );
    },
  );
}
