// REC-003 (#39), RNF-02: si SQLite rechaza una escritura a mitad de
// `confirmPurchase`, la transacción se deshace entera. Es el hueco que dejó
// `repository_test.dart:233`, cuyo rechazo es un `StateError` del propio
// repositorio y no del motor (conciliación del 2026-10-19, §6).
//
// El rechazo lo provoca un disparador TEMP creado sólo en esta base de prueba
// (vive en `sqlite_temp_master`, no en el esquema de la app) con
// `RAISE(ABORT)`. Salta al insertar la segunda línea y sólo si la primera
// línea y todos sus efectos ya están escritos en la misma transacción.
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';

const _mark = 'ENSAYO_REC039_ABORT: segunda linea rechazada por SQLite';

/// La primera línea de la compra en curso (Glifosato para Ana y Beto) debe
/// tener ya sus dos asignaciones, sus dos lotes, sus dos entradas
/// `PURCHASE_IN` y el cargo de Beto, que es tercero.
const _trigger =
    '''
CREATE TEMP TRIGGER rec039_abort_second_line BEFORE INSERT ON purchase_items
WHEN (SELECT COUNT(*) FROM purchase_items i
      WHERE i.purchase_id = NEW.purchase_id) = 1
 AND (SELECT COUNT(*) FROM purchase_allocations a
      JOIN purchase_items i ON i.id = a.purchase_item_id
      WHERE i.purchase_id = NEW.purchase_id) = 2
 AND (SELECT COUNT(*) FROM inventory_lots l
      JOIN purchase_items i ON i.id = l.purchase_item_id
      WHERE i.purchase_id = NEW.purchase_id) = 2
 AND (SELECT COUNT(*) FROM inventory_movements m
      JOIN inventory_lots l ON l.id = m.lot_id
      JOIN purchase_items i ON i.id = l.purchase_item_id
      WHERE i.purchase_id = NEW.purchase_id AND m.type = 'PURCHASE_IN') = 2
 AND (SELECT COUNT(*) FROM account_transactions t
      JOIN purchase_allocations a ON t.reference_type = 'PURCHASE_ALLOCATION'
        AND t.reference_id = a.id
      JOIN purchase_items i ON i.id = a.purchase_item_id
      WHERE i.purchase_id = NEW.purchase_id) = 1
BEGIN
  SELECT RAISE(ABORT, '$_mark');
END''';

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late AgroRepository repo;
  late Database db;
  late int ana, beto, supplier, campaign, glifosato, atrazina;

  /// Compra sembrada del 05/01, de dos líneas: Glifosato 10 L a Bs 100,00
  /// para Ana (familia, cobro por uso) y Atrazina 2 kg a Bs 200,00 para Beto
  /// (tercero, cobro por asignación: Bs 400,00).
  setUp(() async {
    database = openDb(inMemoryDatabasePath);
    repo = AgroRepository(database);
    db = await database.database;
    ana = await repo.addPerson(name: 'Ana', role: PersonRole.family);
    beto = await repo.addPerson(name: 'Beto', role: PersonRole.thirdParty);
    supplier = await repo.addSupplier(name: 'Agro Sur');
    campaign = await repo.addCampaign(
      name: 'Verano',
      start: DateTime.utc(2026, 1, 1),
    );
    glifosato = await repo.addProduct(name: 'Glifosato');
    atrazina = await repo.addProduct(name: 'Atrazina', unit: 'KG');
    await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: supplier,
        campaignId: campaign,
        purchaseDate: DateTime.utc(2026, 1, 5),
        items: [
          PurchaseItemDraft(
            productId: glifosato,
            quantityBase: 10000,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 10000,
            allocations: [AllocationDraft(personId: ana, quantityBase: 10000)],
          ),
          PurchaseItemDraft(
            productId: atrazina,
            quantityBase: 2000,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 20000,
            allocations: [AllocationDraft(personId: beto, quantityBase: 2000)],
          ),
        ],
      ),
    );
  });

  /// La compra del 10/02 que se intenta: Glifosato 6 L a Bs 120,00 (Ana 4 L,
  /// Beto 2 L) y Atrazina 3 kg a Bs 210,00 para Beto. Total Bs 1.350,00.
  PurchaseDraft draft() => PurchaseDraft(
    supplierId: supplier,
    campaignId: campaign,
    purchaseDate: DateTime.utc(2026, 2, 10),
    invoiceNumber: 'F-200',
    items: [
      PurchaseItemDraft(
        productId: glifosato,
        quantityBase: 6000,
        currency: CurrencyCode.bob,
        originalUnitPriceMinor: 12000,
        allocations: [
          AllocationDraft(personId: ana, quantityBase: 4000),
          AllocationDraft(personId: beto, quantityBase: 2000),
        ],
      ),
      PurchaseItemDraft(
        productId: atrazina,
        quantityBase: 3000,
        currency: CurrencyCode.bob,
        originalUnitPriceMinor: 21000,
        allocations: [AllocationDraft(personId: beto, quantityBase: 3000)],
      ),
    ],
  );

  /// Todas las tablas del esquema principal, fila por fila, más
  /// `sqlite_sequence` y el propio esquema principal (`sqlite_master`). El
  /// disparador TEMP no figura en ninguno de los dos.
  Future<Map<String, Object?>> snapshot() async => {
    ...await dumpTables(db),
    'sqlite_sequence': await db.rawQuery(
      'SELECT * FROM sqlite_sequence ORDER BY name',
    ),
    'sqlite_master': await db.rawQuery(
      'SELECT type, name, tbl_name, sql FROM sqlite_master ORDER BY name',
    ),
  };

  /// Saldos derivados: stock por persona y producto, saldo de cuenta por
  /// persona y los totales del tablero.
  Future<Map<String, Object>> balances() async {
    final summary = await repo.dashboard();
    return {
      'stock': await stockByPersonProduct(db),
      'accounts': {
        for (final r in await db.rawQuery(
          '''SELECT person_id, SUM(amount_bob_minor_signed) s
          FROM account_transactions GROUP BY person_id''',
        ))
          r['person_id']! as int: r['s']! as int,
      },
      'dashboard': (
        purchases: summary.purchasesBobMinor,
        providerPaid: summary.providerPaidMinor,
        family: summary.familyReceivableMinor,
        thirdParty: summary.thirdPartyReceivableMinor,
        received: summary.receivedMinor,
        stock: summary.stockBase,
      ),
    };
  }

  Future<List<String?>> tempTriggers() async => [
    for (final r in await db.rawQuery(
      "SELECT name FROM sqlite_temp_master WHERE type='trigger'",
    ))
      r['name'] as String?,
  ];

  test('si SQLite rechaza la segunda línea, confirmPurchase no deja nada y, '
      'sin el disparador, la misma compra se confirma', () async {
    final before = await snapshot();
    final balancesBefore = await balances();
    expect(balancesBefore, {
      'stock': {(ana, glifosato): 10000, (beto, atrazina): 2000},
      'accounts': {beto: 40000},
      'dashboard': (
        purchases: 140000,
        providerPaid: 0,
        family: 0,
        thirdParty: 40000,
        received: 0,
        stock: 12000,
      ),
    });

    await db.execute(_trigger);
    expect(await tempTriggers(), ['rec039_abort_second_line']);

    // El error es del motor (DatabaseException con la marca y código
    // extendido 1811, SQLITE_CONSTRAINT_TRIGGER), no un StateError ni una
    // BusinessRuleException.
    await expectLater(
      repo.confirmPurchase(draft()),
      throwsA(
        isA<DatabaseException>()
            .having((e) => e.toString(), 'mensaje', contains(_mark))
            .having((e) => e.getResultCode(), 'código', 1811),
      ),
    );

    // Ni cabecera, ni líneas, ni asignaciones, lotes, movimientos o cargos:
    // todo igual que antes, incluidos los contadores y el esquema.
    expect(await snapshot(), before);
    expect(await balances(), balancesBefore);

    await db.execute('DROP TRIGGER rec039_abort_second_line');
    expect(await tempTriggers(), isEmpty);

    final id = await repo.confirmPurchase(draft());
    expect(id, 2);
    final after = await snapshot();

    // Lo que cambió son sólo filas nuevas al final de seis tablas y sus
    // contadores, que siguen desde donde quedaron antes del rechazo.
    const written = {
      'purchases',
      'purchase_items',
      'purchase_allocations',
      'inventory_lots',
      'inventory_movements',
      'account_transactions',
    };
    expect(after['sqlite_sequence'], [
      {'name': 'account_transactions', 'seq': 3},
      {'name': 'campaigns', 'seq': 1},
      {'name': 'inventory_lots', 'seq': 5},
      {'name': 'inventory_movements', 'seq': 5},
      {'name': 'persons', 'seq': 2},
      {'name': 'products', 'seq': 2},
      {'name': 'purchase_allocations', 'seq': 5},
      {'name': 'purchase_items', 'seq': 4},
      {'name': 'purchases', 'seq': 2},
      {'name': 'suppliers', 'seq': 1},
    ]);
    for (final table in before.keys) {
      if (table == 'sqlite_sequence') continue;
      if (written.contains(table)) {
        final rows = before[table]! as List;
        expect(
          (after[table]! as List).take(rows.length).toList(),
          rows,
          reason: table,
        );
      } else {
        expect(after[table], before[table], reason: table);
      }
    }
    List<List<Object?>> added(String table, List<String> columns) => [
      for (final row in (after[table]! as List<Map<String, Object?>>).skip(
        (before[table]! as List).length,
      ))
        [for (final c in columns) row[c]],
    ];

    expect(
      added('purchases', [
        'id',
        'purchase_date',
        'invoice_number',
        'total_bob_minor',
        'status',
        'reversed_at',
      ]),
      [
        [2, '2026-02-10T00:00:00.000Z', 'F-200', 135000, 'CONFIRMED', null],
      ],
    );
    expect(
      added('purchase_items', [
        'purchase_id',
        'product_id',
        'quantity_base',
        'converted_unit_price_bob_minor',
        'subtotal_bob_minor',
      ]),
      [
        [2, glifosato, 6000, 12000, 72000],
        [2, atrazina, 3000, 21000, 63000],
      ],
    );
    expect(
      added('purchase_allocations', [
        'person_id',
        'quantity_base',
        'charge_policy_snapshot',
        'amount_bob_minor_if_allocation_charge',
      ]),
      [
        [ana, 4000, 'BY_ACTUAL_USAGE', null],
        [beto, 2000, 'BY_PURCHASE_ALLOCATION', 24000],
        [beto, 3000, 'BY_PURCHASE_ALLOCATION', 63000],
      ],
    );
    expect(
      added('inventory_lots', [
        'product_id',
        'owner_person_id',
        'acquired_date',
        'initial_quantity_base',
        'unit_cost_bob_minor_per_major_unit',
      ]),
      [
        [glifosato, ana, '2026-02-10T00:00:00.000Z', 4000, 12000],
        [glifosato, beto, '2026-02-10T00:00:00.000Z', 2000, 12000],
        [atrazina, beto, '2026-02-10T00:00:00.000Z', 3000, 21000],
      ],
    );
    expect(
      added('inventory_movements', [
        'product_id',
        'owner_person_id',
        'type',
        'quantity_signed',
        'reference_type',
      ]),
      [
        [glifosato, ana, 'PURCHASE_IN', 4000, 'PURCHASE_ALLOCATION'],
        [glifosato, beto, 'PURCHASE_IN', 2000, 'PURCHASE_ALLOCATION'],
        [atrazina, beto, 'PURCHASE_IN', 3000, 'PURCHASE_ALLOCATION'],
      ],
    );
    expect(
      added('account_transactions', [
        'person_id',
        'campaign_id',
        'type',
        'amount_bob_minor_signed',
      ]),
      [
        [beto, campaign, 'PURCHASE_ALLOCATION_CHARGE', 24000],
        [beto, campaign, 'PURCHASE_ALLOCATION_CHARGE', 63000],
      ],
    );

    expect(await balances(), {
      'stock': {
        (ana, glifosato): 14000,
        (beto, atrazina): 5000,
        (beto, glifosato): 2000,
      },
      'accounts': {beto: 127000},
      'dashboard': (
        purchases: 275000,
        providerPaid: 0,
        family: 0,
        thirdParty: 127000,
        received: 0,
        stock: 21000,
      ),
    });
  });

  test('el disparador no salta antes de la segunda línea: con él puesto, una '
      'compra de una sola línea se confirma', () async {
    await db.execute(_trigger);
    final id = await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: supplier,
        campaignId: campaign,
        purchaseDate: DateTime.utc(2026, 2, 10),
        items: [draft().items.first],
      ),
    );
    expect(
      (await db.query(
        'purchases',
        columns: ['total_bob_minor'],
        where: 'id=?',
        whereArgs: [id],
      )).single['total_bob_minor'],
      72000,
    );
    expect(await tempTriggers(), ['rec039_abort_second_line']);
  });
}
