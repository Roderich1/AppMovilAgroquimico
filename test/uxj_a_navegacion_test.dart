// Bloque A de la presentación para el jurado (2026-11-05): textos, el «+» y
// la navegación.
//   (a) Campañas y Reportes, abiertos desde Operaciones, marcan Operaciones
//       en la barra inferior y Atrás vuelve a Operaciones.
//   (b) «Ir a campañas» (aplicación sin campaña activa) llega a Campañas.
//   (c) El panel del «+» pone primero Compra, Aplicación y Planificación;
//       Pago y Transferencia después. En 360×800 con letra al 100 y al
//       200 % todas las filas se ven enteras y miden al menos 48 de alto.
//   (d) En el ancho del POCO (393×873) el «+» no tapa ninguna tarjeta de
//       Operaciones sin desplazar.
//   (e) Operaciones: tarjetas con icono y nombre; sólo Campañas añade la
//       campaña actual.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/presentation/screens/campaigns_screen.dart';
import 'package:agroquimicos/presentation/screens/operations_screen.dart';
import 'package:agroquimicos/presentation/screens/reports_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_ui_harness.dart';

const _fabName = 'Registrar operación';

void main() {
  sqfliteFfiInit();

  int selectedTab(WidgetTester tester) =>
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

  void phone(WidgetTester tester, Size size, {double textScale = 1}) {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  for (final (title, screen) in [
    ('Campañas', CampaignsScreen),
    ('Reportes', ReportsScreen),
  ]) {
    testWidgets('(a) $title desde Operaciones: barra en Operaciones y Atrás '
        'vuelve', (tester) async {
      phone(tester, const Size(393, 873));
      final s = await activatedHousehold(tester, 'uxj-a-$title');
      final c = await pumpModeApp(tester, s.database);
      c.read(routerProvider).go('/operaciones');
      await settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(OperationsScreen),
          matching: find.text(title),
        ),
      );
      await settle(tester);
      expect(find.byType(screen), findsOneWidget);
      expect(selectedTab(tester), 1, reason: 'Operaciones marcada');

      // Atrás del sistema, como en el teléfono.
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(screen), findsNothing);
      expect(find.byType(OperationsScreen), findsOneWidget);
      expect(selectedTab(tester), 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('(b) «Ir a campañas» llega a la pantalla de Campañas', (
    tester,
  ) async {
    phone(tester, const Size(393, 873));
    final s = await activatedHousehold(tester, 'uxj-a-ir');
    await tester.runAsync(
      () => s.household.repo.closeCampaign(s.household.campaign),
    );
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).go('/aplicaciones');
    await settle(tester);
    await tester.tap(find.text('Registrar'));
    await settle(tester);
    expect(find.text('Falta una campaña activa'), findsOneWidget);
    await tester.tap(find.text('Ir a campañas'));
    await settle(tester);
    expect(find.byType(CampaignsScreen), findsOneWidget);
    expect(find.text('Sin campaña activa'), findsWidgets);
    expect(selectedTab(tester), 1);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('(c) panel del «+» al ${scale * 100} % en 360×800: orden y '
        'filas enteras', (tester) async {
      phone(tester, const Size(360, 800), textScale: scale);
      final s = await activatedHousehold(tester, 'uxj-a-panel-$scale');
      final c = await pumpModeApp(tester, s.database);
      c.read(routerProvider).go('/operaciones');
      await settle(tester);
      await tester.tap(find.byTooltip(_fabName));
      await settle(tester);
      final sheet = find.byType(BottomSheet);
      expect(sheet, findsOneWidget);
      final screen = Offset.zero & const Size(360, 800);
      var previousTop = double.negativeInfinity;
      for (final option in const [
        'Compra',
        'Aplicación',
        'Planificación',
        'Pago',
        'Transferencia',
      ]) {
        final label = find.descendant(of: sheet, matching: find.text(option));
        expect(label, findsOneWidget, reason: option);
        final row = find.ancestor(of: label, matching: find.byType(ListTile));
        final rect = tester.getRect(row);
        expect(rect.top, greaterThan(previousTop), reason: 'orden: $option');
        previousTop = rect.top;
        expect(
          screen.intersect(rect) == rect,
          isTrue,
          reason: '«$option» entera en pantalla: $rect',
        );
        expect(rect.height, greaterThanOrEqualTo(48), reason: option);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('(d) en el ancho del POCO el «+» no tapa ninguna tarjeta de '
      'Operaciones', (tester) async {
    phone(tester, const Size(393, 873));
    final s = await activatedHousehold(tester, 'uxj-a-poco');
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).go('/operaciones');
    await settle(tester);
    final fab = tester.getRect(find.byTooltip(_fabName));
    final cards = find.descendant(
      of: find.byType(OperationsScreen),
      matching: find.byType(Card),
    );
    expect(cards, findsNWidgets(7));
    for (final card in cards.evaluate()) {
      final rect = tester.getRect(find.byWidget(card.widget));
      expect(rect.overlaps(fab), isFalse, reason: 'tarjeta $rect, «+» $fab');
    }
  });

  testWidgets('(e) Operaciones: icono y nombre; sólo Campañas añade la '
      'campaña actual', (tester) async {
    phone(tester, const Size(393, 873));
    final s = await activatedHousehold(tester, 'uxj-a-tarjetas');
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).go('/operaciones');
    await settle(tester);
    final tiles = tester
        .widgetList<ListTile>(
          find.descendant(
            of: find.byType(OperationsScreen),
            matching: find.byType(ListTile),
          ),
        )
        .toList();
    expect(tiles, hasLength(7));
    expect(tiles.where((t) => t.subtitle != null), hasLength(1));
    expect(find.text('Actual: Campaña 1'), findsOneWidget);
    expect(find.text('Facturas y pagos al proveedor'), findsNothing);
  });
}
