// Capturas de la sesión A (segunda ronda del rediseño): la hoja «Producto n»
// de Nueva compra, vacía, con datos, con el teclado y la revisión, en el
// ARNÉS de pruebas (no en un teléfono), sobre una base sintética.
//
//   flutter test tool/rediseno/capturas_rdm2_a_test.dart
//   RDM_SHOTS=<carpeta> (por defecto build/rediseno_capturas_rdm2_a)
//   RDM_TEXT_SCALE=1.3 / 2.0 para letra ampliada; RDM_WIDTH=900 para ancha
//
// Arranque copiado de tool/rediseno/capturas_arnes_test.dart (del
// orquestador). No es parte de la suite: vive en tool/ y sólo escribe
// imágenes.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/presentation/widgets/adaptive_entity_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test/support/f04_mode_ui_harness.dart';
import '../../test/support/purchase_form_driver.dart';

typedef Row = Map<String, Object?>;

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
    Platform.environment['RDM_SHOTS'] ?? 'build/rediseno_capturas_rdm2_a',
  )..createSync(recursive: true);
  final width =
      double.tryParse(Platform.environment['RDM_WIDTH'] ?? '') ?? 390.0;
  final scale =
      double.tryParse(Platform.environment['RDM_TEXT_SCALE'] ?? '') ?? 1.0;

  Future<void> shot(WidgetTester tester, String name) async {
    await settle(tester);
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    final bytes = await tester.runAsync(() async {
      final image = await layer.toImage(
        Offset.zero & (view.size * tester.view.devicePixelRatio),
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    File('${out.path}/$name.png').writeAsBytesSync(bytes!);
  }

  Finder picker(String label) => find.byWidgetPredicate(
    (w) => w is AdaptiveEntityPicker<Row> && w.label == label,
  );
  Future<void> choose(WidgetTester tester, String label, String name) async {
    final w = tester.widget<AdaptiveEntityPicker<Row>>(picker(label).last);
    w.onChanged(w.items.firstWhere((i) => w.labelOf(i) == name));
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

  testWidgets('compra: hoja de producto (sesión A, ronda 2)', (tester) async {
    await tester.runAsync(_loadFonts);
    debugDisableShadows = false;
    tester.view.physicalSize = Size(width * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final s = await activatedHousehold(tester, 'rdm2-a-shots');
    await tester.runAsync(() async {
      await s.household.repo.addSupplier(name: 'Agroinsumos del Valle');
    });
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).push('/compras/nueva');
    await waitFor(tester, find.byKey(const Key('purchase-add-line')));
    await settle(tester);
    final tag =
        '${scale == 1.0 ? '' : '_x${scale.toString().replaceAll('.', '')}'}'
        '${width == 390 ? '' : '_w${width.round()}'}';

    await choose(tester, 'Proveedor', 'Agroinsumos del Valle');
    // Con la letra grande «Añadir producto» todavía no está construido.
    await tester.scrollUntilVisible(
      find.byKey(const Key('purchase-add-line')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
    await openPurchaseLine(tester);
    await shot(tester, 'a1_hoja_vacia$tag');

    await choose(tester, 'Producto', 'Glifosato');
    await tester.enterText(field('Cantidad comprada'), '12');
    await tester.enterText(field('Precio por L'), '118');
    await settle(tester);
    await tapKey(tester, 'purchase-alloc-single-0');
    await choose(tester, 'Persona', 'Hermana');
    // Antes de la ronda 2 la fecha estaba dentro de la sección plegada.
    if (find.byKey(const Key('purchase-expiry-0')).evaluate().isEmpty) {
      await tapKey(tester, 'purchase-lot-data-0');
    }
    await tapKey(tester, 'purchase-expiry-0');
    // El selector abre en hoy; se acepta tal cual (fecha sintética).
    final dialog = find.byType(DatePickerDialog);
    await tester.tap(
      find.descendant(of: dialog, matching: find.byType(TextButton)).last,
    );
    await settle(tester);
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester);
    await shot(tester, 'a2_hoja_con_datos$tag');
    if (find.byKey(const Key('purchase-lot-number-0')).evaluate().isEmpty) {
      await tapKey(tester, 'purchase-lot-data-0');
    }
    await tester.enterText(
      find.byKey(const Key('purchase-lot-number-0')),
      'GL-2611-07',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester);
    await tester.ensureVisible(find.byKey(const Key('purchase-lot-number-0')));
    await settle(tester);
    await shot(tester, 'a3_hoja_con_datos_abajo$tag');

    // Con el teclado: el campo de cantidad enfocado y un teclado de 336 dp.
    await tester.ensureVisible(find.byKey(const Key('purchase-quantity-0')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('purchase-quantity-0')));
    tester.view.viewInsets = const FakeViewPadding(bottom: 336 * 2);
    await settle(tester);
    await shot(tester, 'a4_hoja_teclado$tag');
    tester.view.resetViewInsets();
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester);

    await closePurchaseLine(tester);
    await shot(tester, 'a5_paso1_resumen$tag');
    await tapKey(tester, 'purchase-continue');
    await shot(tester, 'a6_revision$tag');
    debugDisableShadows = true;
  });
}
