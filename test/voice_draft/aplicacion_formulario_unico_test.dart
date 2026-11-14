import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/presentation/widgets/adaptive_entity_picker.dart';
import 'package:agroquimicos/voice/voice_providers.dart';
import 'package:agroquimicos/presentation/screens/application_form_screen.dart'
    show applicationPersonLabel;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/f04_mode_ui_harness.dart';
import '../voice/support/fake_speech_transcription_port.dart';

typedef Row = Map<String, Object?>;

/// «Nueva aplicación» con «Completar por voz» (F09, formulario único). Texto
/// inyectado sintético: prueba de integración, no de precisión.
void main() {
  sqfliteFfiInit();

  const full =
      'apliqué dos litros de Glifosato en el chaco titular en media hectárea';

  late FakeSpeechTranscriptionPort port;

  Future<AppDatabase> open(
    WidgetTester tester,
    String name,
    List<FakeTurn> script, {
    bool stock = true,
    bool withPlan = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, name);
    await tester.runAsync(() async {
      final h = s.household;
      if (stock) await h.buy(h.titular, 5000);
      await h.repo.addProduct(name: 'Bellator');
      if (withPlan) {
        await h.repo.addPlanMulti(
          farmId: h.titularFarm,
          campaignId: h.campaign,
          areaM2: 10000,
          items: [PlanItemDraft(productId: h.product, doseBasePerHa: 1500)],
        );
      }
    });
    port = FakeSpeechTranscriptionPort(script: script, repeatLast: false);
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
    c.read(routerProvider).push('/aplicaciones/nueva');
    await waitFor(tester, find.byKey(const Key('aplicacion-completar-voz')));
    await settle(tester);
    return s.database;
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.pump();
    await tester.tap(find.byKey(Key(key)));
    await settle(tester);
  }

  Finder picker(String label) => find.byWidgetPredicate(
    (w) => w is AdaptiveEntityPicker<Row> && w.label == label,
  );

  String? picked(WidgetTester tester, String label) => tester
      .widgetList<AdaptiveEntityPicker<Row>>(picker(label))
      .first
      .value?['name']
      ?.toString();

  Future<void> choose(WidgetTester tester, String label, String name) async {
    final w = tester.widgetList<AdaptiveEntityPicker<Row>>(picker(label)).first;
    w.onChanged(w.items.firstWhere((i) => w.labelOf(i) == name));
    await settle(tester);
  }

  String area(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const Key('application-area')))
      .controller!
      .text;

  bool enabled(WidgetTester tester, String key) =>
      tester.widget<ButtonStyleButton>(find.byKey(Key(key))).onPressed != null;

  Future<int> count(WidgetTester tester, AppDatabase db, String table) async =>
      (await tester.runAsync(() async => (await db.database).query(table)))!
          .length;

  Future<void> dictate(WidgetTester tester) async {
    await tapKey(tester, 'voz-hablar');
    await tapKey(tester, 'voz-terminar');
    // Las existencias del responsable se leen después de poner el chaco.
    await settle(tester);
    await settle(tester);
  }

  Future<void> openPanel(WidgetTester tester) async {
    await tapKey(tester, 'aplicacion-completar-voz');
    // El catálogo de la voz (con los planes pendientes) se lee al abrir.
    await settle(tester);
  }

  testWidgets('voz en una aplicación vacía: chaco, persona, área y la línea '
      'con sus existencias; nada cambia hasta confirmar y se registra una '
      'sola aplicación', (tester) async {
    final db = await open(tester, 'a-vacio', [
      const FakeTurn(segment: full, endsOnStop: true),
    ]);
    await openPanel(tester);
    await dictate(tester);
    expect(picked(tester, applicationPersonLabel), 'Titular');
    expect(picked(tester, 'Chaco'), 'Chaco titular');
    expect(area(tester), '0,5');
    expect(find.byKey(const Key('voz-marca-farm')), findsOneWidget);
    expect(find.byKey(const Key('aplicacion-lineas-paso2')), findsOneWidget);
    final movements = await count(tester, db, 'inventory_movements');
    await tapKey(tester, 'application-continue');
    expect(find.text('Glifosato'), findsWidgets);
    expect(find.text('2 L'), findsOneWidget);
    expect(find.byKey(const Key('voz-marca-quantity@1')), findsOneWidget);
    await tapKey(tester, 'application-continue');
    expect(await count(tester, db, 'applications'), 0);
    expect(await count(tester, db, 'inventory_movements'), movements);
    await tapKey(tester, 'application-confirm');
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    expect(await count(tester, db, 'applications'), 1);
    expect(await count(tester, db, 'inventory_movements'), movements + 1);
  });

  testWidgets('producto sin existencias: la línea se muestra pero la voz no '
      'esquiva el aviso; no se registra nada', (tester) async {
    final db = await open(tester, 'a-sin-stock', [
      const FakeTurn(
        segment: 'apliqué un litro de Bellator en el chaco titular',
        endsOnStop: true,
      ),
    ]);
    await openPanel(tester);
    await dictate(tester);
    await tapKey(tester, 'application-continue');
    expect(find.text('Bellator'), findsWidgets);
    await tapKey(tester, 'application-continue');
    if (find.byKey(const Key('application-confirm')).evaluate().isNotEmpty) {
      await tapKey(tester, 'application-confirm');
    }
    expect(await count(tester, db, 'applications'), 0);
    expect(find.textContaining('No alcanza'), findsWidgets);
  });

  testWidgets('chaco de otra persona con una persona ya elegida: no se '
      'cambia solo (vaciaría la mezcla); se pregunta', (tester) async {
    await open(tester, 'a-otra-persona', [
      const FakeTurn(segment: full, endsOnStop: true),
    ]);
    await choose(tester, applicationPersonLabel, 'Hermana');
    await openPanel(tester);
    await dictate(tester);
    expect(picked(tester, applicationPersonLabel), 'Hermana');
    // Su único chaco ya estaba elegido (comportamiento del formulario).
    expect(picked(tester, 'Chaco'), 'Chaco hermana');
    expect(find.byKey(const Key('voz-revisar-farm')), findsOneWidget);
    expect(enabled(tester, 'application-continue'), isFalse);
    expect(find.byKey(const Key('voz-bloqueo-guardar')), findsOneWidget);
  });

  testWidgets('deshacer el dictado retira también la revisión del chaco '
      'ajeno que planteó; la persona y el chaco elegidos siguen', (
    tester,
  ) async {
    await open(tester, 'a-deshacer-revision', [
      const FakeTurn(segment: full, endsOnStop: true),
    ]);
    await choose(tester, applicationPersonLabel, 'Hermana');
    await openPanel(tester);
    await dictate(tester);
    expect(find.byKey(const Key('voz-revisar-farm')), findsOneWidget);
    expect(enabled(tester, 'application-continue'), isFalse);
    await tapKey(tester, 'voz-deshacer');
    expect(find.byKey(const Key('voz-revisar-farm')), findsNothing);
    expect(find.byKey(const Key('voz-bloqueo-guardar')), findsNothing);
    expect(enabled(tester, 'application-continue'), isTrue);
    expect(picked(tester, applicationPersonLabel), 'Hermana');
    expect(picked(tester, 'Chaco'), 'Chaco hermana');
  });

  testWidgets('pedir un plan por voz ofrece los planes pendientes y abre el '
      'recorrido de siempre «Aplicar este plan»', (tester) async {
    await open(tester, 'a-plan', [
      const FakeTurn(
        segment: 'aplicar la planificación del chaco titular',
        endsOnStop: true,
      ),
    ], withPlan: true);
    await openPanel(tester);
    await dictate(tester);
    expect(find.byKey(const Key('voz-revisar-plan')), findsOneWidget);
    await tapKey(tester, 'voz-opcion-plan-0');
    // La frase también puso el chaco: hay cambios, así que se confirma.
    expect(find.text('Abrir el plan'), findsOneWidget);
    await tester.tap(find.text('Abrir el plan'));
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    expect(find.byKey(const Key('application-plan-farm')), findsOneWidget);
  });

  testWidgets('cancelar el dictado: el resultado tardío no cambia la '
      'aplicación', (tester) async {
    await open(tester, 'a-cancelar', [
      const FakeTurn(segment: full, delay: Duration(seconds: 2)),
    ]);
    await openPanel(tester);
    await tester.tap(find.byKey(const Key('voz-hablar')));
    await tester.pump();
    await tapKey(tester, 'voz-cancelar-dictado');
    await tester.pump(const Duration(seconds: 3));
    await settle(tester);
    expect(picked(tester, 'Chaco'), isNull);
    expect(area(tester), '');
  });
}
