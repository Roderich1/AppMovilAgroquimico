// Ronda 2 del rediseño, sesión C (P2 y P3): Personas con dos áreas
// (Cuentas y Costos) y una sola lista de personas; `/liquidacion` ya no
// repite la lista; los respaldos siguen en Ajustes › Respaldos; el estado de
// cuenta y los movimientos propios comparten estructura (resumen, período,
// exportar) con contenido distinto. Datos sintéticos (`c_seed.dart`).
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/domain/account_texts.dart' show bob;
import 'package:agroquimicos/domain/reports/report_composer.dart';
import 'package:agroquimicos/presentation/screens/reports_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_ui_harness.dart';
import 'support_rdm2/c_seed.dart';

void main() {
  sqfliteFfiInit();

  Future<void> tapKey(WidgetTester tester, Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.pump();
    await tester.tap(find.byKey(key));
    await settle(tester);
  }

  Future<(Rdm2cWorld, dynamic)> open(
    WidgetTester tester,
    String name,
    String route,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final w = await seedRdm2cWorld(tester, name);
    final c = await pumpModeApp(tester, w.database);
    c.read(routerProvider).go(route);
    await waitFor(tester, find.byKey(const Key('persons-area-accounts')));
    await settle(tester);
    return (w, c);
  }

  for (final route in ['/personas', '/liquidacion']) {
    testWidgets('$route: una sola lista; cada persona una vez; sin la fila '
        '«Por campaña, costos y respaldos» ni el menú de respaldos', (
      tester,
    ) async {
      final (w, _) = await open(tester, 'rdm2-c-areas-$route', route);
      for (final name in [
        rdm2cOwnerName,
        rdm2cLongName,
        rdm2cThirdName,
        rdm2cQuietName,
        rdm2cAdminName,
      ]) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
      expect(find.text('Por campaña, costos y respaldos'), findsNothing);
      expect(find.byTooltip('Copias de seguridad'), findsNothing);
      expect(find.text('Personas'), findsWidgets);
      // El titular: su consumo propio, sin pago; los demás, con pago.
      expect(find.byKey(const Key('own-consumption-card')), findsOneWidget);
      expect(find.byKey(Key('account-pay-${w.owner}')), findsNothing);
      expect(find.byKey(Key('account-pay-${w.third}')), findsOneWidget);
      expect(find.byKey(Key('account-pay-${w.admin}')), findsNothing);
      // Alcance claro: la campaña activa, y «todas» en la cabecera.
      expect(
        find.textContaining('Deuda pendiente por origen · Invierno 2026'),
        findsWidgets,
      );
      expect(
        find.textContaining('Le deben · todas las campañas'),
        findsOneWidget,
      );
    });
  }

  testWidgets('Costos: por chaco, hectárea y producto, con el alcance y su '
      'exportación (Excel o PDF en Reportes)', (tester) async {
    final (w, c) = await open(tester, 'rdm2-c-areas-costos', '/personas');
    await tapKey(tester, const Key('persons-area-costs'));
    expect(find.text('Costo por chaco y hectárea'), findsOneWidget);
    expect(find.text('Costo consumido por producto'), findsOneWidget);
    expect(find.text('Chaco Río Grande de la Quebrada'), findsOneWidget);
    expect(
      find.text('Aplicaciones de Invierno 2026 (sin las revertidas)'),
      findsOneWidget,
    );
    // La lista de personas no se repite aquí.
    expect(find.byKey(const Key('own-consumption-card')), findsNothing);
    // Todas las campañas.
    await tester.tap(find.text('Invierno 2026').first);
    await settle(tester);
    await tester.tap(find.text('Todas las campañas').last);
    await settle(tester);
    expect(
      find.text('Aplicaciones de todas las campañas (sin las revertidas)'),
      findsOneWidget,
    );
    await tapKey(tester, const Key('costs-export-farms'));
    final reports = tester.widget<ReportsScreen>(find.byType(ReportsScreen));
    expect(reports.initialKind, ReportKind.farmCost);
    expect(reports.initialCampaignId, isNull);
    expect(w.verano, isPositive);
    expect(c, isNotNull);
  });

  // Ajustes › Respaldos (exportar y restaurar) lo recorre
  // f04_admin_owner_restore_ui_test.dart, que prepara path_provider.

  testWidgets('detalles con la misma estructura: estado de cuenta con pago y '
      'movimientos propios sin pago', (tester) async {
    final (w, c) = await open(tester, 'rdm2-c-areas-detalle', '/personas');
    await tapKey(tester, Key('person-statement-${w.third}'));
    for (final key in ['detail-summary', 'detail-period', 'detail-export']) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
    expect(find.byKey(const Key('detail-pay')), findsOneWidget);
    expect(find.text('Debe · todas las campañas'), findsOneWidget);
    // Período: recalcula con el libro ya leído.
    expect(find.textContaining('período de Invierno 2026'), findsWidgets);
    await tester.tap(find.byKey(const Key('detail-period')));
    await settle(tester);
    await tester.tap(find.text('Todas las campañas').last);
    await settle(tester);
    expect(
      find.text('Estado de cuenta cronológico · todas las campañas'),
      findsOneWidget,
    );
    // Pagar desde el detalle: una vez, y la cifra se actualiza.
    await tapKey(tester, const Key('detail-pay'));
    await tester.enterText(find.byKey(const Key('payment-amount')), '100');
    await settle(tester);
    await tapKey(tester, const Key('payment-submit'));
    final rows = (await tester.runAsync(
      () async => (await w.database.database).query(
        'account_transactions',
        where: "person_id=? AND type='PAYMENT'",
        whereArgs: [w.third],
      ),
    ))!;
    expect(rows, hasLength(2));
    expect(
      tester.widget<Text>(find.byKey(const Key('detail-amount'))).data,
      '600,00',
    );
    await tester.tap(find.text('Cerrar'));
    await settle(tester);

    await tapKey(tester, Key('person-statement-${w.owner}'));
    for (final key in ['detail-summary', 'detail-period', 'detail-export']) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
    expect(find.byKey(const Key('detail-pay')), findsNothing);
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Registrar pago'),
      ),
      findsNothing,
    );
    expect(find.text('No es deuda'), findsWidgets);
    expect(
      find.textContaining('Imputado: Invierno 2026 ${bob(20000)}'),
      findsOneWidget,
    );
    await tapKey(tester, const Key('detail-export'));
    final reports = tester.widget<ReportsScreen>(find.byType(ReportsScreen));
    expect(reports.initialKind, ReportKind.accountStatement);
    expect(reports.initialPersonId, w.owner);
    expect(reports.initialCampaignId, w.invierno);
    expect(c, isNotNull);
  });
}
