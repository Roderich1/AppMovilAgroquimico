// Capturas del rediseño en el ARNÉS de pruebas (no en un teléfono): la app
// real sobre una base sintética, con las tipografías empaquetadas y los
// iconos de Material, a 390×844 dp (el tamaño de las láminas del prototipo).
// Sirven para revisar el diseño rápido y compararlo con la lámina; la
// verificación en el emulador es aparte.
//
//   flutter test tool/rediseno/capturas_arnes_test.dart
//   RDM_SHOTS=<carpeta> (por defecto build/rediseno_capturas)
//   RDM_TEXT_SCALE=1.3 para letra ampliada
//
// No es parte de la suite: vive en tool/ y sólo escribe imágenes.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/presentation/widgets/adaptive_entity_picker.dart';
import 'package:agroquimicos/voice/voice_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test/support/f04_mode_ui_harness.dart';
import '../../test/support/purchase_form_driver.dart';
import '../../test/voice/support/fake_speech_transcription_port.dart';

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
    Platform.environment['RDM_SHOTS'] ?? 'build/rediseno_capturas',
  )..createSync(recursive: true);
  final width =
      double.tryParse(Platform.environment['RDM_WIDTH'] ?? '') ?? 390.0;
  final scale =
      double.tryParse(Platform.environment['RDM_TEXT_SCALE'] ?? '') ?? 1.0;

  Future<void> shot(WidgetTester tester, String name) async {
    await settle(tester);
    // La vista entera (también las hojas modales y el botón flotante), no
    // sólo la página: se captura la capa raíz de la vista.
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    final bytes = await tester.runAsync(() async {
      // La capa raíz ya aplica la densidad: se recorta en píxeles físicos.
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
    final w = tester.widget<AdaptiveEntityPicker<Row>>(picker(label));
    w.onChanged(w.items.firstWhere((i) => w.labelOf(i) == name));
    await settle(tester);
  }

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  Future<void> tapKey(WidgetTester tester, String key) async {
    await preparePurchaseKey(tester, key);
    // Con la letra grande puede no estar construido todavía: desplazar.
    if (find.byKey(Key(key)).evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        find.byKey(Key(key)),
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.pump();
    await tester.tap(find.byKey(Key(key)));
    await settle(tester);
  }

  testWidgets('compra: recorrido de capturas', (tester) async {
    await tester.runAsync(_loadFonts);
    // Sombras reales: en las pruebas se dibujan como un borde negro.
    debugDisableShadows = false;
    tester.view.physicalSize = Size(width * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final s = await activatedHousehold(tester, 'rdm-shots');
    await tester.runAsync(() async {
      await s.household.repo.addSupplier(name: 'Agroinsumos del Valle');
      await s.household.repo.addProduct(name: 'Fungicida sistémico');
    });
    // Sin micrófono: el puerto falso no oye nada (no hay dictado en estas
    // capturas).
    // Un turno SINTÉTICO (texto inyectado, no reconocimiento) para ver la
    // revisión tras dictar: precio sin «el litro» → por revisar.
    final port = FakeSpeechTranscriptionPort(
      script: const [
        FakeTurn(
          segment:
              'compra de diez litros de Glifosato a 50 bolivianos, '
              'proveedor Agroinsumos del Valle',
          endsOnStop: true,
        ),
      ],
      repeatLast: false,
    );
    final c = await pumpModeApp(
      tester,
      s.database,
      extraOverrides: [
        speechPortFactoryProvider.overrideWith(
          (ref) =>
              () => port,
        ),
        wholeTurnPortFactoryProvider.overrideWith(
          (ref) =>
              () => port,
        ),
      ],
    );
    c.read(routerProvider).push('/compras/nueva');
    await waitFor(tester, find.byKey(const Key('purchase-add-line')));
    final tag =
        '${scale == 1.0 ? '' : '_x${scale.toString().replaceAll('.', '')}'}'
        '${width == 390 ? '' : '_w${width.round()}'}';

    await shot(tester, '2.1_paso1_vacio$tag');
    await tapKey(tester, 'compra-completar-voz');
    await shot(tester, '2.2_panel_voz$tag');
    await tapKey(tester, 'voz-hablar');
    await tapKey(tester, 'voz-terminar');
    await shot(tester, '2.5_tras_dictar_sintetico$tag');
    await tester.scrollUntilVisible(
      find.byKey(const Key('voz-descartar-price@1')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
    await shot(tester, '2.5b_revision_precio_sintetico$tag');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
    await settle(tester);
    await tapKey(tester, 'voz-deshacer');

    await choose(tester, 'Proveedor', 'Agroinsumos del Valle');
    await openPurchaseLine(tester);
    await choose(tester, 'Producto', 'Glifosato');
    await tester.enterText(field('Cantidad comprada'), '12');
    await tester.enterText(field('Precio por L'), '118');
    await settle(tester);
    await tapKey(tester, 'purchase-alloc-single-0');
    await choose(tester, 'Persona', 'Hermana');
    await shot(tester, '2.6_hoja_producto$tag');
    await tapKey(tester, 'purchase-line-next');
    await choose(tester, 'Producto', 'Fungicida sistémico');
    await tester.enterText(field('Cantidad comprada'), '4');
    await tester.enterText(field('Precio por L'), '150');
    await settle(tester);
    await tapKey(tester, 'purchase-alloc-split-1');
    await shot(tester, '2.6b_hoja_reparto$tag');
    await tapKey(tester, 'purchase-alloc-single-1');
    await choose(tester, 'Persona', 'Vecino');
    await closePurchaseLine(tester);
    await shot(tester, '2.1_paso1_lleno$tag');
    await tapKey(tester, 'purchase-continue');
    await shot(tester, '2.7_paso2$tag');
    await tapKey(tester, 'purchase-paid-yes');
    await shot(tester, '2.7b_paso2_pagado$tag');
    debugDisableShadows = true;
  });

  testWidgets('shell: barra, «Registrar» y Sindicato', (tester) async {
    await tester.runAsync(_loadFonts);
    // Sombras reales: en las pruebas se dibujan como un borde negro.
    debugDisableShadows = false;
    tester.view.physicalSize = Size(width * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    // Respaldos lee el directorio de la aplicación: uno temporal.
    final support = Directory.systemTemp.createTempSync('rdm-shell');
    addTearDown(() => support.deleteSync(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => support.path,
        );
    final s = await activatedHousehold(tester, 'rdm-shell');
    final c = await pumpModeApp(tester, s.database);
    final tag =
        '${scale == 1.0 ? '' : '_x${scale.toString().replaceAll('.', '')}'}'
        '${width == 390 ? '' : '_w${width.round()}'}';
    c.read(routerProvider).go('/operaciones');
    await settle(tester);
    await shot(tester, '1.2_actividad_barra$tag');
    await tester.tap(find.byKey(const Key('shell-registrar')));
    await settle(tester);
    await shot(tester, '1.7_registrar$tag');
    Navigator.of(tester.element(find.byKey(const Key('register-sheet')))).pop();
    await settle(tester);
    c.read(routerProvider).go('/sindicato');
    await settle(tester);
    await shot(tester, '1.6_sindicato$tag');
    c.read(routerProvider).go('/');
    await settle(tester);
    c.read(routerProvider).push('/mas');
    await settle(tester);
    await shot(tester, '7.1_ajustes$tag');
    c.read(routerProvider).push('/respaldo-remoto');
    await settle(tester);
    await shot(tester, '7.6_respaldos$tag');
    debugDisableShadows = true;
  });
}
