// Capturas de la sesión A del rediseño (aplicación y planificación) en el
// ARNÉS de pruebas (no en un teléfono): la app real sobre una base
// sintética, con las tipografías empaquetadas, a 390×844 dp. Sirven para
// comparar con las láminas Aplicacion1–3, VozAplicacion, Plan y VozPlan.
//
//   flutter test tool/rediseno/capturas_a_test.dart
//   RDM_SHOTS=<carpeta> (por defecto build/rediseno_capturas_a)
//   RDM_TEXT_SCALE=1.3 / 2.0 para letra ampliada; RDM_WIDTH=360
//
// El dictado es un turno SINTÉTICO (texto inyectado, sin reconocimiento ni
// audio): sólo muestra cómo quedan los estados tras dictar. No mide la voz.
// No es parte de la suite: vive en tool/ y sólo escribe imágenes.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/presentation/widgets/adaptive_entity_picker.dart';
import 'package:agroquimicos/voice/voice_providers.dart';
import 'package:agroquimicos/presentation/screens/application_form_screen.dart'
    show applicationPersonLabel;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test/support/f04_mode_fixtures.dart';
import '../../test/support/f04_mode_ui_harness.dart';
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

/// Compra sintética de [product] para [person] (precio 120 Bs por unidad).
Future<void> _buy(
  Household h, {
  required int person,
  required int product,
  required int quantity,
}) => h.repo.confirmPurchase(
  PurchaseDraft(
    supplierId: h.supplier,
    campaignId: h.campaign,
    purchaseDate: DateTime.utc(2026, 1, 2),
    items: [
      PurchaseItemDraft(
        productId: product,
        quantityBase: quantity,
        currency: CurrencyCode.bob,
        originalUnitPriceMinor: 12000,
        allocations: [
          AllocationDraft(personId: person, quantityBase: quantity),
        ],
      ),
    ],
  ),
);

void main() {
  sqfliteFfiInit();
  final out = Directory(
    Platform.environment['RDM_SHOTS'] ?? 'build/rediseno_capturas_a',
  )..createSync(recursive: true);
  final width =
      double.tryParse(Platform.environment['RDM_WIDTH'] ?? '') ?? 390.0;
  final scale =
      double.tryParse(Platform.environment['RDM_TEXT_SCALE'] ?? '') ?? 1.0;
  final tag =
      '${scale == 1.0 ? '' : '_x${scale.toString().replaceAll('.', '')}'}'
      '${width == 390 ? '' : '_w${width.round()}'}';

  /// Una prueba de capturas con las sombras reales (las pruebas las
  /// desactivan por omisión; sin ellas el botón flotante sale con borde
  /// negro). Se restablecen al terminar, como en `capturas_arnes_test.dart`.
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
    // La vista entera (también las hojas modales y los diálogos), no sólo la
    // página: se captura la capa raíz de la vista (como el arnés de B1).
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
    File('${out.path}/$name$tag.png').writeAsBytesSync(bytes!);
  }

  Finder picker(String label) => find.byWidgetPredicate(
    (w) => w is AdaptiveEntityPicker<Row> && w.label == label,
  );
  Future<void> choose(WidgetTester tester, String label, String name) async {
    // Con la letra grande puede no estar construido todavía: desplazar.
    if (picker(label).evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        picker(label),
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }
    final w = tester.widget<AdaptiveEntityPicker<Row>>(picker(label));
    w.onChanged(w.items.firstWhere((i) => w.labelOf(i) == name));
    await settle(tester);
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
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

  Future<void> top(WidgetTester tester) async {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await settle(tester);
  }

  Future<({dynamic database, Household h, FakeSpeechTranscriptionPort port})>
  setUp(WidgetTester tester, String name, List<FakeTurn> script) async {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = Size(width * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final s = await activatedHousehold(tester, name);
    final h = s.household;
    await tester.runAsync(() async {
      final herbicida = await h.repo.addProduct(name: 'Herbicida selectivo');
      final insecticida = await h.repo.addProduct(name: 'Insecticida');
      await _buy(h, person: h.titular, product: h.product, quantity: 5000);
      await _buy(h, person: h.relative, product: h.product, quantity: 11000);
      await _buy(h, person: h.relative, product: herbicida, quantity: 4000);
      await _buy(h, person: h.titular, product: insecticida, quantity: 1000);
    });
    final port = FakeSpeechTranscriptionPort(script: script, repeatLast: false);
    return (database: s.database, h: h, port: port);
  }

  Future<void> open(
    WidgetTester tester,
    dynamic database,
    FakeSpeechTranscriptionPort port,
    String route,
  ) async {
    final c = await pumpModeApp(
      tester,
      database,
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
    await waitFor(
      tester,
      find.byKey(
        Key(
          route.startsWith('/planificacion')
              ? 'plan-header'
              : 'application-step',
        ),
      ),
    );
    await settle(tester);
  }

  shotsTest('aplicación: recorrido de capturas', (tester) async {
    final s = await setUp(tester, 'rdm-a-aplicacion', const []);
    await open(tester, s.database, s.port, '/aplicaciones/nueva');

    await shot(tester, '3.1_paso1_vacio');
    await tapKey(tester, 'aplicacion-completar-voz');
    await shot(tester, '3.1v_panel_voz');
    await tapKey(tester, 'voz-panel-cerrar');

    await choose(tester, applicationPersonLabel, 'Hermana');
    await choose(tester, 'Chaco', 'Chaco hermana');
    await shot(tester, '3.1b_paso1_lleno');

    await tapKey(tester, 'application-continue');
    await shot(tester, '3.2_paso2_vacio');
    await tapKey(tester, 'application-add-product');
    await choose(tester, 'Producto', 'Herbicida selectivo');
    await tester.enterText(
      find.byKey(const Key('application-line-quantity')),
      '2',
    );
    await settle(tester);
    await shot(tester, '3.2h_hoja_producto');
    await tapKey(tester, 'application-line-add');
    await tapKey(tester, 'application-add-product');
    await choose(tester, 'Producto', 'Glifosato');
    await tester.enterText(
      find.byKey(const Key('application-line-quantity')),
      '20',
    );
    await settle(tester);
    await shot(tester, '3.2i_hoja_sin_existencias');
    await tester.enterText(
      find.byKey(const Key('application-line-quantity')),
      '1,5',
    );
    await settle(tester);
    await tapKey(tester, 'application-line-add');
    await top(tester);
    await shot(tester, '3.2b_paso2_mezcla');
    final herbicida = tester
        .widgetList<Card>(find.byType(Card))
        .map((c) => (c.key as ValueKey<String>?)?.value ?? '')
        .firstWhere((k) => k.startsWith('application-line-'));
    await tapKey(
      tester,
      herbicida.replaceFirst('application-line-', 'application-line-detail-'),
    );
    await shot(tester, '3.2d_dosis_y_costo');

    await tapKey(tester, 'application-continue');
    await shot(tester, '3.3_paso3_resumen');
    await tapKey(tester, 'application-cost-help');
    await shot(tester, '3.3b_paso3_ayuda_costo');
  });

  shotsTest('aplicación: voz (dictado sintético) y conflicto de chaco', (
    tester,
  ) async {
    const full =
        'apliqué dos litros de Glifosato en el chaco titular en media hectárea';
    final s = await setUp(tester, 'rdm-a-voz', const [
      FakeTurn(segment: full, endsOnStop: true),
      FakeTurn(segment: full, endsOnStop: true),
    ]);
    await open(tester, s.database, s.port, '/aplicaciones/nueva');
    await tapKey(tester, 'aplicacion-completar-voz');
    await tapKey(tester, 'voz-hablar');
    await tapKey(tester, 'voz-terminar');
    await settle(tester);
    await shot(tester, '3.1s_tras_dictar_sintetico');
    await tapKey(tester, 'application-continue');
    await shot(tester, '3.2s_paso2_tras_dictar_sintetico');
    await tapKey(tester, 'application-back');
    // Otra persona elegida y el mismo dictado: el chaco no se cambia solo.
    await tapKey(tester, 'voz-deshacer');
    await choose(tester, applicationPersonLabel, 'Hermana');
    await tapKey(tester, 'form-dictar');
    await tapKey(tester, 'voz-hablar');
    await tapKey(tester, 'voz-terminar');
    await settle(tester);
    await shot(tester, '3.1c_conflicto_chaco_sintetico');
  });

  shotsTest('aplicación desde un plan: persona y chaco fijos, sin voz', (
    tester,
  ) async {
    final s = await setUp(tester, 'rdm-a-plan', const []);
    final planId = await tester.runAsync(
      () => s.h.repo.addPlanMulti(
        farmId: s.h.titularFarm,
        campaignId: s.h.campaign,
        areaM2: 10000,
        items: [PlanItemDraft(productId: s.h.product, doseBasePerHa: 1500)],
      ),
    );
    await open(
      tester,
      s.database,
      s.port,
      '/aplicaciones/nueva?planId=$planId',
    );
    await shot(tester, '3.1p_paso1_desde_plan');
    await tapKey(tester, 'application-continue');
    await shot(tester, '3.2p_paso2_desde_plan');
  });

  shotsTest('plan: recorrido de capturas', (tester) async {
    final s = await setUp(tester, 'rdm-a-plan-nuevo', const []);
    await open(tester, s.database, s.port, '/planificacion/nueva');
    await shot(tester, '3.5_plan_vacio');
    await tapKey(tester, 'plan-completar-voz');
    await shot(tester, '3.6_plan_panel_voz');
    await tapKey(tester, 'voz-panel-cerrar');
    await choose(tester, 'Chaco', 'Chaco hermana');
    await choose(tester, 'Agregar producto', 'Herbicida selectivo');
    await tester.tap(find.byTooltip('Agregar al plan'));
    await settle(tester);
    await choose(tester, 'Agregar producto', 'Insecticida');
    await tester.tap(find.byTooltip('Agregar al plan'));
    await settle(tester);
    final doses = find.byWidgetPredicate(
      (w) =>
          w is TextField && (w.decoration?.labelText ?? '').startsWith('Dosis'),
    );
    await tester.enterText(doses.at(0), '2');
    await tester.enterText(doses.at(1), '1');
    await settle(tester);
    await shot(tester, '3.5b_plan_lleno');
  });

  shotsTest('plan: voz (dictado sintético) y conflicto de chaco', (
    tester,
  ) async {
    const full =
        'planificar el chaco titular con dos litros por hectárea de Glifosato';
    final s = await setUp(tester, 'rdm-a-plan-voz', const [
      FakeTurn(segment: full, endsOnStop: true),
      FakeTurn(segment: full, endsOnStop: true),
    ]);
    await open(tester, s.database, s.port, '/planificacion/nueva');
    await tapKey(tester, 'plan-completar-voz');
    await tapKey(tester, 'voz-hablar');
    await tapKey(tester, 'voz-terminar');
    await settle(tester);
    await shot(tester, '3.6s_plan_tras_dictar_sintetico');
    await tapKey(tester, 'voz-deshacer');
    await choose(tester, 'Chaco', 'Chaco hermana');
    await tapKey(tester, 'form-dictar');
    await tapKey(tester, 'voz-hablar');
    await tapKey(tester, 'voz-terminar');
    await settle(tester);
    await shot(tester, '3.6c_plan_conflicto_sintetico');
  });

  shotsTest('listas: aplicaciones y planificación', (tester) async {
    final s = await setUp(tester, 'rdm-a-listas', const []);
    final h = s.h;
    await tester.runAsync(() async {
      await h.repo.confirmApplication(
        ApplicationDraft(
          personId: h.relative,
          farmId: h.relativeFarm,
          campaignId: h.campaign,
          appliedAt: DateTime.now(),
          lines: [
            ApplicationLineDraft(productId: h.product, quantityBase: 1500),
          ],
        ),
      );
      final applied = await h.repo.addPlanMulti(
        farmId: h.titularFarm,
        campaignId: h.campaign,
        areaM2: 10000,
        items: [PlanItemDraft(productId: h.product, doseBasePerHa: 1000)],
      );
      await h.repo.confirmApplication(
        ApplicationDraft(
          personId: h.titular,
          farmId: h.titularFarm,
          campaignId: h.campaign,
          appliedAt: DateTime.now(),
          planId: applied,
          lines: [
            ApplicationLineDraft(productId: h.product, quantityBase: 1000),
          ],
        ),
      );
      await h.repo.addPlanMulti(
        farmId: h.relativeFarm,
        campaignId: h.campaign,
        areaM2: 5000,
        items: [PlanItemDraft(productId: h.product, doseBasePerHa: 2000)],
      );
    });
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).go('/aplicaciones');
    await waitFor(tester, find.byKey(const Key('applications-register')));
    await settle(tester);
    await shot(tester, '3.7_lista_aplicaciones');
    c.read(routerProvider).go('/planificacion');
    await waitFor(tester, find.byKey(const Key('planning-new')));
    await settle(tester);
    await tester.tap(find.byType(ExpansionTile).first);
    await settle(tester);
    await shot(tester, '3.8_lista_planes');
    await tester.tap(find.text('Mostrar planes aplicados'));
    await settle(tester);
    await shot(tester, '3.8b_lista_planes_con_aplicados');
  });

  shotsTest('personas: bitácora del chaco', (tester) async {
    final s = await setUp(tester, 'rdm-a-bitacora', const []);
    final h = s.h;
    await tester.runAsync(() async {
      for (final quantity in [1500, 2000]) {
        await h.repo.confirmApplication(
          ApplicationDraft(
            personId: h.relative,
            farmId: h.relativeFarm,
            campaignId: h.campaign,
            appliedAt: DateTime.now(),
            lines: [
              ApplicationLineDraft(
                productId: h.product,
                quantityBase: quantity,
                treatedAreaM2: 5000,
                doseBasePerHa: 3000,
                theoreticalQuantityBase: 1500,
              ),
            ],
          ),
        );
      }
    });
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).go('/personas');
    await settle(tester);
    c.read(routerProvider).push('/chacos/${h.relativeFarm}');
    await waitFor(tester, find.byType(ExpansionTile));
    await settle(tester);
    await shot(tester, '5.7_bitacora');
    await tester.tap(find.byType(ExpansionTile).first);
    await settle(tester);
    await shot(tester, '5.7b_bitacora_detalle');
  });

  shotsTest('personas: detalle de persona', (tester) async {
    final s = await setUp(tester, 'rdm-a-persona', const []);
    final h = s.h;
    await tester.runAsync(
      () => h.repo.confirmApplication(
        ApplicationDraft(
          personId: h.relative,
          farmId: h.relativeFarm,
          campaignId: h.campaign,
          appliedAt: DateTime.now(),
          lines: [
            ApplicationLineDraft(productId: h.product, quantityBase: 2000),
          ],
        ),
      ),
    );
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).go('/personas');
    await settle(tester);
    c.read(routerProvider).push('/personas/${h.relative}');
    await waitFor(tester, find.byType(ChoiceChip));
    await settle(tester);
    await shot(tester, '5.2_persona');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Cuenta'));
    await settle(tester);
    await shot(tester, '5.2b_persona_cuenta');
    c.read(routerProvider).pop();
    await settle(tester);
    c.read(routerProvider).push('/personas/${h.titular}');
    await waitFor(tester, find.byType(ChoiceChip));
    await settle(tester);
    await shot(tester, '5.2c_persona_titular');
  });

  shotsTest('personas: cuentas, pago, estado de cuenta y propios', (
    tester,
  ) async {
    final s = await setUp(tester, 'rdm-a-cuentas', const []);
    final h = s.h;
    await tester.runAsync(() async {
      await h.repo.confirmApplication(
        ApplicationDraft(
          personId: h.relative,
          farmId: h.relativeFarm,
          campaignId: h.campaign,
          appliedAt: DateTime.now(),
          lines: [
            ApplicationLineDraft(productId: h.product, quantityBase: 2000),
          ],
        ),
      );
      await h.repo.confirmApplication(
        ApplicationDraft(
          personId: h.titular,
          farmId: h.titularFarm,
          campaignId: h.campaign,
          appliedAt: DateTime.now(),
          lines: [
            ApplicationLineDraft(productId: h.product, quantityBase: 1000),
          ],
        ),
      );
    });
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).go('/liquidacion');
    await waitFor(tester, find.byKey(const Key('own-consumption-card')));
    await settle(tester);
    await shot(tester, '5.3_cuentas');
    final hermana = find.ancestor(
      of: find.text('Hermana'),
      matching: find.byType(Card),
    );
    final pay = find.descendant(
      of: hermana,
      matching: find.widgetWithText(FilledButton, 'Registrar pago'),
    );
    await tester.ensureVisible(pay);
    await tester.pump();
    await tester.tap(pay);
    await settle(tester);
    await shot(tester, '5.4_pago');
    await tester.tap(find.byKey(const Key('payment-all')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('payment-amount')), '100');
    await settle(tester);
    await shot(tester, '5.4b_pago_importe');
    await tester.tap(find.byKey(const Key('payment-cancel')));
    await settle(tester);
    final menu = find.descendant(
      of: hermana,
      matching: find.byType(PopupMenuButton<String>),
    );
    await tester.ensureVisible(menu);
    await tester.pump();
    await tester.tap(menu);
    await settle(tester);
    await tester.tap(find.text('Ver detalle cronológico'));
    await settle(tester);
    await shot(tester, '5.5_cuenta');
    await tester.tap(find.text('Cerrar'));
    await settle(tester);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await settle(tester);
    final ownMenu = find.descendant(
      of: find.byKey(const Key('own-consumption-card')),
      matching: find.byType(PopupMenuButton<String>),
    );
    await tester.ensureVisible(ownMenu);
    await tester.pump();
    await tester.tap(ownMenu);
    await settle(tester);
    await tester.tap(find.text('Ver movimientos propios'));
    await settle(tester);
    await shot(tester, '5.6_propios');
    await tester.tap(find.text('Cerrar'));
    await settle(tester);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
    await settle(tester);
    await shot(tester, '5.3b_cuentas_costos');
  });

  shotsTest('personas: lista de personas', (tester) async {
    final s = await setUp(tester, 'rdm-a-personas', const []);
    final h = s.h;
    await tester.runAsync(() async {
      for (final (person, farm) in [
        (h.relative, h.relativeFarm),
        (h.titular, h.titularFarm),
      ]) {
        await h.repo.confirmApplication(
          ApplicationDraft(
            personId: person,
            farmId: farm,
            campaignId: h.campaign,
            appliedAt: DateTime.now(),
            lines: [
              ApplicationLineDraft(productId: h.product, quantityBase: 1500),
            ],
          ),
        );
      }
    });
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).go('/personas');
    await waitFor(tester, find.byKey(const Key('persons-receivable')));
    await settle(tester);
    await shot(tester, '5.1_personas');
  });
}
