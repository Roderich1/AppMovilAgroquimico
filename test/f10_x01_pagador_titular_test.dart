// Regla del pagador aprobada el 2026-10-26 tras el piloto X01: el pago al
// proveedor lo registra el titular vigente de la instalación, en las dos
// modalidades. El titular sale del vínculo real (`owner_bindings`), no del rol
// ADMIN, del nombre ni de la primera fila. Compra y pago se guardan juntos.
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/domain/person_roles.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';

void main() {
  sqfliteFfiInit();

  group('regla pura (person_roles)', () {
    bool can(
      PersonRole role, {
      required bool owner,
      required OperationMode mode,
    }) => canActAs(
      PersonPurpose.providerPayer,
      role: role,
      isOwner: owner,
      mode: mode,
    );

    test('compartido: paga el titular, sea familiar o ADMIN; nadie más', () {
      for (final role in PersonRole.values) {
        expect(
          can(role, owner: true, mode: OperationMode.shared),
          isTrue,
          reason: 'titular ${role.name}',
        );
        expect(
          can(role, owner: false, mode: OperationMode.shared),
          isFalse,
          reason: 'no titular ${role.name}',
        );
      }
    });

    test('propio: igual, sólo el titular', () {
      for (final role in PersonRole.values) {
        expect(can(role, owner: true, mode: OperationMode.personal), isTrue);
        expect(can(role, owner: false, mode: OperationMode.personal), isFalse);
      }
    });

    test('las demás reglas por rol no cambian', () {
      bool shared(
        PersonPurpose purpose,
        PersonRole role, {
        bool owner = false,
      }) => canActAs(
        purpose,
        role: role,
        isOwner: owner,
        mode: OperationMode.shared,
      );
      expect(shared(PersonPurpose.applicator, PersonRole.admin), isFalse);
      expect(
        shared(PersonPurpose.applicator, PersonRole.admin, owner: true),
        isTrue,
      );
      expect(shared(PersonPurpose.transferParty, PersonRole.family), isTrue);
      for (final role in PersonRole.values) {
        expect(shared(PersonPurpose.purchaseAllocation, role), isTrue);
        expect(shared(PersonPurpose.farmOwner, role), isTrue);
      }
    });
  });

  group('repositorio', () {
    late AppDatabase database;
    late Household household;
    late int admin;

    /// Hogar compartido con titular (familiar) vinculado, hermana, vecino y un
    /// ADMIN histórico que NO es titular.
    setUp(() async {
      database = openDb(inMemoryDatabasePath);
      final repo = AgroRepository(database);
      household = await seedHousehold(repo);
      admin = await repo.addPerson(
        name: 'Pagador antiguo',
        role: PersonRole.admin,
      );
      await OwnerBindingStore(database).bindExistingPerson(
        personId: household.titular,
        scope: memberA,
        installationRef: installationHere,
      );
      await OperationModeStore(database)
          .apply(OperationMode.shared, confirmed: true);
    });

    Future<void> rejectedWithoutChanges(
      Future<Object?> Function() call,
      String fragment,
    ) async {
      final db = await database.database;
      final before = await dumpTables(db);
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
    }

    Future<List<Map<String, Object?>>> payments() async =>
        (await database.database).query('provider_payments', orderBy: 'id');

    test(
      'candidatos a pagador: sólo el titular, aunque haya un ADMIN',
      () async {
        final ids = {
          for (final p in await household.repo.peopleFor(
            PersonPurpose.providerPayer,
          ))
            p['id'],
        };
        expect(ids, {household.titular});
      },
    );

    test('pago posterior por el titular: se guarda', () async {
      final purchase = await household.buy(household.relative, 1000);
      await household.repo.addProviderPayment(
        purchaseId: purchase,
        payerPersonId: household.titular,
        amountBobMinor: 5000,
        method: 'CASH',
      );
      expect((await payments()).single['payer_person_id'], household.titular);
    });

    test('pago posterior por otra persona (familiar o ADMIN): se rechaza sin '
        'cambios', () async {
      final purchase = await household.buy(household.relative, 1000);
      for (final payer in [household.relative, admin, household.thirdParty]) {
        await rejectedWithoutChanges(
          () => household.repo.addProviderPayment(
            purchaseId: purchase,
            payerPersonId: payer,
            amountBobMinor: 100,
            method: 'CASH',
          ),
          'titular vigente',
        );
      }
    });

    test('compra pagada al confirmar: compra y pago en la misma escritura, a '
        'nombre del titular y con la fecha de la compra', () async {
      final date = DateTime.utc(2026, 1, 20, 14);
      final purchase = await household.repo.confirmPurchase(
        PurchaseDraft(
          supplierId: household.supplier,
          campaignId: household.campaign,
          purchaseDate: date,
          items: [
            PurchaseItemDraft(
              productId: household.product,
              quantityBase: 2000,
              currency: CurrencyCode.bob,
              originalUnitPriceMinor: 4500,
              allocations: [
                // Las existencias van a quien se asignan; el pago, al titular.
                AllocationDraft(
                  personId: household.relative,
                  quantityBase: 2000,
                ),
              ],
            ),
          ],
        ),
        paidInFullByOwner: true,
      );
      final row = (await payments()).single;
      expect(row['purchase_id'], purchase);
      expect(row['payer_person_id'], household.titular);
      expect(row['amount_bob_minor'], 9000);
      expect(row['payment_date'], date.toIso8601String());
      expect((await household.repo.purchases()).single['paid_bob_minor'], 9000);
    });

    test('compra sin pago: no se crea ningún pago', () async {
      await household.buy(household.titular, 1000);
      expect(await payments(), isEmpty);
    });

    test(
      'sin titular vinculado, confirmar pagada no escribe ni la compra ni el '
      'pago',
      () async {
        // Un archivo propio: con `inMemoryDatabasePath`, sqflite_common_ffi
        // comparte la misma base entre aperturas y vería el titular del setUp.
        final fresh = openDb(await tempDbPath('sin-titular'));
        final repo = AgroRepository(fresh);
        final h = await seedHousehold(repo);
        final db = await fresh.database;
        final before = await dumpTables(db);
        await expectLater(
          repo.confirmPurchase(
            PurchaseDraft(
              supplierId: h.supplier,
              campaignId: h.campaign,
              purchaseDate: DateTime.utc(2026, 1, 20),
              items: [
                PurchaseItemDraft(
                  productId: h.product,
                  quantityBase: 1000,
                  currency: CurrencyCode.bob,
                  originalUnitPriceMinor: 1000,
                  allocations: [
                    AllocationDraft(personId: h.titular, quantityBase: 1000),
                  ],
                ),
              ],
            ),
            paidInFullByOwner: true,
          ),
          throwsA(
            isA<BusinessRuleException>().having(
              (e) => e.message,
              'message',
              contains('titular vinculado'),
            ),
          ),
        );
        expect(await dumpTables(db), before);
        // Sin pago sí se puede comprar: la regla sólo afecta al pago.
        await h.buy(h.titular, 1000);
        expect((await db.query('purchases')).length, 1);
      },
    );

    test('los pagos históricos de un ADMIN se conservan tal cual', () async {
      final purchase = await household.buy(household.relative, 1000);
      final db = await database.database;
      // Un pago anterior a la regla, registrado por el ADMIN.
      await db.insert('provider_payments', {
        'purchase_id': purchase,
        'payer_person_id': admin,
        'payment_date': '2026-01-05T12:00:00.000Z',
        'amount_bob_minor': 3000,
        'method': 'CASH',
      });
      final before = await payments();
      await household.repo.addProviderPayment(
        purchaseId: purchase,
        payerPersonId: household.titular,
        amountBobMinor: 2000,
        method: 'CASH',
      );
      final after = await payments();
      expect(after.first, before.single, reason: 'no se reasigna');
      expect(after.last['payer_person_id'], household.titular);
      expect(
        (await db.query(
          'persons',
          where: 'id=?',
          whereArgs: [admin],
        )).single['role'],
        'ADMIN',
        reason: 'nadie cambia de rol',
      );
    });
  });
}
