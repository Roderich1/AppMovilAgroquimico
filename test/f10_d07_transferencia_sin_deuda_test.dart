// D-07 (bloque 2): una transferencia entrega producto sin generar deuda.
//
// Se mantiene RN-35 (transferir no inserta filas en `account_transactions`) y,
// por decisión del autor (Roderich Rendón) del 2026-10-27, la confirmación lo
// dice antes de guardar: «Esta transferencia entrega producto a [persona],
// pero no genera una deuda». Se comprueba con un familiar y con un tercero que
// paga por compra (THIRD_PARTY, BY_PURCHASE_ALLOCATION), y que el historial
// —lista y detalle de transferencias, aviso de reversión y movimientos del
// detalle de producto— no presenta la entrega como venta ni como deuda: el
// costo FIFO se rotula como costo de referencia.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/presentation/screens/inventory_detail_screen.dart';
import 'package:agroquimicos/presentation/screens/transfer_form_screen.dart';
import 'package:agroquimicos/presentation/screens/transfers_screen.dart';
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
  late int ana, beto, carlos, supplier, campaign, glifosato, atrazina;

  /// Ana (familiar) compra Glifosato y Atrazina para sí; Don Carlos (tercero,
  /// cobro por compra) compra 2 L de Glifosato, que le dejan un cargo previo.
  Future<void> seed() async {
    database = AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    repo = AgroRepository(database);
    db = await database.database;
    ana = await repo.addPerson(name: 'Ana', role: PersonRole.family);
    beto = await repo.addPerson(name: 'Beto', role: PersonRole.family);
    carlos = await repo.addPerson(
      name: 'Don Carlos',
      role: PersonRole.thirdParty,
    );
    supplier = await repo.addSupplier(name: 'Agro Sur');
    campaign = await repo.addCampaign(
      name: 'Verano',
      start: DateTime.utc(2026, 1, 1),
    );
    glifosato = await repo.addProduct(name: 'Glifosato');
    atrazina = await repo.addProduct(name: 'Atrazina');
    PurchaseItemDraft line(int product, int person, int qty, int price) =>
        PurchaseItemDraft(
          productId: product,
          quantityBase: qty,
          currency: CurrencyCode.bob,
          originalUnitPriceMinor: price,
          allocations: [AllocationDraft(personId: person, quantityBase: qty)],
        );
    await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: supplier,
        campaignId: campaign,
        purchaseDate: DateTime.utc(2026, 1, 5, 12),
        items: [
          line(glifosato, ana, 10000, 10000),
          line(atrazina, ana, 5000, 8000),
        ],
      ),
    );
    await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: supplier,
        campaignId: campaign,
        purchaseDate: DateTime.utc(2026, 1, 6, 12),
        items: [line(glifosato, carlos, 2000, 10000)],
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

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          activatedInstallationForTests(),
        ],
        child: MaterialApp(home: home),
      ),
    );
    await settle(tester);
  }

  Future<List<Map<String, Object?>>> accountRows(WidgetTester tester) async =>
      (await tester.runAsync(
        () => db.query('account_transactions', orderBy: 'id'),
      ))!;

  Future<int> count(WidgetTester tester, String table) async =>
      (await tester.runAsync(() => db.query(table)))!.length;

  group('confirmación de la transferencia', () {
    /// Abre el formulario sobre una página anfitriona para que el `pop(true)`
    /// del guardado tenga a dónde volver.
    Future<void> openForm(WidgetTester tester) async {
      await pump(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
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
      );
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

    Future<void> quantity(
      WidgetTester tester,
      String product,
      String text,
    ) async {
      await tester.enterText(
        find.descendant(
          of: find.widgetWithText(ListTile, product),
          matching: find.byType(TextField),
        ),
        text,
      );
      await tester.pump();
    }

    Finder inDialog(String text) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(text),
    );

    testWidgets('a un familiar: la confirmación dice que entrega producto a '
        'Beto sin deuda y, al confirmar, no aparece ningún asiento', (
      tester,
    ) async {
      await tester.runAsync(seed);
      addTearDown(() => database.close());
      await openForm(tester);
      await choose(tester, 'Persona origen', 'Ana');
      await quantity(tester, 'Glifosato', '3');
      await choose(tester, 'Persona destino', 'Beto');

      final before = await accountRows(tester);
      await tester.tap(find.text('Revisar y confirmar'));
      await settle(tester, rounds: 3);

      expect(find.text('Confirmar transferencia'), findsOneWidget);
      expect(
        inDialog(
          'Esta transferencia entrega producto a Beto, pero no genera una '
          'deuda.',
        ),
        findsOneWidget,
      );
      expect(
        inDialog(
          'No se registra ningún cargo ni cobro a Beto. El costo del '
          'producto entregado sólo es de referencia, no un precio de venta.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Confirmar'));
      await settle(tester);
      expect(find.byType(TransferFormScreen), findsNothing);
      expect(await count(tester, 'transfers'), 1);
      // RN-35: ninguna fila nueva ni cambiada en `account_transactions`.
      expect(await accountRows(tester), before);
      expect(
        (await accountRows(tester)).map((r) => r['type']),
        isNot(contains('TRANSFER_CHARGE')),
      );
    });

    testWidgets('a un tercero con cobro por compra y dos productos: la misma '
        'frase con su nombre y su cuenta no cambia', (tester) async {
      await tester.runAsync(seed);
      addTearDown(() => database.close());
      final policy = (await tester.runAsync(
        () => db.query('persons', where: 'id=?', whereArgs: [carlos]),
      ))!.single;
      expect(policy['role'], 'THIRD_PARTY');
      expect(policy['settlement_policy'], 'BY_PURCHASE_ALLOCATION');

      await openForm(tester);
      await choose(tester, 'Persona origen', 'Ana');
      await quantity(tester, 'Glifosato', '2');
      await quantity(tester, 'Atrazina', '1');
      await choose(tester, 'Persona destino', 'Don Carlos');

      final before = await accountRows(tester);
      // El cargo previo del tercero existe: lo que se comprueba es que la
      // transferencia no añade otro.
      expect(before.map((r) => (r['person_id'], r['type'])), [
        (carlos, 'PURCHASE_ALLOCATION_CHARGE'),
      ]);
      await tester.tap(find.text('Revisar y confirmar'));
      await settle(tester, rounds: 3);

      expect(inDialog('Glifosato: 2 L'), findsOneWidget);
      expect(inDialog('Atrazina: 1 L'), findsOneWidget);
      expect(
        inDialog(
          'Esta transferencia entrega producto a Don Carlos, pero no genera '
          'una deuda.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Confirmar'));
      await settle(tester);
      expect(find.byType(TransferFormScreen), findsNothing);
      expect(await count(tester, 'transfers'), 1);
      expect(await count(tester, 'transfer_items'), 2);
      expect(await accountRows(tester), before);
      final balance = (await tester.runAsync(
        () => db.rawQuery(
          'SELECT COALESCE(SUM(amount_bob_minor_signed),0) s '
          'FROM account_transactions WHERE person_id=?',
          [carlos],
        ),
      ))!.single['s'];
      expect(balance, 20000, reason: 'sólo el cargo de su propia compra');
    });

    testWidgets('«Revisar» cierra la confirmación sin guardar nada', (
      tester,
    ) async {
      await tester.runAsync(seed);
      addTearDown(() => database.close());
      await openForm(tester);
      await choose(tester, 'Persona origen', 'Ana');
      await quantity(tester, 'Glifosato', '1');
      await choose(tester, 'Persona destino', 'Don Carlos');
      final before = await accountRows(tester);
      await tester.tap(find.text('Revisar y confirmar'));
      await settle(tester, rounds: 3);
      expect(find.byKey(const Key('transfer-no-debt-notice')), findsOneWidget);
      await tester.tap(find.text('Revisar'));
      await settle(tester, rounds: 3);
      expect(find.byType(AlertDialog), findsNothing);
      expect(await count(tester, 'transfers'), 0);
      expect(await accountRows(tester), before);
    });
  });

  group('historial', () {
    /// Ana entrega 3 L de Glifosato a Don Carlos y 1 L a Beto; la segunda se
    /// revierte para que el detalle de producto tenga también las reversiones.
    Future<void> seedHistory() async {
      await seed();
      await repo.transferProductsFifo(
        fromPersonId: ana,
        toPersonId: carlos,
        items: [TransferItemDraft(productId: glifosato, quantityBase: 3000)],
        date: DateTime.utc(2026, 1, 10, 12),
      );
      final toBeto = await repo.transferProductsFifo(
        fromPersonId: ana,
        toPersonId: beto,
        items: [TransferItemDraft(productId: glifosato, quantityBase: 1000)],
        date: DateTime.utc(2026, 1, 11, 12),
      );
      await repo.reverseTransferUnauditedForTesting(toBeto, reason: 'Error');
    }

    testWidgets('la lista dice «Entrega sin deuda» y el detalle rotula el '
        'costo como referencia, no como lo que el otro debe', (tester) async {
      await tester.runAsync(seedHistory);
      addTearDown(() => database.close());
      await pump(tester, const Scaffold(body: TransfersScreen()));

      expect(
        find.text(
          'Entregas de producto de una persona a otra. No generan deuda; el '
          'costo es sólo de referencia.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('10/01/2026 · Glifosato 3 L\nEntrega sin deuda'),
        findsOneWidget,
      );
      expect(
        find.text('11/01/2026 · Glifosato 1 L\nEntrega sin deuda'),
        findsOneWidget,
      );

      await tester.tap(find.text('Ana → Don Carlos'));
      await settle(tester, rounds: 3);
      expect(
        find.textContaining(
          '1 producto(s) · 1 lote(s) · costo de referencia 300,00',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Es el costo de compra del producto entregado, no un precio de '
          'venta: Don Carlos no debe nada por esta entrega.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('el aviso de reversión dice que la transferencia no generó '
        'deuda; cancelar no cambia nada', (tester) async {
      await tester.runAsync(seedHistory);
      addTearDown(() => database.close());
      await pump(tester, const Scaffold(body: TransfersScreen()));
      final before = await accountRows(tester);

      await tester.tap(find.byIcon(Icons.undo));
      await settle(tester, rounds: 3);
      final effects = tester
          .widget<Text>(find.byKey(const Key('approval-effects')))
          .data!;
      expect(effects, contains('Ana → Don Carlos'));
      expect(
        effects,
        contains('sólo de referencia: la transferencia no generó deuda.'),
      );
      expect(
        effects,
        contains(
          'El stock volverá a la persona de origen y ninguna cuenta cambia.',
        ),
      );
      await tester.tap(find.text('Cancelar'));
      await settle(tester, rounds: 3);
      expect(await accountRows(tester), before);
    });

    testWidgets('en los movimientos del producto los pases se leen como '
        'entrega sin deuda, también sus reversiones', (tester) async {
      await tester.runAsync(seedHistory);
      addTearDown(() => database.close());
      await pump(
        tester,
        Scaffold(body: InventoryDetailScreen(productId: glifosato)),
      );

      final list = find.byKey(const Key('inventory-movements'));
      expect(list, findsOneWidget);
      final subtitles = {
        for (final tile in tester.widgetList<ListTile>(
          find.descendant(of: list, matching: find.byType(ListTile)),
        ))
          '${(tile.title! as Text).data} | ${(tile.subtitle! as Text).data}',
      };
      expect(
        subtitles,
        containsAll([
          'Pase a Don Carlos | 10/01/2026 · Ana · entrega sin deuda',
          'Recibido de Ana | 10/01/2026 · Don Carlos · entrega sin deuda',
          'Pase a Beto | 11/01/2026 · Ana · entrega sin deuda',
          'Recibido de Ana | 11/01/2026 · Beto · entrega sin deuda',
        ]),
      );
      expect(
        subtitles.where((s) => s.startsWith('Pase revertido')),
        hasLength(2),
      );
      for (final s in subtitles.where((s) => s.startsWith('Pase revertido'))) {
        expect(s, endsWith(' · sin deuda'));
      }
      // Las compras y su proveedor siguen igual.
      expect(subtitles, contains('Compra | 05/01/2026 · Ana · Agro Sur'));
      expect(
        find.text(
          'Lo que explica el saldo: compras, aplicaciones, pases (entregas '
          'sin deuda) y reversiones, del más reciente al más antiguo.',
        ),
        findsOneWidget,
      );
    });
  });
}
