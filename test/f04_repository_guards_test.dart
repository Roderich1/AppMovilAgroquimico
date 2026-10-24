// Guardas de dominio en AgroRepository: la política de activación y el modo
// propio se aplican en el repositorio, no sólo ocultando controles.
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/farmer_operation_gate.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/domain/installation_access.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';

void main() {
  sqfliteFfiInit();

  group('compuerta de activación', () {
    late AppDatabase database;
    late Household household;
    late int purchase;
    late int application;
    late int transfer;
    var state = InstallationAccessState.activated;

    setUp(() async {
      state = InstallationAccessState.activated;
      database = openDb(inMemoryDatabasePath);
      final repo = AgroRepository(
        database,
        gate: FarmerOperationGate(() => state),
      );
      household = await seedHousehold(repo);
      purchase = await household.buy(household.titular, 10000);
      application = await household.apply(
        household.titular,
        household.titularFarm,
        1000,
      );
      transfer = await repo.transferProductFifo(
        fromPersonId: household.titular,
        toPersonId: household.relative,
        productId: household.product,
        quantityBase: 500,
      );
    });

    // Una llamada por cada escritura pública del repositorio.
    Map<String, Future<Object?> Function()> writes() {
      final repo = household.repo;
      return {
        'addPerson': () => repo.addPerson(name: 'X', role: PersonRole.family),
        'addFarm': () =>
            repo.addFarm(ownerId: household.titular, name: 'X', areaM2: 1),
        'addCampaign': () =>
            repo.addCampaign(name: 'X', start: DateTime.utc(2027)),
        'activateCampaign': () => repo.activateCampaign(household.campaign),
        'closeCampaign': () => repo.closeCampaign(household.campaign),
        'addProduct': () => repo.addProduct(name: 'X'),
        'addSupplier': () => repo.addSupplier(name: 'X'),
        'addPlan': () => repo.addPlan(
          farmId: household.titularFarm,
          campaignId: household.campaign,
          productId: household.product,
          areaM2: 100,
          doseBasePerHa: 10,
        ),
        'addPlanMulti': () => repo.addPlanMulti(
          farmId: household.titularFarm,
          campaignId: household.campaign,
          areaM2: 100,
          items: [
            PlanItemDraft(productId: household.product, doseBasePerHa: 10),
          ],
        ),
        'confirmPurchase': () => household.buy(household.titular, 1),
        'addProviderPayment': () => repo.addProviderPayment(
          purchaseId: purchase,
          payerPersonId: household.titular,
          amountBobMinor: 1,
          method: 'CASH',
        ),
        'confirmApplication': () =>
            household.apply(household.titular, household.titularFarm, 1),
        'addAccountPayment': () => repo.addAccountPayment(
          personId: household.titular,
          amountBobMinor: 1,
        ),
        'reverseApplication': () => repo.reverseApplicationUnauditedForTesting(application),
        'reversePurchase': () => repo.reversePurchaseUnauditedForTesting(purchase),
        'transferStock': () => repo.transferStock(
          sourceLotId: 1,
          destinationPersonId: household.relative,
          quantityBase: 1,
        ),
        'transferProductFifo': () => repo.transferProductFifo(
          fromPersonId: household.titular,
          toPersonId: household.relative,
          productId: household.product,
          quantityBase: 1,
        ),
        'transferProductsFifo': () => repo.transferProductsFifo(
          fromPersonId: household.titular,
          toPersonId: household.relative,
          items: [
            TransferItemDraft(productId: household.product, quantityBase: 1),
          ],
        ),
        'reverseTransfer': () => repo.reverseTransferUnauditedForTesting(transfer),
        'renameCatalog': () =>
            repo.renameCatalog('products', household.product, 'Y'),
        'archiveCatalog': () =>
            repo.archiveCatalog('suppliers', household.supplier),
        'storeInvoiceImage': () => repo.storeInvoiceImage('no-existe.jpg'),
      };
    }

    for (final blocked in InstallationAccessState.values.where(
      (s) => !s.allowsFarmerOperations,
    )) {
      test(
        '${blocked.name}: toda escritura se rechaza y la base no cambia',
        () async {
          final db = await database.database;
          final before = await dumpTables(db);
          state = blocked;
          for (final entry in writes().entries) {
            await expectLater(
              entry.value(),
              throwsA(isA<FarmerOperationBlockedException>()),
              reason: entry.key,
            );
          }
          expect(await dumpTables(db), before);
        },
      );
    }

    for (final allowed in InstallationAccessState.values.where(
      (s) => s.allowsFarmerOperations,
    )) {
      test('${allowed.name}: la compuerta deja pasar las escrituras', () async {
        state = allowed;
        await household.repo.addProduct(name: 'Atrazina');
        await household.buy(household.titular, 2000);
      });
    }

    test('la lectura sigue disponible con la compuerta cerrada', () async {
      state = InstallationAccessState.newRequiresActivation;
      expect(
        await household.repo.personStockSummary(household.titular),
        isNotEmpty,
      );
    });
  });

  group('guardas del modo propio', () {
    late AppDatabase database;
    late Household household;

    setUp(() async {
      database = openDb(inMemoryDatabasePath);
      household = await seedHousehold(AgroRepository(database));
      await household.buy(household.titular, 10000);
      await OwnerBindingStore(database).bindExistingPerson(
        personId: household.titular,
        scope: memberA,
        installationRef: installationHere,
      );
      await OperationModeStore(database)
          .apply(OperationMode.personal, confirmed: true);
    });

    Future<void> rejectedWithoutChanges(Future<Object?> Function() call) async {
      final db = await database.database;
      final before = await dumpTables(db);
      await expectLater(
        call(),
        throwsA(isA<PersonalModeRestrictionException>()),
      );
      expect(await dumpTables(db), before);
    }

    test(
      'compra asignada a otra persona',
      () =>
          rejectedWithoutChanges(() => household.buy(household.relative, 100)),
    );

    test('aplicación de otra persona o en el chaco de otra persona', () async {
      await rejectedWithoutChanges(
        () => household.apply(household.relative, household.titularFarm, 100),
      );
      await rejectedWithoutChanges(
        () => household.apply(household.titular, household.relativeFarm, 100),
      );
    });

    test(
      'las tres rutas de transferencia, aunque la interfaz las oculte',
      () async {
        final repo = household.repo;
        await rejectedWithoutChanges(
          () => repo.transferProductFifo(
            fromPersonId: household.titular,
            toPersonId: household.relative,
            productId: household.product,
            quantityBase: 100,
          ),
        );
        await rejectedWithoutChanges(
          () => repo.transferProductsFifo(
            fromPersonId: household.titular,
            toPersonId: household.relative,
            items: [
              TransferItemDraft(
                productId: household.product,
                quantityBase: 100,
              ),
            ],
          ),
        );
        await rejectedWithoutChanges(
          () => repo.transferStock(
            sourceLotId: 1,
            destinationPersonId: household.relative,
            quantityBase: 100,
          ),
        );
      },
    );

    test('pago al proveedor registrado por otra persona', () async {
      final repo = household.repo;
      final purchase = (await repo.purchases()).single['id']! as int;
      await rejectedWithoutChanges(
        () => repo.addProviderPayment(
          purchaseId: purchase,
          payerPersonId: household.relative,
          amountBobMinor: 100,
          method: 'CASH',
        ),
      );
      // El titular sí registra su pago, aunque sea familiar y no ADMIN.
      await repo.addProviderPayment(
        purchaseId: purchase,
        payerPersonId: household.titular,
        amountBobMinor: 100,
        method: 'CASH',
      );
    });

    test('chaco, plan y pago de cuenta de otra persona', () async {
      final repo = household.repo;
      await rejectedWithoutChanges(
        () => repo.addFarm(ownerId: household.relative, name: 'X', areaM2: 1),
      );
      await rejectedWithoutChanges(
        () => repo.addPlan(
          farmId: household.relativeFarm,
          campaignId: household.campaign,
          productId: household.product,
          areaM2: 100,
          doseBasePerHa: 10,
        ),
      );
      await rejectedWithoutChanges(
        () => repo.addAccountPayment(
          personId: household.relative,
          amountBobMinor: 100,
        ),
      );
    });

    test('el titular opera con normalidad en modo propio', () async {
      final db = await database.database;
      await household.buy(household.titular, 500);
      await household.apply(household.titular, household.titularFarm, 1500);
      expect(await stockByPersonProduct(db), {
        (household.titular, household.product): 9000,
      });
    });

    test('el titular vinculado no se puede archivar en ningún modo', () async {
      await expectLater(
        household.repo.archiveCatalog('persons', household.titular),
        throwsA(isA<BusinessRuleException>()),
      );
      await OperationModeStore(database)
          .apply(OperationMode.shared, confirmed: true);
      await expectLater(
        household.repo.archiveCatalog('persons', household.titular),
        throwsA(isA<BusinessRuleException>()),
      );
    });
  });

  test('modo propio sin titular (estado incoherente) falla cerrado', () async {
    final database = openDb(inMemoryDatabasePath);
    final repo = AgroRepository(database);
    final household = await seedHousehold(repo);
    final db = await database.database;
    await db.insert('app_settings', {
      'key': AppDatabase.operationModeKey,
      'value': OperationMode.personal.code,
    });
    await expectLater(
      household.buy(household.titular, 100),
      throwsA(isA<PersonalModeRestrictionException>()),
    );
  });
}
