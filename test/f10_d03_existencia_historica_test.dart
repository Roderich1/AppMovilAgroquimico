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

import 'support/d03_dump.dart';
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

/// El caso de Ana (`fix_inventario_movimientos_test`), en días de enero: 10 L
/// el 05/01, 3 L aplicados el 10/01, 3 L más el 06/01, un pase de 2 L a Beto el
/// 15/01 y una aplicación de 1 L el 17/01, las dos revertidas hoy.
class AnaJanuary {
  AnaJanuary(this.database, this.repo);
  final AppDatabase database;
  final AgroRepository repo;
  late int ana;
  late int beto;
  late int supplier;
  late int campaign;
  late int glifosato;
  late int farm;
  late int first;
  late int second;
  late int transfer;
  late int reversed;

  Future<Database> get db => database.database;

  static DateTime jan(int d) => DateTime.utc(2026, 1, d, 12);

  Future<int> buy(int quantity, int d) => repo.confirmPurchase(
    PurchaseDraft(
      supplierId: supplier,
      campaignId: campaign,
      purchaseDate: jan(d),
      items: [
        PurchaseItemDraft(
          productId: glifosato,
          quantityBase: quantity,
          currency: CurrencyCode.bob,
          originalUnitPriceMinor: 10000,
          allocations: [AllocationDraft(personId: ana, quantityBase: quantity)],
        ),
      ],
    ),
  );

  Future<int> apply(int quantity, int d) => applyAt(quantity, jan(d));

  Future<int> applyAt(int quantity, DateTime at) => repo.confirmApplication(
    ApplicationDraft(
      personId: ana,
      farmId: farm,
      campaignId: campaign,
      appliedAt: at,
      lines: [
        ApplicationLineDraft(productId: glifosato, quantityBase: quantity),
      ],
    ),
  );

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
}

Future<AnaJanuary> anaJanuary(String name) async {
  final database = openDb(await tempDbPath(name));
  final a = AnaJanuary(database, AgroRepository(database));
  final repo = a.repo;
  a
    ..ana = await repo.addPerson(name: 'Ana', role: PersonRole.family)
    ..beto = await repo.addPerson(name: 'Beto', role: PersonRole.family)
    ..supplier = await repo.addSupplier(name: 'Agro Sur')
    ..campaign = await repo.addCampaign(
      name: 'Verano',
      start: DateTime.utc(2026, 1, 1),
    )
    ..glifosato = await repo.addProduct(name: 'Glifosato');
  a.farm = await repo.addFarm(ownerId: a.ana, name: 'Chaco Ana', areaM2: 10000);
  a.first = await a.lotOfPurchase(await a.buy(10000, 5));
  await a.apply(3000, 10);
  a.second = await a.lotOfPurchase(await a.buy(3000, 6));
  a.transfer = await repo.transferProductsFifo(
    fromPersonId: a.ana,
    toPersonId: a.beto,
    items: [TransferItemDraft(productId: a.glifosato, quantityBase: 2000)],
    date: AnaJanuary.jan(15),
  );
  await repo.reverseTransferUnauditedForTesting(
    a.transfer,
    reason: 'Equivocado',
  );
  a.reversed = await a.apply(1000, 17);
  await repo.reverseApplicationUnauditedForTesting(a.reversed, reason: 'Error');
  return a;
}

extension on AnaJanuary {
  /// Saldo del lote al final de cada día con movimientos (`aaaa-mm-dd` →
  /// saldo), en orden de día efectivo y de id. Con [corrected], sin los
  /// movimientos del pase y de la aplicación revertidos.
  Future<Map<String, int>> dayBalances(
    int lot, {
    bool corrected = false,
  }) async {
    final rows = await (await db).query(
      'inventory_movements',
      where: 'lot_id=?',
      whereArgs: [lot],
    );
    bool annulled(Map<String, Object?> m) =>
        (const [
              'TRANSFER',
              'TRANSFER_REVERSAL',
            ].contains(m['reference_type']) &&
            m['reference_id'] == transfer) ||
        (const [
              'APPLICATION',
              'APPLICATION_REVERSAL',
            ].contains(m['reference_type']) &&
            m['reference_id'] == reversed);
    final ordered =
        [
          for (final m in rows)
            if (!corrected || !annulled(m))
              (
                storedLocalDay(m['movement_date']! as String),
                m['id']! as int,
                m['quantity_signed']! as int,
              ),
        ]..sort((x, y) {
          final byDay = x.$1.compareTo(y.$1);
          return byDay != 0 ? byDay : x.$2.compareTo(y.$2);
        });
    final out = <String, int>{};
    var running = 0;
    for (final m in ordered) {
      running += m.$3;
      out[m.$1] = running;
    }
    return out;
  }

  Future<int> lotOfPurchase(int purchase) async =>
      (await (await db).rawQuery(
            '''SELECT l.id FROM inventory_lots l
            JOIN purchase_items i ON i.id=l.purchase_item_id
            WHERE i.purchase_id=?''',
            [purchase],
          )).single['id']!
          as int;
}

/// Medianoche local del día, como guarda el formulario un día pasado (#121).
DateTime oct(int day) => DateTime(2026, 10, day);

Matcher historical({
  required int held,
  required int available,
  required int requested,
  required String message,
  String day = '2026-10-15',
}) => throwsA(
  // Se nombra el tipo y se leen sus campos por `dynamic` para que el archivo
  // compile también contra el `lib/` de la base (ed9c55c): así las pruebas
  // fallan allí por su aserción, no por compilación.
  isA<BusinessRuleException>()
      .having((e) => e.message, 'message', message)
      .having((e) => '${e.runtimeType}', 'type', 'HistoricalStockException')
      .having((e) => (e as dynamic).day, 'day', day)
      .having((e) => (e as dynamic).heldBase, 'heldBase', held)
      .having((e) => (e as dynamic).availableBase, 'availableBase', available)
      .having((e) => (e as dynamic).requestedBase, 'requestedBase', requested)
      .having(
        (e) => e.message.toLowerCase(),
        'message',
        isNot(contains('no había existencias')),
      )
      .having((e) => e.message, 'message', isNot(contains('había 0 '))),
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
        held: 0,
        available: 0,
        requested: 800,
        message:
            'Bellator: el 15/10/2026 esa persona no tenía este producto; '
            'pidió 0,8 L. $_tail',
      ),
    );
    expect(await dumpTables(await h.db), before);
  });

  test('1b. con fecha pasada, también cuando tampoco alcanza el saldo de '
      'hoy: el rechazo nombra producto, fecha y existencia', () async {
    final h = await home('d03-1b');
    await h.buy(h.titular, h.bellator, 1000, oct(10));
    final before = await dumpTables(await h.db);
    await expectLater(
      h.repo.confirmApplication(h.application(oct(15), {h.bellator: 2000})),
      historical(
        held: 1000,
        available: 1000,
        requested: 2000,
        message:
            'Bellator: el 15/10/2026 esa persona tenía 1 L; pidió 2 L. $_tail',
      ),
    );
    expect(await dumpTables(await h.db), before);
    // La ruta de hoy conserva su mensaje (RN-25).
    await expectLater(
      h.repo.confirmApplication(
        h.application(DateTime.now(), {h.bellator: 2000}),
      ),
      throwsA(
        isA<BusinessRuleException>().having(
          (e) => e.message,
          'message',
          'Stock insuficiente para confirmar la aplicación.',
        ),
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
        held: 1000,
        available: 300,
        requested: 500,
        message:
            'Bellator: el 15/10/2026 esa persona tenía 1 L; de eso quedan '
            '0,3 L sin usar en operaciones posteriores; pidió 0,5 L. $_tail',
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

  test('3b. un pase posterior que sale del mismo lote, del lado de quien da, '
      'reduce el cupo', () async {
    final h = await home('d03-3b');
    await h.buy(h.titular, h.bellator, 1000, oct(10));
    // El 18/10 el titular pasa 0,7 L de ese lote a la hermana.
    await h.repo.transferProductFifo(
      fromPersonId: h.titular,
      toPersonId: h.sister,
      productId: h.bellator,
      quantityBase: 700,
      date: oct(18),
    );
    // El 20/10 entra otro litro, que el 15/10 no existía.
    await h.buy(h.titular, h.bellator, 1000, oct(20));
    final first = await h.lot(h.titular, h.bellator, '2026-10-10');
    final before = await dumpTables(await h.db);
    await expectLater(
      h.repo.confirmApplication(h.application(oct(15), {h.bellator: 500})),
      historical(
        held: 1000,
        available: 300,
        requested: 500,
        message:
            'Bellator: el 15/10/2026 esa persona tenía 1 L; de eso quedan '
            '0,3 L sin usar en operaciones posteriores; pidió 0,5 L. $_tail',
      ),
    );
    expect(await dumpTables(await h.db), before);
    final id = await h.repo.confirmApplication(
      h.application(oct(15), {h.bellator: 300}),
    );
    expect(await h.consumptions(id), {first: (300, 3000)});
    expect(await h.negativeHistory(), isEmpty);
  });

  // 3c cambió su resultado esperado con la decisión del autor del 2026-10-28:
  // los pares operación + reversión demostrados no cuentan en la proyección
  // histórica. Antes (2026-10-27) 8 L se rechazaban con 7 L elegibles.
  test('3c. caso de Ana: con la historia corregida tenía 10 L el 21/01 y '
      '8 L se aceptan; la base sólo gana las filas de la aplicación', () async {
    final ana = await anaJanuary('d03-3c');
    final before = await dumpTables(await ana.db);
    final id = await ana.apply(8000, 21);
    // FIFO sobre lotes elegibles: 7 L del 05/01 y 1 L del 06/01, a su costo.
    expect(await ana.consumptions(id), {
      ana.first: (7000, 70000),
      ana.second: (1000, 10000),
    });
    expectOnlyApplicationRows(before, await dumpTables(await ana.db), id);
    // Saldo actual: 10 − 8 = 2 L, todo del lote del 06/01.
    expect(await ana.balance(ana.first), 0);
    expect(await ana.balance(ana.second), 2000);
    // La bitácora sin corregir conserva las fechas reales: el lote del 05/01
    // queda en −3 L el 21/01 (Ana en total, −3 + 2 = −1 L) hasta las
    // reversiones de hoy. La historia corregida no baja de cero.
    final raw = await ana.dayBalances(ana.first);
    expect(raw['2026-01-21'], -3000);
    expect((await ana.dayBalances(ana.second))['2026-01-21'], 2000);
    final corrected = await ana.dayBalances(ana.first, corrected: true);
    expect(corrected['2026-01-21'], 0);
    expect(corrected.values.every((v) => v >= 0), isTrue);
  });

  test('3c-bis. si después se consumieron 4 L de lo devuelto, 8 L se '
      'rechazan con la existencia corregida', () async {
    final ana = await anaJanuary('d03-3c-bis');
    // Hoy se usan 4 L: salen del lote del 05/01, que hoy tiene 7 L.
    await ana.applyAt(4000, DateTime.now());
    final before = await dumpTables(await ana.db);
    await expectLater(
      ana.apply(8000, 21),
      historical(
        day: '2026-01-21',
        held: 10000,
        available: 6000,
        requested: 8000,
        message:
            'Glifosato: el 21/01/2026 esa persona tenía 10 L; de eso quedan '
            '6 L sin usar en operaciones posteriores; pidió 8 L. $_tail',
      ),
    );
    expect(await dumpTables(await ana.db), before);
  });

  test('3d. un lote con historial negativo previo no aporta cupo', () async {
    final h = await home('d03-3d');
    // La hermana compra el 05/10 y le pasa 1 L al titular el 20/10: el
    // lote recibido conserva la adquisición del 05/10.
    await h.buy(h.sister, h.bellator, 1000, oct(5));
    await h.repo.transferProductFifo(
      fromPersonId: h.sister,
      toPersonId: h.titular,
      productId: h.bellator,
      quantityBase: 1000,
      date: oct(20),
    );
    final received = await h.lot(h.titular, h.bellator, '2026-10-05');
    // Lo que dejaba la regla anterior: una aplicación del 15/10 que consumió
    // ese lote recibido el 20/10. Se registra hoy y se le pone la fecha.
    final old = await h.repo.confirmApplication(
      h.application(DateTime.now(), {h.bellator: 500}),
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
    // El titular compra 0,4 L propios el 16/10. El lote recibido tiene el
    // 17/10 un saldo histórico de -0,5 L (hoy, 0,5 L): el FIFO de antes lo
    // tomaría primero.
    await h.buy(h.titular, h.bellator, 400, oct(16));
    final own = await h.lot(h.titular, h.bellator, '2026-10-16');
    expect(await h.negativeHistory(), [(received, '2026-10-15', -500)]);

    final before = await dumpTables(db);
    await expectLater(
      h.repo.confirmApplication(h.application(oct(17), {h.bellator: 600})),
      historical(
        day: '2026-10-17',
        held: 400,
        available: 400,
        requested: 600,
        message:
            'Bellator: el 17/10/2026 esa persona tenía 0,4 L; pidió 0,6 L. '
            '$_tail',
      ),
    );
    expect(await dumpTables(db), before);
    final id = await h.repo.confirmApplication(
      h.application(oct(17), {h.bellator: 400}),
    );
    // Sólo del lote propio; el recibido no aporta nada.
    expect(await h.consumptions(id), {own: (400, 4000)});
    expect(await h.balance(received), 500);
    // El registro anterior no se corrige.
    expect(await h.negativeHistory(), [(received, '2026-10-15', -500)]);
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
        held: 0,
        available: 0,
        requested: 1000,
        message:
            'Expansive: el 15/10/2026 esa persona no tenía este producto; '
            'pidió 1 KG. $_tail',
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
        held: 0,
        available: 0,
        requested: 800,
        message:
            'Bellator: el 15/10/2026 esa persona no tenía este producto; '
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

  // En producción la voz confirma siempre con la fecha de hoy
  // (`VoiceDraftGateway` usa `DateTime.now()`): estas pruebas fijan el reloj
  // en un día pasado sólo para demostrar que el rechazo del repositorio y su
  // mensaje llegan igual al borrador de voz.
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
        'Glifosato: el 15/10/2026 esa persona no tenía este producto; '
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
