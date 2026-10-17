import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/presentation/screens/application_form_screen.dart';
import 'package:agroquimicos/presentation/voice/voice_draft_gateway.dart';
import 'package:agroquimicos/presentation/widgets/adaptive_entity_picker.dart';
import 'package:agroquimicos/voice_draft/application/application_interpreter.dart';
import 'package:agroquimicos/voice_draft/application/voice_application_draft.dart';
import 'package:agroquimicos/voice_draft/core/draft_field.dart';
import 'package:agroquimicos/voice_draft/core/voice_draft_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';

/// Área exacta del plan: «Aplicar este plan» y su equivalente por voz escriben
/// lo mismo (decisión «Precisión de área», 2026-10-17).
///
/// El plan guarda `area_m2` entero. El formulario lo cargaba en hectáreas con
/// tres decimales (10001 m² → «1» → 10000 m²), el área del chaco con dos
/// (12345 m² → «1,23» → 12300 m²) y calculaba la teórica en coma flotante;
/// la voz conserva el entero. Aquí se recorre el formulario real, como widget,
/// y la voz con su intérprete, su controlador y su gateway, cada uno sobre una
/// base sembrada igual, y se comparan las tablas enteras.
void main() {
  sqfliteFfiInit();

  /// 10001 m² no es múltiplo de 10. Con 5 L/ha la teórica exacta es
  /// 10001 × 5000 / 10000 = 5000,5 → 5001 (mitad hacia arriba, como
  /// `addPlanMulti`); con 10000 m² sería 5000.
  const planArea = 10001;
  const glifosatoDose = 5000;
  const bellatorDose = 1500;

  /// Cantidad real de Bellator, la misma en los dos recorridos.
  const bellatorReal = 2000;

  Future<void> settle(WidgetTester tester) async {
    for (var round = 0; round < 6; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
  }

  /// Base con un chaco de 10001 m², stock de los dos productos y un plan
  /// pendiente de 10001 m².
  Future<({AppDatabase db, AgroRepository repo, int plan, int farm})> seed(
    String name,
  ) async {
    final db = openDb(await tempDbPath(name));
    final repo = AgroRepository(db);
    final h = await seedHousehold(repo);
    final farm = await repo.addFarm(
      ownerId: h.titular,
      name: 'Impar',
      areaM2: planArea,
    );
    final bellator = await repo.addProduct(name: 'Bellator');
    await h.buy(h.titular, 20000);
    await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: h.supplier,
        campaignId: h.campaign,
        purchaseDate: DateTime(2026, 1, 2),
        items: [
          PurchaseItemDraft(
            productId: bellator,
            quantityBase: 20000,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 20000,
            allocations: [
              AllocationDraft(personId: h.titular, quantityBase: 20000),
            ],
          ),
        ],
      ),
    );
    final plan = await repo.addPlanMulti(
      farmId: farm,
      campaignId: h.campaign,
      areaM2: planArea,
      items: [
        PlanItemDraft(productId: h.product, doseBasePerHa: glifosatoDose),
        PlanItemDraft(productId: bellator, doseBasePerHa: bellatorDose),
      ],
    );
    return (db: db, repo: repo, plan: plan, farm: farm);
  }

  /// Recorrido por voz: pedir el plan, elegirlo, corregir la real de Bellator
  /// y confirmar con [confirmations] toques.
  Future<void> viaVoice(
    AgroRepository repo,
    int plan, {
    int? manualAreaM2,
    int confirmations = 1,
  }) async {
    final gateway = VoiceDraftGateway(repo);
    final catalog = await gateway.applicationCatalog();
    final controller = VoiceDraftController<VoiceApplicationDraft, int>(
      initial: VoiceApplicationDraft.start(catalog),
      commit: gateway.confirmApplication,
    );
    addTearDown(controller.dispose);
    controller.applyVoice((c) {
      final r = interpretApplication(
        'aplicar la planificación del chaco Impar',
        c,
        catalog,
      );
      return (r.draft, r.outcome);
    });
    controller.editManually((c) => selectPlan(c, plan, catalog));
    controller.applyVoice((c) {
      final r = interpretApplication(
        'de Bellator en realidad usamos dos litros',
        c,
        catalog,
      );
      return (r.draft, r.outcome);
    });
    if (manualAreaM2 != null) {
      controller.editManually(
        (c) => c.copyWith(
          area: DraftField.resolved(manualAreaM2, origin: FieldOrigin.manual),
        ),
      );
    }
    final owner = controller.draft.person!.id;
    final stock = await gateway.availableStock(owner);
    controller.editManually((c) => c.withStock(owner, stock));
    expect(controller.blockers, isEmpty);
    await Future.wait([
      for (var i = 0; i < confirmations; i++) controller.confirm(),
    ]);
  }

  Finder areaField() => find.widgetWithText(TextField, 'Área tratada (ha)');

  final navigator = GlobalKey<NavigatorState>();

  /// Abre el formulario como lo abre «Aplicar este plan» (`planId`).
  Future<void> openForm(
    WidgetTester tester,
    AgroRepository repo,
    int plan,
  ) async {
    tester.view.physicalSize = const Size(500, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('inicio')),
        ),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<bool>(
        builder: (_) => ApplicationFormScreen(planId: plan),
      ),
    );
    // La carga lee la campaña, las personas, los chacos, el plan, el stock y
    // el costo FIFO de cada línea: se espera a que aparezca el formulario.
    for (var i = 0; i < 40 && areaField().evaluate().isEmpty; i++) {
      await settle(tester);
    }
    await settle(tester);
    expect(areaField(), findsOneWidget);
  }

  String areaText(WidgetTester tester) =>
      tester.widget<TextField>(areaField()).controller!.text;

  Finder realField(String unit, int index) =>
      find.widgetWithText(TextField, 'Cantidad real ($unit)').at(index);

  Future<void> confirmForm(WidgetTester tester, {int taps = 1}) async {
    final button = find.byKey(const Key('application-confirm'));
    await tester.ensureVisible(button);
    await tester.pump();
    for (var i = 0; i < taps; i++) {
      await tester.tap(button, warnIfMissed: false);
    }
    await settle(tester);
  }

  /// Las tablas enteras, sin lo que legítimamente difiere entre dos
  /// recorridos: marcas de tiempo (`*_at`), el instante de la aplicación
  /// copiado al movimiento y al cargo (`movement_date`, `transaction_date`;
  /// la voz usa su reloj y el formulario `DateTime.now()`), UUID y el
  /// identificador de operación. Las fechas sembradas (compra, lote) sí se
  /// comparan.
  Future<Map<String, List<Map<String, Object?>>>> business(
    AppDatabase d,
  ) async => {
    for (final e in (await dumpTables(await d.database)).entries)
      e.key: [
        for (final row in e.value)
          {
            for (final c in row.entries)
              if (!c.key.endsWith('_at') &&
                  c.key != 'movement_date' &&
                  c.key != 'transaction_date' &&
                  !c.key.contains('uuid') &&
                  !c.key.contains('operation'))
                c.key: c.value,
          },
      ],
  };

  Future<List<Map<String, Object?>>> rows(AppDatabase d, String table) async =>
      (await d.database).query(table, orderBy: 'id');

  testWidgets(
    'plan de 10001 m²: formulario y voz guardan el área y la teórica exactas',
    (tester) async {
      final voice = (await tester.runAsync(() => seed('voz')))!;
      final form = (await tester.runAsync(() => seed('formulario')))!;
      await tester.runAsync(() => viaVoice(voice.repo, voice.plan));

      await openForm(tester, form.repo, form.plan);
      // Se muestra lo que se guardará: 1,0001 ha, no «1».
      expect(areaText(tester), '1,0001');
      // Las líneas siguen el orden del plan: Glifosato y Bellator, ambas en L.
      await tester.enterText(realField('L', 1), '2');
      await settle(tester);
      await confirmForm(tester);

      final app = (await tester.runAsync(() => rows(form.db, 'applications')))!
          .single;
      expect(app['treated_area_m2'], planArea);
      expect(app['plan_id'], form.plan);
      final items = (await tester.runAsync(
        () => rows(form.db, 'application_items'),
      ))!;
      expect(
        [for (final i in items) i['treated_area_m2']],
        [planArea, planArea],
      );
      // 10001 × 5000 / 10000 = 5000,5 → 5001; 10001 × 1500 / 10000 = 1500,15
      // → 1500.
      expect(
        [for (final i in items) i['theoretical_quantity_base']],
        [5001, 1500],
      );
      expect([for (final i in items) i['quantity_base']], [5001, bellatorReal]);

      final voiceTables = (await tester.runAsync(() => business(voice.db)))!;
      final formTables = (await tester.runAsync(() => business(form.db)))!;
      expect(formTables.keys, voiceTables.keys);
      expect(formTables.keys, voiceTables.keys);
      for (final table in voiceTables.keys) {
        expect(formTables[table], voiceTables[table], reason: table);
      }
    },
  );

  testWidgets(
    'el área editada a mano se guarda tal cual en los dos recorridos',
    (tester) async {
      final voice = (await tester.runAsync(() => seed('voz-editada')))!;
      final form = (await tester.runAsync(() => seed('formulario-editado')))!;
      await tester.runAsync(
        () => viaVoice(voice.repo, voice.plan, manualAreaM2: 12345),
      );

      await openForm(tester, form.repo, form.plan);
      await tester.enterText(areaField(), '1,2345');
      await tester.enterText(realField('L', 1), '2');
      await settle(tester);
      await confirmForm(tester);

      final app = (await tester.runAsync(() => rows(form.db, 'applications')))!
          .single;
      expect(app['treated_area_m2'], 12345);
      final items = (await tester.runAsync(
        () => rows(form.db, 'application_items'),
      ))!;
      // 12345 × 5000 / 10000 = 6172,5 → 6173; 12345 × 1500 / 10000 =
      // 1851,75 → 1852. La real no cambia con el área.
      expect(
        [for (final i in items) i['theoretical_quantity_base']],
        [6173, 1852],
      );
      expect([for (final i in items) i['quantity_base']], [5001, bellatorReal]);

      final voiceTables = (await tester.runAsync(() => business(voice.db)))!;
      final formTables = (await tester.runAsync(() => business(form.db)))!;
      expect(formTables.keys, voiceTables.keys);
      expect(formTables.keys, voiceTables.keys);
      for (final table in voiceTables.keys) {
        expect(formTables[table], voiceTables[table], reason: table);
      }
    },
  );

  testWidgets('volver a elegir el chaco toma su área exacta, no con dos '
      'decimales', (tester) async {
    final form = (await tester.runAsync(() => seed('formulario-chaco')))!;
    await openForm(tester, form.repo, form.plan);
    final picker = find.byWidgetPredicate(
      (w) =>
          w is AdaptiveEntityPicker<Map<String, Object?>> && w.label == 'Chaco',
    );
    final chaco = tester
        .widget<AdaptiveEntityPicker<Map<String, Object?>>>(picker)
        .items
        .singleWhere((f) => f['id'] == form.farm);
    tester
        .widget<AdaptiveEntityPicker<Map<String, Object?>>>(picker)
        .onChanged(chaco);
    await settle(tester);
    expect(areaText(tester), '1,0001');
    await tester.enterText(realField('L', 1), '2');
    await settle(tester);
    await confirmForm(tester);
    final app = (await tester.runAsync(() => rows(form.db, 'applications')))!
        .single;
    expect(app['treated_area_m2'], planArea);
  });

  testWidgets('doble confirmación: una aplicación, igual que la voz', (
    tester,
  ) async {
    final voice = (await tester.runAsync(() => seed('voz-doble')))!;
    final form = (await tester.runAsync(() => seed('formulario-doble')))!;
    await tester.runAsync(
      () => viaVoice(voice.repo, voice.plan, confirmations: 2),
    );

    await openForm(tester, form.repo, form.plan);
    await tester.enterText(realField('L', 1), '2');
    await settle(tester);
    await confirmForm(tester, taps: 2);

    expect(
      (await tester.runAsync(() => rows(form.db, 'applications')))!,
      hasLength(1),
    );
    // Sin aviso de error: el segundo toque no intenta otra escritura.
    expect(find.byType(SnackBar), findsNothing);
    final voiceTables = (await tester.runAsync(() => business(voice.db)))!;
    final formTables = (await tester.runAsync(() => business(form.db)))!;
    expect(formTables.keys, voiceTables.keys);
    for (final table in voiceTables.keys) {
      expect(formTables[table], voiceTables[table], reason: table);
    }
  });
}
