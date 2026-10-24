// Migración v8: marca de origen de la base y tabla de vínculos de titular.
// La marca se decide por el camino de creación (onCreate) o de migración,
// nunca por si la base tiene filas.
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';

void main() {
  sqfliteFfiInit();

  Future<Set<String>> triggers(Database db) async => {
    for (final row in await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='trigger'",
    ))
      row['name']! as String,
  };

  // Triggers de la sincronización F05 (v9): una base nueva y una migrada
  // los tienen igual que los de owner_bindings.
  const syncTriggers = {
    'trg_sync_outbox_no_delete',
    'trg_sync_outbox_identity',
    'trg_sync_outbox_sent_immutable',
    'trg_sync_outbox_acked_final',
    'trg_declared_needs_no_delete',
    'trg_declared_need_versions_no_delete',
    'trg_declared_need_versions_no_update',
    // v11 (RF-13 y RF-03): auditoría de reversiones y borradores tardíos.
    'trg_reversal_audit_no_update',
    'trg_reversal_audit_no_delete',
    'trg_reversal_audit_effects_no_update',
    'trg_reversal_audit_effects_no_delete',
    'trg_late_drafts_no_delete',
    'trg_late_drafts_resolved_immutable',
  };

  test('una base nueva nace en la versión vigente marcada NEW_UNDER_POLICY y sin titular', () async {
    final database = openDb(inMemoryDatabasePath);
    final db = await database.database;
    expect(
      (await db.rawQuery('PRAGMA user_version')).single.values.single,
      // v9 (F05) se añadió después; la política sigue naciendo en v8.
      AppDatabase.schemaVersion,
    );
    expect(await settings(db), {
      AppDatabase.installOriginKey: AppDatabase.installOriginNew,
    });
    expect(await db.query('owner_bindings'), isEmpty);
    expect(await triggers(db), {
      'trg_owner_bindings_no_delete',
      'trg_owner_bindings_close_only',
      ...syncTriggers,
    });
  });

  test(
    'una base v7 con datos migra a LEGACY_PRE_POLICY sin cambiar ninguna fila',
    () async {
      final path = await tempDbPath('v7_con_datos');
      final seeded = AppDatabase(factory: databaseFactoryFfi, path: path);
      final household = await seedHousehold(AgroRepository(seeded));
      await household.buy(household.titular, 10000);
      await household.buy(household.thirdParty, 4000);
      await household.apply(household.titular, household.titularFarm, 2500);
      await household.repo.transferProductFifo(
        fromPersonId: household.titular,
        toPersonId: household.relative,
        productId: household.product,
        quantityBase: 1500,
      );
      await seeded.close();
      await downgradeToV7(path);

      final legacy = await databaseFactoryFfi.openDatabase(path);
      final before = await dumpTables(legacy);
      final settingsBefore = await settings(legacy);
      await legacy.close();
      expect(before.containsKey('owner_bindings'), isFalse);

      final migrated = openDb(path);
      final db = await migrated.database;
      expect(
        (await db.rawQuery('PRAGMA user_version')).single.values.single,
        // v9 (F05) se añadió después; la política sigue naciendo en v8.
        AppDatabase.schemaVersion,
      );
      // Todas las tablas previas quedan idénticas, fila por fila.
      expect(
        await dumpTables(
          db,
          except: {
            'owner_bindings',
            'app_settings',
            ...syncTablesV9,
            ...reviewAuditTablesV11,
          },
        ),
        {...before}..remove('app_settings'),
      );
      // Las tablas de la sincronización (v9) nacen vacías.
      for (final table in syncTablesV9) {
        expect(await db.query(table), isEmpty, reason: table);
      }
      // app_settings sólo gana la marca de origen.
      expect(await settings(db), {
        ...settingsBefore,
        AppDatabase.installOriginKey: AppDatabase.installOriginLegacy,
      });
      // Nada se atribuye a ninguna cuenta.
      expect(await db.query('owner_bindings'), isEmpty);
      expect(await triggers(db), {
        'trg_owner_bindings_no_delete',
        'trg_owner_bindings_close_only',
        ...syncTriggers,
      });
    },
  );

  test(
    'una base v7 VACÍA también es histórica: no se decide por filas',
    () async {
      final path = await tempDbPath('v7_vacia');
      await AppDatabase(
        factory: databaseFactoryFfi,
        path: path,
      ).database.then((db) => db.close());
      await downgradeToV7(path);

      final db = await openDb(path).database;
      expect(
        (await settings(db))[AppDatabase.installOriginKey],
        AppDatabase.installOriginLegacy,
      );
    },
  );

  test('una base nueva CON datos sigue siendo NEW_UNDER_POLICY', () async {
    final path = await tempDbPath('nueva_con_datos');
    final database = openDb(path);
    final household = await seedHousehold(AgroRepository(database));
    await household.buy(household.titular, 1000);
    await database.close();

    final db = await openDb(path).database;
    expect(
      (await settings(db))[AppDatabase.installOriginKey],
      AppDatabase.installOriginNew,
    );
  });

  test(
    'reabrir una base ya en v8 no cambia la marca ni ninguna fila',
    () async {
      final path = await tempDbPath('reapertura');
      final first = openDb(path);
      final household = await seedHousehold(AgroRepository(first));
      await household.buy(household.titular, 1000);
      final before = await dumpTables(await first.database);
      await first.close();

      final again = await openDb(path).database;
      expect(await dumpTables(again), before);
    },
  );

  test('una base migrada y una nueva tienen los mismos disparadores', () async {
    final path = await tempDbPath('v7_disparadores');
    await AppDatabase(
      factory: databaseFactoryFfi,
      path: path,
    ).database.then((db) => db.close());
    await downgradeToV7(path);
    final migrated = await openDb(path).database;
    final fresh = await openDb(inMemoryDatabasePath).database;
    expect(await triggers(migrated), await triggers(fresh));
  });
}
