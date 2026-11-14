// Rediseño, sesión A (grupo Personas): «Registrar pago» desde la tarjeta de
// Personas y desde la cabecera de Persona usa la misma hoja y el mismo
// registro que Cuentas. «Pagar todo» sólo escribe el importe: nunca registra
// solo. App real (arnés de F04) sobre una base sintética.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/account_texts.dart' show bob;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_ui_harness.dart';

void main() {
  sqfliteFfiInit();

  /// Hogar con un cargo de 200,00 Bs a la hermana (una aplicación).
  Future<({dynamic database, int relative})> home(
    WidgetTester tester,
    String name,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, name);
    final h = s.household;
    await tester.runAsync(() async {
      await h.buy(h.relative, 4000);
      await h.repo.confirmApplication(
        ApplicationDraft(
          personId: h.relative,
          farmId: h.relativeFarm,
          campaignId: h.campaign,
          appliedAt: DateTime.now(),
          lines: [
            ApplicationLineDraft(productId: h.product, quantityBase: 2000),
          ],
        ),
      );
    });
    return (database: s.database, relative: h.relative);
  }

  Future<List<Map<String, Object?>>> payments(
    WidgetTester tester,
    dynamic database,
    int person,
  ) async => (await tester.runAsync(
    () async => (await database.database).query(
      'account_transactions',
      where: "person_id = ? AND type IN ('PAYMENT', 'ADVANCE')",
      whereArgs: [person],
    ),
  ))!;

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.pump();
    await tester.tap(find.byKey(Key(key)));
    await settle(tester);
  }

  testWidgets('Personas: «Registrar pago» de la tarjeta registra un pago; '
      '«Pagar todo» sólo escribe el importe', (tester) async {
    final s = await home(tester, 'rdm-a-personas-pago');
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).go('/personas');
    await waitFor(tester, find.byKey(Key('person-pay-${s.relative}')));
    await settle(tester);

    await tapKey(tester, 'person-pay-${s.relative}');
    expect(find.byKey(const Key('payment-sheet')), findsOneWidget);
    // «Pagar todo» no registra nada: sólo rellena el campo.
    await tapKey(tester, 'payment-all');
    expect(await payments(tester, s.database, s.relative), isEmpty);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('payment-amount')))
          .controller!
          .text,
      '200',
    );
    expect(find.text('Quedará al día'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('payment-amount')), '50');
    await settle(tester);
    expect(find.text('Quedará debiendo ${bob(15000)}'), findsOneWidget);
    await tapKey(tester, 'payment-submit');

    final rows = await payments(tester, s.database, s.relative);
    expect(rows, hasLength(1));
    expect(rows.single['amount_bob_minor_signed'], -5000);
    expect(find.byKey(const Key('payment-sheet')), findsNothing);
  });

  testWidgets('Persona: «Registrar pago» de la cabecera registra un pago; '
      'cancelar no escribe nada', (tester) async {
    final s = await home(tester, 'rdm-a-persona-pago');
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).go('/personas');
    await settle(tester);
    c.read(routerProvider).push('/personas/${s.relative}');
    await waitFor(tester, find.byKey(const Key('person-detail-pay')));
    await settle(tester);

    await tapKey(tester, 'person-detail-pay');
    await tapKey(tester, 'payment-cancel');
    expect(await payments(tester, s.database, s.relative), isEmpty);

    await tapKey(tester, 'person-detail-pay');
    await tester.enterText(find.byKey(const Key('payment-amount')), '40');
    await settle(tester);
    await tapKey(tester, 'payment-submit');
    final rows = await payments(tester, s.database, s.relative);
    expect(rows, hasLength(1));
    expect(rows.single['amount_bob_minor_signed'], -4000);
    // La cabecera se recarga con el saldo nuevo: 200,00 − 40,00.
    expect(
      tester.widget<Text>(find.byKey(const Key('person-headline-amount'))).data,
      '160,00',
    );
  });
}
