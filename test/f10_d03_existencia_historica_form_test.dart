// D-03 (decisión del autor, Roderich Rendón, 2026-10-27) en el formulario de
// aplicación: con un día pasado, el repositorio rechaza el producto que se
// compró después y el formulario muestra su mensaje (producto, fecha y
// existencia elegible) sin escribir nada. La vista previa del formulario
// sigue mostrando el saldo de hoy: no añade consultas.
//
// App real en modalidad propia (arnés de F04). Prueba de HOST, sin
// dispositivo ni personas.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/domain/campaign_calendar.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/presentation/widgets/adaptive_entity_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/es_material_labels.dart';
import 'support/f04_mode_fixtures.dart';
import 'support/f04_mode_ui_harness.dart';

typedef Row = Map<String, Object?>;

void main() {
  sqfliteFfiInit();

  Finder picker(String label) => find.byWidgetPredicate(
    (w) => w is AdaptiveEntityPicker<Row> && w.label == label,
  );

  Future<void> choose(WidgetTester tester, String label, String name) async {
    final widget = tester.widget<AdaptiveEntityPicker<Row>>(picker(label));
    widget.onChanged(
      widget.items.firstWhere((item) => widget.labelOf(item) == name),
    );
    await settle(tester);
  }

  Finder inPicker(Finder matching) =>
      find.descendant(of: find.byType(DatePickerDialog), matching: matching);

  Future<void> tapKey(WidgetTester tester, Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.pump();
    await tester.tap(find.byKey(key), warnIfMissed: false);
    await settle(tester);
  }

  testWidgets('día pasado con el producto comprado hoy: el formulario '
      'muestra el rechazo del repositorio y no escribe nada', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, 'd03-formulario');
    await tester.runAsync(() async {
      // La única existencia del titular entra hoy.
      await s.household.buy(s.household.titular, 5000, date: DateTime.now());
      await OperationModeStore(s.database)
          .apply(OperationMode.personal, confirmed: true);
    });
    final AppDatabase database = s.database;
    final c = await pumpModeApp(tester, database);
    c.read(routerProvider).push('/aplicaciones/nueva');
    await waitFor(tester, picker('Chaco'));
    await settle(tester);

    // El 1 del mes en curso o, si hoy es 1, el del mes anterior.
    final today = DateTime.now();
    final previousMonth = today.day == 1;
    final day = localDay(
      DateTime(today.year, today.month - (previousMonth ? 1 : 0), 1),
    );
    final es = await esMaterial();
    await tapKey(tester, const Key('application-date'));
    expect(find.byType(DatePickerDialog), findsOneWidget);
    if (previousMonth) {
      await tester.tap(inPicker(find.byTooltip(es.previousMonthTooltip)));
      await settle(tester);
    }
    await tester.tap(inPicker(find.text('1')));
    await tester.pump();
    await tester.tap(inPicker(find.text(es.okButtonLabel)));
    await settle(tester);

    final w = tester.widget<AdaptiveEntityPicker<Row>>(picker('Chaco'));
    if (w.items.any((item) => w.labelOf(item) == 'Chaco titular')) {
      await choose(tester, 'Chaco', 'Chaco titular');
    }
    await tapKey(tester, const Key('application-continue'));
    await tapKey(tester, const Key('application-add-product'));
    await choose(tester, 'Producto', 'Glifosato');
    await tester.enterText(
      find.byKey(const Key('application-line-quantity')),
      '2',
    );
    await tapKey(tester, const Key('application-line-add'));
    expect(find.text('2 L'), findsOneWidget);

    final before = (await tester.runAsync(
      () async => dumpTables(await database.database),
    ))!;
    await tapKey(tester, const Key('application-continue'));
    await tapKey(tester, const Key('application-confirm'));
    await waitFor(tester, find.textContaining('esa persona no tenía'));

    expect(
      find.textContaining(
        'Glifosato: el ${displayDay(day)} esa persona no tenía este '
        'producto; pidió 2 L.',
      ),
      findsOneWidget,
    );
    // Sigue en el resumen, con el botón para corregir y volver a intentar.
    expect(find.byKey(const Key('application-confirm')), findsOneWidget);
    expect(
      (await tester.runAsync(() async => dumpTables(await database.database)))!,
      before,
    );
  });
}
