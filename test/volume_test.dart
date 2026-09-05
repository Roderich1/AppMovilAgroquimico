import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  test('fixture de volumen mantiene consultas acotadas e índices V5', () async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(database.close);
    final repo = AgroRepository(database);
    final person = await repo.addPerson(
      name: 'Persona',
      role: PersonRole.family,
    );
    final farm = await repo.addFarm(
      ownerId: person,
      name: 'Chaco',
      areaM2: 10000,
    );
    final campaign = await repo.addCampaign(
      name: 'Campaña',
      start: DateTime.utc(2026),
    );
    final supplier = await repo.addSupplier(name: 'Proveedor');
    final db = await database.database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (var i = 0; i < 100; i++) {
        batch.insert('products', {
          'name': 'Producto ${i.toString().padLeft(3, '0')}',
          'unit': i.isEven ? 'L' : 'KG',
          'base_unit': i.isEven ? 'ML' : 'G',
        });
      }
      for (var i = 0; i < 1000; i++) {
        batch.insert('applications', {
          'farm_id': farm,
          'person_id': person,
          'campaign_id': campaign,
          'applied_at': DateTime.utc(
            2026,
            1,
            1,
          ).add(Duration(hours: i)).toIso8601String(),
          'status': 'CONFIRMED',
          'total_cost_bob_minor': 0,
        });
      }
      for (var i = 0; i < 300; i++) {
        batch.insert('purchases', {
          'supplier_id': supplier,
          'campaign_id': campaign,
          'purchase_date': DateTime.utc(
            2026,
            1,
            1,
          ).add(Duration(days: i)).toIso8601String(),
          'total_bob_minor': 0,
          'status': 'CONFIRMED',
        });
      }
      for (var i = 0; i < 2000; i++) {
        batch.insert('inventory_movements', {
          'product_id': (i % 100) + 1,
          'owner_person_id': person,
          'movement_date': DateTime.utc(2026, 1, 1).toIso8601String(),
          'type': 'ADJUSTMENT',
          'quantity_signed': i.isEven ? 1000 : -1000,
        });
      }
      await batch.commit(noResult: true);
    });
    final watch = Stopwatch()..start();
    final applications = await repo.applications(limit: 200);
    final inventory = await repo.inventorySummary(limit: 5);
    watch.stop();
    expect(applications, hasLength(200));
    expect(inventory, hasLength(5));
    final indexes = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index'",
    )).map((r) => r['name']);
    expect(
      indexes,
      containsAll([
        'idx_products_active_name',
        'idx_applications_filters',
        'idx_application_item_unique',
        'idx_transfer_items_transfer_product',
      ]),
    );
    expect(watch.elapsedMilliseconds, lessThan(5000));
  });
}
