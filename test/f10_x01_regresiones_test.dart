// Piloto X01 (2026-10-25, POCO, modalidad compartida): dos comportamientos
// observados en la sesión, reproducidos con el formulario y el selector reales
// sobre la app completa (arnés de F04, base en archivo, repositorio real).
//
// 1. Nueva aplicación: con dos productos en existencia, elegir uno agregaba
//    también el otro. `AdaptiveEntityPicker` autoselecciona cuando queda una
//    sola opción y el formulario agregaba cada selección al instante, así que
//    el producto restante entraba solo.
// 2. Nueva compra: en compartida sin ninguna persona ADMIN (como el dataset
//    DS-UX: titular y familiar), «Registrar pago total ahora» ofrecía un
//    «Pagador» sin opciones y la confirmación se negaba sin salida.
//
// La primera versión de estas pruebas (misma intención, recorrido de la
// interfaz anterior: elegir en «Elegir producto» y activar «Registrar pago
// total ahora») se ejecutó sobre `f9a4b76` (`lib/` = `1d77c14`, la base del
// piloto) antes de cambiar `lib/` y FALLÓ: «Productos (1)» no existía porque
// había dos tarjetas, y «Pagador» estaba en pantalla sin opciones. Esa versión
// no está en el repositorio (la interfaz que recorría ya no existe); su salida
// está transcrita en `docs/evidence/F10_X01_CORRECCIONES_22E4E45.md` §2.
// Esta versión recorre la interfaz corregida: pasos, «Agregar producto →
// cantidad → Agregar a la mezcla» y «¿Pagaste toda esta compra?»; sobre
// `f9a4b76` fallaría por claves inexistentes, no por el defecto.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/domain/models.dart';
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

  Future<List<Row>> rows(WidgetTester tester, db, String table) async =>
      (await tester.runAsync(
        () async => (await db.database).query(table, orderBy: 'id'),
      ))!;

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.pump();
    await tester.tap(find.byKey(Key(key)));
    await settle(tester);
  }

  testWidgets('X01-A · aplicación: elegir un producto agrega exactamente ese '
      'producto, no el que queda', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, 'x01-aplicacion');
    final h = s.household;
    // Dos productos en existencia del titular, como DS-UX (Glifosato Demo y
    // Bellator).
    await tester.runAsync(() async {
      final bellator = await h.repo.addProduct(name: 'Bellator');
      await h.repo.confirmPurchase(
        PurchaseDraft(
          supplierId: h.supplier,
          campaignId: h.campaign,
          purchaseDate: DateTime.utc(2026, 1, 2),
          items: [
            PurchaseItemDraft(
              productId: h.product,
              quantityBase: 5000,
              currency: CurrencyCode.bob,
              originalUnitPriceMinor: 4500,
              allocations: [
                AllocationDraft(personId: h.titular, quantityBase: 5000),
              ],
            ),
            PurchaseItemDraft(
              productId: bellator,
              quantityBase: 1000,
              currency: CurrencyCode.bob,
              originalUnitPriceMinor: 18000,
              allocations: [
                AllocationDraft(personId: h.titular, quantityBase: 1000),
              ],
            ),
          ],
        ),
      );
    });
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).push('/aplicaciones/nueva');
    await waitFor(tester, picker('Chaco'));
    await settle(tester);
    await choose(tester, 'Persona', 'Titular');
    await choose(tester, 'Chaco', 'Chaco titular');
    await tapKey(tester, 'application-continue');

    // El agricultor elige UN producto, escribe la cantidad y confirma.
    await tapKey(tester, 'application-add-product');
    await choose(tester, 'Producto', 'Glifosato');
    await tester.enterText(
      find.byKey(const Key('application-line-quantity')),
      '1',
    );
    await tapKey(tester, 'application-line-add');
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);

    // Sólo ese producto está en la mezcla: una tarjeta, no dos.
    expect(find.text('Productos (1)'), findsOneWidget);
    expect(find.text('Productos (2)'), findsNothing);
    expect(
      find.widgetWithText(Card, 'Bellator'),
      findsNothing,
      reason: 'Bellator no se eligió y no debe entrar en la mezcla',
    );
    expect(find.widgetWithText(Card, 'Glifosato'), findsOneWidget);
  });

  testWidgets('X01-B · compra en compartida sin ADMIN: se puede registrar el '
      'pago, y lo paga el titular vigente', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, 'x01-compra');
    final h = s.household;
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).push('/compras/nueva');
    await waitFor(tester, field('Cantidad comprada'));
    await settle(tester);

    await choose(tester, 'Proveedor', 'Proveedor');
    await choose(tester, 'Producto', 'Glifosato');
    await tester.enterText(field('Cantidad comprada'), '2');
    await tester.enterText(field('Precio BOB/L'), '45');
    // Destinatario explícito: toda la línea para el titular (la cantidad se
    // deriva de la comprada; no se reteclea).
    await tapKey(tester, 'purchase-alloc-single-0');
    await choose(tester, 'Persona', 'Titular');
    await settle(tester);
    await tapKey(tester, 'purchase-continue');

    // Quiere dejar el pago registrado. Ninguna persona es ADMIN: con la regla
    // antigua «Pagador» no tenía opciones. Con la regla nueva paga el titular
    // y no hay nada que elegir.
    expect(find.text('Pagador'), findsNothing);
    expect(find.byKey(const Key('purchase-paid-pending')), findsOneWidget);
    await tester.tap(find.byKey(const Key('purchase-paid-yes')));
    await settle(tester);
    expect(find.text('Paga el titular: Titular'), findsOneWidget);

    await tapKey(tester, 'purchase-confirm');
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);

    final purchases = await rows(tester, s.database, 'purchases');
    expect(purchases, hasLength(1), reason: 'la compra debe guardarse');
    final payments = await rows(tester, s.database, 'provider_payments');
    expect(payments, hasLength(1), reason: 'el pago debe guardarse');
    expect(payments.single['payer_person_id'], h.titular);
    expect(payments.single['amount_bob_minor'], 9000);
  });
}
