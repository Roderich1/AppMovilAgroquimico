// Capturas de «Chacos» del modo individual (sesión C, 2026-11-13; láminas
// I-40 a I-43) en el ARNÉS de pruebas, no en un teléfono: la app real sobre
// una base SINTÉTICA en modo individual, con las tipografías empaquetadas.
//
//   flutter test tool/rediseno/capturas_ind_c_test.dart
//   RDM_SHOTS=<carpeta> (por defecto build/rediseno_capturas_ind_c)
//   RDM_TEXT_SCALE=1.3 / 2.0 para letra ampliada; RDM_WIDTH=900 para ancho
//
// No es parte de la suite: vive en tool/ y sólo escribe imágenes.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test/support/f04_app_access.dart';
import '../../test/support/f04_mode_fixtures.dart';
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

/// Base sintética en modo individual: titular con «Chaco Norte» (3 ha, dos
/// aplicaciones de herbicida con superficie tratada y una de fertilizante en
/// kg sin superficie, un plan de fungicida por hacer) y un chaco de nombre
/// largo sin aplicaciones. [withFarms] en falso deja la base sin chacos.
Future<({dynamic database, int norte})> _seed(
  WidgetTester tester,
  String name, {
  bool withFarms = true,
}) async {
  final file = await tester.runAsync(() => tempDbPath(name));
  final database = openDb(file!);
  final norte = await tester.runAsync(() async {
    final binding = await seedActivatedInstallation(database);
    final repo = AgroRepository(database);
    final owner = binding.personId;
    final campaign = await repo.addCampaign(
      name: 'Invierno 2026',
      start: DateTime.utc(2026, 1, 1),
    );
    var norte = 0;
    if (withFarms) {
      final supplier = await repo.addSupplier(name: 'Agroservicios del Norte');
      final herbicida = await repo.addProduct(name: 'Herbicida');
      final fungicida = await repo.addProduct(name: 'Fungicida');
      final fertilizante = await repo.addProduct(
        name: 'Fertilizante foliar',
        unit: 'KG',
      );
      norte = await repo.addFarm(
        ownerId: owner,
        name: 'Chaco Norte',
        areaM2: 30000,
      );
      await repo.addFarm(
        ownerId: owner,
        name: 'Chaco de la loma grande junto al río Piraí',
        areaM2: 5000,
      );
      PurchaseItemDraft item(int product, int quantity, int price) =>
          PurchaseItemDraft(
            productId: product,
            quantityBase: quantity,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: price,
            allocations: [
              AllocationDraft(personId: owner, quantityBase: quantity),
            ],
          );
      await repo.confirmPurchase(
        PurchaseDraft(
          supplierId: supplier,
          campaignId: campaign,
          purchaseDate: DateTime.utc(2026, 10, 1),
          items: [
            item(herbicida, 10000, 12000),
            item(fungicida, 6000, 9000),
            item(fertilizante, 4000, 5000),
          ],
        ),
      );
      Future<void> apply(
        DateTime date,
        int product,
        int quantity, {
        int? treated,
      }) => repo
          .confirmApplication(
            ApplicationDraft(
              personId: owner,
              farmId: norte,
              campaignId: campaign,
              appliedAt: date,
              treatedAreaM2: treated,
              lines: [
                ApplicationLineDraft(
                  productId: product,
                  quantityBase: quantity,
                ),
              ],
            ),
          )
          .then((_) {});
      await apply(DateTime(2026, 10, 20, 12), herbicida, 6000, treated: 30000);
      await apply(DateTime(2026, 11, 1, 12), herbicida, 2000, treated: 10000);
      await apply(DateTime(2026, 11, 5, 12), fertilizante, 1000);
      await repo.addPlan(
        farmId: norte,
        campaignId: campaign,
        productId: fungicida,
        areaM2: 30000,
        doseBasePerHa: 2000,
        plannedDate: DateTime(2026, 11, 20),
      );
    }
    await OperationModeStore(database)
        .apply(OperationMode.personal, confirmed: true);
    return norte;
  });
  return (database: database, norte: norte!);
}

void main() {
  sqfliteFfiInit();
  final out = Directory(
    Platform.environment['RDM_SHOTS'] ?? 'build/rediseno_capturas_ind_c',
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

  Future<void> setUp(WidgetTester tester) async {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = Size(width * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Future<void> bottom(WidgetTester tester) async {
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -4000));
    await settle(tester);
  }

  testWidgets('I-40, I-41, I-42 con datos', (tester) async {
    await setUp(tester);
    final w = await _seed(tester, 'ind-c-shots');
    final c = await pumpModeApp(tester, w.database);

    c.read(routerProvider).go('/chacos');
    await waitFor(tester, find.byKey(const Key('ind-chacos-costos')));
    await shot(tester, 'i40_chacos');

    c.read(routerProvider).go('/chacos/${w.norte}');
    await waitFor(tester, find.byKey(const Key('ind-chaco-costo')));
    await shot(tester, 'i41_chaco_detalle');
    await bottom(tester);
    await shot(tester, 'i41b_chaco_detalle_final');

    final costs = find.byKey(const Key('ind-chaco-ver-costos'));
    await tester.ensureVisible(costs);
    await tester.pump();
    await tester.tap(costs);
    await waitFor(tester, find.byKey(const Key('ind-costos-hero')));
    await shot(tester, 'i42_costos_por_chaco');
    await tester.tap(find.byKey(const Key('ind-costos-por-producto')));
    await shot(tester, 'i42b_costos_por_producto');
    await tester.tap(find.byKey(const Key('ind-costos-por-campana')));
    await shot(tester, 'i42c_costos_por_campana');
  });

  testWidgets('I-43 sin chacos', (tester) async {
    await setUp(tester);
    final w = await _seed(tester, 'ind-c-shots-empty', withFarms: false);
    final c = await pumpModeApp(tester, w.database);
    c.read(routerProvider).go('/chacos');
    await waitFor(tester, find.text('Agregue su primer chaco'));
    await shot(tester, 'i43_chacos_vacio');
  });
}
