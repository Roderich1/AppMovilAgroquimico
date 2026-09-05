import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late AppDatabase database;
  late AgroRepository repo;
  late int adminId,
      familyId,
      thirdId,
      supplierId,
      campaignId,
      productId,
      farmId;

  setUp(() async {
    database = AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    repo = AgroRepository(database);
    adminId = await repo.addPerson(
      name: 'Administrador',
      role: PersonRole.admin,
    );
    familyId = await repo.addPerson(name: 'Carlos', role: PersonRole.family);
    thirdId = await repo.addPerson(
      name: 'Tercero',
      role: PersonRole.thirdParty,
    );
    supplierId = await repo.addSupplier(name: 'Proveedor');
    campaignId = await repo.addCampaign(
      name: 'Verano',
      start: DateTime.utc(2026, 1, 1),
    );
    productId = await repo.addProduct(name: 'Glifosato');
    farmId = await repo.addFarm(
      ownerId: familyId,
      name: 'Chaco Carlos',
      areaM2: 280000,
    );
  });

  tearDown(() => database.close());

  PurchaseDraft purchase({
    required int quantityBase,
    required int priceMinor,
    required int ownerId,
    CurrencyCode currency = CurrencyCode.bob,
    int? fx,
    DateTime? date,
  }) => PurchaseDraft(
    supplierId: supplierId,
    campaignId: campaignId,
    purchaseDate: date ?? DateTime.utc(2026, 2, 1),
    exchangeRateSource: fx == null
        ? null
        : ExchangeRateSource.agreedWithSupplier,
    items: [
      PurchaseItemDraft(
        productId: productId,
        quantityBase: quantityBase,
        currency: currency,
        originalUnitPriceMinor: priceMinor,
        exchangeRateScaled: fx,
        allocations: [
          AllocationDraft(personId: ownerId, quantityBase: quantityBase),
        ],
      ),
    ],
  );

  test('asignación familiar no crea deuda; uso y pago parcial sí', () async {
    final purchaseId = await repo.confirmPurchase(
      purchase(
        quantityBase: 50000,
        priceMinor: 1600,
        ownerId: familyId,
        currency: CurrencyCode.usd,
        fx: 7000000,
      ),
    );
    expect(await repo.statement(familyId), isEmpty);
    await repo.addProviderPayment(
      purchaseId: purchaseId,
      payerPersonId: adminId,
      amountBobMinor: 560000,
      method: 'TRANSFER',
    );
    expect((await repo.purchases()).single['paid_bob_minor'], 560000);

    await repo.confirmApplication(
      ApplicationDraft(
        personId: familyId,
        farmId: farmId,
        campaignId: campaignId,
        appliedAt: DateTime.utc(2026, 3, 1),
        lines: [
          ApplicationLineDraft(productId: productId, quantityBase: 28000),
        ],
      ),
    );
    var settlement = (await repo.settlements()).firstWhere(
      (row) => row['id'] == familyId,
    );
    expect(settlement['balance'], 313600);

    await repo.addAccountPayment(
      personId: familyId,
      campaignId: campaignId,
      amountBobMinor: 100000,
    );
    settlement = (await repo.settlements()).firstWhere(
      (row) => row['id'] == familyId,
    );
    expect(settlement['balance'], 213600);
  });

  test('tercero genera cargo por allocation y adelanto lo compensa', () async {
    await repo.addAccountPayment(
      personId: thirdId,
      campaignId: campaignId,
      amountBobMinor: 336000,
      advance: true,
    );
    await repo.confirmPurchase(
      purchase(
        quantityBase: 30000,
        priceMinor: 1600,
        ownerId: thirdId,
        currency: CurrencyCode.usd,
        fx: 7000000,
      ),
    );
    final settlement = (await repo.settlements()).firstWhere(
      (row) => row['id'] == thirdId,
    );
    expect(settlement['charges'], 336000);
    expect(settlement['payments'], 336000);
    expect(settlement['balance'], 0);
  });

  test('FIFO consume lotes de costos diferentes y valoriza Bs 5.450', () async {
    await repo.confirmPurchase(
      purchase(
        quantityBase: 20000,
        priceMinor: 10000,
        ownerId: familyId,
        date: DateTime.utc(2026, 1, 1),
      ),
    );
    await repo.confirmPurchase(
      purchase(
        quantityBase: 30000,
        priceMinor: 11500,
        ownerId: familyId,
        date: DateTime.utc(2026, 2, 1),
      ),
    );
    final applicationId = await repo.confirmApplication(
      ApplicationDraft(
        personId: familyId,
        farmId: farmId,
        campaignId: campaignId,
        appliedAt: DateTime.utc(2026, 3, 1),
        lines: [
          ApplicationLineDraft(productId: productId, quantityBase: 50000),
        ],
      ),
    );
    final application = (await repo.applications()).singleWhere(
      (row) => row['id'] == applicationId,
    );
    expect(application['total_cost_bob_minor'], 545000);
    final consumptions = await repo.list('application_consumptions');
    expect(
      consumptions.map((row) => row['cost_bob_minor']),
      containsAll([200000, 345000]),
    );
    expect(await repo.stock(), isEmpty);
  });

  test(
    'reversión de aplicación restaura inventario y revierte el cargo',
    () async {
      await repo.confirmPurchase(
        purchase(quantityBase: 50000, priceMinor: 11200, ownerId: familyId),
      );
      final applicationId = await repo.confirmApplication(
        ApplicationDraft(
          personId: familyId,
          farmId: farmId,
          campaignId: campaignId,
          appliedAt: DateTime.utc(2026, 3, 1),
          lines: [
            ApplicationLineDraft(productId: productId, quantityBase: 28000),
          ],
        ),
      );
      await repo.reverseApplication(applicationId, reason: 'Error de carga');
      expect((await repo.stock()).single['quantity_base'], 50000);
      final settlement = (await repo.settlements()).firstWhere(
        (row) => row['id'] == familyId,
      );
      expect(settlement['balance'], 0);
      expect((await repo.applications()).single['status'], 'REVERSED');
    },
  );

  test('compra consumida bloquea cancelación directa', () async {
    final id = await repo.confirmPurchase(
      purchase(quantityBase: 50000, priceMinor: 11200, ownerId: familyId),
    );
    await repo.confirmApplication(
      ApplicationDraft(
        personId: familyId,
        farmId: farmId,
        campaignId: campaignId,
        appliedAt: DateTime.utc(2026, 3, 1),
        lines: [ApplicationLineDraft(productId: productId, quantityBase: 1000)],
      ),
    );
    expect(
      () => repo.reversePurchase(id),
      throwsA(isA<BusinessRuleException>()),
    );
  });

  test('fallo interno revierte toda la transacción de compra', () async {
    final bad = purchase(
      quantityBase: 10000,
      priceMinor: 5000,
      ownerId: 999999,
    );
    await expectLater(repo.confirmPurchase(bad), throwsA(anything));
    expect(await repo.purchases(), isEmpty);
    expect(await repo.list('purchase_items'), isEmpty);
    expect(await repo.list('inventory_lots'), isEmpty);
  });

  test('transferencia divide lote sin modificar costo histórico', () async {
    await repo.confirmPurchase(
      purchase(quantityBase: 50000, priceMinor: 11200, ownerId: familyId),
    );
    final source = (await repo.list('inventory_lots')).single;
    final destinationLot = await repo.transferStock(
      sourceLotId: source['id']! as int,
      destinationPersonId: thirdId,
      quantityBase: 10000,
    );
    final lots = await repo.list('inventory_lots');
    final destination = lots.firstWhere((row) => row['id'] == destinationLot);
    expect(destination['unit_cost_bob_minor_per_major_unit'], 11200);
    expect(destination['original_unit_price_minor'], 11200);
    expect((await repo.dashboard()).stockBase, 50000);
  });

  test(
    'una factura admite tres productos, BOB/USD, asignaciones y foto',
    () async {
      final paraquat = await repo.addProduct(name: 'Paraquat', unit: 'KG');
      final aceite = await repo.addProduct(name: 'Aceite');
      final id = await repo.confirmPurchase(
        PurchaseDraft(
          supplierId: supplierId,
          campaignId: campaignId,
          purchaseDate: DateTime.utc(2026, 4, 1),
          invoiceImagePath: 'invoices/factura-001.jpg',
          exchangeRateSource: ExchangeRateSource.agreedWithSupplier,
          items: [
            PurchaseItemDraft(
              productId: productId,
              quantityBase: 420000,
              currency: CurrencyCode.usd,
              originalUnitPriceMinor: 1600,
              exchangeRateScaled: 7000000,
              allocations: [
                AllocationDraft(personId: familyId, quantityBase: 420000),
              ],
            ),
            PurchaseItemDraft(
              productId: paraquat,
              quantityBase: 56000,
              currency: CurrencyCode.bob,
              originalUnitPriceMinor: 16000,
              allocations: [
                AllocationDraft(personId: thirdId, quantityBase: 56000),
              ],
            ),
            PurchaseItemDraft(
              productId: aceite,
              quantityBase: 20000,
              currency: CurrencyCode.bob,
              originalUnitPriceMinor: 8000,
              allocations: [
                AllocationDraft(personId: familyId, quantityBase: 20000),
              ],
            ),
          ],
        ),
      );
      final purchaseRow = (await repo.purchases()).singleWhere(
        (row) => row['id'] == id,
      );
      expect(purchaseRow['total_bob_minor'], 5760000);
      expect(purchaseRow['invoice_image_path'], 'invoices/factura-001.jpg');
      expect(await repo.list('purchase_items'), hasLength(3));
      expect(await repo.list('purchase_allocations'), hasLength(3));
      expect(await repo.list('inventory_lots'), hasLength(3));
    },
  );

  test(
    'inventario separa litros y kilos y calcula stock por persona',
    () async {
      final paraquat = await repo.addProduct(name: 'Paraquat', unit: 'KG');
      await repo.confirmPurchase(
        purchase(quantityBase: 20000, priceMinor: 10000, ownerId: familyId),
      );
      await repo.confirmPurchase(
        PurchaseDraft(
          supplierId: supplierId,
          campaignId: campaignId,
          purchaseDate: DateTime.utc(2026, 2, 1),
          items: [
            PurchaseItemDraft(
              productId: paraquat,
              quantityBase: 30000,
              currency: CurrencyCode.bob,
              originalUnitPriceMinor: 12000,
              allocations: [
                AllocationDraft(personId: familyId, quantityBase: 30000),
              ],
            ),
          ],
        ),
      );
      final inventory = await repo.inventorySummary();
      expect(
        inventory.firstWhere(
          (row) => row['product_name'] == 'Glifosato',
        )['unit'],
        'L',
      );
      expect(
        inventory.firstWhere(
          (row) => row['product_name'] == 'Paraquat',
        )['unit'],
        'KG',
      );
      final personStock = await repo.personStockSummary(familyId);
      expect(personStock, hasLength(2));
      expect(
        personStock.fold<int>(
          0,
          (sum, row) => sum + (row['available_base']! as int),
        ),
        50000,
      );
    },
  );

  test('detalle de producto expone stock, lotes y bloquea exceso', () async {
    await repo.confirmPurchase(
      purchase(quantityBase: 20000, priceMinor: 11200, ownerId: familyId),
    );
    final insight = await repo.productStockInsight(
      personId: familyId,
      productId: productId,
      campaignId: campaignId,
    );
    expect(insight['owner_available_base'], 20000);
    expect(insight['available_lots'], 1);
    expect(insight['next_fifo_cost_minor'], 11200);
    await expectLater(
      repo.confirmApplication(
        ApplicationDraft(
          personId: familyId,
          farmId: farmId,
          campaignId: campaignId,
          appliedAt: DateTime.utc(2026, 3, 1),
          lines: [
            ApplicationLineDraft(productId: productId, quantityBase: 21000),
          ],
        ),
      ),
      throwsA(isA<BusinessRuleException>()),
    );
  });

  test('plan conserva área editable, unidad y necesidad correcta', () async {
    await repo.addPlan(
      farmId: farmId,
      campaignId: campaignId,
      productId: productId,
      areaM2: 280000,
      doseBasePerHa: 1500,
    );
    final plan = (await repo.plans()).single;
    expect(plan['area_m2'], 280000);
    expect(plan['required_quantity_base'], 42000);
    expect(plan['unit'], 'L');
  });
}
