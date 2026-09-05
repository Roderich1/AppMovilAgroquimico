import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('escenario de aceptación completo de campaña', () async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    final repo = AgroRepository(database);
    addTearDown(database.close);

    final admin = await repo.addPerson(
      name: 'Ana administradora',
      role: PersonRole.admin,
    );
    final family = await repo.addPerson(name: 'José', role: PersonRole.family);
    final third = await repo.addPerson(
      name: 'Marco',
      role: PersonRole.thirdParty,
    );
    final farm = await repo.addFarm(
      ownerId: family,
      name: 'JoseLimoncito',
      areaM2: 800000,
    );
    final campaign = await repo.addCampaign(
      name: 'Verano 2026',
      start: DateTime.utc(2026, 1, 1),
    );
    final product = await repo.addProduct(
      name: 'Glifosato',
      activeIngredient: 'Glifosato 48%',
    );
    final paraquat = await repo.addProduct(name: 'Paraquat', unit: 'KG');
    final supplier = await repo.addSupplier(name: 'Agro proveedor');

    await repo.addPlan(
      farmId: farm,
      campaignId: campaign,
      productId: product,
      areaM2: 280000,
      doseBasePerHa: 1500,
    );
    expect(
      (await repo.list('application_plan_items'))
          .single['required_quantity_base'],
      42000,
    );

    await repo.addAccountPayment(
      personId: third,
      campaignId: campaign,
      amountBobMinor: 336000,
      advance: true,
    );
    final purchase = await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: supplier,
        campaignId: campaign,
        purchaseDate: DateTime.utc(2026, 2, 1),
        invoiceNumber: 'F-001',
        invoiceImagePath: 'invoices/f-001.jpg',
        exchangeRateSource: ExchangeRateSource.agreedWithSupplier,
        items: [
          PurchaseItemDraft(
            productId: product,
            quantityBase: 420000,
            currency: CurrencyCode.usd,
            originalUnitPriceMinor: 1600,
            exchangeRateScaled: 7000000,
            allocations: [
              AllocationDraft(personId: family, quantityBase: 390000),
              AllocationDraft(personId: third, quantityBase: 30000),
            ],
          ),
          PurchaseItemDraft(
            productId: paraquat,
            quantityBase: 56000,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 16000,
            allocations: [
              AllocationDraft(personId: family, quantityBase: 56000),
            ],
          ),
        ],
      ),
    );
    expect((await repo.purchases()).single['total_bob_minor'], 5600000);
    expect(
      (await repo.purchases()).single['invoice_image_path'],
      'invoices/f-001.jpg',
    );
    await repo.addProviderPayment(
      purchaseId: purchase,
      payerPersonId: admin,
      amountBobMinor: 5600000,
      method: 'TRANSFER',
    );
    expect(await repo.list('inventory_lots'), hasLength(3));
    final inventory = await repo.inventorySummary();
    expect(
      inventory.firstWhere(
        (row) => row['product_name'] == 'Glifosato',
      )['available_base'],
      420000,
    );
    expect(
      inventory.firstWhere(
        (row) => row['product_name'] == 'Paraquat',
      )['available_base'],
      56000,
    );
    expect(
      (await repo.settlements()).firstWhere(
        (row) => row['id'] == third,
      )['balance'],
      0,
    );
    expect(
      (await repo.settlements()).firstWhere(
        (row) => row['id'] == family,
      )['balance'],
      0,
    );

    await repo.confirmApplication(
      ApplicationDraft(
        personId: family,
        farmId: farm,
        campaignId: campaign,
        appliedAt: DateTime.utc(2026, 3, 1),
        lines: [
          ApplicationLineDraft(
            productId: product,
            quantityBase: 42000,
            treatedAreaM2: 280000,
            doseBasePerHa: 1500,
            theoreticalQuantityBase: 42000,
          ),
        ],
      ),
    );
    expect(
      (await repo.settlements()).firstWhere(
        (row) => row['id'] == family,
      )['balance'],
      470400,
    );
    await repo.addAccountPayment(
      personId: family,
      campaignId: campaign,
      amountBobMinor: 200000,
    );
    expect(
      (await repo.settlements()).firstWhere(
        (row) => row['id'] == family,
      )['balance'],
      270400,
    );
    final remaining = await repo.inventorySummary();
    expect(
      remaining.firstWhere(
        (row) => row['product_name'] == 'Glifosato',
      )['available_base'],
      378000,
    );
    expect(
      remaining.firstWhere(
        (row) => row['product_name'] == 'Paraquat',
      )['available_base'],
      56000,
    );
  });
}
