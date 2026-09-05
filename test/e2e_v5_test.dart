import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('E2E V5: catálogo, compra, transferencia, plan y aplicación', () async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(database.close);
    final repo = AgroRepository(database);

    final ana = await repo.addPerson(name: 'Ana', role: PersonRole.family);
    final jose = await repo.addPerson(name: 'José', role: PersonRole.family);
    final supplier = await repo.addSupplier(name: 'Agro proveedor');
    final farm = await repo.addFarm(
      ownerId: jose,
      name: 'JoseLimoncito',
      areaM2: 50000,
    );
    final campaign = await repo.addCampaign(
      name: 'Verano 2026',
      start: DateTime.utc(2026, 1, 1),
    );

    final products = <int>[];
    for (var i = 0; i < 20; i++) {
      products.add(
        await repo.addProduct(
          name: 'Producto ${i + 1}',
          unit: i.isEven ? 'L' : 'KG',
        ),
      );
    }
    expect(await repo.products(), hasLength(20));

    await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: supplier,
        campaignId: campaign,
        purchaseDate: DateTime.utc(2026, 1, 5),
        items: [
          for (var i = 0; i < 12; i++)
            PurchaseItemDraft(
              productId: products[i],
              quantityBase: i == 2 ? 120000 : 100000,
              currency: CurrencyCode.bob,
              originalUnitPriceMinor: 2500 + i * 100,
              allocations: [
                AllocationDraft(personId: ana, quantityBase: 100000),
                if (i == 2)
                  AllocationDraft(personId: jose, quantityBase: 20000),
              ],
            ),
        ],
      ),
    );
    expect(
      (await repo.inventorySummary()).where(
        (row) => (row['available_base'] as int) > 0,
      ),
      hasLength(12),
    );

    await repo.transferProductsFifo(
      fromPersonId: ana,
      toPersonId: jose,
      items: [
        TransferItemDraft(productId: products[0], quantityBase: 10000),
        TransferItemDraft(productId: products[1], quantityBase: 15000),
      ],
      notes: 'Préstamo interno',
    );
    final joseStock = await repo.personStockSummary(jose);
    expect(joseStock, hasLength(3));
    expect(
      joseStock.fold<int>(
        0,
        (sum, row) => sum + (row['available_base'] as int),
      ),
      45000,
    );

    final plan = await repo.addPlanMulti(
      farmId: farm,
      campaignId: campaign,
      areaM2: 10000,
      items: [
        for (var i = 0; i < 3; i++)
          PlanItemDraft(productId: products[i], doseBasePerHa: 5000),
      ],
    );
    final planned = await repo.planForApplication(plan);
    expect(planned, hasLength(3));

    final balanceBefore =
        (await repo.settlements()).firstWhere(
              (row) => row['id'] == jose,
            )['balance']
            as int;
    final application = await repo.confirmApplication(
      ApplicationDraft(
        personId: jose,
        farmId: farm,
        campaignId: campaign,
        planId: plan,
        treatedAreaM2: 10000,
        appliedAt: DateTime.utc(2026, 1, 10),
        lines: [
          for (final row in planned)
            ApplicationLineDraft(
              productId: row['product_id'] as int,
              quantityBase: 5000,
              treatedAreaM2: 10000,
              doseBasePerHa: 5000,
              theoreticalQuantityBase: 5000,
            ),
        ],
      ),
    );

    final db = await database.database;
    expect(
      (await db.query(
        'application_items',
        where: 'application_id=?',
        whereArgs: [application],
      )),
      hasLength(3),
    );
    expect(
      (await db.query(
        'application_plans',
        where: 'id=?',
        whereArgs: [plan],
      )).single['status'],
      'APPLIED',
    );
    final balanceAfter =
        (await repo.settlements()).firstWhere(
              (row) => row['id'] == jose,
            )['balance']
            as int;
    expect(balanceAfter, greaterThan(balanceBefore));
    final physical = await repo.inventorySummary();
    for (var i = 0; i < 12; i++) {
      final quantity = physical.firstWhere(
        (row) => row['product_id'] == products[i],
      )['available_base'];
      expect(quantity, i < 2 ? 95000 : (i == 2 ? 115000 : 100000));
    }

    final nextCampaign = await repo.addCampaign(
      name: 'Invierno 2026',
      start: DateTime.utc(2026, 6, 1),
    );
    await repo.activateCampaign(nextCampaign, closeCurrent: true);
    expect(await repo.products(), hasLength(20));
    expect(
      (await repo.inventorySummary()).where(
        (row) => (row['available_base'] as int) > 0,
      ),
      hasLength(12),
    );
    expect(await repo.settlements(), hasLength(2));

    await repo.reverseApplication(application, reason: 'Control E2E');
    // El plan permanece APPLIED: revertir la aplicación no lo devuelve a la
    // cola de pendientes (UIBUG-045, MODELO A).
    expect(
      (await db.query(
        'application_plans',
        where: 'id=?',
        whereArgs: [plan],
      )).single['status'],
      'APPLIED',
    );
    for (var i = 0; i < 12; i++) {
      final quantity = (await repo.inventorySummary()).firstWhere(
        (row) => row['product_id'] == products[i],
      )['available_base'];
      expect(quantity, i == 2 ? 120000 : 100000);
    }
  });
}
