// DS-V Mobile: dataset de volumen de la evaluación F10 (protocolo v1.0, §1.4).
//
// HERRAMIENTA DE EVALUACIÓN. No se compila dentro de la aplicación y no forma
// parte de la suite (`flutter test` sin argumentos sólo recorre `test/`). Se
// ejecuta explícitamente sobre la base EXTRAÍDA de la copia aislada `.f10eval`
// ya activada, con la app detenida:
//
//     F10_DSV_DB=/ruta/absoluta/agroquimicos_v2.db \
//       flutter test tool/f10_eval/seed_dsv_mobile.dart
//
// Escribe por `AgroRepository` (`confirmPurchase`, `confirmApplication`), con las
// mismas reglas de saldo, FIFO, campaña y titular que la app. Es una fixture de
// base, no una publicación por Sync: no crea intenciones y lo comprueba.
//
// Composición exacta (semilla 20261016): 100 productos (`DSV-001` … `DSV-100`),
// 5 proveedores, 1 campaña, 300 compras de 2 líneas y 1 000 aplicaciones de 1
// línea, en orden cronológico entre el 2025-10-16 y el 2026-10-15. `DSV-001`
// concentra los movimientos (objetivo de R3). Al terminar imprime una línea
// `DSV_RESULT {...}` con los conteos e invariantes para la evidencia.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const int seed = 20261016;
const int productCount = 100;
const int supplierCount = 5;
const int purchaseCount = 300;
const int applicationCount = 1000;

/// Un evento del calendario sintético: compra (k) o aplicación (j).
class _Event {
  _Event.purchase(this.at, this.index) : isPurchase = true;
  _Event.application(this.at, this.index) : isPurchase = false;
  final DateTime at;
  final int index;
  final bool isPurchase;
}

void main() {
  sqfliteFfiInit();

  test('siembra DS-V Mobile en la base indicada por F10_DSV_DB', () async {
    final path = Platform.environment['F10_DSV_DB'];
    expect(path, isNotNull, reason: 'Defina F10_DSV_DB');
    expect(p.isAbsolute(path!), isTrue, reason: 'F10_DSV_DB debe ser absoluta');
    expect(File(path).existsSync(), isTrue, reason: 'no existe $path');

    final database = AppDatabase(factory: databaseFactoryFfi, path: path);
    final repo = AgroRepository(database);
    final db = await database.database;
    Future<int> count(String sql, [List<Object?> args = const []]) async =>
        ((await db.rawQuery(sql, args)).first.values.first as int?) ?? 0;

    // Sólo sobre una copia recién activada: nada de negocio previo.
    for (final table in [
      'products',
      'purchases',
      'applications',
      'campaigns',
      'suppliers',
    ]) {
      expect(
        await count('SELECT COUNT(*) FROM $table'),
        0,
        reason: '$table ya tiene filas: la siembra sólo va sobre una copia nueva',
      );
    }
    final outboxBefore = await count('SELECT COUNT(*) FROM sync_outbox');
    final outboxMaxBefore = await count(
      'SELECT COALESCE(MAX(rowid), 0) FROM sync_outbox',
    );

    final context = await repo.operatingContext();
    final owner = context.ownerPersonId;
    expect(owner, isNotNull, reason: 'la copia no tiene titular vinculado');

    final rng = Random(seed);
    final start = DateTime.utc(2025, 10, 16);

    final campaignId = await repo.addCampaign(
      name: 'Campaña DSV 2025-2026',
      start: DateTime.utc(2025, 10, 1),
    );
    final farmRows = await db.query(
      'farms',
      where: 'owner_person_id = ?',
      whereArgs: [owner],
      orderBy: 'id',
      limit: 1,
    );
    final farmId = farmRows.isNotEmpty
        ? farmRows.single['id']! as int
        : await repo.addFarm(
            ownerId: owner!,
            name: 'Chaco DSV Norte',
            areaM2: 50000,
          );

    final supplierIds = <int>[
      for (var s = 1; s <= supplierCount; s++)
        await repo.addSupplier(name: 'Proveedor DSV $s'),
    ];
    final productIds = <int>[];
    for (var i = 1; i <= productCount; i++) {
      final code = 'DSV-${i.toString().padLeft(3, '0')}';
      productIds.add(
        await repo.addProduct(
          name: '$code Producto sintético',
          activeIngredient: 'Sintético $i',
          unit: i <= 70 ? 'L' : 'KG',
        ),
      );
    }
    final target = productIds.first; // DSV-001

    // Calendario: compras desde el día 0; aplicaciones desde el día 10, para
    // que siempre haya saldo de algo. Orden cronológico estricto.
    final events = <_Event>[
      for (var k = 0; k < purchaseCount; k++)
        _Event.purchase(
          start.add(Duration(minutes: (k * 365 * 24 * 60 ~/ purchaseCount) + 9 * 60)),
          k,
        ),
      for (var j = 0; j < applicationCount; j++)
        _Event.application(
          start.add(
            Duration(
              minutes: (10 * 24 * 60) +
                  (j * 355 * 24 * 60 ~/ applicationCount) +
                  15 * 60,
            ),
          ),
          j,
        ),
    ]..sort((a, b) {
        final byTime = a.at.compareTo(b.at);
        if (byTime != 0) return byTime;
        return a.isPurchase == b.isPurchase ? a.index - b.index : (a.isPurchase ? -1 : 1);
      });

    final stock = <int, int>{for (final id in productIds) id: 0};
    final movements = <int, int>{for (final id in productIds) id: 0};
    var purchases = 0;
    var applications = 0;

    for (final event in events) {
      if (event.isPurchase) {
        final first = event.index % 5 == 0
            ? target
            : productIds[1 + rng.nextInt(productCount - 1)];
        int second;
        do {
          second = productIds[1 + rng.nextInt(productCount - 1)];
        } while (second == first);
        final items = <PurchaseItemDraft>[];
        for (final productId in [first, second]) {
          final quantity = (20 + rng.nextInt(41)) * 1000; // 20–60 L o kg
          items.add(
            PurchaseItemDraft(
              productId: productId,
              quantityBase: quantity,
              currency: CurrencyCode.bob,
              originalUnitPriceMinor: 2000 + rng.nextInt(7001),
              allocations: [
                AllocationDraft(personId: owner!, quantityBase: quantity),
              ],
            ),
          );
          stock[productId] = stock[productId]! + quantity;
          movements[productId] = movements[productId]! + 1;
        }
        await repo.confirmPurchase(
          PurchaseDraft(
            supplierId: supplierIds[event.index % supplierCount],
            campaignId: campaignId,
            purchaseDate: event.at,
            invoiceNumber: 'DSV-F-${(event.index + 1).toString().padLeft(4, '0')}',
            items: items,
          ),
        );
        purchases++;
      } else {
        final quantity = (5 + rng.nextInt(26)) * 100; // 0,5–3 L o kg
        int? productId;
        if (event.index % 5 == 0 && stock[target]! >= quantity) {
          productId = target;
        } else {
          final candidates = [
            for (final id in productIds.skip(1))
              if (stock[id]! >= quantity) id,
          ];
          expect(candidates, isNotEmpty, reason: 'sin saldo en ${event.at}');
          productId = candidates[rng.nextInt(candidates.length)];
        }
        await repo.confirmApplication(
          ApplicationDraft(
            personId: owner!,
            farmId: farmId,
            campaignId: campaignId,
            appliedAt: event.at,
            lines: [
              ApplicationLineDraft(productId: productId, quantityBase: quantity),
            ],
          ),
        );
        stock[productId] = stock[productId]! - quantity;
        movements[productId] = movements[productId]! + 1;
        applications++;
      }
    }

    // Invariantes.
    final result = <String, Object?>{
      'seed': seed,
      'products': await count('SELECT COUNT(*) FROM products'),
      'suppliers': await count('SELECT COUNT(*) FROM suppliers'),
      'campaigns': await count('SELECT COUNT(*) FROM campaigns'),
      'purchases': await count('SELECT COUNT(*) FROM purchases'),
      'purchase_items': await count('SELECT COUNT(*) FROM purchase_items'),
      'applications': await count('SELECT COUNT(*) FROM applications'),
      'application_items': await count('SELECT COUNT(*) FROM application_items'),
      'inventory_movements': await count('SELECT COUNT(*) FROM inventory_movements'),
      'negative_stock_products': await count(
        'SELECT COUNT(*) FROM (SELECT product_id FROM inventory_movements '
        'GROUP BY product_id HAVING SUM(quantity_signed) < 0)',
      ),
      'sync_outbox_before': outboxBefore,
      'sync_outbox_after': await count('SELECT COUNT(*) FROM sync_outbox'),
      'sync_outbox_max_rowid_after': await count(
        'SELECT COALESCE(MAX(rowid), 0) FROM sync_outbox',
      ),
      'target_product_movements': await count(
        'SELECT COUNT(*) FROM inventory_movements WHERE product_id = ?',
        [target],
      ),
      'max_other_product_movements': await count(
        'SELECT COALESCE(MAX(c), 0) FROM (SELECT COUNT(*) c FROM inventory_movements '
        'WHERE product_id <> ? GROUP BY product_id)',
        [target],
      ),
    };
    final integrity = (await db.rawQuery('PRAGMA integrity_check')).first.values.first;
    result['integrity_check'] = integrity;

    expect(purchases, purchaseCount);
    expect(applications, applicationCount);
    expect(result['products'], productCount);
    expect(result['purchases'], purchaseCount);
    expect(result['purchase_items'], purchaseCount * 2);
    expect(result['applications'], applicationCount);
    expect(result['application_items'], applicationCount);
    expect(result['negative_stock_products'], 0);
    expect(result['sync_outbox_after'], outboxBefore);
    expect(result['sync_outbox_max_rowid_after'], outboxMaxBefore);
    expect(integrity, 'ok');
    expect(
      (result['target_product_movements']! as int) >
          (result['max_other_product_movements']! as int),
      isTrue,
    );
    // Una aplicación que consume varios lotes FIFO deja un movimiento por lote:
    // las líneas de DSV-001 (compras + aplicaciones) se registran aparte.
    result['target_product_lines'] = movements[target];

    await database.close();
    result['db_bytes'] = File(path).lengthSync();
    result['wal_left'] = File('$path-wal').existsSync();
    expect(result['wal_left'], isFalse);
    // ignore: avoid_print
    print('DSV_RESULT ${jsonEncode(result)}');
  }, timeout: const Timeout(Duration(minutes: 20)));
}
