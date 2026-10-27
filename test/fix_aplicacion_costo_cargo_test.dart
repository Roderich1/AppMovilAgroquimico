// Paso 3 de Nueva aplicación (B-06): el resumen muestra el costo estimado por
// producto y en total, y el cargo que corresponde a la persona según su
// política de cobro, distinguiéndolos. Se recorre el formulario real sobre una
// base sembrada; cómo se calcula y se escribe el cargo no cambia.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/money.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
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

  /// Recorrido explícito completo para un producto.
  Future<void> addProduct(
    WidgetTester tester,
    String name,
    String quantity,
  ) async {
    await tapKey(tester, 'application-add-product');
    await choose(tester, 'Producto', name);
    await tester.enterText(
      find.byKey(const Key('application-line-quantity')),
      quantity,
    );
    await tapKey(tester, 'application-line-add');
  }

  /// Glifosato a 100,00 Bs/L y Bellator a 200,00 Bs/L, 10 L de cada uno para
  /// [person].
  Future<int> stockFor(Household h, int person) async {
    final bellator = await h.repo.addProduct(name: 'Bellator');
    await h.repo.confirmPurchase(
      PurchaseDraft(
        supplierId: h.supplier,
        campaignId: h.campaign,
        purchaseDate: DateTime.utc(2026, 1, 2, 12),
        items: [
          for (final (product, price) in [
            (h.product, 10000),
            (bellator, 20000),
          ])
            PurchaseItemDraft(
              productId: product,
              quantityBase: 10000,
              currency: CurrencyCode.bob,
              originalUnitPriceMinor: price,
              allocations: [
                AllocationDraft(personId: person, quantityBase: 10000),
              ],
            ),
        ],
      ),
    );
    return bellator;
  }

  /// 0,2 L de Glifosato (20,00 Bs) y 0,1 L de Bellator (20,00 Bs): 40,00 Bs.
  Future<void> mixAndReview(WidgetTester tester) async {
    await addProduct(tester, 'Glifosato', '0,2');
    await addProduct(tester, 'Bellator', '0,1');
    await tapKey(tester, 'application-continue');
    expect(find.text('Paso 3 de 3 · Resumen y confirmación'), findsOneWidget);
  }

  void expectCosts(WidgetTester tester, int glifosato, int bellator) {
    expect(
      find.byKey(Key('application-review-cost-$glifosato')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.byKey(Key('application-review-cost-$glifosato')))
          .data,
      formatBob(2000),
    );
    expect(
      tester
          .widget<Text>(find.byKey(Key('application-review-cost-$bellator')))
          .data,
      formatBob(2000),
    );
    expect(
      find.text('Costo total estimado: ${formatBob(4000)}'),
      findsOneWidget,
    );
  }

  group('compartida (formulario montado directo, sin activación)', () {
    final navigator = GlobalKey<NavigatorState>();

    Future<({AgroRepository repo, Household h, int bellator})> seed(
      String name,
      int Function(Household) person,
    ) async {
      final db = openDb(await tempDbPath(name));
      final repo = AgroRepository(db);
      final h = await seedHousehold(repo);
      await repo.addFarm(
        ownerId: h.thirdParty,
        name: 'Chaco vecino',
        areaM2: 5000,
      );
      final bellator = await stockFor(h, person(h));
      return (repo: repo, h: h, bellator: bellator);
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
    }

    testWidgets('cobro por consumo: costo por producto, total y «Se cargará '
        'a …»', (tester) async {
      final s = (await tester.runAsync(
        () => seed('consumo', (h) => h.titular),
      ))!;
      await openForm(tester, s.repo);
      await choose(tester, 'Persona', 'Titular');
      await choose(tester, 'Chaco', 'Chaco titular');
      await tapKey(tester, 'application-continue');
      await mixAndReview(tester);

      expectCosts(tester, s.h.product, s.bellator);
      expect(
        find.text('Se cargará a Titular: ${formatBob(4000)}'),
        findsOneWidget,
      );
      expect(find.textContaining('No genera cargo'), findsNothing);
    });

    testWidgets('cobro por compra: el mismo costo y «No genera cargo»', (
      tester,
    ) async {
      final s = (await tester.runAsync(
        () => seed('compra', (h) => h.thirdParty),
      ))!;
      await openForm(tester, s.repo);
      await choose(tester, 'Persona', 'Vecino');
      await choose(tester, 'Chaco', 'Chaco vecino');
      await tapKey(tester, 'application-continue');
      await mixAndReview(tester);

      expectCosts(tester, s.h.product, s.bellator);
      expect(
        find.text(
          'No genera cargo: Vecino ya pagó estos productos al comprarlos',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Se cargará'), findsNothing);
    });
  });

  testWidgets('propia: el titular ve «Costo propio»', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, 'propia-costo');
    final bellator = (await tester.runAsync(() async {
      final bellator = await stockFor(s.household, s.household.titular);
      await OperationModeStore(s.database)
          .apply(OperationMode.personal, confirmed: true);
      return bellator;
    }))!;
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).push('/aplicaciones/nueva');
    await waitFor(tester, picker('Chaco'));
    await settle(tester);
    await choose(tester, 'Chaco', 'Chaco titular');
    await tapKey(tester, 'application-continue');
    await mixAndReview(tester);

    expectCosts(tester, s.household.product, bellator);
    expect(find.text('Costo propio: ${formatBob(4000)}'), findsOneWidget);
    expect(find.textContaining('Se cargará'), findsNothing);
  });
}
