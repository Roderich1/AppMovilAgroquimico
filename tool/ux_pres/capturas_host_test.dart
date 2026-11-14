// Capturas HOST comparables de la presentación móvil (2026-11-05). La app
// real (AgroApp, repositorio real, base SQLite en archivo) con los mismos
// datos sintéticos en cualquier commit: sirve para el «antes» (base de la
// rama) y el «después». Fuente Roboto real e iconos Material, 393×873 dp a
// 2,75 (el ancho del POCO). No es una prueba: guarda PNG en UXP_OUT.
//
//   UXP_OUT=/ruta/absoluta flutter test tool/ux_pres/capturas_host_test.dart
//
// Cada vista se captura si existe en el commit (p. ej. «Campañas» o la fila
// «Crear producto» sólo existen en la rama) y se anota en UXP_OUT/vistas.txt.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/presentation/widgets/adaptive_entity_picker.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' show FocusManager, FocusHighlightStrategy;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test/support/f04_mode_ui_harness.dart';

typedef Row = Map<String, Object?>;

const _size = Size(393, 873);
const _ratio = 2.75;

void main() {
  sqfliteFfiInit();
  final out = Platform.environment['UXP_OUT'];

  setUpAll(() async {
    final roboto = FontLoader('Roboto');
    for (final name in ['regular', 'medium', 'bold']) {
      final bytes = File('test/fonts/roboto-$name.ttf').readAsBytesSync();
      roboto.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await roboto.load();
    // Los iconos Material vienen con el SDK de Flutter, junto al motor.
    final engine = File(Platform.resolvedExecutable).parent;
    var dir = engine;
    while (!Directory(p.join(dir.path, 'material_fonts')).existsSync()) {
      dir = dir.parent;
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File(
              p.join(dir.path, 'material_fonts', 'materialicons-regular.otf'),
            ).readAsBytesSync(),
          ),
        ),
      );
    await icons.load();
  });

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 400));
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    final bytes = await tester.runAsync(() async {
      // La capa raíz ya escala por la densidad: sus límites van en píxeles
      // físicos y la imagen sale a escala 1.
      final image = await layer.toImage(Offset.zero & (view.size * _ratio));
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    File(p.join(out!, '$name.png')).writeAsBytesSync(bytes!);
    File(p.join(out, 'vistas.txt'))
        .writeAsStringSync('$name\n', mode: FileMode.append);
  }

  Future<ProviderContainer> app(WidgetTester tester, String name) async {
    tester.view.physicalSize = _size * _ratio;
    tester.view.devicePixelRatio = _ratio;
    addTearDown(tester.view.reset);
    final s = await activatedHousehold(tester, name);
    await tester.runAsync(() async {
      final h = s.household;
      await h.repo.addProduct(name: 'Mancozeb', unit: 'KG');
      await h.buy(h.titular, 2000);
      await h.apply(h.titular, h.titularFarm, 500);
    });
    return pumpModeApp(tester, s.database);
  }

  Finder picker(String label) => find.byWidgetPredicate(
    (w) => w is AdaptiveEntityPicker<Row> && w.label == label,
  );

  testWidgets('capturas', (tester) async {
    expect(out, isNotNull, reason: 'Defina UXP_OUT');
    // Como en un teléfono: sin el resaltado de foco de escritorio.
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTouch;
    Directory(out!).createSync(recursive: true);
    final c = await app(tester, 'capturas');
    final router = c.read(routerProvider);

    Future<void> go(String path, String name) async {
      router.go(path);
      await settle(tester);
      await shot(tester, name);
    }

    await go('/operaciones', '01_operaciones');
    await tester.tap(find.byTooltip('Registrar operación'));
    await settle(tester);
    await shot(tester, '02_operaciones_mas_registrar');
    await tester.tapAt(const Offset(200, 60));
    await settle(tester);
    await go('/mas', '03_mas');
    await go('/compras', '04_compras');
    await go('/aplicaciones', '05_aplicaciones');
    await go('/planificacion', '06_planificacion');
    await go('/catalogos', '07_catalogos');
    // Campañas sólo existe con su pantalla propia (en la rama).
    if (File('lib/presentation/screens/campaigns_screen.dart').existsSync()) {
      await go('/campanas', '08_campanas');
    }

    await go('/operaciones', '_');
    router.push('/compras/nueva');
    await waitFor(tester, picker('Producto'));
    await settle(tester);
    await shot(tester, '10_compra');
    await tester.tap(picker('Producto'));
    await settle(tester);
    await shot(tester, '11_compra_selector_producto');
    if (find.text('Crear producto').evaluate().isNotEmpty) {
      await tester.tap(find.text('Crear producto'));
      await settle(tester);
      await shot(tester, '12_compra_crear_producto');
      await tester.tap(find.text('Cancelar'));
    } else {
      await tester.tapAt(const Offset(200, 60));
    }
    await settle(tester);

    router.pop();
    await settle(tester);
    router.push('/planificacion/nueva');
    await waitFor(tester, picker('Chaco'));
    await settle(tester);
    await shot(tester, '13_planificacion_form');
    router.pop();
    await settle(tester);
    router.push('/aplicaciones/nueva');
    await waitFor(tester, picker('Chaco'));
    await settle(tester);
    await shot(tester, '14_aplicacion_form');
  });
}
