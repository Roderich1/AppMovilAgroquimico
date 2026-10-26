// Agricultor histórico registrado como ADMIN local. ADMIN es un rol privado de
// negocio (paga a los proveedores, política MANUAL, fuera de la liquidación);
// no es el ADMINISTRADOR central ni un permiso. Puede ser titular con una
// confirmación explícita: no cambia su rol, no se duplica la persona, no se
// reasigna ningún movimiento, y puede completar sus propias operaciones.
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/domain/installation_access.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/domain/person_roles.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';

/// Tablas que el vínculo puede tocar; todas las demás deben quedar idénticas.
const _bindingTables = {'owner_bindings', 'app_settings'};

/// Base v7 (anterior a la política) creada con datos reales y migrada a v8
/// al reabrirla. Devuelve la base abierta y el hogar.
Future<(AppDatabase, Household)> _historical(
  String name,
  Future<Household> Function(AgroRepository repo) seed,
) async {
  final path = await tempDbPath(name);
  final source = AppDatabase(factory: databaseFactoryFfi, path: path);
  final household = await seed(AgroRepository(source));
  await source.close();
  await downgradeToV7(path);
  final database = openDb(path);
  // Se sembró con otra instancia; reabierta, se opera sobre la base migrada.
  final reopened =
      Household(
          AgroRepository(database),
          household.titular,
          household.relative,
          household.thirdParty,
        )
        ..supplier = household.supplier
        ..campaign = household.campaign
        ..product = household.product
        ..titularFarm = household.titularFarm
        ..relativeFarm = household.relativeFarm;
  return (database, reopened);
}

/// Agricultor ADMIN que paga, hijo FAMILY que aplica y vecino THIRD_PARTY.
Future<Household> _adminFarmerHousehold(AgroRepository repo) async {
  final household = Household(
    repo,
    await repo.addPerson(name: 'Agricultor', role: PersonRole.admin),
    await repo.addPerson(name: 'Hijo', role: PersonRole.family),
    await repo.addPerson(name: 'Vecino', role: PersonRole.thirdParty),
  );
  household
    ..supplier = await repo.addSupplier(name: 'Proveedor')
    ..campaign = await repo.addCampaign(
      name: 'Campaña 1',
      start: DateTime.utc(2026, 1, 1),
    )
    ..product = await repo.addProduct(name: 'Glifosato')
    ..titularFarm = await repo.addFarm(
      ownerId: household.titular,
      name: 'Chaco agricultor',
      areaM2: 10000,
    )
    ..relativeFarm = await repo.addFarm(
      ownerId: household.relative,
      name: 'Chaco hijo',
      areaM2: 5000,
    );
  final purchase = await repo.confirmPurchase(
    PurchaseDraft(
      supplierId: household.supplier,
      campaignId: household.campaign,
      purchaseDate: DateTime.utc(2026, 1, 2),
      items: [
        PurchaseItemDraft(
          productId: household.product,
          quantityBase: 30000,
          currency: CurrencyCode.bob,
          originalUnitPriceMinor: 10000,
          allocations: [
            AllocationDraft(personId: household.titular, quantityBase: 10000),
            AllocationDraft(personId: household.relative, quantityBase: 15000),
            AllocationDraft(personId: household.thirdParty, quantityBase: 5000),
          ],
        ),
      ],
    ),
  );
  await _legacyProviderPayment(
    repo,
    purchase: purchase,
    payer: household.titular,
    amount: 10000,
  );
  await household.apply(household.relative, household.relativeFarm, 4000);
  await repo.addAccountPayment(
    personId: household.relative,
    amountBobMinor: 1000,
  );
  return household;
}

/// Agricultor solo, registrado como ADMIN, con su chaco y una compra propia.
Future<Household> _soloAdminFarmer(AgroRepository repo) async {
  final farmer = await repo.addPerson(
    name: 'Agricultor',
    role: PersonRole.admin,
  );
  final household = Household(repo, farmer, farmer, farmer);
  household
    ..supplier = await repo.addSupplier(name: 'Proveedor')
    ..campaign = await repo.addCampaign(
      name: 'Campaña 1',
      start: DateTime.utc(2026, 1, 1),
    )
    ..product = await repo.addProduct(name: 'Glifosato')
    ..titularFarm = await repo.addFarm(
      ownerId: farmer,
      name: 'Chaco agricultor',
      areaM2: 10000,
    );
  household.relativeFarm = household.titularFarm;
  final purchase = await household.buy(farmer, 5000);
  await _legacyProviderPayment(
    repo,
    purchase: purchase,
    payer: farmer,
    amount: 20000,
  );
  return household;
}

/// Pago al proveedor anterior a la regla del pagador (2026-10-26, piloto
/// X01): se escribe como quedó en las bases históricas, sin la validación
/// nueva, que exige el titular vinculado. Los pagos históricos se conservan.
Future<void> _legacyProviderPayment(
  AgroRepository repo, {
  required int purchase,
  required int payer,
  required int amount,
}) async {
  await (await repo.appDatabase.database).insert('provider_payments', {
    'purchase_id': purchase,
    'payer_person_id': payer,
    'payment_date': '2026-01-03T12:00:00.000Z',
    'amount_bob_minor': amount,
    'method': 'CASH',
  });
}

Future<List<Map<String, Object?>>> _accountRows(
  DatabaseExecutor db,
  int person,
) => db.query(
  'account_transactions',
  where: 'person_id=?',
  whereArgs: [person],
  orderBy: 'id',
);

void main() {
  sqfliteFfiInit();

  group('vincular al agricultor histórico ADMIN', () {
    test('base v7: exige confirmación; con ella conserva rol, persona y movimientos', () async {
      final (database, household) = await _historical(
        'admin_v7',
        _adminFarmerHousehold,
      );
      final db = await database.database;
      final store = OwnerBindingStore(database);
      expect(await store.origin(), InstallOrigin.legacyPrePolicy);
      final untouched = await dumpTables(db);

      await expectLater(
        store.bindExistingPerson(
          personId: household.titular,
          scope: memberA,
          installationRef: installationHere,
        ),
        throwsA(isA<OwnerAdministratorConfirmationRequired>()),
      );
      expect(await dumpTables(db), untouched);

      final settingsBefore = await settings(db);
      final binding = await store.bindExistingPerson(
        personId: household.titular,
        scope: memberA,
        installationRef: installationHere,
        confirmAdministrator: true,
      );
      expect(binding.personId, household.titular);
      expect(binding.ownerRole, PersonRole.admin);

      // Todo lo demás, fila por fila, igual: misma persona (rol ADMIN,
      // política MANUAL), mismas compras, lotes, movimientos, pagos y cuentas.
      expect(await dumpTables(db, except: _bindingTables), {
        for (final entry in untouched.entries)
          if (!_bindingTables.contains(entry.key)) entry.key: entry.value,
      });
      final people = await db.query('persons', orderBy: 'id');
      expect(people, hasLength(3), reason: 'no se duplica la persona');
      expect(
        people.firstWhere((p) => p['id'] == household.titular),
        allOf(
          containsPair('role', 'ADMIN'),
          containsPair('settlement_policy', 'MANUAL'),
        ),
      );
      expect(await settings(db), {
        ...settingsBefore,
        AppDatabase.activatedInstallationKey: installationHere,
      });
      final bindingRow = (await db.query('owner_bindings')).single;
      expect(bindingRow['person_id'], household.titular);
      expect(bindingRow['owner_role'], 'ADMIN');

      final state = classifyInstallation(
        await store.accessInputs(
          session: LocalSessionCondition.readable,
          sessionScope: memberA,
          currentInstallationRef: installationHere,
        ),
      );
      expect(state, InstallationAccessState.activated);
    });

    test('cambiar el titular a un ADMIN también exige confirmación', () async {
      final database = openDb(inMemoryDatabasePath);
      final household = await seedHousehold(AgroRepository(database));
      final admin = await household.repo.addPerson(
        name: 'Agricultor',
        role: PersonRole.admin,
      );
      final store = OwnerBindingStore(database);
      await store.bindExistingPerson(
        personId: household.titular,
        scope: memberA,
        installationRef: installationHere,
      );
      final db = await database.database;
      final before = await dumpTables(db);
      await expectLater(
        store.changeOwner(newPersonId: admin, sessionScope: memberA),
        throwsA(isA<OwnerAdministratorConfirmationRequired>()),
      );
      expect(await dumpTables(db), before);
      final next = await store.changeOwner(
        newPersonId: admin,
        sessionScope: memberA,
        confirmAdministrator: true,
      );
      expect(next.ownerRole, PersonRole.admin);
      final history = await store.history();
      expect(history.map((b) => (b.personId, b.ownerRole, b.isActive)), [
        (household.titular, PersonRole.family, false),
        (admin, PersonRole.admin, true),
      ]);
    });
  });

  group('el titular ADMIN completa sus operaciones', () {
    test('compartido: compra, aplica en su chaco, transfiere y paga; reglas de cobro intactas', () async {
      final (database, household) = await _historical(
        'admin_shared',
        _adminFarmerHousehold,
      );
      await OwnerBindingStore(database).bindExistingPerson(
        personId: household.titular,
        scope: memberA,
        installationRef: installationHere,
        confirmAdministrator: true,
      );
      final db = await database.database;
      final repo = household.repo;
      final farmer = household.titular;
      final son = household.relative;
      final neighbor = household.thirdParty;
      final peopleBefore = await db.query('persons', orderBy: 'id');
      final sonAccountBefore = await _accountRows(db, son);
      final neighborAccountBefore = await _accountRows(db, neighbor);
      expect(await stockByPersonProduct(db), {
        (farmer, household.product): 10000,
        (son, household.product): 11000,
        (neighbor, household.product): 5000,
      });

      // Los formularios lo ofrecen donde lo necesita (titular y modalidad
      // leídos de la base).
      Future<Set<Object?>> ids(PersonPurpose purpose) async => {
        for (final person in await repo.peopleFor(purpose)) person['id'],
      };
      expect(await repo.operatingContext(), (
        mode: OperationMode.shared,
        ownerPersonId: farmer,
      ));
      expect(await ids(PersonPurpose.applicator), {farmer, son, neighbor});
      expect(await ids(PersonPurpose.transferParty), {farmer, son, neighbor});
      expect(await ids(PersonPurpose.providerPayer), {farmer});
      expect(await ids(PersonPurpose.purchaseAllocation), {
        farmer,
        son,
        neighbor,
      });
      // Mismas filas, mismo orden y sin columnas añadidas por la consulta.
      expect(
        await repo.peopleFor(PersonPurpose.purchaseAllocation),
        await repo.people(),
      );

      final purchase = await household.buy(farmer, 2000);
      final application = await household.apply(
        farmer,
        household.titularFarm,
        3000,
      );
      await repo.transferProductFifo(
        fromPersonId: farmer,
        toPersonId: son,
        productId: household.product,
        quantityBase: 1000,
      );
      await repo.addProviderPayment(
        purchaseId: purchase,
        payerPersonId: farmer,
        amountBobMinor: 20000,
        method: PaymentMethod.cash,
      );

      expect(await stockByPersonProduct(db), {
        (farmer, household.product): 8000,
        (son, household.product): 12000,
        (neighbor, household.product): 5000,
      });
      // El consumo del titular tiene costo FIFO, pero su política MANUAL no
      // genera cargos: su cuenta sigue vacía; las de los demás no cambian.
      final applied = (await db.query(
        'applications',
        where: 'id=?',
        whereArgs: [application],
      )).single;
      expect(applied['person_id'], farmer);
      expect(applied['total_cost_bob_minor'], greaterThan(0));
      expect(await _accountRows(db, farmer), isEmpty);
      expect(await _accountRows(db, son), sonAccountBefore);
      expect(await _accountRows(db, neighbor), neighborAccountBefore);
      final allocation = (await db.rawQuery(
        '''SELECT a.* FROM purchase_allocations a
          JOIN purchase_items i ON i.id=a.purchase_item_id WHERE i.purchase_id=?''',
        [purchase],
      )).single;
      expect(allocation['person_id'], farmer);
      expect(allocation['charge_policy_snapshot'], 'MANUAL');
      // Sigue fuera de la liquidación y nadie cambió de rol ni se duplicó.
      expect((await repo.settlements()).map((row) => row['id']).toSet(), {
        son,
        neighbor,
      });
      expect(await db.query('persons', orderBy: 'id'), peopleBefore);
    });

    test('propio: un agricultor solo registrado como ADMIN compra, paga y aplica; no transfiere', () async {
      final (database, household) = await _historical(
        'admin_personal',
        _soloAdminFarmer,
      );
      await OwnerBindingStore(database).bindExistingPerson(
        personId: household.titular,
        scope: memberA,
        installationRef: installationHere,
        confirmAdministrator: true,
      );
      await OperationModeStore(database)
          .apply(OperationMode.personal, confirmed: true);
      final db = await database.database;
      final repo = household.repo;
      final farmer = household.titular;
      final spouse = await repo.addPerson(
        name: 'Esposa',
        role: PersonRole.family,
      );

      for (final purpose in PersonPurpose.values) {
        expect(
          {for (final person in await repo.peopleFor(purpose)) person['id']},
          purpose == PersonPurpose.transferParty ? isEmpty : {farmer},
          reason: purpose.name,
        );
      }

      final purchase = await household.buy(farmer, 1000);
      await repo.addProviderPayment(
        purchaseId: purchase,
        payerPersonId: farmer,
        amountBobMinor: 10000,
        method: PaymentMethod.cash,
      );
      await household.apply(farmer, household.titularFarm, 2000);
      final before = await dumpTables(db);
      await expectLater(
        repo.transferProductFifo(
          fromPersonId: farmer,
          toPersonId: spouse,
          productId: household.product,
          quantityBase: 100,
        ),
        throwsA(isA<PersonalModeRestrictionException>()),
      );
      await expectLater(
        household.buy(spouse, 100),
        throwsA(isA<PersonalModeRestrictionException>()),
      );
      expect(await dumpTables(db), before);
      expect(await stockByPersonProduct(db), {
        (farmer, household.product): 4000,
      });
      expect(await _accountRows(db, farmer), isEmpty);
      expect(
        (await db.query(
          'persons',
          columns: ['role'],
          where: 'id=?',
          whereArgs: [farmer],
        )).single['role'],
        'ADMIN',
      );
    });
  });

  group('papeles por formulario (titular, rol privado y modalidad)', () {
    test('compartido conserva las reglas por rol y suma al titular ADMIN', () {
      bool can(PersonPurpose purpose, PersonRole role, {bool owner = false}) =>
          canActAs(
            purpose,
            role: role,
            isOwner: owner,
            mode: OperationMode.shared,
          );
      // Un ADMIN que no es titular no aplica ni transfiere; desde la regla
      // del 2026-10-26 (piloto X01) tampoco paga: paga el titular.
      expect(can(PersonPurpose.providerPayer, PersonRole.admin), isFalse);
      expect(can(PersonPurpose.applicator, PersonRole.admin), isFalse);
      expect(can(PersonPurpose.transferParty, PersonRole.admin), isFalse);
      // El titular ADMIN, además, aplica y transfiere.
      expect(
        can(PersonPurpose.applicator, PersonRole.admin, owner: true),
        isTrue,
      );
      expect(
        can(PersonPurpose.transferParty, PersonRole.admin, owner: true),
        isTrue,
      );
      // El pago al proveedor es del titular, sea familiar o ADMIN.
      expect(
        can(PersonPurpose.providerPayer, PersonRole.family, owner: true),
        isTrue,
      );
      expect(
        can(PersonPurpose.providerPayer, PersonRole.admin, owner: true),
        isTrue,
      );
      for (final role in PersonRole.values) {
        expect(can(PersonPurpose.purchaseAllocation, role), isTrue);
        expect(can(PersonPurpose.farmOwner, role), isTrue);
      }
    });

    test('propio: sólo el titular, en todo salvo transferir', () {
      for (final purpose in PersonPurpose.values) {
        for (final role in PersonRole.values) {
          for (final owner in [false, true]) {
            expect(
              canActAs(
                purpose,
                role: role,
                isOwner: owner,
                mode: OperationMode.personal,
              ),
              owner && purpose != PersonPurpose.transferParty,
              reason: '${purpose.name} ${role.name} owner=$owner',
            );
          }
        }
      }
    });

    test('elegibilidad de titular por rol privado', () {
      expect(ownerEligibility(PersonRole.family), OwnerEligibility.eligible);
      expect(
        ownerEligibility(PersonRole.admin),
        OwnerEligibility.requiresAdministratorConfirmation,
      );
      expect(
        ownerEligibility(PersonRole.thirdParty),
        OwnerEligibility.notEligible,
      );
    });
  });
}
