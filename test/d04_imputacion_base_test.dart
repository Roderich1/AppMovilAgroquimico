// D-04 · Pagos e imputación entre campañas (decisión del autor, Roderich
// Rendón, del 2026-10-27; docs/architecture/
// D04_E15_CUENTAS_IMPUTACION_Y_COSTO_PROPIO.md §3).
//
// Este archivo sólo usa API que ya existía en `ed9c55c`: imputaciones
// guardadas, `dashboard()`, `campaignCloseSummary()`, la exportación por el
// servicio y los textos de Cuentas e Inicio. Así compila sobre la base y falla
// allí por aserción, con las cifras «hoy» del documento.

import 'dart:convert';
import 'dart:io';

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/domain/money.dart';
import 'package:agroquimicos/domain/reports/report_composer.dart';
import 'package:agroquimicos/presentation/screens/dashboard_screen.dart';
import 'package:agroquimicos/presentation/screens/settlements_screen.dart';
import 'package:agroquimicos/services/reports/csv_report_generator.dart';
import 'package:agroquimicos/services/reports/report_export_service.dart';
import 'package:agroquimicos/services/reports/report_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/d04_world.dart';

void main() {
  sqfliteFfiInit();

  group('repositorio', () {
    late D04World w;
    setUp(() async => w = await D04World.create());
    tearDown(() => w.close());

    Future<int> resumen(int campaign) async =>
        (await w.repo.campaignCloseSummary(campaign))['receivable_bob_minor']!
            as int;

    test('D04-01 1b · resumen por origen: Verano 31, Invierno 40 '
        '(hoy 81 y −10)', () async {
      await w.charge(w.familiar, w.verano, at(3, 15), 8100);
      await w.charge(w.familiar, w.invierno, at(8, 10), 4000);
      await w.pay(w.familiar, 5000, campaign: w.invierno, date: at(10, 20));
      expect(await resumen(w.verano), 3100);
      expect(await resumen(w.invierno), 4000);
      expect((await w.repo.dashboard()).familyReceivableMinor, 7100);
    });

    test('D04-02 · resumen 0 y 0 (hoy 81 y −81)', () async {
      await w.charge(w.familiar, w.verano, at(3, 15), 8100);
      await w.pay(w.familiar, 8100, campaign: w.invierno, date: at(10, 20));
      expect(await resumen(w.verano), 0);
      expect(await resumen(w.invierno), 0);
    });

    test('D04-03 · resumen 0 y 21 (hoy 81 y −60)', () async {
      await w.charge(w.familiar, w.verano, at(3, 15), 8100);
      await w.charge(w.familiar, w.invierno, at(8, 10), 4000);
      await w.pay(w.familiar, 10000, campaign: w.invierno, date: at(10, 20));
      expect(await resumen(w.verano), 0);
      expect(await resumen(w.invierno), 2100);
    });

    test('D04-04 · Familias por cobrar 0 (hoy −19)', () async {
      await w.charge(w.familiar, w.verano, at(3, 15), 8100);
      await w.pay(w.familiar, 10000, date: at(10, 20));
      final dash = await w.repo.dashboard();
      expect(dash.familyReceivableMinor, 0);
      expect(dash.receivedMinor, 10000);
      expect(await resumen(w.verano), 0);
    });

    test('D04-05 · resumen de Invierno 370 (hoy 70)', () async {
      await w.pay(
        w.tercero,
        30000,
        campaign: w.invierno,
        date: at(7, 5),
        advance: true,
      );
      await w.charge(
        w.tercero,
        w.invierno,
        at(7, 10),
        25000,
        type: 'PURCHASE_ALLOCATION_CHARGE',
      );
      await w.charge(
        w.tercero,
        w.invierno,
        at(8, 15),
        12000,
        type: 'PURCHASE_ALLOCATION_CHARGE',
      );
      expect(await resumen(w.invierno), 37000);
      expect((await w.repo.dashboard()).thirdPartyReceivableMinor, 7000);
    });

    test('D04-06 · Familias por cobrar 0 (hoy −10)', () async {
      final c1 = await w.charge(w.familiar, w.verano, at(3, 15), 8100);
      await w.charge(w.familiar, w.invierno, at(8, 10), 4000);
      final q1 = await w.pay(w.familiar, 5000, date: at(10, 20));
      await w.reverse(c1, at(10, 25));
      expect((await w.repo.dashboard()).familyReceivableMinor, 0);
      expect(await resumen(w.invierno), 4000);
      expect(await w.allocationsOf(q1), {c1: 5000});
    });

    test('D04-07 · el pago nuevo no se imputa al cargo revertido '
        '(hoy q1 → c1 50)', () async {
      final c1 = await w.charge(w.familiar, w.verano, at(3, 15), 8100);
      final c2 = await w.charge(w.familiar, w.invierno, at(8, 10), 4000);
      await w.reverse(c1, at(10, 18));
      final q1 = await w.pay(
        w.familiar,
        5000,
        campaign: w.invierno,
        date: at(10, 20),
      );
      expect(await w.allocationsOf(q1), {c2: 4000});
      expect(await resumen(w.invierno), 0);
    });

    test('D04-08 · Terceros por cobrar 0 (hoy −100)', () async {
      final c1 = await w.charge(
        w.tercero,
        w.verano,
        at(3, 5),
        25000,
        type: 'PURCHASE_ALLOCATION_CHARGE',
      );
      await w.pay(w.tercero, 10000, campaign: w.verano, date: at(4, 10));
      await w.reverse(c1, at(10, 22));
      expect((await w.repo.dashboard()).thirdPartyReceivableMinor, 0);
      expect(await resumen(w.verano), 0);
    });

    test('D04-09b · resumen de Verano 81 sin imputación fabricada '
        '(hoy 31)', () async {
      await w.charge(w.familiar, w.verano, at(3, 15), 8100);
      await w.rawPayment(w.familiar, 5000, campaign: w.verano, date: at(4, 1));
      expect(await resumen(w.verano), 8100);
      expect((await w.repo.dashboard()).familyReceivableMinor, 3100);
    });

    test('M-2r · el pago posterior a la reversión no se imputa '
        '(hoy q3 → c1 21)', () async {
      final c1 = await w.charge(w.familiar, w.verano, at(3, 15), 8100);
      await w.pay(w.familiar, 3000, campaign: w.invierno, date: at(9, 1));
      await w.pay(w.familiar, 3000, date: at(9, 15));
      await w.reverse(c1, at(10, 18));
      final q3 = await w.pay(
        w.familiar,
        3000,
        campaign: w.invierno,
        date: at(10, 20),
      );
      expect(await w.allocationsOf(q3), isEmpty);
    });

    test('M-3 · mismo día: se imputa por día y luego id '
        '(hoy c2 20 y c1 5)', () async {
      final c1 = await w.charge(w.familiar, w.invierno, at(8, 10, 18), 3000);
      await w.charge(w.familiar, w.invierno, at(8, 10), 2000);
      final q1 = await w.pay(
        w.familiar,
        2500,
        campaign: w.invierno,
        date: at(10, 21),
      );
      expect(await w.allocationsOf(q1), {c1: 2500});
    });

    test('M-4 · tardía: resumen de Verano 21 (hoy 111)', () async {
      await w.charge(w.familiar, w.verano, at(3, 15), 8100);
      await w.charge(w.familiar, w.invierno, at(8, 10), 4000);
      await w.pay(w.familiar, 5000, campaign: w.invierno, date: at(10, 20));
      await w.charge(w.familiar, w.verano, at(6, 20), 3000);
      await w.pay(w.familiar, 4000, campaign: w.invierno, date: at(10, 25));
      expect(await resumen(w.verano), 2100);
      expect(await resumen(w.invierno), 4000);
    });

    test('M-5 · adelanto sin cargos: Familias 0 y resumen 0 '
        '(hoy −100 y −100)', () async {
      await w.pay(
        w.familiar,
        10000,
        campaign: w.invierno,
        date: at(7, 5),
        advance: true,
      );
      expect((await w.repo.dashboard()).familyReceivableMinor, 0);
      expect(await resumen(w.invierno), 0);
    });

    test('D-R6 · el ADMIN no entra en el resumen (hoy sí)', () async {
      await w.charge(w.admin, w.invierno, at(8, 10), 1000);
      expect(await resumen(w.invierno), 0);
    });
  });

  group('exportación', () {
    late Directory root;
    late D04World w;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('agro_d04_export_');
      w = await D04World.create();
    });
    tearDown(() async {
      await w.close();
      await root.delete(recursive: true);
    });

    test('M-8 · estado de cuenta filtrado por Invierno: apertura por fecha y '
        'totales con etiquetas propias (hoy «Saldo final» 121)', () async {
      await w.charge(w.familiar, w.verano, at(3, 15), 8100);
      await w.charge(w.familiar, w.invierno, at(8, 10), 4000);
      await w.pay(w.familiar, 5000, date: at(10, 20));
      final service = ReportExportService(
        w.repo,
        LocalReportStorage(
          directory: () async => Directory(p.join(root.path, 'reportes')),
        ),
        clock: () => DateTime(2026, 10, 27, 10),
      );
      final table = await service.compose(
        ReportRequest(
          kind: ReportKind.accountStatement,
          format: ReportFormat.csv,
          campaignId: w.invierno,
          personId: w.familiar,
        ),
      );
      final csv = utf8.decode(const CsvReportGenerator().generate(table));
      expect(csv, contains('Saldo al inicio del período (Bs);81,00'));
      expect(csv, contains('Saldo a hoy (Bs);71,00'));
      expect(
        csv,
        contains('Deuda pendiente por origen · Invierno 2026 (Bs);40,00'),
      );
      expect(csv, contains('Saldo neto · todas las campañas (Bs);71,00'));
      expect(csv, contains('Imputado: Verano 2026 ${bs(5000)}'));
      expect(csv, isNot(contains('Saldo final')));
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

    Future<D04World> world(
      WidgetTester tester,
      Future<void> Function(D04World w) seed,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final w = (await tester.runAsync(D04World.create))!;
      addTearDown(() => tester.runAsync(w.close));
      await tester.runAsync(() => seed(w));
      return w;
    }

    Future<void> pump(WidgetTester tester, D04World w, Widget screen) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [repositoryProvider.overrideWithValue(w.repo)],
          child: MaterialApp(home: Scaffold(body: screen)),
        ),
      );
      await settle(tester);
    }

    Finder card(String name) =>
        find.ancestor(of: find.text(name), matching: find.byType(Card)).first;

    testWidgets('D04-01 1b · Cuentas filtrada por Invierno: deuda por origen '
        '40 y saldo neto 71 (hoy «A favor · Invierno 2026» −10)', (
      tester,
    ) async {
      final w = await world(tester, (w) async {
        await w.charge(w.familiar, w.verano, at(3, 15), 8100);
        await w.charge(w.familiar, w.invierno, at(8, 10), 4000);
        await w.pay(w.familiar, 5000, campaign: w.invierno, date: at(10, 20));
      });
      await pump(tester, w, const SettlementsScreen());
      final familiar = card('Familiar Demo');
      Finder inCard(String text) =>
          find.descendant(of: familiar, matching: find.text(text));
      expect(
        inCard(
          'Cargos de Invierno 2026 ${bs(4000)} · pagos aplicados ${bs(0)}',
        ),
        findsOneWidget,
      );
      expect(
        inCard('Saldo neto · todas las campañas ${bs(7100)}'),
        findsOneWidget,
      );
      expect(
        inCard('Deuda pendiente por origen · Invierno 2026'),
        findsOneWidget,
      );
      expect(
        find.descendant(of: familiar, matching: find.textContaining(bs(4000))),
        findsWidgets,
      );
      expect(find.textContaining('A favor · Invierno 2026'), findsNothing);

      // Detalle: desglose por origen y cronológico por período.
      await tester.tap(
        find.descendant(
          of: familiar,
          matching: find.byType(PopupMenuButton<String>),
        ),
      );
      await settle(tester);
      await tester.tap(find.text('Ver detalle cronológico'));
      await settle(tester);
      Finder inDialog(String text) => find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining(text),
      );
      expect(inDialog('Deuda pendiente por origen (a hoy)'), findsOneWidget);
      expect(
        inDialog(
          'Verano 2026: cargos ${bs(8100)} · pagos aplicados ${bs(5000)} · '
          'pendiente ${bs(3100)}',
        ),
        findsOneWidget,
      );
      expect(
        inDialog('Saldo al inicio del período (01/07/2026)'),
        findsOneWidget,
      );
      expect(inDialog('Imputado: Verano 2026 ${bs(5000)}'), findsOneWidget);
      // La lista del diálogo es perezosa: el cierre está al final.
      await tester.drag(
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(ListView),
            )
            .first,
        const Offset(0, -3000),
      );
      await settle(tester);
      expect(inDialog('Saldo a hoy'), findsOneWidget);
      expect(inDialog('Saldo inicial de campaña'), findsNothing);
      await tester.tap(find.text('Cerrar'));
      await settle(tester);
    });

    testWidgets('D04-01 · diálogo de pago: saldo neto de todas las campañas '
        'y mensaje con la imputación escrita (hoy «Saldo pendiente 40,00»)', (
      tester,
    ) async {
      final w = await world(tester, (w) async {
        await w.charge(w.familiar, w.verano, at(3, 15), 8100);
        await w.charge(w.familiar, w.invierno, at(8, 10), 4000);
      });
      await pump(tester, w, const SettlementsScreen());
      await tester.tap(
        find.descendant(
          of: card('Familiar Demo'),
          matching: find.byType(PopupMenuButton<String>),
        ),
      );
      await settle(tester);
      await tester.tap(find.text('Registrar pago'));
      await settle(tester);
      Finder inDialog(String text) => find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(text),
      );
      expect(inDialog('Se registra en: Invierno 2026'), findsOneWidget);
      expect(
        inDialog('Saldo neto · todas las campañas: debe ${bs(12100)}'),
        findsOneWidget,
      );
      expect(
        inDialog(
          'Se aplica primero a la deuda más antigua, de cualquier campaña.',
        ),
        findsOneWidget,
      );
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        '50',
      );
      await tester.tap(find.text('Registrar'));
      await settle(tester);
      expect(
        find.text(
          'Pago de ${bs(5000)} registrado a Familiar Demo. '
          'Imputado: Verano 2026 ${bs(5000)}.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('D04-04 · Inicio: Familias por cobrar 0 y «A favor de '
        'familias: 19,00 Bs» (hoy −19)', (tester) async {
      final w = await world(tester, (w) async {
        await w.charge(w.familiar, w.verano, at(3, 15), 8100);
        await w.pay(w.familiar, 10000, date: at(10, 20));
      });
      await pump(tester, w, const DashboardScreen());
      final familias = find
          .ancestor(
            of: find.text('Familias por cobrar'),
            matching: find.byType(Card),
          )
          .first;
      expect(
        find.descendant(of: familias, matching: find.text(formatBob(0))),
        findsWidgets,
        reason: 'por cobrar = max(0, saldo neto)',
      );
      expect(
        find.descendant(
          of: familias,
          matching: find.text('A favor de familias: ${bs(1900)}'),
        ),
        findsOneWidget,
      );
    });
  });
}
