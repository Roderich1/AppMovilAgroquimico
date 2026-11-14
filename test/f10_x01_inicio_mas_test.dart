// Inicio y «Más» tras el piloto X01: cuatro accesos principales con icono y
// texto que llevan al inicio real de cada registro; las funciones poco
// frecuentes agrupadas en «Más» con todos sus accesos; sin «Nuevo» flotante
// que compita en Inicio. «Sindicato» sólo abre la pantalla (la misma que la
// pestaña, revisión del autor del 2026-11-12).
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/presentation/app_shell.dart';
import 'package:agroquimicos/presentation/widgets/adaptive_entity_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_ui_harness.dart';
import 'support/purchase_form_driver.dart';

typedef Row = Map<String, Object?>;

void main() {
  sqfliteFfiInit();

  Finder picker(String label) => find.byWidgetPredicate(
    (w) => w is AdaptiveEntityPicker<Row> && w.label == label,
  );

  Future<void> choose(WidgetTester tester, String label, String name) async {
    final widget = tester.widget<AdaptiveEntityPicker<Row>>(picker(label));
    widget.onChanged(
      widget.items.firstWhere((item) => widget.labelOf(item) == name),
    );
    await settle(tester);
  }

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.pump();
    await tester.tap(find.byKey(Key(key)));
    await settle(tester);
  }

  // Rediseño (2026-11-12): «Más» son los ajustes y cuelga de Inicio.
  test('el shell: /mas es hija de Inicio y Inicio no tiene FAB', () {
    expect(
      const AppShell(location: '/mas', child: SizedBox()).selectedIndex,
      0,
    );
    expect(
      const AppShell(location: '/mas', child: SizedBox()).backFallback,
      '/',
    );
    expect(
      const AppShell(location: '/', child: SizedBox()).hidesGlobalFab,
      isTrue,
    );
    expect(
      const AppShell(
        location: '/operaciones',
        child: SizedBox(),
      ).hidesGlobalFab,
      isFalse,
    );
  });

  testWidgets('Inicio: los cuatro accesos, sin «Nuevo» flotante; cada uno abre '
      'su destino y no envía nada', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, 'inicio');
    final offline = OfflineTransport();
    final c = await pumpModeApp(tester, s.database, transport: offline);

    for (final label in [
      'Registrar compra',
      'Registrar aplicación',
      'Ver cuánto queda',
      'Envíos, convocatorias y lo que comparte',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('Sincronización con el sindicato'), findsNothing);

    // Registrar compra abre el formulario en su primer paso.
    await tapKey(tester, 'home-registrar-compra');
    await waitFor(tester, find.byKey(const Key('purchase-add-line')));
    expect(find.text('¿Qué compró?'), findsOneWidget);
    expect(find.text('¿Qué compró?'), findsOneWidget);
    c.read(routerProvider).pop();
    await settle(tester);
    expect(find.text('Registrar compra'), findsOneWidget);

    // Registrar aplicación abre su formulario.
    await tapKey(tester, 'home-registrar-aplicacion');
    await waitFor(tester, picker('Chaco'));
    expect(find.byKey(const Key('application-step')), findsOneWidget);
    expect(find.text('¿Dónde aplicó?'), findsOneWidget);
    c.read(routerProvider).pop();
    await settle(tester);

    // Ver cuánto queda lleva al inventario.
    await tapKey(tester, 'home-ver-cuanto-queda');
    expect(currentPath(c), '/inventario');
    // Rediseño B: la pantalla se llama Almacén (como su pestaña).
    expect(find.byKey(const Key('page-frame-title')), findsOneWidget);
    expect(find.text('Almacén'), findsWidgets);
    c.read(routerProvider).go('/');
    await settle(tester);

    // «Sindicato» abre la pantalla principal de Sindicato (la de la
    // pestaña) y no publica ni consulta nada: ni una petición. Enviar y
    // actualizar siguen siendo acciones aparte.
    final requestsBefore = offline.requests;
    await tapKey(tester, 'home-enviar-sindicato');
    await waitFor(tester, find.byKey(const Key('union-status')));
    expect(currentPath(c), '/sindicato');
    expect(find.byKey(const Key('union-refresh')), findsOneWidget);
    expect(offline.requests, requestsBefore);
  });

  testWidgets('Inicio: al guardar una compra desde el acceso directo se avisa '
      '«Compra guardada.» y se vuelve a Inicio', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, 'inicio-compra');
    await pumpModeApp(tester, s.database);
    await tapKey(tester, 'home-registrar-compra');
    await waitFor(tester, find.byKey(const Key('purchase-add-line')));
    await settle(tester);
    await choose(tester, 'Proveedor', 'Proveedor');
    await openPurchaseLine(tester);
    await choose(tester, 'Producto', 'Glifosato');
    await openPurchaseLine(tester);
    await tester.enterText(field('Cantidad comprada'), '1');
    await openPurchaseLine(tester);
    await tester.enterText(field('Precio por L'), '10');
    await tapKey(tester, 'purchase-alloc-single-0');
    await choose(tester, 'Persona', 'Titular');
    await settle(tester);
    await closePurchaseLine(tester);
    await tapKey(tester, 'purchase-continue');
    await tester.tap(find.byKey(const Key('purchase-paid-no')));
    await settle(tester);
    expect(find.byKey(const Key('purchase-no-payment')), findsOneWidget);
    await tapKey(tester, 'purchase-confirm');
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    expect(find.text('Compra guardada.'), findsOneWidget);
    expect(find.text('Registrar compra'), findsOneWidget);
    final payments = await tester.runAsync(
      () async => (await s.database.database).query('provider_payments'),
    );
    expect(payments, isEmpty);
  });

  testWidgets('Actividad: lo diario y Reportes; Más (desde Inicio) conserva '
      'los accesos y Atrás vuelve', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, 'mas');
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).go('/operaciones');
    await settle(tester);
    // Rediseño B: Actividad filtra por tipo y abre cada lista; Reportes va en
    // su cabecera. Más y Campañas cuelgan de Inicio (B1).
    for (final title in [
      'Compras',
      'Aplicaciones',
      'Planes',
      'Transferencias',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(find.byTooltip('Reportes'), findsOneWidget);
    expect(find.text('Más'), findsNothing);
    expect(
      find.text('Personas, chacos, productos y proveedores'),
      findsNothing,
    );
    expect(find.textContaining('FIFO'), findsNothing);

    c.read(routerProvider).go('/');
    await settle(tester);
    await tester.tap(find.byKey(const Key('home-settings')));
    await settle(tester);
    // Con `push` el router no cambia la ruta base: se mira la pantalla.
    expect(find.text('Ajustes y datos'), findsWidgets);
    // Reportes está en la cabecera de Actividad (2026-11-05) y no se repite
    // aquí; Vínculos y Compras conjuntas, en la pestaña Sindicato (rediseño).
    expect(find.text('Reportes'), findsNothing);
    for (final title in [
      'Personas, chacos, productos y proveedores',
      'Campañas',
      'Operaciones tardías',
      'Acceso en línea',
      'PIN del titular',
      'Respaldos',
      'Modo de uso',
      'Registrar por voz',
      'Licencias',
    ]) {
      await tester.scrollUntilVisible(
        find.text(title),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(title), findsOneWidget, reason: title);
    }
    await tester.scrollUntilVisible(
      find.text('Personas, chacos, productos y proveedores'),
      -100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Personas, chacos, productos y proveedores'));
    await settle(tester);
    expect(find.text('Datos'), findsWidgets);
    expect(
      find.text('Personas, chacos, productos y proveedores'),
      findsNothing,
    );
    c.read(routerProvider).pop();
    await settle(tester);
    expect(
      find.text('Personas, chacos, productos y proveedores'),
      findsOneWidget,
    );
  });
}
