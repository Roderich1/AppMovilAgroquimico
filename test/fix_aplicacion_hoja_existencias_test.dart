// E-08, revisión cruzada: la hoja de producto compara con lo disponible de la
// persona elegida (dos personas con stock distinto) y «Cambiar producto»
// también rechaza una cantidad por encima; y el texto de cargo para una
// política MANUAL. Formulario real montado directo sobre una base sembrada.
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

  final quantityField = find.byKey(const Key('application-line-quantity'));
  final addButton = find.byKey(const Key('application-line-add'));

  bool addEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(addButton).onPressed != null;

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(quantityField, text);
    await settle(tester);
  }

  final navigator = GlobalKey<NavigatorState>();

  /// Titular con 1,5 L y Hermana con 0,5 L de Glifosato.
  Future<({AppDatabase db, AgroRepository repo, Household h})> seed(
    String name,
  ) async {
    final db = openDb(await tempDbPath(name));
    final repo = AgroRepository(db);
    final h = await seedHousehold(repo);
    await h.buy(h.titular, 1500);
    await h.buy(h.relative, 500);
    return (db: db, repo: repo, h: h);
  }

  Future<void> openForm(
    WidgetTester tester,
    AgroRepository repo,
    String person,
    String farm,
  ) async {
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
    await choose(tester, 'Persona', person);
    await choose(tester, 'Chaco', farm);
    await tapKey(tester, 'application-continue');
  }

  testWidgets(
    '«Cambiar producto»: una cantidad por encima deshabilita «Guardar '
    'cambios» y la tarjeta no cambia; una válida sí se guarda',
    (tester) async {
      final s = (await tester.runAsync(() => seed('editar')))!;
      await openForm(tester, s.repo, 'Titular', 'Chaco titular');
      await tapKey(tester, 'application-add-product');
      await choose(tester, 'Producto', 'Glifosato');
      await type(tester, '1');
      await tapKey(tester, 'application-line-add');
      expect(find.text('1 L'), findsOneWidget);

      await tapKey(tester, 'application-line-edit-${s.h.product}');
      expect(find.text('Guardar cambios'), findsOneWidget);
      await type(tester, '200');
      expect(
        find.text(
          'Pediste 200 L y hay 1,5 L. Baja la cantidad o registra primero la '
          'compra.',
        ),
        findsOneWidget,
      );
      expect(addEnabled(tester), isFalse);
      await tapKey(tester, 'application-line-add');
      // La hoja sigue abierta y la tarjeta conserva 1 L.
      expect(find.text('Guardar cambios'), findsOneWidget);

      await type(tester, '1,5');
      expect(find.textContaining('Pediste'), findsNothing);
      expect(addEnabled(tester), isTrue);
      await tapKey(tester, 'application-line-add');
      expect(find.text('Guardar cambios'), findsNothing);
      expect(find.text('1,5 L'), findsOneWidget);
      expect(find.text('1 L'), findsNothing);
      expect(find.textContaining('faltan'), findsNothing);
    },
  );

  testWidgets(
    'compartida con dos personas: «hay» es lo de la persona elegida',
    (tester) async {
      final s = (await tester.runAsync(() => seed('dos-personas')))!;
      await openForm(tester, s.repo, 'Hermana', 'Chaco hermana');
      await tapKey(tester, 'application-add-product');
      expect(
        find.descendant(
          of: picker('Producto'),
          matching: find.text('Seleccionar'),
        ),
        findsOneWidget,
      );
      await choose(tester, 'Producto', 'Glifosato');
      expect(find.text('Hay 0,5 L.'), findsOneWidget);
      // 1 L cabría en lo del titular (1,5 L), pero no en lo de la hermana.
      await type(tester, '1');
      expect(
        find.text(
          'Pediste 1 L y hay 0,5 L. Baja la cantidad o registra primero la '
          'compra.',
        ),
        findsOneWidget,
      );
      expect(addEnabled(tester), isFalse);
      await type(tester, '0,5');
      expect(addEnabled(tester), isTrue);
      await tapKey(tester, 'application-line-add');
      expect(find.text('Productos (1)'), findsOneWidget);
      expect(find.text('0,5 L'), findsOneWidget);
    },
  );

  testWidgets('política MANUAL: el resumen dice que la cuenta se ajusta a '
      'mano', (tester) async {
    final s = (await tester.runAsync(() => seed('manual')))!;
    await tester.runAsync(
      () async => (await s.db.database).update(
        'persons',
        {'settlement_policy': SettlementPolicy.manual.code},
        where: 'id=?',
        whereArgs: [s.h.relative],
      ),
    );
    await openForm(tester, s.repo, 'Hermana', 'Chaco hermana');
    await tapKey(tester, 'application-add-product');
    await choose(tester, 'Producto', 'Glifosato');
    await type(tester, '0,5');
    await tapKey(tester, 'application-line-add');
    await tapKey(tester, 'application-continue');
    expect(
      find.text(
        'No genera cargo automático: la cuenta de Hermana se ajusta a mano',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Se cargará'), findsNothing);
  });
}
