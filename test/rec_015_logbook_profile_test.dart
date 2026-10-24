// REC-015 (#51): bitácora de chaco y perfil de persona.
//
// Criterio 3: `farmLogbook` devuelve cada aplicación del chaco con fecha,
// campaña, persona, producto, área, dosis, cantidad teórica y real, costo y
// lotes FIFO, y filtra por campaña y por producto; `FarmLogbookScreen` lo
// muestra.
// Criterio 2: `PersonDetailScreen` muestra superficie, saldo, stock por
// producto y unidad, y un estado de cuenta en el que una aplicación revertida
// conserva su cargo y añade el crédito compensatorio.
//
// Todos los valores esperados salen de la fixture, calculados a mano:
//
//   Compras (Campaña 1), asignadas a Ana:
//     C1 10/01  Glifosato 3 L a 100,00 Bs/L (lote g1); Paraquat 4 KG a 50,00
//     C2 20/01  Glifosato 5 L a 120,00 Bs/L (lote g2)
//   Aplicaciones de Ana:
//     A1 01/02 C1 Chaco Grande  Glifosato 4 L   g1 3 L + g2 1 L = 420,00 Bs
//     A2 15/02 C1 Chaco Grande  Paraquat 1 KG   p1 1 KG          =  50,00 Bs
//     A3 01/03 C1 Chaco Grande  Glifosato 0,5 L g2 0,5 L         =  60,00 Bs
//        (revertida: vuelven 0,5 L a g2 y se abona 60,00 Bs)
//     A5 10/03 C1 Chaco Chico   Glifosato 0,5 L g2 0,5 L         =  60,00 Bs
//     A4 01/07 C2 Chaco Grande  Glifosato 1 L   g2 1 L           = 120,00 Bs
//   Saldo de Ana: 420 + 50 + 60 + 60 + 120 − 60 = 650,00 Bs.
//   Stock de Ana: Glifosato 8 − 4 − 0,5 + 0,5 − 0,5 − 1 = 2,5 L; Paraquat 3 KG.
//   Superficie: Chaco Grande 10 ha + Chaco Chico 2,5 ha = 12,5 ha.
//
// Las fechas son mediodía local, para que el día civil no dependa de la zona
// horaria del equipo (America/La_Paz en local, UTC en el CI).

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/money.dart';
import 'package:agroquimicos/presentation/screens/farm_logbook_screen.dart';
import 'package:agroquimicos/presentation/screens/person_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_app_access.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late AgroRepository repo;
  late int ana;
  late int grande;
  late int chico;
  late int campaign1;
  late int campaign2;
  late int glifosato;
  late int paraquat;
  late int lotG1;
  late int lotG2;
  late int lotP1;
  late int a1;
  late int a2;
  late int a3;
  late int a4;
  late int a5;

  DateTime day(int month, int dayOfMonth) =>
      DateTime(2026, month, dayOfMonth, 12);

  Future<int> apply({
    required int farm,
    required int campaign,
    required DateTime at,
    required int product,
    required int quantity,
    required int area,
    required int dose,
  }) => repo.confirmApplication(
    ApplicationDraft(
      personId: ana,
      farmId: farm,
      campaignId: campaign,
      appliedAt: at,
      treatedAreaM2: area,
      lines: [
        ApplicationLineDraft(
          productId: product,
          quantityBase: quantity,
          treatedAreaM2: area,
          doseBasePerHa: dose,
          theoreticalQuantityBase: quantity,
        ),
      ],
    ),
  );

  setUp(() async {
    database = AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    repo = AgroRepository(database);
    ana = await repo.addPerson(name: 'Ana Familiar', role: PersonRole.family);
    final supplier = await repo.addSupplier(name: 'Proveedor');
    grande = await repo.addFarm(
      ownerId: ana,
      name: 'Chaco Grande',
      areaM2: 100000,
    );
    chico = await repo.addFarm(
      ownerId: ana,
      name: 'Chaco Chico',
      areaM2: 25000,
    );
    campaign1 = await repo.addCampaign(name: 'Campaña 1', start: day(1, 1));
    glifosato = await repo.addProduct(name: 'Glifosato');
    paraquat = await repo.addProduct(name: 'Paraquat', unit: 'KG');

    PurchaseItemDraft item(int product, int quantity, int priceMinor) =>
        PurchaseItemDraft(
          productId: product,
          quantityBase: quantity,
          currency: CurrencyCode.bob,
          originalUnitPriceMinor: priceMinor,
          allocations: [AllocationDraft(personId: ana, quantityBase: quantity)],
        );
    await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: supplier,
        campaignId: campaign1,
        purchaseDate: day(1, 10),
        items: [item(glifosato, 3000, 10000), item(paraquat, 4000, 5000)],
      ),
    );
    await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: supplier,
        campaignId: campaign1,
        purchaseDate: day(1, 20),
        items: [item(glifosato, 5000, 12000)],
      ),
    );
    final glifosatoLots = await repo.inventoryProductLots(glifosato);
    lotG1 = glifosatoLots[0]['lot_id']! as int;
    lotG2 = glifosatoLots[1]['lot_id']! as int;
    lotP1 =
        (await repo.inventoryProductLots(paraquat)).single['lot_id']! as int;

    a1 = await apply(
      farm: grande,
      campaign: campaign1,
      at: day(2, 1),
      product: glifosato,
      quantity: 4000,
      area: 100000,
      dose: 400,
    );
    a2 = await apply(
      farm: grande,
      campaign: campaign1,
      at: day(2, 15),
      product: paraquat,
      quantity: 1000,
      area: 100000,
      dose: 100,
    );
    a3 = await apply(
      farm: grande,
      campaign: campaign1,
      at: day(3, 1),
      product: glifosato,
      quantity: 500,
      area: 50000,
      dose: 1000,
    );
    await repo.reverseApplicationUnauditedForTesting(
      a3,
      reason: 'Registrada por error',
    );
    a5 = await apply(
      farm: chico,
      campaign: campaign1,
      at: day(3, 10),
      product: glifosato,
      quantity: 500,
      area: 25000,
      dose: 2000,
    );

    await repo.closeCampaign(campaign1, end: day(5, 31));
    campaign2 = await repo.addCampaign(name: 'Campaña 2', start: day(6, 1));
    if ((await repo.activeCampaign())?['id'] != campaign2) {
      await repo.activateCampaign(campaign2);
    }
    a4 = await apply(
      farm: grande,
      campaign: campaign2,
      at: day(7, 1),
      product: glifosato,
      quantity: 1000,
      area: 100000,
      dose: 100,
    );
  });

  tearDown(() => database.close());

  group('farmLogbook', () {
    List<int?> ids(List<Map<String, Object?>> rows) =>
        rows.map((row) => row['application_id'] as int?).toList();

    test('sólo las aplicaciones del chaco, de la más reciente a la más '
        'antigua, con todos los campos del criterio', () async {
      final rows = await repo.farmLogbook(grande);
      expect(ids(rows), [a4, a3, a2, a1]);

      final first = rows.last;
      expect(
        DateTime.parse(first['applied_at']! as String).toLocal(),
        day(2, 1),
      );
      expect(first['campaign_name'], 'Campaña 1');
      expect(first['person_name'], 'Ana Familiar');
      expect(first['product_name'], 'Glifosato');
      expect(first['unit'], 'L');
      expect(first['treated_area_m2'], 100000);
      expect(first['dose_base_per_ha'], 400);
      expect(first['theoretical_quantity_base'], 4000);
      expect(first['quantity_base'], 4000);
      expect(first['cost_bob_minor'], 42000);
      expect(first['fifo_lots'], '#$lotG1: 3000,#$lotG2: 1000');

      final paraquatRow = rows[2];
      expect(paraquatRow['product_name'], 'Paraquat');
      expect(paraquatRow['unit'], 'KG');
      expect(paraquatRow['cost_bob_minor'], 5000);
      expect(paraquatRow['fifo_lots'], '#$lotP1: 1000');

      final latest = rows.first;
      expect(latest['campaign_name'], 'Campaña 2');
      expect(latest['cost_bob_minor'], 12000);
      expect(latest['fifo_lots'], '#$lotG2: 1000');
    });

    test('la aplicación revertida sigue en la bitácora, marcada y sin lotes '
        'consumidos', () async {
      final reversed = (await repo.farmLogbook(grande))
          .singleWhere((row) => row['application_id'] == a3);
      expect(reversed['status'], 'REVERSED');
      expect(reversed['quantity_base'], 500);
      expect(reversed['cost_bob_minor'], 6000);
      // Sus consumos se revirtieron: ya no retienen ningún lote.
      expect(reversed['fifo_lots'], isNull);

      final others = (await repo.farmLogbook(grande))
          .where((row) => row['application_id'] != a3);
      expect(others.map((row) => row['status']).toSet(), {'CONFIRMED'});
    });

    test('filtra por campaña', () async {
      expect(ids(await repo.farmLogbook(grande, campaignId: campaign1)), [
        a3,
        a2,
        a1,
      ]);
      expect(ids(await repo.farmLogbook(grande, campaignId: campaign2)), [a4]);
    });

    test('filtra por producto', () async {
      expect(ids(await repo.farmLogbook(grande, productId: glifosato)), [
        a4,
        a3,
        a1,
      ]);
      expect(ids(await repo.farmLogbook(grande, productId: paraquat)), [a2]);
    });

    test('combina los dos filtros', () async {
      expect(
        ids(
          await repo.farmLogbook(
            grande,
            campaignId: campaign1,
            productId: glifosato,
          ),
        ),
        [a3, a1],
      );
      expect(
        await repo.farmLogbook(
          grande,
          campaignId: campaign2,
          productId: paraquat,
        ),
        isEmpty,
      );
    });

    test('el otro chaco tiene su propia bitácora', () async {
      expect(ids(await repo.farmLogbook(chico)), [a5]);
    });
  });

  group('pantallas', () {
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

    Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(repo),
            activatedInstallationForTests(),
          ],
          child: MaterialApp(home: Scaffold(body: screen)),
        ),
      );
    }

    group('FarmLogbookScreen', () {
      String detail({
        required int area,
        required int dose,
        required int quantity,
        required int cost,
        required String lots,
        String unit = 'L',
      }) =>
          'Área ${formatHectares(area)} · dosis '
          '${formatQuantity(dose, unit)}/ha\n'
          'Teórico ${formatQuantity(quantity, unit)} · real '
          '${formatQuantity(quantity, unit)} · costo ${formatBob(cost)}\n'
          'Lotes $lots';

      testWidgets('muestra el chaco y cada aplicación con sus datos', (
        tester,
      ) async {
        await pumpScreen(tester, FarmLogbookScreen(farmId: grande));
        await waitFor(tester, find.byType(ExpansionTile));

        expect(find.text('Chaco Grande'), findsOneWidget);
        expect(
          find.text('Bitácora · Ana Familiar · ${formatHectares(100000)}'),
          findsOneWidget,
        );
        expect(find.byType(ExpansionTile), findsNWidgets(4));
        // El otro chaco no aparece.
        expect(find.textContaining('10/03/2026'), findsNothing);

        final a1Subtitle = '01/02/2026 · Campaña 1 · Ana Familiar';
        final a1Tile = find.ancestor(
          of: find.text(a1Subtitle),
          matching: find.byType(ExpansionTile),
        );
        expect(
          find.descendant(of: a1Tile, matching: find.text('Glifosato')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: a1Tile,
            matching: find.text(formatQuantity(4000, 'L')),
          ),
          findsOneWidget,
        );

        await tester.tap(find.text(a1Subtitle));
        await settle(tester);
        expect(
          find.text(
            detail(
              area: 100000,
              dose: 400,
              quantity: 4000,
              cost: 42000,
              lots:
                  '#$lotG1 ${formatQuantity(3000, 'L')} · '
                  '#$lotG2 ${formatQuantity(1000, 'L')}',
            ),
          ),
          findsOneWidget,
        );

        await tester.tap(find.text('15/02/2026 · Campaña 1 · Ana Familiar'));
        await settle(tester);
        expect(
          find.text(
            detail(
              area: 100000,
              dose: 100,
              quantity: 1000,
              cost: 5000,
              lots: '#$lotP1 ${formatQuantity(1000, 'KG')}',
              unit: 'KG',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.text('01/07/2026 · Campaña 2 · Ana Familiar'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('la aplicación revertida se distingue de las confirmadas', (
        tester,
      ) async {
        await pumpScreen(tester, FarmLogbookScreen(farmId: grande));
        await waitFor(tester, find.byType(ExpansionTile));

        expect(
          find.text('01/03/2026 · Campaña 1 · Ana Familiar · Revertida'),
          findsOneWidget,
        );
        expect(find.textContaining('Revertida'), findsOneWidget);
      });
    });

    group('PersonDetailScreen', () {
      Future<void> openTab(WidgetTester tester, String label) async {
        await tester.tap(find.widgetWithText(ChoiceChip, label));
        await settle(tester);
      }

      Finder row(String title, String trailing) => find.ancestor(
        of: find.text(trailing),
        matching: find.ancestor(
          of: find.text(title),
          matching: find.byType(ListTile),
        ),
      );

      testWidgets('resumen: superficie y saldo total', (tester) async {
        await pumpScreen(tester, PersonDetailScreen(personId: ana));
        await waitFor(tester, find.byType(ChoiceChip));

        expect(find.text('Ana Familiar'), findsOneWidget);
        expect(
          find.text('Familiar · saldo total ${formatBob(65000)}'),
          findsOneWidget,
        );
        expect(row('Superficie', formatHectares(125000)), findsOneWidget);
        expect(
          row('Saldo total · todas las campañas', formatBob(65000)),
          findsOneWidget,
        );
      });

      testWidgets('chacos: los dos, con su superficie', (tester) async {
        await pumpScreen(tester, PersonDetailScreen(personId: ana));
        await waitFor(tester, find.byType(ChoiceChip));
        await openTab(tester, 'Chacos');

        // El área va en el subtítulo de cada chaco.
        expect(find.text('Chaco Grande'), findsOneWidget);
        expect(find.text(formatHectares(100000)), findsOneWidget);
        expect(find.text('Chaco Chico'), findsOneWidget);
        expect(find.text(formatHectares(25000)), findsOneWidget);
      });

      testWidgets('inventario: stock por producto y unidad', (tester) async {
        await pumpScreen(tester, PersonDetailScreen(personId: ana));
        await waitFor(tester, find.byType(ChoiceChip));
        await openTab(tester, 'Inventario');

        expect(row('Glifosato', formatQuantity(2500, 'L')), findsOneWidget);
        expect(row('Paraquat', formatQuantity(3000, 'KG')), findsOneWidget);
      });

      testWidgets('cuenta: la reversión conserva el cargo y añade el crédito', (
        tester,
      ) async {
        await pumpScreen(tester, PersonDetailScreen(personId: ana));
        await waitFor(tester, find.byType(ChoiceChip));
        await openTab(tester, 'Cuenta');

        final lines = find.descendant(
          of: find.byType(Card),
          matching: find.byType(ListTile),
        );
        // Cinco cargos por consumo y un crédito, en orden de fecha: el crédito
        // se fechó el día de la reversión, hoy.
        expect(lines, findsNWidgets(6));
        final rows = [
          for (final element in lines.evaluate())
            (
              title: ((element.widget as ListTile).title! as Text).data,
              date: ((element.widget as ListTile).subtitle! as Text).data,
              amount: find
                  .descendant(
                    of: find.byWidget(element.widget),
                    matching: find.byType(Text),
                  )
                  .evaluate()
                  .map((text) => (text.widget as Text).data)
                  .toList(),
            ),
        ];
        expect(rows.map((row) => row.date).toList(), [
          '01/02/2026',
          '15/02/2026',
          '01/03/2026',
          '10/03/2026',
          '01/07/2026',
          formatDate(DateTime.now().toUtc().toIso8601String()),
        ]);
        expect(rows.map((row) => row.title).toList(), [
          'Glifosato',
          'Paraquat',
          'Glifosato',
          'Glifosato',
          'Glifosato',
          // Sin producto propio, el concepto del crédito es el motivo de la
          // reversión (`detailedStatement`: COALESCE(..., notes, type)).
          'Registrada por error',
        ]);
        final running = [42000, 47000, 53000, 59000, 71000, 65000];
        final amounts = [42000, 5000, 6000, 6000, 12000, -6000];
        for (var i = 0; i < rows.length; i++) {
          expect(rows[i].amount, contains(formatBob(amounts[i])));
          expect(
            rows[i].amount,
            contains('Acumulado ${formatBob(running[i])}'),
          );
        }
        // El cargo de A3 (01/03) se conserva, y el crédito lo compensa.
        expect(rows[2].amount, contains(formatBob(6000)));
        expect(rows.last.amount, contains(formatBob(-6000)));
      });
    });
  });
}
