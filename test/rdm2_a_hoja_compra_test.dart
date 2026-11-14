// Ronda 2 del rediseño móvil (sesión A, 2026-11-12): la hoja «Producto n» de
// Nueva compra.
//
// - La pantalla real de Compra sigue detrás, a la vista y atenuada por un
//   velo semitransparente, pero inerte: ni toques, ni foco, ni lector de
//   pantalla llegan a ella.
// - El borrador es uno solo: cerrar con «Cerrar», con el velo o con Atrás y
//   volver a abrir conserva lo escrito, sin crear ni recrear nada.
// - Con el teclado abierto y la letra al 130 % y al 200 % los campos, «Listo»
//   y «Añadir otro» se alcanzan, sin desbordes.
// - Lotes: el vencimiento opcional a la vista; el número del envase, aparte
//   en «Más datos del envase», se guarda igual que antes y nunca se inventa;
//   los resúmenes no repiten «sin número de lote».
//
// Datos sintéticos.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/presentation/screens/purchase_form_screen.dart';
import 'package:agroquimicos/presentation/widgets/adaptive_entity_picker.dart';
import 'package:agroquimicos/presentation/widgets/agro_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_ui_harness.dart';
import 'support/purchase_form_driver.dart';
import 'support_rdm2/a_purchase_sheet.dart';

typedef Row = Map<String, Object?>;

void main() {
  sqfliteFfiInit();

  /// Nueva compra en modo propio (todo para el titular: no hace falta
  /// elegir destinatario), con dos productos en el catálogo.
  Future<AppDatabase> open(WidgetTester tester, String name) async {
    final s = await activatedHousehold(tester, name);
    await tester.runAsync(() async {
      await OperationModeStore(s.database)
          .apply(OperationMode.personal, confirmed: true);
      await s.household.repo.addProduct(name: 'Fungicida sistémico');
    });
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).push('/compras/nueva');
    await waitFor(tester, find.byKey(const Key('purchase-add-line')));
    await settle(tester);
    return s.database;
  }

  Finder picker(String label) => reachable(
    find.byWidgetPredicate(
      (w) => w is AdaptiveEntityPicker<Row> && w.label == label,
    ),
  );

  Future<void> choose(WidgetTester tester, String label, String name) async {
    final w = tester.widget<AdaptiveEntityPicker<Row>>(picker(label));
    w.onChanged(w.items.firstWhere((i) => w.labelOf(i) == name));
    await settle(tester);
  }

  Finder field(String label) => reachable(
    find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
    ),
  );

  String textOf(WidgetTester tester, String label) =>
      tester.widget<TextField>(field(label)).controller!.text;

  Future<void> tapKey(WidgetTester tester, String key) async {
    final target = reachable(find.byKey(Key(key)));
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.tap(target);
    await settle(tester);
  }

  Future<List<Row>> rows(
    WidgetTester tester,
    AppDatabase db,
    String table,
  ) async => (await tester.runAsync(
    () async => (await db.database).query(table, orderBy: 'id'),
  ))!;

  Finder pageScrollable() => find
      .descendant(
        of: find.byKey(const Key('purchase-scroll')),
        matching: find.byType(Scrollable),
      )
      .first;

  testWidgets('fondo: la página real de Compra sigue detrás, atenuada e '
      'inerte (toques, foco y lector de pantalla)', (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester, 'rdm2-a-fondo');
    await choose(tester, 'Proveedor', 'Proveedor');
    // Sin hoja, la página se anuncia.
    expect(find.semantics.byLabel('¿Qué compró?'), findsOneWidget);
    final scrollBefore = tester.state<ScrollableState>(pageScrollable());

    await openPurchaseLine(tester);
    expect(purchaseLineSheetOpen(), isTrue);
    // La página no sale de escena: se sigue viendo (antes, `Offstage`).
    expect(find.text('¿Qué compró?'), findsOneWidget);
    expect(find.byKey(const Key('purchase-step')), findsOneWidget);
    expect(find.byKey(const Key('purchase-add-line')), findsOneWidget);
    // Es la misma página, no una copia: el mismo estado de desplazamiento.
    expect(
      identical(tester.state<ScrollableState>(pageScrollable()), scrollBefore),
      isTrue,
    );
    // El velo es semitransparente (deja ver la página) y no plano.
    final veil = tester.widget<ModalBarrier>(find.byKey(InPageSheet.veilKey));
    expect(veil.color, isNotNull);
    expect(veil.color!.a, greaterThan(0.2));
    expect(veil.color!.a, lessThan(0.8));
    // Inerte para el lector de pantalla y el foco.
    expect(tester.widget<ExcludeSemantics>(purchasePage()).excluding, isTrue);
    expect(
      tester
          .widget<ExcludeFocus>(
            find
                .descendant(
                  of: purchasePage(),
                  matching: find.byType(ExcludeFocus),
                )
                .first,
          )
          .excluding,
      isTrue,
    );
    expect(find.semantics.byLabel('¿Qué compró?'), findsNothing);
    expect(find.semantics.byLabel('Paso 1 de 2'), findsNothing);
    expect(find.semantics.byLabel('Producto 1'), findsWidgets);
    // Y para el dedo: tocar donde está «Volver» de la página toca el velo,
    // que cierra la hoja; la compra no se cierra ni pide descartar.
    await tester.tapAt(
      tester.getCenter(find.byKey(const Key('purchase-close'))),
    );
    await settle(tester);
    expect(purchaseLineSheetOpen(), isFalse);
    expect(find.byType(PurchaseFormScreen), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    // Sin hoja, la página vuelve a anunciarse y a responder.
    expect(find.semantics.byLabel('¿Qué compró?'), findsOneWidget);
    expect(tester.widget<ExcludeSemantics>(purchasePage()).excluding, isFalse);
    semantics.dispose();
  });

  testWidgets('borrador: «Cerrar», el velo y Atrás conservan lo escrito en '
      'la misma línea; Atrás sin hoja pide descartar', (tester) async {
    await open(tester, 'rdm2-a-borrador');
    await openPurchaseLine(tester);
    await choose(tester, 'Producto', 'Glifosato');
    await tester.enterText(field('Cantidad comprada'), '12');
    await tester.enterText(field('Precio por L'), '118');
    await settle(tester);
    final controller = tester
        .widget<TextField>(field('Cantidad comprada'))
        .controller;

    Future<void> reopenAndCheck(String how) async {
      expect(purchaseLineSheetOpen(), isFalse, reason: how);
      expect(find.byType(PurchaseFormScreen), findsOneWidget, reason: how);
      expect(find.byType(AlertDialog), findsNothing, reason: how);
      // Una sola línea: cerrar no crea ni duplica nada.
      expect(find.byKey(const Key('purchase-line-1')), findsNothing);
      await openPurchaseLine(tester);
      expect(find.text('Producto 1'), findsOneWidget, reason: how);
      expect(textOf(tester, 'Cantidad comprada'), '12', reason: how);
      expect(textOf(tester, 'Precio por L'), '118', reason: how);
      // El mismo borrador, no uno recreado.
      expect(
        identical(
          tester.widget<TextField>(field('Cantidad comprada')).controller,
          controller,
        ),
        isTrue,
        reason: how,
      );
    }

    await tapKey(tester, 'purchase-line-close');
    await reopenAndCheck('Cerrar');
    // Un toque en el velo, arriba, sobre la página.
    await tester.tapAt(const Offset(200, 20));
    await settle(tester);
    await reopenAndCheck('velo');
    // Atrás de Android con la hoja abierta: cierra sólo la hoja.
    await tester.binding.handlePopRoute();
    await settle(tester);
    await reopenAndCheck('Atrás');
    // Atrás sin hoja y con datos: pide descartar; «Seguir editando» deja
    // todo igual.
    await closePurchaseLine(tester);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.text('¿Descartar cambios?'), findsOneWidget);
    await tester.tap(find.text('Seguir editando'));
    await settle(tester);
    await reopenAndCheck('Seguir editando');
  });

  for (final scale in [1.3, 2.0]) {
    testWidgets('teclado abierto y letra al ${(scale * 100).round()} %: '
        'campos, «Listo» y «Añadir otro» alcanzables, sin desbordes', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await open(tester, 'rdm2-a-teclado-$scale');
      await tester.scrollUntilVisible(
        find.byKey(const Key('purchase-add-line')),
        200,
        scrollable: pageScrollable(),
      );
      await openPurchaseLine(tester);
      await choose(tester, 'Producto', 'Glifosato');
      await tapKey(tester, 'purchase-quantity-0');
      // Teclado de 336 dp: queda 844 − 336 = 508 dp a la vista.
      tester.view.viewInsets = const FakeViewPadding(bottom: 336 * 2);
      addTearDown(tester.view.resetViewInsets);
      await settle(tester);
      const visibleBottom = 844.0 - 336;

      void above(Finder f, String what) {
        final rect = tester.getRect(f);
        expect(rect.top, greaterThanOrEqualTo(0), reason: what);
        expect(
          rect.bottom,
          lessThanOrEqualTo(visibleBottom + 0.5),
          reason: what,
        );
      }

      // Las acciones quedan fijas sobre el teclado.
      above(reachable(find.byKey(const Key('purchase-line-done'))), 'Listo');
      above(
        reachable(find.byKey(const Key('purchase-line-next'))),
        'Añadir otro',
      );
      // Cada campo se alcanza desplazando la hoja.
      for (final key in [
        'purchase-quantity-0',
        'purchase-price-0',
        'purchase-expiry-0',
        'purchase-lot-data-0',
      ]) {
        final f = reachable(find.byKey(Key(key)));
        await tester.ensureVisible(f);
        await settle(tester);
        above(f, key);
      }
      await tapKey(tester, 'purchase-lot-data-0');
      final lot = reachable(find.byKey(const Key('purchase-lot-number-0')));
      await tester.ensureVisible(lot);
      await settle(tester);
      above(lot, 'número del envase');
      await tester.enterText(lot, 'GL-77');
      await settle(tester);
      // «Añadir otro» y «Listo» responden con el teclado abierto.
      await tapKey(tester, 'purchase-line-next');
      expect(find.text('Producto 2'), findsOneWidget);
      await tapKey(tester, 'purchase-line-done');
      expect(purchaseLineSheetOpen(), isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('número del envase: aparte en «Más datos del envase», se '
      'guarda igual que antes y nunca se inventa; resúmenes sin «sin número '
      'de lote»', (tester) async {
    final db = await open(tester, 'rdm2-a-envase');
    await choose(tester, 'Proveedor', 'Proveedor');
    await openPurchaseLine(tester);
    await choose(tester, 'Producto', 'Glifosato');
    await tester.enterText(field('Cantidad comprada'), '2');
    await tester.enterText(field('Precio por L'), '45');
    await settle(tester);
    // El vencimiento, a la vista; el número del envase, plegado aparte.
    expect(reachable(find.text('Vencimiento (opcional)')), findsOneWidget);
    expect(reachable(find.text('Más datos del envase')), findsOneWidget);
    expect(find.byKey(const Key('purchase-lot-number-0')), findsNothing);
    expect(find.text('Vencimiento y lote (opcional)'), findsNothing);
    await tapKey(tester, 'purchase-lot-data-0');
    final lot = reachable(find.byKey(const Key('purchase-lot-number-0')));
    expect(
      tester.widget<TextField>(lot).decoration!.labelText,
      'Lote del fabricante (opcional)',
    );
    await tester.enterText(lot, '  GL-77 ');
    await settle(tester);
    expect(reachable(find.text('Lote del fabricante: GL-77')), findsOneWidget);

    // Segunda línea sin número: queda vacía, no se genera ninguno.
    await tapKey(tester, 'purchase-line-next');
    await choose(tester, 'Producto', 'Fungicida sistémico');
    await tester.enterText(field('Cantidad comprada'), '1');
    await tester.enterText(field('Precio por L'), '10');
    await settle(tester);
    await closePurchaseLine(tester);
    // Las tarjetas: cantidad y persona, sin el número ni su ausencia.
    expect(find.textContaining('sin número'), findsNothing);
    expect(find.textContaining('GL-77'), findsNothing);

    await tapKey(tester, 'purchase-continue');
    expect(
      tester.widget<Text>(find.byKey(const Key('purchase-review-lot-0'))).data,
      'Lote del fabricante: GL-77',
    );
    expect(find.byKey(const Key('purchase-review-lot-1')), findsNothing);
    expect(find.textContaining('sin número'), findsNothing);
    expect(find.textContaining('Sin fecha'), findsNothing);
    await tester.tap(find.byKey(const Key('purchase-paid-no')));
    await settle(tester);
    await tapKey(tester, 'purchase-confirm');
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);

    final lots = await rows(tester, db, 'inventory_lots');
    expect(lots, hasLength(2));
    // Sin espacios a los lados, como antes; la segunda, sin número.
    expect(lots[0]['lot_number'], 'GL-77');
    expect(lots[0]['expiry_date'], isNull);
    expect(lots[1]['lot_number'], isNull);
    expect(lots[1]['expiry_date'], isNull);
  });
}
