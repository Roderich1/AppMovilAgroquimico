// Capturas de la ronda 2 de la sesión B (detalle de producto de Almacén,
// lotes, avisos) en el ARNÉS de pruebas, no en un teléfono: la app real
// sobre una base SINTÉTICA (test/support_rdm2/b_almacen_seed.dart), con las
// tipografías empaquetadas y los iconos de Material. El arranque copia el de
// capturas_arnes_test.dart.
//
//   flutter test tool/rediseno/capturas_rdm2_b_test.dart
//   RDM_SHOTS=<carpeta> (por defecto build/rediseno_capturas_rdm2_b)
//   RDM_TEXT_SCALE=1.3 | 2.0 para letra ampliada
//   RDM_WIDTH=900 para una vista ancha
//
// Sirve igual sobre el código anterior («antes») y el nuevo («después»):
// sólo usa claves que existen en los dos y despliega cualquier panel
// plegado de los lotes.
//
// No es parte de la suite: vive en tool/ y sólo escribe imágenes.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:agroquimicos/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test/support/f04_mode_ui_harness.dart';
import '../../test/support_rdm2/b_almacen_seed.dart';

Future<void> _loadFonts() async {
  Future<void> family(String name, List<String> assets) async {
    final loader = FontLoader(name);
    for (final asset in assets) {
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
  }

  await family('DM Sans', [
    'assets/fonts/DMSans-400.ttf',
    'assets/fonts/DMSans-500.ttf',
    'assets/fonts/DMSans-700.ttf',
  ]);
  await family('Bricolage Grotesque', [
    'assets/fonts/BricolageGrotesque-700.ttf',
    'assets/fonts/BricolageGrotesque-800.ttf',
  ]);
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final icons = File(
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(await icons.readAsBytes())));
  await loader.load();
}

void main() {
  sqfliteFfiInit();
  final out = Directory(
    Platform.environment['RDM_SHOTS'] ?? 'build/rediseno_capturas_rdm2_b',
  )..createSync(recursive: true);
  final width =
      double.tryParse(Platform.environment['RDM_WIDTH'] ?? '') ?? 390.0;
  final scale =
      double.tryParse(Platform.environment['RDM_TEXT_SCALE'] ?? '') ?? 1.0;
  final tag =
      '${scale == 1.0 ? '' : '_x${scale.toString().replaceAll('.', '')}'}'
      '${width == 390 ? '' : '_w${width.round()}'}';

  Future<void> shot(WidgetTester tester, String name) async {
    await settle(tester);
    // La vista entera (diálogos incluidos), como capturas_arnes_test.dart.
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    final bytes = await tester.runAsync(() async {
      final image = await layer.toImage(
        Offset.zero & (view.size * tester.view.devicePixelRatio),
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    File('${out.path}/$name$tag.png').writeAsBytesSync(bytes!);
  }

  ScrollableState page(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable).first);

  /// Desplaza la página para que [finder] quede arriba de la vista.
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await settle(tester);
    final position = page(tester).position;
    final top = tester.getTopLeft(finder).dy;
    position.jumpTo(
      (position.pixels + top - 60).clamp(0, position.maxScrollExtent),
    );
    await settle(tester);
  }

  testWidgets('almacén: detalle, lotes, avisos, compra', (tester) async {
    await tester.runAsync(_loadFonts);
    debugDisableShadows = false;
    tester.view.physicalSize = Size(width * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    try {
      final s = await activatedHousehold(tester, 'rdm2-b-shots');
      final seed = await tester.runAsync(() => seedAlmacenB(s.household));
      final c = await pumpModeApp(tester, s.database);
      c.read(routerProvider).go('/inventario');
      await settle(tester);
      // Lista de Almacén: la tarjeta del producto con sus etiquetas.
      await shot(tester, 'b0_lista');
      c.read(routerProvider).push('/inventario/${seed!.product}');
      await waitFor(tester, find.byKey(const Key('inventory-lots')));
      await settle(tester);
      await shot(tester, 'b1_detalle_arriba');

      // Movimientos (y, en el código nuevo, el acceso al historial).
      await scrollTo(
        tester,
        find.byKey(const Key('inventory-movements-title')),
      );
      await shot(tester, 'b2_detalle_movimientos');

      // Lotes desplegados: el panel y, si los hay, los paneles de cada lote.
      final lots = find.byKey(const Key('inventory-lots'));
      await tester.ensureVisible(lots);
      await settle(tester);
      await tester.tap(
        find.descendant(of: lots, matching: find.byType(InkWell)).first,
      );
      await settle(tester);
      // Código anterior: cada lote era otro panel plegado (se abren todos,
      // como en la captura 9 del autor). El código nuevo no tiene paneles
      // dentro.
      final inner = find.descendant(
        of: lots,
        matching: find.byWidgetPredicate(
          (w) => w is ExpansionTile && w.key != const Key('inventory-lots'),
        ),
      );
      final count = inner.evaluate().length;
      for (var i = 0; i < count; i++) {
        final header = find
            .descendant(of: inner.at(i), matching: find.byType(ListTile))
            .first;
        await tester.ensureVisible(header);
        await settle(tester);
        await tester.tap(header);
        await settle(tester);
      }
      await scrollTo(tester, lots);
      await shot(tester, 'b3_lotes_desplegados');
      final position = page(tester).position;
      position.jumpTo(position.maxScrollExtent);
      await settle(tester);
      await shot(tester, 'b3b_lotes_fin');

      // Diálogo de avisos.
      final edit = find.byKey(const Key('inventory-alert-settings-edit'));
      await tester.ensureVisible(edit);
      await settle(tester);
      await tester.tap(edit);
      await settle(tester);
      await shot(tester, 'b4_dialogo_avisos');
      await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
      await settle(tester);

      // Historial completo (sólo el código nuevo lo tiene).
      final all = find.byKey(const Key('inventory-movements-all'));
      if (all.evaluate().isNotEmpty) {
        await tester.ensureVisible(all);
        await settle(tester);
        await tester.tap(all);
        await settle(tester);
        await shot(tester, 'b5_historial');
        Navigator.of(tester.element(find.byKey(const Key('inventory-history'))))
            .pop();
        await settle(tester);
      }

      // Avisos de inventario y detalle de la compra con dos lotes.
      c.read(routerProvider).go('/inventario');
      await settle(tester);
      c.read(routerProvider).push('/inventario/avisos');
      await settle(tester);
      await shot(tester, 'b6_avisos_inventario');
      c.read(routerProvider).go('/inventario');
      await settle(tester);
      c.read(routerProvider).push('/compras/detalle/${seed.purchaseWithLots}');
      await settle(tester);
      await shot(tester, 'b7_compra_detalle');
      final items = find.textContaining('Vencimiento');
      if (items.evaluate().isNotEmpty) {
        await scrollTo(tester, items.first);
        await shot(tester, 'b7b_compra_lotes');
      }
      // Compra sin número del fabricante ni vencimiento.
      c.read(routerProvider).go('/inventario');
      await settle(tester);
      c
          .read(routerProvider)
          .push('/compras/detalle/${seed.purchaseWithoutNumber}');
      await settle(tester);
      final plain = find.textContaining('Vencimiento');
      if (plain.evaluate().isNotEmpty) {
        await scrollTo(tester, plain.first);
        await shot(tester, 'b8_compra_sin_numero');
      }
    } finally {
      debugDisableShadows = true;
    }
  });
}
