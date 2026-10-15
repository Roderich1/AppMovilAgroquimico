// F04-BUG-01 (#73): la reversión de una transferencia multiproducto debe usar
// el producto de cada lote, nunca el de la cabecera `transfers`, y la
// migración a v7 repara los movimientos que la regla anterior dejó mal.
import 'dart:io';

import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  /// Escenario mínimo: dos responsables, un proveedor, una campaña y tres
  /// productos con stock del origen.
  Future<
    ({
      AppDatabase database,
      AgroRepository repo,
      int owner,
      int receiver,
      List<int> products,
    })
  >
  escenario(String path) async {
    final database = AppDatabase(factory: databaseFactoryFfi, path: path);
    final repo = AgroRepository(database);
    final owner = await repo.addPerson(name: 'Origen', role: PersonRole.family);
    final receiver = await repo.addPerson(
      name: 'Destino',
      role: PersonRole.family,
    );
    final supplier = await repo.addSupplier(name: 'Proveedor');
    final campaign = await repo.addCampaign(
      name: 'Campaña 1',
      start: DateTime.utc(2026, 1, 1),
    );
    final products = [
      await repo.addProduct(name: 'Glifosato'),
      await repo.addProduct(name: 'Atrazina'),
      await repo.addProduct(name: 'Mancozeb', unit: 'KG'),
    ];

    Future<void> comprar(int product, int quantity, DateTime date) =>
        repo.confirmPurchase(
          PurchaseDraft(
            supplierId: supplier,
            campaignId: campaign,
            purchaseDate: date,
            items: [
              PurchaseItemDraft(
                productId: product,
                quantityBase: quantity,
                currency: CurrencyCode.bob,
                originalUnitPriceMinor: 10000,
                allocations: [
                  AllocationDraft(personId: owner, quantityBase: quantity),
                ],
              ),
            ],
          ),
        );

    // El primer producto tiene dos lotes para que la transferencia y su
    // reversión recorran FIFO con más de un lote.
    await comprar(products[0], 10000, DateTime.utc(2026, 1, 2));
    await comprar(products[0], 20000, DateTime.utc(2026, 1, 3));
    await comprar(products[1], 15000, DateTime.utc(2026, 1, 4));
    await comprar(products[2], 8000, DateTime.utc(2026, 1, 5));
    return (
      database: database,
      repo: repo,
      owner: owner,
      receiver: receiver,
      products: products,
    );
  }

  /// Saldo disponible por producto de un responsable (0 si no tiene filas).
  Future<Map<int, int>> saldos(
    AgroRepository repo,
    int personId,
    List<int> products,
  ) async {
    final rows = await repo.personStockSummary(personId);
    final byProduct = {
      for (final row in rows)
        row['product_id']! as int: row['available_base']! as int,
    };
    return {for (final product in products) product: byProduct[product] ?? 0};
  }

  /// Ningún responsable queda con saldo negativo en ningún producto.
  Future<void> sinSaldosNegativos(AppDatabase database) async {
    final db = await database.database;
    final negativos = await db.rawQuery(
      '''SELECT owner_person_id, product_id, SUM(quantity_signed) saldo
      FROM inventory_movements GROUP BY owner_person_id, product_id
      HAVING saldo < 0''',
    );
    expect(negativos, isEmpty, reason: 'ningún saldo puede quedar negativo');
  }

  /// Movimientos de reversión cuyo producto difiere del de su lote.
  Future<List<Map<String, Object?>>> reversionesDescuadradas(
    DatabaseExecutor db,
  ) => db.rawQuery('''SELECT m.id FROM inventory_movements m
    JOIN inventory_lots l ON l.id=m.lot_id
    WHERE m.type IN ('TRANSFER_REVERSAL_IN','TRANSFER_REVERSAL_OUT')
      AND m.product_id <> l.product_id''');

  Future<int> transferirTres(
    AgroRepository repo,
    int owner,
    int receiver,
    List<int> products,
  ) => repo.transferProductsFifo(
    fromPersonId: owner,
    toPersonId: receiver,
    items: [
      TransferItemDraft(productId: products[0], quantityBase: 25000),
      TransferItemDraft(productId: products[1], quantityBase: 5000),
      TransferItemDraft(productId: products[2], quantityBase: 8000),
    ],
  );

  group('reverseTransfer usa el producto de cada lote', () {
    test('revertir una transferencia de 3 productos deja cada saldo igual al previo', () async {
      final s = await escenario(inMemoryDatabasePath);
      addTearDown(s.database.close);

      final origenAntes = await saldos(s.repo, s.owner, s.products);
      final destinoAntes = await saldos(s.repo, s.receiver, s.products);
      expect(origenAntes, {
        s.products[0]: 30000,
        s.products[1]: 15000,
        s.products[2]: 8000,
      });
      expect(destinoAntes.values, everyElement(0));

      final transfer = await transferirTres(
        s.repo,
        s.owner,
        s.receiver,
        s.products,
      );
      // La transferencia sí movió los tres productos.
      expect(await saldos(s.repo, s.receiver, s.products), {
        s.products[0]: 25000,
        s.products[1]: 5000,
        s.products[2]: 8000,
      });

      await s.repo.reverseTransfer(transfer);

      expect(await saldos(s.repo, s.owner, s.products), origenAntes);
      expect(await saldos(s.repo, s.receiver, s.products), destinoAntes);
      await sinSaldosNegativos(s.database);

      final db = await s.database.database;
      expect(await reversionesDescuadradas(db), isEmpty);
      // Cada producto tiene sus propios movimientos de reversión.
      final productosRevertidos = (await db.rawQuery(
        '''SELECT DISTINCT product_id FROM inventory_movements
          WHERE reference_type='TRANSFER_REVERSAL' AND reference_id=?''',
        [transfer],
      )).map((row) => row['product_id']! as int).toSet();
      expect(productosRevertidos, s.products.toSet());
    });

    test('regresión: una transferencia de un solo producto se revierte igual que antes', () async {
      final s = await escenario(inMemoryDatabasePath);
      addTearDown(s.database.close);
      final product = s.products[0];
      final origenAntes = await saldos(s.repo, s.owner, s.products);

      final transfer = await s.repo.transferProductFifo(
        fromPersonId: s.owner,
        toPersonId: s.receiver,
        productId: product,
        quantityBase: 25000,
      );
      await s.repo.reverseTransfer(transfer);

      expect(await saldos(s.repo, s.owner, s.products), origenAntes);
      expect(
        (await saldos(s.repo, s.receiver, s.products)).values,
        everyElement(0),
      );
      await sinSaldosNegativos(s.database);

      final db = await s.database.database;
      final lotItems = await db.query(
        'transfer_lot_items',
        where: 'transfer_id=?',
        whereArgs: [transfer],
        orderBy: 'id',
      );
      // FIFO con dos lotes: 10000 del primero y 15000 del segundo.
      expect(lotItems.map((row) => row['quantity_base']), [10000, 15000]);

      final reversiones = await db.query(
        'inventory_movements',
        where: "reference_type='TRANSFER_REVERSAL' AND reference_id=?",
        whereArgs: [transfer],
        orderBy: 'id',
      );
      // Igual que antes: por cada lote, una entrada al origen y una salida
      // del destino, con el producto de la transferencia.
      expect(
        reversiones.map(
          (row) => (
            row['type'],
            row['lot_id'],
            row['owner_person_id'],
            row['quantity_signed'],
            row['product_id'],
          ),
        ),
        [
          for (final item in lotItems) ...[
            (
              'TRANSFER_REVERSAL_IN',
              item['source_lot_id'],
              s.owner,
              item['quantity_base'],
              product,
            ),
            (
              'TRANSFER_REVERSAL_OUT',
              item['destination_lot_id'],
              s.receiver,
              -(item['quantity_base']! as int),
              product,
            ),
          ],
        ],
      );
      final cabecera = (await db.query(
        'transfers',
        where: 'id=?',
        whereArgs: [transfer],
      )).single;
      expect(cabecera['status'], 'REVERSED');
      expect(cabecera['reversed_at'], isNotNull);
      final destinos = await db.query(
        'inventory_lots',
        where:
            'id IN (SELECT destination_lot_id FROM transfer_lot_items '
            'WHERE transfer_id=?)',
        whereArgs: [transfer],
      );
      expect(
        destinos.map((row) => row['reversed_at']),
        everyElement(isNotNull),
      );
    });
  });

  group('migración a v7: reparación de reversiones', () {
    /// Base v6 con una transferencia de 3 productos revertida con la regla
    /// anterior: todos los movimientos `TRANSFER_REVERSAL_*` llevan el
    /// producto de la cabecera. El esquema de v6 y v7 es el mismo; solo
    /// cambian los datos y `user_version`.
    Future<
      ({
        String path,
        int owner,
        int receiver,
        List<int> products,
        int reescritas,
      })
    >
    baseV6ConDefecto() async {
      final directory = await Directory.systemTemp.createTemp('agro_v7_');
      addTearDown(() => directory.delete(recursive: true));
      final path = p.join(directory.path, 'v6.db');

      final s = await escenario(path);
      final transfer = await transferirTres(
        s.repo,
        s.owner,
        s.receiver,
        s.products,
      );
      await s.repo.reverseTransfer(transfer);
      final db = await s.database.database;
      // Reproduce lo que escribía `reverseTransfer` hasta v6: el producto de
      // la cabecera en todos los movimientos de reversión.
      final reescritas = await db.rawUpdate(
        '''UPDATE inventory_movements SET product_id =
          (SELECT t.product_id FROM transfers t WHERE t.id=reference_id)
        WHERE reference_type='TRANSFER_REVERSAL' AND reference_id=?''',
        [transfer],
      );
      await db.execute('PRAGMA user_version = 6');
      await s.database.close();
      return (
        path: path,
        owner: s.owner,
        receiver: s.receiver,
        products: s.products,
        reescritas: reescritas,
      );
    }

    Future<List<Map<String, Object?>>> movimientos(DatabaseExecutor db) =>
        db.query('inventory_movements', orderBy: 'id');

    test(
      'la base v6 sembrada tiene el defecto: saldos descuadrados por producto',
      () async {
        final seed = await baseV6ConDefecto();
        final legacy = await databaseFactoryFfi.openDatabase(seed.path);
        addTearDown(legacy.close);
        expect(
          (await legacy.rawQuery('PRAGMA user_version')).first.values.first,
          6,
        );
        // 2 movimientos por lote: el primer producto usa 2 lotes, los otros
        // uno cada uno, pero solo los de los productos 2 y 3 quedan mal.
        expect(seed.reescritas, 8);
        expect(await reversionesDescuadradas(legacy), hasLength(4));
        final negativos = await legacy.rawQuery(
          '''SELECT product_id FROM inventory_movements
          GROUP BY owner_person_id, product_id HAVING SUM(quantity_signed) < 0''',
        );
        expect(negativos, isNotEmpty);
      },
    );

    test(
      'abrir la base v6 con AppDatabase repara los movimientos y cuadra saldos',
      () async {
        final seed = await baseV6ConDefecto();

        final legacy = await databaseFactoryFfi.openDatabase(seed.path);
        final antes = await movimientos(legacy);
        final descuadradas = (await reversionesDescuadradas(legacy))
            .map((row) => row['id'])
            .toSet();
        await legacy.close();

        final migrated = AppDatabase(
          factory: databaseFactoryFfi,
          path: seed.path,
        );
        addTearDown(migrated.close);
        final repo = AgroRepository(migrated);
        final db = await migrated.database;

        expect(
          (await db.rawQuery('PRAGMA user_version')).first.values.first,
          AppDatabase.schemaVersion,
        );
        expect(AppDatabase.schemaVersion, 7);
        expect(await reversionesDescuadradas(db), isEmpty);

        // Solo cambian las filas reparadas, y solo en su producto.
        final despues = await movimientos(db);
        expect(despues, hasLength(antes.length));
        for (var i = 0; i < antes.length; i++) {
          final before = Map.of(antes[i]);
          final after = Map.of(despues[i]);
          if (descuadradas.contains(before['id'])) {
            expect(after['product_id'], isNot(before['product_id']));
            before.remove('product_id');
            after.remove('product_id');
          }
          expect(after, before);
        }

        expect(
          (await db.query(
            'app_settings',
            where: 'key=?',
            whereArgs: [AppDatabase.transferReversalRepairKey],
          )).single['value'],
          '${descuadradas.length}',
        );

        expect(await saldos(repo, seed.owner, seed.products), {
          seed.products[0]: 30000,
          seed.products[1]: 15000,
          seed.products[2]: 8000,
        });
        expect(
          (await saldos(repo, seed.receiver, seed.products)).values,
          everyElement(0),
        );
        await sinSaldosNegativos(migrated);
      },
    );

    test(
      'la reparación es idempotente: otra ejecución no cambia filas',
      () async {
        final seed = await baseV6ConDefecto();
        final migrated = AppDatabase(
          factory: databaseFactoryFfi,
          path: seed.path,
        );
        final db = await migrated.database;
        final trasMigrar = await movimientos(db);
        final ajustes = await db.query('app_settings', orderBy: 'key');

        expect(await AppDatabase.repairTransferReversalProducts(db), 0);
        expect(await movimientos(db), trasMigrar);
        await migrated.close();

        // Reabrir una base ya en v7 no vuelve a migrar ni a registrar nada.
        final reopened = AppDatabase(
          factory: databaseFactoryFfi,
          path: seed.path,
        );
        addTearDown(reopened.close);
        final again = await reopened.database;
        expect(await movimientos(again), trasMigrar);
        expect(await again.query('app_settings', orderBy: 'key'), ajustes);
        expect(await AppDatabase.repairTransferReversalProducts(again), 0);
      },
    );

    test(
      'una base nueva nace en v7 sin nada que reparar ni registrar',
      () async {
        final database = AppDatabase(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
        );
        addTearDown(database.close);
        final db = await database.database;
        expect(
          (await db.rawQuery('PRAGMA user_version')).first.values.first,
          7,
        );
        expect(
          await db.query(
            'app_settings',
            where: 'key=?',
            whereArgs: [AppDatabase.transferReversalRepairKey],
          ),
          isEmpty,
        );
      },
    );
  });
}
