import 'dart:io';

import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';

Future<Map<String, List<String>>> columnsOf(DatabaseExecutor db) async {
  final tables = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' "
    "AND name NOT LIKE 'sqlite_%' ORDER BY name",
  );
  return {
    for (final row in tables)
      row['name']! as String: [
        for (final column in await db.rawQuery(
          'PRAGMA table_info("${row['name']}")',
        ))
          '${column['name']}',
      ],
  };
}

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

  // v9 (F05): vínculos centrales, necesidad declarada y outbox (MOB #29,
  // #30, #34, #72). Sólo añade tablas vacías; nada existente cambia.

  Future<String> seededAt(int version) async {
    final path = await tempDbPath('v$version');
    final seeded = AppDatabase(factory: databaseFactoryFfi, path: path);
    final household = await seedHousehold(AgroRepository(seeded));
    await household.buy(household.titular, 10000);
    await household.apply(household.titular, household.titularFarm, 2500);
    if (version >= 8) {
      await OwnerBindingStore(seeded).bindExistingPerson(
        personId: household.titular,
        scope: memberA,
        installationRef: installationHere,
      );
    }
    await seeded.close();
    if (version == 8) {
      await downgradeToV8(path);
    } else {
      await downgradeToV7(path);
      if (version == 6) {
        // v6→v7 sólo repara datos de reversiones de transferencia.
        final db = await databaseFactoryFfi.openDatabase(path);
        await db.execute('PRAGMA user_version = 6');
        await db.close();
      }
    }
    return path;
  }

  for (final version in [8, 7, 6]) {
    test(
      'v$version → versión actual conserva todas las filas y las tablas nuevas nacen vacías',
      () async {
        final path = await seededAt(version);
        final legacy = await databaseFactoryFfi.openDatabase(path);
        final before = await dumpTables(legacy);
        final columnsBefore = await columnsOf(legacy);
        await legacy.close();
        for (final table in syncTablesV9) {
          expect(before.containsKey(table), isFalse, reason: table);
        }

        final migrated = openDb(path);
        final db = await migrated.database;
        expect(
          (await db.rawQuery('PRAGMA user_version')).single.values.single,
          AppDatabase.schemaVersion,
        );
        final after = withoutV12(
          await dumpTables(
            db,
            except: {...syncTablesV9, ...reviewAuditTablesV11},
          ),
        );
        if (version == 8) {
          expect(after, before);
        } else {
          // Desde v7 o antes, v8 añade además el titular (vacío) y la marca.
          expect(
            {...after}
              ..remove('owner_bindings')
              ..remove('app_settings'),
            {...before}..remove('app_settings'),
          );
        }
        for (final table in syncTablesV9) {
          expect(await db.query(table), isEmpty, reason: table);
        }
        // Ninguna tabla existente recibe un identificador global: las claves
        // locales siguen siendo los enteros de SQLite (MOB #29). La única
        // ampliación es la de v12 (F04-AV): columnas opcionales de
        // vencimiento, número de lote, nivel mínimo y plazo, al final.
        final columnsAfter = await columnsOf(db);
        for (final entry in columnsBefore.entries) {
          expect(columnsAfter[entry.key], [
            ...entry.value,
            ...?inventoryAlertsColumnsV12[entry.key],
          ], reason: entry.key);
        }
      },
    );
  }

  test(
    'una base nueva nace con el esquema de sincronización y sin intenciones',
    () async {
      final database = openDb(inMemoryDatabasePath);
      final db = await database.database;
      for (final table in syncTablesV9) {
        expect(await db.query(table), isEmpty, reason: table);
      }
      final outboxColumns = (await columnsOf(db))['sync_outbox']!;
      expect(outboxColumns, contains('operation_id'));
      expect(outboxColumns, contains('owner_binding_id'));
    },
  );

  test(
    'una intención exige vínculo de titular (owner_binding_id NOT NULL)',
    () async {
      final database = openDb(inMemoryDatabasePath);
      final db = await database.database;
      await expectLater(
        db.insert('sync_outbox', {
          'operation_id': '11111111-1111-4111-8111-111111111111',
          'projection_type': 'DECLARED_NEED',
          'action': 'PUBLISH',
          'campaign_ref': '0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d',
          'product_ref': '2a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d',
          'base_unit': 'ML',
          'quantity_base': '1000',
          'status': 'PENDING',
          'created_at': '2026-10-15T00:00:00.000Z',
          'updated_at': '2026-10-15T00:00:00.000Z',
        }),
        throwsA(isA<DatabaseException>()),
      );
    },
  );

  // v15 (E1): foto de la etiqueta en `products` y solicitudes de
  // identificación. Aditiva: columnas que nacen NULL y una tabla vacía.
  test('v14 → v15 conserva todas las filas, añade las columnas de foto en NULL y la tabla vacía', () async {
    final path = await seededAt(8);
    // Lleva la base sembrada a la versión actual y luego a v14 exacta.
    final current = openDb(path);
    await current.database;
    await current.close();
    await downgradeToV14(path);

    final legacy = await databaseFactoryFfi.openDatabase(path);
    final before = await dumpTables(legacy);
    final columnsBefore = await columnsOf(legacy);
    await legacy.close();
    expect(before.containsKey('product_identification_requests'), isFalse);
    expect(columnsBefore['products'], isNot(contains('photo_path')));
    expect(before['purchases'], isNotEmpty);
    expect(before['applications'], isNotEmpty);

    final migrated = openDb(path);
    final db = await migrated.database;
    expect(
      (await db.rawQuery('PRAGMA user_version')).single.values.single,
      AppDatabase.schemaVersion,
    );
    expect(await db.query('product_identification_requests'), isEmpty);
    final columnsAfter = await columnsOf(db);
    for (final entry in columnsBefore.entries) {
      expect(columnsAfter[entry.key], [
        ...entry.value,
        if (entry.key == 'products') ...productPhotoColumnsV15,
      ], reason: entry.key);
    }
    final after = await dumpTables(
      db,
      except: {'product_identification_requests'},
    );
    expect(after.keys, before.keys);
    for (final table in before.keys) {
      expect(
        [
          for (final row in after[table]!)
            {
              for (final cell in row.entries)
                if (table != 'products' ||
                    !productPhotoColumnsV15.contains(cell.key))
                  cell.key: cell.value,
            },
        ],
        before[table],
        reason: table,
      );
    }
    for (final row in after['products']!) {
      for (final column in productPhotoColumnsV15) {
        expect(row[column], isNull, reason: column);
      }
    }
  });

  test('la migración a v15 es idempotente sobre una base ya migrada', () async {
    final path = await tempDbPath('v15_twice');
    final first = openDb(path);
    await first.database;
    await first.close();
    // Simula una migración interrumpida tras añadir las columnas: la tabla
    // falta y user_version sigue en 14.
    final raw = await databaseFactoryFfi.openDatabase(path);
    await raw.execute('DROP TABLE product_identification_requests');
    await raw.execute('PRAGMA user_version = 14');
    await raw.close();

    final second = openDb(path);
    final db = await second.database;
    expect(
      (await columnsOf(db))['products']!.where(productPhotoColumnsV15.contains),
      productPhotoColumnsV15.toList(),
    );
    expect(await db.query('product_identification_requests'), isEmpty);
  });

  // v16 (E2): convocatorias de compra conjunta y su cola propia. Aditiva:
  // dos tablas vacías; ninguna otra fila ni columna cambia.
  test('v15 → v16 conserva todas las filas y columnas y añade las dos tablas vacías', () async {
    final path = await seededAt(8);
    final current = openDb(path);
    await current.database;
    await current.close();
    await downgradeToV15(path);

    final legacy = await databaseFactoryFfi.openDatabase(path);
    final before = await dumpTables(legacy);
    final columnsBefore = await columnsOf(legacy);
    await legacy.close();
    for (final table in jointPurchaseTablesV16) {
      expect(before.containsKey(table), isFalse, reason: table);
    }
    expect(before['purchases'], isNotEmpty);
    expect(before['applications'], isNotEmpty);

    final migrated = openDb(path);
    final db = await migrated.database;
    expect(
      (await db.rawQuery('PRAGMA user_version')).single.values.single,
      AppDatabase.schemaVersion,
    );
    for (final table in jointPurchaseTablesV16) {
      expect(await db.query(table), isEmpty, reason: table);
    }
    final columnsAfter = await columnsOf(db);
    for (final entry in columnsBefore.entries) {
      expect(columnsAfter[entry.key], entry.value, reason: entry.key);
    }
    final after = await dumpTables(db, except: jointPurchaseTablesV16);
    expect(after, before);
  });

  test('la migración a v16 es idempotente sobre una base ya migrada', () async {
    final path = await tempDbPath('v16_twice');
    final first = openDb(path);
    await first.database;
    await first.close();
    // Migración interrumpida: una tabla creada, la otra no, user_version 15.
    final raw = await databaseFactoryFfi.openDatabase(path);
    await raw.execute('DROP TABLE joint_purchase_participation_ops');
    await raw.execute('PRAGMA user_version = 15');
    await raw.close();

    final second = openDb(path);
    final db = await second.database;
    for (final table in jointPurchaseTablesV16) {
      expect(await db.query(table), isEmpty, reason: table);
    }
    final indexes = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index' "
      "AND name LIKE 'idx_joint_purchase_%' ORDER BY name",
    );
    expect(indexes.map((row) => row['name']), [
      'idx_joint_purchase_calls_unseen',
      'idx_joint_purchase_ops_status',
    ]);
  });

  test('v16: el motor rechaza estados fuera de la lista cerrada y secuencias repetidas', () async {
    final database = openDb(inMemoryDatabasePath);
    final db = await database.database;
    Map<String, Object?> op(String id) => {
      'operation_id': id,
      'call_id': 'c',
      'tenant_id': 't',
      'member_id': 'm',
      'sequence': 1,
      'kind': 'CONFIRM',
      'send_status': 'PENDING_SEND',
      'created_at': 'x',
      'updated_at': 'x',
    };
    await db.insert('joint_purchase_participation_ops', op('a'));
    await expectLater(
      db.insert('joint_purchase_participation_ops', op('b')),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      db.insert('joint_purchase_participation_ops', {
        ...op('c'),
        'sequence': 2,
        'send_status': 'SENT',
      }),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      db.insert('joint_purchase_calls', {
        'call_id': 'c',
        'tenant_id': 't',
        'member_id': 'm',
        'name': 'n',
        'status': 'DRAFT',
        'deadline_at': 'x',
        'products_json': '[]',
        'fetched_at': 'x',
        'server_time_at_fetch': 'x',
      }),
      throwsA(isA<DatabaseException>()),
    );
    await database.close();
  });
}
