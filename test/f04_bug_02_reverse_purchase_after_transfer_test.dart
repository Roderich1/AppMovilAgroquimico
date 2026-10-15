// F04-BUG-02: después de revertir una transferencia, la compra de origen debe
// poder revertirse, porque todo el stock transferido volvió a su lote.
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('revertir la compra después de revertir su transferencia', () async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(database.close);
    final repo = AgroRepository(database);
    final owner = await repo.addPerson(name: 'Origen', role: PersonRole.family);
    final receiver = await repo.addPerson(
      name: 'Destino',
      role: PersonRole.family,
    );
    final supplier = await repo.addSupplier(name: 'Proveedor');
    final campaign = await repo.addCampaign(
      name: 'Campaña 1',
      start: DateTime.utc(2026, 1, 1),
    );
    final product = await repo.addProduct(name: 'Glifosato');
    final purchase = await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: supplier,
        campaignId: campaign,
        purchaseDate: DateTime.utc(2026, 1, 2),
        items: [
          PurchaseItemDraft(
            productId: product,
            quantityBase: 10000,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 10000,
            allocations: [
              AllocationDraft(personId: owner, quantityBase: 10000),
            ],
          ),
        ],
      ),
    );
    final transfer = await repo.transferProductFifo(
      fromPersonId: owner,
      toPersonId: receiver,
      productId: product,
      quantityBase: 4000,
    );
    await repo.reverseTransfer(transfer);

    // Tras revertir la transferencia, el origen tiene de nuevo las 10000.
    final db = await database.database;
    Future<int> saldo(int person) async =>
        (await db.rawQuery(
              'SELECT COALESCE(SUM(quantity_signed),0) saldo '
              'FROM inventory_movements WHERE owner_person_id=? AND product_id=?',
              [person, product],
            )).single['saldo']!
            as int;
    expect(await saldo(owner), 10000);
    expect(await saldo(receiver), 0);

    await repo.reversePurchase(purchase, reason: 'Error de registro');

    final compra = (await db.query(
      'purchases',
      where: 'id=?',
      whereArgs: [purchase],
    )).single;
    expect(compra['status'], 'REVERSED');
    expect(await saldo(owner), 0);
    expect(await saldo(receiver), 0);
  });
}
