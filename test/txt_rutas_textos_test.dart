// HD-3 (sesión de manuales, 2026-11-14): cinco textos nombraban pantallas
// que ya no existen. Se comprueba el texto nuevo y que el recorrido que nombra
// existe y se recorre de verdad, en los dos modos cuando aplica:
//   (1) «Inicio › Ajustes y datos › Campañas» (compra sin campaña activa).
//   (2) «Actividad › Compras › Lista de compras», «Registrar pago al
//       proveedor» (compra sin pago, modo con varias personas).
//   (3) «Sindicato › Ver estado de los envíos» abre «Envíos» (restauración).
//   (4) La franja «Proveedores» de Actividad: ver ind_b_almacen_actividad_test.
//   (5) «Inicio › Cuenta en línea», «Verificar acceso en línea» (estimación
//       sin acceso verificado; el texto, en f12_est_07_estimation_ui_test).
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/operation_mode_controller.dart';
import 'package:agroquimicos/presentation/screens/campaigns_screen.dart';
import 'package:agroquimicos/presentation/screens/more_screen.dart';
import 'package:agroquimicos/presentation/screens/purchase_detail_screen.dart';
import 'package:agroquimicos/presentation/screens/purchases_screen.dart';
import 'package:agroquimicos/presentation/screens/sync_status_screen.dart';
import 'package:agroquimicos/presentation/widgets/adaptive_entity_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_ui_harness.dart';
import 'support/purchase_form_driver.dart';

typedef _Row = Map<String, Object?>;

void main() {
  sqfliteFfiInit();

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await settle(tester);
  }

  for (final personal in [false, true]) {
    final mode = personal ? 'individual' : 'varias personas';

    Future<ProviderContainer> app(WidgetTester tester, String name) async {
      await tester.binding.setSurfaceSize(const Size(800, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final s = await activatedHousehold(tester, name);
      if (personal) {
        await tester.runAsync(
          () =>
              OperationModeStore(s.database)
                  .apply(OperationMode.personal, confirmed: true),
        );
      }
      final c = await pumpModeApp(tester, s.database);
      expect(
        c.read(operationModeProvider),
        personal ? OperationMode.personal : OperationMode.shared,
      );
      return c;
    }

    testWidgets('(1) $mode: Inicio › Ajustes y datos › Campañas existe', (
      tester,
    ) async {
      final c = await app(tester, 'txt-campanas-$personal');
      c.read(routerProvider).go('/');
      await settle(tester);
      await tap(tester, find.byKey(const Key('home-settings')));
      expect(find.byType(MoreScreen), findsOneWidget);
      expect(find.text('Ajustes y datos'), findsOneWidget);
      await tap(tester, find.byKey(const Key('more-campaigns')));
      expect(find.byType(CampaignsScreen), findsOneWidget);
    });

    testWidgets('(3) $mode: Sindicato › Ver estado de los envíos abre '
        '«Envíos»', (tester) async {
      final c = await app(tester, 'txt-envios-$personal');
      c.read(routerProvider).go('/sindicato');
      await settle(tester);
      expect(find.text('Ver estado de los envíos'), findsOneWidget);
      await tap(tester, find.byKey(const Key('union-status')));
      expect(find.byType(SyncStatusScreen), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SyncStatusScreen),
          matching: find.text('Envíos'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('(5) $mode: Inicio › Cuenta en línea ofrece «Verificar '
        'acceso en línea»', (tester) async {
      final c = await app(tester, 'txt-acceso-$personal');
      c.read(routerProvider).go('/');
      await settle(tester);
      final routine = find.byKey(const Key('home-session-routine'));
      await tester.ensureVisible(routine);
      await tester.pump();
      expect(find.text('Cuenta en línea'), findsOneWidget);
      final verify = find.descendant(
        of: routine,
        matching: find.byKey(const Key('verify-online-access')),
      );
      expect(verify, findsOneWidget);
      expect(
        find.descendant(
          of: verify,
          matching: find.text('Verificar acceso en línea'),
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets('(1) compra sin campaña activa: el aviso nombra «Inicio › '
      'Ajustes y datos › Campañas»', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, 'txt-compra-sin-campana');
    await tester.runAsync(
      () => s.household.repo.closeCampaign(s.household.campaign),
    );
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).push('/compras/nueva');
    await waitFor(tester, find.byKey(const Key('purchase-add-line')));
    await settle(tester);
    await openPurchaseLine(tester);
    final picker = find.byWidgetPredicate(
      (w) => w is AdaptiveEntityPicker<_Row> && w.label == 'Producto',
    );
    final w = tester.widget<AdaptiveEntityPicker<_Row>>(picker.last);
    w.onChanged(w.items.firstWhere((i) => w.labelOf(i) == 'Glifosato'));
    await settle(tester);
    Finder field(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
    );
    await tester.enterText(field('Cantidad comprada'), '2');
    await tester.enterText(field('Precio por L'), '50');
    await settle(tester);
    Future<void> tapKey(String key) async {
      await preparePurchaseKey(tester, key);
      await tap(tester, find.byKey(Key(key)).last);
    }

    await tapKey('purchase-alloc-single-0');
    final person = find.byWidgetPredicate(
      (w) => w is AdaptiveEntityPicker<_Row> && w.label == 'Persona',
    );
    final p = tester.widget<AdaptiveEntityPicker<_Row>>(person.last);
    p.onChanged(p.items.firstWhere((i) => p.labelOf(i) == 'Hermana'));
    await settle(tester);
    await closePurchaseLine(tester);
    await tapKey('purchase-continue');
    await tapKey('purchase-paid-no');
    await tapKey('purchase-confirm');
    expect(
      find.text(
        'No hay una campaña activa. Actívela en Inicio › Ajustes y datos › '
        'Campañas.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Administrar datos'), findsNothing);
  });

  testWidgets('(2) varias personas: Actividad › Compras › Lista de compras › '
      'la compra ofrece «Registrar pago al proveedor»', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, 'txt-compra-sin-pago');
    final purchase = await tester.runAsync(
      () => s.household.buy(s.household.titular, 2000),
    );
    final c = await pumpModeApp(tester, s.database);
    expect(c.read(operationModeProvider), OperationMode.shared);
    c.read(routerProvider).go('/operaciones');
    await settle(tester);
    await tap(tester, find.byKey(const Key('activity-filter-purchases')));
    expect(find.text('Lista de compras'), findsOneWidget);
    await tap(tester, find.byKey(const Key('activity-open-purchases')));
    expect(find.byType(PurchasesScreen), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PurchasesScreen),
        matching: find.text('Compras'),
      ),
      findsWidgets,
    );
    await tap(tester, find.byKey(Key('purchase-card-$purchase')));
    expect(find.byType(PurchaseDetailScreen), findsOneWidget);
    expect(find.text('Registrar pago al proveedor'), findsOneWidget);
  });
}
