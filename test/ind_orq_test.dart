// Modo individual — partes del orquestador (2026-11-13): barra por modo,
// Inicio (I-01, I-02), hoja Registrar (I-03), Ajustes (I-50) y Modo de uso
// (I-51, I-52). App real sobre base en archivo y sin red.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/money.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/presentation/screens/operation_mode_screen.dart';
import 'package:agroquimicos/presentation/widgets/rdm_b_ui.dart' show splitBob;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';
import 'support/f04_mode_ui_harness.dart';

void main() {
  sqfliteFfiInit();

  Finder navLabel(String label) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );

  Future<void> toPersonal(WidgetTester tester, AppDatabase database) async {
    await tester.runAsync(
      () =>
          OperationModeStore(database)
              .apply(OperationMode.personal, confirmed: true),
    );
  }

  String textOf(WidgetTester tester, Key key) {
    final widget = tester.widget(find.byKey(key));
    if (widget is Text) return widget.data ?? '';
    return tester
        .widgetList<Text>(
          find.descendant(of: find.byKey(key), matching: find.byType(Text)),
        )
        .map((t) => t.data ?? '')
        .join(' ');
  }

  group('barra por modo', () {
    testWidgets('modo individual: Chacos sustituye a Personas', (tester) async {
      final s = await activatedHousehold(tester, 'ind_nav_personal');
      await toPersonal(tester, s.database);
      final c = await pumpModeApp(tester, s.database);
      expect(navLabel('Chacos'), findsOneWidget);
      expect(navLabel('Personas'), findsNothing);
      for (final label in ['Inicio', 'Actividad', 'Almacén', 'Sindicato']) {
        expect(navLabel(label), findsOneWidget, reason: label);
      }
      await tester.tap(navLabel('Chacos'));
      await settle(tester);
      expect(currentPath(c), '/chacos');
      // Una ruta de Personas (consulta histórica) resalta Chacos: siempre
      // queda una pestaña elegida.
      c.read(routerProvider).go('/personas');
      await settle(tester);
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, 3);
    });

    testWidgets('modo con varias personas: la barra no cambia', (tester) async {
      final s = await activatedHousehold(tester, 'ind_nav_shared');
      await pumpModeApp(tester, s.database);
      expect(navLabel('Personas'), findsOneWidget);
      expect(navLabel('Chacos'), findsNothing);
    });
  });

  group('Inicio individual', () {
    testWidgets('I-02: campaña sin registros, sin cifras en cero', (
      tester,
    ) async {
      final s = await activatedHousehold(tester, 'ind_home_empty');
      await toPersonal(tester, s.database);
      await pumpModeApp(tester, s.database);
      expect(find.byKey(const Key('ind-home-empty-title')), findsOneWidget);
      expect(find.byKey(const Key('ind-home-step-farm')), findsOneWidget);
      expect(find.byKey(const Key('ind-home-step-purchase')), findsOneWidget);
      expect(
        find.byKey(const Key('ind-home-step-application')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('ind-home-applied')), findsNothing);
      expect(find.byKey(const Key('home-figure-received')), findsNothing);
      expect(find.byKey(const Key('home-receivable-total')), findsNothing);
      // El titular ya tiene un chaco: el paso 1 se marca hecho.
      expect(
        textOf(tester, const Key('ind-home-step-farm')),
        contains('Sus chacos'),
      );
    });

    testWidgets('I-01: costo aplicado y compras de la campaña, deuda de todas, '
        'sin cobros a personas', (tester) async {
      final s = await activatedHousehold(tester, 'ind_home_figures');
      final h = s.household;
      await toPersonal(tester, s.database);
      late Map<String, Object?> close;
      await tester.runAsync(() async {
        // Compra a crédito de 5 L a 100 Bs/L con un pago parcial de 120 Bs,
        // y una aplicación de 2 L en el chaco del titular.
        final purchase = await h.buy(h.titular, 5000);
        await h.repo.addProviderPayment(
          purchaseId: purchase,
          payerPersonId: h.titular,
          amountBobMinor: 12000,
          method: PaymentMethod.cash,
        );
        await h.apply(h.titular, h.titularFarm, 2000);
        close = await h.repo.campaignCloseSummary(h.campaign);
      });
      await pumpModeApp(tester, s.database);

      final applied = close['applications_bob_minor']! as int;
      final purchases = close['purchases_bob_minor']! as int;
      expect(applied, greaterThan(0));
      expect(purchases, 50000);
      expect(
        textOf(tester, const Key('ind-home-applied-label')),
        'Costo de productos aplicados · Campaña 1',
      );
      expect(
        textOf(tester, const Key('ind-home-applied')),
        splitBob(applied).number,
      );
      expect(
        tester.getSemantics(find.byKey(const Key('ind-home-purchases'))).label,
        'Compras · Campaña 1: ${formatBob(purchases).trim()}',
      );
      expect(
        tester
            .getSemantics(find.byKey(const Key('ind-home-provider-debt')))
            .label,
        'Debe a proveedores · todas las campañas: '
        '${formatBob(50000 - 12000).trim()}',
      );
      expect(
        textOf(tester, const Key('home-attention-provider-balance')),
        '1 compra pendiente de pago',
      );
      expect(find.byKey(const Key('home-figure-received')), findsNothing);
      expect(find.byKey(const Key('home-top-balances')), findsNothing);
      expect(find.byKey(const Key('ind-home-plans')), findsOneWidget);
    });

    testWidgets('modo con varias personas: Inicio de siempre', (tester) async {
      final s = await activatedHousehold(tester, 'ind_home_shared');
      await pumpModeApp(tester, s.database);
      expect(find.byKey(const Key('home-receivable-total')), findsOneWidget);
      expect(find.byKey(const Key('ind-home-applied')), findsNothing);
      expect(find.byKey(const Key('ind-home-empty-title')), findsNothing);
    });
  });

  group('hoja Registrar', () {
    Future<void> openSheet(WidgetTester tester, ProviderContainer c) async {
      c.read(routerProvider).go('/operaciones');
      await settle(tester);
      await tester.tap(find.byKey(const Key('shell-registrar')));
      await settle(tester);
    }

    testWidgets('I-03: pago a un proveedor, sin transferencia ni cobro', (
      tester,
    ) async {
      final s = await activatedHousehold(tester, 'ind_register_personal');
      await toPersonal(tester, s.database);
      final c = await pumpModeApp(tester, s.database);
      await openSheet(tester, c);
      expect(find.byKey(const Key('register-purchase')), findsOneWidget);
      expect(find.byKey(const Key('register-application')), findsOneWidget);
      expect(find.byKey(const Key('register-plan')), findsOneWidget);
      expect(
        find.byKey(const Key('register-provider-payment')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('register-payment')), findsNothing);
      expect(find.byKey(const Key('register-transfer')), findsNothing);
      expect(find.byKey(const Key('register-voice-note')), findsOneWidget);
    });

    testWidgets('modo con varias personas: hoja de siempre', (tester) async {
      final s = await activatedHousehold(tester, 'ind_register_shared');
      final c = await pumpModeApp(tester, s.database);
      await openSheet(tester, c);
      expect(find.byKey(const Key('register-payment')), findsOneWidget);
      expect(find.byKey(const Key('register-transfer')), findsOneWidget);
      expect(find.byKey(const Key('register-voice')), findsOneWidget);
      expect(find.byKey(const Key('register-provider-payment')), findsNothing);
    });
  });

  group('Ajustes y Modo de uso', () {
    testWidgets('I-50: modo y titular arriba; datos y seguridad', (
      tester,
    ) async {
      final s = await activatedHousehold(tester, 'ind_settings');
      await toPersonal(tester, s.database);
      final c = await pumpModeApp(tester, s.database);
      c.read(routerProvider).push('/mas');
      await settle(tester);
      expect(find.text('Modo individual'), findsOneWidget);
      expect(find.byKey(const Key('more-owner-name')), findsOneWidget);
      expect(find.text('Chacos, productos y proveedores'), findsOneWidget);
      for (final key in [
        'more-campaigns',
        'more-reports',
        'more-late',
        'more-access',
        'more-pin',
        'more-backups',
        'more-licenses',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
    });

    testWidgets('I-51: desde individual el cambio está disponible', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final s = await activatedHousehold(tester, 'ind_mode_available');
      await toPersonal(tester, s.database);
      final c = await pumpModeApp(tester, s.database);
      c.read(routerProvider).push('/modo');
      await settle(tester);
      expect(textOf(tester, const Key('mode-current')), 'Modo individual');
      expect(find.byKey(const Key('mode-available')), findsOneWidget);
      expect(find.byKey(const Key('mode-blocked')), findsNothing);
      final button = tester.widget<OutlinedButton>(
        find.byKey(const Key('mode-change')),
      );
      expect(button.onPressed, isNotNull);
      expect(find.text('Pasar a varias personas'), findsOneWidget);
    });

    testWidgets(
      'I-52: con existencias de otra persona el cambio se bloquea con el '
      'motivo real y no se borra nada',
      (tester) async {
        final s = await activatedHousehold(tester, 'ind_mode_blocked');
        final h = s.household;
        late Map<String, List<Map<String, Object?>>> before;
        await tester.runAsync(() async {
          await h.buy(h.relative, 3000);
          before = await dumpTables(await s.database.database);
        });
        final c = await pumpModeApp(tester, s.database);
        c.read(routerProvider).push('/modo');
        await settle(tester);
        expect(
          textOf(tester, const Key('mode-current')),
          'Modo con varias personas',
        );
        expect(find.byKey(const Key('mode-blocked')), findsOneWidget);
        expect(find.text('Hermana tiene productos'), findsOneWidget);
        final button = tester.widget<OutlinedButton>(
          find.byKey(const Key('mode-change')),
        );
        expect(button.onPressed, isNull);
        expect(
          textOf(tester, const Key('mode-change-hint')),
          'Se activará cuando no queden pendientes.',
        );
        final after = await tester.runAsync(
          () async => dumpTables(await s.database.database),
        );
        expect(after, before);
        expect(
          await tester.runAsync(() => OperationModeStore(s.database).current()),
          OperationMode.shared,
        );
      },
    );

    test('nombres de los modos de las láminas', () {
      expect(operationModeTitle(OperationMode.personal), 'Modo individual');
      expect(
        operationModeTitle(OperationMode.shared),
        'Modo con varias personas',
      );
    });
  });
}
