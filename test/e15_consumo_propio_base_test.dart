// E-15 · Registro propio del titular (decisión del autor, Roderich Rendón, del
// 2026-10-27; docs/architecture/D04_E15_CUENTAS_IMPUTACION_Y_COSTO_PROPIO.md
// parte B).
//
// Sólo usa API que ya existía en el HEAD de D-04 (`accountSummaries`,
// `dashboard`, `campaignCloseSummary`, la exportación y las pantallas). Así
// compila sobre D-04 y falla allí por aserción: en D-04 el titular todavía es
// una persona más de las cuentas por cobrar.

import 'dart:io';

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/domain/reports/report_composer.dart';
import 'package:agroquimicos/domain/reports/report_table.dart';
import 'package:agroquimicos/operation_mode_controller.dart';
import 'package:agroquimicos/presentation/screens/dashboard_screen.dart';
import 'package:agroquimicos/presentation/screens/persons_screen.dart';
import 'package:agroquimicos/presentation/screens/settlements_screen.dart';
import 'package:agroquimicos/services/reports/report_export_service.dart';
import 'package:agroquimicos/services/reports/report_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/d04_world.dart';
import 'support/e15_world.dart';

void main() {
  sqfliteFfiInit();

  group('repositorio', () {
    late E15World e;
    tearDown(() => e.close());

    test('E15-01 · el titular no está en Cuentas, ni en Inicio, ni en el '
        'resumen (D-04: Titular 81 y Familias 101)', () async {
      e = await E15World.create();
      await e.seedE1501();
      final rows = await e.w.repo.accountSummaries();
      expect(rows.map((r) => r.personId), isNot(contains(e.titular)));
      expect((await e.w.repo.dashboard()).familyReceivableMinor, 2000);
      expect(
        (await e.w.repo.campaignCloseSummary(
          e.w.invierno,
        ))['receivable_bob_minor'],
        2000,
      );
    });

    test('E15-04 · el pago propio no es «Pagos recibidos» '
        '(D-04: 81)', () async {
      e = await E15World.create();
      await e.buy(e.titular, 'Glifosato', 1000, 4500);
      await e.apply(e.titular, e.chacoNorte, DateTime(2026, 10, 20), {
        'Glifosato': 1000,
      });
      await e.w.pay(e.titular, 4500, campaign: e.w.invierno, date: at(10, 21));
      expect((await e.w.repo.dashboard()).receivedMinor, 0);
    });

    test('M-10 · transferencia: Familias por cobrar 45 (D-04: 90)', () async {
      e = await E15World.create();
      await e.buy(e.titular, 'Glifosato', 2000, 4500);
      await e.w.repo.transferProductsFifo(
        fromPersonId: e.titular,
        toPersonId: e.w.familiar,
        items: [
          TransferItemDraft(
            productId: e.products['Glifosato']!,
            quantityBase: 1000,
          ),
        ],
        date: DateTime(2026, 8, 5),
      );
      await e.apply(e.titular, e.chacoNorte, DateTime(2026, 8, 10), {
        'Glifosato': 1000,
      });
      await e.apply(e.w.familiar, e.chacoFamiliar, DateTime(2026, 8, 12), {
        'Glifosato': 1000,
      });
      expect((await e.w.repo.dashboard()).familyReceivableMinor, 4500);
    });

    test('E15-06 · intervalos: Familias por cobrar 20 (D-04: 101)', () async {
      e = await E15World.create();
      await e.buy(e.titular, 'Glifosato', 1000, 4500);
      await e.buy(e.titular, 'Bellator', 200, 18000);
      await e.buy(e.w.familiar, 'Cipermetrina', 250, 8000);
      await e.apply(e.w.familiar, e.chacoFamiliar, DateTime(2026, 8, 5), {
        'Cipermetrina': 250,
      });
      await e.apply(e.titular, e.chacoNorte, DateTime(2026, 8, 10), {
        'Glifosato': 1000,
        'Bellator': 200,
      });
      await e.changeOwner(
        e.w.familiar,
        DateTime.now().toUtc().toIso8601String(),
      );
      expect((await e.w.repo.dashboard()).familyReceivableMinor, 2000);
    });

    test('E15-01 · la exportación del titular son sus movimientos propios '
        '(D-04: «Estado de cuenta» con «Saldo a hoy» 81)', () async {
      e = await E15World.create();
      await e.seedE1501();
      final root = await Directory.systemTemp.createTemp('agro_e15_');
      addTearDown(() => root.delete(recursive: true));
      final table =
          await ReportExportService(
            e.w.repo,
            LocalReportStorage(
              directory: () async => Directory(p.join(root.path, 'reportes')),
            ),
            clock: () => DateTime(2026, 10, 27, 10),
          ).compose(
            ReportRequest(
              kind: ReportKind.accountStatement,
              format: ReportFormat.csv,
              personId: e.titular,
            ),
          );
      expect(table.title, 'Movimientos propios del titular');
      expect(
        {for (final t in table.totals) t.label: (t.cell as ReportMoney).minor},
        {
          'Consumo aplicado, costo FIFO (Bs)': 8100,
          'Cargos anotados (Bs)': 8100,
          'Créditos por reversión (Bs)': 0,
          'Pagos y ajustes registrados (Bs)': 0,
        },
      );
    });
  });

  group('pantallas', () {
    Future<void> settle(WidgetTester tester) async {
      for (var round = 0; round < 6; round++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        for (var frame = 0; frame < 6; frame++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      }
    }

    Future<void> pump(
      WidgetTester tester,
      AgroRepository repo,
      Widget screen,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [repositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(home: Scaffold(body: screen)),
        ),
      );
      await settle(tester);
    }

    Future<E15World> seeded(WidgetTester tester) async {
      final e = (await tester.runAsync(() async {
        final e = await E15World.create();
        await e.seedE1501();
        return e;
      }))!;
      addTearDown(() => tester.runAsync(e.close));
      return e;
    }

    testWidgets('E15-01 · Cuentas: tarjeta «Consumo y costos propios» y el '
        'titular fuera de la lista (D-04: «Titular» con 81 pendiente)', (
      tester,
    ) async {
      final e = await seeded(tester);
      await pump(tester, e.w.repo, const SettlementsScreen());
      final own = find.byKey(const Key('own-consumption-card'));
      expect(own, findsOneWidget);
      Finder inOwn(String text) =>
          find.descendant(of: own, matching: find.text(text));
      expect(inOwn('Consumo y costos propios'), findsOneWidget);
      expect(inOwn('Titular'), findsOneWidget);
      expect(
        inOwn('Consumo aplicado (costo FIFO) · Invierno 2026 ${bs(8100)}'),
        findsOneWidget,
      );
      expect(inOwn('1 aplicación vigente'), findsOneWidget);
      expect(
        inOwn(
          'Asientos en su cuenta (no son deuda): cargos anotados ${bs(8100)} '
          '· créditos por reversión ${bs(0)} · pagos y ajustes registrados '
          '${bs(0)}',
        ),
        findsOneWidget,
      );
      // «Titular» sólo aparece en su tarjeta, nunca como deudor.
      expect(find.text('Titular'), findsOneWidget);
      // Criterio Q-2: conserva pago y adelanto (#26).
      await tester.tap(
        find.descendant(
          of: own,
          matching: find.byType(PopupMenuButton<String>),
        ),
      );
      await settle(tester);
      expect(find.text('Ver movimientos propios'), findsOneWidget);
      expect(find.text('Registrar pago'), findsOneWidget);
      expect(find.text('Registrar adelanto'), findsOneWidget);
      await tester.tap(find.text('Ver movimientos propios'));
      await settle(tester);
      Finder inDialog(String text) => find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining(text),
      );
      expect(inDialog('Movimientos propios · Titular'), findsOneWidget);
      expect(
        inDialog('Asientos de su cuenta (registro, no deuda)'),
        findsOneWidget,
      );
      expect(inDialog('Acumulado'), findsNothing);
      expect(inDialog('Pendiente a hoy'), findsNothing);
    });

    testWidgets('E15-01 · Inicio: Familias por cobrar 20 y el titular fuera '
        'de «Principales saldos» (D-04: 101 y Titular 81)', (tester) async {
      final e = await seeded(tester);
      await pump(tester, e.w.repo, const DashboardScreen());
      final familias = find
          .ancestor(
            of: find.text('Familias por cobrar'),
            matching: find.byType(Card),
          )
          .first;
      expect(
        find.descendant(of: familias, matching: find.textContaining(bs(2000))),
        findsOneWidget,
      );
      expect(find.text('Titular'), findsNothing);
      expect(find.text('Familiar Demo'), findsOneWidget);
    });

    testWidgets('E15-01 · Personas: «Consumo propio 81,00 Bs» para el '
        'titular (D-04: saldo 81)', (tester) async {
      final e = await seeded(tester);
      await pump(tester, e.w.repo, const PersonsScreen());
      final tile = find.ancestor(
        of: find.text('Titular'),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(
          of: tile,
          matching: find.text('Consumo propio ${bs(8100)}'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('E15-05 · modo propio sólo con el titular: tarjeta y «En '
        'inventario propio no hay cuentas por cobrar.» (D-04: sólo el '
        'titular como deudor)', (tester) async {
      final repo = (await tester.runAsync(() async {
        final database = AppDatabase(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
        );
        final repo = AgroRepository(database);
        final titular = await repo.addPerson(
          name: 'Titular',
          role: PersonRole.family,
        );
        await (await database.database).insert('owner_bindings', {
          'person_id': titular,
          'member_id': 'member-e15',
          'tenant_id': 'tenant-e15',
          'owner_role': 'FAMILY',
          'bound_at': at(1, 1),
        });
        await repo.addCampaign(
          name: 'Invierno 2026',
          start: DateTime(2026, 7, 1),
        );
        await OperationModeStore(database)
            .apply(OperationMode.personal, confirmed: true);
        return repo;
      }))!;
      addTearDown(() => tester.runAsync(repo.appDatabase.close));
      await pump(tester, repo, const SettlementsScreen());
      // Como al montar la app: la modalidad se relee de la base.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SettlementsScreen)),
      );
      await tester.runAsync(
        () => container.read(operationModeProvider.notifier).reload(),
      );
      await settle(tester);
      expect(find.byKey(const Key('own-consumption-card')), findsOneWidget);
      expect(
        find.text('En inventario propio no hay cuentas por cobrar.'),
        findsOneWidget,
      );
    });
  });
}
