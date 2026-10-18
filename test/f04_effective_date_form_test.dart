// #121: los formularios de compra y aplicación muestran la fecha efectiva,
// hoy por defecto, y dejan elegir un día pasado con el selector real; cancelar
// el selector conserva el borrador; el repositorio clasifica y, si rechaza, no
// escribe nada. Se conservan la precisión de área y la confirmación única de
// #115. App real en modalidad propia (arnés de F04). Pruebas de HOST; el
// selector de Material sale en inglés porque la app no configura
// localizaciones (observación de #118, no condición).
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/domain/campaign_calendar.dart';
import 'package:agroquimicos/domain/money.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/presentation/widgets/adaptive_entity_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );

  String fieldText(WidgetTester tester, String label) =>
      tester.widget<TextField>(field(label)).controller!.text;

  Finder dateTile(Key key) => find.byKey(key);

  /// Día que se elige en el selector: el 1 del mes en curso o, si hoy es 1,
  /// el 1 del mes anterior. Siempre es un día pasado.
  ({String day, bool previousMonth}) pastDayChoice(DateTime today) =>
      today.day > 1
      ? (
          day: localDay(DateTime(today.year, today.month, 1)),
          previousMonth: false,
        )
      : (
          day: localDay(DateTime(today.year, today.month - 1, 1)),
          previousMonth: true,
        );

  Finder inPicker(Finder matching) =>
      find.descendant(of: find.byType(DatePickerDialog), matching: matching);

  Future<void> openPicker(WidgetTester tester, Key tile) async {
    await tester.ensureVisible(dateTile(tile));
    await tester.pump();
    await tester.tap(dateTile(tile));
    await settle(tester);
    expect(find.byType(DatePickerDialog), findsOneWidget);
  }

  Future<void> pickPastDay(
    WidgetTester tester,
    Key tile, {
    required bool previousMonth,
  }) async {
    await openPicker(tester, tile);
    if (previousMonth) {
      await tester.tap(inPicker(find.byTooltip('Previous month')));
      await settle(tester);
    }
    await tester.tap(inPicker(find.text('1')));
    await tester.pump();
    await tester.tap(inPicker(find.text('OK')));
    await settle(tester);
  }

  Future<void> cancelPicker(WidgetTester tester, Key tile) async {
    await openPicker(tester, tile);
    await tester.tap(inPicker(find.text('Cancel')));
    await settle(tester);
    expect(find.byType(DatePickerDialog), findsNothing);
  }

  /// Hogar activado en modalidad propia, con stock del titular. Con
  /// [closedBeforeToday], una campaña cerrada que termina ayer y la activa
  /// desde hoy; con [endYesterday], la activa termina ayer (hoy no cae en
  /// ninguna campaña).
  Future<({AppDatabase database, Household household, int campaign})> home(
    WidgetTester tester,
    String name, {
    bool closedBeforeToday = false,
    bool endYesterday = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, name);
    final campaign = await tester.runAsync(() async {
      await s.household.buy(s.household.titular, 5000);
      var active = s.household.campaign;
      if (closedBeforeToday) {
        active = await s.household.repo.addCampaign(
          name: 'Campaña 2',
          start: DateTime.now(),
        );
        await s.household.repo.activateCampaign(active, closeCurrent: true);
      }
      if (endYesterday) {
        await s.household.repo.setCampaignEnd(
          active,
          end: DateTime.now().subtract(const Duration(days: 1)),
        );
      }
      await OperationModeStore(s.database)
          .apply(OperationMode.personal, confirmed: true);
      return active;
    });
    return (database: s.database, household: s.household, campaign: campaign!);
  }

  Future<List<Row>> rows(
    WidgetTester tester,
    AppDatabase db,
    String table,
  ) async => (await tester.runAsync(
    () async => (await db.database).query(table, orderBy: 'id'),
  ))!;

  Future<Map<String, List<Row>>> dump(
    WidgetTester tester,
    AppDatabase db,
  ) async =>
      (await tester.runAsync(() async => dumpTables(await db.database)))!;

  Future<void> fillPurchase(WidgetTester tester) async {
    await choose(tester, 'Proveedor', 'Proveedor');
    await choose(tester, 'Producto', 'Glifosato');
    await tester.enterText(field('Cantidad comprada'), '4');
    await tester.enterText(field('Precio BOB/L'), '50');
    await settle(tester);
  }

  Future<void> confirm(WidgetTester tester, Key button, {int taps = 1}) async {
    await tester.ensureVisible(find.byKey(button));
    await tester.pump();
    for (var i = 0; i < taps; i++) {
      await tester.tap(find.byKey(button), warnIfMissed: false);
    }
    await settle(tester);
  }

  group('compra', () {
    const tile = Key('purchase-date');
    const button = Key('purchase-confirm');

    testWidgets('hoy por defecto; un día pasado del período activo se guarda '
        'ese día, a medianoche local, en la campaña activa', (tester) async {
      final h = await home(tester, 'compra-pasada');
      final c = await pumpModeApp(tester, h.database);
      c.read(routerProvider).push('/compras/nueva');
      await waitFor(tester, field('Cantidad comprada'));
      await settle(tester);
      final today = DateTime.now();
      expect(
        find.descendant(
          of: dateTile(tile),
          matching: find.textContaining('(hoy)'),
        ),
        findsOneWidget,
      );
      await fillPurchase(tester);
      final choice = pastDayChoice(today);
      await pickPastDay(tester, tile, previousMonth: choice.previousMonth);
      expect(
        find.descendant(
          of: dateTile(tile),
          matching: find.text(formatDate(choice.day)),
        ),
        findsOneWidget,
      );
      // Elegir la fecha no toca el resto del borrador.
      expect(fieldText(tester, 'Cantidad comprada'), '4');
      await confirm(tester, button);

      final purchases = await rows(tester, h.database, 'purchases');
      expect(purchases, hasLength(2), reason: 'la del stock y la nueva');
      final row = purchases.last;
      expect(row['campaign_id'], h.campaign);
      final stored = row['purchase_date']! as String;
      expect(storedLocalDay(stored), choice.day);
      final local = DateTime.parse(stored).toLocal();
      expect(
        [local.hour, local.minute, local.second],
        [0, 0, 0],
        reason: 'hora no conocida: medianoche local del día elegido',
      );
    });

    testWidgets('cancelar el selector conserva el borrador y la fecha de hoy, '
        'y no escribe nada', (tester) async {
      final h = await home(tester, 'compra-cancelar');
      final c = await pumpModeApp(tester, h.database);
      c.read(routerProvider).push('/compras/nueva');
      await waitFor(tester, field('Cantidad comprada'));
      await settle(tester);
      await fillPurchase(tester);
      final before = await dump(tester, h.database);
      await cancelPicker(tester, tile);
      expect(
        find.descendant(
          of: dateTile(tile),
          matching: find.textContaining('(hoy)'),
        ),
        findsOneWidget,
      );
      expect(fieldText(tester, 'Cantidad comprada'), '4');
      expect(fieldText(tester, 'Precio BOB/L'), '50');
      expect(await dump(tester, h.database), before);
    });

    testWidgets('un día de la campaña cerrada se rechaza con el mensaje y sin '
        'escribir; el borrador sigue en pantalla', (tester) async {
      final h = await home(tester, 'compra-cerrada', closedBeforeToday: true);
      final c = await pumpModeApp(tester, h.database);
      c.read(routerProvider).push('/compras/nueva');
      await waitFor(tester, field('Cantidad comprada'));
      await settle(tester);
      await fillPurchase(tester);
      final choice = pastDayChoice(DateTime.now());
      await pickPastDay(tester, tile, previousMonth: choice.previousMonth);
      final before = await dump(tester, h.database);
      await confirm(tester, button);
      expect(find.textContaining('campaña cerrada'), findsOneWidget);
      expect(find.byKey(button), findsOneWidget);
      expect(await dump(tester, h.database), before);
    });
  });

  group('aplicación', () {
    const tile = Key('application-date');
    const button = Key('application-confirm');

    /// Con un solo chaco y un solo producto en stock, el selector los deja
    /// elegidos al abrir; si no, se eligen aquí.
    Future<void> fillApplication(WidgetTester tester) async {
      Future<void> chooseIfOffered(String label, String name) async {
        final w = tester.widget<AdaptiveEntityPicker<Row>>(picker(label));
        if (w.items.any((item) => w.labelOf(item) == name)) {
          await choose(tester, label, name);
        }
      }

      await chooseIfOffered('Chaco', 'Chaco titular');
      await chooseIfOffered('Elegir producto', 'Glifosato');
      expect(field('Cantidad real (L)'), findsOneWidget);
      await tester.enterText(field('Cantidad real (L)'), '2');
      await settle(tester);
    }

    testWidgets('un día pasado se guarda a medianoche local, con el área '
        'exacta y una sola aplicación aunque se toque dos veces', (
      tester,
    ) async {
      final h = await home(tester, 'aplicacion-pasada');
      final c = await pumpModeApp(tester, h.database);
      c.read(routerProvider).push('/aplicaciones/nueva');
      await waitFor(tester, picker('Chaco'));
      await settle(tester);
      expect(
        find.descendant(
          of: dateTile(tile),
          matching: find.textContaining('(hoy)'),
        ),
        findsOneWidget,
      );
      await fillApplication(tester);
      final choice = pastDayChoice(DateTime.now());
      await pickPastDay(tester, tile, previousMonth: choice.previousMonth);
      expect(fieldText(tester, 'Cantidad real (L)'), '2');
      await confirm(tester, button, taps: 2);

      final applications = await rows(tester, h.database, 'applications');
      expect(applications, hasLength(1));
      final row = applications.single;
      expect(row['campaign_id'], h.campaign);
      final stored = row['applied_at']! as String;
      expect(storedLocalDay(stored), choice.day);
      final local = DateTime.parse(stored).toLocal();
      expect([local.hour, local.minute, local.second], [0, 0, 0]);
      // Precisión de área de #115: el chaco de 10 000 m² se guarda exacto.
      expect(row['treated_area_m2'], 10000);
      expect(
        (await rows(
          tester,
          h.database,
          'application_items',
        )).single['quantity_base'],
        2000,
      );
    });

    testWidgets('cancelar el selector conserva el borrador', (tester) async {
      final h = await home(tester, 'aplicacion-cancelar');
      final c = await pumpModeApp(tester, h.database);
      c.read(routerProvider).push('/aplicaciones/nueva');
      await waitFor(tester, picker('Chaco'));
      await settle(tester);
      await fillApplication(tester);
      await cancelPicker(tester, tile);
      expect(
        find.descendant(
          of: dateTile(tile),
          matching: find.textContaining('(hoy)'),
        ),
        findsOneWidget,
      );
      expect(fieldText(tester, 'Cantidad real (L)'), '2');
      expect(await rows(tester, h.database, 'applications'), isEmpty);
    });

    testWidgets('hoy fuera de toda campaña: se rechaza con el mensaje y sin '
        'escribir', (tester) async {
      final h = await home(
        tester,
        'aplicacion-sin-campana',
        endYesterday: true,
      );
      final c = await pumpModeApp(tester, h.database);
      c.read(routerProvider).push('/aplicaciones/nueva');
      await waitFor(tester, picker('Chaco'));
      await settle(tester);
      await fillApplication(tester);
      final before = await dump(tester, h.database);
      await confirm(tester, button);
      expect(find.textContaining('ninguna campaña'), findsOneWidget);
      expect(find.byKey(button), findsOneWidget);
      expect(await dump(tester, h.database), before);
    });
  });
}
