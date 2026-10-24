// F04-BUG-02: después de revertir una transferencia, la compra de origen debe
// poder revertirse, porque todo el stock transferido volvió a su lote.
// RF-13 / CU-17: la operación original se conserva y una misma reversión no
// produce dos restituciones.
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';

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
    await repo.reverseTransferUnauditedForTesting(transfer);

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

    await repo.reversePurchaseUnauditedForTesting(
      purchase,
      reason: 'Error de registro',
    );

    final compra = (await db.query(
      'purchases',
      where: 'id=?',
      whereArgs: [purchase],
    )).single;
    expect(compra['status'], 'REVERSED');
    expect(await saldo(owner), 0);
    expect(await saldo(receiver), 0);
  });

  group('casos límite', () {
    late AppDatabase database;
    late AgroRepository repo;
    late int a, b, c, tercero, supplier, campaign, glifosato, atrazina;

    setUp(() async {
      database = openDb(inMemoryDatabasePath);
      repo = AgroRepository(database);
      a = await repo.addPerson(name: 'A', role: PersonRole.family);
      b = await repo.addPerson(name: 'B', role: PersonRole.family);
      c = await repo.addPerson(name: 'C', role: PersonRole.family);
      tercero = await repo.addPerson(
        name: 'Tercero',
        role: PersonRole.thirdParty,
      );
      supplier = await repo.addSupplier(name: 'Proveedor');
      campaign = await repo.addCampaign(
        name: 'Campaña 1',
        start: DateTime.utc(2026, 1, 1),
      );
      glifosato = await repo.addProduct(name: 'Glifosato');
      atrazina = await repo.addProduct(name: 'Atrazina');
    });

    /// Compra de dos productos: Glifosato 10000 para A; Atrazina 6000 para A
    /// y 2000 para el tercero (que se cobra al asignar).
    Future<int> twoProductPurchase() => repo.confirmPurchase(
      PurchaseDraft(
        supplierId: supplier,
        campaignId: campaign,
        purchaseDate: DateTime.utc(2026, 1, 2),
        items: [
          PurchaseItemDraft(
            productId: glifosato,
            quantityBase: 10000,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 10000,
            allocations: [AllocationDraft(personId: a, quantityBase: 10000)],
          ),
          PurchaseItemDraft(
            productId: atrazina,
            quantityBase: 8000,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 5000,
            allocations: [
              AllocationDraft(personId: a, quantityBase: 6000),
              AllocationDraft(personId: tercero, quantityBase: 2000),
            ],
          ),
        ],
      ),
    );

    Future<Map<(int, int), int>> stock() async =>
        stockByPersonProduct(await database.database);

    test('multiproducto con un tercero y pago: tras revertir una transferencia, la compra se revierte una sola vez', () async {
      final purchase = await twoProductPurchase();
      await repo.addProviderPayment(
        purchaseId: purchase,
        payerPersonId: a,
        amountBobMinor: 1000,
        method: 'CASH',
      );
      final transfer = await repo.transferProductsFifo(
        fromPersonId: a,
        toPersonId: b,
        items: [
          TransferItemDraft(productId: glifosato, quantityBase: 3000),
          TransferItemDraft(productId: atrazina, quantityBase: 1000),
        ],
      );
      await repo.reverseTransferUnauditedForTesting(transfer);
      final db = await database.database;
      final chargesBefore = await db.query(
        'account_transactions',
        where: "type='PURCHASE_ALLOCATION_CHARGE'",
      );
      expect(chargesBefore, hasLength(1));

      await repo.reversePurchaseUnauditedForTesting(purchase, reason: 'Error');

      expect(
        (await stock()).values.every((saldo) => saldo == 0),
        isTrue,
        reason: 'cada (persona, producto) en 0: ${await stock()}',
      );
      // Una restitución por lote vivo de la compra (A-Glifosato,
      // A-Atrazina, Tercero-Atrazina); ninguna sobre los lotes anulados.
      final reversals = await db.query(
        'inventory_movements',
        where: "type='PURCHASE_REVERSAL'",
        orderBy: 'id',
      );
      expect(
        reversals.map(
          (m) => (m['owner_person_id'], m['product_id'], m['quantity_signed']),
        ),
        unorderedEquals([
          (a, glifosato, -10000),
          (a, atrazina, -6000),
          (tercero, atrazina, -2000),
        ]),
      );
      // El cargo del tercero se acredita una vez, vinculado al original.
      final credits = await db.query(
        'account_transactions',
        where: "type='CREDIT_ADJUSTMENT'",
      );
      expect(credits, hasLength(1));
      expect(credits.single['reversal_of_id'], chargesBefore.single['id']);
      expect(
        credits.single['amount_bob_minor_signed'],
        -(chargesBefore.single['amount_bob_minor_signed']! as int),
      );
      expect(
        (await db.query(
          'provider_payments',
          where: 'purchase_id=?',
          whereArgs: [purchase],
        )).single['reversed_at'],
        isNotNull,
      );
      // La operación original sigue consultable.
      expect(
        (await db.query(
          'purchases',
          where: 'id=?',
          whereArgs: [purchase],
        )).single['status'],
        'REVERSED',
      );

      // Segundo intento: rechazado y sin ningún efecto.
      final after = await dumpTables(db);
      await expectLater(
        repo.reversePurchaseUnauditedForTesting(purchase),
        throwsA(isA<BusinessRuleException>()),
      );
      expect(await dumpTables(db), after);
    });

    test('cadena A→B→C revertida entera: la compra se revierte', () async {
      final purchase = await twoProductPurchase();
      final first = await repo.transferProductFifo(
        fromPersonId: a,
        toPersonId: b,
        productId: glifosato,
        quantityBase: 5000,
      );
      final second = await repo.transferProductFifo(
        fromPersonId: b,
        toPersonId: c,
        productId: glifosato,
        quantityBase: 2000,
      );
      await repo.reverseTransferUnauditedForTesting(second);
      await repo.reverseTransferUnauditedForTesting(first);
      expect((await stock())[(a, glifosato)], 10000);

      await repo.reversePurchaseUnauditedForTesting(purchase);

      expect((await stock()).values.every((saldo) => saldo == 0), isTrue);
    });

    test(
      'con la transferencia sin revertir se sigue rechazando y nada cambia',
      () async {
        final purchase = await twoProductPurchase();
        await repo.transferProductFifo(
          fromPersonId: a,
          toPersonId: b,
          productId: glifosato,
          quantityBase: 4000,
        );
        final db = await database.database;
        final before = await dumpTables(db);

        await expectLater(
          repo.reversePurchaseUnauditedForTesting(purchase),
          throwsA(isA<BusinessRuleException>()),
        );
        expect(await dumpTables(db), before);
      },
    );

    test(
      'un lote anulado que conserva saldo se rechaza en vez de ignorarse',
      () async {
        final purchase = await twoProductPurchase();
        final transfer = await repo.transferProductFifo(
          fromPersonId: a,
          toPersonId: b,
          productId: glifosato,
          quantityBase: 4000,
        );
        await repo.reverseTransferUnauditedForTesting(transfer);
        final db = await database.database;
        // Estado inconsistente simulado: un movimiento sobre el lote anulado.
        final reversed = (await db.query(
          'inventory_lots',
          where: 'reversed_at IS NOT NULL',
        )).single;
        await db.insert('inventory_movements', {
          'lot_id': reversed['id'],
          'product_id': glifosato,
          'owner_person_id': b,
          'movement_date': '2026-02-01T00:00:00.000Z',
          'type': 'TRANSFER_IN',
          'quantity_signed': 1,
          'reference_type': 'TRANSFER',
          'reference_id': transfer,
        });
        final before = await dumpTables(db);

        await expectLater(
          repo.reversePurchaseUnauditedForTesting(purchase),
          throwsA(
            isA<BusinessRuleException>().having(
              (e) => e.message,
              'mensaje',
              contains('lote anulado'),
            ),
          ),
        );
        expect(await dumpTables(db), before);
      },
    );
  });
}
