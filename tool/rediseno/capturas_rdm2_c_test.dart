// Capturas de la ronda 2, sesión C (Personas: Cuentas y Costos, buscador,
// estado de cuenta y movimientos propios) en el ARNÉS de pruebas, no en un
// teléfono: la app real sobre una base SINTÉTICA (`c_seed.dart`), con las
// tipografías empaquetadas.
//
//   flutter test tool/rediseno/capturas_rdm2_c_test.dart
//   RDM_SHOTS=<carpeta> (por defecto build/rediseno_capturas_rdm2_c)
//   RDM_TEXT_SCALE=1.3 / 2.0 para letra ampliada; RDM_WIDTH=900 para ancho
//
// Sirve para el «antes» (código base) y el «después»: sólo usa rutas y
// textos que existen en los dos; lo que no existe se salta.
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
import '../../test/support_rdm2/c_seed.dart';

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
    Platform.environment['RDM_SHOTS'] ?? 'build/rediseno_capturas_rdm2_c',
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

  Finder search() => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == 'Buscar persona',
  );

  Future<void> tapFinder(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder.first);
    await tester.pump();
    await tester.tap(finder.first);
    await settle(tester);
  }

  Future<void> top(WidgetTester tester) async {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 4000));
    await settle(tester);
  }

  Future<void> closeDialog(WidgetTester tester) async {
    if (find.text('Cerrar').evaluate().isNotEmpty) {
      await tester.tap(find.text('Cerrar').last);
      await settle(tester);
    }
  }

  Finder cardOf(String name) =>
      find.ancestor(of: find.text(name).first, matching: find.byType(Card));

  Future<void> recorrido(WidgetTester tester) async {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = Size(width * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final w = await seedRdm2cWorld(tester, 'rdm2-c-shots');
    final c = await pumpModeApp(tester, w.database);

    // Personas.
    c.read(routerProvider).go('/personas');
    await waitFor(tester, find.byKey(const Key('persons-receivable')));
    await settle(tester);
    await shot(tester, 'c01_personas');

    // Buscador de Personas con «ro».
    await tester.enterText(search(), 'ro');
    await settle(tester);
    await shot(tester, 'c02_personas_buscar_ro');
    await tester.enterText(search(), 'maria  quispe');
    await settle(tester);
    await shot(tester, 'c02b_personas_buscar_maria_quispe');
    await tester.enterText(search(), '');
    await settle(tester);

    // Estado de cuenta de Juan Mamani.
    final verCuenta = find.descendant(
      of: cardOf(rdm2cThirdName),
      matching: find.text('Ver cuenta'),
    );
    if (verCuenta.evaluate().isNotEmpty) {
      await tapFinder(tester, verCuenta);
      await shot(tester, 'c04_estado_cuenta');
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -600));
      await settle(tester);
      await shot(tester, 'c04b_estado_cuenta_movimientos');
      await closeDialog(tester);
    }
    // Movimientos propios del titular.
    final propios = find.text('Ver movimientos propios');
    if (propios.evaluate().isNotEmpty) {
      await tapFinder(tester, propios);
      await shot(tester, 'c05_propios');
      await closeDialog(tester);
    }
    await top(tester);

    // Costos (después: pestaña de Personas).
    final costos = find.byKey(const Key('persons-area-costs'));
    if (costos.evaluate().isNotEmpty) {
      await tapFinder(tester, costos);
      await shot(tester, 'c06_costos');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
      await settle(tester);
      await shot(tester, 'c06b_costos_productos');
      await top(tester);
      await tapFinder(tester, find.byKey(const Key('persons-area-accounts')));
    }

    // Cuentas (`/liquidacion`): la pantalla que se repetía (antes) o la
    // misma lista de Personas (después).
    c.read(routerProvider).go('/liquidacion');
    await settle(tester);
    await shot(tester, 'c03_liquidacion');
    await tester.enterText(search(), 'ro');
    await settle(tester);
    await shot(tester, 'c03b_liquidacion_buscar_ro');
    await tester.enterText(search(), '');
    await settle(tester);
    final ownMenu = find.descendant(
      of: find.byKey(const Key('own-consumption-card')),
      matching: find.byType(PopupMenuButton<String>),
    );
    if (ownMenu.evaluate().isNotEmpty) {
      await tapFinder(tester, ownMenu);
      await shot(tester, 'c03c_menu_titular');
      await tester.tapAt(const Offset(10, 10));
      await settle(tester);
    }
    if (find.text('Costo por chaco y hectárea').evaluate().isNotEmpty) {
      await tester.scrollUntilVisible(
        find.text('Costo por chaco y hectárea'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await settle(tester);
      await shot(tester, 'c03d_liquidacion_costos');
    }

    // Detalles de persona.
    c.read(routerProvider).go('/personas');
    await settle(tester);
    c.read(routerProvider).push('/personas/${w.owner}');
    await settle(tester);
    await shot(tester, 'c07_persona_titular');
    c.read(routerProvider).go('/personas');
    await settle(tester);
    c.read(routerProvider).push('/personas/${w.longName}');
    await settle(tester);
    await shot(tester, 'c08_persona_nombre_largo');
  }

  testWidgets('personas: cuentas, costos, buscador y detalles', (tester) async {
    // Sombras reales; se restablecen antes de que el arnés compruebe sus
    // invariantes (como en `capturas_a_test.dart`).
    debugDisableShadows = false;
    try {
      await recorrido(tester);
    } finally {
      debugDisableShadows = true;
    }
  });
}
