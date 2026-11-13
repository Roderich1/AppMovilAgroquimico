// Ronda 2 del rediseño, sesión C (P1a). Decisión del autor del 2026-11-12,
// que revisa el criterio Q-2/C-12 (#26) de D04_E15 §7: el titular tiene
// consumo y costos propios; no se le registra un pago de cuenta personal
// («cobro» a sí mismo). No afecta a sus compras ni a sus pagos a proveedores.
// Los asientos históricos se conservan y se siguen leyendo como registro.
//
// Base sintética: el mundo de D-04/E-15 (en memoria) para el repositorio y
// el hogar activado del arnés de F04 para las pantallas.
import 'dart:convert';
import 'dart:io';

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/domain/account_texts.dart';
import 'package:agroquimicos/domain/reports/report_composer.dart';
import 'package:agroquimicos/services/reports/pdf_report_generator.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/operation_mode_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/d04_world.dart';
import 'support/e15_world.dart';
import 'support/f04_mode_ui_harness.dart';
import 'support_rdm2/c_seed.dart';

void main() {
  sqfliteFfiInit();

  Future<int> paymentRows(E15World e, int person) async =>
      (await (await e.w.db).query(
        'account_transactions',
        where: "person_id=? AND type IN ('PAYMENT','ADVANCE')",
        whereArgs: [person],
      )).length;

  Matcher rejectedForOwner() => throwsA(
    isA<BusinessRuleException>().having(
      (e) => e.message,
      'message',
      ownerAccountPaymentRejectedMessage,
    ),
  );

  group('repositorio: el pago de cuenta personal del titular se rechaza', () {
    late E15World e;
    setUp(() async => e = await E15World.create());
    tearDown(() => e.close());

    test(
      'pago y adelanto al titular vigente: rechazados, sin escribir',
      () async {
        await e.seedE1501();
        for (final advance in [false, true]) {
          await expectLater(
            e.w.repo.registerAccountPayment(
              personId: e.titular,
              campaignId: e.w.invierno,
              amountBobMinor: 8100,
              advance: advance,
            ),
            rejectedForOwner(),
          );
        }
        // También por la entrada antigua y con una fecha anterior al vínculo
        // (todo lo del titular vigente es propio, criterio Q-3).
        await expectLater(
          e.w.pay(e.titular, 100, date: at(1, 1)),
          rejectedForOwner(),
        );
        expect(await paymentRows(e, e.titular), 0);
      },
    );

    test('las demás personas siguen pagando como siempre', () async {
      await e.seedE1501();
      final result = await e.w.repo.registerAccountPayment(
        personId: e.w.familiar,
        campaignId: e.w.invierno,
        amountBobMinor: 2000,
      );
      expect(result.imputed.single.amountMinor, 2000);
      expect(await paymentRows(e, e.w.familiar), 1);
    });

    test('titular anterior: se rechaza un pago con fecha de cuando era '
        'titular; uno de hoy (por cobrar) se registra', () async {
      await e.changeOwner(e.w.familiar, at(10, 1));
      await expectLater(
        e.w.pay(e.titular, 500, date: at(5, 1)),
        rejectedForOwner(),
      );
      await e.w.repo.registerAccountPayment(
        personId: e.titular,
        amountBobMinor: 500,
      );
      expect(await paymentRows(e, e.titular), 1);
      // El nuevo titular tampoco recibe pagos de cuenta.
      await expectLater(
        e.w.repo.registerAccountPayment(
          personId: e.w.familiar,
          amountBobMinor: 500,
        ),
        rejectedForOwner(),
      );
    });

    test(
      'las compras y los pagos a proveedores del titular no cambian',
      () async {
        final purchase = await e.w.repo.confirmPurchase(
          PurchaseDraft(
            supplierId: e.supplier,
            campaignId: e.w.invierno,
            purchaseDate: DateTime(2026, 7, 1),
            items: [
              PurchaseItemDraft(
                productId: e.products['Glifosato']!,
                quantityBase: 2000,
                currency: CurrencyCode.bob,
                originalUnitPriceMinor: 4500,
                allocations: [
                  AllocationDraft(personId: e.titular, quantityBase: 2000),
                ],
              ),
            ],
          ),
        );
        await e.w.repo.addProviderPayment(
          purchaseId: purchase,
          payerPersonId: e.titular,
          amountBobMinor: 9000,
          method: PaymentMethod.cash,
        );
        final paid = await (await e.w.db).query(
          'provider_payments',
          where: 'purchase_id=? AND payer_person_id=?',
          whereArgs: [purchase, e.titular],
        );
        expect(paid.single['amount_bob_minor'], 9000);
      },
    );

    test('inventario propio: nadie recibe pagos de cuenta', () async {
      await OperationModeStore(e.w.database)
          .apply(OperationMode.personal, confirmed: true);
      await expectLater(
        e.w.repo.registerAccountPayment(
          personId: e.titular,
          amountBobMinor: 100,
        ),
        rejectedForOwner(),
      );
      await expectLater(
        e.w.repo.registerAccountPayment(
          personId: e.w.familiar,
          amountBobMinor: 100,
        ),
        throwsA(isA<PersonalModeRestrictionException>()),
      );
    });

    test('un pago histórico del titular (menú Q-2) se sigue leyendo como '
        'registro, no como cobro', () async {
      await e.seedE1501();
      await (await e.w.db).insert('account_transactions', {
        'person_id': e.titular,
        'campaign_id': e.w.invierno,
        'transaction_date': at(10, 25),
        'type': 'PAYMENT',
        'amount_bob_minor_signed': -3000,
        'reference_type': 'PAYMENT',
      });
      final ledger = await e.w.repo.accountLedger();
      expect(
        ledger.ownAccount(e.titular).entries.map((x) => x.amountMinor),
        contains(-3000),
      );
      expect(ledger.receivedMinor(), 0);
      expect(ledger.account(e.titular).entries, isEmpty);
    });
  });

  group(
    'asiento histórico de pago del titular, imputado a su cargo propio',
    () {
      // El caso visto en el emulador el 2026-11-12: un «Pago» del titular
      // «registrado en Invierno 2026», «Imputado: Invierno 2026 22,00 Bs».
      late E15World e;
      late int paymentId;
      setUp(() async {
        e = await E15World.create();
        await e.seedE1501();
        final db = await e.w.db;
        final charge = (await db.query(
          'account_transactions',
          where: "person_id=? AND type='USAGE_CHARGE'",
          whereArgs: [e.titular],
        )).single;
        paymentId = await db.insert('account_transactions', {
          'person_id': e.titular,
          'campaign_id': e.w.invierno,
          'transaction_date': at(11, 12, 9),
          'type': 'PAYMENT',
          'amount_bob_minor_signed': -2200,
          'reference_type': 'PAYMENT',
        });
        await db.insert('payment_allocations', {
          'payment_transaction_id': paymentId,
          'charge_transaction_id': charge['id'],
          'amount_bob_minor': 2200,
        });
      });
      tearDown(() => e.close());

      test(
        'se lee como registro propio, con su imputación, y no como cobro',
        () async {
          final ledger = await e.w.repo.accountLedger();
          final own = ledger.ownAccount(e.titular);
          final entry = own.entries.singleWhere((x) => x.id == paymentId);
          expect(
            statusText(ledger, own, entry, ownRecord: true),
            'Imputado: Invierno 2026 ${bob(2200)}',
          );
          expect(ownRecordTotals(own).paymentsMinor, 2200);
          expect(ledger.account(e.titular).entries, isEmpty);
          expect(ledger.receivedMinor(), 0);
          expect(
            ledger.summaries().map((row) => row.personId),
            isNot(contains(e.titular)),
          );
        },
      );

      test(
        'la guarda no lo toca y el estado de cuenta y el PDF lo incluyen',
        () async {
          await expectLater(
            e.w.repo.registerAccountPayment(
              personId: e.titular,
              amountBobMinor: 100,
            ),
            rejectedForOwner(),
          );
          expect(await paymentRows(e, e.titular), 1);
          final statement = await e.w.repo.accountStatement(e.titular);
          expect(statement.ownLines.map((x) => x.id), contains(paymentId));
          final table = const ReportComposer().ownStatement(
            statement: statement,
            generatedAt: DateTime(2026, 11, 12, 10),
          );
          final content = latin1.decode(
            const PdfReportGenerator().generate(table),
          );
          expect(content, startsWith('%PDF-1.4'));
          expect(content, contains('(22,00)'));
          expect(content, contains('Pagos y ajustes registrados'));
        },
      );
    },
  );

  test('la consulta de sólo lectura encuentra los mismos asientos que el '
      'criterio de clase (Q-3) y no cambia nada', () async {
    final e = await E15World.create();
    addTearDown(e.close);
    await e.seedE1501();
    final db = await e.w.db;
    Future<int> rawPayment(int person, String date, int minor) =>
        db.insert('account_transactions', {
          'person_id': person,
          'campaign_id': e.w.invierno,
          'transaction_date': date,
          'type': 'PAYMENT',
          'amount_bob_minor_signed': -minor,
          'reference_type': 'PAYMENT',
        });
    final ownBefore = await rawPayment(e.titular, at(10, 21), 2200);
    final familiarEarly = await e.w.pay(e.w.familiar, 500, date: at(9, 1));
    // Cambio de titular: lo del nuevo titular es propio entero (Q-3); el
    // titular anterior conserva como propio sólo lo de su intervalo.
    await e.changeOwner(e.w.familiar, at(10, 25));
    final formerAfter = await rawPayment(e.titular, at(10, 30), 700);
    final formerInside = await rawPayment(e.titular, at(10, 24), 300);
    final tercero = await e.w.pay(e.w.tercero, 900, date: at(10, 2));

    final sql = File('tool/rediseno/asientos_pago_titular.sql')
        .readAsStringSync()
        .trim();
    final before = await db.query('account_transactions');
    final found = {
      for (final row in await db.rawQuery(sql)) row['asiento_id']! as int,
    };
    expect(await db.query('account_transactions'), before);

    final ledger = await e.w.repo.accountLedger();
    final byRule = {
      for (final account in ledger.ownAccounts.values)
        for (final entry in account.entries)
          if (entry.type == 'PAYMENT' || entry.type == 'ADVANCE') entry.id,
    };
    expect(found, byRule);
    expect(found, {ownBefore, familiarEarly, formerInside});
    expect(found, isNot(contains(formerAfter)));
    expect(found, isNot(contains(tercero)));
  });

  group('pantallas: ningún acceso registra un pago al titular', () {
    Future<void> openOwnMenu(WidgetTester tester) async {
      final menu = find.descendant(
        of: find.byKey(const Key('own-consumption-card')),
        matching: find.byType(PopupMenuButton<String>),
      );
      await tester.ensureVisible(menu);
      await tester.pump();
      await tester.tap(menu);
      await settle(tester);
    }

    testWidgets('Cuentas: el menú de lo propio no ofrece «Registrar pago»', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final w = await seedRdm2cWorld(tester, 'rdm2-c-pago-menu');
      final c = await pumpModeApp(tester, w.database);
      c.read(routerProvider).go('/liquidacion');
      await waitFor(tester, find.byKey(const Key('own-consumption-card')));
      await settle(tester);
      await openOwnMenu(tester);
      expect(find.text('Ver movimientos propios'), findsWidgets);
      expect(find.text('Exportar movimientos propios'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(PopupMenuItem<String>),
          matching: find.text('Registrar pago'),
        ),
        findsNothing,
      );
      expect(find.byKey(Key('account-pay-${w.owner}')), findsNothing);
      expect(find.byKey(Key('person-pay-${w.owner}')), findsNothing);
      // Las demás personas conservan su botón.
      expect(find.byKey(Key('account-pay-${w.third}')), findsOneWidget);
      // El asiento histórico del titular se sigue mostrando como registro.
      await tester.tap(find.text('Ver movimientos propios').last);
      await settle(tester);
      expect(
        find.textContaining('Imputado: Invierno 2026 ${bob(20000)}'),
        findsOneWidget,
      );
    });

    testWidgets('Personas y Persona: sin «Registrar pago» para el titular', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final w = await seedRdm2cWorld(tester, 'rdm2-c-pago-personas');
      final c = await pumpModeApp(tester, w.database);
      c.read(routerProvider).go('/personas');
      await waitFor(tester, find.byKey(const Key('persons-receivable')));
      await settle(tester);
      expect(find.byKey(Key('person-pay-${w.owner}')), findsNothing);
      expect(find.byKey(Key('account-pay-${w.owner}')), findsNothing);
      c.read(routerProvider).push('/personas/${w.owner}');
      await settle(tester);
      expect(find.text(rdm2cOwnerName), findsWidgets);
      expect(find.byKey(const Key('person-detail-pay')), findsNothing);
      expect(find.text('Registrar pago'), findsNothing);
    });

    testWidgets('inventario propio: ningún «Registrar pago» de cuenta', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final w = await seedRdm2cWorld(
        tester,
        'rdm2-c-pago-propio',
        withBalances: false,
      );
      final c = await pumpModeApp(tester, w.database);
      await tester.runAsync(() async {
        await OperationModeStore(w.database)
            .apply(OperationMode.personal, confirmed: true);
        await c.read(operationModeProvider.notifier).reload();
      });
      for (final route in ['/personas', '/liquidacion']) {
        c.read(routerProvider).go(route);
        await settle(tester);
        await settle(tester);
        expect(
          find.widgetWithText(FilledButton, 'Registrar pago'),
          findsNothing,
          reason: route,
        );
      }
      c.read(routerProvider).push('/personas/${w.owner}');
      await settle(tester);
      expect(find.byKey(const Key('person-detail-pay')), findsNothing);
    });
  });
}
