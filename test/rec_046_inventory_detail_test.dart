// REC-010 (#46): las tres lecturas del detalle de producto (cabecera, reparto
// por persona y lotes con su procedencia y filtros), y el saldo intacto tras
// rechazar una aplicación por stock (conciliación del 2026-10-19, §3.1).
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
  late int ana, beto, sur, norte, verano, invierno, glifosato, atrazina;
  late int chacoAna;

  Future<int> buy({
    required int supplier,
    required int campaign,
    required DateTime date,
    required List<PurchaseItemDraft> items,
  }) => repo.confirmPurchase(
    PurchaseDraft(
      supplierId: supplier,
      campaignId: campaign,
      purchaseDate: date,
      items: items,
    ),
  );

  PurchaseItemDraft line(int product, int price, Map<int, int> owners) =>
      PurchaseItemDraft(
        productId: product,
        quantityBase: owners.values.fold(0, (sum, q) => sum + q),
        currency: CurrencyCode.bob,
        originalUnitPriceMinor: price,
        allocations: [
          for (final MapEntry(key: person, value: q) in owners.entries)
            AllocationDraft(personId: person, quantityBase: q),
        ],
      );

  /// Glifosato (L), en Bs por litro:
  /// - 05/01, Agro Sur, Verano: Ana 10 L y Beto 5 L a 100,00.
  /// - 10/01, Agro Norte, Verano: Ana 8 L a 120,00.
  /// - 10/03, Agro Sur, Invierno: Beto 6 L a 110,00.
  /// - 20/03: Ana aplica 12 L (FIFO: 10 L del 05/01 y 2 L del 10/01).
  /// - 25/03: Ana transfiere 1 L a Beto (sale del lote del 10/01).
  /// - Plan pendiente en Invierno: 1 ha a 2 L/ha.
  /// Atrazina: Beto 7 L a 50,00 el 05/01 (no debe mezclarse con Glifosato).
  setUp(() async {
    database = openDb(inMemoryDatabasePath);
    repo = AgroRepository(database);
    db = await database.database;
    ana = await repo.addPerson(name: 'Ana', role: PersonRole.family);
    beto = await repo.addPerson(name: 'Beto', role: PersonRole.family);
    sur = await repo.addSupplier(name: 'Agro Sur');
    norte = await repo.addSupplier(name: 'Agro Norte');
    glifosato = await repo.addProduct(name: 'Glifosato');
    atrazina = await repo.addProduct(name: 'Atrazina');
    chacoAna = await repo.addFarm(
      ownerId: ana,
      name: 'Chaco Ana',
      areaM2: 10000,
    );
    verano = await repo.addCampaign(
      name: 'Verano',
      start: DateTime.utc(2026, 1, 1),
    );
    invierno = await repo.addCampaign(
      name: 'Invierno',
      start: DateTime.utc(2026, 3, 1),
    );
    await buy(
      supplier: sur,
      campaign: verano,
      date: DateTime.utc(2026, 1, 5),
      items: [
        line(glifosato, 10000, {ana: 10000, beto: 5000}),
        line(atrazina, 5000, {beto: 7000}),
      ],
    );
    await buy(
      supplier: norte,
      campaign: verano,
      date: DateTime.utc(2026, 1, 10),
      items: [
        line(glifosato, 12000, {ana: 8000}),
      ],
    );
    await repo.activateCampaign(invierno, closeCurrent: true);
    await buy(
      supplier: sur,
      campaign: invierno,
      date: DateTime.utc(2026, 3, 10),
      items: [
        line(glifosato, 11000, {beto: 6000}),
      ],
    );
    await repo.confirmApplication(
      ApplicationDraft(
        personId: ana,
        farmId: chacoAna,
        campaignId: invierno,
        appliedAt: DateTime.utc(2026, 3, 20),
        lines: [
          ApplicationLineDraft(productId: glifosato, quantityBase: 12000),
        ],
      ),
    );
    await repo.transferProductFifo(
      fromPersonId: ana,
      toPersonId: beto,
      productId: glifosato,
      quantityBase: 1000,
      date: DateTime.utc(2026, 3, 25),
    );
    await repo.addPlan(
      farmId: chacoAna,
      campaignId: invierno,
      productId: glifosato,
      areaM2: 10000,
      doseBasePerHa: 2000,
    );
  });

  /// Cabecera y reparto de Glifosato con los valores de la fixture.
  Future<void> expectGlifosatoDetail() async {
    final header = await repo.inventoryProductHeader(glifosato);
    expect(header, {
      'product_id': glifosato,
      'product_name': 'Glifosato',
      'unit': 'L',
      'purchased_base': 29000, // 15 + 8 + 6 L
      'consumed_base': 12000,
      'physical_base': 17000, // 29 − 12 L; la transferencia no cambia el total
      // Ana 5 L a 120; Beto 5 L a 100, 6 L a 110 y 1 L a 120: Bs 1.880,00.
      'value_bob_minor': 188000,
      'committed_base': 2000,
    });
    final distribution = await repo.inventoryProductDistribution(glifosato);
    expect(distribution, [
      {
        'person_id': ana,
        'person_name': 'Ana',
        // Asignación neta (#46/#51): 10 + 8 L comprados menos el litro
        // transferido a Beto. La cifra bruta anterior (18 L) sólo sumaba los
        // movimientos positivos y no descontaba lo entregado.
        'assigned_base': 17000,
        'consumed_base': 12000,
        'available_base': 5000,
      },
      {
        'person_id': beto,
        'person_name': 'Beto',
        'assigned_base': 12000, // 5 + 6 L comprados y 1 L recibido
        'consumed_base': 0,
        'available_base': 12000,
      },
    ]);
    expect(
      distribution.fold<int>(0, (s, r) => s + (r['available_base']! as int)),
      header['physical_base'],
    );
  }

  test('cabecera y reparto por persona del detalle de producto', () async {
    await expectGlifosatoDetail();
    // La Atrazina tiene su propia cabecera y no entra en la de Glifosato.
    final atrazinaHeader = await repo.inventoryProductHeader(atrazina);
    expect(atrazinaHeader['physical_base'], 7000);
    expect(atrazinaHeader['committed_base'], 0);
    expect(
      (await repo.inventoryProductDistribution(atrazina))
          .map((r) => (r['person_name'], r['available_base']))
          .toList(),
      [('Beto', 7000)],
    );
  });

  test(
    'lotes vigentes con su procedencia, en orden FIFO, y sus filtros',
    () async {
      // (responsable, proveedor, campaña, inicial, saldo, costo, derivado)
      List<(Object?, Object?, Object?, Object?, Object?, Object?, bool)> view(
        List<Map<String, Object?>> rows,
      ) => [
        for (final r in rows)
          (
            r['owner_name'],
            r['supplier_name'],
            r['campaign_name'],
            r['initial_quantity_base'],
            r['available_base'],
            r['unit_cost'],
            r['parent_lot_id'] != null,
          ),
      ];
      const beto0501 = ('Beto', 'Agro Sur', 'Verano', 5000, 5000, 10000, false);
      const ana1001 = ('Ana', 'Agro Norte', 'Verano', 8000, 5000, 12000, false);
      // El lote recibido por transferencia conserva la procedencia del origen.
      const beto1001 = (
        'Beto',
        'Agro Norte',
        'Verano',
        1000,
        1000,
        12000,
        true,
      );
      const beto1003 = (
        'Beto',
        'Agro Sur',
        'Invierno',
        6000,
        6000,
        11000,
        false,
      );

      final all = await repo.inventoryProductLots(glifosato);
      // El lote de Ana del 05/01 quedó en 0 y no se muestra.
      expect(view(all), [beto0501, ana1001, beto1001, beto1003]);
      expect(all.map((r) => r['acquired_date']), [
        '2026-01-05T00:00:00.000Z',
        '2026-01-10T00:00:00.000Z',
        '2026-01-10T00:00:00.000Z',
        '2026-03-10T00:00:00.000Z',
      ]);
      expect(all[2]['parent_lot_id'], all[1]['lot_id']);
      expect(all.every((r) => r['currency_code'] == 'BOB'), isTrue);

      expect(view(await repo.inventoryProductLots(glifosato, personId: beto)), [
        beto0501,
        beto1001,
        beto1003,
      ]);
      expect(view(await repo.inventoryProductLots(glifosato, personId: ana)), [
        ana1001,
      ]);
      expect(
        view(await repo.inventoryProductLots(glifosato, supplierId: norte)),
        [ana1001, beto1001],
      );
      expect(
        view(await repo.inventoryProductLots(glifosato, supplierId: sur)),
        [beto0501, beto1003],
      );
      expect(
        view(await repo.inventoryProductLots(glifosato, campaignId: invierno)),
        [beto1003],
      );
      expect(
        view(
          await repo.inventoryProductLots(
            glifosato,
            personId: beto,
            campaignId: verano,
          ),
        ),
        [beto0501, beto1001],
      );
      expect(
        await repo.inventoryProductLots(
          glifosato,
          personId: ana,
          supplierId: sur,
        ),
        isEmpty,
      );
      expect(view(await repo.inventoryProductLots(atrazina)), [
        ('Beto', 'Agro Sur', 'Verano', 7000, 7000, 5000, false),
      ]);
    },
  );

  test('una aplicación rechazada por stock deja el saldo y las tablas como '
      'estaban', () async {
    final before = await dumpTables(db);
    // Ana tiene 5 L; pide 5,001 L.
    await expectLater(
      repo.confirmApplication(
        ApplicationDraft(
          personId: ana,
          farmId: chacoAna,
          campaignId: invierno,
          appliedAt: DateTime.utc(2026, 3, 28),
          lines: [
            ApplicationLineDraft(productId: glifosato, quantityBase: 5001),
          ],
        ),
      ),
      throwsA(
        isA<BusinessRuleException>().having(
          (e) => e.message,
          'message',
          'Stock insuficiente para confirmar la aplicación.',
        ),
      ),
    );
    expect(await dumpTables(db), before);
    expect((await stockByPersonProduct(db))[(ana, glifosato)], 5000);
    await expectGlifosatoDetail();
  });
}
