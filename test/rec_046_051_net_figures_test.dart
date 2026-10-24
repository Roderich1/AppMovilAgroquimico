// REC-010 (#46) y REC-015 (#51): cifras netas de comprado, consumido y
// asignación (decisión de Roderich Rendón del 2026-10-19, opción b de §6.4 de
// `docs/evidence/REC_CONCILIACION_2026-10-19.md`).
//
//   comprado neto      = PURCHASE_IN + PURCHASE_REVERSAL
//   consumido neto     = −(APPLICATION_OUT + APPLICATION_REVERSAL)
//   asignación neta    = comprado neto + TRANSFER_IN + TRANSFER_OUT
//                        + TRANSFER_REVERSAL_IN + TRANSFER_REVERSAL_OUT
//   físico             = todos los movimientos (sin cambio)
//
// Fixture, Glifosato en L a Bs 100,00 salvo C2:
//   C1 05/01  Ana compra 10 L.
//   C2 06/01  Beto compra 4 L a Bs 120,00.
//   A1 10/01  Ana aplica 3 L (Bs 300,00).
//   A2 11/01  Beto aplica 1 L de C2 (Bs 120,00); se revierte A2 y después C2.
//   A3 12/01  Ana aplica 2 L (Bs 200,00); se revierte.
//   T1 15/01  Ana transfiere 2 L a Beto; se revierte.
//   T2 16/01  Ana transfiere 1 L a Beto.
//   C4 17/01  Beto compra 2 KG de Atrazina a Bs 50,00; se revierte.
//   Caro no tiene ningún movimiento.
//
//              comprado  consumido  asignado  físico
//   bruto        14         6          —        7      (14 − 6 ≠ 7)
//   neto         10         3          —        7
//   Ana  bruto    —         5         14        6
//   Ana  neto     —         3          9        6
//   Beto bruto    —         1          8        1
//   Beto neto     —         0          1        1
//
// El físico, el valor (6 + 1 L a Bs 100,00 = Bs 700,00), FIFO y los costos no
// cambian. Reutiliza `rec_046_inventory_detail_test.dart` para la procedencia y
// los filtros de lotes, y `report_export_service_test.dart:328` para la
// paridad del CSV de inventario sin reversiones.
import 'dart:convert';
import 'dart:io';

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/typed_reads.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/reports/report_composer.dart';
import 'package:agroquimicos/presentation/screens/inventory_detail_screen.dart';
import 'package:agroquimicos/presentation/screens/person_detail_screen.dart';
import 'package:agroquimicos/services/reports/csv_report_generator.dart';
import 'package:agroquimicos/services/reports/report_export_service.dart';
import 'package:agroquimicos/services/reports/report_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_app_access.dart';
import 'support/f04_mode_fixtures.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late AgroRepository repo;
  late Database db;
  late int ana, beto, caro, glifosato, atrazina;
  late int c1, c2, c4, a1, a2, a3, t1, t2;

  DateTime day(int d) => DateTime.utc(2026, 1, d);

  Future<void> seed() async {
    repo = AgroRepository(database);
    db = await database.database;
    ana = await repo.addPerson(name: 'Ana', role: PersonRole.family);
    beto = await repo.addPerson(name: 'Beto', role: PersonRole.family);
    // Sin ningún movimiento: no debe aparecer en el reparto ni tener stock.
    caro = await repo.addPerson(name: 'Caro', role: PersonRole.family);
    final supplier = await repo.addSupplier(name: 'Agro Sur');
    final campaign = await repo.addCampaign(name: 'Verano', start: day(1));
    glifosato = await repo.addProduct(name: 'Glifosato');
    atrazina = await repo.addProduct(name: 'Atrazina', unit: 'KG');
    final farmAna = await repo.addFarm(
      ownerId: ana,
      name: 'Chaco Ana',
      areaM2: 10000,
    );
    final farmBeto = await repo.addFarm(
      ownerId: beto,
      name: 'Chaco Beto',
      areaM2: 10000,
    );

    Future<int> buy(int person, int product, int qty, int price, int d) =>
        repo.confirmPurchase(
          PurchaseDraft(
            supplierId: supplier,
            campaignId: campaign,
            purchaseDate: day(d),
            items: [
              PurchaseItemDraft(
                productId: product,
                quantityBase: qty,
                currency: CurrencyCode.bob,
                originalUnitPriceMinor: price,
                allocations: [
                  AllocationDraft(personId: person, quantityBase: qty),
                ],
              ),
            ],
          ),
        );
    Future<int> apply(int person, int farm, int qty, int d) =>
        repo.confirmApplication(
          ApplicationDraft(
            personId: person,
            farmId: farm,
            campaignId: campaign,
            appliedAt: day(d),
            lines: [
              ApplicationLineDraft(productId: glifosato, quantityBase: qty),
            ],
          ),
        );
    Future<int> transfer(int qty, int d) => repo.transferProductsFifo(
      fromPersonId: ana,
      toPersonId: beto,
      items: [TransferItemDraft(productId: glifosato, quantityBase: qty)],
      date: day(d),
    );

    c1 = await buy(ana, glifosato, 10000, 10000, 5);
    c2 = await buy(beto, glifosato, 4000, 12000, 6);
    a1 = await apply(ana, farmAna, 3000, 10);
    a2 = await apply(beto, farmBeto, 1000, 11);
    await repo.reverseApplicationUnauditedForTesting(
      a2,
      reason: 'Error de carga',
    );
    await repo.reversePurchaseUnauditedForTesting(
      c2,
      reason: 'Devuelta al proveedor',
    );
    a3 = await apply(ana, farmAna, 2000, 12);
    await repo.reverseApplicationUnauditedForTesting(
      a3,
      reason: 'Error de carga',
    );
    t1 = await transfer(2000, 15);
    await repo.reverseTransferUnauditedForTesting(
      t1,
      reason: 'Destino equivocado',
    );
    t2 = await transfer(1000, 16);
    c4 = await buy(beto, atrazina, 2000, 5000, 17);
    await repo.reversePurchaseUnauditedForTesting(
      c4,
      reason: 'Devuelta al proveedor',
    );
  }

  group('lecturas', () {
    setUp(() async {
      database = openDb(inMemoryDatabasePath);
      await seed();
    });

    test('la fixture usa los ocho tipos de movimiento', () async {
      final types = (await db.rawQuery(
        'SELECT DISTINCT type FROM inventory_movements',
      )).map((r) => r['type']).toSet();
      expect(types, {
        'PURCHASE_IN',
        'PURCHASE_REVERSAL',
        'APPLICATION_OUT',
        'APPLICATION_REVERSAL',
        'TRANSFER_OUT',
        'TRANSFER_IN',
        'TRANSFER_REVERSAL_IN',
        'TRANSFER_REVERSAL_OUT',
      });
    });

    test('la cabecera da comprado y consumido netos; su diferencia es el '
        'físico', () async {
      final header = await repo.inventoryProductHeader(glifosato);
      expect(header, {
        'product_id': glifosato,
        'product_name': 'Glifosato',
        'unit': 'L',
        'purchased_base': 10000, // 10 + 4 − 4 (C2 revertida)
        'consumed_base': 3000, // 3 + 1 − 1 + 2 − 2
        'physical_base': 7000,
        'value_bob_minor': 70000,
        'committed_base': 0,
      });
      expect(await repo.inventoryProductHeader(atrazina), {
        'product_id': atrazina,
        'product_name': 'Atrazina',
        'unit': 'KG',
        'purchased_base': 0, // 2 − 2: C4 revertida
        'consumed_base': 0,
        'physical_base': 0,
        'value_bob_minor': 0,
        'committed_base': 0,
      });
    });

    test('el reparto da asignación y consumo netos por persona, conserva la '
        'fila que quedó en cero y omite a quien no tuvo movimientos', () async {
      // Caro no tiene movimientos: `COUNT(m.id)` la omite (con `COUNT(*)` el
      // LEFT JOIN la contaría como una fila).
      expect(await repo.inventoryProductDistribution(glifosato), [
        {
          'person_id': ana,
          'person_name': 'Ana',
          // 10 comprados − 2 + 2 (T1 y su reversión) − 1 (T2) = 9.
          'assigned_base': 9000,
          'consumed_base': 3000,
          'available_base': 6000,
        },
        {
          'person_id': beto,
          'person_name': 'Beto',
          // C2 revertida suma 0; recibe 2 − 2 + 1 = 1.
          'assigned_base': 1000,
          'consumed_base': 0, // A2 y su reversión
          'available_base': 1000,
        },
      ]);
      expect(await repo.inventoryProductDistribution(atrazina), [
        {
          'person_id': beto,
          'person_name': 'Beto',
          'assigned_base': 0,
          'consumed_base': 0,
          'available_base': 0,
        },
      ]);
    });

    test(
      'el perfil da las mismas cifras netas, conserva la fila en cero y omite '
      'los productos sin movimientos',
      () async {
        // Ana nunca tuvo Atrazina y Caro nada: no aparecen.
        expect(await repo.personStockSummary(caro), isEmpty);
        expect(await repo.personStockSummary(ana), [
          {
            'product_id': glifosato,
            'product_name': 'Glifosato',
            'unit': 'L',
            'assigned_base': 9000,
            'consumed_base': 3000,
            'available_base': 6000,
          },
        ]);
        expect(await repo.personStockSummary(beto), [
          {
            'product_id': atrazina,
            'product_name': 'Atrazina',
            'unit': 'KG',
            'assigned_base': 0,
            'consumed_base': 0,
            'available_base': 0,
          },
          {
            'product_id': glifosato,
            'product_name': 'Glifosato',
            'unit': 'L',
            'assigned_base': 1000,
            'consumed_base': 0,
            'available_base': 1000,
          },
        ]);
      },
    );

    test('el resumen y su adaptador tipado llevan las cifras netas; el físico '
        'y el valor no cambian', () async {
      final summary = await repo.inventorySummary();
      expect(summary, [
        {
          'product_id': atrazina,
          'product_name': 'Atrazina',
          'unit': 'KG',
          'purchased_base': 0,
          'consumed_base': 0,
          'available_base': 0,
          'committed_base': 0,
          'projected_base': 0,
          'available_value_bob_minor': 0,
          'people_count': 1, // Beto tiene movimientos, aunque sumen 0
        },
        {
          'product_id': glifosato,
          'product_name': 'Glifosato',
          'unit': 'L',
          'purchased_base': 10000,
          'consumed_base': 3000,
          'available_base': 7000,
          'committed_base': 0,
          'projected_base': 7000,
          'available_value_bob_minor': 70000,
          'people_count': 2,
        },
      ]);
      final typed = await repo.inventorySummaryTyped();
      expect(typed.last.productName, 'Glifosato');
      expect(typed.last.purchasedBase, 10000);
      expect(typed.last.consumedBase, 3000);
      expect(typed.last.availableBase, 7000);
      expect(typed.last.availableValueBobMinor, 70000);
    });

    test('consultar no escribe: físico, costos, asientos y filas persistidas '
        'quedan como los dejó la fixture', () async {
      final before = await dumpTables(db);
      await repo.inventorySummary();
      await repo.inventorySummaryTyped();
      await repo.inventoryProductHeader(glifosato);
      await repo.inventoryProductDistribution(glifosato);
      await repo.personStockSummary(ana);
      await repo.personStockSummary(beto);
      expect(await dumpTables(db), before);

      final stock = await stockByPersonProduct(db);
      expect(stock[(ana, glifosato)], 6000);
      expect(stock[(beto, glifosato)], 1000);
      expect(stock[(beto, atrazina)], 0);
      final costs = await db.query(
        'applications',
        columns: ['id', 'status', 'total_cost_bob_minor'],
        orderBy: 'id',
      );
      expect(costs, [
        {'id': a1, 'status': 'CONFIRMED', 'total_cost_bob_minor': 30000},
        {'id': a2, 'status': 'REVERSED', 'total_cost_bob_minor': 12000},
        {'id': a3, 'status': 'REVERSED', 'total_cost_bob_minor': 20000},
      ]);
      // Ambas pagan por uso: cada aplicación carga su costo y cada reversión
      // lo abona; las compras no generan asientos.
      expect(
        await db.query(
          'account_transactions',
          columns: ['person_id', 'type', 'amount_bob_minor_signed'],
          orderBy: 'id',
        ),
        [
          {
            'person_id': ana,
            'type': 'USAGE_CHARGE',
            'amount_bob_minor_signed': 30000,
          },
          {
            'person_id': beto,
            'type': 'USAGE_CHARGE',
            'amount_bob_minor_signed': 12000,
          },
          {
            'person_id': beto,
            'type': 'CREDIT_ADJUSTMENT',
            'amount_bob_minor_signed': -12000,
          },
          {
            'person_id': ana,
            'type': 'USAGE_CHARGE',
            'amount_bob_minor_signed': 20000,
          },
          {
            'person_id': ana,
            'type': 'CREDIT_ADJUSTMENT',
            'amount_bob_minor_signed': -20000,
          },
        ],
      );
    });

    test(
      'el historial sigue mostrando cada operación y su reversión',
      () async {
        Map<Object?, Object?> statuses(List<Map<String, Object?>> rows) => {
          for (final row in rows) row['id']: row['status'],
        };
        expect(statuses(await repo.purchases()), {
          c1: 'CONFIRMED',
          c2: 'REVERSED',
          c4: 'REVERSED',
        });
        expect(statuses(await repo.applications()), {
          a1: 'CONFIRMED',
          a2: 'REVERSED',
          a3: 'REVERSED',
        });
        expect(statuses(await repo.transfers()), {
          t1: 'REVERSED',
          t2: 'CONFIRMED',
        });
      },
    );

    test('el CSV de inventario sigue mostrando físico, comprometido, '
        'proyectado y valor', () async {
      final root = await Directory.systemTemp.createTemp('agro_rec_neto_');
      addTearDown(() => root.delete(recursive: true));
      final service = ReportExportService(
        repo,
        LocalReportStorage(
          directory: () async => Directory(p.join(root.path, 'reportes')),
        ),
        clock: () => DateTime.utc(2026, 10, 19, 12),
      );
      final stored = await service.export(
        const ReportRequest(
          kind: ReportKind.inventory,
          format: ReportFormat.csv,
        ),
      );
      final content = utf8.decode(
        (await File(stored.path).readAsBytes()).sublist(utf8Bom.length),
      );
      expect(content, contains('\r\nAtrazina;KG;0;0;0;0,00\r\n'));
      expect(content, contains('\r\nGlifosato;L;7;0;7;700,00\r\n'));
      expect(content, contains('Valor total (Bs);700,00'));
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

    Future<void> seedScreens(WidgetTester tester) async {
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
    }

    Future<void> mount(WidgetTester tester, Widget screen) => tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          activatedInstallationForTests(),
        ],
        child: MaterialApp(home: Scaffold(body: screen)),
      ),
    );

    testWidgets('el detalle rotula las cifras netas y explica la asignación '
        'neta', (tester) async {
      await seedScreens(tester);
      await mount(tester, InventoryDetailScreen(productId: glifosato));
      await waitFor(tester, find.text('Comprado neto'));

      /// El valor dentro de la tarjeta de su rótulo.
      Finder metric(String label, String value) => find.descendant(
        of: find
            .ancestor(of: find.text(label), matching: find.byType(Card))
            .first,
        matching: find.text(value),
      );
      expect(metric('Comprado neto', '10 L'), findsOneWidget);
      expect(metric('Consumido neto', '3 L'), findsOneWidget);
      expect(metric('Físico', '7 L'), findsOneWidget);
      expect(
        find.text(
          'Neto: no cuenta lo revertido. Comprado neto menos consumido '
          'neto es el físico.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Asignación neta: lo comprado para esta persona, más lo que '
          'recibió y menos lo que entregó por transferencias. No cuenta lo '
          'revertido. Restando lo consumido queda su físico.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Asignación neta 9 L · consumido neto 3 L'),
        findsOneWidget,
      );
      expect(
        find.text('Asignación neta 1 L · consumido neto 0 L'),
        findsOneWidget,
      );
      expect(find.text('Caro'), findsNothing);
      expect(find.text('Comprado'), findsNothing);
      expect(find.text('Consumido'), findsNothing);
    });

    testWidgets('el perfil rotula el consumo neto y conserva la fila en cero', (
      tester,
    ) async {
      await seedScreens(tester);
      Future<void> profile(int person) async {
        await mount(
          tester,
          PersonDetailScreen(key: ValueKey(person), personId: person),
        );
        await waitFor(tester, find.byType(ChoiceChip));
        await tester.tap(find.widgetWithText(ChoiceChip, 'Inventario'));
        await settle(tester);
      }

      await profile(ana);
      expect(find.text('Consumido neto 3 L'), findsOneWidget);
      expect(find.text('6 L'), findsOneWidget);
      expect(find.text('Atrazina'), findsNothing);

      await profile(beto);
      expect(find.text('Atrazina'), findsOneWidget);
      expect(find.text('Consumido neto 0 KG'), findsOneWidget);
      expect(find.text('Consumido neto 0 L'), findsOneWidget);
      expect(find.text('1 L'), findsOneWidget);
    });
  });
}
