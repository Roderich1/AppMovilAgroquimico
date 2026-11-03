// OE3, cierre HOST de #45 (REC-009, pagos a proveedores): las dos guardas del
// pago posterior que no tenían prueba según el inventario de OE3 del
// 2026-11-03 (`_insertProviderPayment` en `agro_repository.dart`):
//
// - un pago que supera el saldo de la compra se rechaza («El pago supera el
//   saldo de la compra.»), también el que lo supera por un centavo después de
//   pagos parciales; el pago que lo deja exacto en cero se acepta;
// - una compra revertida no admite pagos («La compra no está activa.»), aunque
//   la reversión haya dejado su saldo pagado en cero.
//
// En cada rechazo todas las tablas quedan idénticas, fila por fila: compras,
// pagos, inventario y las cuentas internas (`account_transactions`, con el
// cargo del tercero y, tras revertir, su abono), además de la liquidación
// calculada (`settlements`).
//
// Pruebas de HOST (sqflite_common_ffi, base en memoria). No son DEVICE.
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';

typedef Row = Map<String, Object?>;

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late Household household;

  setUp(() async {
    database = openDb(inMemoryDatabasePath);
    household = await seedHousehold(AgroRepository(database));
    await OwnerBindingStore(database).bindExistingPerson(
      personId: household.titular,
      scope: memberA,
      installationRef: installationHere,
    );
    // Compartida: la compra puede asignarse a un tercero, que lleva cargo en
    // su cuenta interna (BY_PURCHASE_ALLOCATION).
    await OperationModeStore(database)
        .apply(OperationMode.shared, confirmed: true);
  });

  AgroRepository repo() => household.repo;

  /// Compra de 10 unidades: 6 al titular y 4 al vecino (tercero).
  Future<int> buyShared() => repo().confirmPurchase(
    PurchaseDraft(
      supplierId: household.supplier,
      campaignId: household.campaign,
      purchaseDate: DateTime.utc(2026, 1, 2, 14),
      items: [
        PurchaseItemDraft(
          productId: household.product,
          quantityBase: 10000,
          currency: CurrencyCode.bob,
          originalUnitPriceMinor: 10000,
          allocations: [
            AllocationDraft(personId: household.titular, quantityBase: 6000),
            AllocationDraft(personId: household.thirdParty, quantityBase: 4000),
          ],
        ),
      ],
    ),
  );

  Future<int> totalOf(int purchase) async =>
      (await (await database.database).query(
            'purchases',
            columns: ['total_bob_minor'],
            where: 'id=?',
            whereArgs: [purchase],
          )).single['total_bob_minor']!
          as int;

  Future<int> pay(int purchase, int amount) => repo().addProviderPayment(
    purchaseId: purchase,
    payerPersonId: household.titular,
    amountBobMinor: amount,
    method: PaymentMethod.cash,
  );

  /// Rechazo con [fragment] y ninguna fila distinta en ninguna tabla, ni en
  /// la liquidación calculada.
  Future<void> rejectedWithoutChanges(
    Future<Object?> Function() call,
    String fragment,
  ) async {
    final db = await database.database;
    final before = await dumpTables(db);
    final settlementsBefore = await repo().settlements();
    await expectLater(
      call(),
      throwsA(
        isA<BusinessRuleException>().having(
          (e) => e.message,
          'message',
          contains(fragment),
        ),
      ),
    );
    expect(await dumpTables(db), before);
    expect(await repo().settlements(), settlementsBefore);
  }

  Future<List<Row>> accountRows() async =>
      (await database.database).query('account_transactions', orderBy: 'id');

  test('un pago que supera el saldo se rechaza sin tocar compras, pagos ni '
      'cuentas internas; el que lo deja en cero se acepta', () async {
    final purchase = await buyShared();
    final total = await totalOf(purchase);
    expect(total, greaterThan(100));
    // El tercero lleva su cargo: las cuentas internas no están vacías.
    expect(
      (await accountRows()).map((row) => row['type']),
      contains('PURCHASE_ALLOCATION_CHARGE'),
    );

    // Un único pago mayor que el total.
    await rejectedWithoutChanges(
      () => pay(purchase, total + 1),
      'El pago supera el saldo de la compra.',
    );
    // Tras un pago parcial, un centavo más que el saldo.
    await pay(purchase, total - 100);
    await rejectedWithoutChanges(
      () => pay(purchase, 101),
      'El pago supera el saldo de la compra.',
    );
    // El saldo exacto sí.
    await pay(purchase, 100);
    final payments = await (await database.database).query(
      'provider_payments',
      where: 'purchase_id=?',
      whereArgs: [purchase],
      orderBy: 'id',
    );
    expect(payments.map((row) => row['amount_bob_minor']), [total - 100, 100]);
    // Saldada: cualquier pago más se rechaza igual.
    await rejectedWithoutChanges(
      () => pay(purchase, 1),
      'El pago supera el saldo de la compra.',
    );
  });

  test('una compra revertida no admite pagos, aunque su saldo pagado haya '
      'vuelto a cero; nada cambia', () async {
    final purchase = await buyShared();
    final total = await totalOf(purchase);
    await pay(purchase, 500);
    await repo().reversePurchaseUnauditedForTesting(purchase, reason: 'Error');
    final db = await database.database;
    // La reversión anuló el pago y abonó el cargo del tercero: el pagado
    // vigente es cero, así que sólo la guarda de compra activa lo frena.
    expect(
      (await db.query(
        'provider_payments',
        where: 'purchase_id=? AND reversed_at IS NULL',
        whereArgs: [purchase],
      )),
      isEmpty,
    );
    expect(
      (await accountRows()).map((row) => row['type']),
      containsAll(['PURCHASE_ALLOCATION_CHARGE', 'CREDIT_ADJUSTMENT']),
    );
    for (final amount in [1, 500, total]) {
      await rejectedWithoutChanges(
        () => pay(purchase, amount),
        'La compra no está activa.',
      );
    }
    // Lo mismo con una compra revertida sin pagos previos.
    final untouched = await buyShared();
    await repo().reversePurchaseUnauditedForTesting(untouched, reason: 'Error');
    await rejectedWithoutChanges(
      () => pay(untouched, 1),
      'La compra no está activa.',
    );
  });
}
