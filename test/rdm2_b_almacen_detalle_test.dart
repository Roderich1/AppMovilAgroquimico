// Ronda 2 del rediseño, sesión B (encargo del autor del 2026-11-12):
// detalle de producto de Almacén, avisos y presentación de lotes.
//
// Regresión: el detalle muestra las MISMAS cifras que antes, comparadas con
// lo que devuelven las lecturas actuales del repositorio
// (`inventoryProductHeader`, `inventoryProductDistribution`,
// `inventoryProductLots`, `productMovements`) y con los valores que mostraba
// el código anterior sobre los mismos datos sintéticos (capturas «antes» de
// docs/evidence/rediseno-movil/2026-11-12/ronda2/B/antes/b1_detalle_arriba*).
// Además: el aviso de vencimiento dice la cantidad afectada; ningún «Lote #»
// ni «sin número de lote» en las vistas principales; el número del
// fabricante aparece cuando existe. Datos sintéticos
// (test/support_rdm2/b_almacen_seed.dart).
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/domain/inventory_alerts.dart';
import 'package:agroquimicos/domain/money.dart';
import 'package:agroquimicos/presentation/widgets/rdm2_b_lotes.dart';
import 'package:agroquimicos/presentation/widgets/rdm_b_ui.dart'
    show splitQuantity;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';
import 'support/f04_mode_ui_harness.dart';
import 'support_rdm2/b_almacen_seed.dart';

typedef Row = Map<String, Object?>;

void main() {
  sqfliteFfiInit();

  group('funciones de presentación', () {
    test('expiryPortions agrupa por estado y fecha y suma cantidades', () {
      final portions = expiryPortions(
        lots: const [
          (availableBase: 1000, expiryDay: '2026-12-11'),
          (availableBase: 500, expiryDay: '2026-12-11'),
          (availableBase: 500, expiryDay: '2026-11-01'),
          (availableBase: 2000, expiryDay: null),
          (availableBase: 1000, expiryDay: '2027-06-01'),
          (availableBase: 0, expiryDay: '2026-11-12'),
        ],
        today: '2026-11-12',
        leadDays: 30,
      );
      expect(
        [for (final p in portions) (p.status, p.day, p.quantityBase, p.warns)],
        [
          (ExpiryStatus.expired, '2026-11-01', 500, true),
          (ExpiryStatus.near, '2026-12-11', 1500, true),
          (ExpiryStatus.later, '2027-06-01', 1000, false),
          (ExpiryStatus.unknown, null, 2000, false),
        ],
      );
      // La suma no cambia: es la existencia de los lotes con cantidad.
      expect(portions.fold(0, (s, p) => s + p.quantityBase), 5000);
    });

    test('expiryPortionText dice la cantidad y concuerda en número', () {
      ExpiryPortion p(ExpiryStatus s, String? d, int q) =>
          ExpiryPortion(status: s, day: d, quantityBase: q);
      expect(
        expiryPortionText(p(ExpiryStatus.near, '2026-12-11', 1000), 'L'),
        '1 L vence el 11/12/2026',
      );
      expect(
        expiryPortionText(p(ExpiryStatus.near, '2026-12-11', 1500), 'L'),
        '1,5 L vencen el 11/12/2026',
      );
      expect(
        expiryPortionText(p(ExpiryStatus.expired, '2026-11-01', 500), 'KG'),
        '0,5 KG vencieron el 01/11/2026',
      );
      expect(
        expiryPortionText(p(ExpiryStatus.expired, '2026-11-01', 1000), 'L'),
        '1 L venció el 01/11/2026',
      );
      expect(
        expiryPortionText(p(ExpiryStatus.today, '2026-11-12', 2000), 'L'),
        '2 L vencen hoy',
      );
      expect(
        expiryPortionText(p(ExpiryStatus.unknown, null, 3000), 'L'),
        '3 L sin fecha de vencimiento',
      );
    });

    test('lotReferences sólo distingue la misma persona el mismo día', () {
      expect(
        lotReferences(const [
          (person: 'Ana', acquiredDay: '2026-10-01'),
          (person: 'Ana', acquiredDay: '2026-10-02'),
          (person: 'Beto', acquiredDay: '2026-10-02'),
          (person: 'Ana', acquiredDay: '2026-10-02'),
        ]),
        [null, 'entrada 1 de 2', null, 'entrada 2 de 2'],
      );
    });

    test('etiquetas de la lista con la cantidad que vence', () {
      LotExpiryAlert alert(int base, int? days) => LotExpiryAlert(
        lot: AlertLot(
          lotId: base,
          productId: 1,
          productName: 'P',
          unit: 'L',
          ownerPersonId: 1,
          ownerName: 'Ana',
          remainingBase: base,
          leadDays: 30,
          leadDaysIsDefault: true,
          expiryDay: '2026-12-01',
        ),
        status: ExpiryStatus.near,
        days: days,
      );
      expect(
        nearExpiryBadge([alert(1000, 25), alert(500, 25)], 'L'),
        '1,5 L vencen en 25 días',
      );
      expect(nearExpiryBadge([alert(1000, 1)], 'L'), '1 L vence en 1 día');
      expect(
        nearExpiryBadge([alert(1000, 25), alert(500, 10)], 'L'),
        '1,5 L por vencer, desde 10 días',
      );
      expect(todayExpiryBadge([alert(1000, 0)], 'L'), '1 L vence hoy');
    });
  });

  group('pantallas', () {
    Future<
      ({
        ProviderContainer c,
        AlmacenSeedB seed,
        Household household,
        Row header,
        List<Row> distribution,
        List<Row> lots,
        List<Row> movements,
      })
    >
    open(WidgetTester tester, String name) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final s = await activatedHousehold(tester, name);
      final seed = (await tester.runAsync(() => seedAlmacenB(s.household)))!;
      final repo = s.household.repo;
      final reads = (await tester.runAsync(
        () async => (
          header: await repo.inventoryProductHeader(seed.product),
          distribution: await repo.inventoryProductDistribution(seed.product),
          lots: await repo.inventoryProductLots(seed.product),
          movements: await repo.productMovements(seed.product, limit: 500),
        ),
      ))!;
      final c = await pumpModeApp(tester, s.database);
      return (
        c: c,
        seed: seed,
        household: s.household,
        header: reads.header,
        distribution: reads.distribution,
        lots: reads.lots,
        movements: reads.movements,
      );
    }

    Finder metric(String label, String value) => find.descendant(
      of: find.byKey(Key('metric-$label')),
      matching: find.text(value),
    );

    testWidgets('detalle: mismas cifras que las lecturas actuales y que el '
        'código anterior, en el orden pedido', (tester) async {
      final r = await open(tester, 'rdm2-b-detalle');
      r.c.read(routerProvider).push('/inventario/${r.seed.product}');
      await waitFor(tester, find.byKey(const Key('inventory-lots')));
      await settle(tester);
      final h = r.header;
      final unit = h['unit']! as String;
      final physical = h['physical_base']! as int;
      final committed = h['committed_base']! as int;

      // Valores que mostraba el código anterior con estos datos (capturas
      // «antes»): Físico 5 L, Comprado neto 9 L, Consumido neto 4 L,
      // Previsto en planes 1,5 L, Quedarán 3,5 L, Valor 180,50 Bs.
      expect(formatQuantity(physical, unit), '5 L');
      expect(formatQuantity(h['purchased_base']! as int, unit), '9 L');
      expect(formatQuantity(h['consumed_base']! as int, unit), '4 L');
      expect(formatQuantity(committed, unit), '1,5 L');
      expect(formatQuantity(physical - committed, unit), '3,5 L');
      expect(formatBob(h['value_bob_minor']! as int), formatBob(18050));

      // 1. Cuánto hay ahora (grande) — mismo físico.
      final big = splitQuantity(physical, unit);
      expect(metric('Hay ahora', big.number), findsOneWidget);
      expect(metric('Hay ahora', big.unit), findsOneWidget);
      // 3. Previsto en planes y la proyección.
      expect(
        metric('Previsto en planes', formatQuantity(committed, unit)),
        findsOneWidget,
      );
      expect(
        metric(
          'Quedarían si se aplican los planes',
          formatQuantity(physical - committed, unit),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Es una proyección: los planes no apartan producto y lo que hay '
          'ahora no cambia.',
        ),
        findsOneWidget,
      );
      // 5. Cifras netas y valor, como información secundaria.
      expect(
        metric(
          'Comprado neto',
          formatQuantity(h['purchased_base']! as int, unit),
        ),
        findsOneWidget,
      );
      expect(
        metric(
          'Consumido neto',
          formatQuantity(h['consumed_base']! as int, unit),
        ),
        findsOneWidget,
      );
      expect(
        metric(
          'Valor a costo de compra',
          formatBob(h['value_bob_minor']! as int),
        ),
        findsOneWidget,
      );

      // 2. Quién lo tiene: cada persona con lo que tiene y su consumido neto
      // de su asignación neta (antes: «Asignación neta 3,5 L · consumido
      // neto 1,5 L», 2 L; «Asignación neta 5,5 L · consumido neto 2,5 L»,
      // 3 L).
      final group = find.byKey(const Key('inventory-distribution'));
      final tiles = tester
          .widgetList<ListTile>(
            find.descendant(of: group, matching: find.byType(ListTile)),
          )
          .toList();
      expect(tiles, hasLength(r.distribution.length));
      for (final (i, row) in r.distribution.indexed) {
        expect((tiles[i].title! as Text).data, row['person_name']);
        expect(
          (tiles[i].subtitle! as Text).data,
          'Usó ${formatQuantity(row['consumed_base']! as int, unit)} de '
          '${formatQuantity(row['assigned_base']! as int, unit)}',
        );
        expect(
          (tiles[i].trailing! as Text).data,
          formatQuantity(row['available_base']! as int, unit),
        );
      }
      expect(
        [for (final t in tiles) (t.subtitle! as Text).data],
        ['Usó 1,5 L de 3,5 L', 'Usó 2,5 L de 5,5 L'],
      );
      expect(
        [for (final t in tiles) (t.trailing! as Text).data],
        ['2 L', '3 L'],
      );

      // Vencimiento con la cantidad afectada, no «Por vencer» a secas.
      final today = r.seed.today;
      String day(int offset) =>
          formatDate(DateTime(today.year, today.month, today.day + offset));
      final expiry = find.byKey(const Key('inventory-expiry'));
      expect(
        find.descendant(
          of: expiry,
          matching: find.text('0,5 L vencieron el ${day(-5)}'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: expiry,
          matching: find.text('1,5 L vencen el ${day(25)}'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: expiry,
          matching: find.text('1 L sin fecha de vencimiento'),
        ),
        findsOneWidget,
      );
      expect(find.text('Por vencer'), findsNothing);
      expect(find.text('Lote vencido'), findsNothing);

      // Orden: cantidad → personas → planes → movimientos → más datos.
      double top(String key) => tester.getTopLeft(find.byKey(Key(key))).dy;
      expect(top('metric-Hay ahora'), lessThan(top('inventory-distribution')));
      expect(top('inventory-distribution'), lessThan(top('inventory-plans')));
      expect(top('inventory-plans'), lessThan(top('inventory-movements')));
      expect(top('inventory-movements'), lessThan(top('inventory-lots')));
      expect(top('inventory-lots'), lessThan(top('inventory-totals')));
      expect(
        top('inventory-totals'),
        lessThan(top('inventory-alert-settings')),
      );

      // 4. Movimientos recientes (cinco) y acceso al historial completo.
      final recent = find.descendant(
        of: find.byKey(const Key('inventory-movements')),
        matching: find.byType(ListTile),
      );
      expect(recent, findsNWidgets(5));
      expect(r.movements.length, greaterThan(5));

      // Términos técnicos fuera de la vista principal; sin identificadores
      // internos ni «sin número de lote».
      for (final term in [
        'Físico',
        'Asignación neta',
        'Quedarán',
        'Lote #',
        'sin número de lote',
        'Lotes disponibles y valor físico',
      ]) {
        expect(find.textContaining(term), findsNothing, reason: term);
      }

      // Lotes desplegados: una tarjeta por lote, con la cantidad de la
      // lectura actual; el número del fabricante sólo si existe.
      await tester.ensureVisible(find.byKey(const Key('inventory-lots')));
      await tester.tap(find.byKey(const Key('inventory-lots')));
      await settle(tester);
      for (final (i, lot) in r.lots.indexed) {
        final card = find.byKey(Key('inventory-lot-$i'));
        expect(card, findsOneWidget);
        expect(
          find.descendant(
            of: card,
            matching: find.text(
              formatQuantity(lot['available_base']! as int, unit),
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: card,
            matching: find.text('${lot['owner_name']}'),
          ),
          findsOneWidget,
        );
        final number = lot['lot_number'] as String?;
        expect(
          find.descendant(
            of: card,
            matching: find.textContaining(manufacturerLotLabel),
          ),
          number == null ? findsNothing : findsOneWidget,
        );
        if (number != null) {
          expect(
            find.descendant(
              of: card,
              matching: find.text('$manufacturerLotLabel: $number'),
            ),
            findsOneWidget,
          );
        }
        expect(
          find.descendant(
            of: card,
            matching: find.textContaining(
              'Comprado el ${formatDate(lot['acquired_date'])}',
            ),
          ),
          findsOneWidget,
        );
      }
      expect(find.byKey(Key('inventory-lot-${r.lots.length}')), findsNothing);
      // La suma de los lotes es lo que hay ahora.
      expect(
        r.lots.fold(0, (s, l) => s + (l['available_base']! as int)),
        physical,
      );
      expect(find.text('$manufacturerLotLabel: HSR-2291'), findsNWidgets(2));
      expect(find.text('$manufacturerLotLabel: VJ-07'), findsOneWidget);
      // Dos entradas de Rosa del mismo día: referencia visual, no un lote.
      expect(find.textContaining('entrada 1 de 2'), findsOneWidget);
      expect(find.textContaining('entrada 2 de 2'), findsOneWidget);
      expect(find.textContaining('recibido por pase'), findsOneWidget);
      expect(find.textContaining('Lote #'), findsNothing);
      expect(find.textContaining('sin número de lote'), findsNothing);
      expect(find.textContaining('origen'), findsNothing);

      // Historial completo: todas las filas de la lectura actual.
      await tester.ensureVisible(
        find.byKey(const Key('inventory-movements-all')),
      );
      await tester.tap(find.byKey(const Key('inventory-movements-all')));
      await waitFor(tester, find.byKey(const Key('inventory-history')));
      await settle(tester);
      final history = tester
          .widgetList<ListTile>(
            find.descendant(
              of: find.byKey(const Key('inventory-history')),
              matching: find.byType(ListTile),
            ),
          )
          .toList();
      expect(history, hasLength(r.movements.length));
      for (final (i, row) in r.movements.indexed) {
        final q = row['quantity_signed']! as int;
        expect(
          (history[i].trailing! as Text).data,
          '${q < 0 ? '-' : '+'}${formatQuantity(q.abs(), unit)}',
        );
      }
      expect(find.byKey(const Key('inventory-history-more')), findsNothing);
    });

    testWidgets('sin existencia suficiente para los planes: «Faltarían», '
        'con el mismo cálculo (físico − previsto)', (tester) async {
      final r = await open(tester, 'rdm2-b-faltan');
      final h = r.household;
      await tester.runAsync(
        () => h.repo.addPlan(
          farmId: h.titularFarm,
          campaignId: h.campaign,
          productId: h.product,
          areaM2: 10000,
          doseBasePerHa: 2500,
        ),
      );
      final header = (await tester.runAsync(
        () => h.repo.inventoryProductHeader(h.product),
      ))!;
      final projected =
          (header['physical_base']! as int) -
          (header['committed_base']! as int);
      expect(projected, lessThan(0));
      r.c.read(routerProvider).push('/inventario/${h.product}');
      await waitFor(tester, find.byKey(const Key('inventory-plans')));
      await settle(tester);
      expect(
        metric(
          'Faltarían si se aplican los planes',
          formatQuantity(-projected, 'L'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Quedarían'), findsNothing);
    });

    testWidgets('avisos, lista y detalle de compra: sin «sin número de lote» '
        'ni «sin registrar»; el número del fabricante cuando existe', (
      tester,
    ) async {
      final r = await open(tester, 'rdm2-b-vistas');
      // Lista de Almacén: la etiqueta dice cuánto vence.
      r.c.read(routerProvider).go('/inventario');
      await waitFor(
        tester,
        find.byKey(Key('inventory-product-${r.seed.product}')),
      );
      await settle(tester);
      expect(
        find.descendant(
          of: find.byKey(Key('inventory-product-${r.seed.product}')),
          matching: find.text('1,5 L vencen en 25 días'),
        ),
        findsOneWidget,
      );

      // Avisos de inventario.
      r.c.read(routerProvider).push('/inventario/avisos');
      await waitFor(tester, find.byKey(const Key('alerts-expired')));
      await settle(tester);
      expect(find.textContaining('sin número de lote'), findsNothing);
      expect(find.textContaining('Lote #'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('alerts-expired')),
          matching: find.text('$manufacturerLotLabel: VJ-07'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining(manufacturerLotLabel), findsOneWidget);

      // Detalle de compra con número del fabricante.
      r.c.read(routerProvider).go('/inventario');
      await settle(tester);
      r.c
          .read(routerProvider)
          .push('/compras/detalle/${r.seed.purchaseWithLots}');
      Finder rich(String text) => find.textContaining(text, findRichText: true);
      await waitFor(tester, rich('Vencimiento: '));
      await settle(tester);
      expect(rich('$manufacturerLotLabel: HSR-2291'), findsOneWidget);
      expect(rich('sin registrar'), findsNothing);

      // Detalle de compra sin número: el dato no aparece.
      r.c.read(routerProvider).go('/inventario');
      await settle(tester);
      r.c
          .read(routerProvider)
          .push('/compras/detalle/${r.seed.purchaseWithoutNumber}');
      await waitFor(tester, rich('Vencimiento: sin fecha registrada'));
      await settle(tester);
      expect(rich(manufacturerLotLabel), findsNothing);
      expect(rich('Número de lote'), findsNothing);
      expect(rich('sin registrar'), findsNothing);
      // Sigue pudiendo registrarlo.
      expect(find.text('Corregir vencimiento o lote'), findsOneWidget);
    });
  });
}
