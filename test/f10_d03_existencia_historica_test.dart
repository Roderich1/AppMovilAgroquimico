// D-03 (decisión del autor, Roderich Rendón, 2026-10-27): una aplicación
// no consume producto que todavía no existía en su fecha efectiva, tampoco
// dentro de la campaña activa. Con fecha pasada, `confirmApplication` usa la
// elegibilidad de RF-03 (lotes adquiridos ese día o antes y un cupo que no
// deja negativo ningún saldo posterior); con fecha de hoy, la ruta de
// siempre. Precisión de RN-25; RN-26 (FIFO), RF-03, CU-09.
//
// Pruebas de HOST (sqflite_common_ffi). Sin dispositivo ni personas. Usan el
// reloj real: los días de octubre de 2026 son pasados desde el 2026-10-27.
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/campaign_calendar.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/presentation/voice/voice_draft_gateway.dart';
import 'package:agroquimicos/presentation/widgets/common.dart'
    show friendlyError;
import 'package:agroquimicos/voice_draft/application/application_interpreter.dart';
import 'package:agroquimicos/voice_draft/application/voice_application_draft.dart';
import 'package:agroquimicos/voice_draft/core/voice_draft_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';

/// Texto fijo que sigue a la cifra en todo rechazo histórico.
const _tail =
    'Una aplicación con fecha pasada sólo puede usar lo que esa persona ya '
    'tenía ese día y no se usó después: no cuenta el producto comprado o '
    'recibido más tarde. Revise la fecha o la cantidad. No se registró nada.';

/// Hogar con una campaña activa desde el 01/10/2026, dos familiares (cargo
/// por consumo) y dos productos.
class Home {
  Home(this.database, this.repo);
  final AppDatabase database;
  final AgroRepository repo;
  late int titular;
  late int sister;
  late int supplier;
  late int campaign;
  late int bellator;
  late int expansive;
  late int farm;

  Future<Database> get db => database.database;

  /// Compra de [quantity] (unidad base) a [price] Bs por L o kg, asignada a
  /// [person] en el día [at].
  Future<int> buy(
    int person,
    int product,
    int quantity,
    DateTime at, {
    int price = 100,
  }) => repo.confirmPurchase(
    PurchaseDraft(
      supplierId: supplier,
      campaignId: campaign,
      purchaseDate: at,
      items: [
        PurchaseItemDraft(
          productId: product,
          quantityBase: quantity,
          currency: CurrencyCode.bob,
          originalUnitPriceMinor: price * 100,
          allocations: [
            AllocationDraft(personId: person, quantityBase: quantity),
          ],
        ),
      ],
    ),
  );

  ApplicationDraft application(
    DateTime at,
    Map<int, int> quantities, {
    int? planId,
  }) => ApplicationDraft(
    personId: titular,
    farmId: farm,
    campaignId: campaign,
    appliedAt: at,
    planId: planId,
    lines: [
      for (final entry in quantities.entries)
        ApplicationLineDraft(productId: entry.key, quantityBase: entry.value),
    ],
  );

  /// Lote de [person] y [product] adquirido el día [day] (`aaaa-mm-dd`).
  Future<int> lot(int person, int product, String day) async {
    final rows = await (await db).query(
      'inventory_lots',
      where: 'owner_person_id=? AND product_id=?',
      whereArgs: [person, product],
      orderBy: 'id',
    );
    return rows
            .where((r) => storedLocalDay(r['acquired_date']! as String) == day)
            .single['id']!
        as int;
  }

  /// Consumos de una aplicación: lote → (cantidad, costo).
  Future<Map<int, (int, int)>> consumptions(int application) async => {
    for (final row in await (await db).rawQuery(
      '''SELECT c.inventory_lot_id lot, c.quantity_consumed_base q,
        c.cost_bob_minor cost FROM application_consumptions c
        JOIN application_items i ON i.id=c.application_item_id
        WHERE i.application_id=? ORDER BY c.id''',
      [application],
    ))
      row['lot']! as int: (row['q']! as int, row['cost']! as int),
  };

  Future<int> balance(int lot) async =>
      Sqflite.firstIntValue(
        await (await db).rawQuery(
          'SELECT SUM(quantity_signed) FROM inventory_movements WHERE lot_id=?',
          [lot],
        ),
      ) ??
      0;

  /// Oráculo: saldos al final de cada día, por lote, en orden de día
  /// efectivo y después de id. Devuelve los (lote, día, saldo) negativos.
  Future<List<(int, String, int)>> negativeHistory() async {
    final rows = await (await db).query(
      'inventory_movements',
      columns: ['id', 'lot_id', 'movement_date', 'quantity_signed'],
    );
    final byLot = <int, List<(String, int, int)>>{};
    for (final r in rows) {
      byLot.putIfAbsent(r['lot_id']! as int, () => []).add((
        storedLocalDay(r['movement_date']! as String),
        r['id']! as int,
        r['quantity_signed']! as int,
      ));
    }
    final negative = <(int, String, int)>[];
    for (final entry in byLot.entries) {
      final list = entry.value
        ..sort((a, b) {
          final byDay = a.$1.compareTo(b.$1);
          return byDay != 0 ? byDay : a.$2.compareTo(b.$2);
        });
      var running = 0;
      for (var i = 0; i < list.length; i++) {
        running += list[i].$3;
        final endOfDay = i == list.length - 1 || list[i + 1].$1 != list[i].$1;
        if (endOfDay && running < 0) {
          negative.add((entry.key, list[i].$1, running));
        }
      }
    }
    return negative;
  }
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
    ..expansive = await repo.addProduct(name: 'Expansive', unit: 'KG')
    ..campaign = await repo.addCampaign(
      name: 'Invierno',
      start: DateTime(2026, 10, 1),
    );
  h.farm = await repo.addFarm(
    ownerId: h.titular,
    name: 'Chaco titular',
    areaM2: 10000,
  );
  return h;
}

/// Medianoche local del día, como guarda el formulario un día pasado (#121).
DateTime oct(int day) => DateTime(2026, 10, day);

Matcher historical({
  required int available,
  required int requested,
  required String message,
}) => throwsA(
  // Se nombra el tipo y se leen sus campos por `dynamic` para que el archivo
  // compile también contra el `lib/` de la base (ed9c55c): así las pruebas
  // fallan allí por su aserción, no por compilación.
  isA<BusinessRuleException>()
      .having((e) => e.message, 'message', message)
      .having((e) => '${e.runtimeType}', 'type', 'HistoricalStockException')
      .having((e) => (e as dynamic).day, 'day', '2026-10-15')
      .having((e) => (e as dynamic).availableBase, 'availableBase', available)
      .having((e) => (e as dynamic).requestedBase, 'requestedBase', requested)
      .having(
        (e) => e.message.toLowerCase(),
        'message',
        isNot(contains('no había existencias')),
      ),
);

void main() {
  sqfliteFfiInit();

  test('1. compra del 20/10 y aplicación del 15/10: rechazada con el '
      'producto, la fecha y la existencia elegible (0)', () async {
    final h = await home('d03-1');
    await h.buy(h.titular, h.bellator, 1000, oct(20));
    final before = await dumpTables(await h.db);
    await expectLater(
      h.repo.confirmApplication(h.application(oct(15), {h.bellator: 800})),
      historical(
        available: 0,
        requested: 800,
        message:
            'Bellator: el 15/10/2026 había 0 L disponibles para esa persona; '
            'pidió 0,8 L. $_tail',
      ),
    );
    expect(await dumpTables(await h.db), before);
  });

  test('2. existencia anterior suficiente: aceptada y el FIFO consume sólo '
      'lotes elegibles, con su costo', () async {
    final h = await home('d03-2');
    // La hermana compra el 05/10 a Bs 100; el titular, el 10/10 a Bs 200.
    await h.buy(h.sister, h.bellator, 1000, oct(5), price: 100);
    await h.buy(h.titular, h.bellator, 1000, oct(10), price: 200);
    // El 20/10 la hermana le transfiere 0,5 L: el lote recibido conserva la
    // adquisición del 05/10 (va antes en el FIFO) pero el titular no lo
    // tenía el 15/10.
    await h.repo.transferProductFifo(
      fromPersonId: h.sister,
      toPersonId: h.titular,
      productId: h.bellator,
      quantityBase: 500,
      date: oct(20),
    );
    final own = await h.lot(h.titular, h.bellator, '2026-10-10');
    final received = await h.lot(h.titular, h.bellator, '2026-10-05');

    final id = await h.repo.confirmApplication(
      h.application(oct(15), {h.bellator: 600}),
    );
    // Sólo del lote propio del 10/10: 0,6 L × Bs 200 = Bs 120.
    expect(await h.consumptions(id), {own: (600, 12000)});
    final row = (await (await h.db).query(
      'applications',
      where: 'id=?',
      whereArgs: [id],
    )).single;
    expect(row['total_cost_bob_minor'], 12000);
    expect(storedLocalDay(row['applied_at']! as String), '2026-10-15');
    expect(await h.balance(received), 500);
    expect(await h.balance(own), 400);
    expect(await h.negativeHistory(), isEmpty);
  });

  test('2b. un lote adquirido el mismo día es elegible', () async {
    final h = await home('d03-2b');
    await h.buy(h.titular, h.bellator, 1000, oct(15));
    final lot = await h.lot(h.titular, h.bellator, '2026-10-15');
    final id = await h.repo.confirmApplication(
      h.application(oct(15), {h.bellator: 1000}),
    );
    expect(await h.consumptions(id), {lot: (1000, 10000)});
    expect(await h.negativeHistory(), isEmpty);
  });

  test('3. existencia comprometida por movimientos posteriores: se rechaza '
      'lo que excede el cupo y se acepta hasta el cupo, sin saldos '
      'negativos', () async {
    final h = await home('d03-3');
    await h.buy(h.titular, h.bellator, 1000, oct(10));
    // El 18/10 ya se usaron 0,7 L del lote del 10/10.
    await h.repo.confirmApplication(h.application(oct(18), {h.bellator: 700}));
    // El 20/10 entra otro litro, que el 15/10 no existía.
    await h.buy(h.titular, h.bellator, 1000, oct(20));
    final first = await h.lot(h.titular, h.bellator, '2026-10-10');
    final later = await h.lot(h.titular, h.bellator, '2026-10-20');

    final before = await dumpTables(await h.db);
    await expectLater(
      h.repo.confirmApplication(h.application(oct(15), {h.bellator: 500})),
      historical(
        available: 300,
        requested: 500,
        message:
            'Bellator: el 15/10/2026 había 0,3 L disponibles para esa persona; '
            'pidió 0,5 L. $_tail',
      ),
    );
    expect(await dumpTables(await h.db), before);

    // Hasta el cupo, sí: sale todo del lote del 10/10.
    final id = await h.repo.confirmApplication(
      h.application(oct(15), {h.bellator: 300}),
    );
    expect(await h.consumptions(id), {first: (300, 3000)});
    expect(await h.balance(first), 0);
    expect(await h.balance(later), 1000);
    expect(await h.negativeHistory(), isEmpty);
  });

  test('4. rechazo multiproducto sin efectos parciales: ninguna fila nueva '
      'en aplicaciones, movimientos, cuentas ni outbox', () async {
    final h = await home('d03-4');
    await h.buy(h.titular, h.bellator, 1000, oct(10));
    await h.buy(h.titular, h.expansive, 2000, oct(20));
    final db = await h.db;
    Future<Map<String, int>> counts() async => {
      for (final table in const [
        'applications',
        'application_items',
        'application_consumptions',
        'inventory_movements',
        'account_transactions',
        'sync_outbox',
      ])
        table: Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $table'),
        )!,
    };
    final before = await dumpTables(db);
    final countsBefore = await counts();
    // La primera línea cabe; la segunda no existía el 15/10.
    await expectLater(
      h.repo.confirmApplication(
        h.application(oct(15), {h.bellator: 500, h.expansive: 1000}),
      ),
      historical(
        available: 0,
        requested: 1000,
        message:
            'Expansive: el 15/10/2026 había 0 KG disponibles para esa '
            'persona; pidió 1 KG. $_tail',
      ),
    );
    expect(await counts(), countsBefore);
    expect(await dumpTables(db), before);
  });

  test('4b. aplicación de un plan con fecha pasada: misma regla y el plan '
      'sigue pendiente', () async {
    final h = await home('d03-4b');
    await h.buy(h.titular, h.bellator, 1000, oct(20));
    final plan = await h.repo.addPlan(
      farmId: h.farm,
      campaignId: h.campaign,
      productId: h.bellator,
      areaM2: 10000,
      doseBasePerHa: 800,
    );
    final before = await dumpTables(await h.db);
    await expectLater(
      h.repo.confirmApplication(
        h.application(oct(15), {h.bellator: 800}, planId: plan),
      ),
      historical(
        available: 0,
        requested: 800,
        message:
            'Bellator: el 15/10/2026 había 0 L disponibles para esa persona; '
            'pidió 0,8 L. $_tail',
      ),
    );
    expect(await dumpTables(await h.db), before);
  });

  test('6. aplicación de hoy: misma ruta, mismo FIFO y mismo costo, también '
      'con lo comprado hoy', () async {
    final h = await home('d03-6');
    await h.buy(h.titular, h.bellator, 1000, oct(10), price: 100);
    await h.buy(h.titular, h.bellator, 1000, DateTime.now(), price: 200);
    final first = await h.lot(h.titular, h.bellator, '2026-10-10');
    final today = await h.lot(h.titular, h.bellator, localDay(DateTime.now()));
    final at = DateTime.now();
    final id = await h.repo.confirmApplication(
      h.application(at, {h.bellator: 1500}),
    );
    expect(await h.consumptions(id), {
      first: (1000, 10000),
      today: (500, 10000),
    });
    final db = await h.db;
    final movements = await db.query(
      'inventory_movements',
      where: "reference_type='APPLICATION' AND reference_id=?",
      whereArgs: [id],
      orderBy: 'id',
    );
    expect(movements.map((m) => m['movement_date']).toSet(), {
      at.toUtc().toIso8601String(),
    });
    expect(movements.map((m) => m['quantity_signed']), [-1000, -500]);
    final charge = (await db.query(
      'account_transactions',
      where: "type='USAGE_CHARGE' AND reference_id=?",
      whereArgs: [id],
    )).single;
    expect(charge['amount_bob_minor_signed'], 20000);
  });

  test('6b. un registro anterior inconsistente no se corrige y no impide '
      'la aplicación de hoy', () async {
    final h = await home('d03-6b');
    await h.buy(h.titular, h.bellator, 1000, oct(20));
    final lot = await h.lot(h.titular, h.bellator, '2026-10-20');
    // Lo que dejaba la regla anterior: una aplicación del 15/10 que consumió
    // el lote del 20/10. Se registra hoy y se le pone la fecha a mano.
    final old = await h.repo.confirmApplication(
      h.application(DateTime.now(), {h.bellator: 800}),
    );
    final db = await h.db;
    final stamp = oct(15).toUtc().toIso8601String();
    await db.update(
      'applications',
      {'applied_at': stamp},
      where: 'id=?',
      whereArgs: [old],
    );
    await db.update(
      'inventory_movements',
      {'movement_date': stamp},
      where: "reference_type='APPLICATION' AND reference_id=?",
      whereArgs: [old],
    );
    Future<Map<String, List<Map<String, Object?>>>> oldRows() async => {
      'applications': await db.query(
        'applications',
        where: 'id=?',
        whereArgs: [old],
      ),
      'movements': await db.query(
        'inventory_movements',
        where: "reference_type='APPLICATION' AND reference_id=?",
        whereArgs: [old],
      ),
      'consumptions': await db.rawQuery(
        '''SELECT c.* FROM application_consumptions c JOIN application_items i
        ON i.id=c.application_item_id WHERE i.application_id=?''',
        [old],
      ),
    };
    final before = await oldRows();
    expect(await h.negativeHistory(), [(lot, '2026-10-15', -800)]);

    final id = await h.repo.confirmApplication(
      h.application(DateTime.now(), {h.bellator: 200}),
    );
    expect(await h.consumptions(id), {lot: (200, 2000)});
    expect(await oldRows(), before);
  });

  group('7. por voz, con la misma regla', () {
    late AppDatabase database;
    late Household household;

    setUp(() async {
      database = openDb(inMemoryDatabasePath);
      household = await seedHousehold(AgroRepository(database));
    });

    const dictation =
        'apliqué dos litros de Glifosato en el chaco titular en media hectárea';

    Future<VoiceDraftController<VoiceApplicationDraft, int>> openDraft(
      DateTime at,
    ) async {
      final gateway = VoiceDraftGateway(
        AgroRepository(database),
        clock: () => at,
      );
      final catalog = await gateway.applicationCatalog();
      final controller = VoiceDraftController<VoiceApplicationDraft, int>(
        initial: VoiceApplicationDraft.start(catalog),
        commit: gateway.confirmApplication,
        describeError: friendlyError,
      );
      addTearDown(controller.dispose);
      controller.applyVoice((current) {
        final r = interpretApplication(dictation, current, catalog);
        return (r.draft, r.outcome);
      });
      final owner = controller.draft.person!.id;
      final stock = await gateway.availableStock(owner);
      controller.editManually((c) => c.withStock(owner, stock));
      expect(controller.blockers, isEmpty);
      return controller;
    }

    test('confirmar el 15/10 lo comprado el 20/10: rechazado con el mismo '
        'mensaje y sin escribir', () async {
      await household.buy(household.titular, 5000, date: oct(20));
      final db = await database.database;
      final controller = await openDraft(DateTime(2026, 10, 15, 9));
      final before = await dumpTables(db);
      expect(await controller.confirm(), isNull);
      expect(
        controller.error,
        'Glifosato: el 15/10/2026 había 0 L disponibles para esa persona; '
        'pidió 2 L. $_tail',
      );
      expect(await dumpTables(db), before);
    });

    test(
      'con existencia de esa fecha, confirma desde el lote elegible',
      () async {
        await household.buy(household.titular, 5000, date: oct(10));
        final db = await database.database;
        final controller = await openDraft(DateTime(2026, 10, 15, 9));
        final id = await controller.confirm();
        expect(id, isNotNull);
        final consumed = await db.rawQuery(
          '''SELECT SUM(c.quantity_consumed_base) q FROM application_consumptions c
        JOIN application_items i ON i.id=c.application_item_id
        WHERE i.application_id=?''',
          [id],
        );
        expect(consumed.single['q'], 2000);
      },
    );
  });
}
