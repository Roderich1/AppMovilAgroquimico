// Capturas de la sesión A del MODO INDIVIDUAL (láminas I-10 a I-24): compra,
// voz, aplicación y plan en el ARNÉS de pruebas (no en un teléfono), sobre un
// hogar sintético que cumple las condiciones del modo individual.
//
//   flutter test tool/rediseno/capturas_ind_a_test.dart
//   RDM_SHOTS=<carpeta> (por defecto build/capturas_ind_a)
//   RDM_TEXT_SCALE=1.3 / 2.0 para letra ampliada; RDM_WIDTH=900 para ancha
//
// Los dictados son TEXTO INYECTADO por el puerto falso (sintético), no
// reconocimiento real. No es parte de la suite: vive en tool/ y sólo escribe
// imágenes.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/presentation/widgets/adaptive_entity_picker.dart';
import 'package:agroquimicos/voice/port/speech_transcription_port.dart';
import 'package:agroquimicos/voice/voice_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test/support/f04_mode_ui_harness.dart';
import '../../test/support/ind_a_household.dart';
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
    Platform.environment['RDM_SHOTS'] ?? 'build/capturas_ind_a',
  )..createSync(recursive: true);
  final width =
      double.tryParse(Platform.environment['RDM_WIDTH'] ?? '') ?? 390.0;
  final scale =
      double.tryParse(Platform.environment['RDM_TEXT_SCALE'] ?? '') ?? 1.0;
  final tag =
      '${scale == 1.0 ? '' : '_x${scale.toString().replaceAll('.', '')}'}'
      '${width == 390 ? '' : '_w${width.round()}'}';

  void shotsTest(String name, Future<void> Function(WidgetTester) body) =>
      testWidgets(name, (tester) async {
        debugDisableShadows = false;
        try {
          await body(tester);
        } finally {
          debugDisableShadows = true;
        }
      });

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

  Finder picker(String label) => find.byWidgetPredicate(
    (w) => w is AdaptiveEntityPicker<Row> && w.label == label,
  );
  Future<void> choose(WidgetTester tester, String label, String name) async {
    if (picker(label).evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        picker(label),
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }
    final w = tester.widget<AdaptiveEntityPicker<Row>>(picker(label).last);
    w.onChanged(w.items.firstWhere((i) => w.labelOf(i) == name));
    await settle(tester);
  }

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );

  Future<void> tapKey(WidgetTester tester, String key) async {
    await preparePurchaseKey(tester, key);
    if (find.byKey(Key(key)).evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        find.byKey(Key(key)),
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(find.byKey(Key(key)).last);
    await tester.pump();
    await tester.tap(find.byKey(Key(key)).last);
    await settle(tester);
  }

  Future<
    ({
      AppDatabase database,
      IndAHousehold h,
      ProviderContainer c,
      FakeSpeechTranscriptionPort port,
    })
  >
  open(
    WidgetTester tester,
    String name,
    String route,
    Finder ready, {
    List<FakeTurn> script = const [],
  }) async {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = Size(width * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final s = await personalHousehold(tester, name);
    final port = FakeSpeechTranscriptionPort(script: script, repeatLast: false);
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
    c.read(routerProvider).push(route);
    await waitFor(tester, ready);
    await settle(tester);
    return (database: s.database, h: s.household, c: c, port: port);
  }

  shotsTest('I-10/I-11/I-12: compra individual con dos productos', (
    tester,
  ) async {
    await open(
      tester,
      'ind-a-compra',
      '/compras/nueva',
      find.byKey(const Key('purchase-add-line')),
    );
    await choose(tester, 'Proveedor', 'Agroinsumos');
    await openPurchaseLine(tester);
    await shot(tester, 'I-11a_hoja_vacia');
    await choose(tester, 'Producto', 'Herbicida');
    await tester.enterText(field('Cantidad comprada'), '12');
    await tester.enterText(field('Precio por L'), '118');
    await settle(tester);
    await tapKey(tester, 'purchase-line-next');
    await choose(tester, 'Producto', 'Fungicida');
    await tester.enterText(field('Cantidad comprada'), '4');
    await tester.enterText(field('Precio por L'), '150');
    await settle(tester);
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester);
    await shot(tester, 'I-11_hoja_producto');
    // Con el teclado: cantidad enfocada y un teclado de 336 dp.
    await tester.tap(find.byKey(const Key('purchase-quantity-1')));
    tester.view.viewInsets = const FakeViewPadding(bottom: 336 * 2);
    await settle(tester);
    await shot(tester, 'I-11k_hoja_teclado');
    tester.view.resetViewInsets();
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester);
    await closePurchaseLine(tester);
    await shot(tester, 'I-10_paso1');
    await tapKey(tester, 'purchase-continue');
    await shot(tester, 'I-12_revision');
    await tapKey(tester, 'purchase-paid-no');
    await shot(tester, 'I-12b_revision_todavia_no');
    await tapKey(tester, 'purchase-paid-yes');
    await shot(tester, 'I-12c_revision_pagado');
  });

  shotsTest('I-13/I-14/I-15: voz en la compra individual', (tester) async {
    // Dictado sintético: el precio del Herbicida falta (I-15) y se nombra a
    // una persona que no existe (no debe crearse ni asignarse).
    final w = await open(
      tester,
      'ind-a-voz',
      '/compras/nueva',
      find.byKey(const Key('compra-completar-voz')),
      script: [
        FakeTurn(
          segment:
              'compra a Agroinsumos de cuatro litros de Fungicida a 150 '
              'bolivianos el litro y doce litros de Herbicida, todo para '
              'Beto Mamani',
          endsOnStop: true,
        ),
        // Segundo dictado: se queda escuchando; el arnés lo pasa a
        // «Procesando» y se cancela (I-14).
        FakeTurn(silent: true),
      ],
    );
    await tapKey(tester, 'compra-completar-voz');
    await shot(tester, 'I-13a_panel_voz');
    await tapKey(tester, 'voz-hablar');
    await shot(tester, 'I-13_escuchando');
    await tapKey(tester, 'voz-terminar');
    await shot(tester, 'I-15_revisar_tras_dictar');
    await tapKey(tester, 'voz-dictar-mas');
    await tapKey(tester, 'voz-hablar');
    w.port.emitForTest(
      const TranscriptionStageChanged(TranscriptionStage.processing),
    );
    await settle(tester);
    await shot(tester, 'I-14_procesando');
    await tapKey(tester, 'voz-cancelar-dictado');
    await shot(tester, 'I-14b_cancelado');
  });

  shotsTest('I-20/I-21/I-22: aplicación individual', (tester) async {
    await open(
      tester,
      'ind-a-aplicacion',
      '/aplicaciones/nueva',
      find.byKey(const Key('application-step')),
    );
    await shot(tester, 'I-20a_paso1_vacio');
    await choose(tester, 'Chaco', 'Chaco Norte');
    await shot(tester, 'I-20_paso1');
    await tapKey(tester, 'application-continue');
    await tapKey(tester, 'application-add-product');
    await choose(tester, 'Producto', 'Herbicida');
    await tester.tap(find.byKey(const Key('application-line-quantity')));
    await tester.enterText(
      find.byKey(const Key('application-line-quantity')),
      '2',
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 336 * 2);
    await settle(tester);
    await shot(tester, 'I-21_teclado');
    tester.view.resetViewInsets();
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester);
    await tapKey(tester, 'application-line-add');
    await shot(tester, 'I-20b_paso2');
    await tapKey(tester, 'application-continue');
    await shot(tester, 'I-22_revision');
  });

  shotsTest('I-23/I-24: plan individual', (tester) async {
    await open(
      tester,
      'ind-a-plan',
      '/planificacion/nueva',
      find.byKey(const Key('plan-header')),
    );
    await shot(tester, 'I-23a_vacio');
    await choose(tester, 'Chaco', 'Chaco Norte');
    await choose(tester, 'Agregar producto', 'Fungicida');
    await tester.tap(find.byTooltip('Agregar al plan'));
    await settle(tester);
    final doses = find.byWidgetPredicate(
      (w) =>
          w is TextField && (w.decoration?.labelText ?? '').startsWith('Dosis'),
    );
    await tester.enterText(doses.at(0), '2');
    await settle(tester);
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester);
    await shot(tester, 'I-23_plan');
    await tapKey(tester, 'plan-continue');
    await shot(tester, 'I-24_revision');
  });
}
