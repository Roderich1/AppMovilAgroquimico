// Capturas del modo individual, sesión B (láminas I-04, I-05, I-30, I-31,
// I-32, I-33) en el ARNÉS de pruebas, no en un teléfono: la app real sobre
// una base SINTÉTICA que cumple el modo individual
// (test/support/ind_b_individual_seed.dart), con las tipografías
// empaquetadas y los iconos de Material. Arranque copiado de
// capturas_rdm2_b_test.dart.
//
//   flutter test tool/rediseno/capturas_ind_b_test.dart
//   RDM_SHOTS=<carpeta> (por defecto build/capturas_ind_b)
//   RDM_TEXT_SCALE=1.3 | 2.0 para letra ampliada
//   RDM_WIDTH=900 para una vista ancha
//
// Proveedores (I-05) se abre con una ruta propia del arnés mientras la ruta
// `/proveedores` no exista en app.dart (la añade el orquestador): por eso
// esa captura no tiene barra inferior.
//
// No es parte de la suite: vive en tool/ y sólo escribe imágenes.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/presentation/screens/ind_b_suppliers_screen.dart';
import 'package:agroquimicos/presentation/theme/agro_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test/support/f04_mode_ui_harness.dart';
import '../../test/support/ind_b_individual_seed.dart';

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
    Platform.environment['RDM_SHOTS'] ?? 'build/capturas_ind_b',
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

  void setUpView(WidgetTester tester) {
    debugDisableShadows = false;
    tester.view.physicalSize = Size(width * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  testWidgets('modo individual: almacén, detalle, actividad, proveedores', (
    tester,
  ) async {
    await tester.runAsync(_loadFonts);
    setUpView(tester);
    final s = await activatedHousehold(tester, 'ind-b-shots');
    final seed = await tester.runAsync(() => seedIndividualB(s.household));
    final c = await pumpModeApp(tester, s.database);

    // I-30 / I-33: Almacén (nombre largo, unidades distintas, planes).
    c.read(routerProvider).go('/inventario');
    await waitFor(tester, find.byKey(const Key('inventory-alerts-pill')));
    await shot(tester, 'i30_almacen');
    await scrollTo(tester, find.byKey(const Key('inventory-alerts-entry')));
    await shot(tester, 'i30_almacen_final');

    // I-31: detalle del fungicida (planes, movimientos, lotes).
    c.read(routerProvider).push('/inventario/${seed!.fungicide}');
    await waitFor(tester, find.byKey(const Key('inventory-movements')));
    await shot(tester, 'i31_detalle');
    await scrollTo(tester, find.byKey(const Key('inventory-movements-title')));
    await shot(tester, 'i31_detalle_movimientos');
    final lots = find.byKey(const Key('inventory-lots'));
    await tester.ensureVisible(lots);
    await settle(tester);
    await tester.tap(lots);
    await settle(tester);
    await scrollTo(tester, lots);
    await shot(tester, 'i31_detalle_lotes');
    c.read(routerProvider).pop();
    await settle(tester);

    // I-04: Actividad.
    c.read(routerProvider).go('/operaciones');
    await waitFor(tester, find.byKey(const Key('activity-suppliers')));
    await shot(tester, 'i04_actividad');

    // I-05: Proveedores (ruta del arnés; ver cabecera).
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Material(
          color: AgroColors.canvas,
          child: SafeArea(child: SuppliersBalanceScreen()),
        ),
      ),
    );
    await waitFor(tester, find.byKey(const Key('suppliers-debt')));
    await shot(tester, 'i05_proveedores');
    debugDisableShadows = true;
  });

  testWidgets('modo individual sin compras: almacén vacío', (tester) async {
    await tester.runAsync(_loadFonts);
    setUpView(tester);
    final s = await activatedHousehold(tester, 'ind-b-shots-vacio');
    await tester.runAsync(
      () =>
          OperationModeStore(s.database)
              .apply(OperationMode.personal, confirmed: true),
    );
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).go('/inventario');
    await waitFor(tester, find.byKey(const Key('inventory-empty')));
    await shot(tester, 'i32_almacen_vacio');
    debugDisableShadows = true;
  });
}
