// Ronda 2 del rediseño (sesión A): con la hoja «Producto n» abierta, la
// página de Nueva compra sigue construida y a la vista detrás del velo (antes
// quedaba fuera de escena). Los buscadores encuentran entonces lo mismo dos
// veces —en la hoja y en la tarjeta de la línea, detrás— y lo de la página no
// se puede tocar (el velo lo tapa). Estas ayudas buscan lo que la persona
// puede alcanzar: con la hoja abierta, sólo lo de la hoja; sin hoja, todo.
// Las pruebas siguen comprobando lo mismo que antes; sólo cambia cómo llegan.
import 'package:agroquimicos/presentation/widgets/agro_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/purchase_form_driver.dart';

/// La hoja abierta (si hay una).
Finder purchaseSheet() => find.byType(InPageSheet);

/// [finder] restringido a lo alcanzable: con la hoja abierta, dentro de ella.
Finder reachable(Finder finder) => purchaseLineSheetOpen()
    ? find.descendant(of: purchaseSheet(), matching: finder)
    : finder;

/// Como [preparePurchaseKey], y además: si la hoja está abierta y [key] sólo
/// existe en la página de detrás, cierra la hoja para poder tocarla.
Future<void> prepareReachableKey(WidgetTester tester, String key) async {
  await preparePurchaseKey(tester, key);
  if (purchaseLineSheetOpen() &&
      reachable(find.byKey(Key(key))).evaluate().isEmpty) {
    await closePurchaseLine(tester);
  }
}

/// La página de detrás de la hoja (envoltorio de la página de Compra).
Finder purchasePage() => find.byKey(const Key('purchase-page'));
