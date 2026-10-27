// D-04 (decisión del autor del 2026-10-27): M-4 y D04-06 con las operaciones
// reales de la app en lugar de asientos insertados a mano. La tardía se
// confirma por RF-03 y la aplicación se revierte por RF-13, las dos con la
// autorización del titular (PIN de prueba), como en
// `f04_rf03_late_operations_test` y `f04_rf13_reversal_audit_test`.
//
// Usa las lecturas nuevas de D-04: sobre `ed9c55c` no compila.

import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/services/auth/local_owner_credential.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/d04_world.dart' show bs;
import 'support/f04_app_access.dart';
import 'support/f04_mode_fixtures.dart';
import 'support/f04_owner_pin.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late AgroRepository repo;
  late Household h;
  late OwnerBindingContext binding;
  late TestOwnerPin pin;
  late int history;

  setUp(() async {
    database = openDb(inMemoryDatabasePath);
    final bound = await seedActivatedInstallation(database);
    repo = AgroRepository(database, ownerCredential: () => pin.credential);
    h = await seedHousehold(repo);
    history = await repo.addHistoricalCampaign(
      name: 'Campaña 2025',
      start: DateTime.utc(2025, 6, 1, 15),
      end: DateTime.utc(2025, 12, 30, 15),
    );
    binding = OwnerBindingContext(
      bindingId: bound.id,
      personId: bound.personId,
      scope: memberA,
    );
    pin = await TestOwnerPin.enrolled(binding);
  });
  tearDown(() => database.close());

  Future<OwnerAuthorization> authorize(
    AuthorizationPurpose purpose,
    String subject,
  ) => pin.credential.verify(
    pin: '284917',
    purpose: purpose,
    subjectRef: subject,
    binding: binding,
  );

  Future<void> confirmLate(String ref) async {
    final result = await repo.confirmLateOperation(
      ref,
      authorization: await authorize(
        AuthorizationPurpose.confirmLateOperation,
        'late:$ref',
      ),
    );
    expect(result, isNotNull);
  }

  Future<Map<int, int>> allocationsOf(int payment) async => {
    for (final row in await (await database.database).query(
      'payment_allocations',
      where: 'payment_transaction_id=?',
      whereArgs: [payment],
    ))
      row['charge_transaction_id']! as int: row['amount_bob_minor']! as int,
  };

  Future<int> chargeOf(String referenceType, int referenceId) async =>
      (await (await database.database).query(
            'account_transactions',
            where: 'reference_type=? AND reference_id=? AND amount_bob_minor_signed>0',
            whereArgs: [referenceType, referenceId],
          )).single['id']!
          as int;

  test('M-4 y D04-06 reales: la tardía confirmada va primero en el FIFO y '
      'cambia el cierre de su período; la reversión libera lo imputado', () async {
    // Hermana compra 5 L a 100 Bs/L y aplica 2 L en la campaña activa: 200 Bs.
    await h.buy(h.relative, 5000);
    final application = await h.apply(h.relative, h.relativeFarm, 2000);
    final c2 = await chargeOf('APPLICATION', application);

    final before = (await repo.accountLedger()).statement(
      h.relative,
      campaignId: history,
    );
    expect(before.closingMinor, 0);

    // Tardía en la campaña cerrada: compra de 0,5 L y aplicación de 0,5 L.
    final purchaseRef = await repo.captureLatePurchase(
      PurchaseDraft(
        supplierId: h.supplier,
        campaignId: h.campaign,
        purchaseDate: DateTime.utc(2025, 8, 10, 15),
        items: [
          PurchaseItemDraft(
            productId: h.product,
            quantityBase: 500,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 10000,
            allocations: [
              AllocationDraft(personId: h.relative, quantityBase: 500),
            ],
          ),
        ],
      ),
      reason: 'Factura encontrada',
    );
    await confirmLate(purchaseRef);
    final applicationRef = await repo.captureLateApplication(
      ApplicationDraft(
        personId: h.relative,
        farmId: h.relativeFarm,
        campaignId: h.campaign,
        appliedAt: DateTime.utc(2025, 9, 1, 15),
        lines: [ApplicationLineDraft(productId: h.product, quantityBase: 500)],
      ),
      reason: 'Aplicación sin registrar',
    );
    await confirmLate(applicationRef);
    final lateCharge = (await (await database.database).query(
      'account_transactions',
      where: "person_id=? AND campaign_id=? AND type='USAGE_CHARGE'",
      whereArgs: [h.relative, history],
    )).single;
    final c3 = lateCharge['id']! as int;
    expect(lateCharge['amount_bob_minor_signed'], 5000);
    expect(c3, greaterThan(c2), reason: 'la tardía se inserta después');

    // M-4: el cierre del período cerrado cambia tras la tardía.
    var ledger = await repo.accountLedger();
    expect(
      ledger.statement(h.relative, campaignId: history).closingMinor,
      5000,
    );

    // El pago va primero a la tardía (día más antiguo), aunque su id es mayor.
    final payment = await repo.registerAccountPayment(
      personId: h.relative,
      campaignId: h.campaign,
      amountBobMinor: 10000,
    );
    expect(await allocationsOf(payment.paymentId), {c3: 5000, c2: 5000});
    expect(
      payment.message('Hermana'),
      'Pago de ${bs(10000)} registrado a Hermana. Imputado: Campaña 2025 '
      '${bs(5000)} · Campaña 1 ${bs(5000)}.',
    );
    ledger = await repo.accountLedger();
    var account = ledger.account(h.relative);
    expect(account.debtFor(history).pendingMinor, 0);
    expect(account.debtFor(h.campaign).pendingMinor, 15000);

    // D04-06 real: la reversión RF-13 libera lo imputado al cargo revertido.
    await repo.reverseApplication(
      application,
      reason: 'Dosis registrada por error',
      authorization: await authorize(
        AuthorizationPurpose.reverseApplication,
        'application:$application',
      ),
    );
    ledger = await repo.accountLedger();
    account = ledger.account(h.relative);
    expect(account.pendingMinor, 0);
    expect(account.releasedMinor, 5000);
    expect(account.netMinor, -5000);
    expect(account.netMinor, account.signedSumMinor);
    // Un pago posterior no se imputa al cargo revertido (criterio Q-5).
    final later = await repo.registerAccountPayment(
      personId: h.relative,
      amountBobMinor: 1000,
    );
    expect(await allocationsOf(later.paymentId), isEmpty);
    expect(await allocationsOf(payment.paymentId), {c3: 5000, c2: 5000});
  });
}
