// OE3 (2026-11-03): cantidad con decimales en la transferencia. Misma persona,
// producto, unidad y existencias para cada entrada. Regla vigente
// (docs/44_NUMERIC_INPUT_SPEC.md): la coma separa decimales y el punto, miles.
// Antes, «1.5» (`malformed`) no avanzaba y el único aviso era «Seleccione
// origen, destino y al menos una cantidad válida.», con los dos elegidos.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/presentation/screens/transfer_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_app_access.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late AgroRepository repo;
  late Database db;
  late int ana, glifosato;

  Future<void> seed() async {
    database = AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    repo = AgroRepository(database);
    db = await database.database;
    ana = await repo.addPerson(name: 'Ana', role: PersonRole.family);
    await repo.addPerson(name: 'Beto', role: PersonRole.family);
    final supplier = await repo.addSupplier(name: 'Agro Sur');
    final campaign = await repo.addCampaign(
      name: 'Verano',
      start: DateTime.utc(2026, 1, 1),
    );
    glifosato = await repo.addProduct(name: 'Glifosato');
    await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: supplier,
        campaignId: campaign,
        purchaseDate: DateTime.utc(2026, 1, 5, 12),
        items: [
          PurchaseItemDraft(
            productId: glifosato,
            quantityBase: 5000,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 30000,
            allocations: [AllocationDraft(personId: ana, quantityBase: 5000)],
          ),
        ],
      ),
    );
  }

  Future<void> settle(WidgetTester tester, {int rounds = 8}) async {
    for (var round = 0; round < rounds; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
  }

  Future<void> openForm(WidgetTester tester) async {
    tester.view.physicalSize = const Size(600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          activatedInstallationForTests(),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<bool>(
                    builder: (_) => const TransferFormScreen(),
                  ),
                ),
                child: const Text('Abrir formulario'),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Abrir formulario'));
    await settle(tester);
  }

  Future<void> choose(WidgetTester tester, String picker, String name) async {
    await tester.tap(
      find
          .ancestor(of: find.text(picker), matching: find.byType(InkWell))
          .first,
    );
    await settle(tester, rounds: 3);
    await tester.tap(find.text(name).last);
    await settle(tester);
  }

  Future<void> fill(WidgetTester tester, String text) async {
    await tester.enterText(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Glifosato'),
        matching: find.byType(TextField),
      ),
      text,
    );
    await tester.pump();
    await choose(tester, 'Persona destino', 'Beto');
    await tester.tap(find.text('Revisar y confirmar'));
    await settle(tester, rounds: 3);
  }

  Future<List<Map<String, Object?>>> rows(
    WidgetTester tester,
    String sql,
  ) async => (await tester.runAsync(() => db.rawQuery(sql)))!;

  String? snack() {
    final texts = find
        .descendant(of: find.byType(SnackBar), matching: find.byType(Text))
        .evaluate()
        .map((e) => (e.widget as Text).data)
        .toList();
    return texts.isEmpty ? null : texts.last;
  }

  Future<void> start(WidgetTester tester) async {
    await tester.runAsync(seed);
    addTearDown(() => database.close());
    await openForm(tester);
    await choose(tester, 'Persona origen', 'Ana');
  }

  testWidgets('«1,5» es válido: confirma 1,5 L y guarda 1500 en unidad base, '
      'con salida y entrada compensadas', (tester) async {
    await start(tester);
    await fill(tester, '1,5');
    expect(find.text('Confirmar transferencia'), findsOneWidget);
    expect(find.textContaining('Glifosato: 1,5 L'), findsOneWidget);
    await tester.tap(find.text('Confirmar'));
    await settle(tester);
    expect(await rows(tester, 'SELECT quantity_base FROM transfers'), [
      {'quantity_base': 1500},
    ]);
    expect(
      await rows(
        tester,
        "SELECT type, quantity_signed FROM inventory_movements "
        "WHERE type LIKE 'TRANSFER%' ORDER BY id",
      ),
      [
        {'type': 'TRANSFER_OUT', 'quantity_signed': -1500},
        {'type': 'TRANSFER_IN', 'quantity_signed': 1500},
      ],
    );
  });

  testWidgets('«1.5» es inválido: no avanza, dice cuál cantidad y por qué, y '
      'no guarda nada', (tester) async {
    await start(tester);
    await fill(tester, '1.5');
    expect(find.text('Confirmar transferencia'), findsNothing);
    expect(
      snack(),
      'Revise la cantidad de Glifosato. Escriba el número como 1.500,25: use '
      'la coma para los decimales y el punto para los miles.',
    );
    expect(await rows(tester, 'SELECT id FROM transfers'), isEmpty);
    // El texto tecleado no se altera.
    expect(find.widgetWithText(TextField, '1.5'), findsOneWidget);
  });

  testWidgets('«1,500» es ambiguo: no avanza y propone las dos lecturas', (
    tester,
  ) async {
    await start(tester);
    await fill(tester, '1,500');
    expect(find.text('Confirmar transferencia'), findsNothing);
    expect(
      snack(),
      startsWith('Revise la cantidad de Glifosato. "1,500" es ambiguo'),
    );
    expect(await rows(tester, 'SELECT id FROM transfers'), isEmpty);
  });

  testWidgets('sin cantidad: se mantiene el aviso de siempre', (tester) async {
    await start(tester);
    await fill(tester, '');
    expect(find.text('Confirmar transferencia'), findsNothing);
    expect(
      snack(),
      'Seleccione origen, destino y al menos una cantidad válida.',
    );
  });
}
