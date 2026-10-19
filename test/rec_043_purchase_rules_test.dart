// REC-007 (#43): rechazos de `confirmPurchase` sin dejar filas, y moneda,
// precio original y tipo de cambio conservados en cada línea y en cada lote
// (conciliación del 2026-10-19, §3.1). La atomicidad ante un fallo interno ya
// la cubre `repository_test.dart` («fallo interno revierte toda la
// transacción de compra»); aquí no se repite.
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late AgroRepository repo;
  late Database db;
  late int carlos, tercero, supplier, campaign, glifosato, atrazina;

  setUp(() async {
    database = openDb(inMemoryDatabasePath);
    repo = AgroRepository(database);
    db = await database.database;
    carlos = await repo.addPerson(name: 'Carlos', role: PersonRole.family);
    tercero = await repo.addPerson(
      name: 'Tercero',
      role: PersonRole.thirdParty,
    );
    supplier = await repo.addSupplier(name: 'Proveedor');
    campaign = await repo.addCampaign(
      name: 'Verano',
      start: DateTime.utc(2026, 1, 1),
    );
    glifosato = await repo.addProduct(name: 'Glifosato');
    atrazina = await repo.addProduct(name: 'Atrazina');
  });

  PurchaseItemDraft bobLine(int product, {int quantity = 5000}) =>
      PurchaseItemDraft(
        productId: product,
        quantityBase: quantity,
        currency: CurrencyCode.bob,
        originalUnitPriceMinor: 4500,
        allocations: [
          AllocationDraft(personId: carlos, quantityBase: quantity),
        ],
      );

  PurchaseDraft draft(List<PurchaseItemDraft> items) => PurchaseDraft(
    supplierId: supplier,
    campaignId: campaign,
    purchaseDate: DateTime.utc(2026, 2, 1),
    exchangeRateSource: ExchangeRateSource.agreedWithSupplier,
    items: items,
  );

  test(
    'cada regla de confirmPurchase rechaza la compra sin dejar filas',
    () async {
      // Una compra válida previa: los rechazos no deben tocarla.
      await repo.confirmPurchase(draft([bobLine(glifosato)]));
      final before = await dumpTables(db);

      final cases = <(String, PurchaseDraft)>[
        ('La compra necesita al menos un producto.', draft([])),
        (
          'No repita productos dentro de la compra.',
          draft([bobLine(atrazina), bobLine(atrazina, quantity: 1000)]),
        ),
        (
          'Cantidad y precio deben ser mayores a cero.',
          draft([bobLine(glifosato), bobLine(atrazina, quantity: 0)]),
        ),
        (
          'Cantidad y precio deben ser mayores a cero.',
          draft([
            PurchaseItemDraft(
              productId: atrazina,
              quantityBase: 1000,
              currency: CurrencyCode.bob,
              originalUnitPriceMinor: 0,
              allocations: [
                AllocationDraft(personId: carlos, quantityBase: 1000),
              ],
            ),
          ]),
        ),
        for (final fx in [null, 0, -6960000])
          (
            'Una compra en USD requiere tipo de cambio.',
            draft([
              bobLine(glifosato),
              PurchaseItemDraft(
                productId: atrazina,
                quantityBase: 1000,
                currency: CurrencyCode.usd,
                originalUnitPriceMinor: 1250,
                exchangeRateScaled: fx,
                allocations: [
                  AllocationDraft(personId: carlos, quantityBase: 1000),
                ],
              ),
            ]),
          ),
        (
          'Una compra en BOB no debe guardar tipo de cambio.',
          draft([
            PurchaseItemDraft(
              productId: atrazina,
              quantityBase: 1000,
              currency: CurrencyCode.bob,
              originalUnitPriceMinor: 4500,
              exchangeRateScaled: 6960000,
              allocations: [
                AllocationDraft(personId: carlos, quantityBase: 1000),
              ],
            ),
          ]),
        ),
        // Las asignaciones de la segunda línea suman 9 L de 10 L comprados.
        (
          'La cantidad asignada debe coincidir con la cantidad comprada.',
          draft([
            bobLine(glifosato),
            PurchaseItemDraft(
              productId: atrazina,
              quantityBase: 10000,
              currency: CurrencyCode.bob,
              originalUnitPriceMinor: 4500,
              allocations: [
                AllocationDraft(personId: carlos, quantityBase: 6000),
                AllocationDraft(personId: tercero, quantityBase: 3000),
              ],
            ),
          ]),
        ),
        // Y por exceso: 11 L asignados de 10 L.
        (
          'La cantidad asignada debe coincidir con la cantidad comprada.',
          draft([
            PurchaseItemDraft(
              productId: atrazina,
              quantityBase: 10000,
              currency: CurrencyCode.bob,
              originalUnitPriceMinor: 4500,
              allocations: [
                AllocationDraft(personId: carlos, quantityBase: 6000),
                AllocationDraft(personId: tercero, quantityBase: 5000),
              ],
            ),
          ]),
        ),
      ];

      for (final (message, rejected) in cases) {
        await expectLater(
          repo.confirmPurchase(rejected),
          throwsA(
            isA<BusinessRuleException>().having(
              (e) => e.message,
              'message',
              message,
            ),
          ),
        );
        expect(await dumpTables(db), before, reason: message);
      }
      // Sigue sólo la compra previa: 1 compra, 1 ítem, 1 lote, 1 movimiento.
      for (final table in [
        'purchases',
        'purchase_items',
        'purchase_allocations',
        'inventory_lots',
        'inventory_movements',
      ]) {
        expect(before[table], hasLength(1), reason: table);
      }
      expect(before['account_transactions'], isEmpty);
    },
  );

  test('una compra USD conserva moneda, precio original y tipo de cambio en '
      'cada línea y en cada lote', () async {
    // Glifosato: 10 L a USD 12,50/L con 6,96 → Bs 87,00/L; 6 L para Carlos y
    // 4 L para el tercero. Atrazina: 5 L a Bs 45,00/L para Carlos.
    final purchaseId = await repo.confirmPurchase(
      draft([
        PurchaseItemDraft(
          productId: glifosato,
          quantityBase: 10000,
          currency: CurrencyCode.usd,
          originalUnitPriceMinor: 1250,
          exchangeRateScaled: 6960000,
          allocations: [
            AllocationDraft(personId: carlos, quantityBase: 6000),
            AllocationDraft(personId: tercero, quantityBase: 4000),
          ],
        ),
        bobLine(atrazina),
      ]),
    );

    final purchase = (await db.query(
      'purchases',
      where: 'id=?',
      whereArgs: [purchaseId],
    )).single;
    // 10 L × Bs 87,00 + 5 L × Bs 45,00 = Bs 1.095,00.
    expect(purchase['total_bob_minor'], 109500);
    expect(purchase['default_currency_code'], 'USD');
    expect(purchase['default_exchange_rate_scaled'], 6960000);
    expect(purchase['exchange_rate_source'], 'AGREED_WITH_SUPPLIER');

    final items = await db.query(
      'purchase_items',
      columns: [
        'product_id',
        'currency_code',
        'original_unit_price_minor',
        'exchange_rate_scaled',
        'converted_unit_price_bob_minor',
        'original_subtotal_minor',
        'subtotal_bob_minor',
      ],
      where: 'purchase_id=?',
      whereArgs: [purchaseId],
      orderBy: 'id',
    );
    expect(items, [
      {
        'product_id': glifosato,
        'currency_code': 'USD',
        'original_unit_price_minor': 1250,
        'exchange_rate_scaled': 6960000,
        'converted_unit_price_bob_minor': 8700,
        'original_subtotal_minor': 12500,
        'subtotal_bob_minor': 87000,
      },
      {
        'product_id': atrazina,
        'currency_code': 'BOB',
        'original_unit_price_minor': 4500,
        'exchange_rate_scaled': null,
        'converted_unit_price_bob_minor': 4500,
        'original_subtotal_minor': 22500,
        'subtotal_bob_minor': 22500,
      },
    ]);

    final lots = await db.rawQuery(
      '''SELECT l.product_id, l.owner_person_id, l.initial_quantity_base,
      l.currency_code, l.original_unit_price_minor, l.exchange_rate_scaled,
      l.unit_cost_bob_minor_per_major_unit
      FROM inventory_lots l JOIN purchase_items i ON i.id=l.purchase_item_id
      WHERE i.purchase_id=? ORDER BY l.id''',
      [purchaseId],
    );
    expect(lots, [
      {
        'product_id': glifosato,
        'owner_person_id': carlos,
        'initial_quantity_base': 6000,
        'currency_code': 'USD',
        'original_unit_price_minor': 1250,
        'exchange_rate_scaled': 6960000,
        'unit_cost_bob_minor_per_major_unit': 8700,
      },
      {
        'product_id': glifosato,
        'owner_person_id': tercero,
        'initial_quantity_base': 4000,
        'currency_code': 'USD',
        'original_unit_price_minor': 1250,
        'exchange_rate_scaled': 6960000,
        'unit_cost_bob_minor_per_major_unit': 8700,
      },
      {
        'product_id': atrazina,
        'owner_person_id': carlos,
        'initial_quantity_base': 5000,
        'currency_code': 'BOB',
        'original_unit_price_minor': 4500,
        'exchange_rate_scaled': null,
        'unit_cost_bob_minor_per_major_unit': 4500,
      },
    ]);

    // El tercero se cobra al asignar: 4 L × Bs 87,00 = Bs 348,00.
    final charges = await db.query(
      'account_transactions',
      columns: ['person_id', 'type', 'amount_bob_minor_signed'],
    );
    expect(charges, [
      {
        'person_id': tercero,
        'type': 'PURCHASE_ALLOCATION_CHARGE',
        'amount_bob_minor_signed': 34800,
      },
    ]);
  });
}
