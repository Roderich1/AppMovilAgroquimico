// REC-011 (#47): atomicidad de una aplicación multiproducto, cantidades ≤ 0,
// `variance_quantity_base` y `estimateFifoCost` frente al costo real, con sus
// consumos por ítem (conciliación del 2026-10-19, §3.1). El saldo intacto
// tras rechazar una aplicación por stock está en
// `rec_046_inventory_detail_test.dart`; no se repite aquí.
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/campaign_calendar.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/money.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late AgroRepository repo;
  late Database db;
  late int ana, campaign, farm, glifosato, atrazina;
  late int glifosatoEnero, glifosatoFebrero, atrazinaEnero;

  /// Ana tiene Glifosato en dos lotes, 10 L a Bs 100,00 (05/01) y 10 L a
  /// Bs 130,00 (10/02), y Atrazina en KG, 4 kg a Bs 200,00 (05/01).
  setUp(() async {
    database = openDb(inMemoryDatabasePath);
    repo = AgroRepository(database);
    db = await database.database;
    ana = await repo.addPerson(name: 'Ana', role: PersonRole.family);
    final supplier = await repo.addSupplier(name: 'Proveedor');
    campaign = await repo.addCampaign(
      name: 'Verano',
      start: DateTime.utc(2026, 1, 1),
    );
    glifosato = await repo.addProduct(name: 'Glifosato');
    atrazina = await repo.addProduct(name: 'Atrazina', unit: 'KG');
    farm = await repo.addFarm(ownerId: ana, name: 'Chaco Ana', areaM2: 50000);
    PurchaseItemDraft line(int product, int quantity, int price) =>
        PurchaseItemDraft(
          productId: product,
          quantityBase: quantity,
          currency: CurrencyCode.bob,
          originalUnitPriceMinor: price,
          allocations: [AllocationDraft(personId: ana, quantityBase: quantity)],
        );
    await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: supplier,
        campaignId: campaign,
        purchaseDate: DateTime.utc(2026, 1, 5),
        items: [line(glifosato, 10000, 10000), line(atrazina, 4000, 20000)],
      ),
    );
    await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: supplier,
        campaignId: campaign,
        purchaseDate: DateTime.utc(2026, 2, 10),
        items: [line(glifosato, 10000, 13000)],
      ),
    );
    final lots = await db.query('inventory_lots', orderBy: 'id');
    glifosatoEnero = lots[0]['id']! as int;
    atrazinaEnero = lots[1]['id']! as int;
    glifosatoFebrero = lots[2]['id']! as int;
    expect(
      [
        for (final l in lots)
          (l['product_id'], l['unit_cost_bob_minor_per_major_unit']),
      ],
      [(glifosato, 10000), (atrazina, 20000), (glifosato, 13000)],
    );
  });

  ApplicationDraft application(List<ApplicationLineDraft> lines) =>
      ApplicationDraft(
        personId: ana,
        farmId: farm,
        campaignId: campaign,
        appliedAt: DateTime.utc(2026, 3, 1),
        lines: lines,
      );

  Matcher rejected(String message) => throwsA(
    isA<BusinessRuleException>().having((e) => e.message, 'message', message),
  );

  test('si una línea no tiene stock, no queda ningún efecto de las demás', () async {
    final before = await dumpTables(db);
    // La Atrazina alcanza (3 de 4 kg) y se procesa primero; el Glifosato
    // pide 20,001 L de 20 L. D-03 (decisión del autor del 2026-10-27): con
    // fecha pasada el mensaje indica producto, fecha y existencia
    // elegible; antes era «Stock insuficiente para confirmar la
    // aplicación.».
    await expectLater(
      repo.confirmApplication(
        application([
          ApplicationLineDraft(productId: atrazina, quantityBase: 3000),
          ApplicationLineDraft(productId: glifosato, quantityBase: 20001),
        ]),
      ),
      rejected(
        'Glifosato: el ${formatDate(localDay(DateTime.utc(2026, 3, 1)))} esa persona tenía 20 L; pidió 20,001 L. '
        'Una aplicación con fecha pasada sólo puede usar lo que esa persona '
        'ya tenía ese día y no se usó después: no cuenta el producto '
        'comprado o recibido más tarde. Revise la fecha o la cantidad. No '
        'se registró nada.',
      ),
    );
    expect(await dumpTables(db), before);
    for (final table in [
      'applications',
      'application_items',
      'application_consumptions',
      'account_transactions',
    ]) {
      expect(before[table], isEmpty, reason: table);
    }
    expect(await stockByPersonProduct(db), {
      (ana, glifosato): 20000,
      (ana, atrazina): 4000,
    });
  });

  test(
    'una línea con cantidad cero o negativa se rechaza sin efectos',
    () async {
      final before = await dumpTables(db);
      for (final lines in [
        [ApplicationLineDraft(productId: glifosato, quantityBase: 0)],
        [
          ApplicationLineDraft(productId: atrazina, quantityBase: 1000),
          ApplicationLineDraft(productId: glifosato, quantityBase: -500),
        ],
      ]) {
        await expectLater(
          repo.confirmApplication(application(lines)),
          rejected('La cantidad aplicada debe ser mayor a cero.'),
        );
        expect(await dumpTables(db), before);
      }
    },
  );

  test(
    'variance_quantity_base guarda la cantidad real menos la teórica',
    () async {
      final id = await repo.confirmApplication(
        application([
          ApplicationLineDraft(
            productId: glifosato,
            quantityBase: 12000,
            treatedAreaM2: 50000,
            doseBasePerHa: 2300,
            theoreticalQuantityBase: 11500,
          ),
          ApplicationLineDraft(
            productId: atrazina,
            quantityBase: 1500,
            treatedAreaM2: 50000,
            doseBasePerHa: 400,
            theoreticalQuantityBase: 2000,
          ),
        ]),
      );
      expect(
        await db.query(
          'application_items',
          columns: [
            'product_id',
            'quantity_base',
            'theoretical_quantity_base',
            'variance_quantity_base',
            'unit',
          ],
          where: 'application_id=?',
          whereArgs: [id],
          orderBy: 'id',
        ),
        [
          {
            'product_id': glifosato,
            'quantity_base': 12000,
            'theoretical_quantity_base': 11500,
            'variance_quantity_base': 500,
            'unit': 'L',
          },
          {
            'product_id': atrazina,
            'quantity_base': 1500,
            'theoretical_quantity_base': 2000,
            'variance_quantity_base': -500,
            'unit': 'KG',
          },
        ],
      );
      // Sin cantidad teórica no hay variación que registrar.
      final plain = await repo.confirmApplication(
        application([
          ApplicationLineDraft(productId: glifosato, quantityBase: 1000),
        ]),
      );
      final item = (await db.query(
        'application_items',
        where: 'application_id=?',
        whereArgs: [plain],
      )).single;
      expect(item['theoretical_quantity_base'], isNull);
      expect(item['variance_quantity_base'], isNull);
    },
  );

  test('estimateFifoCost coincide con el costo real de la aplicación y sus '
      'consumos por ítem', () async {
    // 12 L de Glifosato: 10 L a 100,00 + 2 L a 130,00 = Bs 1.260,00.
    // 1,5 kg de Atrazina a 200,00 = Bs 300,00.
    expect(
      await repo.estimateFifoCost(
        personId: ana,
        productId: glifosato,
        quantityBase: 12000,
      ),
      126000,
    );
    expect(
      await repo.estimateFifoCost(
        personId: ana,
        productId: atrazina,
        quantityBase: 1500,
      ),
      30000,
    );

    final id = await repo.confirmApplication(
      application([
        ApplicationLineDraft(productId: glifosato, quantityBase: 12000),
        ApplicationLineDraft(productId: atrazina, quantityBase: 1500),
      ]),
    );

    final items = await db.query(
      'application_items',
      where: 'application_id=?',
      whereArgs: [id],
      orderBy: 'id',
    );
    expect(
      items.map(
        (i) => (
          i['product_id'],
          i['cost_bob_minor'],
          i['fifo_estimated_cost_bob_minor'],
        ),
      ),
      [(glifosato, 126000, 126000), (atrazina, 30000, 30000)],
    );
    final consumptions = await db.rawQuery(
      '''SELECT i.product_id, c.inventory_lot_id, c.quantity_consumed_base,
      c.cost_bob_minor FROM application_consumptions c
      JOIN application_items i ON i.id=c.application_item_id
      WHERE i.application_id=? ORDER BY c.id''',
      [id],
    );
    expect(
      consumptions.map(
        (c) => (
          c['product_id'],
          c['inventory_lot_id'],
          c['quantity_consumed_base'],
          c['cost_bob_minor'],
        ),
      ),
      [
        (glifosato, glifosatoEnero, 10000, 100000),
        (glifosato, glifosatoFebrero, 2000, 26000),
        (atrazina, atrazinaEnero, 1500, 30000),
      ],
    );
    final header = (await db.query(
      'applications',
      where: 'id=?',
      whereArgs: [id],
    )).single;
    expect(header['total_cost_bob_minor'], 156000);
    expect(
      await db.query(
        'account_transactions',
        columns: ['type', 'amount_bob_minor_signed', 'reference_id'],
      ),
      [
        {
          'type': 'USAGE_CHARGE',
          'amount_bob_minor_signed': 156000,
          'reference_id': id,
        },
      ],
    );

    // Después, la estimación sigue el FIFO restante: 8 L a 130,00.
    expect(
      await repo.estimateFifoCost(
        personId: ana,
        productId: glifosato,
        quantityBase: 8000,
      ),
      104000,
    );
  });
}
