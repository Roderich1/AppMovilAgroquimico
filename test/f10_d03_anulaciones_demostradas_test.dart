// D-03, decisión del autor (Roderich Rendón) del 2026-10-28: la bitácora
// conserva la operación, la reversión y sus fechas reales; la proyección
// histórica (`_lotHistoryAt`, compartida por la aplicación con fecha pasada
// y la operación tardía de RF-03) neutraliza el par sólo cuando el vínculo de
// anulación está demostrado (contrato F04 §2.6). Sin duplicar existencias,
// con el saldo de hoy como tope, sin reescribir nada y sin PIN para permitir
// existencias insuficientes. RN-25, RN-26, RF-03, RF-13, CU-09.
//
// Pruebas de HOST (sqflite_common_ffi). Sin dispositivo ni personas. Usan el
// reloj real: los días de octubre de 2026 y de 2025 son pasados.
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/services/auth/local_owner_credential.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/d03_dump.dart';
import 'support/f04_app_access.dart';
import 'support/f04_mode_fixtures.dart';
import 'support/f04_owner_pin.dart';

const _tail =
    'Una aplicación con fecha pasada sólo puede usar lo que esa persona ya '
    'tenía ese día y no se usó después: no cuenta el producto comprado o '
    'recibido más tarde. Revise la fecha o la cantidad. No se registró nada.';

/// Se leen los campos por `dynamic` para que el archivo compile también
/// contra el `lib/` de la base.
Matcher historical({
  required String day,
  required int held,
  required int available,
  required int requested,
  required String message,
}) => throwsA(
  isA<BusinessRuleException>()
      .having((e) => e.message, 'message', message)
      .having((e) => '${e.runtimeType}', 'type', 'HistoricalStockException')
      .having((e) => (e as dynamic).day, 'day', day)
      .having((e) => (e as dynamic).heldBase, 'heldBase', held)
      .having((e) => (e as dynamic).availableBase, 'availableBase', available)
      .having((e) => (e as dynamic).requestedBase, 'requestedBase', requested),
);

DateTime oct(int day) => DateTime(2026, 10, day);

/// Titular y hermana (familiares), Bellator, una campaña activa desde el
/// 01/10/2026 y un chaco por persona.
class Home {
  Home(this.database, this.repo);
  final AppDatabase database;
  final AgroRepository repo;
  late int titular;
  late int sister;
  late int supplier;
  late int campaign;
  late int bellator;
  late int farm;
  late int sisterFarm;

  Future<Database> get db => database.database;

  Future<int> buy(int person, int quantity, DateTime at) =>
      repo.confirmPurchase(
        PurchaseDraft(
          supplierId: supplier,
          campaignId: campaign,
          purchaseDate: at,
          items: [
            PurchaseItemDraft(
              productId: bellator,
              quantityBase: quantity,
              currency: CurrencyCode.bob,
              originalUnitPriceMinor: 10000,
              allocations: [
                AllocationDraft(personId: person, quantityBase: quantity),
              ],
            ),
          ],
        ),
      );

  Future<int> apply(int quantity, DateTime at, {int? person}) =>
      repo.confirmApplication(
        ApplicationDraft(
          personId: person ?? titular,
          farmId: person == sister ? sisterFarm : farm,
          campaignId: campaign,
          appliedAt: at,
          lines: [
            ApplicationLineDraft(productId: bellator, quantityBase: quantity),
          ],
        ),
      );

  Future<int> lotOf(int person, {int index = 0}) async =>
      (await (await db).query(
            'inventory_lots',
            where: 'owner_person_id=? AND product_id=?',
            whereArgs: [person, bellator],
            orderBy: 'id',
          ))[index]['id']!
          as int;

  Future<int> balance(int lot) async =>
      Sqflite.firstIntValue(
        await (await db).rawQuery(
          'SELECT SUM(quantity_signed) FROM inventory_movements WHERE lot_id=?',
          [lot],
        ),
      ) ??
      0;

  Future<Map<int, int>> consumed(int application) async => {
    for (final row in await (await db).rawQuery(
      '''SELECT c.inventory_lot_id lot, c.quantity_consumed_base q
        FROM application_consumptions c
        JOIN application_items i ON i.id=c.application_item_id
        WHERE i.application_id=? ORDER BY c.id''',
      [application],
    ))
      row['lot']! as int: row['q']! as int,
  };
}

Future<Home> home(String name) async {
  final database = openDb(await tempDbPath(name));
  final h = Home(database, AgroRepository(database));
  final repo = h.repo;
  h
    ..titular = await repo.addPerson(name: 'Titular', role: PersonRole.family)
    ..sister = await repo.addPerson(name: 'Hermana', role: PersonRole.family)
    ..supplier = await repo.addSupplier(name: 'Proveedor')
    ..bellator = await repo.addProduct(name: 'Bellator')
    ..campaign = await repo.addCampaign(
      name: 'Invierno',
      start: DateTime(2026, 10, 1),
    );
  h
    ..farm = await repo.addFarm(
      ownerId: h.titular,
      name: 'Chaco titular',
      areaM2: 10000,
    )
    ..sisterFarm = await repo.addFarm(
      ownerId: h.sister,
      name: 'Chaco hermana',
      areaM2: 10000,
    );
  return h;
}

/// 1 L el 10/10 y una aplicación de todo el litro el 15/10, revertida hoy
/// (por error). Devuelve la aplicación revertida.
Future<int> reversedApplication(Home h) async {
  await h.buy(h.titular, 1000, oct(10));
  final reversed = await h.apply(1000, oct(15));
  await h.repo.reverseApplicationUnauditedForTesting(reversed, reason: 'Error');
  return reversed;
}

void main() {
  sqfliteFfiInit();

  group('aplicación revertida', () {
    test('con el vínculo demostrado, lo anulado no cuenta: 0,5 L el 12/10 se '
        'aceptan y la base sólo gana las filas nuevas', () async {
      final h = await home('d03n-control');
      await reversedApplication(h);
      final lot = await h.lotOf(h.titular);
      final before = await dumpTables(await h.db);
      final id = await h.apply(500, oct(12));
      expect(await h.consumed(id), {lot: 500});
      expectOnlyApplicationRows(before, await dumpTables(await h.db), id);
      expect(await h.balance(lot), 500);
    });

    test('la ruta de hoy no cambia: usa el saldo actual', () async {
      final h = await home('d03n-hoy');
      await reversedApplication(h);
      final lot = await h.lotOf(h.titular);
      final id = await h.apply(1000, DateTime.now());
      expect(await h.consumed(id), {lot: 1000});
      expect(await h.balance(lot), 0);
    });

    test('sin disponibilidad duplicada: el mínimo de los saldos posteriores '
        'limita el cupo a lo que queda hoy; lo devuelto que ya usó una '
        'aplicación de hoy no vuelve a contar', () async {
      final h = await home('d03n-duplicado');
      await reversedApplication(h);
      final lot = await h.lotOf(h.titular);
      // Hoy se usan 0,6 L del litro devuelto: quedan 0,4 L.
      await h.apply(600, DateTime.now());
      expect(await h.balance(lot), 400);
      final before = await dumpTables(await h.db);
      await expectLater(
        h.apply(500, oct(12)),
        historical(
          day: '2026-10-12',
          held: 1000,
          available: 400,
          requested: 500,
          message:
              'Bellator: el 12/10/2026 esa persona tenía 1 L; de eso quedan '
              '0,4 L sin usar en operaciones posteriores; pidió 0,5 L. $_tail',
        ),
      );
      expect(await dumpTables(await h.db), before);
      // Hasta el saldo de hoy, sí.
      final id = await h.apply(400, oct(12));
      expect(await h.consumed(id), {lot: 400});
      expectOnlyApplicationRows(before, await dumpTables(await h.db), id);
      expect(await h.balance(lot), 0);
    });

    // Cada variante rompe una condición del vínculo (datos manipulados a
    // mano, como podría dejarlos una base inconsistente). Ninguna neutraliza:
    // el 12/10 quedan 0 L de 1 L, como sin la decisión del 2026-10-28.
    final Map<String, Future<void> Function(Home h, int reversed)> broken = {
      'falta la marca reversed_at de la aplicación': (h, reversed) async =>
          (await h.db).update(
            'applications',
            {'reversed_at': null},
            where: 'id=?',
            whereArgs: [reversed],
          ),
      'la referencia de la reversión no coincide': (h, reversed) async =>
          (await h.db).update(
            'inventory_movements',
            {'reference_id': reversed + 1000},
            where: "type='APPLICATION_REVERSAL' AND reference_id=?",
            whereArgs: [reversed],
          ),
      'la cantidad de la reversión no coincide': (h, reversed) async =>
          (await h.db).update(
            'inventory_movements',
            {'quantity_signed': 900},
            where: "type='APPLICATION_REVERSAL' AND reference_id=?",
            whereArgs: [reversed],
          ),
      'la reversión está en otro lote': (h, reversed) async {
        // Otro lote del titular, adquirido el 13/10 (no elegible el 12/10).
        await h.buy(h.titular, 1000, oct(13));
        final other = await h.lotOf(h.titular, index: 1);
        await (await h.db).update(
          'inventory_movements',
          {'lot_id': other},
          where: "type='APPLICATION_REVERSAL' AND reference_id=?",
          whereArgs: [reversed],
        );
      },
      // Condición 5, aislada de la 4: los movimientos siguen opuestos e
      // iguales, pero el consumo de la aplicación en ese lote no cuadra.
      'el consumo tiene otra cantidad (q)': (h, reversed) async =>
          (await h.db).rawUpdate(
            '''UPDATE application_consumptions SET quantity_consumed_base=900
            WHERE application_item_id IN
              (SELECT id FROM application_items WHERE application_id=?)''',
            [reversed],
          ),
      'el consumo no está revertido (r)': (h, reversed) async =>
          (await h.db).rawUpdate(
            '''UPDATE application_consumptions SET reversed_at=NULL
            WHERE application_item_id IN
              (SELECT id FROM application_items WHERE application_id=?)''',
            [reversed],
          ),
    };
    for (final entry in broken.entries) {
      test('sin vínculo demostrado no se neutraliza nada: ${entry.key}', () async {
        final h = await home('d03n-${entry.key.hashCode}');
        final reversed = await reversedApplication(h);
        await entry.value(h, reversed);
        final before = await dumpTables(await h.db);
        await expectLater(
          h.apply(500, oct(12)),
          historical(
            day: '2026-10-12',
            held: 1000,
            available: 0,
            requested: 500,
            message:
                'Bellator: el 12/10/2026 esa persona tenía 1 L; de eso quedan '
                '0 L sin usar en operaciones posteriores; pidió 0,5 L. $_tail',
          ),
        );
        expect(await dumpTables(await h.db), before);
      });
    }
  });

  test('otro lote elegible en la fecha: la reversión movida a él no se '
      'empareja con la salida del primer lote ni aporta un par', () async {
    final h = await home('d03n-otro-lote-elegible');
    final reversed = await reversedApplication(h);
    // Un segundo lote del titular, adquirido el 11/10: elegible el 12/10.
    await h.buy(h.titular, 1000, oct(11));
    final first = await h.lotOf(h.titular);
    final other = await h.lotOf(h.titular, index: 1);
    await (await h.db).update(
      'inventory_movements',
      {'lot_id': other},
      where: "type='APPLICATION_REVERSAL' AND reference_id=?",
      whereArgs: [reversed],
    );
    final before = await dumpTables(await h.db);
    // El primer lote: 1 L el 12/10 y 0 L después (la salida del 15/10 queda
    // sin par). El segundo: 1 L el 12/10 y 2 L hoy (la reversión movida no
    // tiene salida en ese lote). Cupo 0 + 1 L.
    await expectLater(
      h.apply(1500, oct(12)),
      historical(
        day: '2026-10-12',
        held: 2000,
        available: 1000,
        requested: 1500,
        message:
            'Bellator: el 12/10/2026 esa persona tenía 2 L; de eso quedan '
            '1 L sin usar en operaciones posteriores; pidió 1,5 L. $_tail',
      ),
    );
    expect(await dumpTables(await h.db), before);
    final id = await h.apply(1000, oct(12));
    expect(await h.consumed(id), {other: 1000});
    expect(await h.balance(first), 0);
  });

  test('transferencia revertida: el lote de origen recupera la cantidad en la '
      'historia y el lote de destino no aporta', () async {
    final h = await home('d03n-pase');
    await h.buy(h.titular, 1000, oct(10));
    final source = await h.lotOf(h.titular);
    final transfer = await h.repo.transferProductFifo(
      fromPersonId: h.titular,
      toPersonId: h.sister,
      productId: h.bellator,
      quantityBase: 600,
      date: oct(15),
    );
    await h.repo.reverseTransferUnauditedForTesting(
      transfer,
      reason: 'Equivocado',
    );
    final before = await dumpTables(await h.db);
    // La hermana: su lote recibido quedó anulado y no aporta.
    await expectLater(
      h.apply(100, oct(18), person: h.sister),
      historical(
        day: '2026-10-18',
        held: 0,
        available: 0,
        requested: 100,
        message:
            'Bellator: el 18/10/2026 esa persona no tenía este producto; '
            'pidió 0,1 L. $_tail',
      ),
    );
    expect(await dumpTables(await h.db), before);
    // El titular: el 18/10 cuenta el litro entero.
    final id = await h.apply(1000, oct(18));
    expect(await h.consumed(id), {source: 1000});
    expectOnlyApplicationRows(before, await dumpTables(await h.db), id);
    expect(await h.balance(source), 0);
  });

  test('pase de dos lotes revertido y 0,5 L usados hoy: el 16/10 el cupo es '
      '0 + 0,5 L, sin duplicar', () async {
    final h = await home('d03n-pase-dos-lotes');
    await h.buy(h.titular, 400, oct(10));
    await h.buy(h.titular, 600, oct(11));
    final l1 = await h.lotOf(h.titular);
    final l2 = await h.lotOf(h.titular, index: 1);
    final transfer = await h.repo.transferProductFifo(
      fromPersonId: h.titular,
      toPersonId: h.sister,
      productId: h.bellator,
      quantityBase: 1000,
      date: oct(15),
    );
    await h.repo.reverseTransferUnauditedForTesting(
      transfer,
      reason: 'Equivocado',
    );
    // Hoy: 0,4 L del lote del 10/10 y 0,1 L del lote del 11/10.
    final today = await h.apply(500, DateTime.now());
    expect(await h.consumed(today), {l1: 400, l2: 100});
    final before = await dumpTables(await h.db);
    await expectLater(
      h.apply(1000, oct(16)),
      historical(
        day: '2026-10-16',
        held: 1000,
        available: 500,
        requested: 1000,
        message:
            'Bellator: el 16/10/2026 esa persona tenía 1 L; de eso quedan '
            '0,5 L sin usar en operaciones posteriores; pidió 1 L. $_tail',
      ),
    );
    expect(await dumpTables(await h.db), before);
    final id = await h.apply(500, oct(16));
    expect(await h.consumed(id), {l2: 500});
    expectOnlyApplicationRows(before, await dumpTables(await h.db), id);
  });

  // Casos negativos de transferencia, con datos manipulados a mano: ninguno
  // neutraliza el par. El 18/10 el titular tenía 0,4 L (salió 0,6 L el 15/10)
  // y hoy 1 L, así que quedan 0,4 L.
  final Map<String, Future<void> Function(Home h, int transfer)>
  brokenTransfers = {
    'el lote de destino no está anulado': (h, transfer) async =>
        (await h.db).rawUpdate(
          '''UPDATE inventory_lots SET reversed_at=NULL WHERE id IN
          (SELECT destination_lot_id FROM transfer_lot_items
           WHERE transfer_id=?)''',
          [transfer],
        ),
    'la transferencia no está en REVERSED': (h, transfer) async =>
        (await h.db).update(
          'transfers',
          {'status': 'CONFIRMED'},
          where: 'id=?',
          whereArgs: [transfer],
        ),
    'transfer_lot_items tiene otra cantidad': (h, transfer) async =>
        (await h.db).update(
          'transfer_lot_items',
          {'quantity_base': 500},
          where: 'transfer_id=?',
          whereArgs: [transfer],
        ),
  };
  for (final entry in brokenTransfers.entries) {
    test('pase revertido sin vínculo demostrado: ${entry.key}', () async {
      final h = await home('d03n-pase-${entry.key.hashCode}');
      await h.buy(h.titular, 1000, oct(10));
      final transfer = await h.repo.transferProductFifo(
        fromPersonId: h.titular,
        toPersonId: h.sister,
        productId: h.bellator,
        quantityBase: 600,
        date: oct(15),
      );
      await h.repo.reverseTransferUnauditedForTesting(
        transfer,
        reason: 'Equivocado',
      );
      await entry.value(h, transfer);
      final before = await dumpTables(await h.db);
      await expectLater(
        h.apply(1000, oct(18)),
        historical(
          day: '2026-10-18',
          held: 400,
          available: 400,
          requested: 1000,
          message:
              'Bellator: el 18/10/2026 esa persona tenía 0,4 L; pidió 1 L. '
              '$_tail',
        ),
      );
      expect(await dumpTables(await h.db), before);
    });
  }

  group('con auditoría de RF-13 y operación tardía', () {
    late AppDatabase database;
    late AgroRepository repo;
    late Household h;
    late OwnerBindingContext binding;
    late LocalOwnerCredential credential;

    DateTime d(int y, int m, int day) => DateTime.utc(y, m, day, 15);

    setUp(() async {
      database = openDb(inMemoryDatabasePath);
      final bound = await seedActivatedInstallation(database);
      repo = AgroRepository(database, ownerCredential: () => credential);
      h = await seedHousehold(repo);
      await repo.addHistoricalCampaign(
        name: 'Campaña 2025',
        start: d(2025, 6, 1),
        end: d(2025, 12, 30),
      );
      binding = OwnerBindingContext(
        bindingId: bound.id,
        personId: bound.personId,
        scope: memberA,
      );
      credential = (await TestOwnerPin.enrolled(binding)).credential;
    });

    Future<OwnerAuthorization> auth(AuthorizationPurpose purpose, String ref) =>
        credential.verify(
          pin: '284917',
          purpose: purpose,
          subjectRef: ref,
          binding: binding,
        );

    ApplicationDraft lateApplication(DateTime at, int quantity) =>
        ApplicationDraft(
          personId: h.titular,
          farmId: h.titularFarm,
          campaignId: h.campaign,
          appliedAt: at,
          lines: [
            ApplicationLineDraft(productId: h.product, quantityBase: quantity),
          ],
        );

    Future<LateResolution> confirm(String ref) async =>
        repo.confirmLateOperation(
          ref,
          authorization: await auth(
            AuthorizationPurpose.confirmLateOperation,
            'late:$ref',
          ),
        );

    /// Compra tardía de 1 L el 01/07/2025 y aplicación tardía de todo el
    /// litro el 01/08/2025, las dos confirmadas. Devuelve la aplicación.
    Future<int> lateHistory() async {
      final purchase = await repo.captureLatePurchase(
        PurchaseDraft(
          supplierId: h.supplier,
          campaignId: h.campaign,
          purchaseDate: d(2025, 7, 1),
          items: [
            PurchaseItemDraft(
              productId: h.product,
              quantityBase: 1000,
              currency: CurrencyCode.bob,
              originalUnitPriceMinor: 10000,
              allocations: [
                AllocationDraft(personId: h.titular, quantityBase: 1000),
              ],
            ),
          ],
        ),
        reason: 'Factura tardía',
      );
      expect(
        (await confirm(purchase)).outcome,
        LateResolutionOutcome.confirmed,
      );
      final application = await repo.captureLateApplication(
        lateApplication(d(2025, 8, 1), 1000),
        reason: 'Aplicación anotada tarde',
      );
      final resolved = await confirm(application);
      expect(resolved.outcome, LateResolutionOutcome.confirmed);
      return resolved.operationId!;
    }

    test('reversión auditada con PIN: el par se neutraliza también para la '
        'tardía, que se confirma', () async {
      final reversed = await lateHistory();
      await repo.reverseApplication(
        reversed,
        reason: 'Registrada por error',
        authorization: await auth(
          AuthorizationPurpose.reverseApplication,
          'application:$reversed',
        ),
      );
      final db = await database.database;
      final before = await dumpTables(db, except: {'late_operation_drafts'});
      final ref = await repo.captureLateApplication(
        lateApplication(d(2025, 7, 15), 500),
        reason: 'Otra anotada tarde',
      );
      final resolved = await confirm(ref);
      expect(resolved.outcome, LateResolutionOutcome.confirmed);
      expectOnlyApplicationRows(
        before,
        await dumpTables(db, except: {'late_operation_drafts'}),
        resolved.operationId!,
      );
    });

    test('una auditoría que no nombra el movimiento de reversión no demuestra '
        'el vínculo: la tardía queda en conflicto, sin efectos', () async {
      final reversed = await lateHistory();
      await repo.reverseApplicationUnauditedForTesting(
        reversed,
        reason: 'Registrada por error',
      );
      final db = await database.database;
      // Auditoría de la operación, sin el movimiento entre sus efectos.
      await db.insert('reversal_audit', {
        'reversal_ref': '33333333-3333-4333-8333-333333333333',
        'operation_type': 'APPLICATION',
        'operation_id': reversed,
        'reason': 'Registrada por error',
        'actor_person_id': binding.personId,
        'actor_binding_id': binding.bindingId,
        'actor_member_id': memberA.memberId,
        'actor_tenant_id': memberA.tenantId,
        'actor_method': 'LOCAL_PIN',
        'credential_enrolment_ref': 'otro',
        'recorded_at': DateTime.now().toUtc().toIso8601String(),
      });
      final ref = await repo.captureLateApplication(
        lateApplication(d(2025, 7, 15), 500),
        reason: 'Otra anotada tarde',
      );
      final before = await dumpTables(db, except: {'late_operation_drafts'});
      final resolved = await confirm(ref);
      expect(resolved.outcome, LateResolutionOutcome.conflict);
      expect(resolved.conflictCode, LateConflict.stockUnavailable);
      expect(await dumpTables(db, except: {'late_operation_drafts'}), before);
    });
  });
}
