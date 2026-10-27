// E-10: el detalle del producto lista los movimientos reales de
// `inventory_movements` con fecha, tipo en palabras, persona y cantidad con
// signo; lotes y valor físico quedan plegados; «Comprometido» y «Libre
// proyectado» pasan a «Reservado por planes» y «Quedará libre». Las lecturas
// se hacen una vez al abrir (B-15).
//
// Fixture (Glifosato en L; instantes a mediodía UTC: el día local coincide
// con el día UTC en cualquier zona entre UTC−11 y UTC+11, Bolivia incluida):
//   05/01 Ana compra 10 L a Agro Sur.      10/01 Ana aplica 3 L en Chaco Ana.
//   06/01 Ana compra 3 L a Agro Norte.
//   15/01 Ana pasa 2 L a Beto; se revierte.
//   17/01 Ana aplica 1 L; se revierte.
//   19/01 Beto compra 4 L a Agro Norte; se revierte.
//   21/01 Ana aplica 7 L: 4 L del lote del 05/01 y 3 L del lote del 06/01
//   (dos movimientos, una sola fila en el historial).
//   Las reversiones se fechan al revertir (ahora): van primero.
//
// D-03 (decisión del autor del 2026-10-27): una aplicación con fecha pasada
// sólo usa lo que había ese día y no se usó después. Las reversiones del
// pase y de la aplicación del 17/01 devuelven sus 3 L con la fecha de hoy,
// así que el 21/01 Ana tenía 4 L + 3 L. Antes la prueba aplicaba 8 L (7 + 1)
// contando esos 3 L; ahora aplica 7 L, también de dos lotes. Las doce
// aplicaciones extra de la prueba de «Ver más» van con la fecha de hoy, el
// único día en que queda saldo.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/presentation/screens/inventory_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_app_access.dart';
import 'support/f04_mode_fixtures.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late AgroRepository repo;
  late int ana, beto, glifosato, farmAna;

  DateTime day(int d) => DateTime.utc(2026, 1, d, 12);

  Future<int> buy(int person, int supplier, int qty, int d) =>
      repo.confirmPurchase(
        PurchaseDraft(
          supplierId: supplier,
          campaignId: 1,
          purchaseDate: day(d),
          items: [
            PurchaseItemDraft(
              productId: glifosato,
              quantityBase: qty,
              currency: CurrencyCode.bob,
              originalUnitPriceMinor: 10000,
              allocations: [
                AllocationDraft(personId: person, quantityBase: qty),
              ],
            ),
          ],
        ),
      );

  Future<int> applyAt(int qty, DateTime at) => repo.confirmApplication(
    ApplicationDraft(
      personId: ana,
      farmId: farmAna,
      campaignId: 1,
      appliedAt: at,
      lines: [ApplicationLineDraft(productId: glifosato, quantityBase: qty)],
    ),
  );

  Future<int> apply(int qty, int d) => applyAt(qty, day(d));

  /// Sólo la compra y la primera aplicación.
  Future<void> seedBasic() async {
    repo = AgroRepository(database);
    ana = await repo.addPerson(name: 'Ana', role: PersonRole.family);
    beto = await repo.addPerson(name: 'Beto', role: PersonRole.family);
    final sur = await repo.addSupplier(name: 'Agro Sur');
    await repo.addCampaign(name: 'Verano', start: DateTime.utc(2026, 1, 1));
    glifosato = await repo.addProduct(name: 'Glifosato');
    farmAna = await repo.addFarm(
      ownerId: ana,
      name: 'Chaco Ana',
      areaM2: 10000,
    );
    await buy(ana, sur, 10000, 5);
    await apply(3000, 10);
  }

  /// Además: segunda compra, pase y su reversión, aplicación revertida,
  /// compra revertida y una aplicación que consume de dos lotes.
  Future<void> seedAll() async {
    await seedBasic();
    final norte = await repo.addSupplier(name: 'Agro Norte');
    await buy(ana, norte, 3000, 6);
    final t1 = await repo.transferProductsFifo(
      fromPersonId: ana,
      toPersonId: beto,
      items: [TransferItemDraft(productId: glifosato, quantityBase: 2000)],
      date: day(15),
    );
    await repo.reverseTransferUnauditedForTesting(t1, reason: 'Equivocado');
    final a2 = await apply(1000, 17);
    await repo.reverseApplicationUnauditedForTesting(a2, reason: 'Error');
    final c2 = await buy(beto, norte, 4000, 19);
    await repo.reversePurchaseUnauditedForTesting(c2, reason: 'Devuelta');
    await apply(7000, 21);
  }

  group('repositorio', () {
    setUp(() async {
      database = openDb(inMemoryDatabasePath);
      await seedAll();
    });

    test('productMovements: del más reciente al más antiguo, con chaco, '
        'contraparte y proveedor según la referencia; una aplicación sobre '
        'dos lotes es una fila', () async {
      final rows = await repo.productMovements(glifosato);
      // 13 movimientos guardados (la aplicación del 21/01 son dos), 12 filas.
      expect(
        (await (await database.database).rawQuery(
          'SELECT COUNT(*) n FROM inventory_movements WHERE product_id=?',
          [glifosato],
        )).single['n'],
        13,
      );
      expect(rows, hasLength(12));
      final view = [
        for (final r in rows)
          (
            r['type'],
            r['owner_name'],
            r['quantity_signed'],
            r['farm_name'],
            r['counterpart_name'],
            r['supplier_name'],
          ),
      ];
      expect(view.take(5), [
        ('PURCHASE_REVERSAL', 'Beto', -4000, null, null, 'Agro Norte'),
        ('APPLICATION_REVERSAL', 'Ana', 1000, 'Chaco Ana', null, null),
        ('TRANSFER_REVERSAL_OUT', 'Beto', -2000, null, 'Ana', null),
        ('TRANSFER_REVERSAL_IN', 'Ana', 2000, null, 'Beto', null),
        ('APPLICATION_OUT', 'Ana', -7000, 'Chaco Ana', null, null),
      ]);
      expect(view.skip(5).toList(), [
        ('PURCHASE_IN', 'Beto', 4000, null, null, 'Agro Norte'),
        ('APPLICATION_OUT', 'Ana', -1000, 'Chaco Ana', null, null),
        ('TRANSFER_IN', 'Beto', 2000, null, 'Ana', null),
        ('TRANSFER_OUT', 'Ana', -2000, null, 'Beto', null),
        ('APPLICATION_OUT', 'Ana', -3000, 'Chaco Ana', null, null),
        ('PURCHASE_IN', 'Ana', 3000, null, null, 'Agro Norte'),
        ('PURCHASE_IN', 'Ana', 10000, null, null, 'Agro Sur'),
      ]);
      expect(rows.map((r) => r['movement_date']).skip(4), [
        '2026-01-21T12:00:00.000Z',
        '2026-01-19T12:00:00.000Z',
        '2026-01-17T12:00:00.000Z',
        '2026-01-15T12:00:00.000Z',
        '2026-01-15T12:00:00.000Z',
        '2026-01-10T12:00:00.000Z',
        '2026-01-06T12:00:00.000Z',
        '2026-01-05T12:00:00.000Z',
      ]);
      expect(await repo.productMovements(glifosato, limit: 3), hasLength(3));
      // Otro producto no se mezcla.
      final otro = await repo.addProduct(name: 'Otro');
      expect(await repo.productMovements(otro), isEmpty);
    });

    test('consultar no escribe', () async {
      final db = await database.database;
      final before = await dumpTables(db);
      await repo.productMovements(glifosato);
      expect(await dumpTables(db), before);
    });
  });

  group('pantalla', () {
    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      for (var frame = 0; frame < 8; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> waitFor(WidgetTester tester, Finder finder) async {
      for (var round = 0; round < 60; round++) {
        if (finder.evaluate().isNotEmpty) return;
        await settle(tester);
      }
    }

    Future<void> mount(
      WidgetTester tester,
      Future<void> Function() seed,
    ) async {
      await tester.runAsync(() async {
        database = AppDatabase(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
        );
        await seed();
      });
      addTearDown(database.close);
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(repo),
            activatedInstallationForTests(),
          ],
          child: MaterialApp(
            home: Scaffold(body: InventoryDetailScreen(productId: glifosato)),
          ),
        ),
      );
      await waitFor(tester, find.byKey(const Key('inventory-movements')));
    }

    testWidgets('con una compra y una aplicación, «Movimientos» muestra las '
        'dos filas con su fecha; lotes y valor quedan plegados; etiquetas '
        'nuevas', (tester) async {
      await mount(tester, seedBasic);
      final list = find.byKey(const Key('inventory-movements'));
      expect(
        find.descendant(of: list, matching: find.byType(ListTile)),
        findsNWidgets(2),
      );
      final tiles = tester
          .widgetList<ListTile>(
            find.descendant(of: list, matching: find.byType(ListTile)),
          )
          .toList();
      expect((tiles[0].title! as Text).data, 'Aplicación en Chaco Ana');
      expect((tiles[0].subtitle! as Text).data, '10/01/2026 · Ana');
      expect((tiles[0].trailing! as Text).data, '-3 L');
      expect((tiles[1].title! as Text).data, 'Compra');
      expect((tiles[1].subtitle! as Text).data, '05/01/2026 · Ana · Agro Sur');
      expect((tiles[1].trailing! as Text).data, '+10 L');
      expect(find.byKey(const Key('inventory-movements-more')), findsNothing);

      expect(find.text('Reservado por planes'), findsOneWidget);
      expect(find.text('Quedará libre'), findsOneWidget);
      expect(find.text('Comprometido'), findsNothing);
      expect(find.text('Libre proyectado'), findsNothing);
      // Plegado: el lote no se ve hasta desplegar.
      expect(find.text('Lotes disponibles y valor físico'), findsOneWidget);
      expect(find.textContaining('Lote #'), findsNothing);
      await tester.tap(find.text('Lotes disponibles y valor físico'));
      await settle(tester);
      expect(find.text('Ana · 7 L'), findsOneWidget);
    });

    testWidgets('todos los tipos en palabras y «Ver más» cuando hay más de '
        'veinte', (tester) async {
      await mount(tester, () async {
        await seedAll();
        // Doce aplicaciones más: 24 filas en total.
        for (var i = 0; i < 12; i++) {
          await applyAt(100, DateTime.now());
        }
      });
      final list = find.byKey(const Key('inventory-movements'));
      Iterable<String> titles() => tester
          .widgetList<ListTile>(
            find.descendant(of: list, matching: find.byType(ListTile)),
          )
          .map((t) => (t.title! as Text).data!);
      expect(titles(), hasLength(20));
      expect(find.byKey(const Key('inventory-movements-more')), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('inventory-movements-more')),
      );
      await tester.tap(find.byKey(const Key('inventory-movements-more')));
      await settle(tester);
      expect(titles(), hasLength(24));
      expect(find.byKey(const Key('inventory-movements-more')), findsNothing);
      expect(
        titles().toSet(),
        containsAll([
          'Compra',
          'Compra revertida',
          'Aplicación en Chaco Ana',
          'Aplicación revertida en Chaco Ana',
          'Pase a Beto',
          'Recibido de Ana',
          'Pase revertido: vuelve de Beto',
          'Pase revertido: devuelto a Ana',
        ]),
      );
    });
  });
}
