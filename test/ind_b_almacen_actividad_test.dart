// Modo individual, sesión B (láminas I-04, I-05, I-30, I-31, I-32, I-33):
// Almacén, detalle de producto, Actividad y Proveedores en la app real sobre
// una base sintética que cumple de verdad el modo individual
// (test/support/ind_b_individual_seed.dart), y las mismas pantallas en el
// modo con varias personas para comprobar que no cambian.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/domain/money.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/operation_mode_controller.dart';
import 'package:agroquimicos/presentation/screens/ind_b_suppliers_screen.dart';
import 'package:agroquimicos/presentation/screens/inventory_alerts_screen.dart';
import 'package:agroquimicos/presentation/screens/operations_screen.dart';
import 'package:agroquimicos/presentation/screens/purchase_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_app_access.dart';
import 'support/f04_mode_fixtures.dart';
import 'support/f04_mode_ui_harness.dart';
import 'support/ind_b_individual_seed.dart';

void main() {
  sqfliteFfiInit();

  void tallView(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<({ProviderContainer c, IndBSeed seed, Household h})> individual(
    WidgetTester tester,
    String name,
  ) async {
    tallView(tester);
    final s = await activatedHousehold(tester, name);
    final seed = await tester.runAsync(() => seedIndividualB(s.household));
    final c = await pumpModeApp(tester, s.database);
    expect(c.read(operationModeProvider), OperationMode.personal);
    return (c: c, seed: seed!, h: s.household);
  }

  Finder keyText(String key, String text) => find.descendant(
    of: find.byKey(Key(key)),
    matching: find.textContaining(text),
    matchRoot: true,
  );

  group('Almacén (I-30, I-32, I-33)', () {
    testWidgets('individual: buscador, filtros, píldora de avisos y sólo '
        'productos con movimiento; sin «Poco por responsable»', (tester) async {
      final w = await individual(tester, 'indb-almacen');
      w.c.read(routerProvider).go('/inventario');
      await waitFor(tester, find.byKey(const Key('inventory-alerts-pill')));
      await settle(tester);

      expect(find.byKey(const Key('inventory-search')), findsOneWidget);
      expect(find.byKey(const Key('inventory-search-toggle')), findsNothing);
      // Las tres cifras del modo con varias personas no se muestran.
      expect(find.byKey(const Key('inventory-tile-expired')), findsNothing);
      // 1 lote por vencer (fungicida en 10 días).
      expect(keyText('inventory-alerts-pill', '1 aviso'), findsOneWidget);
      for (final p in [
        indBLongName,
        'Fungicida',
        'Insecticida',
        'Fertilizante foliar',
      ]) {
        expect(find.text(p), findsOneWidget, reason: p);
      }
      // «Glifosato» del catálogo nunca entró al almacén.
      expect(find.text('Glifosato'), findsNothing);
      expect(find.text('Poco por responsable'), findsNothing);
      // Unidades distintas, cada una con la suya: 14 + 4 = 18 L de
      // fungicida, 25 kg de fertilizante; valoración conservada.
      expect(
        find.byKey(Key('inventory-product-${w.seed.fertilizer}')),
        findsOneWidget,
      );
      expect(find.textContaining('Valor '), findsWidgets);
      expect(
        find.textContaining('Previsto en planes 6 L · quedarían 8 L'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('inventory-filter-withPlans')));
      await settle(tester);
      expect(find.text('Fungicida'), findsOneWidget);
      expect(find.text('Insecticida'), findsNothing);
      expect(find.text(indBLongName), findsNothing);

      await tester.tap(find.byKey(const Key('inventory-filter-expiring')));
      await settle(tester);
      expect(find.text('Fungicida'), findsOneWidget);
      expect(find.text('Fertilizante foliar'), findsNothing);

      await tester.tap(find.byKey(const Key('inventory-filter-all')));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('inventory-search')), 'fert');
      await settle(tester);
      expect(find.text('Fertilizante foliar'), findsOneWidget);
      expect(find.text('Fungicida'), findsNothing);

      // La píldora abre los avisos.
      await tester.tap(find.byKey(const Key('inventory-alerts-pill')));
      await waitFor(tester, find.byType(InventoryAlertsScreen));
      expect(find.byType(InventoryAlertsScreen), findsOneWidget);
    });

    testWidgets('individual sin compras: estado vacío sin cifras en cero y '
        '«Registrar una compra» abre el formulario', (tester) async {
      tallView(tester);
      final s = await activatedHousehold(tester, 'indb-vacio');
      await tester.runAsync(
        () =>
            OperationModeStore(s.database)
                .apply(OperationMode.personal, confirmed: true),
      );
      final c = await pumpModeApp(tester, s.database);
      c.read(routerProvider).go('/inventario');
      await waitFor(tester, find.byKey(const Key('inventory-empty')));
      expect(
        find.text('Su almacén todavía no tiene productos'),
        findsOneWidget,
      );
      expect(find.text('Glifosato'), findsNothing);
      expect(find.textContaining('0 L'), findsNothing);
      expect(find.byKey(const Key('inventory-search')), findsNothing);
      final button = find.byKey(const Key('inventory-empty-purchase'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await waitFor(tester, find.byType(PurchaseFormScreen));
      expect(find.byType(PurchaseFormScreen), findsOneWidget);
    });

    testWidgets('varias personas: Almacén igual que antes (cifras de avisos, '
        'buscador plegado, sin filtros ni píldora)', (tester) async {
      tallView(tester);
      final s = await activatedHousehold(tester, 'indb-almacen-shared');
      await tester.runAsync(() => s.household.buy(s.household.titular, 5000));
      final c = await pumpModeApp(tester, s.database);
      expect(c.read(operationModeProvider), OperationMode.shared);
      c.read(routerProvider).go('/inventario');
      await waitFor(tester, find.byKey(const Key('inventory-tile-expired')));
      expect(find.byKey(const Key('inventory-search-toggle')), findsOneWidget);
      expect(find.byKey(const Key('inventory-search')), findsNothing);
      expect(find.byKey(const Key('inventory-alerts-pill')), findsNothing);
      expect(find.byKey(const Key('inventory-filter-all')), findsNothing);
      expect(find.byKey(const Key('inventory-empty')), findsNothing);
      // El catálogo completo, como antes.
      expect(find.text('Glifosato'), findsOneWidget);
    });
  });

  group('Detalle de producto (I-31)', () {
    testWidgets('individual: «Tiene ahora», sin «Quién lo tiene», previsto '
        'en planes como proyección y sin repetir al titular', (tester) async {
      final w = await individual(tester, 'indb-detalle');
      w.c.read(routerProvider).push('/inventario/${w.seed.fungicide}');
      await waitFor(tester, find.byKey(const Key('inventory-movements')));
      await settle(tester);

      expect(find.text('Tiene ahora'), findsOneWidget);
      expect(find.text('Hay ahora'), findsNothing);
      expect(find.byKey(const Key('inventory-distribution')), findsNothing);
      expect(find.text('Quién lo tiene'), findsNothing);
      expect(
        keyText('inventory-plans-projection', 'quedarán 8 L'),
        findsOneWidget,
      );
      expect(
        keyText('inventory-plans-projection', 'Un plan no descuenta'),
        findsOneWidget,
      );
      expect(find.text('Compra · Agroinsumos'), findsNWidgets(2));
      expect(find.textContaining('Rosa Vargas'), findsNothing);

      // Lotes: sin el nombre del titular; la fecha de compra encabeza.
      await tester.ensureVisible(find.byKey(const Key('inventory-lots')));
      await tester.tap(find.byKey(const Key('inventory-lots')));
      await settle(tester);
      expect(find.byKey(const Key('inventory-lot-0')), findsOneWidget);
      expect(find.textContaining('Rosa Vargas'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('inventory-lot-0')),
          matching: find.textContaining('Comprado el'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('varias personas: «Hay ahora», «Quién lo tiene» y la persona '
        'en cada movimiento, como antes', (tester) async {
      tallView(tester);
      final s = await activatedHousehold(tester, 'indb-detalle-shared');
      await tester.runAsync(() => s.household.buy(s.household.titular, 5000));
      final c = await pumpModeApp(tester, s.database);
      c.read(routerProvider).push('/inventario/${s.household.product}');
      await waitFor(tester, find.byKey(const Key('inventory-movements')));
      expect(find.text('Hay ahora'), findsOneWidget);
      expect(find.byKey(const Key('inventory-distribution')), findsOneWidget);
      final tile = tester.widget<ListTile>(
        find.descendant(
          of: find.byKey(const Key('inventory-movements')),
          matching: find.byType(ListTile),
        ),
      );
      expect((tile.title! as Text).data, 'Compra');
      expect((tile.subtitle! as Text).data, contains('Titular · Proveedor'));
    });
  });

  group('Actividad (I-04)', () {
    testWidgets('individual: franja «Proveedores» con la deuda de todas las '
        'campañas y filas sin el nombre del titular', (tester) async {
      final w = await individual(tester, 'indb-actividad');
      w.c.read(routerProvider).go('/operaciones');
      await waitFor(tester, find.byKey(const Key('activity-suppliers')));
      await settle(tester);
      // HD-3: con el título de la pantalla que abre.
      expect(
        find.descendant(
          of: find.byKey(const Key('activity-suppliers')),
          matching: find.text('Proveedores'),
        ),
        findsOneWidget,
      );
      // 1.260,00 + 625,00 + 300,00.
      expect(
        keyText(
          'activity-suppliers',
          'Debe ${formatBob(218500).trim()} · todas las campañas',
        ),
        findsOneWidget,
      );
      expect(find.text('Chaco Norte'), findsOneWidget);
      expect(find.textContaining('Rosa Vargas'), findsNothing);
      expect(find.text('Plan · Chaco Norte'), findsOneWidget);
      expect(find.byKey(const Key('activity-filter-transfers')), findsNothing);
    });

    testWidgets('varias personas: sin la franja «Proveedores» y con la persona '
        'en cada aplicación, como antes', (tester) async {
      tallView(tester);
      final s = await activatedHousehold(tester, 'indb-actividad-shared');
      final h = s.household;
      await tester.runAsync(() async {
        await h.buy(h.titular, 5000);
        await h.apply(h.titular, h.titularFarm, 1000);
      });
      final c = await pumpModeApp(tester, s.database);
      c.read(routerProvider).go('/operaciones');
      await waitFor(tester, find.byKey(const Key('activity-filter-transfers')));
      await settle(tester);
      expect(find.byKey(const Key('activity-suppliers')), findsNothing);
      expect(find.text('Chaco titular · Titular'), findsOneWidget);
    });

    testWidgets('la franja «Proveedores» abre la pantalla «Proveedores» en '
        '$indProvidersPath', (tester) async {
      tallView(tester);
      final s = await activatedHousehold(tester, 'indb-actividad-nav');
      await tester.runAsync(() => seedIndividualB(s.household));
      final router = GoRouter(
        initialLocation: '/operaciones',
        routes: [
          GoRoute(
            path: '/operaciones',
            builder: (_, _) => const Scaffold(body: OperationsScreen()),
          ),
          GoRoute(
            path: indProvidersPath,
            builder: (_, _) => const Scaffold(body: SuppliersBalanceScreen()),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(AgroRepository(s.database)),
            activatedInstallationForTests(),
            personalModeProvider.overrideWithValue(true),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await waitFor(tester, find.byKey(const Key('activity-suppliers')));
      await tester.tap(find.byKey(const Key('activity-suppliers')));
      await waitFor(tester, find.byKey(const Key('suppliers-debt')));
      await settle(tester);
      // HD-3: la franja se titula como la pantalla que abre.
      expect(
        find.descendant(
          of: find.byType(SuppliersBalanceScreen),
          matching: find.text('Proveedores'),
        ),
        findsOneWidget,
      );
      expect(
        find.text('Proveedores y saldos', skipOffstage: false),
        findsNothing,
      );
    });
  });

  group('Proveedores (I-05)', () {
    Future<({AgroRepository repo, IndBSeed seed})> mountSuppliers(
      WidgetTester tester,
      String name, {
      bool personal = true,
    }) async {
      tallView(tester);
      final s = await activatedHousehold(tester, name);
      final seed = await tester.runAsync(() => seedIndividualB(s.household));
      final repo = AgroRepository(s.database);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(repo),
            activatedInstallationForTests(),
            personalModeProvider.overrideWithValue(personal),
          ],
          child: const MaterialApp(
            home: Scaffold(body: SuppliersBalanceScreen()),
          ),
        ),
      );
      await waitFor(tester, find.byKey(const Key('suppliers-debt')));
      return (repo: repo, seed: seed!);
    }

    testWidgets('deuda total y por proveedor, compras con saldo y pagadas', (
      tester,
    ) async {
      final m = await mountSuppliers(tester, 'indb-proveedores');
      expect(
        find.bySemanticsLabel(
          'Debe a proveedores, todas las campañas: ${formatBob(218500).trim()}',
        ),
        findsOneWidget,
      );
      expect(
        keyText('suppliers-debt', '3 compras con saldo · 2 proveedores'),
        findsOneWidget,
      );
      expect(find.text('Agroinsumos'), findsOneWidget);
      expect(find.text('Debe ${formatBob(188500).trim()}'), findsOneWidget);
      expect(find.text('El Sembrador'), findsOneWidget);
      expect(find.text('Debe ${formatBob(62500).trim()}'), findsOneWidget);
      expect(find.text('Debe ${formatBob(126000).trim()}'), findsOneWidget);
      expect(find.textContaining('pagó 600,00'), findsOneWidget);
      expect(find.text('Compra de ${formatBob(84000).trim()}'), findsOneWidget);
      expect(find.text('Pagada'), findsOneWidget);
      expect(
        find.byKey(Key('suppliers-pay-${m.seed.paidPurchase}')),
        findsNothing,
      );
      expect(keyText('suppliers-footer', 'Chacos › Costos'), findsOneWidget);
    });

    testWidgets('«Pagar» registra el pago del titular al proveedor y baja la '
        'deuda; no crea cobros a personas', (tester) async {
      final m = await mountSuppliers(tester, 'indb-proveedores-pago');
      final db = await tester.runAsync(() => m.repo.appDatabase.database);
      final accountsBefore = await tester.runAsync(
        () => db!.rawQuery('SELECT COUNT(*) n FROM account_transactions'),
      );
      final pay = find.byKey(Key('suppliers-pay-${m.seed.unpaidPurchase}'));
      await tester.ensureVisible(pay);
      await tester.tap(pay);
      await settle(tester);
      expect(find.byKey(const Key('payment-personal-payer')), findsOneWidget);
      expect(find.text('Paga el titular: Rosa Vargas'), findsOneWidget);
      await tester.tap(find.text('Registrar'));
      await settle(tester);
      final payments = await tester.runAsync(
        () => db!.rawQuery(
          'SELECT payer_person_id, amount_bob_minor FROM provider_payments '
          'WHERE purchase_id=? AND reversed_at IS NULL',
          [m.seed.unpaidPurchase],
        ),
      );
      expect(payments, [
        {'payer_person_id': m.seed.titular, 'amount_bob_minor': 62500},
      ]);
      final accountsAfter = await tester.runAsync(
        () => db!.rawQuery('SELECT COUNT(*) n FROM account_transactions'),
      );
      expect(accountsAfter, accountsBefore);
      // La pantalla vuelve a leer las compras y avisa: la deuda baja y la
      // compra pagada pasa a «Pagada».
      expect(find.text('Pago al proveedor registrado.'), findsOneWidget);
      await waitFor(
        tester,
        find.bySemanticsLabel(
          'Debe a proveedores, todas las campañas: ${formatBob(156000).trim()}',
        ),
      );
      expect(
        find.bySemanticsLabel(
          'Debe a proveedores, todas las campañas: ${formatBob(156000).trim()}',
        ),
        findsOneWidget,
      );
      expect(find.text('Pagada'), findsNWidgets(2));
      expect(
        find.byKey(Key('suppliers-pay-${m.seed.unpaidPurchase}')),
        findsNothing,
      );
    });

    testWidgets('varias personas: la misma pantalla sin mencionar Chacos', (
      tester,
    ) async {
      await mountSuppliers(tester, 'indb-proveedores-shared', personal: false);
      expect(keyText('suppliers-footer', 'Chacos'), findsNothing);
      expect(
        keyText('suppliers-footer', 'no es un cobro a una persona'),
        findsOneWidget,
      );
    });
  });
}
