import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/presentation/widgets/adaptive_entity_picker.dart';
import 'package:agroquimicos/voice/voice_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/f04_mode_ui_harness.dart';
import '../voice/support/fake_speech_transcription_port.dart';

typedef Row = Map<String, Object?>;

/// «Nueva planificación» con «Completar por voz» (F09, formulario único).
/// Texto inyectado sintético: prueba de integración, no de precisión.
void main() {
  sqfliteFfiInit();

  const full =
      'planificar el chaco titular con dos litros por hectárea de Glifosato';

  late FakeSpeechTranscriptionPort port;

  Future<AppDatabase> open(
    WidgetTester tester,
    String name,
    List<FakeTurn> script,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, name);
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
    c.read(routerProvider).push('/planificacion/nueva');
    await waitFor(tester, find.byKey(const Key('plan-completar-voz')));
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

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );

  String text(WidgetTester tester, String label) =>
      tester.widget<TextField>(field(label)).controller!.text;

  bool saveEnabled(WidgetTester tester) =>
      tester
          .widget<ButtonStyleButton>(find.byKey(const Key('plan-confirm')))
          .onPressed !=
      null;

  Future<int> count(WidgetTester tester, AppDatabase db, String table) async =>
      (await tester.runAsync(() async => (await db.database).query(table)))!
          .length;

  Future<void> dictate(WidgetTester tester) async {
    await tapKey(tester, 'voz-hablar');
    await tapKey(tester, 'voz-terminar');
    await settle(tester);
  }

  testWidgets('voz en un plan vacío: chaco, área y la línea con su dosis; '
      'guardar crea un plan y no toca inventario ni cuentas', (tester) async {
    final db = await open(tester, 'p-vacio', [
      const FakeTurn(segment: full, endsOnStop: true),
    ]);
    final movements = await count(tester, db, 'inventory_movements');
    final accounts = await count(tester, db, 'account_transactions');
    await tapKey(tester, 'plan-completar-voz');
    await dictate(tester);
    expect(picked(tester, 'Chaco'), 'Chaco titular');
    expect(text(tester, 'Área planificada (ha)'), '1');
    expect(find.text('Productos (1)'), findsOneWidget);
    expect(text(tester, 'Dosis (L/ha)'), '2');
    expect(find.byKey(const Key('voz-marca-farm')), findsOneWidget);
    expect(saveEnabled(tester), isTrue);
    expect(await count(tester, db, 'application_plans'), 0);
    await tapKey(tester, 'plan-confirm');
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    expect(await count(tester, db, 'application_plans'), 1);
    expect(await count(tester, db, 'application_plan_items'), 1);
    expect(await count(tester, db, 'inventory_movements'), movements);
    expect(await count(tester, db, 'account_transactions'), accounts);
  });

  testWidgets('mixto: chaco elegido a mano y la dosis dictada; el chaco y el '
      'área no cambian', (tester) async {
    await open(tester, 'p-mixto', [
      const FakeTurn(
        segment: 'dos litros por hectárea de Glifosato',
        endsOnStop: true,
      ),
    ]);
    await choose(tester, 'Chaco', 'Chaco hermana');
    expect(text(tester, 'Área planificada (ha)'), '0,5');
    await tapKey(tester, 'plan-completar-voz');
    await dictate(tester);
    expect(picked(tester, 'Chaco'), 'Chaco hermana');
    expect(text(tester, 'Área planificada (ha)'), '0,5');
    expect(text(tester, 'Dosis (L/ha)'), '2');
    expect(find.byKey(const Key('voz-elegir-farm')), findsNothing);
    expect(find.byKey(const Key('voz-elegir-area')), findsNothing);
  });

  testWidgets('conflicto: otro chaco dictado no reemplaza al elegido; se '
      'pregunta y no se puede guardar hasta decidir', (tester) async {
    await open(tester, 'p-conflicto', [
      const FakeTurn(segment: full, endsOnStop: true),
    ]);
    await choose(tester, 'Chaco', 'Chaco hermana');
    await tapKey(tester, 'plan-completar-voz');
    await dictate(tester);
    expect(picked(tester, 'Chaco'), 'Chaco hermana');
    expect(find.byKey(const Key('voz-elegir-farm')), findsOneWidget);
    expect(saveEnabled(tester), isFalse);
    expect(find.byKey(const Key('voz-bloqueo-guardar')), findsOneWidget);
    await tapKey(tester, 'voz-mantener-farm');
    // El área que venía con el chaco dictado también se decide.
    if (find.byKey(const Key('voz-mantener-area')).evaluate().isNotEmpty) {
      await tapKey(tester, 'voz-mantener-area');
    }
    expect(picked(tester, 'Chaco'), 'Chaco hermana');
    expect(text(tester, 'Área planificada (ha)'), '0,5');
    expect(saveEnabled(tester), isTrue);
  });

  testWidgets('línea empezada a mano (producto sin dosis): la dosis dictada '
      'la completa, sin añadir otra', (tester) async {
    await open(tester, 'p-contexto', [
      const FakeTurn(
        segment: 'dos litros por hectárea de Glifosato',
        endsOnStop: true,
      ),
    ]);
    await choose(tester, 'Agregar producto', 'Glifosato');
    await tester.tap(find.byTooltip('Agregar al plan'));
    await settle(tester);
    expect(find.text('Productos (1)'), findsOneWidget);
    await tapKey(tester, 'plan-completar-voz');
    await dictate(tester);
    expect(find.text('Productos (1)'), findsOneWidget);
    expect(text(tester, 'Dosis (L/ha)'), '2');
  });

  testWidgets('deshacer: revierte el chaco y el área dictados y conserva la '
      'línea si se editó después', (tester) async {
    await open(tester, 'p-deshacer', [
      const FakeTurn(segment: full, endsOnStop: true),
    ]);
    await tapKey(tester, 'plan-completar-voz');
    await dictate(tester);
    await tester.enterText(field('Dosis (L/ha)'), '3');
    await settle(tester);
    await tapKey(tester, 'voz-deshacer');
    expect(picked(tester, 'Chaco'), isNull);
    expect(text(tester, 'Área planificada (ha)'), '');
    expect(find.text('Productos (1)'), findsOneWidget);
    expect(text(tester, 'Dosis (L/ha)'), '3');
  });
}
