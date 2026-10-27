// Huecos señalados por la revisión cruzada de las correcciones X01:
// (a) confirmar la compra sin responder «¿Pagaste toda esta compra?» no
//     escribe nada y explica qué falta;
// (b) «Sí, pagué todo» con una fecha de campaña cerrada: la captura tardía
//     guarda el borrador SIN pago y lo dice;
// (c) el pago posterior desde Compras, en compartida, no pide elegir pagador:
//     paga el titular.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/presentation/widgets/adaptive_entity_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/es_material_labels.dart';
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

  Future<List<Row>> rows(WidgetTester tester, db, String table) async =>
      (await tester.runAsync(
        () async => (await db.database).query(table, orderBy: 'id'),
      ))!;

  /// Paso 1 completo en compartida: Glifosato 2 L a 45, todo al titular.
  Future<void> fillStep1(WidgetTester tester) async {
    await choose(tester, 'Proveedor', 'Proveedor');
    await choose(tester, 'Producto', 'Glifosato');
    await tester.enterText(field('Cantidad comprada'), '2');
    await tester.enterText(field('Precio BOB/L'), '45');
    await choose(tester, 'Persona', 'Titular');
    await tester.enterText(field('Cantidad'), '2');
    await settle(tester);
    await tapKey(tester, 'purchase-continue');
  }

  testWidgets('(a) sin responder la pregunta del pago no se guarda nada y se '
      'dice qué falta', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, 'sin-respuesta');
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).push('/compras/nueva');
    await waitFor(tester, field('Cantidad comprada'));
    await settle(tester);
    await fillStep1(tester);
    expect(find.byKey(const Key('purchase-paid-pending')), findsOneWidget);
    await tapKey(tester, 'purchase-confirm');
    expect(find.text('Indica si pagaste toda esta compra.'), findsOneWidget);
    expect(await rows(tester, s.database, 'purchases'), isEmpty);
    expect(await rows(tester, s.database, 'provider_payments'), isEmpty);
    // El borrador sigue en la revisión.
    expect(find.byKey(const Key('purchase-confirm')), findsOneWidget);
  });

  testWidgets('(b) «Sí, pagué todo» con fecha de campaña cerrada: la revisión '
      'guarda el borrador sin pago y lo avisa', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, 'tardia-con-pago');
    final h = s.household;
    // Campaña 1 cerrada ayer; Campaña 2 activa desde hoy.
    await tester.runAsync(() async {
      final active = await h.repo.addCampaign(
        name: 'Campaña 2',
        start: DateTime.now(),
      );
      await h.repo.activateCampaign(active, closeCurrent: true);
    });
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).push('/compras/nueva');
    await waitFor(tester, field('Cantidad comprada'));
    await settle(tester);
    // Un día de la campaña cerrada: el 1 del mes en curso o del anterior.
    await tester.ensureVisible(find.byKey(const Key('purchase-date')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('purchase-date')));
    await settle(tester);
    final today = DateTime.now();
    if (today.day == 1) {
      await tester.tap(
        find.descendant(
          of: find.byType(DatePickerDialog),
          matching: find.byTooltip((await esMaterial()).previousMonthTooltip),
        ),
      );
      await settle(tester);
    }
    await tester.tap(
      find.descendant(
        of: find.byType(DatePickerDialog),
        matching: find.text('1'),
      ),
    );
    await settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(DatePickerDialog),
        matching: find.text((await esMaterial()).okButtonLabel),
      ),
    );
    await settle(tester);
    await fillStep1(tester);
    await tester.tap(find.byKey(const Key('purchase-paid-yes')));
    await settle(tester);
    expect(find.text('Pago registrado por: Titular'), findsOneWidget);
    await tapKey(tester, 'purchase-confirm');
    // RF-03: se ofrece la revisión y se avisa de que el pago NO se guarda.
    expect(find.byKey(const Key('late-explanation')), findsOneWidget);
    expect(
      find.textContaining('El pago al proveedor no se guarda con la revisión'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('late-reason')),
      'Factura tardía',
    );
    await tester.tap(find.byKey(const Key('late-register')));
    await waitFor(tester, find.textContaining('Guardada para revisión'));
    expect(
      await rows(tester, s.database, 'late_operation_drafts'),
      hasLength(1),
    );
    expect(await rows(tester, s.database, 'purchases'), isEmpty);
    expect(await rows(tester, s.database, 'provider_payments'), isEmpty);
  });

  testWidgets('(c) pago posterior desde Compras, en compartida: paga el '
      'titular sin elegir pagador', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, 'pago-posterior');
    final h = s.household;
    // Compra existente, sin pago, con existencias para la hermana.
    final purchase = await tester.runAsync(() => h.buy(h.relative, 1000));
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).go('/compras');
    await waitFor(tester, find.byType(PopupMenuButton<String>));
    await settle(tester);
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await settle(tester);
    await tester.tap(find.text('Registrar pago'));
    await waitFor(tester, find.byKey(const Key('payment-personal-payer')));
    expect(find.text('Pagador'), findsNothing);
    expect(find.text('Paga el titular: Titular'), findsOneWidget);
    await tester.tap(find.text('Registrar'));
    await settle(tester);
    final payments = await rows(tester, s.database, 'provider_payments');
    expect(payments, hasLength(1));
    expect(payments.single['purchase_id'], purchase);
    expect(payments.single['payer_person_id'], h.titular);
  });
}
