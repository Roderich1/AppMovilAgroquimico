// Carrera entre una escritura y el paso a modo propio (RF-06, CU-05 E1).
//
// Reproducido sobre b90c628: la escritura leía la modalidad fuera de su
// transacción, el cambio de modalidad se confirmaba entre esa lectura y la
// escritura, y terminaban confirmadas las dos: modo propio con existencias de
// un tercero. Ahora el contexto se lee dentro de la transacción que escribe, y
// el cambio de modalidad evalúa y escribe en la suya; SQLite las serializa.
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';

Future<bool> _succeeded(Future<Object?> future) =>
    future.then((_) => true, onError: (Object _) => false);

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late Household household;
  late OperationModeStore modes;

  setUp(() async {
    database = openDb(await tempDbPath('race'));
    household = await seedHousehold(AgroRepository(database));
    // El titular tiene existencias propias (no bloquean el paso a propio).
    await household.buy(household.titular, 5000);
    await OwnerBindingStore(database).bindExistingPerson(
      personId: household.titular,
      scope: memberA,
      installationRef: installationHere,
    );
    modes = OperationModeStore(database);
  });

  // Escrituras que, confirmadas, dejan actividad activa de otra persona.
  Map<String, Future<Object?> Function()> thirdPartyWrites() {
    final repo = household.repo;
    return {
      'compra asignada a un tercero': () =>
          household.buy(household.thirdParty, 1000),
      'transferencia a un familiar': () => repo.transferProductFifo(
        fromPersonId: household.titular,
        toPersonId: household.relative,
        productId: household.product,
        quantityBase: 1000,
      ),
      'plan en el chaco de un familiar': () => repo.addPlan(
        farmId: household.relativeFarm,
        campaignId: household.campaign,
        productId: household.product,
        areaM2: 100,
        doseBasePerHa: 10,
      ),
      'pago de cuenta de un familiar': () => repo.addAccountPayment(
        personId: household.relative,
        amountBobMinor: 100,
      ),
    };
  }

  for (final writeFirst in [true, false]) {
    final order = writeFirst ? 'escritura primero' : 'modalidad primero';
    for (final name in [
      'compra asignada a un tercero',
      'transferencia a un familiar',
      'plan en el chaco de un familiar',
      'pago de cuenta de un familiar',
    ]) {
      test('$name concurrente con el paso a propio ($order)', () async {
        final write = thirdPartyWrites()[name]!;
        Future<bool> toPersonal() =>
            _succeeded(modes.apply(OperationMode.personal, confirmed: true));
        final results = writeFirst
            ? await Future.wait([_succeeded(write()), toPersonal()])
            : (await Future.wait([toPersonal(), _succeeded(write())])).reversed
                  .toList();
        final (wrote, changed) = (results[0], results[1]);

        expect(
          wrote && changed,
          isFalse,
          reason: 'no pueden confirmarse las dos',
        );
        expect(wrote || changed, isTrue, reason: 'una de las dos se confirma');
        final db = await database.database;
        final mode = await modes.current();
        final activity = await OperationModeStore.thirdPartyActivity(
          db,
          household.titular,
        );
        expect(mode, changed ? OperationMode.personal : OperationMode.shared);
        if (mode == OperationMode.personal) {
          expect(activity.isEmpty, isTrue, reason: 'modo propio sin terceros');
        }
      });
    }
  }

  test('una compra iniciada en propio se rechaza aunque el paso a compartido se confirme a la vez', () async {
    await modes.apply(OperationMode.personal, confirmed: true);
    final db = await database.database;
    final results = await Future.wait([
      _succeeded(household.buy(household.thirdParty, 1000)),
      _succeeded(modes.apply(OperationMode.shared, confirmed: true)),
    ]);
    // Sea cual sea el orden, nunca queda una asignación a un tercero hecha
    // con un contexto de modo propio que ya no rige, ni al revés.
    final thirdPartyStock = (await stockByPersonProduct(
      db,
    ))[(household.thirdParty, household.product)];
    expect(results[1], isTrue);
    expect(results[0], thirdPartyStock == 1000);
    expect(await modes.current(), OperationMode.shared);
    expect(
      await db.query(
        'purchase_allocations',
        where: 'person_id=?',
        whereArgs: [household.thirdParty],
      ),
      hasLength(results[0] ? 1 : 0),
    );
  });
}
