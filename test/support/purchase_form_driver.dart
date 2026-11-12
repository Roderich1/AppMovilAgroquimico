// Rediseño móvil (2026-11-12): en «Nueva compra» los campos de cada producto
// viven en la hoja «Producto n», dentro de la misma página y sobre el mismo
// borrador. Estas ayudas abren o cierran esa hoja antes de tocar un campo, y
// leen los selectores de dos opciones, para que cada prueba siga comprobando
// lo mismo que antes.
import 'package:agroquimicos/presentation/widgets/agro_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'f04_mode_ui_harness.dart' show settle;

/// Hay una hoja de producto abierta.
bool purchaseLineSheetOpen() =>
    find.byKey(const Key('purchase-line-done')).evaluate().isNotEmpty;

/// Abre la hoja del producto [index] (0, 1…). Si la línea no existe todavía,
/// la crea con «Añadir producto» / «Añadir otro producto».
Future<void> openPurchaseLine(WidgetTester tester, [int index = 0]) async {
  if (find.byKey(Key('purchase-line-sheet-$index')).evaluate().isNotEmpty) {
    return;
  }
  await closePurchaseLine(tester);
  final card = find.byKey(Key('purchase-line-$index'));
  final target = card.evaluate().isNotEmpty
      ? card
      : find.byKey(const Key('purchase-add-line'));
  await tester.ensureVisible(target);
  await tester.pump();
  // En la parte de arriba de la tarjeta: debajo puede haber una revisión de
  // voz, que tiene sus propios botones.
  await tester.tapAt(tester.getTopLeft(target) + const Offset(40, 24));
  await settle(tester);
}

/// Cierra la hoja de producto, si hay una abierta («Listo»).
Future<void> closePurchaseLine(WidgetTester tester) async {
  final done = find.byKey(const Key('purchase-line-done'));
  if (done.evaluate().isEmpty) return;
  await tester.ensureVisible(done);
  await tester.pump();
  await tester.tap(done);
  await settle(tester);
}

/// Deja a la vista lo que necesita [key] antes de tocarla: las claves de una
/// línea (`purchase-alloc-*-n`, `purchase-lot-*-n`, `purchase-expiry-*-n`,
/// `purchase-currency-*-n`) abren su hoja; «Continuar» y lo que vive en la
/// página la cierran.
Future<void> preparePurchaseKey(WidgetTester tester, String key) async {
  final line = RegExp(
    r'^purchase-(alloc|lot|expiry|currency|quantity|price|line-remove|alloc-add)[a-z-]*-(\d+)$',
  ).firstMatch(key);
  if (line != null) {
    await openPurchaseLine(tester, int.parse(line.group(2)!));
    return;
  }
  const inPage = {
    'purchase-continue',
    'purchase-add-line',
    'purchase-date',
    'compra-completar-voz',
    'form-dictar',
    'purchase-close',
    'voz-hablar',
    'voz-terminar',
    'voz-cancelar-dictado',
    'voz-panel-cerrar',
    'voz-deshacer',
    'voz-dictar-mas',
    'voz-resultado-cerrar',
  };
  if (inPage.contains(key) || RegExp(r'^purchase-line-\d+$').hasMatch(key)) {
    await closePurchaseLine(tester);
    return;
  }
  // Lo demás (las opciones de una revisión de voz, por ejemplo) está en la
  // hoja o en la página: si no se ve con la hoja abierta, está en la página.
  if (find.byKey(Key(key)).evaluate().isEmpty && purchaseLineSheetOpen()) {
    await closePurchaseLine(tester);
  }
}

/// Si la opción [key] de un [SegmentToggle] está elegida.
bool segmentSelected(WidgetTester tester, String key) {
  final option = find.byKey(Key(key));
  final toggle = tester.widget(
    find
        .ancestor(
          of: option,
          matching: find.byWidgetPredicate((w) => w is SegmentToggle),
        )
        .first,
  ) as SegmentToggle;
  final match = toggle.options.firstWhere((o) => o.key == Key(key));
  return match.value == toggle.selected;
}

/// Si la respuesta [key] de unas [ChoiceCards] está elegida.
bool choiceSelected(WidgetTester tester, String key) {
  final option = find.byKey(Key(key));
  final cards = tester.widget(
    find
        .ancestor(
          of: option,
          matching: find.byWidgetPredicate((w) => w is ChoiceCards),
        )
        .first,
  ) as ChoiceCards;
  final match = cards.options.firstWhere((o) => o.key == Key(key));
  return match.value == cards.selected;
}
