// Pilotos X01 y X02 (2026-10-25/26): en la compra, las existencias quedaron a
// nombre de «Familiar Demo» y en X02 faltó el segundo producto. Causas en el
// código (revisión del 2026-10-26, B-08, B-21, B-07, B-11, E-14, E-16): el
// último producto entraba solo en la última línea; el reparto obligaba a
// elegir persona y reteclear la cantidad; la autoselección del proveedor
// marcaba el formulario como cambiado; un número mal escrito se leía como 0.
//
// Recorridos sobre la app completa (arnés de F04, base en archivo,
// repositorio real), en modalidad compartida salvo (e):
//   (a) ninguna línea incorpora un producto por quedar como única opción;
//   (b) «Toda para una persona» + Titular: cabecera «Para: Titular» sin
//       teclear cantidad; `confirmPurchase` recibe la asignación completa;
//   (c) «Repartir entre varias»: 1 L + 1 L sobre 2 L se acepta;
//       1 L + 0,5 L y 1 L + 1,5 L se rechazan con mensaje;
//   (d) sin destinatario no se puede continuar y el mensaje nombra el
//       producto;
//   (e) en propio no se pregunta;
//   (f) Atrás con sólo el proveedor autoseleccionado cierra sin diálogo;
//   (g) «1.5» y «1,500» en «Cantidad comprada» dejan el mensaje de formato
//       en el campo y el aviso nombra el producto.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/domain/money.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/presentation/screens/purchase_form_screen.dart';
import 'package:agroquimicos/presentation/widgets/adaptive_entity_picker.dart';
import 'package:agroquimicos/presentation/widgets/agro_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  /// Elige en el selector [label] (el [position]-ésimo si hay varios) la
  /// opción cuyo nombre es [name], como al tocarla en la hoja.
  Future<void> choose(
    WidgetTester tester,
    String label,
    String name, {
    int position = 0,
  }) async {
    final widget = tester
        .widgetList<AdaptiveEntityPicker<Row>>(picker(label))
        .elementAt(position);
    widget.onChanged(
      widget.items.firstWhere((item) => widget.labelOf(item) == name),
    );
    await settle(tester);
  }

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );

  Future<void> tapKey(WidgetTester tester, String key) async {
    await preparePurchaseKey(tester, key);
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.pump();
    await tester.tap(find.byKey(Key(key)));
    await settle(tester);
  }

  Future<List<Row>> rows(WidgetTester tester, db, String table) async =>
      (await tester.runAsync(
        () async => (await db.database).query(table, orderBy: 'id'),
      ))!;

  Future<void> openForm(WidgetTester tester, ProviderContainer c) async {
    c.read(routerProvider).push('/compras/nueva');
    await waitFor(tester, find.byKey(const Key('purchase-add-line')));
    await settle(tester);
  }

  /// Lo que dice la tarjeta del producto [index] en el paso 1 (también con
  /// su hoja abierta encima).
  String lineStatus(WidgetTester tester, [int index = 0]) =>
      tester
          .widget<ItemCard>(
            find.byKey(Key('purchase-line-$index'), skipOffstage: false),
          )
          .subtitle ??
      '';

  /// Una línea de la revisión como antes: «producto · cantidad · subtotal ·
  /// destinatario».
  String reviewLine(WidgetTester tester, [int index = 0]) {
    String t(String key) => tester.widget<Text>(find.byKey(Key(key))).data!;
    return '${t('purchase-review-line-$index')} · '
        '${t('purchase-review-subtotal-$index')} · '
        '${t('purchase-review-recipient-$index')}';
  }

  /// Proveedor, Glifosato, 2 L a 45 Bs/L; el destinatario queda por decidir.
  Future<void> fillLine(WidgetTester tester) async {
    await choose(tester, 'Proveedor', 'Proveedor');
    await openPurchaseLine(tester);
    await choose(tester, 'Producto', 'Glifosato');
    await tester.enterText(field('Cantidad comprada'), '2');
    await tester.enterText(field('Precio por L'), '45');
    await settle(tester);
  }

  bool inStep1() =>
      find.text('¿Qué compró?', skipOffstage: false).evaluate().isNotEmpty;

  /// Deja que el aviso en pantalla expire y desaparezca: los `SnackBar` se
  /// encolan, y el siguiente mensaje no se vería mientras dure el anterior.
  Future<void> hideSnackBar(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  }

  testWidgets('(a) con dos productos, elegir A en la línea 1 y agregar otra '
      'línea no rellena la línea 2 con B', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, 'dest-a');
    await tester.runAsync(() => s.household.repo.addProduct(name: 'Bellator'));
    final c = await pumpModeApp(tester, s.database);
    await openForm(tester, c);

    await openPurchaseLine(tester);
    await choose(tester, 'Producto', 'Glifosato');
    // «Añadir otro» crea la línea 2 y abre su hoja.
    await tapKey(tester, 'purchase-line-next');

    expect(find.byKey(const Key('purchase-line-sheet-1')), findsOneWidget);
    // La línea 2 sigue sin producto aunque Bellator sea la única opción.
    final second = tester
        .widgetList<AdaptiveEntityPicker<Row>>(picker('Producto'))
        .last;
    expect(second.value, isNull);
    expect([for (final p in second.items) p['name']], ['Bellator']);
    expect(second.autoSelectSingle, isFalse);
  });

  testWidgets('(a2) con un solo producto en el catálogo la línea tampoco se '
      'rellena sola', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, 'dest-a2');
    final c = await pumpModeApp(tester, s.database);
    await openForm(tester, c);
    await openPurchaseLine(tester);
    expect(
      tester.widget<AdaptiveEntityPicker<Row>>(picker('Producto')).value,
      isNull,
    );
  });

  testWidgets('(b) «Toda para una persona» + Titular: «Para: Titular» sin '
      'teclear la cantidad; el resumen lo muestra y la asignación completa '
      'llega al repositorio', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, 'dest-b');
    final c = await pumpModeApp(tester, s.database);
    await openForm(tester, c);
    await fillLine(tester);

    // Ninguna opción marcada; sin selector de persona todavía.
    expect(lineStatus(tester), contains('Pendiente de destinatario'));
    expect(picker('Persona'), findsNothing);
    expect(segmentSelected(tester, 'purchase-alloc-single-0'), isFalse);
    expect(segmentSelected(tester, 'purchase-alloc-split-0'), isFalse);

    await tapKey(tester, 'purchase-alloc-single-0');
    // El selector no se rellena solo y el titular se rotula «Titular».
    final person = tester.widget<AdaptiveEntityPicker<Row>>(picker('Persona'));
    expect(person.value, isNull);
    expect(person.autoSelectSingle, isFalse);
    final titular = person.items.firstWhere((p) => p['name'] == 'Titular');
    final hermana = person.items.firstWhere((p) => p['name'] == 'Hermana');
    final vecino = person.items.firstWhere((p) => p['name'] == 'Vecino');
    expect(person.secondaryOf!(titular), 'Titular');
    expect(person.secondaryOf!(hermana), 'Familiar');
    expect(person.secondaryOf!(vecino), 'Tercero');
    expect(lineStatus(tester), contains('Pendiente de destinatario'));

    await choose(tester, 'Persona', 'Titular');
    expect(lineStatus(tester), contains('Para: Titular'));
    expect(find.text('Recibe toda la cantidad: 2 L'), findsOneWidget);
    // No hay cantidad que reteclear.
    expect(field('Cantidad'), findsNothing);

    // Si cambia la cantidad comprada, la asignación la sigue.
    await tester.enterText(field('Cantidad comprada'), '3');
    await settle(tester);
    expect(find.text('Recibe toda la cantidad: 3 L'), findsOneWidget);

    await tapKey(tester, 'purchase-continue');
    expect(inStep1(), isFalse);
    expect(
      reviewLine(tester),
      'Glifosato · 3 L · ${formatBob(13500)} · Para: Titular',
    );
    await tester.tap(find.byKey(const Key('purchase-paid-yes')));
    await settle(tester);
    expect(find.text('Paga el titular: Titular'), findsOneWidget);
    expect(find.textContaining('Pago registrado por'), findsNothing);

    await tapKey(tester, 'purchase-confirm');
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    final allocations = await rows(tester, s.database, 'purchase_allocations');
    expect(allocations, hasLength(1));
    expect(allocations.single['person_id'], s.household.titular);
    expect(allocations.single['quantity_base'], 3000);
    final payments = await rows(tester, s.database, 'provider_payments');
    expect(payments.single['payer_person_id'], s.household.titular);
    expect(payments.single['amount_bob_minor'], 13500);
  });

  testWidgets('(c) «Repartir entre varias»: 1 L + 1 L sobre 2 L se acepta; '
      '1 L + 0,5 L y 1 L + 1,5 L se rechazan con mensaje', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, 'dest-c');
    final c = await pumpModeApp(tester, s.database);
    await openForm(tester, c);
    await fillLine(tester);

    await tapKey(tester, 'purchase-alloc-split-0');
    // Dos filas vacías: ninguna persona prellenada.
    expect(picker('Persona'), findsNWidgets(2));
    expect(field('Cantidad'), findsNWidgets(2));
    for (final p in tester.widgetList<AdaptiveEntityPicker<Row>>(
      picker('Persona'),
    )) {
      expect(p.value, isNull);
      expect(p.autoSelectSingle, isFalse);
    }
    expect(lineStatus(tester), isNot(contains('Pendiente de cantidad')));
    expect(lineStatus(tester), contains('Pendiente de persona'));

    await choose(tester, 'Persona', 'Titular');
    await choose(tester, 'Persona', 'Hermana', position: 1);
    await tester.enterText(field('Cantidad').at(0), '1');
    await tester.enterText(field('Cantidad').at(1), '0,5');
    await settle(tester);
    expect(lineStatus(tester), contains('Pendiente 0,5 L'));
    await tapKey(tester, 'purchase-continue');
    expect(
      find.text('Falta repartir parte de la cantidad de Glifosato.'),
      findsOneWidget,
    );
    expect(inStep1(), isTrue);
    await hideSnackBar(tester);

    await tester.enterText(field('Cantidad').at(1), '1,5');
    await settle(tester);
    expect(lineStatus(tester), contains('Excede en 0,5 L'));
    await tapKey(tester, 'purchase-continue');
    expect(
      find.text('Lo repartido supera la cantidad comprada de Glifosato.'),
      findsOneWidget,
    );
    expect(inStep1(), isTrue);
    await hideSnackBar(tester);

    // La misma persona en dos filas se rechaza aunque las partes sumen.
    await tester.enterText(field('Cantidad').at(1), '1');
    await choose(tester, 'Persona', 'Titular', position: 1);
    await tapKey(tester, 'purchase-continue');
    expect(
      find.text(
        'La misma persona aparece dos veces en el reparto de Glifosato.',
      ),
      findsOneWidget,
    );
    expect(inStep1(), isTrue);
    await hideSnackBar(tester);

    await choose(tester, 'Persona', 'Hermana', position: 1);
    expect(
      lineStatus(tester),
      contains('Repartida: Titular 1 L · Hermana 1 L'),
    );
    await tapKey(tester, 'purchase-continue');
    expect(inStep1(), isFalse);
    expect(
      reviewLine(tester),
      'Glifosato · 2 L · ${formatBob(9000)} · '
      'Repartida: Titular 1 L · Hermana 1 L',
    );
    await tester.tap(find.byKey(const Key('purchase-paid-no')));
    await settle(tester);
    await tapKey(tester, 'purchase-confirm');
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    final allocations = await rows(tester, s.database, 'purchase_allocations');
    expect(
      [for (final a in allocations) (a['person_id'], a['quantity_base'])],
      [(s.household.titular, 1000), (s.household.relative, 1000)],
    );
  });

  testWidgets('(d) sin destinatario no se continúa y el mensaje nombra el '
      'producto; con la opción elegida pero sin persona, también', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, 'dest-d');
    final c = await pumpModeApp(tester, s.database);
    await openForm(tester, c);
    await fillLine(tester);

    await tapKey(tester, 'purchase-continue');
    expect(
      find.text(
        'Indique para quién es Glifosato: toda para una persona o repartida '
        'entre varias.',
      ),
      findsOneWidget,
    );
    expect(inStep1(), isTrue);
    await hideSnackBar(tester);

    await tapKey(tester, 'purchase-alloc-single-0');
    await tapKey(tester, 'purchase-continue');
    expect(find.text('Elija para quién es Glifosato.'), findsOneWidget);
    expect(inStep1(), isTrue);
    expect(await rows(tester, s.database, 'purchases'), isEmpty);
  });

  testWidgets('(h) cambiar de opción limpia la anterior en ambos sentidos; '
      'volver a tocar la opción activa no borra nada', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, 'dest-h');
    final c = await pumpModeApp(tester, s.database);
    await openForm(tester, c);
    await fillLine(tester);

    // Una persona → Titular; re-tocar la opción activa conserva la elección.
    await tapKey(tester, 'purchase-alloc-single-0');
    await choose(tester, 'Persona', 'Titular');
    expect(lineStatus(tester), contains('Para: Titular'));
    await tapKey(tester, 'purchase-alloc-single-0');
    expect(lineStatus(tester), contains('Para: Titular'));
    expect(
      tester.widget<AdaptiveEntityPicker<Row>>(picker('Persona')).value,
      isNotNull,
    );

    // Pasar a «Repartir»: la persona única no se arrastra a ninguna fila.
    await tapKey(tester, 'purchase-alloc-split-0');
    expect(picker('Persona'), findsNWidgets(2));
    for (final p in tester.widgetList<AdaptiveEntityPicker<Row>>(
      picker('Persona'),
    )) {
      expect(p.value, isNull);
    }
    expect(lineStatus(tester), isNot(contains('Para: Titular')));
    expect(lineStatus(tester), contains('Pendiente de persona'));
    expect(tester.takeException(), isNull);

    // Rellenar el reparto; re-tocar «Repartir» conserva las filas.
    await choose(tester, 'Persona', 'Hermana');
    await choose(tester, 'Persona', 'Vecino', position: 1);
    await tester.enterText(field('Cantidad').at(0), '1');
    await tester.enterText(field('Cantidad').at(1), '1');
    await settle(tester);
    expect(lineStatus(tester), contains('Repartida: Hermana 1 L · Vecino 1 L'));
    await tapKey(tester, 'purchase-alloc-split-0');
    expect(lineStatus(tester), contains('Repartida: Hermana 1 L · Vecino 1 L'));
    expect(picker('Persona'), findsNWidgets(2));

    // Volver a «Toda para una persona»: sin persona ni filas heredadas.
    await tapKey(tester, 'purchase-alloc-single-0');
    expect(picker('Persona'), findsOneWidget);
    expect(
      tester.widget<AdaptiveEntityPicker<Row>>(picker('Persona')).value,
      isNull,
    );
    expect(field('Cantidad'), findsNothing);
    expect(lineStatus(tester), contains('Pendiente de destinatario'));
    expect(lineStatus(tester), isNot(contains('Repartida:')));
    expect(tester.takeException(), isNull);

    // Y al volver a «Repartir», dos filas nuevas vacías (no las anteriores).
    await tapKey(tester, 'purchase-alloc-split-0');
    expect(picker('Persona'), findsNWidgets(2));
    for (final p in tester.widgetList<AdaptiveEntityPicker<Row>>(
      picker('Persona'),
    )) {
      expect(p.value, isNull);
    }
    for (final f in tester.widgetList<TextField>(field('Cantidad'))) {
      expect(f.controller!.text, isEmpty);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('(e) en propio no se pregunta: todo al titular', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, 'dest-e');
    await tester.runAsync(
      () =>
          OperationModeStore(s.database)
              .apply(OperationMode.personal, confirmed: true),
    );
    final c = await pumpModeApp(tester, s.database);
    await openForm(tester, c);
    await openPurchaseLine(tester);
    expect(find.text('¿Para quién es?'), findsNothing);
    expect(find.text('Una persona'), findsNothing);
    expect(find.text('Repartir entre varias'), findsNothing);
    expect(picker('Persona'), findsNothing);
    // Rediseño individual (lámina I-11): la hoja no repite el titular.
    expect(find.textContaining('Para el titular'), findsNothing);
    // Con el producto elegido, la tarjeta dice lo que falta: la cantidad,
    // nunca el destinatario.
    await choose(tester, 'Producto', 'Glifosato');
    expect(lineStatus(tester), isNot(contains('Pendiente de destinatario')));
    expect(lineStatus(tester), contains('Pendiente de cantidad'));
  });

  testWidgets('(f) Atrás con sólo el proveedor autoseleccionado cierra sin '
      '«¿Descartar cambios?»', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, 'dest-f');
    final c = await pumpModeApp(tester, s.database);
    await openForm(tester, c);
    // El único proveedor quedó elegido como valor de referencia.
    expect(
      tester.widget<AdaptiveEntityPicker<Row>>(picker('Proveedor')).value,
      isNotNull,
    );
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();
    await settle(tester);
    // Un fotograma más: el `Navigator` retira la ruta al terminar la salida.
    await tester.pump();
    expect(find.text('¿Descartar cambios?'), findsNothing);
    expect(find.byType(PurchaseFormScreen), findsNothing);
  });

  testWidgets('(g) «1.5» y «1,500» en la cantidad: mensaje de formato en el '
      'campo y aviso con el nombre del producto', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, 'dest-g');
    final c = await pumpModeApp(tester, s.database);
    await openForm(tester, c);
    await openPurchaseLine(tester);
    await choose(tester, 'Producto', 'Glifosato');
    await tester.enterText(field('Precio por L'), '45');
    await tapKey(tester, 'purchase-alloc-single-0');
    await choose(tester, 'Persona', 'Titular');

    await tester.enterText(field('Cantidad comprada'), '1.5');
    await settle(tester);
    await tapKey(tester, 'purchase-continue');
    expect(
      find.text('Revise la cantidad comprada de Glifosato.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(field('Cantidad comprada'))
          .decoration
          ?.errorText,
      startsWith('Escriba el número como 1.500,25'),
    );
    expect(inStep1(), isTrue);

    await tester.enterText(field('Cantidad comprada'), '1,500');
    await settle(tester);
    // Editar el campo borra el error anterior.
    expect(
      tester
          .widget<TextField>(field('Cantidad comprada'))
          .decoration
          ?.errorText,
      isNull,
    );
    await tapKey(tester, 'purchase-continue');
    expect(
      tester
          .widget<TextField>(field('Cantidad comprada'))
          .decoration
          ?.errorText,
      startsWith('"1,500" es ambiguo'),
    );
    expect(inStep1(), isTrue);

    await tester.enterText(field('Cantidad comprada'), '1,5');
    await settle(tester);
    await tapKey(tester, 'purchase-continue');
    expect(inStep1(), isFalse);
    expect(
      reviewLine(tester),
      'Glifosato · 1,5 L · ${formatBob(6750)} · Para: Titular',
    );
  });
}
