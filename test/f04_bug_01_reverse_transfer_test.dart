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

  /// Saldo de cada lote (suma de sus movimientos).
  Future<Map<int, int>> saldosPorLote(DatabaseExecutor db) async => {
    for (final row in await db.rawQuery(
      '''SELECT l.id, COALESCE(SUM(m.quantity_signed),0) saldo
      FROM inventory_lots l LEFT JOIN inventory_movements m ON m.lot_id=l.id
      GROUP BY l.id''',
    ))
      row['id']! as int: row['saldo']! as int,
  };

  /// Saldo por (responsable, producto) de todas las combinaciones con filas.
  Future<Map<(int, int), int>> saldosPersonaProducto(
    DatabaseExecutor db,
  ) async => {
    for (final row in await db.rawQuery(
      '''SELECT owner_person_id persona, product_id producto,
      SUM(quantity_signed) saldo
      FROM inventory_movements GROUP BY owner_person_id, product_id''',
    ))
      (row['persona']! as int, row['producto']! as int): row['saldo']! as int,
  };

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

    test('revertir 3 productos: cada fila con su lote, responsable, cantidad y producto; lotes y estados', () async {
      final s = await escenario(inMemoryDatabasePath);
      addTearDown(s.database.close);
      final db = await s.database.database;
      final lotesAntes = await saldosPorLote(db);
      final personaProductoAntes = await saldosPersonaProducto(db);

      final transfer = await transferirTres(
        s.repo,
        s.owner,
        s.receiver,
        s.products,
      );
      final lineas = await db.query(
        'transfer_lot_items',
        where: 'transfer_id=?',
        whereArgs: [transfer],
        orderBy: 'id',
      );
      final productoDeLote = {
        for (final row in await db.query('inventory_lots'))
          row['id']! as int: row['product_id']! as int,
      };
      // Cada lote destino conserva el producto de su lote origen.
      for (final item in lineas) {
        expect(
          productoDeLote[item['destination_lot_id']],
          productoDeLote[item['source_lot_id']],
        );
      }

      await s.repo.reverseTransfer(transfer);

      // Por cada línea, una entrada al origen y una salida del destino, con el
      // responsable de cada lado y el producto de su propio lote.
      final reversiones = await db.query(
        'inventory_movements',
        where: "reference_type='TRANSFER_REVERSAL' AND reference_id=?",
        whereArgs: [transfer],
        orderBy: 'id',
      );
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
          for (final item in lineas) ...[
            (
              'TRANSFER_REVERSAL_IN',
              item['source_lot_id'],
              s.owner,
              item['quantity_base'],
              productoDeLote[item['source_lot_id']],
            ),
            (
              'TRANSFER_REVERSAL_OUT',
              item['destination_lot_id'],
              s.receiver,
              -(item['quantity_base']! as int),
              productoDeLote[item['destination_lot_id']],
            ),
          ],
        ],
      );

      // Los lotes previos vuelven a su saldo y los lotes destino quedan en 0.
      final lotesDespues = await saldosPorLote(db);
      for (final lote in lotesAntes.entries) {
        expect(lotesDespues[lote.key], lote.value, reason: 'lote ${lote.key}');
      }
      for (final item in lineas) {
        expect(lotesDespues[item['destination_lot_id']], 0);
      }

      // Responsable × producto: el origen recupera lo previo y el destino
      // queda en 0 en cada producto.
      final personaProductoDespues = await saldosPersonaProducto(db);
      for (final saldo in personaProductoAntes.entries) {
        expect(personaProductoDespues[saldo.key], saldo.value);
      }
      for (final product in s.products) {
        expect(personaProductoDespues[(s.receiver, product)] ?? 0, 0);
      }

      // Estados y relaciones: cabecera y lotes destino revertidos, líneas sin
      // cambios.
      final cabecera = (await db.query(
        'transfers',
        where: 'id=?',
        whereArgs: [transfer],
      )).single;
      expect(cabecera['status'], 'REVERSED');
      expect(cabecera['reversed_at'], isNotNull);
      expect(
        await db.query(
          'transfer_lot_items',
          where: 'transfer_id=?',
          whereArgs: [transfer],
          orderBy: 'id',
        ),
        lineas,
      );
      final destinos = await db.query(
        'inventory_lots',
        where:
            'id IN (SELECT destination_lot_id FROM transfer_lot_items '
            'WHERE transfer_id=?)',
        whereArgs: [transfer],
      );
      expect(destinos, hasLength(lineas.length));
      expect(
        destinos.map((row) => row['reversed_at']),
        everyElement(isNotNull),
      );

      // Una segunda reversión se rechaza y no escribe movimientos.
      final totalMovimientos = (await db.query('inventory_movements')).length;
      await expectLater(
        s.repo.reverseTransfer(transfer),
        throwsA(isA<BusinessRuleException>()),
      );
      expect((await db.query('inventory_movements')).length, totalMovimientos);
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
    /// Base v6 con una transferencia de 3 productos revertida. Con
    /// [conDefecto], la reversión queda como la dejaba la regla anterior:
    /// todos los movimientos `TRANSFER_REVERSAL_*` llevan el producto de la
    /// cabecera. Sin él, queda correcta. El esquema de v6 y v7 es el mismo;
    /// solo cambian los datos y `user_version`.
    Future<
      ({
        String path,
        int owner,
        int receiver,
        List<int> products,
        int transfer,
        int reescritas,
      })
    >
    baseV6({bool conDefecto = true}) async {
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
      final reescritas = conDefecto
          ? await db.rawUpdate(
              '''UPDATE inventory_movements SET product_id =
                (SELECT t.product_id FROM transfers t WHERE t.id=reference_id)
              WHERE reference_type='TRANSFER_REVERSAL' AND reference_id=?''',
              [transfer],
            )
          : 0;
      await db.execute('PRAGMA user_version = 6');
      await s.database.close();
      return (
        path: path,
        owner: s.owner,
        receiver: s.receiver,
        products: s.products,
        transfer: transfer,
        reescritas: reescritas,
      );
    }

    Future<List<Map<String, Object?>>> movimientos(DatabaseExecutor db) =>
        db.query('inventory_movements', orderBy: 'id');

    test(
      'la base v6 sembrada tiene el defecto: saldos descuadrados por producto',
      () async {
        final seed = await baseV6();
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
        final seed = await baseV6();

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
        // La reparación es de v7; versiones posteriores la conservan.
        expect(AppDatabase.schemaVersion, greaterThanOrEqualTo(7));
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
        final seed = await baseV6();
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

    test('una base nueva nace en la versión actual sin nada que reparar ni registrar', () async {
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      addTearDown(database.close);
      final db = await database.database;
      expect(
        (await db.rawQuery('PRAGMA user_version')).first.values.first,
        AppDatabase.schemaVersion,
      );
      expect(
        await db.query(
          'app_settings',
          where: 'key=?',
          whereArgs: [AppDatabase.transferReversalRepairKey],
        ),
        isEmpty,
      );
    });

    test('la reparación solo toca movimientos TRANSFER_REVERSAL_*: otro movimiento descuadrado no cambia', () async {
      final seed = await baseV6();

      // Un movimiento que no es de reversión (la salida de la transferencia
      // del segundo producto) se descuadra a propósito. La migración v7 no
      // debe corregirlo: su alcance son solo las reversiones.
      final legacy = await databaseFactoryFfi.openDatabase(seed.path);
      final ajeno = (await legacy.query(
        'inventory_movements',
        where: "type='TRANSFER_OUT' AND reference_id=? AND product_id=?",
        whereArgs: [seed.transfer, seed.products[1]],
      )).single;
      await legacy.update(
        'inventory_movements',
        {'product_id': seed.products[0]},
        where: 'id=?',
        whereArgs: [ajeno['id']],
      );
      final antes = await movimientos(legacy);
      final descuadradas = (await reversionesDescuadradas(legacy))
          .map((row) => row['id'])
          .toSet();
      expect(descuadradas, hasLength(4));
      await legacy.close();

      final migrated = AppDatabase(
        factory: databaseFactoryFfi,
        path: seed.path,
      );
      addTearDown(migrated.close);
      final db = await migrated.database;

      final despues = await movimientos(db);
      expect(despues, hasLength(antes.length));
      for (var i = 0; i < antes.length; i++) {
        if (descuadradas.contains(antes[i]['id'])) continue;
        expect(despues[i], antes[i]);
      }
      final ajenoDespues = despues.singleWhere(
        (row) => row['id'] == ajeno['id'],
      );
      expect(ajenoDespues['type'], 'TRANSFER_OUT');
      expect(ajenoDespues['product_id'], seed.products[0]);
      expect(
        (await db.query(
          'app_settings',
          where: 'key=?',
          whereArgs: [AppDatabase.transferReversalRepairKey],
        )).single['value'],
        '4',
      );
    });

    test('una base v6 sin el defecto migra a v7 sin cambiar filas ni registrar nada', () async {
      final seed = await baseV6(conDefecto: false);
      expect(seed.reescritas, 0);

      final legacy = await databaseFactoryFfi.openDatabase(seed.path);
      expect(
        (await legacy.rawQuery('PRAGMA user_version')).first.values.first,
        6,
      );
      expect(await reversionesDescuadradas(legacy), isEmpty);
      final antes = await movimientos(legacy);
      final ajustesAntes = await legacy.query('app_settings', orderBy: 'key');
      await legacy.close();

      final migrated = AppDatabase(
        factory: databaseFactoryFfi,
        path: seed.path,
      );
      addTearDown(migrated.close);
      final db = await migrated.database;

      expect(
        (await db.rawQuery('PRAGMA user_version')).first.values.first,
        AppDatabase.schemaVersion,
      );
      expect(await movimientos(db), antes);
      expect(await db.query('app_settings', orderBy: 'key'), ajustesAntes);
      expect(
        await db.query(
          'app_settings',
          where: 'key=?',
          whereArgs: [AppDatabase.transferReversalRepairKey],
        ),
        isEmpty,
      );
    });
  });
}
