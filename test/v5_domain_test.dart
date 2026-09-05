import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late AppDatabase db;
  late AgroRepository repo;
  late int source, destination, supplier, campaign, farm;
  setUp(() async {
    db = AppDatabase(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    repo = AgroRepository(db);
    source = await repo.addPerson(name: 'Ana', role: PersonRole.family);
    destination = await repo.addPerson(name: 'José', role: PersonRole.family);
    supplier = await repo.addSupplier(name: 'Proveedor');
    campaign = await repo.addCampaign(
      name: 'Primavera',
      start: DateTime.utc(2026),
    );
    farm = await repo.addFarm(ownerId: source, name: 'Chaco', areaM2: 100000);
  });
  tearDown(() => db.close());
  Future<int> productWithStock(
    String name,
    String unit,
    int quantity,
    int price,
  ) async {
    final product = await repo.addProduct(name: name, unit: unit);
    await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: supplier,
        campaignId: campaign,
        purchaseDate: DateTime.utc(2026, 1, 2),
        items: [
          PurchaseItemDraft(
            productId: product,
            quantityBase: quantity,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: price,
            allocations: [
              AllocationDraft(personId: source, quantityBase: quantity),
            ],
          ),
        ],
      ),
    );
    return product;
  }

  test('transferencia multiproducto conserva físico y suma owners', () async {
    final liters = await productWithStock('Glifosato', 'L', 100000, 10000);
    final kilos = await productWithStock('Paraquat', 'KG', 50000, 2000);
    final before = await repo.inventorySummary();
    await repo.transferProductsFifo(
      fromPersonId: source,
      toPersonId: destination,
      items: [
        TransferItemDraft(productId: liters, quantityBase: 30000),
        TransferItemDraft(productId: kilos, quantityBase: 20000),
      ],
    );
    final after = await repo.inventorySummary();
    for (final product in [liters, kilos]) {
      final b = before.firstWhere(
        (r) => r['product_id'] == product,
      )['available_base'];
      final a = after.firstWhere(
        (r) => r['product_id'] == product,
      )['available_base'];
      expect(a, b);
      final owners =
          (await repo.personStockSummary(source))
              .where((r) => r['product_id'] == product)
              .fold<int>(0, (s, r) => s + (r['available_base'] as int)) +
          (await repo.personStockSummary(destination))
              .where((r) => r['product_id'] == product)
              .fold<int>(0, (s, r) => s + (r['available_base'] as int));
      expect(owners, a);
    }
  });

  test(
    'un item insuficiente revierte toda transferencia multiproducto',
    () async {
      final a = await productWithStock('A', 'L', 10000, 1000);
      final b = await productWithStock('B', 'KG', 10000, 1000);
      await expectLater(
        repo.transferProductsFifo(
          fromPersonId: source,
          toPersonId: destination,
          items: [
            TransferItemDraft(productId: a, quantityBase: 5000),
            TransferItemDraft(productId: b, quantityBase: 11000),
          ],
        ),
        throwsA(isA<BusinessRuleException>()),
      );
      expect(await repo.transfers(), isEmpty);
      expect(
        (await repo.personStockSummary(source)).map((r) => r['available_base']),
        everyElement(10000),
      );
    },
  );

  test(
    'aplicación de cinco productos costea items y total sin mezclar unidades',
    () async {
      final products = <int>[];
      for (var i = 0; i < 5; i++) {
        products.add(
          await productWithStock(
            'P$i',
            i.isEven ? 'L' : 'KG',
            20000,
            1000 + i * 100,
          ),
        );
      }
      final id = await repo.confirmApplication(
        ApplicationDraft(
          personId: source,
          farmId: farm,
          campaignId: campaign,
          appliedAt: DateTime.utc(2026, 2),
          lines: [
            for (final p in products)
              ApplicationLineDraft(
                productId: p,
                quantityBase: 5000,
                treatedAreaM2: 10000,
                doseBasePerHa: 5000,
                theoreticalQuantityBase: 5000,
              ),
          ],
        ),
      );
      final database = await db.database;
      final items = await database.query(
        'application_items',
        where: 'application_id=?',
        whereArgs: [id],
      );
      expect(items, hasLength(5));
      final app = (await database.query(
        'applications',
        where: 'id=?',
        whereArgs: [id],
      )).single;
      expect(
        app['total_cost_bob_minor'],
        items.fold<int>(0, (s, r) => s + (r['cost_bob_minor'] as int)),
      );
      expect(
        (await database.query(
          'application_consumptions',
          where: 'application_item_id IN (SELECT id FROM application_items WHERE application_id=?)',
          whereArgs: [id],
        )),
        hasLength(5),
      );
    },
  );

  test('duplicados se bloquean en aplicación, plan y transferencia', () async {
    final p = await productWithStock('Único', 'L', 20000, 1000);
    await expectLater(
      repo.confirmApplication(
        ApplicationDraft(
          personId: source,
          farmId: farm,
          campaignId: campaign,
          appliedAt: DateTime.now(),
          lines: [
            ApplicationLineDraft(productId: p, quantityBase: 1000),
            ApplicationLineDraft(productId: p, quantityBase: 1000),
          ],
        ),
      ),
      throwsA(isA<BusinessRuleException>()),
    );
    await expectLater(
      repo.addPlanMulti(
        farmId: farm,
        campaignId: campaign,
        areaM2: 10000,
        items: [
          PlanItemDraft(productId: p, doseBasePerHa: 1000),
          PlanItemDraft(productId: p, doseBasePerHa: 1000),
        ],
      ),
      throwsA(isA<BusinessRuleException>()),
    );
    await expectLater(
      repo.transferProductsFifo(
        fromPersonId: source,
        toPersonId: destination,
        items: [
          TransferItemDraft(productId: p, quantityBase: 1000),
          TransferItemDraft(productId: p, quantityBase: 1000),
        ],
      ),
      throwsA(isA<BusinessRuleException>()),
    );
  });

  test('catálogo, stock y deuda permanecen al cambiar campaña', () async {
    final p = await productWithStock('Global', 'L', 20000, 1000);
    await repo.confirmApplication(
      ApplicationDraft(
        personId: source,
        farmId: farm,
        campaignId: campaign,
        appliedAt: DateTime.now(),
        lines: [ApplicationLineDraft(productId: p, quantityBase: 5000)],
      ),
    );
    final debtBefore = (await repo.settlements()).firstWhere(
      (r) => r['id'] == source,
    )['balance'];
    final winter = await repo.addCampaign(
      name: 'Invierno',
      start: DateTime.utc(2026, 6),
    );
    await repo.activateCampaign(winter, closeCurrent: true);
    expect((await repo.products()).any((r) => r['id'] == p), isTrue);
    expect(
      (await repo.personStockSummary(source))
          .firstWhere((r) => r['product_id'] == p)['available_base'],
      15000,
    );
    await repo.addPlanMulti(
      farmId: farm,
      campaignId: winter,
      areaM2: 10000,
      items: [PlanItemDraft(productId: p, doseBasePerHa: 1000)],
    );
    expect(
      (await repo.settlements()).firstWhere(
        (r) => r['id'] == source,
      )['balance'],
      debtBefore,
    );
  });

  test(
    'aplicación desde plan conserva líneas y completa/reabre el plan',
    () async {
      final first = await productWithStock('Plan A', 'L', 20000, 1000);
      final second = await productWithStock('Plan B', 'KG', 20000, 2000);
      final plan = await repo.addPlanMulti(
        farmId: farm,
        campaignId: campaign,
        areaM2: 10000,
        items: [
          PlanItemDraft(productId: first, doseBasePerHa: 1000),
          PlanItemDraft(productId: second, doseBasePerHa: 2000),
        ],
      );
      final prefill = await repo.planForApplication(plan);
      expect(prefill, hasLength(2));
      final application = await repo.confirmApplication(
        ApplicationDraft(
          personId: source,
          farmId: farm,
          campaignId: campaign,
          planId: plan,
          treatedAreaM2: 10000,
          appliedAt: DateTime.utc(2026, 3),
          lines: [
            for (final row in prefill)
              ApplicationLineDraft(
                productId: row['product_id'] as int,
                quantityBase: row['required_quantity_base'] as int,
                treatedAreaM2: row['area_m2'] as int,
                doseBasePerHa: row['dose_base_per_ha'] as int,
                theoreticalQuantityBase: row['required_quantity_base'] as int,
              ),
          ],
        ),
      );
      final database = await db.database;
      expect(
        (await database.query(
          'application_plans',
          where: 'id=?',
          whereArgs: [plan],
        )).single['status'],
        'COMPLETED',
      );
      await repo.reverseApplication(application);
      expect(
        (await database.query(
          'application_plans',
          where: 'id=?',
          whereArgs: [plan],
        )).single['status'],
        'PLANNED',
      );
    },
  );
}
