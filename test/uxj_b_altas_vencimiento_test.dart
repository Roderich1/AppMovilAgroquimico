// Bloque B de la mejora para la demostración (2026-11-05): altas dentro del
// formulario, revisiones de compra y aplicación, y aviso de lote vencido.
//
// Recorridos sobre la app completa (arnés de F04, base en archivo,
// repositorio real), en modalidad compartida, salvo las pruebas de
// repositorio del final:
//   Compra
//   (c1) catálogo vacío: sin proveedores ni productos se crean ambos desde el
//        selector y quedan elegidos;
//   (c2) con un proveedor ya elegido, crear otro deja elegido el nuevo;
//   (c3) cancelar «Crear producto» no cambia la línea ni escribe nada;
//   (c4) «Agregar persona» en «Toda para una persona» la deja elegida y
//        conserva el borrador; en «Repartir entre varias», en su fila;
//   (c5) «Añadir otro producto» agrega una línea y no se confunde con
//        «Crear producto»;
//   (c6) revisión: el total una sola vez y «¿Ya pagaste al proveedor?»;
//   Aplicación
//   (a1) «Agregar persona» sólo con tipos que pueden aplicar; la persona
//        queda elegida y, sin existencias, se dice por qué y se ofrece
//        «Registrar compra»;
//   (a2) «Registrar compra» abre la compra encima y, al volver, conserva el
//        borrador y refresca las existencias;
//   (a3) costo estimado con ayuda breve y cargo; lote vencido avisado;
//   (a4) lote que vence el día de la aplicación: «Vence hoy», no vencido;
//   Planificación
//   (p1) se planifica un producto sin existencias (no hay regla que lo
//        impida) y el plan dice cuánto comprar;
//   Repositorio
//   (r1) la previsión es la misma asignación FIFO que la escritura y sólo
//        avisa si el lote vencido se va a usar;
//   (r2) aplicación histórica: se compara con su fecha efectiva, no con hoy.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/domain/campaign_calendar.dart';
import 'package:agroquimicos/domain/inventory_alerts.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/money.dart';
import 'package:agroquimicos/presentation/widgets/adaptive_entity_picker.dart';
import 'package:agroquimicos/presentation/widgets/agro_ui.dart'
    show DashedAddButton;
import 'package:agroquimicos/presentation/widgets/application_expiry_notice.dart';
import 'package:agroquimicos/presentation/screens/application_form_screen.dart'
    show applicationPersonLabel;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';
import 'support/f04_mode_ui_harness.dart';
import 'support/purchase_form_driver.dart';

typedef Row = Map<String, Object?>;

void main() {
  sqfliteFfiInit();

  Finder picker(String label) => find.byWidgetPredicate(
    (w) => w is AdaptiveEntityPicker<Row> && w.label == label,
    // Rediseño: con la hoja de un producto abierta, el proveedor sigue en
    // la página, fuera de escena.
    skipOffstage: false,
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

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.pump();
    await tester.tap(find.byKey(Key(key)));
    await settle(tester);
  }

  /// Abre la hoja del selector [label] y toca su fila «[createLabel]».
  Future<void> openCreate(
    WidgetTester tester,
    String label,
    String createLabel, {
    int position = 0,
  }) async {
    // Rediseño: el proveedor está en la página; producto y persona, en la
    // hoja del producto.
    if (label == 'Proveedor') {
      await closePurchaseLine(tester);
    } else if ((label == 'Producto' || label == 'Persona') &&
        !purchaseLineSheetOpen()) {
      await openPurchaseLine(tester);
    }
    final target = picker(label).at(position);
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.tap(target);
    await settle(tester);
    expect(find.byKey(const Key('picker-create')), findsOneWidget);
    await tester.tap(find.text(createLabel));
    await settle(tester);
  }

  Future<void> save(
    WidgetTester tester,
    String what,
    bool Function() done,
  ) async {
    await tester.tap(find.text('Guardar'));
    await waitUntil(tester, what, done);
    await settle(tester);
  }

  Future<List<Row>> rows(WidgetTester tester, db, String table) async =>
      (await tester.runAsync(
        () async => (await db.database).query(table, orderBy: 'id'),
      ))!;

  void bigSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> openPurchase(WidgetTester tester, ProviderContainer c) async {
    c.read(routerProvider).push('/compras/nueva');
    await waitFor(tester, find.byKey(const Key('purchase-add-line')));
    await settle(tester);
  }

  /// Proveedor y Glifosato, 2 L a 45 Bs/L, en la línea 1.
  Future<void> fillLineOne(WidgetTester tester) async {
    await choose(tester, 'Proveedor', 'Proveedor');
    await openPurchaseLine(tester);
    await choose(tester, 'Producto', 'Glifosato');
    await openPurchaseLine(tester);
    await tester.enterText(field('Cantidad comprada'), '2');
    await openPurchaseLine(tester);
    await tester.enterText(field('Precio por L'), '45');
    await settle(tester);
  }

  Future<void> expectLineOneKept(WidgetTester tester) async {
    if (find.byKey(const Key('purchase-line-sheet-0')).evaluate().isEmpty) {
      await openPurchaseLine(tester);
    }
    expect(pickerAt(tester, 'Producto').value?['name'], 'Glifosato');
    expect(fieldText(tester, 'Cantidad comprada'), '2');
    expect(fieldText(tester, 'Precio por L'), '45');
    expect(find.textContaining('Hoy, ', skipOffstage: false), findsOneWidget);
  }

  /// Compra con vencimiento: [quantity] de [product] para [person].
  Future<void> buy(
    Household h, {
    required int person,
    required int product,
    required int quantity,
    DateTime? date,
    String? expiryDay,
    String? lotNumber,
  }) => h.repo.confirmPurchase(
    PurchaseDraft(
      supplierId: h.supplier,
      campaignId: h.campaign,
      purchaseDate: date ?? DateTime.utc(2026, 1, 2, 12),
      items: [
        PurchaseItemDraft(
          productId: product,
          quantityBase: quantity,
          currency: CurrencyCode.bob,
          originalUnitPriceMinor: 10000,
          allocations: [
            AllocationDraft(personId: person, quantityBase: quantity),
          ],
          expiryDay: expiryDay,
          lotNumber: lotNumber,
        ),
      ],
    ),
  );

  String dayOffset(int days) {
    final now = DateTime.now();
    return localDay(DateTime(now.year, now.month, now.day + days, 12));
  }

  // ------------------------------------------------------------------ Compra

  testWidgets('(c1) catálogo vacío: proveedor y producto se crean desde el '
      'selector y quedan elegidos', (tester) async {
    bigSurface(tester);
    final s = await activatedHousehold(tester, 'uxjb-c1');
    await tester.runAsync(() async {
      await s.household.repo.archiveCatalog('suppliers', s.household.supplier);
      await s.household.repo.archiveCatalog('products', s.household.product);
    });
    final c = await pumpModeApp(tester, s.database);
    await openPurchase(tester, c);

    expect(pickerAt(tester, 'Proveedor').items, isEmpty);
    await openPurchaseLine(tester);
    expect(pickerAt(tester, 'Producto').items, isEmpty);
    await tester.enterText(field('Cantidad comprada'), '3');
    await settle(tester);

    await openCreate(tester, 'Proveedor', 'Crear proveedor');
    await tester.enterText(field('Nombre del proveedor'), 'Agro Nuevo');
    await save(
      tester,
      'el alta del proveedor',
      () => pickerAt(tester, 'Proveedor').value?['name'] == 'Agro Nuevo',
    );

    await openCreate(tester, 'Producto', 'Crear producto');
    await tester.enterText(field('Producto'), 'Mancozeb');
    await save(
      tester,
      'el alta del producto',
      () => pickerAt(tester, 'Producto').value?['name'] == 'Mancozeb',
    );

    expect(pickerAt(tester, 'Proveedor').value?['name'], 'Agro Nuevo');
    expect(pickerAt(tester, 'Producto').value?['name'], 'Mancozeb');
    expect(fieldText(tester, 'Cantidad comprada'), '3');
    expect(find.text('¿Qué compró?', skipOffstage: false), findsOneWidget);
  });

  testWidgets('(c2) con un proveedor elegido, crear otro deja elegido el '
      'nuevo', (tester) async {
    bigSurface(tester);
    final s = await activatedHousehold(tester, 'uxjb-c2');
    final c = await pumpModeApp(tester, s.database);
    await openPurchase(tester, c);
    await fillLineOne(tester);
    expect(pickerAt(tester, 'Proveedor').value?['name'], 'Proveedor');

    await openCreate(tester, 'Proveedor', 'Crear proveedor');
    await tester.enterText(field('Nombre del proveedor'), 'Agro Sur');
    await save(
      tester,
      'el alta del proveedor alternativo',
      () => pickerAt(tester, 'Proveedor').value?['name'] == 'Agro Sur',
    );

    expect(pickerAt(tester, 'Proveedor').value?['name'], 'Agro Sur');
    expect([
      for (final row in pickerAt(tester, 'Proveedor').items) row['name'],
    ], containsAll(['Agro Sur', 'Proveedor']));
    await expectLineOneKept(tester);
    // Unos fotogramas más: la autoselección del único proveedor anterior no
    // vuelve a pisar lo creado.
    await settle(tester);
    expect(pickerAt(tester, 'Proveedor').value?['name'], 'Agro Sur');
  });

  testWidgets('(c3) cancelar «Crear producto» no cambia la línea ni escribe '
      'nada', (tester) async {
    bigSurface(tester);
    final s = await activatedHousehold(tester, 'uxjb-c3');
    final c = await pumpModeApp(tester, s.database);
    await openPurchase(tester, c);
    await fillLineOne(tester);
    final before = await rows(tester, s.database, 'products');

    await openCreate(tester, 'Producto', 'Crear producto');
    await tester.enterText(field('Producto'), 'No se guarda');
    await tester.tap(find.text('Cancelar'));
    await settle(tester);

    expect(find.text('Nuevo producto'), findsNothing);
    await expectLineOneKept(tester);
    expect(pickerAt(tester, 'Proveedor').value?['name'], 'Proveedor');
    expect(
      await rows(tester, s.database, 'products'),
      hasLength(before.length),
    );
  });

  testWidgets('(c4) «Agregar persona» en el reparto queda elegida y conserva '
      'el borrador', (tester) async {
    bigSurface(tester);
    final s = await activatedHousehold(tester, 'uxjb-c4');
    final c = await pumpModeApp(tester, s.database);
    await openPurchase(tester, c);
    await fillLineOne(tester);
    await tapKey(tester, 'purchase-alloc-single-0');

    await openCreate(tester, 'Persona', 'Agregar persona');
    expect(find.text('Nueva persona'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('person-name')), 'Primo');
    await save(
      tester,
      'el alta de la persona',
      () => pickerAt(tester, 'Persona').value?['name'] == 'Primo',
    );

    expect(pickerAt(tester, 'Persona').value?['name'], 'Primo');
    expect(find.byKey(const Key('purchase-alloc-derived-0')), findsOneWidget);
    await expectLineOneKept(tester);
    expect(pickerAt(tester, 'Proveedor').value?['name'], 'Proveedor');
    final people = await rows(tester, s.database, 'persons');
    expect(
      people.singleWhere((p) => p['name'] == 'Primo')['role'],
      PersonRole.family.code,
    );

    // En «Repartir entre varias», lo creado queda en la fila que lo pidió.
    await tapKey(tester, 'purchase-alloc-split-0');
    await openCreate(tester, 'Persona', 'Agregar persona', position: 1);
    await tester.enterText(find.byKey(const Key('person-name')), 'Tío');
    await save(
      tester,
      'el alta de la persona en el reparto',
      () => pickerAt(tester, 'Persona', 1).value?['name'] == 'Tío',
    );
    expect(pickerAt(tester, 'Persona', 0).value, isNull);
    expect(pickerAt(tester, 'Persona', 1).value?['name'], 'Tío');
    await expectLineOneKept(tester);
  });

  testWidgets('(c5) «Añadir otro producto» agrega una línea; «Crear producto» '
      'es otra acción', (tester) async {
    bigSurface(tester);
    final s = await activatedHousehold(tester, 'uxjb-c5');
    final c = await pumpModeApp(tester, s.database);
    await openPurchase(tester, c);

    // Rediseño: con la línea vacía la acción dice «Añadir producto» y abre
    // su hoja; dentro, «Añadir otro» agrega la línea 2. «Crear producto» es
    // la fila del selector, otra acción.
    expect(find.text('Agregar producto'), findsNothing);
    expect(find.text('Añadir producto'), findsOneWidget);
    await tapKey(tester, 'purchase-add-line');
    expect(pickerAt(tester, 'Producto').createLabel, 'Crear producto');
    await tapKey(tester, 'purchase-line-next');
    expect(find.byKey(const Key('purchase-line-sheet-1')), findsOneWidget);
    expect(pickerAt(tester, 'Producto').createLabel, 'Crear producto');
    await closePurchaseLine(tester);
    expect(find.text('Añadir otro producto'), findsOneWidget);
  });

  testWidgets('(c6) revisión: el total una sola vez y «¿Ya pagaste al '
      'proveedor?»', (tester) async {
    bigSurface(tester);
    final s = await activatedHousehold(tester, 'uxjb-c6');
    final c = await pumpModeApp(tester, s.database);
    await openPurchase(tester, c);
    await fillLineOne(tester);
    await tapKey(tester, 'purchase-alloc-single-0');
    await choose(tester, 'Persona', 'Hermana');
    await closePurchaseLine(tester);
    await tapKey(tester, 'purchase-continue');

    expect(find.text('Revise y confirme'), findsOneWidget);
    // El importe: el subtotal de la única línea y el total, ambos en el
    // resumen; la pregunta del pago no lo repite.
    expect(
      tester.widget<Text>(find.byKey(const Key('purchase-total'))).data,
      formatBob(9000),
    );
    expect(find.text(formatBob(9000)), findsNWidgets(2));
    expect(
      find.descendant(
        of: find.byKey(const Key('purchase-paid-choice')),
        matching: find.textContaining(formatBob(9000)),
      ),
      findsNothing,
    );
    expect(find.textContaining('Importe'), findsNothing);
    expect(find.text('¿Ya pagó al proveedor?'), findsOneWidget);
    expect(find.text('¿Pagaste toda esta compra?'), findsNothing);
    // El reparto sigue a la vista para revisar.
    expect(
      tester
          .widget<Text>(find.byKey(const Key('purchase-review-recipient-0')))
          .data,
      contains('Para: Hermana'),
    );

    await tapKey(tester, 'purchase-confirm');
    expect(find.text('Indique si ya pagó al proveedor.'), findsOneWidget);
    expect(await rows(tester, s.database, 'purchases'), isEmpty);
  });

  // -------------------------------------------------------------- Aplicación

  testWidgets('(a1) «Agregar persona» sólo con tipos que aplican; sin '
      'existencias se dice por qué', (tester) async {
    bigSurface(tester);
    final s = await activatedHousehold(tester, 'uxjb-a1');
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).push('/aplicaciones/nueva');
    await waitFor(tester, picker(applicationPersonLabel));
    await settle(tester);

    await openCreate(tester, applicationPersonLabel, 'Agregar persona');
    await tester.tap(find.byType(DropdownButtonFormField<PersonRole>));
    await settle(tester);
    // Una persona nueva no es el titular: «Administrador» no podría aplicar.
    expect(find.text('Administrador'), findsNothing);
    expect(find.text('Tercero · cobro por asignación'), findsWidgets);
    await tester.tap(find.text('Tercero · cobro por asignación').last);
    await settle(tester);
    await tester.enterText(find.byKey(const Key('person-name')), 'Peón');
    await save(
      tester,
      'el alta de la persona',
      () => pickerAt(tester, applicationPersonLabel).value?['name'] == 'Peón',
    );
    expect(pickerAt(tester, applicationPersonLabel).value?['name'], 'Peón');
    final people = await rows(tester, s.database, 'persons');
    expect(
      people.singleWhere((p) => p['name'] == 'Peón')['role'],
      PersonRole.thirdParty.code,
    );

    await openCreate(tester, 'Chaco', 'Crear chaco');
    expect(find.text('Propietario: Peón'), findsOneWidget);
    await tester.enterText(field('Nombre'), 'Chaco peón');
    await tester.enterText(field('Superficie (ha)'), '1');
    await save(
      tester,
      'el alta del chaco',
      () => pickerAt(tester, 'Chaco').value?['name'] == 'Chaco peón',
    );
    await tapKey(tester, 'application-continue');

    expect(find.text('¿Qué aplicó?'), findsOneWidget);
    final reason = tester.widget<Text>(
      find.byKey(const Key('application-without-stock')),
    );
    expect(reason.data, contains('Sin existencias de Peón: Glifosato'));
    expect(
      find.byKey(const Key('application-register-purchase')),
      findsOneWidget,
    );
  });

  testWidgets('(a2) «Registrar compra» vuelve a la aplicación con el '
      'borrador entero y las existencias al día', (tester) async {
    bigSurface(tester);
    final s = await activatedHousehold(tester, 'uxjb-a2');
    final h = s.household;
    await tester.runAsync(() async {
      await h.repo.addProduct(name: 'Mancozeb');
      await buy(h, person: h.relative, product: h.product, quantity: 2000);
    });
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).push('/aplicaciones/nueva');
    await waitFor(tester, picker(applicationPersonLabel));
    await settle(tester);
    await choose(tester, applicationPersonLabel, 'Hermana');
    await choose(tester, 'Chaco', 'Chaco hermana');
    await tester.enterText(find.byKey(const Key('application-area')), '0,4');
    await settle(tester);
    await tapKey(tester, 'application-continue');

    await tapKey(tester, 'application-add-product');
    await openPurchaseLine(tester);
    await choose(tester, 'Producto', 'Glifosato');
    await tester.enterText(
      find.byKey(const Key('application-line-quantity')),
      '1',
    );
    await tapKey(tester, 'application-line-add');
    expect(
      tester
          .widget<Text>(find.byKey(const Key('application-without-stock')))
          .data,
      contains('Sin existencias de Hermana: Mancozeb'),
    );

    await tapKey(tester, 'application-register-purchase');
    await waitFor(tester, find.byKey(const Key('purchase-add-line')));
    await settle(tester);
    expect(find.text('¿Qué compró?'), findsOneWidget);
    await openPurchaseLine(tester);
    await choose(tester, 'Producto', 'Mancozeb');
    await openPurchaseLine(tester);
    await tester.enterText(field('Cantidad comprada'), '3');
    await openPurchaseLine(tester);
    await tester.enterText(field('Precio por L'), '10');
    await settle(tester);
    await tapKey(tester, 'purchase-alloc-single-0');
    await choose(tester, 'Persona', 'Hermana');
    await closePurchaseLine(tester);
    await tapKey(tester, 'purchase-continue');
    await tapKey(tester, 'purchase-paid-no');
    await tapKey(tester, 'purchase-confirm');
    await waitUntil(
      tester,
      'la vuelta a la aplicación',
      () => find.byKey(const Key('application-step')).evaluate().isNotEmpty,
    );
    await settle(tester);

    // El borrador sigue: paso, mezcla y cantidades.
    expect(find.text('¿Qué aplicó?'), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(Key('application-line-quantity-${h.product}')),
          )
          .data,
      formatQuantity(1000, 'L'),
    );
    // Existencias al día: Mancozeb ya se puede agregar.
    expect(find.byKey(const Key('application-without-stock')), findsNothing);
    final add = tester.widget<DashedAddButton>(
      find.byKey(const Key('application-add-product')),
    );
    expect(add.onPressed, isNotNull);

    // Y lo del paso 1, también.
    await tapKey(tester, 'application-back');
    expect(pickerAt(tester, applicationPersonLabel).value?['name'], 'Hermana');
    expect(pickerAt(tester, 'Chaco').value?['name'], 'Chaco hermana');
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('application-area')))
          .controller!
          .text,
      '0,4',
    );
    expect(find.textContaining('Hoy, '), findsOneWidget);
    expect(await rows(tester, s.database, 'applications'), isEmpty);
  });

  Future<void> reviewHermana(WidgetTester tester, ProviderContainer c) async {
    c.read(routerProvider).push('/aplicaciones/nueva');
    await waitFor(tester, picker(applicationPersonLabel));
    await settle(tester);
    await choose(tester, applicationPersonLabel, 'Hermana');
    await choose(tester, 'Chaco', 'Chaco hermana');
    await tapKey(tester, 'application-continue');
    await tapKey(tester, 'application-add-product');
    await openPurchaseLine(tester);
    await choose(tester, 'Producto', 'Glifosato');
    await tester.enterText(
      find.byKey(const Key('application-line-quantity')),
      '1',
    );
    await tapKey(tester, 'application-line-add');
    await tapKey(tester, 'application-continue');
    expect(find.text('Revise y confirme'), findsOneWidget);
  }

  testWidgets('(a3) resumen: costo con ayuda breve y cargo; aviso de lote '
      'vencido antes de confirmar', (tester) async {
    bigSurface(tester);
    final s = await activatedHousehold(tester, 'uxjb-a3');
    final h = s.household;
    final yesterday = dayOffset(-1);
    await tester.runAsync(
      () => buy(
        h,
        person: h.relative,
        product: h.product,
        quantity: 2000,
        expiryDay: yesterday,
        lotNumber: 'L-77',
      ),
    );
    final c = await pumpModeApp(tester, s.database);
    await reviewHermana(tester, c);

    expect(
      tester
          .widget<Text>(find.byKey(const Key('application-review-cost')))
          .data,
      formatBob(10000),
    );
    expect(find.byKey(const Key('application-cost-help-text')), findsNothing);
    await tapKey(tester, 'application-cost-help');
    expect(find.byKey(const Key('application-cost-help-text')), findsOneWidget);
    expect(find.byKey(const Key('application-review-charge')), findsOneWidget);

    expect(find.byKey(const Key('application-expiry-expired')), findsOneWidget);
    expect(find.text('Se usará producto vencido'), findsOneWidget);
    expect(
      find.textContaining(
        'Glifosato: ${formatQuantity(1000, 'L')} del lote L-77, vencido el '
        '${displayDay(yesterday)}',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('application-expiry-same-day')), findsNothing);

    // Sólo informa: se confirma igual.
    await tapKey(tester, 'application-confirm');
    await waitUntil(
      tester,
      'la aplicación',
      () => find.byKey(const Key('application-step')).evaluate().isEmpty,
    );
    expect(await rows(tester, s.database, 'applications'), hasLength(1));
  });

  testWidgets('(a4) un lote que vence el día de la aplicación se indica como '
      '«Vence hoy», no como vencido', (tester) async {
    bigSurface(tester);
    final s = await activatedHousehold(tester, 'uxjb-a4');
    final h = s.household;
    await tester.runAsync(
      () => buy(
        h,
        person: h.relative,
        product: h.product,
        quantity: 2000,
        expiryDay: dayOffset(0),
      ),
    );
    final c = await pumpModeApp(tester, s.database);
    await reviewHermana(tester, c);

    expect(find.byKey(const Key('application-expiry-expired')), findsNothing);
    expect(
      find.byKey(const Key('application-expiry-same-day')),
      findsOneWidget,
    );
    expect(find.text('Vence hoy'), findsOneWidget);
    expect(find.textContaining('que vence hoy'), findsOneWidget);
  });

  // ---------------------------------------------------------- Planificación

  testWidgets('(p1) se planifica un producto sin existencias y el plan dice '
      'cuánto comprar', (tester) async {
    bigSurface(tester);
    final s = await activatedHousehold(tester, 'uxjb-p1');
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).push('/planificacion/nueva');
    await waitFor(tester, picker('Chaco'));
    await settle(tester);
    await choose(tester, 'Chaco', 'Chaco hermana');
    await choose(tester, 'Agregar producto', 'Glifosato');
    await tester.tap(find.byTooltip('Agregar al plan'));
    await settle(tester);
    await tester.enterText(field('Dosis (L/ha)'), '2');
    await settle(tester);
    expect(
      find.textContaining('comprar ${formatQuantity(1000, 'L')}'),
      findsOneWidget,
    );

    await tapKey(tester, 'plan-confirm');
    await waitUntil(
      tester,
      'el plan',
      () => find.byKey(const Key('plan-header')).evaluate().isEmpty,
    );
    final plans = await rows(tester, s.database, 'application_plans');
    expect(plans, hasLength(1));
    expect(plans.single['farm_id'], s.household.relativeFarm);
  });

  // ------------------------------------------------------------ Repositorio

  testWidgets('(r1) la previsión es la asignación FIFO de la escritura y sólo '
      'avisa si el lote vencido se usa', (tester) async {
    final s = await activatedHousehold(tester, 'uxjb-r1');
    final h = s.household;
    final today = localDay(DateTime.now());
    await tester.runAsync(() async {
      // Lote A, más antiguo y sin vencimiento; lote B, vencido.
      await buy(
        h,
        person: h.relative,
        product: h.product,
        quantity: 1000,
        date: DateTime.utc(2026, 3, 1, 12),
      );
      await buy(
        h,
        person: h.relative,
        product: h.product,
        quantity: 2000,
        date: DateTime.utc(2026, 3, 2, 12),
        expiryDay: '2026-03-03',
        lotNumber: 'B',
      );

      final small = await h.repo.previewApplicationLots(
        personId: h.relative,
        productId: h.product,
        quantityBase: 500,
        appliedAt: DateTime.now(),
      );
      expect([for (final lot in small) lot.quantityBase], [500]);
      expect(small.single.expiryDay, isNull);
      expect(
        expiringLotUses(
          applicationDay: today,
          lines: [(productName: 'Glifosato', unit: 'L', lots: small)],
        ),
        isEmpty,
      );

      final large = await h.repo.previewApplicationLots(
        personId: h.relative,
        productId: h.product,
        quantityBase: 2000,
        appliedAt: DateTime.now(),
      );
      expect([for (final lot in large) lot.quantityBase], [1000, 1000]);
      final uses = expiringLotUses(
        applicationDay: today,
        lines: [(productName: 'Glifosato', unit: 'L', lots: large)],
      );
      expect(uses, hasLength(1));
      expect(uses.single.status, ApplicationLotExpiry.expired);
      expect(uses.single.lotNumber, 'B');
      expect(uses.single.quantityBase, 1000);

      // La escritura consume exactamente lo previsto.
      final id = await h.repo.confirmApplication(
        ApplicationDraft(
          personId: h.relative,
          farmId: h.relativeFarm,
          campaignId: h.campaign,
          appliedAt: DateTime.now(),
          lines: [
            ApplicationLineDraft(productId: h.product, quantityBase: 2000),
          ],
        ),
      );
      final db = await s.database.database;
      final consumed = await db.rawQuery(
        '''SELECT c.inventory_lot_id lot, c.quantity_consumed_base q
        FROM application_consumptions c JOIN application_items i
          ON i.id=c.application_item_id
        WHERE i.application_id=? ORDER BY c.id''',
        [id],
      );
      expect(
        [for (final row in consumed) (row['lot'], row['q'])],
        [for (final lot in large) (lot.lotId, lot.quantityBase)],
      );
    });
  });

  testWidgets('(r2) aplicación histórica: el vencimiento se compara con su '
      'fecha efectiva, no con hoy', (tester) async {
    final s = await activatedHousehold(tester, 'uxjb-r2');
    final h = s.household;
    await tester.runAsync(() async {
      await buy(
        h,
        person: h.relative,
        product: h.product,
        quantity: 2000,
        date: DateTime(2026, 3, 1, 12),
        expiryDay: '2026-03-10',
      );
      Future<ApplicationLotExpiry?> statusOn(String day) async {
        final lots = await h.repo.previewApplicationLots(
          personId: h.relative,
          productId: h.product,
          quantityBase: 500,
          appliedAt: effectiveInstantForDay(day, DateTime.now()),
        );
        expect(lots, hasLength(1), reason: day);
        expect(lots.single.expiryDay, '2026-03-10');
        final uses = expiringLotUses(
          applicationDay: day,
          lines: [(productName: 'Glifosato', unit: 'L', lots: lots)],
        );
        return uses.isEmpty ? null : uses.single.status;
      }

      // Hoy ese lote ya está vencido…
      expect(
        classifyExpiry(
          expiryDay: '2026-03-10',
          today: localDay(DateTime.now()),
          leadDays: 0,
        ),
        ExpiryStatus.expired,
      );
      // …pero una aplicación del 5 de marzo no lo usó vencido.
      expect(await statusOn('2026-03-05'), isNull);
      expect(await statusOn('2026-03-10'), ApplicationLotExpiry.sameDay);
      expect(await statusOn('2026-03-15'), ApplicationLotExpiry.expired);
    });
  });

  test('vence el mismo día: no es vencido; el día antes no avisa', () {
    expect(
      expiryAtApplication(
        expiryDay: '2026-11-05',
        applicationDay: '2026-11-05',
      ),
      ApplicationLotExpiry.sameDay,
    );
    expect(
      expiryAtApplication(
        expiryDay: '2026-11-04',
        applicationDay: '2026-11-05',
      ),
      ApplicationLotExpiry.expired,
    );
    expect(
      expiryAtApplication(
        expiryDay: '2026-11-06',
        applicationDay: '2026-11-05',
      ),
      isNull,
    );
    expect(
      expiryAtApplication(expiryDay: null, applicationDay: '2026-11-05'),
      isNull,
    );
  });
}
