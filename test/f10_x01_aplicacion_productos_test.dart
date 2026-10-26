// Nueva aplicación tras el piloto X01: los productos entran sólo por el
// recorrido explícito «Agregar producto → elegir → cantidad → Agregar a la
// mezcla». Pruebas con el selector y el formulario juntos, sobre la app real
// (arnés de F04, base en archivo, repositorio real), en compartida y en
// propia.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/presentation/widgets/adaptive_entity_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';
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

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.pump();
    await tester.tap(find.byKey(Key(key)));
    await settle(tester);
  }

  Finder cards() => find.byWidgetPredicate(
    (w) =>
        w is Card &&
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('application-line-') &&
        !(w.key! as ValueKey<String>).value.contains('detail'),
  );

  Future<List<Row>> rows(WidgetTester tester, db, String table) async =>
      (await tester.runAsync(
        () async => (await db.database).query(table, orderBy: 'id'),
      ))!;

  /// Hogar activado con [productNames] en existencia del titular (1 L cada
  /// uno, salvo que se indique), en compartida o en propia.
  Future<({dynamic database, Household household})> home(
    WidgetTester tester,
    String name,
    List<String> productNames, {
    bool personal = false,
    Map<String, int> quantities = const {},
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, name);
    final h = s.household;
    await tester.runAsync(() async {
      final ids = <int>[];
      for (final product in productNames) {
        ids.add(
          product == 'Glifosato'
              ? h.product
              : await h.repo.addProduct(name: product),
        );
      }
      await h.repo.confirmPurchase(
        PurchaseDraft(
          supplierId: h.supplier,
          campaignId: h.campaign,
          purchaseDate: DateTime.utc(2026, 1, 2),
          items: [
            for (final (index, id) in ids.indexed)
              PurchaseItemDraft(
                productId: id,
                quantityBase: quantities[productNames[index]] ?? 1000,
                currency: CurrencyCode.bob,
                originalUnitPriceMinor: 10000,
                allocations: [
                  AllocationDraft(
                    personId: h.titular,
                    quantityBase: quantities[productNames[index]] ?? 1000,
                  ),
                ],
              ),
          ],
        ),
      );
      if (personal) {
        await OperationModeStore(s.database)
            .apply(OperationMode.personal, confirmed: true);
      }
    });
    return (database: s.database, household: h);
  }

  /// Abre el formulario y llega al paso 2 con el titular y su chaco.
  Future<void> openProductsStep(
    WidgetTester tester,
    dynamic database, {
    bool personal = false,
  }) async {
    final c = await pumpModeApp(tester, database);
    c.read(routerProvider).push('/aplicaciones/nueva');
    await waitFor(tester, picker('Chaco'));
    await settle(tester);
    if (!personal) await choose(tester, 'Persona', 'Titular');
    await choose(tester, 'Chaco', 'Chaco titular');
    await tapKey(tester, 'application-continue');
    expect(find.text('Productos (0)'), findsOneWidget);
  }

  /// Recorrido explícito completo para un producto.
  Future<void> addProduct(
    WidgetTester tester,
    String name,
    String quantity,
  ) async {
    await tapKey(tester, 'application-add-product');
    await choose(tester, 'Producto', name);
    await tester.enterText(
      find.byKey(const Key('application-line-quantity')),
      quantity,
    );
    await tapKey(tester, 'application-line-add');
  }

  testWidgets('un solo producto: abrir y cancelar no agregan; sólo «Agregar a '
      'la mezcla» agrega una tarjeta, con su cantidad y unidad', (
    tester,
  ) async {
    final s = await home(tester, 'uno', ['Glifosato']);
    await openProductsStep(tester, s.database);

    // Abrir la hoja no agrega nada, aunque sólo haya una opción.
    await tapKey(tester, 'application-add-product');
    expect(find.byKey(const Key('application-line-add')), findsOneWidget);
    expect(
      find.descendant(
        of: picker('Producto'),
        matching: find.text('Seleccionar'),
      ),
      findsOneWidget,
      reason: 'sin autoselección: la persona elige',
    );
    await tapKey(tester, 'application-line-cancel');
    expect(find.text('Productos (0)'), findsOneWidget);
    expect(cards(), findsNothing);

    // Elegir el producto sin confirmar tampoco agrega.
    await tapKey(tester, 'application-add-product');
    await choose(tester, 'Producto', 'Glifosato');
    await tapKey(tester, 'application-line-cancel');
    expect(find.text('Productos (0)'), findsOneWidget);

    await addProduct(tester, 'Glifosato', '0,5');
    expect(find.text('Productos (1)'), findsOneWidget);
    expect(cards(), findsOneWidget);
    expect(find.text('0,5 L'), findsOneWidget);
    expect(find.text('Editar'), findsOneWidget);
    expect(find.text('Quitar'), findsOneWidget);
    // No queda nada que agregar: el botón se desactiva, no agrega solo.
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('application-add-product')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('dos productos: elegir uno no agrega el otro; después se puede '
      'agregar, quitar y volver a agregar, sin duplicados', (tester) async {
    final s = await home(tester, 'dos', ['Glifosato', 'Bellator']);
    await openProductsStep(tester, s.database);

    await addProduct(tester, 'Glifosato', '1');
    expect(find.text('Productos (1)'), findsOneWidget);
    expect(find.widgetWithText(Card, 'Bellator'), findsNothing);

    // Reconstruir la pantalla (cambio de tamaño) no agrega el restante.
    await tester.binding.setSurfaceSize(const Size(600, 2400));
    await settle(tester);
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    await settle(tester);
    expect(find.text('Productos (1)'), findsOneWidget);

    // El selector sólo ofrece el que falta: nada de duplicados.
    await tapKey(tester, 'application-add-product');
    final offered = tester
        .widget<AdaptiveEntityPicker<Row>>(picker('Producto'))
        .items
        .map((p) => p['product_name'])
        .toList();
    expect(offered, ['Bellator']);
    await choose(tester, 'Producto', 'Bellator');
    await tester.enterText(
      find.byKey(const Key('application-line-quantity')),
      '0,2',
    );
    await tapKey(tester, 'application-line-add');
    expect(find.text('Productos (2)'), findsOneWidget);
    expect(cards(), findsNWidgets(2));

    // Quitar y volver a agregar.
    await tapKey(tester, 'application-line-remove-${s.household.product}');
    expect(find.text('Productos (1)'), findsOneWidget);
    expect(find.widgetWithText(Card, 'Glifosato'), findsNothing);
    await addProduct(tester, 'Glifosato', '1');
    expect(find.text('Productos (2)'), findsOneWidget);
  });

  testWidgets('varios productos: se agregan uno a uno y los no elegidos no '
      'entran; editar cambia la cantidad', (tester) async {
    final s = await home(tester, 'varios', ['Glifosato', 'Bellator', 'Aceite']);
    await openProductsStep(tester, s.database);

    await addProduct(tester, 'Bellator', '0,2');
    await addProduct(tester, 'Aceite', '0,1');
    expect(find.text('Productos (2)'), findsOneWidget);
    expect(find.widgetWithText(Card, 'Glifosato'), findsNothing);

    // Cancelar la incorporación del tercero conserva lo ya escrito.
    await tapKey(tester, 'application-add-product');
    await choose(tester, 'Producto', 'Glifosato');
    await tapKey(tester, 'application-line-cancel');
    expect(find.text('Productos (2)'), findsOneWidget);
    expect(find.text('0,2 L'), findsOneWidget);
    expect(find.text('0,1 L'), findsOneWidget);

    // Editar la cantidad de Bellator.
    final bellator = (await rows(
      tester,
      s.database,
      'products',
    )).firstWhere((p) => p['name'] == 'Bellator')['id'];
    await tapKey(tester, 'application-line-edit-$bellator');
    expect(find.text('Guardar cambios'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('application-line-quantity')),
      '0,3',
    );
    await tapKey(tester, 'application-line-add');
    expect(find.text('0,3 L'), findsOneWidget);
    expect(find.text('0,2 L'), findsNothing);
    expect(find.text('Productos (2)'), findsOneWidget);
  });

  testWidgets('volver un paso atrás conserva el borrador; confirmar guarda '
      'exactamente las líneas elegidas', (tester) async {
    final s = await home(tester, 'guardar', ['Glifosato', 'Bellator']);
    await openProductsStep(tester, s.database);
    await addProduct(tester, 'Bellator', '0,2');

    await tapKey(tester, 'application-back');
    expect(find.byKey(const Key('application-continue')), findsOneWidget);
    expect(find.text('Paso 1 de 3 · Persona y chaco'), findsOneWidget);
    await tapKey(tester, 'application-continue');
    expect(find.text('Productos (1)'), findsOneWidget);
    expect(find.text('0,2 L'), findsOneWidget);

    await tapKey(tester, 'application-continue');
    expect(find.text('Paso 3 de 3 · Resumen y confirmación'), findsOneWidget);
    expect(find.text('Bellator · 0,2 L'), findsOneWidget);
    await tapKey(tester, 'application-confirm');
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);

    final items = await rows(tester, s.database, 'application_items');
    expect(items, hasLength(1));
    expect(items.single['quantity_base'], 200);
    final bellator = (await rows(
      tester,
      s.database,
      'products',
    )).firstWhere((p) => p['name'] == 'Bellator')['id'];
    expect(items.single['product_id'], bellator);
  });

  testWidgets('sin existencia suficiente: se avisa en la hoja y al confirmar '
      'se explica qué falta y cómo seguir, sin guardar nada', (tester) async {
    final s = await home(
      tester,
      'insuficiente',
      ['Glifosato', 'Bellator'],
      quantities: {'Bellator': 1500},
    );
    await openProductsStep(tester, s.database);

    await tapKey(tester, 'application-add-product');
    await choose(tester, 'Producto', 'Bellator');
    await tester.enterText(
      find.byKey(const Key('application-line-quantity')),
      '5',
    );
    await tester.pump();
    expect(
      find.byKey(const Key('application-line-insufficient')),
      findsOneWidget,
    );
    await tapKey(tester, 'application-line-add');
    expect(find.textContaining('faltan 3,5 L'), findsOneWidget);

    await tapKey(tester, 'application-continue');
    await tapKey(tester, 'application-confirm');
    expect(
      find.textContaining('No alcanza el Bellator: hay 1,5 L y escribiste 5 L'),
      findsOneWidget,
    );
    expect(find.textContaining('Baja la cantidad'), findsOneWidget);
    expect(await rows(tester, s.database, 'applications'), isEmpty);
    // El borrador sigue: se puede volver, editar y guardar.
    expect(find.byKey(const Key('application-confirm')), findsOneWidget);
  });

  testWidgets('propia: aplica el titular sin elegirlo y el recorrido es el '
      'mismo', (tester) async {
    final s = await home(tester, 'propia', ['Glifosato'], personal: true);
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).push('/aplicaciones/nueva');
    await waitFor(tester, picker('Chaco'));
    await settle(tester);
    expect(picker('Persona'), findsNothing);
    expect(find.byKey(const Key('application-personal-owner')), findsOneWidget);
    expect(find.text('Titular'), findsWidgets);
    await choose(tester, 'Chaco', 'Chaco titular');
    await tapKey(tester, 'application-continue');
    await addProduct(tester, 'Glifosato', '1');
    expect(find.text('Productos (1)'), findsOneWidget);
    await tapKey(tester, 'application-continue');
    await tapKey(tester, 'application-confirm');
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    final apps = await rows(tester, s.database, 'applications');
    expect(apps, hasLength(1));
    expect(apps.single['person_id'], s.household.titular);
  });
}
