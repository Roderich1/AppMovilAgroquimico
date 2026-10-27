// D-04 · Pagos e imputación entre campañas (decisión del autor, Roderich
// Rendón, del 2026-10-27). Cada prueba es un ejemplo de
// docs/architecture/D04_E15_CUENTAS_IMPUTACION_Y_COSTO_PROPIO.md §3, con sus
// cifras exactas en la lista de Cuentas («Todas» y por campaña), el detalle,
// la exportación, Inicio y el resumen de campaña, más las invariantes de §2.8.
//
// Usa las lecturas nuevas (`accountSummaries`, `accountStatement`,
// `registerAccountPayment`), que no existen en `ed9c55c`: sobre la base este
// archivo no compila. La prueba que falla por aserción sobre la base es
// `d04_imputacion_base_test.dart`.

import 'dart:convert';

import 'package:agroquimicos/domain/account_ledger.dart';
import 'package:agroquimicos/domain/account_texts.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/reports/report_composer.dart';
import 'package:agroquimicos/domain/reports/report_table.dart';
import 'package:agroquimicos/services/reports/csv_report_generator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/d04_world.dart';

void main() {
  sqfliteFfiInit();

  late D04World w;
  setUp(() async => w = await D04World.create());
  tearDown(() => w.close());

  AccountSummary rowOf(List<AccountSummary> rows, int person) =>
      rows.firstWhere((row) => row.personId == person);

  /// Las tres tarjetas de una persona: «Todas», Verano e Invierno.
  Future<({AccountSummary all, AccountSummary v, AccountSummary i})> cards(
    int person,
  ) async => (
    all: rowOf(await w.repo.accountSummaries(), person),
    v: rowOf(await w.repo.accountSummaries(campaignId: w.verano), person),
    i: rowOf(await w.repo.accountSummaries(campaignId: w.invierno), person),
  );

  /// Invariantes de §2.8 para todas las personas.
  Future<void> invariants() async {
    final ledger = await w.repo.accountLedger();
    var totalPending = 0;
    for (final person in ledger.persons) {
      final account = ledger.account(person.id);
      // I-2: N = P − F = suma con signo.
      expect(account.netMinor, account.signedSumMinor, reason: person.name);
      // I-1: Σ_K deuda_K = P.
      final byCampaign = account
          .debtsByCampaign(ledger.campaignOrder)
          .fold(0, (sum, debt) => sum + debt.pendingMinor);
      expect(byCampaign, account.pendingMinor, reason: person.name);
      // I-3: Σ imputaciones = aplicados + liberado.
      final allocated = account.credits.values.fold(
        0,
        (sum, credit) => sum + credit.allocatedMinor,
      );
      expect(
        allocated,
        account.total.appliedMinor + account.total.releasedMinor,
        reason: person.name,
      );
      if (person.role != 'ADMIN') totalPending += account.pendingMinor;
      // I-4: el cronológico de la campaña activa cierra en N.
      final statement = ledger.statement(person.id, campaignId: w.invierno);
      expect(statement.closingMinor, account.netMinor, reason: person.name);
      expect(
        ledger.statement(person.id).closingMinor,
        account.netMinor,
        reason: person.name,
      );
    }
    // I-6 / I-7: el resumen de cada campaña es la suma de las tarjetas.
    var sumResumen = 0;
    for (final campaign in [w.verano, w.invierno]) {
      final resumen =
          (await w.repo.campaignCloseSummary(campaign))['receivable_bob_minor']!
              as int;
      final cardsSum = (await w.repo.accountSummaries(campaignId: campaign))
          .fold(0, (sum, row) => sum + row.scope.pendingMinor);
      expect(resumen, cardsSum);
      sumResumen += resumen;
    }
    expect(sumResumen, totalPending);
    // I-5: Inicio = Σ max(0, P − F) por rol.
    final summary = await w.repo.dashboard();
    var family = 0;
    for (final row in await w.repo.accountSummaries()) {
      if (row.role == 'FAMILY' && row.account.netMinor > 0) {
        family += row.account.netMinor;
      }
    }
    expect(summary.familyReceivableMinor, family);
  }

  Future<AccountStatement> statement(int person, {int? campaign}) =>
      w.repo.accountStatement(person, campaignId: campaign);

  List<String> statuses(AccountStatement s) => [
    for (final line in s.lines) statusText(s.ledger, s.account, line.entry),
  ];

  group('D04-01 · ejemplo obligatorio', () {
    for (final registeredIn in ['Todas', 'Invierno']) {
      test('pago global de 50: Verano 31, Invierno 40, total 71 '
          '(registrado con «$registeredIn»)', () async {
        final c1 = await w.charge(w.familiar, w.verano, at(3, 15), 8100);
        final c2 = await w.charge(w.familiar, w.invierno, at(8, 10), 4000);
        final payment = await w.repo.registerAccountPayment(
          personId: w.familiar,
          campaignId: registeredIn == 'Todas' ? null : w.invierno,
          amountBobMinor: 5000,
          date: DateTime.parse(at(10, 20)),
        );
        expect(await w.allocationsOf(payment.paymentId), {c1: 5000});
        expect(c2, isPositive);
        expect(
          payment.message('Familiar Demo'),
          'Pago de ${bs(5000)} registrado a Familiar Demo. '
          'Imputado: Verano 2026 ${bs(5000)}.',
        );

        final c = await cards(w.familiar);
        expect(
          chargesLine(c.all.scope),
          'Cargos ${bs(12100)} · pagos aplicados ${bs(5000)}',
        );
        expect(
          pendingAndCreditLine(c.all.account),
          'Deuda pendiente ${bs(7100)} · a favor (no aplicado a deuda) ${bs(0)}',
        );
        expect(c.all.account.netMinor, 7100);
        expect(
          chargesLine(c.v.scope, campaignName: 'Verano 2026'),
          'Cargos de Verano 2026 ${bs(8100)} · pagos aplicados ${bs(5000)}',
        );
        expect(
          netLine(c.v.account),
          'Saldo neto · todas las campañas ${bs(7100)}',
        );
        expect(c.v.scope.pendingMinor, 3100);
        expect(
          chargesLine(c.i.scope, campaignName: 'Invierno 2026'),
          'Cargos de Invierno 2026 ${bs(4000)} · pagos aplicados ${bs(0)}',
        );
        expect(c.i.scope.pendingMinor, 4000);
        expect(unattributedCreditLine(c.i.account), isNull);

        final all = await statement(w.familiar);
        expect(all.openingMinor, isNull);
        expect(
          [for (final l in all.lines) l.balanceMinor],
          [8100, 12100, 7100],
        );
        expect(statuses(all), [
          'Pendiente a hoy ${bs(3100)}',
          'Pendiente a hoy ${bs(4000)}',
          'Imputado: Verano 2026 ${bs(5000)}',
        ]);
        expect(
          entryCampaignText(all.ledger, all.account, all.lines.last.entry),
          registeredIn == 'Todas'
              ? 'registrado sin campaña'
              : 'registrado en Invierno 2026',
        );
        expect(closingLabel(all), 'Saldo a hoy');
        expect(
          [
            for (final d in all.debts)
              originDebtLine(all.ledger.campaignName(d.campaignId), d),
          ],
          [
            'Verano 2026: cargos ${bs(8100)} · pagos aplicados ${bs(5000)} · pendiente ${bs(3100)}',
            'Invierno 2026: cargos ${bs(4000)} · pagos aplicados ${bs(0)} · pendiente ${bs(4000)}',
          ],
        );

        final i = await statement(w.familiar, campaign: w.invierno);
        expect(
          openingLabel(i.period!),
          'Saldo al inicio del período (01/07/2026)',
        );
        expect(i.openingMinor, 8100);
        expect([for (final l in i.lines) l.balanceMinor], [12100, 7100]);
        expect(closingLabel(i), 'Saldo a hoy');
        expect(i.closingMinor, 7100);

        final v = await statement(w.familiar, campaign: w.verano);
        expect(v.openingMinor, 0);
        expect([for (final l in v.lines) l.balanceMinor], [8100]);
        expect(closingLabel(v), 'Saldo al cierre del período (30/06/2026)');
        expect(v.closingMinor, 8100);

        final dash = await w.repo.dashboard();
        expect(dash.familyReceivableMinor, 7100);
        expect(dash.familyCreditMinor, 0);
        expect(dash.receivedMinor, 5000);
        expect(
          (await w.repo.campaignCloseSummary(w.verano))['receivable_bob_minor'],
          3100,
        );
        expect(
          (await w.repo.campaignCloseSummary(
            w.invierno,
          ))['receivable_bob_minor'],
          4000,
        );
        await invariants();
      });
    }
  });

  test(
    'D04-02 · pago registrado en la campaña nueva cancela deuda antigua',
    () async {
      final c1 = await w.charge(w.familiar, w.verano, at(3, 15), 8100);
      final q1 = await w.pay(
        w.familiar,
        8100,
        campaign: w.invierno,
        date: at(10, 20),
      );
      expect(await w.allocationsOf(q1), {c1: 8100});
      final c = await cards(w.familiar);
      expect(c.all.account.netMinor, 0);
      expect(c.v.scope.pendingMinor, 0);
      expect(
        chargesLine(c.v.scope, campaignName: 'Verano 2026'),
        'Cargos de Verano 2026 ${bs(8100)} · pagos aplicados ${bs(8100)}',
      );
      expect(
        chargesLine(c.i.scope, campaignName: 'Invierno 2026'),
        'Sin cargos.',
      );
      expect(c.i.scope.pendingMinor, 0);
      final i = await statement(w.familiar, campaign: w.invierno);
      expect(i.openingMinor, 8100);
      expect(statuses(i), ['Imputado: Verano 2026 ${bs(8100)}']);
      expect(i.closingMinor, 0);
      final v = await statement(w.familiar, campaign: w.verano);
      expect(statuses(v), ['Pagado']);
      expect(v.closingMinor, 8100);
      expect(
        (await w.repo.campaignCloseSummary(w.verano))['receivable_bob_minor'],
        0,
      );
      expect(
        (await w.repo.campaignCloseSummary(w.invierno))['receivable_bob_minor'],
        0,
      );
      await invariants();
    },
  );

  test('D04-03 · un pago repartido entre dos campañas', () async {
    final c1 = await w.charge(w.familiar, w.verano, at(3, 15), 8100);
    final c2 = await w.charge(w.familiar, w.invierno, at(8, 10), 4000);
    final q1 = await w.pay(
      w.familiar,
      10000,
      campaign: w.invierno,
      date: at(10, 20),
    );
    expect(await w.allocationsOf(q1), {c1: 8100, c2: 1900});
    final c = await cards(w.familiar);
    expect(c.all.account.netMinor, 2100);
    expect(c.v.scope.pendingMinor, 0);
    expect(c.i.scope.pendingMinor, 2100);
    expect(
      chargesLine(c.i.scope, campaignName: 'Invierno 2026'),
      'Cargos de Invierno 2026 ${bs(4000)} · pagos aplicados ${bs(1900)}',
    );
    final i = await statement(w.familiar, campaign: w.invierno);
    expect(
      statuses(i).last,
      'Imputado: Verano 2026 ${bs(8100)} · Invierno 2026 ${bs(1900)}',
    );
    expect(
      (await w.repo.campaignCloseSummary(w.invierno))['receivable_bob_minor'],
      2100,
    );
    await invariants();
  });

  test('D04-04 · exceso de pago', () async {
    await w.charge(w.familiar, w.verano, at(3, 15), 8100);
    await w.pay(w.familiar, 10000, date: at(10, 20));
    final c = await cards(w.familiar);
    expect(
      pendingAndCreditLine(c.all.account),
      'Deuda pendiente ${bs(0)} · a favor (no aplicado a deuda) ${bs(1900)}',
    );
    expect(c.all.account.netMinor, -1900);
    expect(
      unattributedCreditLine(c.v.account),
      'A favor (no aplicado a deuda) ${bs(1900)} (sin campaña)',
    );
    expect(c.v.scope.pendingMinor, 0);
    expect(c.i.scope.pendingMinor, 0);
    expect(
      creditCompositionLine(c.all.account),
      'pagos sin imputar ${bs(1900)}',
    );
    final i = await statement(w.familiar, campaign: w.invierno);
    expect(i.openingMinor, 8100);
    expect(statuses(i), [
      'Imputado: Verano 2026 ${bs(8100)} · sin imputar ${bs(1900)} '
          '(queda a favor, sin campaña)',
    ]);
    expect(i.closingMinor, -1900);
    final dash = await w.repo.dashboard();
    expect(dash.familyReceivableMinor, 0);
    expect(dash.familyCreditMinor, 1900);
    expect(dash.receivedMinor, 10000);
    await invariants();
  });

  test('D04-05 · anticipo seguido de cargos (criterio Q-1: no se imputa)', () async {
    final q1 = await w.pay(
      w.tercero,
      30000,
      campaign: w.invierno,
      date: at(7, 5),
      advance: true,
    );
    expect(await w.allocationsOf(q1), isEmpty);
    final c1 = await w.charge(
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
    var c = await cards(w.tercero);
    expect(
      pendingAndCreditLine(c.all.account),
      'Deuda pendiente ${bs(37000)} · a favor (no aplicado a deuda) ${bs(30000)}',
    );
    expect(c.all.account.netMinor, 7000);
    expect(c.i.scope.pendingMinor, 37000);
    expect((await w.allocationsOf(q1)), isEmpty, reason: 'I-8');
    expect((await w.repo.dashboard()).thirdPartyReceivableMinor, 7000);
    expect(
      (await w.repo.campaignCloseSummary(w.invierno))['receivable_bob_minor'],
      37000,
    );
    final s = await statement(w.tercero, campaign: w.invierno);
    expect(statuses(s), [
      'Sin imputación registrada: ${bs(30000)} (queda a favor, sin campaña)',
      'Pendiente a hoy ${bs(25000)}',
      'Pendiente a hoy ${bs(12000)}',
    ]);
    // 5b
    final q2 = await w.pay(
      w.tercero,
      7000,
      campaign: w.invierno,
      date: at(10, 20),
    );
    expect(await w.allocationsOf(q2), {c1: 7000});
    c = await cards(w.tercero);
    expect(c.all.account.netMinor, 0);
    expect(c.all.account.pendingMinor, 30000);
    expect(c.all.account.creditMinor, 30000);
    expect(c.i.scope.pendingMinor, 30000);
    expect((await w.repo.dashboard()).thirdPartyReceivableMinor, 0);
    expect(
      (await w.repo.campaignCloseSummary(w.invierno))['receivable_bob_minor'],
      30000,
    );
    await invariants();
  });

  test('D04-06 · reversión de un cargo con pago imputado', () async {
    final c1 = await w.charge(w.familiar, w.verano, at(3, 15), 8100);
    await w.charge(w.familiar, w.invierno, at(8, 10), 4000);
    final q1 = await w.pay(w.familiar, 5000, date: at(10, 20));
    expect(await w.allocationsOf(q1), {c1: 5000});
    await w.reverse(c1, at(10, 25));
    final c = await cards(w.familiar);
    expect(
      chargesLine(c.all.scope),
      'Cargos ${bs(12100)} · revertidos ${bs(8100)} · pagos aplicados ${bs(0)}',
    );
    expect(
      pendingAndCreditLine(c.all.account),
      'Deuda pendiente ${bs(4000)} · a favor (no aplicado a deuda) ${bs(5000)}',
    );
    expect(c.all.account.netMinor, -1000);
    expect(c.v.scope.pendingMinor, 0);
    expect(c.i.scope.pendingMinor, 4000);
    expect(
      creditCompositionLine(c.all.account),
      'liberado por reversión ${bs(5000)}',
    );
    final all = await statement(w.familiar);
    expect(
      releasedLine('Verano 2026', all.debts.first),
      '${bs(5000)} imputados a cargos revertidos de Verano 2026 quedan a favor',
    );
    expect(statuses(all), [
      'Revertido el 25/10/2026',
      'Pendiente a hoy ${bs(4000)}',
      'Imputado a un cargo revertido (Verano 2026, 15/03/2026): ${bs(5000)}. '
          'Queda a favor.',
      'Revierte el cargo del 15/03/2026',
    ]);
    final i = await statement(w.familiar, campaign: w.invierno);
    expect(i.openingMinor, 8100);
    expect([for (final l in i.lines) l.balanceMinor], [12100, 7100, -1000]);
    final v = await statement(w.familiar, campaign: w.verano);
    expect(v.closingMinor, 8100);
    final dash = await w.repo.dashboard();
    expect(dash.familyReceivableMinor, 0);
    expect(dash.familyCreditMinor, 1000);
    expect(await w.allocationsOf(q1), {
      c1: 5000,
    }, reason: 'I-8: no se reimputa');
    await invariants();
  });

  group('D04-07 · cargo revertido antes del pago (D-15)', () {
    test('pago nuevo: no se imputa al cargo revertido (criterio Q-5)', () async {
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
      final c = await cards(w.familiar);
      expect(
        chargesLine(c.all.scope),
        'Cargos ${bs(12100)} · revertidos ${bs(8100)} · pagos aplicados ${bs(4000)}',
      );
      expect(c.all.account.pendingMinor, 0);
      expect(c.all.account.creditMinor, 1000);
      expect(c.all.account.netMinor, -1000);
      expect(c.i.scope.pendingMinor, 0);
      final i = await statement(w.familiar, campaign: w.invierno);
      expect([for (final l in i.lines) l.balanceMinor], [12100, 4000, -1000]);
      expect(
        statuses(i).last,
        'Imputado: Invierno 2026 ${bs(4000)} · sin imputar ${bs(1000)} '
        '(queda a favor, sin campaña)',
      );
      expect(
        (await w.repo.campaignCloseSummary(w.invierno))['receivable_bob_minor'],
        0,
      );
      await invariants();
    });

    test('histórico 07h: la imputación guardada se conserva y se muestra', () async {
      final c1 = await w.charge(w.familiar, w.verano, at(3, 15), 8100);
      await w.charge(w.familiar, w.invierno, at(8, 10), 4000);
      await w.reverse(c1, at(10, 18));
      final q1 = await w.rawPayment(
        w.familiar,
        5000,
        campaign: w.invierno,
        date: at(10, 20),
      );
      await w.rawAllocation(q1, c1, 5000);
      final c = await cards(w.familiar);
      expect(
        chargesLine(c.all.scope),
        'Cargos ${bs(12100)} · revertidos ${bs(8100)} · pagos aplicados ${bs(0)}',
      );
      expect(c.all.account.pendingMinor, 4000);
      expect(c.all.account.creditMinor, 5000);
      expect(c.all.account.netMinor, -1000);
      expect(c.i.scope.pendingMinor, 4000);
      final s = await statement(w.familiar);
      expect(
        statuses(s).last,
        'Imputado a un cargo revertido (Verano 2026, 15/03/2026): ${bs(5000)}. Queda a favor.',
      );
      expect(
        (await w.repo.campaignCloseSummary(w.invierno))['receivable_bob_minor'],
        4000,
      );
      await invariants();
    });
  });

  test('D04-08 · reversión de compra de un tercero con pago imputado', () async {
    final c1 = await w.charge(
      w.tercero,
      w.verano,
      at(3, 5),
      25000,
      type: 'PURCHASE_ALLOCATION_CHARGE',
    );
    final q1 = await w.pay(
      w.tercero,
      10000,
      campaign: w.verano,
      date: at(4, 10),
    );
    expect(await w.allocationsOf(q1), {c1: 10000});
    await w.reverse(c1, at(10, 22));
    final c = await cards(w.tercero);
    expect(
      chargesLine(c.all.scope),
      'Cargos ${bs(25000)} · revertidos ${bs(25000)} · pagos aplicados ${bs(0)}',
    );
    expect(c.all.account.creditMinor, 10000);
    expect(c.all.account.netMinor, -10000);
    expect(c.v.scope.pendingMinor, 0);
    final v = await statement(w.tercero, campaign: w.verano);
    expect([for (final l in v.lines) l.balanceMinor], [25000, 15000]);
    expect(v.closingMinor, 15000);
    final i = await statement(w.tercero, campaign: w.invierno);
    expect(i.openingMinor, 15000);
    expect(i.closingMinor, -10000);
    final dash = await w.repo.dashboard();
    expect(dash.thirdPartyReceivableMinor, 0);
    expect(dash.thirdPartyCreditMinor, 10000);
    await invariants();
  });

  test('D04-09b · pago histórico sin imputaciones: no se fabrica ninguna', () async {
    await w.charge(w.familiar, w.verano, at(3, 15), 8100);
    final q1 = await w.rawPayment(
      w.familiar,
      5000,
      campaign: w.verano,
      date: at(4, 1),
    );
    final c = await cards(w.familiar);
    expect(
      pendingAndCreditLine(c.all.account),
      'Deuda pendiente ${bs(8100)} · a favor (no aplicado a deuda) ${bs(5000)}',
    );
    expect(c.all.account.netMinor, 3100);
    expect(c.v.scope.pendingMinor, 8100);
    final v = await statement(w.familiar, campaign: w.verano);
    expect(
      statuses(v).last,
      'Sin imputación registrada: ${bs(5000)} (queda a favor, sin campaña)',
    );
    expect(
      entryCampaignText(v.ledger, v.account, v.lines.last.entry),
      'registrado en Verano 2026',
    );
    expect(v.closingMinor, 3100);
    expect((await w.repo.dashboard()).familyReceivableMinor, 3100);
    expect(
      (await w.repo.campaignCloseSummary(w.verano))['receivable_bob_minor'],
      8100,
    );
    expect(await w.allocationsOf(q1), isEmpty);
    await invariants();
  });

  test('09d · crédito sin cargo de origen', () async {
    await w.charge(w.familiar, w.verano, at(3, 15), 8100);
    final orphan = await (await w.db).insert('account_transactions', {
      'person_id': w.familiar,
      'campaign_id': w.verano,
      'transaction_date': at(4, 1),
      'type': 'CREDIT_ADJUSTMENT',
      'amount_bob_minor_signed': -2000,
    });
    final s = await statement(w.familiar);
    expect(s.account.classOf(s.lines.last.entry), LedgerEntryClass.credit);
    expect(orphan, isPositive);
    expect(
      statuses(s).last,
      'Crédito sin cargo de origen registrado: ${bs(2000)} (queda a favor, sin campaña)',
    );
    expect(s.account.creditMinor, 2000);
    await invariants();
  });

  test('§2.1 · una compensación futura de un crédito no es deuda', () async {
    final c1 = await w.charge(w.familiar, w.verano, at(3, 15), 8100);
    final q1 = await w.pay(w.familiar, 10000, date: at(4, 1));
    // Una hipotética reversión de pago: positiva y con `reversal_of_id`.
    await (await w.db).insert('account_transactions', {
      'person_id': w.familiar,
      'campaign_id': null,
      'transaction_date': at(4, 2),
      'type': 'PAYMENT_REVERSAL',
      'amount_bob_minor_signed': 10000,
      'reversal_of_id': q1,
    });
    final c = await cards(w.familiar);
    expect(
      c.all.account.pendingMinor,
      0,
      reason: 'la compensación no es cargo',
    );
    expect(c.all.account.compensationMinor, 10000);
    expect(c.all.account.netMinor, c.all.account.signedSumMinor);
    // Un pago nuevo no se imputa a la compensación.
    final q2 = await w.pay(w.familiar, 500, date: at(4, 3));
    expect(await w.allocationsOf(q2), isEmpty);
    expect(c1, isPositive);
    await invariants();
  });

  group('casos M', () {
    test('M-1 · pago exacto', () async {
      final c1 = await w.charge(w.familiar, w.invierno, at(8, 10), 4000);
      final q1 = await w.pay(
        w.familiar,
        4000,
        campaign: w.invierno,
        date: at(10, 21),
      );
      expect(await w.allocationsOf(q1), {c1: 4000});
      final c = await cards(w.familiar);
      expect(c.all.account.netMinor, 0);
      expect(c.i.scope.pendingMinor, 0);
      expect(statuses(await statement(w.familiar)), [
        'Pagado',
        'Imputado: Invierno 2026 ${bs(4000)}',
      ]);
      final dash = await w.repo.dashboard();
      expect(dash.familyReceivableMinor, 0);
      expect(dash.familyCreditMinor, 0);
      await invariants();
    });

    test('M-2 · varios pagos sobre el mismo cargo', () async {
      final c1 = await w.charge(w.familiar, w.verano, at(3, 15), 8100);
      final q1 = await w.pay(
        w.familiar,
        3000,
        campaign: w.invierno,
        date: at(9, 1),
      );
      final q2 = await w.pay(w.familiar, 3000, date: at(9, 15));
      final q3 = await w.pay(
        w.familiar,
        3000,
        campaign: w.invierno,
        date: at(10, 20),
      );
      expect(await w.allocationsOf(q1), {c1: 3000});
      expect(await w.allocationsOf(q2), {c1: 3000});
      expect(await w.allocationsOf(q3), {c1: 2100});
      final c = await cards(w.familiar);
      expect(
        pendingAndCreditLine(c.all.account),
        'Deuda pendiente ${bs(0)} · a favor (no aplicado a deuda) ${bs(900)}',
      );
      expect(c.all.account.netMinor, -900);
      expect(c.v.scope.pendingMinor, 0);
      expect(c.i.scope.pendingMinor, 0);
      expect(
        statuses(await statement(w.familiar)).last,
        'Imputado: Verano 2026 ${bs(2100)} · sin imputar ${bs(900)} (queda a favor, sin campaña)',
      );
      expect((await w.repo.dashboard()).familyCreditMinor, 900);
      await invariants();
    });

    test('M-2r · variante revertida: el pago posterior no se imputa', () async {
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
      final c = await cards(w.familiar);
      expect(
        chargesLine(c.all.scope),
        'Cargos ${bs(8100)} · revertidos ${bs(8100)} · pagos aplicados ${bs(0)}',
      );
      expect(c.all.account.creditMinor, 9000);
      expect(
        creditCompositionLine(c.all.account),
        'pagos sin imputar ${bs(3000)} · liberado por reversión ${bs(6000)}',
      );
      expect(c.all.account.netMinor, -9000);
      expect(
        statuses(await statement(w.familiar)).last,
        'Sin imputación registrada: ${bs(3000)} (queda a favor, sin campaña)',
      );
      await invariants();
    });

    test('M-3 · cargos del mismo día: día y luego id', () async {
      final c1 = await w.charge(w.familiar, w.invierno, at(8, 10, 18), 3000);
      final c2 = await w.charge(w.familiar, w.invierno, at(8, 10), 2000);
      final q1 = await w.pay(
        w.familiar,
        2500,
        campaign: w.invierno,
        date: at(10, 21),
      );
      expect(await w.allocationsOf(q1), {c1: 2500});
      expect(c2, greaterThan(c1));
      final s = await statement(w.familiar, campaign: w.invierno);
      expect([for (final l in s.lines) l.entry.id], [c1, c2, q1]);
      expect(statuses(s).take(2), [
        'Pendiente a hoy ${bs(500)}',
        'Pendiente a hoy ${bs(2000)}',
      ]);
      expect((await cards(w.familiar)).i.scope.pendingMinor, 2500);
      await invariants();
    });

    test('M-4 · cargo tardío en una campaña cerrada', () async {
      final c1 = await w.charge(w.familiar, w.verano, at(3, 15), 8100);
      await w.charge(w.familiar, w.invierno, at(8, 10), 4000);
      await w.pay(w.familiar, 5000, campaign: w.invierno, date: at(10, 20));
      var v = await statement(w.familiar, campaign: w.verano);
      expect(v.closingMinor, 8100);
      final c3 = await w.charge(w.familiar, w.verano, at(6, 20), 3000);
      final q2 = await w.pay(
        w.familiar,
        4000,
        campaign: w.invierno,
        date: at(10, 25),
      );
      expect(await w.allocationsOf(q2), {c1: 3100, c3: 900});
      final c = await cards(w.familiar);
      expect(c.v.scope.pendingMinor, 2100);
      expect(c.i.scope.pendingMinor, 4000);
      expect(c.all.account.netMinor, 6100);
      v = await statement(w.familiar, campaign: w.verano);
      expect(v.closingMinor, 11100, reason: 'el cierre cambia tras la tardía');
      expect(
        (await w.repo.campaignCloseSummary(w.verano))['receivable_bob_minor'],
        2100,
      );
      await invariants();
    });

    test(
      'M-4b · pago registrado con el filtro en la campaña cerrada',
      () async {
        final c1 = await w.charge(w.familiar, w.verano, at(3, 15), 8100);
        await w.charge(w.familiar, w.invierno, at(8, 10), 4000);
        final ledger = await w.repo.accountLedger();
        final now = DateTime(2026, 10, 27, 9);
        expect(
          registrationText(ledger.campaign(w.verano), now),
          'Se registra en: Verano 2026 (cerrada). En el estado cronológico '
          'aparecerá por su fecha, 27/10/2026',
        );
        expect(
          registrationText(ledger.campaign(w.invierno), now),
          'Se registra en: Invierno 2026',
        );
        expect(registrationText(null, now), 'Se registra sin campaña');
        final q1 = await w.pay(
          w.familiar,
          5000,
          campaign: w.verano,
          date: at(10, 27),
        );
        expect(await w.allocationsOf(q1), {c1: 5000});
        final c = await cards(w.familiar);
        expect(c.v.scope.pendingMinor, 3100);
        expect(c.i.scope.pendingMinor, 4000);
        expect(
          (await statement(w.familiar, campaign: w.verano)).closingMinor,
          8100,
        );
        final i = await statement(w.familiar, campaign: w.invierno);
        expect([for (final l in i.lines) l.balanceMinor], [12100, 7100]);
        expect(
          entryCampaignText(i.ledger, i.account, i.lines.last.entry),
          'registrado en Verano 2026',
        );
        await invariants();
      },
    );

    test('M-5 · adelanto sin cargos', () async {
      await w.pay(
        w.familiar,
        10000,
        campaign: w.invierno,
        date: at(7, 5),
        advance: true,
      );
      final c = await cards(w.familiar);
      expect(chargesLine(c.all.scope), 'Sin cargos.');
      expect(
        pendingAndCreditLine(c.all.account),
        'Deuda pendiente ${bs(0)} · a favor (no aplicado a deuda) ${bs(10000)}',
      );
      expect(c.all.account.netMinor, -10000);
      expect(
        chargesLine(c.i.scope, campaignName: 'Invierno 2026'),
        'Sin cargos.',
      );
      expect(c.i.scope.pendingMinor, 0);
      expect((await statement(w.familiar)).debts, isEmpty);
      final dash = await w.repo.dashboard();
      expect(dash.familyReceivableMinor, 0);
      expect(dash.familyCreditMinor, 10000);
      expect(
        (await w.repo.campaignCloseSummary(w.invierno))['receivable_bob_minor'],
        0,
      );
      await invariants();
    });

    test('M-6 · redondeo por lote: 5,06 y un centavo pendiente', () async {
      final repo = w.repo;
      final supplier = await repo.addSupplier(name: 'Proveedor');
      final product = await repo.addProduct(name: 'Fungicida');
      final farm = await repo.addFarm(
        ownerId: w.familiar,
        name: 'Chaco Familiar',
        areaM2: 10000,
      );
      for (final day in [1, 2]) {
        await repo.confirmPurchase(
          PurchaseDraft(
            supplierId: supplier,
            campaignId: w.invierno,
            purchaseDate: DateTime(2026, 7, day),
            items: [
              PurchaseItemDraft(
                productId: product,
                quantityBase: 250,
                currency: CurrencyCode.bob,
                originalUnitPriceMinor: 1010,
                allocations: [
                  AllocationDraft(personId: w.familiar, quantityBase: 250),
                ],
              ),
            ],
          ),
        );
      }
      final application = await repo.confirmApplication(
        ApplicationDraft(
          personId: w.familiar,
          farmId: farm,
          campaignId: w.invierno,
          appliedAt: DateTime(2026, 8, 10),
          lines: [ApplicationLineDraft(productId: product, quantityBase: 500)],
        ),
      );
      final charge = (await (await w.db).query(
        'account_transactions',
        where: "reference_type='APPLICATION' AND reference_id=?",
        whereArgs: [application],
      )).single;
      expect(charge['amount_bob_minor_signed'], 506);
      await w.pay(w.familiar, 505, campaign: w.invierno, date: at(10, 21));
      final c = await cards(w.familiar);
      expect(c.i.scope.pendingMinor, 1);
      expect(
        statuses(await statement(w.familiar)).first,
        'Pendiente a hoy ${bs(1)}',
      );
      expect(
        (await repo.productCostReport()).firstWhere(
          (r) => r['id'] == product,
        )['total_cost_bob_minor'],
        506,
      );
      await invariants();
    });

    test(
      'M-7 · tercero por asignación de compra con pago sin campaña',
      () async {
        final repo = w.repo;
        final supplier = await repo.addSupplier(name: 'Proveedor');
        final product = await repo.addProduct(name: 'Glifosato');
        final farm = await repo.addFarm(
          ownerId: w.tercero,
          name: 'Chaco Tercero',
          areaM2: 10000,
        );
        await repo.confirmPurchase(
          PurchaseDraft(
            supplierId: supplier,
            campaignId: w.invierno,
            purchaseDate: DateTime(2026, 7, 10),
            items: [
              PurchaseItemDraft(
                productId: product,
                quantityBase: 2000,
                currency: CurrencyCode.bob,
                originalUnitPriceMinor: 4500,
                allocations: [
                  AllocationDraft(personId: w.tercero, quantityBase: 2000),
                ],
              ),
            ],
          ),
        );
        await repo.confirmApplication(
          ApplicationDraft(
            personId: w.tercero,
            farmId: farm,
            campaignId: w.invierno,
            appliedAt: DateTime(2026, 8, 15),
            lines: [
              ApplicationLineDraft(productId: product, quantityBase: 1000),
            ],
          ),
        );
        await w.pay(w.tercero, 6000, date: at(10, 20));
        final c = await cards(w.tercero);
        expect(c.all.account.netMinor, 3000);
        expect(c.i.scope.pendingMinor, 3000);
        expect((await repo.dashboard()).thirdPartyReceivableMinor, 3000);
        expect(
          (await repo.farmCostReport()).firstWhere(
            (r) => r['id'] == farm,
          )['total_cost_bob_minor'],
          4500,
        );
        await invariants();
      },
    );

    test(
      'M-8 · exportación: cronológico y desglose con sus etiquetas, CSV',
      () async {
        await w.charge(w.familiar, w.verano, at(3, 15), 8100);
        await w.charge(w.familiar, w.invierno, at(8, 10), 4000);
        await w.pay(w.familiar, 5000, date: at(10, 20));
        final table = const ReportComposer().ledgerStatement(
          statement: await statement(w.familiar, campaign: w.invierno),
          generatedAt: DateTime(2026, 10, 27, 10),
        );
        expect(
          [for (final c in table.columns) c.header],
          [
            'Fecha',
            'Concepto',
            'Chaco',
            'Campaña del asiento',
            'Cargo (Bs)',
            'Crédito (Bs)',
            'Imputación',
            'Acumulado (Bs)',
          ],
        );
        expect(
          table.filters.last.value,
          'Invierno 2026 (período 01/07/2026 – hoy)',
        );
        expect(
          (table.rows.first[1] as ReportText).value,
          'Saldo al inicio del período (01/07/2026)',
        );
        expect((table.rows.first.last as ReportMoney).minor, 8100);
        expect(
          (table.rows[1][6] as ReportText).value,
          'Pendiente a hoy ${bs(4000)}',
        );
        expect(
          (table.rows[2][3] as ReportText).value,
          'registrado sin campaña',
        );
        expect(
          (table.rows[2][6] as ReportText).value,
          'Imputado: Verano 2026 ${bs(5000)}',
        );
        expect(
          {
            for (final t in table.totals)
              t.label: (t.cell as ReportMoney).minor,
          },
          {
            'Saldo al inicio del período (Bs)': 8100,
            'Total de cargos (Bs)': 4000,
            'Total de créditos (Bs)': 5000,
            'Saldo a hoy (Bs)': 7100,
            'Deuda pendiente por origen · Invierno 2026 (Bs)': 4000,
            'A favor (no aplicado a deuda) (Bs)': 0,
            'Saldo neto · todas las campañas (Bs)': 7100,
          },
        );
        final all = const ReportComposer().ledgerStatement(
          statement: await statement(w.familiar),
          generatedAt: DateTime(2026, 10, 27, 10),
        );
        expect(
          [for (final t in all.totals) t.label],
          [
            'Total de cargos (Bs)',
            'Total de créditos (Bs)',
            'Saldo a hoy (Bs)',
            'Deuda pendiente por origen · Verano 2026 (Bs)',
            'Deuda pendiente por origen · Invierno 2026 (Bs)',
            'Deuda pendiente total (Bs)',
            'A favor (no aplicado a deuda) (Bs)',
            'Saldo neto · todas las campañas (Bs)',
          ],
        );
        final csv = utf8.decode(const CsvReportGenerator().generate(table));
        expect(csv, contains('Saldo a hoy (Bs)'));
        expect(
          csv,
          contains('Deuda pendiente por origen · Invierno 2026 (Bs)'),
        );
        expect(csv, isNot(contains('Saldo final')));
      },
    );
  });

  test('el ADMIN no entra en la lista ni en el resumen (D-R6)', () async {
    await w.charge(w.admin, w.invierno, at(8, 10), 1000);
    expect(
      (await w.repo.accountSummaries()).map((r) => r.personId),
      isNot(contains(w.admin)),
    );
    expect(
      (await w.repo.campaignCloseSummary(w.invierno))['receivable_bob_minor'],
      0,
    );
  });

  test('textos del diálogo de pago según el saldo neto (§2.4)', () {
    expect(
      dialogNetText(12100),
      'Saldo neto · todas las campañas: debe ${bs(12100)}',
    );
    expect(
      dialogNetText(-1900),
      'Saldo neto · todas las campañas: a favor ${bs(1900)}',
    );
    expect(dialogNetText(0), 'Saldo neto · todas las campañas: al día');
  });
}
