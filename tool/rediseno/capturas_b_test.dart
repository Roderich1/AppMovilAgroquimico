// Capturas de la sesión B del rediseño (Inicio, Actividad, Almacén,
// Personas) en el ARNÉS de pruebas: la app real sobre una base sintética
// (`test/support_rdm/b_seed.dart`), con las tipografías empaquetadas, a
// 390×844 dp. Sirven para comparar con la lámina; no son verificación en un
// teléfono.
//
//   flutter test tool/rediseno/capturas_b_test.dart --plain-name inicio
//   RDM_SHOTS=<carpeta> (por defecto build/rediseno_capturas_b)
//   RDM_TEXT_SCALE=1.3 | 2.0 · RDM_WIDTH=360
//
// No es parte de la suite: vive en tool/ y sólo escribe imágenes.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test/support/f04_mode_ui_harness.dart';
import '../../test/support_rdm/b_seed.dart';

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
    Platform.environment['RDM_SHOTS'] ?? 'build/rediseno_capturas_b',
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
    // La vista entera (hojas modales y botón flotante incluidos), como el
    // `shot()` de capturas_arnes_test.dart (base B1).
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

  /// Captura la pantalla y, si se desplaza, también el final.
  Future<void> shotWithEnd(WidgetTester tester, String name) async {
    await shot(tester, name);
    final scrollables = find.byType(Scrollable);
    if (scrollables.evaluate().isEmpty) return;
    final state = tester.state<ScrollableState>(scrollables.first);
    if (state.position.maxScrollExtent <= 0) return;
    // La lista se construye a medida que se desplaza: el final estimado
    // cambia hasta llegar de verdad.
    for (var i = 0; i < 10; i++) {
      final end = state.position.maxScrollExtent;
      state.position.jumpTo(end);
      await tester.pump();
      if (state.position.maxScrollExtent == end) break;
    }
    await shot(tester, '${name}_fin');
  }

  /// Prueba del arnés con sombras reales (revisión B-1): sin esto el
  /// flotante sale con un borde negro que la app no tiene.
  void shadowTest(String name, Future<void> Function(WidgetTester) body) =>
      testWidgets(name, (tester) async {
        debugDisableShadows = false;
        try {
          await body(tester);
        } finally {
          debugDisableShadows = true;
        }
      });

  Future<void> setView(WidgetTester tester) async {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = Size(width * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Future<({ProviderContainer c, SeedB seed})> seeded(
    WidgetTester tester,
    String name,
  ) async {
    await setView(tester);
    final s = await activatedHousehold(tester, name);
    final seed = await tester.runAsync(() => seedSessionB(s.household));
    final c = await pumpModeApp(tester, s.database);
    return (c: c, seed: seed!);
  }

  Future<void> go(WidgetTester tester, ProviderContainer c, String path) async {
    c.read(routerProvider).go(path);
    await settle(tester);
  }

  shadowTest('inicio', (tester) async {
    final r = await seeded(tester, 'rdm-b-inicio');
    await go(tester, r.c, '/');
    await shotWithEnd(tester, 'B_1.2_inicio');
  });

  shadowTest('inicio propio', (tester) async {
    await setView(tester);
    final s = await activatedHousehold(tester, 'rdm-b-inicio-propio');
    await tester.runAsync(() => s.household.buy(s.household.titular, 3000));
    final c = await pumpModeApp(tester, s.database);
    await switchModeBehindScreen(tester, c, s.database, OperationMode.personal);
    await go(tester, c, '/');
    await shotWithEnd(tester, 'B_1.2_inicio_propio');
  });

  shadowTest('almacen', (tester) async {
    final r = await seeded(tester, 'rdm-b-almacen');
    await go(tester, r.c, '/inventario');
    await shotWithEnd(tester, 'B_1.4_almacen');
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pump();
    await tester.tap(find.byKey(const Key('inventory-search-toggle')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('inventory-search')), 'xyz');
    await shot(tester, 'B_1.4_almacen_busqueda_vacia');
  });

  shadowTest('almacen vacio', (tester) async {
    await setView(tester);
    final s = await activatedHousehold(tester, 'rdm-b-almacen-vacio');
    final c = await pumpModeApp(tester, s.database);
    await go(tester, c, '/inventario');
    await shot(tester, 'B_1.4_almacen_vacio');
  });

  Future<void> top(WidgetTester tester) async {
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pump();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.pump();
    await tester.tap(find.byKey(Key(key)));
    await settle(tester);
  }

  shadowTest('actividad', (tester) async {
    final r = await seeded(tester, 'rdm-b-actividad');
    await go(tester, r.c, '/operaciones');
    await shotWithEnd(tester, 'B_1.3_actividad');
    await top(tester);
    await tapKey(tester, 'activity-filter-purchases');
    await shot(tester, 'B_1.3_actividad_compras');
    await top(tester);
    await tapKey(tester, 'activity-filter-plans');
    await shot(tester, 'B_1.3_actividad_planes');
    await top(tester);
    await tapKey(tester, 'activity-filter-all');
    await tapKey(tester, 'activity-search-toggle');
    await tester.enterText(find.byKey(const Key('activity-search')), 'zzz');
    await shot(tester, 'B_1.3_actividad_busqueda_vacia');
  });

  shadowTest('actividad vacia', (tester) async {
    await setView(tester);
    final s = await activatedHousehold(tester, 'rdm-b-actividad-vacia');
    final c = await pumpModeApp(tester, s.database);
    await go(tester, c, '/operaciones');
    await shot(tester, 'B_1.3_actividad_vacia');
  });

  shadowTest('inicio vacio', (tester) async {
    await setView(tester);
    final s = await activatedHousehold(tester, 'rdm-b-inicio-vacio');
    final c = await pumpModeApp(tester, s.database);
    await go(tester, c, '/');
    await shot(tester, 'B_1.2_inicio_vacio');
  });
}
