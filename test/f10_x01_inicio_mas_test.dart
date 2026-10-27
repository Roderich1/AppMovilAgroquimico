// Inicio y «Más» tras el piloto X01: cuatro accesos principales con icono y
// texto que llevan al inicio real de cada registro; las funciones poco
// frecuentes agrupadas en «Más» con todos sus accesos; sin «Nuevo» flotante
// que compita en Inicio. «Enviar al sindicato» sólo abre la pantalla.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/presentation/app_shell.dart';
import 'package:agroquimicos/presentation/widgets/adaptive_entity_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_ui_harness.dart';

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

  test('el shell: /mas es hija de Operaciones y Inicio no tiene FAB', () {
    expect(
      const AppShell(location: '/mas', child: SizedBox()).selectedIndex,
      1,
    );
    expect(
      const AppShell(location: '/mas', child: SizedBox()).backFallback,
      '/operaciones',
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
      'Enviar al sindicato',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('Sincronización con el sindicato'), findsNothing);

    // Registrar compra abre el formulario en su primer paso.
    await tapKey(tester, 'home-registrar-compra');
    await waitFor(tester, field('Cantidad comprada'));
    expect(find.text('Nueva compra'), findsOneWidget);
    expect(find.text('Paso 1 de 2 · Proveedor y productos'), findsOneWidget);
    c.read(routerProvider).pop();
    await settle(tester);
    expect(find.text('Registrar compra'), findsOneWidget);

    // Registrar aplicación abre su formulario.
    await tapKey(tester, 'home-registrar-aplicacion');
    await waitFor(tester, picker('Chaco'));
    expect(find.text('Nueva aplicación'), findsOneWidget);
    expect(find.text('Paso 1 de 3 · Persona y chaco'), findsOneWidget);
    c.read(routerProvider).pop();
    await settle(tester);

    // Ver cuánto queda lleva al inventario.
    await tapKey(tester, 'home-ver-cuanto-queda');
    expect(currentPath(c), '/inventario');
    expect(find.text('Inventario'), findsWidgets);
    c.read(routerProvider).go('/');
    await settle(tester);

    // Enviar al sindicato abre la pantalla y no publica nada: ni una
    // petición, y «Sincronizar ahora» sigue siendo una acción aparte.
    final requestsBefore = offline.requests;
    await tapKey(tester, 'home-enviar-sindicato');
    await waitFor(tester, find.text('Sincronizar ahora'));
    expect(find.text('Sincronización'), findsWidgets);
    expect(find.text('Sincronizar ahora'), findsOneWidget);
    expect(offline.requests, requestsBefore);
  });

  testWidgets('Inicio: al guardar una compra desde el acceso directo se avisa '
      '«Compra guardada.» y se vuelve a Inicio', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, 'inicio-compra');
    await pumpModeApp(tester, s.database);
    await tapKey(tester, 'home-registrar-compra');
    await waitFor(tester, field('Cantidad comprada'));
    await settle(tester);
    await choose(tester, 'Proveedor', 'Proveedor');
    await choose(tester, 'Producto', 'Glifosato');
    await tester.enterText(field('Cantidad comprada'), '1');
    await tester.enterText(field('Precio BOB/L'), '10');
    await tapKey(tester, 'purchase-alloc-single-0');
    await choose(tester, 'Persona', 'Titular');
    await settle(tester);
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

  testWidgets('Operaciones: lo diario y «Más»; Más conserva los accesos y '
      'Atrás vuelve', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, 'mas');
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).go('/operaciones');
    await settle(tester);
    for (final title in [
      'Compras',
      'Aplicaciones',
      'Planificación',
      'Transferencias',
      'Más',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(find.text('Administrar datos'), findsNothing);
    expect(find.textContaining('FIFO'), findsNothing);

    await tester.tap(find.text('Más'));
    await settle(tester);
    // Con `push` el router no cambia la ruta base: se mira la pantalla.
    expect(find.text('Lo que se usa de vez en cuando.'), findsOneWidget);
    for (final title in [
      'Reportes',
      'Administrar datos',
      'Modo de uso',
      'Vínculos con el sindicato',
      'Respaldo en la nube',
      'Copias de seguridad en este teléfono',
      'PIN del titular',
      'Operaciones tardías',
      'Registrar por voz',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    await tester.tap(find.text('Administrar datos'));
    await settle(tester);
    expect(find.text('Catálogos'), findsWidgets);
    expect(find.text('Lo que se usa de vez en cuando.'), findsNothing);
    c.read(routerProvider).pop();
    await settle(tester);
    expect(find.text('Lo que se usa de vez en cuando.'), findsOneWidget);
  });
}
