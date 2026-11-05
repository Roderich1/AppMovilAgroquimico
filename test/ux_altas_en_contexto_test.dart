// Presentación móvil (2026-11-05): altas en el selector que las usa, accesos
// propios a Campañas y Reportes, y el «+» que abre los formularios.
//
// Recorridos sobre la app completa (arnés de F04, base en archivo,
// repositorio real), en modalidad compartida:
//   (a) Compra, «Crear producto» en el selector de la línea 2: lo creado queda
//       elegido en esa línea y la línea 1 (producto, cantidad, precio), el
//       proveedor y la fecha siguen igual;
//   (b) Compra, «Crear proveedor»: queda elegido y la línea no cambia;
//   (c) Compra, cancelar el alta no cambia el borrador ni escribe nada;
//   (d) Compra, si la escritura falla se avisa y el borrador sigue igual;
//   (e) Planificación: «Crear chaco» y «Crear producto» quedan elegidos;
//   (f) Aplicación: «Crear chaco» con el dueño ya decidido; el selector de
//       productos (existencias) no ofrece altas;
//   (g) Operaciones muestra Campañas (con la actual) y Reportes; Más ya no
//       repite Reportes; Campañas es una pantalla propia sin «+»;
//   (h) el «+» abre directamente el formulario de aplicación.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/presentation/widgets/adaptive_entity_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_ui_harness.dart';

typedef Row = Map<String, Object?>;

/// Repositorio cuyas altas de catálogo fallan, para el caso (d).
class _FailingCatalogRepository extends AgroRepository {
  _FailingCatalogRepository(super.appDatabase);

  @override
  Future<int> addSupplier({
    required String name,
    String? phone,
    String? notes,
  }) async => throw BusinessRuleException('No se pudo guardar el proveedor.');
}

void main() {
  sqfliteFfiInit();

  Finder picker(String label) => find.byWidgetPredicate(
    (w) => w is AdaptiveEntityPicker<Row> && w.label == label,
  );

  AdaptiveEntityPicker<Row> pickerAt(
    WidgetTester tester,
    String label, [
    int position = 0,
  ]) => tester
      .widgetList<AdaptiveEntityPicker<Row>>(picker(label))
      .elementAt(position);

  Future<void> choose(
    WidgetTester tester,
    String label,
    String name, {
    int position = 0,
  }) async {
    final widget = pickerAt(tester, label, position);
    widget.onChanged(
      widget.items.firstWhere((item) => widget.labelOf(item) == name),
    );
    await settle(tester);
  }

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );

  String fieldText(WidgetTester tester, String label, [int position = 0]) =>
      tester
          .widgetList<TextField>(field(label))
          .elementAt(position)
          .controller!
          .text;

  /// Abre la hoja del selector [label] y toca su fila «[createLabel]».
  Future<void> openCreate(
    WidgetTester tester,
    String label,
    String createLabel, {
    int position = 0,
  }) async {
    final target = picker(label).at(position);
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.tap(target);
    await settle(tester);
    expect(find.byKey(const Key('picker-create')), findsOneWidget);
    await tester.tap(find.text(createLabel));
    await settle(tester);
  }

  Future<List<Row>> rows(WidgetTester tester, db, String table) async =>
      (await tester.runAsync(
        () async => (await db.database).query(table, orderBy: 'id'),
      ))!;

  Future<void> openPurchase(WidgetTester tester, ProviderContainer c) async {
    c.read(routerProvider).push('/compras/nueva');
    await waitFor(tester, field('Cantidad comprada'));
    await settle(tester);
  }

  /// Proveedor, Glifosato, 2 L a 45 Bs/L y una segunda línea vacía.
  Future<void> fillDraft(WidgetTester tester) async {
    await choose(tester, 'Proveedor', 'Proveedor');
    await choose(tester, 'Producto', 'Glifosato');
    await tester.enterText(field('Cantidad comprada'), '2');
    await tester.enterText(field('Precio BOB/L'), '45');
    await settle(tester);
    await tester.tap(find.text('Añadir otro producto'));
    await settle(tester);
    expect(find.text('Productos (2)'), findsOneWidget);
  }

  void expectLineOneKept(WidgetTester tester) {
    expect(pickerAt(tester, 'Proveedor').value?['name'], 'Proveedor');
    expect(pickerAt(tester, 'Producto').value?['name'], 'Glifosato');
    expect(fieldText(tester, 'Cantidad comprada'), '2');
    expect(fieldText(tester, 'Precio BOB/L'), '45');
    expect(find.textContaining('(hoy)'), findsOneWidget);
    expect(find.text('Productos (2)'), findsOneWidget);
  }

  /// «Guardar» del alta y espera a que [done] se cumpla: el alta, la
  /// relectura de la lista y la elección encadenan varias consultas reales,
  /// más de las que espera [settle].
  Future<void> save(
    WidgetTester tester,
    String what,
    bool Function() done,
  ) async {
    await tester.tap(find.text('Guardar'));
    await waitUntil(tester, what, done);
    await settle(tester);
  }

  void bigSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('(a) Compra: «Crear producto» deja lo creado en la línea 2 y '
      'conserva la línea 1, el proveedor y la fecha', (tester) async {
    bigSurface(tester);
    final s = await activatedHousehold(tester, 'ux-a');
    final c = await pumpModeApp(tester, s.database);
    await openPurchase(tester, c);
    await fillDraft(tester);

    await openCreate(tester, 'Producto', 'Crear producto', position: 1);
    expect(find.text('Nuevo producto'), findsOneWidget);
    await tester.enterText(field('Producto'), 'Mancozeb UX');
    await tester.tap(find.text('Kilogramos'));
    await save(
      tester,
      'el alta del producto',
      () => pickerAt(tester, 'Producto', 1).value != null,
    );

    expect(find.text('Nuevo producto'), findsNothing);
    expect(pickerAt(tester, 'Producto', 1).value?['name'], 'Mancozeb UX');
    expect(pickerAt(tester, 'Producto', 1).value?['unit'], 'KG');
    expectLineOneKept(tester);
    final products = await rows(tester, s.database, 'products');
    expect([for (final p in products) p['name']], contains('Mancozeb UX'));
  });

  testWidgets('(b) Compra: «Crear proveedor» queda elegido y la línea no '
      'cambia', (tester) async {
    bigSurface(tester);
    final s = await activatedHousehold(tester, 'ux-b');
    final c = await pumpModeApp(tester, s.database);
    await openPurchase(tester, c);
    await fillDraft(tester);

    await openCreate(tester, 'Proveedor', 'Crear proveedor');
    await tester.enterText(field('Nombre del proveedor'), 'Agro Sur UX');
    await save(
      tester,
      'el alta del proveedor',
      () => pickerAt(tester, 'Proveedor').value?['name'] == 'Agro Sur UX',
    );

    expect(pickerAt(tester, 'Proveedor').value?['name'], 'Agro Sur UX');
    expect(pickerAt(tester, 'Producto').value?['name'], 'Glifosato');
    expect(fieldText(tester, 'Cantidad comprada'), '2');
    expect(fieldText(tester, 'Precio BOB/L'), '45');
  });

  testWidgets('(i) Compra: al cerrar el selector (elegir o crear) el foco no '
      'vuelve al precio y el teclado no se reabre', (tester) async {
    bigSurface(tester);
    final s = await activatedHousehold(tester, 'ux-i');
    final c = await pumpModeApp(tester, s.database);
    await openPurchase(tester, c);
    await fillDraft(tester);

    bool textFocused() =>
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<EditableText>() !=
        null;

    // `enterText` deja el foco en el precio, como al teclearlo.
    await tester.enterText(field('Precio BOB/L'), '45');
    await settle(tester);
    expect(textFocused(), isTrue);
    await tester.tap(picker('Proveedor'));
    await settle(tester);
    await tester.tap(
      find
          .descendant(
            of: find.byType(BottomSheet),
            // El título de la hoja también dice «Proveedor»: la fila es la última.
            matching: find.text('Proveedor'),
          )
          .last,
    );
    await settle(tester);
    expect(textFocused(), isFalse, reason: 'tras elegir en la hoja');

    await tester.enterText(field('Precio BOB/L'), '45');
    await settle(tester);
    await openCreate(tester, 'Proveedor', 'Crear proveedor');
    await tester.enterText(field('Nombre del proveedor'), 'Agro Foco UX');
    await save(
      tester,
      'el alta del proveedor',
      () => pickerAt(tester, 'Proveedor').value?['name'] == 'Agro Foco UX',
    );
    expect(textFocused(), isFalse, reason: 'tras crear desde la hoja');
    expect(fieldText(tester, 'Precio BOB/L'), '45');
  });

  testWidgets('(c) Compra: cancelar el alta no cambia el borrador ni escribe '
      'nada', (tester) async {
    bigSurface(tester);
    final s = await activatedHousehold(tester, 'ux-c');
    final c = await pumpModeApp(tester, s.database);
    await openPurchase(tester, c);
    await fillDraft(tester);
    final before = await rows(tester, s.database, 'suppliers');

    await openCreate(tester, 'Proveedor', 'Crear proveedor');
    await tester.enterText(field('Nombre del proveedor'), 'No se guarda');
    await tester.tap(find.text('Cancelar'));
    await settle(tester);

    expectLineOneKept(tester);
    expect(pickerAt(tester, 'Producto', 1).value, isNull);
    expect(
      await rows(tester, s.database, 'suppliers'),
      hasLength(before.length),
    );
  });

  testWidgets('(d) Compra: si el alta falla se avisa y el borrador sigue '
      'igual', (tester) async {
    bigSurface(tester);
    final s = await activatedHousehold(tester, 'ux-d');
    final c = await pumpModeApp(
      tester,
      s.database,
      extraOverrides: [
        repositoryProvider.overrideWith(
          (ref) => _FailingCatalogRepository(ref.watch(databaseProvider)),
        ),
      ],
    );
    await openPurchase(tester, c);
    await fillDraft(tester);

    await openCreate(tester, 'Proveedor', 'Crear proveedor');
    await tester.enterText(field('Nombre del proveedor'), 'Falla UX');
    await save(
      tester,
      'el aviso del fallo',
      () => find.text('No se pudo guardar el proveedor.').evaluate().isNotEmpty,
    );

    expect(find.text('No se pudo guardar el proveedor.'), findsOneWidget);
    expectLineOneKept(tester);
    expect(find.text('Paso 1 de 2 · Proveedor y productos'), findsOneWidget);
  });

  testWidgets('(e) Planificación: «Crear chaco» y «Crear producto» quedan '
      'elegidos', (tester) async {
    bigSurface(tester);
    final s = await activatedHousehold(tester, 'ux-e');
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).push('/planificacion/nueva');
    await waitFor(tester, picker('Chaco'));
    await settle(tester);

    await openCreate(tester, 'Chaco', 'Crear chaco');
    expect(find.text('Nuevo chaco'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await settle(tester);
    await tester.tap(find.text('Titular').last);
    await settle(tester);
    await tester.enterText(field('Nombre'), 'Chaco Loma UX');
    await tester.enterText(field('Superficie (ha)'), '2,5');
    await save(
      tester,
      'el alta del chaco',
      () => pickerAt(tester, 'Chaco').value?['name'] == 'Chaco Loma UX',
    );

    expect(pickerAt(tester, 'Chaco').value?['name'], 'Chaco Loma UX');
    expect(fieldText(tester, 'Área planificada (ha)'), '2,5');

    await openCreate(tester, 'Agregar producto', 'Crear producto');
    await tester.enterText(field('Producto'), 'Cipermetrina UX');
    await save(
      tester,
      'el alta del producto',
      () =>
          pickerAt(tester, 'Agregar producto').value?['name'] ==
          'Cipermetrina UX',
    );

    expect(
      pickerAt(tester, 'Agregar producto').value?['name'],
      'Cipermetrina UX',
    );
    expect(pickerAt(tester, 'Chaco').value?['name'], 'Chaco Loma UX');
  });

  testWidgets('(f) Aplicación: «Crear chaco» con la persona elegida como '
      'dueña; los productos no ofrecen altas', (tester) async {
    bigSurface(tester);
    final s = await activatedHousehold(tester, 'ux-f');
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).push('/aplicaciones/nueva');
    await waitFor(tester, picker('Persona'));
    await settle(tester);
    await choose(tester, 'Persona', 'Hermana');

    await openCreate(tester, 'Chaco', 'Crear chaco');
    expect(find.text('Propietario: Hermana'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<int>), findsNothing);
    await tester.enterText(field('Nombre'), 'Chaco Bajo UX');
    await tester.enterText(field('Superficie (ha)'), '1');
    await save(
      tester,
      'el alta del chaco',
      () => pickerAt(tester, 'Chaco').value?['name'] == 'Chaco Bajo UX',
    );

    expect(pickerAt(tester, 'Chaco').value?['name'], 'Chaco Bajo UX');
    expect(pickerAt(tester, 'Persona').value?['name'], 'Hermana');
    final farms = await rows(tester, s.database, 'farms');
    final created = farms.singleWhere((f) => f['name'] == 'Chaco Bajo UX');
    expect(created['owner_person_id'], s.household.relative);

    await tester.tap(find.byKey(const Key('application-continue')));
    await settle(tester);
    for (final p in tester.widgetList<AdaptiveEntityPicker<Row>>(
      find.byType(AdaptiveEntityPicker<Row>),
    )) {
      expect(p.createLabel, isNull, reason: p.label);
    }
  });

  testWidgets('(g) Operaciones: Campañas con la actual y Reportes; Más no '
      'repite Reportes; Campañas sin «+»', (tester) async {
    bigSurface(tester);
    final s = await activatedHousehold(tester, 'ux-g');
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).go('/operaciones');
    await settle(tester);

    expect(find.text('Campañas'), findsOneWidget);
    expect(find.text('Actual: Campaña 1'), findsOneWidget);
    expect(find.text('Reportes'), findsOneWidget);

    await tester.tap(find.text('Más'));
    await settle(tester);
    expect(find.text('Reportes'), findsNothing);
    await tester.tap(find.byTooltip('Volver'));
    await settle(tester);

    await tester.tap(find.text('Campañas'));
    await settle(tester);
    expect(find.byKey(const Key('campaigns-current')), findsOneWidget);
    expect(find.text('Campaña 1'), findsOneWidget);
    expect(find.byTooltip('Registrar operación'), findsNothing);
    expect(find.byKey(const Key('campaigns-add')), findsOneWidget);
  });

  testWidgets('(h) el «+» abre el formulario de aplicación', (tester) async {
    bigSurface(tester);
    final s = await activatedHousehold(tester, 'ux-h');
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).go('/operaciones');
    await settle(tester);

    await tester.tap(find.byTooltip('Registrar operación'));
    await settle(tester);
    await tester.tap(find.text('Aplicación'));
    await settle(tester);
    expect(find.text('Nueva aplicación'), findsOneWidget);
  });
}
