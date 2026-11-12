// Bloque A de la presentación para el jurado (2026-11-05): textos, el «+» y
// la navegación.
//   (a) Campañas (desde Inicio) y Reportes (desde Actividad) marcan su
//       pestaña en la barra inferior y Atrás vuelve a ella (rediseño B).
//   (b) «Ir a campañas» (aplicación sin campaña activa) llega a Campañas.
//   (c) El panel del «+» pone primero Compra, Aplicación y Planificación;
//       Pago y Transferencia después. En 360×800 con letra al 100 y al
//       200 % todas las filas se ven enteras y miden al menos 48 de alto.
//   (d) En el ancho del POCO (393×873) el «+» no tapa los botones ni los
//       filtros de Actividad sin desplazar (rediseño B).
//   (e) Actividad: filtros con nombre y Reportes; Más y Campañas, en Inicio.
//   (f) Al volver de un formulario, la pantalla de debajo no conserva una
//       flecha «Volver» que no lleva a ningún sitio.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/presentation/screens/applications_screen.dart';
import 'package:agroquimicos/presentation/screens/dashboard_screen.dart';
import 'package:agroquimicos/presentation/screens/campaigns_screen.dart';
import 'package:agroquimicos/presentation/screens/operations_screen.dart';
import 'package:agroquimicos/presentation/screens/reports_screen.dart';
import 'package:agroquimicos/presentation/widgets/agro_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_ui_harness.dart';

// Rediseño (2026-11-12): «+ Registrar» con nombre visible.
const _fab = Key('shell-registrar');

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

  // Rediseño B (2026-11-12): Campañas es un ajuste y se abre desde la
  // campaña de la cabecera de Inicio (B1); Reportes sigue en Actividad, como
  // botón de la cabecera. Cada uno marca su pestaña y Atrás vuelve a ella.
  for (final (title, screen, origin, tab, key) in [
    ('Campañas', CampaignsScreen, '/', 0, 'home-active-campaign'),
    ('Reportes', ReportsScreen, '/operaciones', 1, 'activity-reports'),
  ]) {
    testWidgets('(a) $title desde su pestaña: barra en su pestaña y Atrás '
        'vuelve', (tester) async {
      phone(tester, const Size(393, 873));
      final s = await activatedHousehold(tester, 'uxj-a-$title');
      final c = await pumpModeApp(tester, s.database);
      c.read(routerProvider).go(origin);
      await settle(tester);
      await tester.tap(find.byKey(Key(key)));
      await settle(tester);
      expect(find.byType(screen), findsOneWidget);
      expect(selectedTab(tester), tab, reason: 'pestaña de $title');

      // Atrás del sistema, como en el teléfono.
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(screen), findsNothing);
      expect(
        find.byType(tab == 0 ? DashboardScreen : OperationsScreen),
        findsOneWidget,
      );
      expect(selectedTab(tester), tab);
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
    // El botón de la lista, no el «+ Registrar» del shell.
    await tester.tap(
      find.descendant(
        of: find.byType(ApplicationsScreen),
        matching: find.text('Registrar'),
      ),
    );
    await settle(tester);
    expect(find.text('Falta una campaña activa'), findsOneWidget);
    await tester.tap(find.text('Ir a campañas'));
    await settle(tester);
    expect(find.byType(CampaignsScreen), findsOneWidget);
    expect(find.text('Sin campaña activa'), findsWidgets);
    expect(selectedTab(tester), 0, reason: 'Campañas cuelga de Inicio');
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('(c) panel del «+» al ${scale * 100} % en 360×800: orden y '
        'filas enteras', (tester) async {
      phone(tester, const Size(360, 800), textScale: scale);
      final s = await activatedHousehold(tester, 'uxj-a-panel-$scale');
      final c = await pumpModeApp(tester, s.database);
      c.read(routerProvider).go('/operaciones');
      await settle(tester);
      await tester.tap(find.byKey(_fab));
      await settle(tester);
      final sheet = find.byType(BottomSheet);
      expect(sheet, findsOneWidget);
      final screen = Offset.zero & const Size(360, 800);
      var previousTop = double.negativeInfinity;
      for (final option in const [
        'Compra',
        'Aplicación',
        'Plan de aplicación',
        'Pago',
        'Transferencia',
      ]) {
        final label = find.descendant(of: sheet, matching: find.text(option));
        expect(label, findsOneWidget, reason: option);
        // Compra y Aplicación son botones grandes (lado a lado si caben); el
        // resto, filas; la voz, un panel punteado.
        final row = find
            .ancestor(
              of: label,
              matching: find.byWidgetPredicate(
                (w) => w is ListTile || w is ActionTile || w is DashedPanel,
              ),
            )
            .first;
        final rect = tester.getRect(row);
        expect(
          rect.top,
          greaterThanOrEqualTo(previousTop),
          reason: 'orden: $option',
        );
        previousTop = rect.top;
        expect(
          screen.intersect(rect) == rect,
          isTrue,
          reason: '«$option» entera en pantalla: $rect',
        );
        expect(rect.height, greaterThanOrEqualTo(48), reason: option);
      }
      // «Completar por voz» (nuevo en la hoja, 2026-11-12) va al final: con
      // la letra al 200 % se alcanza desplazando la hoja.
      final voice = find.descendant(
        of: sheet,
        matching: find.text('Completar por voz'),
      );
      expect(voice, findsOneWidget);
      await tester.ensureVisible(voice);
      await settle(tester);
      expect(
        screen.contains(tester.getCenter(voice)),
        isTrue,
        reason: '«Completar por voz» alcanzable',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('(d) en el ancho del POCO el «+» no tapa los botones ni los '
      'filtros de Actividad', (tester) async {
    phone(tester, const Size(393, 873));
    final s = await activatedHousehold(tester, 'uxj-a-poco');
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).go('/operaciones');
    await settle(tester);
    final fab = tester.getRect(find.byKey(_fab));
    // Rediseño B: Actividad ya no es una cuadrícula de tarjetas; lo que se
    // toca sin desplazar son los botones de la cabecera y los filtros.
    final controls = [
      find.byKey(const Key('activity-search-toggle')),
      find.byKey(const Key('activity-reports')),
      for (final f in ['all', 'purchases', 'applications', 'plans'])
        find.byKey(Key('activity-filter-$f')),
    ];
    for (final control in controls) {
      final rect = tester.getRect(control);
      expect(rect.overlaps(fab), isFalse, reason: '$control $rect, «+» $fab');
    }
  });

  testWidgets('(e) Actividad: filtros con nombre, Reportes en la cabecera; '
      'Más y Campañas están en Inicio', (tester) async {
    phone(tester, const Size(393, 873));
    final s = await activatedHousehold(tester, 'uxj-a-tarjetas');
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).go('/operaciones');
    await settle(tester);
    final activity = find.byType(OperationsScreen);
    for (final label in [
      'Todo',
      'Compras',
      'Aplicaciones',
      'Planes',
      'Transferencias',
    ]) {
      expect(
        find.descendant(of: activity, matching: find.text(label)),
        findsOneWidget,
        reason: label,
      );
    }
    expect(find.byTooltip('Reportes'), findsOneWidget);
    expect(
      find.descendant(of: activity, matching: find.text('Más')),
      findsNothing,
    );
    expect(
      find.descendant(of: activity, matching: find.text('Campañas')),
      findsNothing,
    );
    expect(find.text('Facturas y pagos al proveedor'), findsNothing);
  });

  testWidgets('(f) tras volver de un formulario abierto con el teclado, la '
      'pantalla de debajo no queda con una flecha «Volver» muerta', (
    tester,
  ) async {
    phone(tester, const Size(393, 873));
    final s = await activatedHousehold(tester, 'uxj-a-volver');
    final c = await pumpModeApp(tester, s.database);
    final router = c.read(routerProvider);
    // Se llega con `go`: no hay nada a lo que volver. Lo que reconstruye la
    // pantalla de debajo es el «+», que se oculta con el teclado.
    router.go('/operaciones');
    await settle(tester);
    expect(find.byTooltip('Volver'), findsNothing);

    router.push('/compras/nueva');
    await settle(tester);
    // El teclado del formulario reconstruye también la pantalla de debajo.
    tester.view.viewInsets = const FakeViewPadding(bottom: 600);
    await tester.pump();
    await settle(tester);
    tester.view.resetViewInsets();
    await tester.pump();
    await settle(tester);
    router.pop();
    await settle(tester);

    expect(find.byType(OperationsScreen), findsOneWidget);
    expect(find.byTooltip('Volver'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
