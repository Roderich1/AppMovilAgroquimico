// B-04: sin dosis, la aplicación guarda teórico y desvío nulos (no «teórico
// 0» y «desvío = toda la cantidad»); con dosis, el teórico de siempre. El
// área tratada vacía o mal escrita se rechaza al continuar el paso 1 con el
// mensaje de formato de `numeric_input.dart`. Formulario real montado
// directo sobre una base sembrada, y el repositorio por su cuenta.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/presentation/screens/application_form_screen.dart';
import 'package:agroquimicos/presentation/widgets/adaptive_entity_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.pump();
    await tester.tap(find.byKey(Key(key)));
    await settle(tester);
  }

  final navigator = GlobalKey<NavigatorState>();

  Future<({AppDatabase db, AgroRepository repo, Household h})> seed(
    String name,
  ) async {
    final db = openDb(await tempDbPath(name));
    final repo = AgroRepository(db);
    final h = await seedHousehold(repo);
    await h.buy(h.titular, 10000);
    return (db: db, repo: repo, h: h);
  }

  Future<void> openForm(WidgetTester tester, AgroRepository repo) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
      MaterialPageRoute<bool>(builder: (_) => const ApplicationFormScreen()),
    );
    await waitFor(tester, picker('Chaco'));
    await settle(tester);
    await choose(tester, 'Persona', 'Titular');
    await choose(tester, 'Chaco', 'Chaco titular');
  }

  Future<List<Row>> items(WidgetTester tester, AppDatabase db) async =>
      (await tester.runAsync(
        () async => (await db.database).query(
          'application_items',
          columns: [
            'quantity_base',
            'treated_area_m2',
            'dose_base_per_ha',
            'theoretical_quantity_base',
            'variance_quantity_base',
          ],
          orderBy: 'id',
        ),
      ))!;

  Future<void> addGlifosato(WidgetTester tester, String quantity) async {
    await tapKey(tester, 'application-add-product');
    await choose(tester, 'Producto', 'Glifosato');
    await tester.enterText(
      find.byKey(const Key('application-line-quantity')),
      quantity,
    );
    await tapKey(tester, 'application-line-add');
  }

  Future<void> confirm(WidgetTester tester) async {
    await tapKey(tester, 'application-continue');
    await tapKey(tester, 'application-confirm');
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
  }

  testWidgets('sin dosis: teórico y desvío quedan nulos; el detalle lo dice', (
    tester,
  ) async {
    final s = (await tester.runAsync(() => seed('sin-dosis')))!;
    await openForm(tester, s.repo);
    await tapKey(tester, 'application-continue');
    await addGlifosato(tester, '2');
    await tapKey(tester, 'application-line-detail-${s.h.product}');
    expect(
      find.textContaining('Sin dosis no se calcula el teórico'),
      findsOneWidget,
    );
    expect(find.textContaining('Teórico por dosis y área'), findsNothing);
    await confirm(tester);

    expect(await items(tester, s.db), [
      {
        'quantity_base': 2000,
        'treated_area_m2': 10000,
        'dose_base_per_ha': null,
        'theoretical_quantity_base': null,
        'variance_quantity_base': null,
      },
    ]);
  });

  testWidgets('con dosis: el teórico y el desvío de siempre', (tester) async {
    final s = (await tester.runAsync(() => seed('con-dosis')))!;
    await openForm(tester, s.repo);
    await tapKey(tester, 'application-continue');
    await addGlifosato(tester, '2');
    await tapKey(tester, 'application-line-detail-${s.h.product}');
    await tester.enterText(
      find.widgetWithText(TextField, 'Dosis (L/ha)'),
      '1,5',
    );
    await tester.pump();
    expect(
      find.textContaining('Teórico por dosis y área: 1,5 L'),
      findsOneWidget,
    );
    await confirm(tester);

    expect(await items(tester, s.db), [
      {
        'quantity_base': 2000,
        'treated_area_m2': 10000,
        'dose_base_per_ha': 1500,
        'theoretical_quantity_base': 1500,
        'variance_quantity_base': 500,
      },
    ]);
  });

  testWidgets('dosis mal escrita: el campo lo dice y no se guarda como «sin '
      'dosis»', (tester) async {
    final s = (await tester.runAsync(() => seed('dosis-mal')))!;
    await openForm(tester, s.repo);
    await tapKey(tester, 'application-continue');
    await addGlifosato(tester, '2');
    await tapKey(tester, 'application-line-detail-${s.h.product}');
    await tester.enterText(
      find.widgetWithText(TextField, 'Dosis (L/ha)'),
      '1.5',
    );
    await tester.pump();
    expect(
      find.textContaining('Escriba el número como 1.500,25'),
      findsOneWidget,
    );
    await confirm(tester);
    expect(find.textContaining('Dosis de Glifosato:'), findsOneWidget);
    expect(await items(tester, s.db), isEmpty);
  });

  testWidgets('área vacía o mal escrita: no se continúa y el campo explica el '
      'formato', (tester) async {
    final s = (await tester.runAsync(() => seed('area')))!;
    await openForm(tester, s.repo);
    final area = find.byKey(const Key('application-area'));

    await tester.enterText(area, '');
    await tapKey(tester, 'application-continue');
    expect(find.text('Paso 1 de 3 · Persona y chaco'), findsOneWidget);
    expect(find.text('Escribe el área tratada en hectáreas.'), findsOneWidget);

    await tester.enterText(area, '1.5');
    await tapKey(tester, 'application-continue');
    expect(find.text('Paso 1 de 3 · Persona y chaco'), findsOneWidget);
    expect(
      find.text(
        'Escriba el número como 1.500,25: use la coma para los decimales y '
        'el punto para los miles.',
      ),
      findsOneWidget,
    );

    await tester.enterText(area, '1,500');
    await tapKey(tester, 'application-continue');
    expect(find.text('Paso 1 de 3 · Persona y chaco'), findsOneWidget);
    expect(find.textContaining('"1,500" es ambiguo'), findsOneWidget);

    await tester.enterText(area, '0');
    await tapKey(tester, 'application-continue');
    expect(find.text('Paso 1 de 3 · Persona y chaco'), findsOneWidget);
    expect(
      find.text('El área tratada debe ser mayor que cero.'),
      findsOneWidget,
    );

    await tester.enterText(area, '1,5');
    await tapKey(tester, 'application-continue');
    expect(find.text('Paso 2 de 3 · Productos y cantidades'), findsOneWidget);
    await addGlifosato(tester, '2');
    await confirm(tester);
    expect((await items(tester, s.db)).single['treated_area_m2'], 15000);
  });

  test('repositorio: una línea sin teórico se guarda con teórico y desvío '
      'nulos', () async {
    final database = openDb(inMemoryDatabasePath);
    final repo = AgroRepository(database);
    final h = await seedHousehold(repo);
    await h.buy(h.titular, 10000);
    await repo.confirmApplication(
      ApplicationDraft(
        personId: h.titular,
        farmId: h.titularFarm,
        campaignId: h.campaign,
        appliedAt: DateTime.utc(2026, 2, 1, 12),
        treatedAreaM2: 10000,
        lines: [
          ApplicationLineDraft(
            productId: h.product,
            quantityBase: 2000,
            treatedAreaM2: 10000,
          ),
        ],
      ),
    );
    final rows = await (await database.database).rawQuery(
      'SELECT theoretical_quantity_base IS NULL t, '
      'variance_quantity_base IS NULL v FROM application_items',
    );
    expect(rows, [
      {'t': 1, 'v': 1},
    ]);
  });
}
