// Soporte de pruebas de la política de activación, el titular y la modalidad.
import 'dart:io';

import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/installation_access.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const memberA = OwnerScope(
  memberId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  tenantId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
);
const memberB = OwnerScope(
  memberId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  tenantId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
);
const memberAOtherTenant = OwnerScope(
  memberId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  tenantId: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
);
final installationHere = installationReference(
  '11111111-1111-4111-8111-111111111111',
);
final installationElsewhere = installationReference(
  '22222222-2222-4222-8222-222222222222',
);

/// Ruta de archivo en un directorio temporal que se borra al final.
Future<String> tempDbPath(String name) async {
  final directory = await Directory.systemTemp.createTemp('agro_f04_');
  addTearDown(() => directory.delete(recursive: true));
  return p.join(directory.path, '$name.db');
}

AppDatabase openDb(String path) {
  final database = AppDatabase(factory: databaseFactoryFfi, path: path);
  addTearDown(database.close);
  return database;
}

/// Volcado completo de todas las tablas (filas enteras, no conteos).
Future<Map<String, List<Map<String, Object?>>>> dumpTables(
  DatabaseExecutor db, {
  Set<String> except = const {},
}) async {
  final tables = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' "
    "AND name NOT LIKE 'sqlite_%' ORDER BY name",
  );
  return {
    for (final row in tables)
      if (!except.contains(row['name']))
        row['name']! as String: await db.rawQuery(
          'SELECT * FROM "${row['name']}" ORDER BY rowid',
        ),
  };
}

Future<Map<String, String>> settings(DatabaseExecutor db) async => {
  for (final row in await db.query('app_settings'))
    row['key']! as String: row['value']! as String,
};

/// Saldo por (persona, producto) calculado desde los movimientos.
Future<Map<(int, int), int>> stockByPersonProduct(DatabaseExecutor db) async =>
    {
      for (final row in await db.rawQuery(
        '''SELECT owner_person_id o, product_id p, SUM(quantity_signed) s
    FROM inventory_movements GROUP BY owner_person_id, product_id''',
      ))
        (row['o']! as int, row['p']! as int): row['s']! as int,
    };

class Household {
  Household(this.repo, this.titular, this.relative, this.thirdParty);
  final AgroRepository repo;
  final int titular;
  final int relative;
  final int thirdParty;
  late int supplier;
  late int campaign;
  late int product;
  late int titularFarm;
  late int relativeFarm;

  Future<int> buy(int person, int quantity, {DateTime? date}) =>
      repo.confirmPurchase(
        PurchaseDraft(
          supplierId: supplier,
          campaignId: campaign,
          purchaseDate: date ?? DateTime.utc(2026, 1, 2),
          items: [
            PurchaseItemDraft(
              productId: product,
              quantityBase: quantity,
              currency: CurrencyCode.bob,
              originalUnitPriceMinor: 10000,
              allocations: [
                AllocationDraft(personId: person, quantityBase: quantity),
              ],
            ),
          ],
        ),
      );

  Future<int> apply(int person, int farm, int quantity) =>
      repo.confirmApplication(
        ApplicationDraft(
          personId: person,
          farmId: farm,
          campaignId: campaign,
          appliedAt: DateTime.utc(2026, 2, 1),
          lines: [
            ApplicationLineDraft(productId: product, quantityBase: quantity),
          ],
        ),
      );
}

/// Hogar con titular (familiar), otro familiar y un tercero; un proveedor,
/// una campaña, un producto y un chaco por familiar.
Future<Household> seedHousehold(AgroRepository repo) async {
  final household = Household(
    repo,
    await repo.addPerson(name: 'Titular', role: PersonRole.family),
    await repo.addPerson(name: 'Hermana', role: PersonRole.family),
    await repo.addPerson(name: 'Vecino', role: PersonRole.thirdParty),
  );
  household
    ..supplier = await repo.addSupplier(name: 'Proveedor')
    ..campaign = await repo.addCampaign(
      name: 'Campaña 1',
      start: DateTime.utc(2026, 1, 1),
    )
    ..product = await repo.addProduct(name: 'Glifosato')
    ..titularFarm = await repo.addFarm(
      ownerId: household.titular,
      name: 'Chaco titular',
      areaM2: 10000,
    )
    ..relativeFarm = await repo.addFarm(
      ownerId: household.relative,
      name: 'Chaco hermana',
      areaM2: 5000,
    );
  return household;
}

/// Lleva una base creada con el esquema actual a un v7 exacto: v8 sólo añade
/// `owner_bindings`, sus disparadores e índice y la marca `install_origin`.
/// Tablas que añadió v9 (F05), en orden de borrado (dependientes primero).
const syncTablesV9 = [
  'declared_need_versions',
  'declared_needs',
  'sync_outbox',
  'product_bindings',
  'campaign_bindings',
];

/// Tablas que añadió v11 (RF-13 y RF-03), en orden de borrado.
const reviewAuditTablesV11 = [
  'reversal_audit_effects',
  'reversal_audit',
  'late_operation_drafts',
];

/// Quita todo lo que añadió v11 (RF-13 y RF-03): tablas, índices y triggers.
Future<void> dropReviewAuditSchemaV11(DatabaseExecutor db) async {
  final triggers = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='trigger' AND "
    "(name LIKE 'trg_reversal_audit%' OR name LIKE 'trg_late_drafts%')",
  );
  for (final row in triggers) {
    await db.execute('DROP TRIGGER IF EXISTS "${row['name']}"');
  }
  for (final table in reviewAuditTablesV11) {
    await db.execute('DROP TABLE IF EXISTS $table');
  }
}

/// Deja una base creada con la versión actual exactamente como una v10.
Future<void> downgradeToV10(String path) async {
  final db = await databaseFactoryFfi.openDatabase(path);
  await dropReviewAuditSchemaV11(db);
  await db.execute('PRAGMA user_version = 10');
  await db.close();
}

/// Quita todo lo que añadió v9: tablas, índices y triggers.
Future<void> dropSyncSchemaV9(DatabaseExecutor db) async {
  await dropReviewAuditSchemaV11(db);
  final triggers = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='trigger' AND "
    "(name LIKE 'trg_sync_outbox_%' OR name LIKE 'trg_declared_need%')",
  );
  for (final row in triggers) {
    await db.execute('DROP TRIGGER IF EXISTS "${row['name']}"');
  }
  for (final table in syncTablesV9) {
    await db.execute('DROP TABLE IF EXISTS $table');
  }
}

/// Deja una base creada con la versión actual exactamente como una v8.
Future<void> downgradeToV8(String path) async {
  final db = await databaseFactoryFfi.openDatabase(path);
  await dropSyncSchemaV9(db);
  await db.execute('PRAGMA user_version = 8');
  await db.close();
}

Future<void> downgradeToV7(String path) async {
  final db = await databaseFactoryFfi.openDatabase(path);
  await dropSyncSchemaV9(db);
  await db.execute('DROP TRIGGER IF EXISTS trg_owner_bindings_no_delete');
  await db.execute('DROP TRIGGER IF EXISTS trg_owner_bindings_close_only');
  await db.execute('DROP TABLE IF EXISTS owner_bindings');
  await db.delete(
    'app_settings',
    where: 'key=?',
    whereArgs: [AppDatabase.installOriginKey],
  );
  await db.execute('PRAGMA user_version = 7');
  await db.close();
}
