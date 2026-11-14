// Capturas del orquestador del modo individual (láminas I-01, I-02, I-03,
// I-50, I-51, I-52 e I-53) en el ARNÉS de pruebas, no en un teléfono: la app
// real sobre una base SINTÉTICA, con las tipografías empaquetadas.
//
//   flutter test tool/rediseno/capturas_ind_orq_test.dart
//   RDM_SHOTS=<carpeta> (por defecto build/capturas_ind_orq)
//   RDM_TEXT_SCALE=1.3 | 2.0 para letra ampliada
//   RDM_WIDTH=900 para una vista ancha
//
// No es parte de la suite: vive en tool/ y sólo escribe imágenes.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/presentation/widgets/ind_connection_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test/support/f04_mode_ui_harness.dart';

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
    Platform.environment['RDM_SHOTS'] ?? 'build/capturas_ind_orq',
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

  void setUpView(WidgetTester tester) {
    debugDisableShadows = false;
    tester.view.physicalSize = Size(width * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  testWidgets('individual: Inicio vacío (I-02)', (tester) async {
    await tester.runAsync(_loadFonts);
    setUpView(tester);
    final s = await activatedHousehold(tester, 'ind-orq-vacio');
    await tester.runAsync(
      () =>
          OperationModeStore(s.database)
              .apply(OperationMode.personal, confirmed: true),
    );
    await pumpModeApp(tester, s.database);
    await shot(tester, 'o02_inicio_vacio');
    debugDisableShadows = true;
  });

  testWidgets('individual: Inicio, Registrar, Ajustes, Modo, envíos', (
    tester,
  ) async {
    await tester.runAsync(_loadFonts);
    setUpView(tester);
    final s = await activatedHousehold(tester, 'ind-orq-datos');
    final h = s.household;
    await tester.runAsync(() async {
      // Dos compras a crédito (una con pago parcial) y una aplicación.
      final first = await h.buy(h.titular, 20000);
      await h.buy(h.titular, 5000, date: DateTime.utc(2026, 1, 10));
      await h.repo.addProviderPayment(
        purchaseId: first,
        payerPersonId: h.titular,
        amountBobMinor: 100000,
        method: PaymentMethod.cash,
      );
      await h.apply(h.titular, h.titularFarm, 4000);
      await OperationModeStore(s.database)
          .apply(OperationMode.personal, confirmed: true);
    });
    final c = await pumpModeApp(tester, s.database);
    await shot(tester, 'o01_inicio');

    c.read(routerProvider).go('/operaciones');
    await settle(tester);
    await tester.tap(find.byKey(const Key('shell-registrar')));
    await settle(tester);
    await shot(tester, 'o03_registrar');
    await tester.tap(find.byKey(const Key('register-close')));
    await settle(tester);

    c.read(routerProvider).push('/mas');
    await settle(tester);
    await shot(tester, 'o50_ajustes');

    c.read(routerProvider).push('/modo');
    await settle(tester);
    await shot(tester, 'o51_modo_disponible');
    c.read(routerProvider).pop();
    await settle(tester);
    c.read(routerProvider).pop();
    await settle(tester);

    c.read(routerProvider).go('/sindicato');
    await settle(tester);
    // La hoja se abre desde el indicador «Sindicato · N pendientes»; sin
    // envíos en la base sintética se abre directamente (estado vacío).
    showIndConnectionSheet(tester.element(find.byType(Scaffold).first));
    await settle(tester);
    await shot(tester, 'o53_envios_vacio');
    debugDisableShadows = true;
  });

  testWidgets('varias personas: Modo bloqueado (I-52)', (tester) async {
    await tester.runAsync(_loadFonts);
    setUpView(tester);
    final s = await activatedHousehold(tester, 'ind-orq-bloqueo');
    final h = s.household;
    await tester.runAsync(() async {
      await h.buy(h.relative, 3000);
      await h.buy(h.thirdParty, 2000);
    });
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).push('/modo');
    await settle(tester);
    await shot(tester, 'o52_modo_bloqueado');
    debugDisableShadows = true;
  });
}
