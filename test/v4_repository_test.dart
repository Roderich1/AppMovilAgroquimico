import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late AppDatabase database;
  late AgroRepository repo;
  late int owner, receiver, supplier, campaign, product, farm;

  setUp(() async {
    database = AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    repo = AgroRepository(database);
    owner = await repo.addPerson(name: 'Origen', role: PersonRole.family);
    receiver = await repo.addPerson(name: 'Destino', role: PersonRole.family);
    supplier = await repo.addSupplier(name: 'Proveedor');
    campaign = await repo.addCampaign(
      name: 'Campaña 1',
      start: DateTime.utc(2026, 1, 1),
    );
    product = await repo.addProduct(name: 'Producto');
    farm = await repo.addFarm(ownerId: owner, name: 'Chaco', areaM2: 10000);
  });
  tearDown(() => database.close());

  Future<void> buy(int quantity, int price, DateTime date) =>
      repo.confirmPurchase(
        PurchaseDraft(
          supplierId: supplier,
          campaignId: campaign,
          purchaseDate: date,
          items: [
            PurchaseItemDraft(
              productId: product,
              quantityBase: quantity,
              currency: CurrencyCode.bob,
              originalUnitPriceMinor: price,
              allocations: [
                AllocationDraft(personId: owner, quantityBase: quantity),
              ],
            ),
          ],
        ),
      );

  test('solo una campaña activa y el inventario sobrevive al cambio', () async {
    await buy(10000, 10000, DateTime.utc(2026, 1, 2));
    final next = await repo.addCampaign(
      name: 'Campaña 2',
      start: DateTime.utc(2026, 7, 1),
    );
    expect(
      (await repo.campaigns())
          .where((row) => row['status'] == 'ACTIVE')
          .single['id'],
      campaign,
    );
    await expectLater(
      repo.activateCampaign(next),
      throwsA(isA<CampaignConflictException>()),
    );
    await repo.activateCampaign(next, closeCurrent: true);
    expect((await repo.activeCampaign())!['id'], next);
    expect(
      (await repo.personStockSummary(owner)).single['available_base'],
      10000,
    );
  });

  test(
    'transferencia FIFO usa varios lotes, conserva costo y revierte',
    () async {
      await buy(10000, 10000, DateTime.utc(2026, 1, 2));
      await buy(20000, 20000, DateTime.utc(2026, 1, 3));
      final transfer = await repo.transferProductFifo(
        fromPersonId: owner,
        toPersonId: receiver,
        productId: product,
        quantityBase: 25000,
      );
      final db = await database.database;
      final items = await db.query(
        'transfer_lot_items',
        where: 'transfer_id=?',
        whereArgs: [transfer],
        orderBy: 'id',
      );
      expect(items.map((row) => row['quantity_base']), [10000, 15000]);
      expect((await repo.transfers()).single['total_cost_bob_minor'], 400000);
      expect(
        (await repo.personStockSummary(receiver)).single['available_base'],
        25000,
      );
      await repo.reverseTransfer(transfer);
      expect(
        (await repo.personStockSummary(owner)).single['available_base'],
        30000,
      );
      expect(
        (await repo.personStockSummary(receiver)).single['available_base'],
        0,
      );
    },
  );

  test('transferencia insuficiente hace rollback completo', () async {
    await buy(10000, 10000, DateTime.utc(2026, 1, 2));
    await expectLater(
      repo.transferProductFifo(
        fromPersonId: owner,
        toPersonId: receiver,
        productId: product,
        quantityBase: 11000,
      ),
      throwsA(isA<BusinessRuleException>()),
    );
    expect(await repo.transfers(), isEmpty);
    expect(
      (await repo.personStockSummary(owner)).single['available_base'],
      10000,
    );
  });

  test(
    'saldo inicial cruza campañas y el pago se imputa a deuda antigua',
    () async {
      await buy(10000, 10000, DateTime.utc(2026, 1, 2));
      await repo.confirmApplication(
        ApplicationDraft(
          personId: owner,
          farmId: farm,
          campaignId: campaign,
          appliedAt: DateTime.utc(2026, 2, 1),
          lines: [
            ApplicationLineDraft(productId: product, quantityBase: 10000),
          ],
        ),
      );
      final next = await repo.addCampaign(
        name: 'Campaña 2',
        start: DateTime.utc(2026, 7, 1),
      );
      await repo.activateCampaign(next, closeCurrent: true);
      await repo.addAccountPayment(
        personId: owner,
        campaignId: next,
        amountBobMinor: 4000,
      );
      final balance = await repo.personCampaignBalance(owner, next);
      expect(balance['opening_balance'], 100000);
      expect(balance['campaign_payments'], 4000);
      expect(balance['total_balance'], 96000);
      final allocations = await (await database.database).query(
        'payment_allocations',
      );
      expect(allocations.single['amount_bob_minor'], 4000);
    },
  );
}
