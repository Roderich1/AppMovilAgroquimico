// REC-012 (#48): rechazo de una transferencia con el mismo origen y destino, y
// de la reversión cuando el stock destino ya tuvo movimientos (conciliación
// del 2026-10-19, §3.1). La reversión multiproducto y la doble reversión las
// cubre `f04_bug_01_reverse_transfer_test.dart`; aquí no se repiten. El CHECK
// del motor (`from_person_id <> to_person_id`) está en
// `rec_039_schema_constraints_test.dart`.
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
  late int ana, beto, caro, campaign, chacoBeto, glifosato, atrazina;

  /// Ana compra 10 L de Glifosato y 5 L de Atrazina.
  setUp(() async {
    database = openDb(inMemoryDatabasePath);
    repo = AgroRepository(database);
    db = await database.database;
    ana = await repo.addPerson(name: 'Ana', role: PersonRole.family);
    beto = await repo.addPerson(name: 'Beto', role: PersonRole.family);
    caro = await repo.addPerson(name: 'Caro', role: PersonRole.family);
    final supplier = await repo.addSupplier(name: 'Proveedor');
    campaign = await repo.addCampaign(
      name: 'Verano',
      start: DateTime.utc(2026, 1, 1),
    );
    glifosato = await repo.addProduct(name: 'Glifosato');
    atrazina = await repo.addProduct(name: 'Atrazina');
    chacoBeto = await repo.addFarm(
      ownerId: beto,
      name: 'Chaco Beto',
      areaM2: 10000,
    );
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
        items: [line(glifosato, 10000, 10000), line(atrazina, 5000, 8000)],
      ),
    );
  });

  Matcher rejected(String message) => throwsA(
    isA<BusinessRuleException>().having((e) => e.message, 'message', message),
  );

  Future<int> transferToBeto() => repo.transferProductsFifo(
    fromPersonId: ana,
    toPersonId: beto,
    items: [
      TransferItemDraft(productId: glifosato, quantityBase: 4000),
      TransferItemDraft(productId: atrazina, quantityBase: 2000),
    ],
    date: DateTime.utc(2026, 1, 10),
  );

  Future<String?> status(int transfer) async =>
      (await db.query(
            'transfers',
            columns: ['status'],
            where: 'id=?',
            whereArgs: [transfer],
          )).single['status']
          as String?;

  test(
    'una transferencia con el mismo origen y destino se rechaza sin efectos',
    () async {
      final before = await dumpTables(db);
      await expectLater(
        repo.transferProductsFifo(
          fromPersonId: ana,
          toPersonId: ana,
          items: [
            TransferItemDraft(productId: glifosato, quantityBase: 1000),
            TransferItemDraft(productId: atrazina, quantityBase: 1000),
          ],
        ),
        rejected('El origen y el destino deben ser diferentes.'),
      );
      final lot = (await db.query('inventory_lots', orderBy: 'id')).first;
      await expectLater(
        repo.transferStock(
          sourceLotId: lot['id']! as int,
          destinationPersonId: ana,
          quantityBase: 1000,
        ),
        rejected('El origen y el destino deben ser diferentes.'),
      );
      expect(await dumpTables(db), before);
      expect(before['transfers'], isEmpty);
      expect(await stockByPersonProduct(db), {
        (ana, glifosato): 10000,
        (ana, atrazina): 5000,
      });
    },
  );

  test('si el destino ya aplicó parte de lo recibido, la reversión se rechaza '
      'sin efectos y procede tras revertir esa aplicación', () async {
    final transfer = await transferToBeto();
    final application = await repo.confirmApplication(
      ApplicationDraft(
        personId: beto,
        farmId: chacoBeto,
        campaignId: campaign,
        appliedAt: DateTime.utc(2026, 1, 15),
        lines: [ApplicationLineDraft(productId: glifosato, quantityBase: 1000)],
      ),
    );
    final before = await dumpTables(db);

    await expectLater(
      repo.reverseTransfer(transfer, reason: 'Error'),
      rejected(
        'El stock transferido ya tuvo movimientos. Reviértalos antes de continuar.',
      ),
    );
    expect(await dumpTables(db), before);
    expect(await status(transfer), 'CONFIRMED');
    expect(await stockByPersonProduct(db), {
      (ana, glifosato): 6000,
      (ana, atrazina): 3000,
      (beto, glifosato): 3000,
      (beto, atrazina): 2000,
    });

    // Al revertir la aplicación, el lote destino vuelve a tener lo recibido
    // y la transferencia sí se revierte.
    await repo.reverseApplication(application);
    await repo.reverseTransfer(transfer);
    expect(await status(transfer), 'REVERSED');
    final stock = await stockByPersonProduct(db);
    expect(stock[(ana, glifosato)], 10000);
    expect(stock[(ana, atrazina)], 5000);
    expect(stock[(beto, glifosato)], 0);
    expect(stock[(beto, atrazina)], 0);
  });

  test('si el destino ya transfirió parte de otro producto recibido, la '
      'reversión se rechaza sin efectos', () async {
    final transfer = await transferToBeto();
    // Beto pasa 0,5 L de la Atrazina recibida a Caro.
    await repo.transferProductFifo(
      fromPersonId: beto,
      toPersonId: caro,
      productId: atrazina,
      quantityBase: 500,
      date: DateTime.utc(2026, 1, 12),
    );
    final before = await dumpTables(db);

    await expectLater(
      repo.reverseTransfer(transfer),
      rejected(
        'El stock transferido ya tuvo movimientos. Reviértalos antes de continuar.',
      ),
    );
    expect(await dumpTables(db), before);
    expect(await status(transfer), 'CONFIRMED');
    expect(await stockByPersonProduct(db), {
      (ana, glifosato): 6000,
      (ana, atrazina): 3000,
      (beto, glifosato): 4000,
      (beto, atrazina): 1500,
      (caro, atrazina): 500,
    });
  });
}
