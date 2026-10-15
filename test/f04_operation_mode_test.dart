// MODE-01 (#24) y MODE-04 (#27): modalidad persistida y transiciones seguras
// (RF-06, CU-05, RN-17). Se comparan volcados completos, no conteos.
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';

void main() {
  sqfliteFfiInit();

  const businessOnly = {'app_settings'};

  Future<
    ({AppDatabase database, Household household, OperationModeStore modes})
  >
  boundHousehold(String path) async {
    final database = openDb(path);
    final repo = AgroRepository(database);
    final household = await seedHousehold(repo);
    await OwnerBindingStore(database).bindExistingPerson(
      personId: household.titular,
      scope: memberA,
      installationRef: installationHere,
    );
    return (
      database: database,
      household: household,
      modes: OperationModeStore(database),
    );
  }

  group('MODE-01: persistencia', () {
    test('una base nueva y una migrada leen SHARED por defecto', () async {
      expect(
        await OperationModeStore(openDb(inMemoryDatabasePath)).current(),
        OperationMode.shared,
      );
      final path = await tempDbPath('migrada');
      await openDb(path).database.then((db) => db.close());
      await downgradeToV7(path);
      expect(
        await OperationModeStore(openDb(path)).current(),
        OperationMode.shared,
      );
    });

    test('la modalidad elegida sobrevive a cerrar y reabrir la base', () async {
      final path = await tempDbPath('persistencia');
      final s = await boundHousehold(path);
      await s.modes.apply(OperationMode.personal, confirmed: true);
      await s.database.close();
      expect(
        await OperationModeStore(openDb(path)).current(),
        OperationMode.personal,
      );
    });

    test('sin confirmación explícita no cambia nada', () async {
      final s = await boundHousehold(inMemoryDatabasePath);
      final db = await s.database.database;
      final before = await dumpTables(db);
      await expectLater(
        s.modes.apply(OperationMode.personal, confirmed: false),
        throwsA(isA<ModeTransitionException>()),
      );
      expect(await dumpTables(db), before);
    });
  });

  group('MODE-04: SHARED → PERSONAL', () {
    test('sin titular vinculado se bloquea', () async {
      final database = openDb(inMemoryDatabasePath);
      await seedHousehold(AgroRepository(database));
      final decision = await OperationModeStore(database)
          .evaluate(OperationMode.personal);
      expect(decision.allowed, isFalse);
      expect(decision.blocks, contains(ModeTransitionBlock.ownerRequired));
    });

    test(
      'con existencias de un tercero se bloquea, lo muestra y no toca datos',
      () async {
        final s = await boundHousehold(inMemoryDatabasePath);
        final h = s.household;
        await h.buy(h.titular, 10000);
        await h.buy(h.thirdParty, 4000);
        final db = await s.database.database;
        final before = await dumpTables(db);

        final decision = await s.modes.evaluate(OperationMode.personal);
        expect(decision.allowed, isFalse);
        expect(decision.blocks, {ModeTransitionBlock.thirdPartyActivity});
        expect(decision.activity.personsWithStock, {h.thirdParty});
        // El tercero también debe la compra asignada: saldo pendiente.
        expect(
          decision.activity.personsWithAccountBalance,
          contains(h.thirdParty),
        );

        await expectLater(
          s.modes.apply(OperationMode.personal, confirmed: true),
          throwsA(
            isA<ModeTransitionException>().having(
              (e) => e.decision?.activity.personsWithStock,
              'personas con existencias',
              {h.thirdParty},
            ),
          ),
        );
        expect(await dumpTables(db), before);
        expect(await s.modes.current(), OperationMode.shared);
      },
    );

    test('un plan abierto en el chaco de otro familiar bloquea', () async {
      final s = await boundHousehold(inMemoryDatabasePath);
      final h = s.household;
      final plan = await h.repo.addPlan(
        farmId: h.relativeFarm,
        campaignId: h.campaign,
        productId: h.product,
        areaM2: 5000,
        doseBasePerHa: 1000,
      );
      final decision = await s.modes.evaluate(OperationMode.personal);
      expect(decision.activity.openPlanIds, {plan});
      expect(decision.allowed, isFalse);
    });

    test('tras resolver explícitamente lo de terceros, la transición se admite y conserva todo', () async {
      final s = await boundHousehold(inMemoryDatabasePath);
      final h = s.household;
      await h.buy(h.titular, 10000);
      await h.buy(h.relative, 3000);
      // La hermana usa todo su producto y paga su cuenta: ya no hay
      // información activa suya, aunque su historial siga ahí.
      await h.apply(h.relative, h.relativeFarm, 3000);
      final db = await s.database.database;
      final debt =
          (await db.rawQuery(
                'SELECT SUM(amount_bob_minor_signed) s FROM account_transactions WHERE person_id=?',
                [h.relative],
              )).single['s']!
              as int;
      if (debt != 0) {
        await h.repo.addAccountPayment(
          personId: h.relative,
          campaignId: h.campaign,
          amountBobMinor: debt,
        );
      }
      expect(
        (await s.modes.evaluate(OperationMode.personal)).allowed,
        isTrue,
        reason: 'sin existencias, planes ni saldos de terceros',
      );
      final business = await dumpTables(db, except: businessOnly);
      final stock = await stockByPersonProduct(db);

      await s.modes.apply(OperationMode.personal, confirmed: true);

      expect(await s.modes.current(), OperationMode.personal);
      expect(await dumpTables(db, except: businessOnly), business);
      expect(await stockByPersonProduct(db), stock);
      expect(
        (await settings(db)).keys,
        containsAll([
          AppDatabase.operationModeKey,
          AppDatabase.operationModeChangedAtKey,
        ]),
      );
    });
  });

  group('MODE-04: PERSONAL → SHARED e ida y vuelta', () {
    test(
      'PERSONAL → SHARED conserva el historial asociado al titular',
      () async {
        final s = await boundHousehold(inMemoryDatabasePath);
        final h = s.household;
        await s.modes.apply(OperationMode.personal, confirmed: true);
        await h.buy(h.titular, 8000);
        await h.apply(h.titular, h.titularFarm, 2000);
        final db = await s.database.database;
        final business = await dumpTables(db, except: businessOnly);
        final stock = await stockByPersonProduct(db);

        final decision = await s.modes.apply(
          OperationMode.shared,
          confirmed: true,
        );
        expect(decision.allowed, isTrue);
        expect(await dumpTables(db, except: businessOnly), business);
        expect(await stockByPersonProduct(db), stock);
        expect(stock, {(h.titular, h.product): 6000});
      },
    );

    test('SHARED → PERSONAL → SHARED deja cada tabla idéntica, con sus propietarios y cantidades', () async {
      final s = await boundHousehold(inMemoryDatabasePath);
      final h = s.household;
      await h.buy(h.titular, 9000);
      await h.apply(h.titular, h.titularFarm, 1000);
      final db = await s.database.database;
      final business = await dumpTables(db, except: businessOnly);
      await s.modes.apply(OperationMode.personal, confirmed: true);
      await s.modes.apply(OperationMode.shared, confirmed: true);
      expect(await dumpTables(db, except: businessOnly), business);
      expect(await s.modes.current(), OperationMode.shared);
    });
  });

  test(
    'una transición que falla a mitad de la escritura no deja efectos',
    () async {
      final s = await boundHousehold(inMemoryDatabasePath);
      final db = await s.database.database;
      final before = await dumpTables(db);
      await expectLater(
        s.modes.apply(
          OperationMode.personal,
          confirmed: true,
          afterWrite: (_) async => throw StateError('corte simulado'),
        ),
        throwsA(isA<StateError>()),
      );
      expect(await dumpTables(db), before);
      expect(await s.modes.current(), OperationMode.shared);
    },
  );
}
