// E-15 · Registro propio del titular (decisión del autor, Roderich Rendón, del
// 2026-10-27; docs/architecture/D04_E15_CUENTAS_IMPUTACION_Y_COSTO_PROPIO.md
// parte B y casos M-9 y M-10).
//
// Usa las lecturas de E-15 (`ownConsumption`, `ownAccount`, `topBalances`,
// `ownStatement`), que no existen en el HEAD de D-04: allí este archivo no
// compila. La prueba que falla por aserción sobre D-04 es
// `e15_consumo_propio_base_test.dart`.

import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/domain/account_ledger.dart';
import 'package:agroquimicos/domain/account_texts.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/domain/reports/report_composer.dart';
import 'package:agroquimicos/domain/reports/report_table.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/d04_world.dart';
import 'support/e15_world.dart';

void main() {
  sqfliteFfiInit();

  late E15World e;
  tearDown(() => e.close());

  Future<AccountLedger> ledger() => e.w.repo.accountLedger();

  /// El titular no está en la lista, ni en Inicio, ni en el resumen.
  Future<void> titularOutOfReceivables() async {
    final l = await ledger();
    expect(l.summaries().map((r) => r.personId), isNot(contains(e.titular)));
    expect(
      l.summaries(campaignId: e.w.invierno).map((r) => r.personId),
      isNot(contains(e.titular)),
    );
    final dash = await e.w.repo.dashboard();
    expect(dash.topBalances.map((r) => r.personId), isNot(contains(e.titular)));
    // I-5 sin lo propio.
    var family = 0;
    for (final row in l.summaries()) {
      if (row.role == 'FAMILY' && row.account.netMinor > 0) {
        family += row.account.netMinor;
      }
    }
    expect(dash.familyReceivableMinor, family);
  }

  test('E15-01 · titular con USAGE_CHARGE en compartido', () async {
    e = await E15World.create();
    await e.seedE1501();
    final l = await ledger();
    expect(l.ownerPersonId, e.titular);
    final consumption = l.ownConsumption(e.titular);
    expect(
      ownConsumptionLine(consumption),
      'Consumo aplicado (costo FIFO) · todas las campañas ${bs(8100)}',
    );
    expect(
      ownConsumptionLine(
        l.ownConsumption(e.titular, campaignId: e.w.invierno),
        campaignName: 'Invierno 2026',
      ),
      'Consumo aplicado (costo FIFO) · Invierno 2026 ${bs(8100)}',
    );
    expect(ownApplicationsLine(consumption), '1 aplicación vigente');
    expect(
      ownRecordsLine(l.ownAccount(e.titular)),
      'Asientos en su cuenta · todas las campañas (no son deuda): cargos anotados ${bs(8100)} · '
      'créditos por reversión ${bs(0)} · pagos y ajustes registrados ${bs(0)}',
    );
    final familiar = l.summaries().firstWhere(
      (r) => r.personId == e.w.familiar,
    );
    expect(familiar.account.netMinor, 2000);
    final dash = await e.w.repo.dashboard();
    expect(dash.familyReceivableMinor, 2000);
    expect(
      (await e.w.repo.campaignCloseSummary(
        e.w.invierno,
      ))['receivable_bob_minor'],
      2000,
    );
    expect(
      (await e.w.repo.farmCostReport()).firstWhere(
        (r) => r['id'] == e.chacoNorte,
      )['total_cost_bob_minor'],
      8100,
      reason: 'el costo por chaco no cambia',
    );
    final table = const ReportComposer().ownStatement(
      statement: await e.w.repo.accountStatement(e.titular),
      generatedAt: DateTime(2026, 10, 27, 10),
    );
    expect(table.title, 'Movimientos propios del titular');
    expect(
      [for (final c in table.columns) c.header],
      [
        'Fecha',
        'Concepto',
        'Chaco',
        'Campaña del asiento',
        'Cargo (Bs)',
        'Crédito (Bs)',
      ],
    );
    expect(
      {for (final t in table.totals) t.label: (t.cell as ReportMoney).minor},
      {
        'Consumo aplicado, costo FIFO (Bs)': 8100,
        'Cargos anotados (Bs)': 8100,
        'Créditos por reversión (Bs)': 0,
        'Pagos y ajustes registrados (Bs)': 0,
      },
    );
    await titularOutOfReceivables();
  });

  test('E15-02a · titular ADMIN (MANUAL): consumo sin asientos', () async {
    e = await E15World.create(titularRole: PersonRole.admin);
    await e.buy(e.titular, 'Glifosato', 1000, 4500);
    await e.buy(e.titular, 'Bellator', 200, 18000);
    await e.apply(e.titular, e.chacoNorte, DateTime(2026, 10, 20), {
      'Glifosato': 1000,
      'Bellator': 200,
    });
    final l = await ledger();
    expect(l.ownConsumption(e.titular).activeCostMinor, 8100);
    expect(
      ownApplicationsLine(l.ownConsumption(e.titular)),
      '1 aplicación vigente',
    );
    expect(
      ownRecordsLine(l.ownAccount(e.titular)),
      'Sin asientos en su cuenta · todas las campañas.',
    );
    expect((await e.w.repo.dashboard()).familyReceivableMinor, 0);
    await titularOutOfReceivables();
  });

  test('E15-02b · titular con BY_PURCHASE_ALLOCATION: costo FIFO 45, cargo '
      'por compra 90 anotado aparte', () async {
    e = await E15World.create(
      titularPolicy: SettlementPolicy.byPurchaseAllocation,
    );
    await e.buy(e.titular, 'Glifosato', 2000, 4500, date: DateTime(2026, 7, 5));
    await e.apply(e.titular, e.chacoNorte, DateTime(2026, 10, 20), {
      'Glifosato': 1000,
    });
    final l = await ledger();
    expect(l.ownConsumption(e.titular).activeCostMinor, 4500);
    expect(
      ownRecordsLine(l.ownAccount(e.titular)),
      'Asientos en su cuenta · todas las campañas (no son deuda): cargos anotados ${bs(9000)} · '
      'créditos por reversión ${bs(0)} · pagos y ajustes registrados ${bs(0)}',
    );
    expect((await e.w.repo.dashboard()).familyReceivableMinor, 0);
    await titularOutOfReceivables();
  });

  test('E15-03 · aplicación revertida: no cuenta en el consumo', () async {
    e = await E15World.create();
    await e.buy(e.titular, 'Glifosato', 2000, 4500);
    await e.buy(e.titular, 'Bellator', 200, 18000);
    final a1 = await e.apply(e.titular, e.chacoNorte, DateTime(2026, 10, 15), {
      'Glifosato': 1000,
      'Bellator': 200,
    });
    await e.w.repo.reverseApplicationUnauditedForTesting(a1);
    await e.apply(e.titular, e.chacoNorte, DateTime(2026, 10, 20), {
      'Glifosato': 1000,
    });
    final l = await ledger();
    final consumption = l.ownConsumption(e.titular);
    expect(consumption.activeCostMinor, 4500);
    expect(
      ownApplicationsLine(consumption),
      '1 aplicación vigente · 1 revertida (${bs(8100)}, no cuenta)',
    );
    expect(
      ownRecordsLine(l.ownAccount(e.titular)),
      'Asientos en su cuenta · todas las campañas (no son deuda): cargos anotados ${bs(12600)} · '
      'créditos por reversión ${bs(8100)} · pagos y ajustes registrados ${bs(0)}',
    );
    // En «Movimientos propios» el cargo revertido sólo dice «Revertido el …»
    // y el vigente no dice «Pendiente» ni «Pagado».
    final s = await e.w.repo.accountStatement(e.titular);
    final statuses = [
      for (final entry in s.ownLines)
        if (s.ownAccount.classOf(entry) == LedgerEntryClass.charge)
          statusText(s.ledger, s.ownAccount, entry, ownRecord: true),
    ];
    expect(statuses.first, startsWith('Revertido el '));
    expect(statuses.last, '');
    await titularOutOfReceivables();
  });

  test('E15-04 · pago propio en Invierno: no es «Pagos recibidos» y no '
      'reduce el consumo', () async {
    e = await E15World.create();
    await e.buy(e.titular, 'Glifosato', 1000, 4500);
    await e.buy(e.titular, 'Bellator', 200, 18000);
    await e.apply(e.titular, e.chacoNorte, DateTime(2026, 10, 20), {
      'Glifosato': 1000,
      'Bellator': 200,
    });
    final payment = await e.w.repo.registerAccountPayment(
      personId: e.titular,
      campaignId: e.w.invierno,
      amountBobMinor: 8100,
      date: DateTime.parse(at(10, 21)),
    );
    expect(payment.imputed.single.amountMinor, 8100);
    final l = await ledger();
    expect(l.ownConsumption(e.titular).activeCostMinor, 8100);
    expect(
      ownRecordsLine(l.ownAccount(e.titular)),
      'Asientos en su cuenta · todas las campañas (no son deuda): cargos anotados ${bs(8100)} · '
      'créditos por reversión ${bs(0)} · pagos y ajustes registrados ${bs(8100)}',
    );
    expect((await e.w.repo.dashboard()).receivedMinor, 0);
    final s = await e.w.repo.accountStatement(e.titular);
    final paymentEntry = s.ownLines.last;
    expect(
      entryCampaignText(s.ledger, s.ownAccount, paymentEntry),
      'registrado en Invierno 2026',
    );
    expect(
      statusText(s.ledger, s.ownAccount, paymentEntry, ownRecord: true),
      'Imputado: Invierno 2026 ${bs(8100)}',
    );
    await titularOutOfReceivables();
  });

  test('E15-05 · modo propio: Familias por cobrar 0', () async {
    e = await E15World.create();
    await OperationModeStore(e.w.database)
        .apply(OperationMode.personal, confirmed: true);
    await e.buy(e.titular, 'Glifosato', 1000, 4500);
    await e.buy(e.titular, 'Bellator', 200, 18000);
    await e.apply(e.titular, e.chacoNorte, DateTime(2026, 10, 20), {
      'Glifosato': 1000,
      'Bellator': 200,
    });
    final l = await ledger();
    expect(l.ownConsumption(e.titular).activeCostMinor, 8100);
    expect((await e.w.repo.dashboard()).familyReceivableMinor, 0);
    expect(
      l
          .summaries()
          .firstWhere((r) => r.personId == e.w.familiar)
          .account
          .netMinor,
      0,
    );
    await titularOutOfReceivables();
  });

  test('E15-06 · cambio de titular por intervalos (criterio Q-3)', () async {
    e = await E15World.create();
    final p2 = e.w.familiar;
    await e.buy(e.titular, 'Glifosato', 1000, 4500);
    await e.buy(e.titular, 'Bellator', 200, 18000);
    await e.buy(p2, 'Cipermetrina', 250, 8000);
    await e.apply(p2, e.chacoFamiliar, DateTime(2026, 8, 5), {
      'Cipermetrina': 250,
    });
    await e.apply(e.titular, e.chacoNorte, DateTime(2026, 8, 10), {
      'Glifosato': 1000,
      'Bellator': 200,
    });
    await e.changeOwner(p2, DateTime.now().toUtc().toIso8601String());
    final l = await ledger();
    expect(l.ownerPersonId, p2);
    final rows = l.summaries();
    expect(rows.firstWhere((r) => r.personId == e.titular).account.netMinor, 0);
    // Criterio de clase (revisión cruzada 2): el titular vigente no figura
    // como deudor ni con lo anterior a su vínculo.
    expect(rows.map((r) => r.personId), isNot(contains(p2)));
    expect(l.ownConsumption(e.titular).activeCostMinor, 8100);
    expect(
      formerOwnerLine(l.ownConsumption(e.titular)),
      'Consumo propio mientras fue titular ${bs(8100)}',
    );
    expect(ownApplicationsLine(l.ownConsumption(p2)), '1 aplicación vigente');
    expect(l.ownConsumption(p2).activeCostMinor, 2000);
    expect(
      ownRecordsLine(l.ownAccount(p2)),
      'Asientos en su cuenta · todas las campañas (no son deuda): cargos '
      'anotados ${bs(2000)} · créditos por reversión ${bs(0)} · pagos y '
      'ajustes registrados ${bs(0)}',
    );
    expect((await e.w.repo.dashboard()).familyReceivableMinor, 0);
    final former = await e.w.repo.accountStatement(e.titular);
    expect(former.isCurrentOwner, isFalse);
    expect(former.hasOwnRecords, isTrue);
  });

  test(
    'M-9 · FIFO de varios lotes: 83,00 y, revertida, sin vigentes',
    () async {
      e = await E15World.create();
      await e.buy(e.titular, 'Glifosato', 1000, 4500);
      await e.buy(
        e.titular,
        'Glifosato',
        1000,
        3800,
        date: DateTime(2026, 7, 5),
      );
      final a = await e.apply(e.titular, e.chacoNorte, DateTime(2026, 10, 20), {
        'Glifosato': 2000,
      });
      var consumption = (await ledger()).ownConsumption(e.titular);
      expect(consumption.activeCostMinor, 8300);
      expect(ownApplicationsLine(consumption), '1 aplicación vigente');
      await e.w.repo.reverseApplicationUnauditedForTesting(a);
      consumption = (await ledger()).ownConsumption(e.titular);
      expect(consumption.activeCostMinor, 0);
      expect(
        ownApplicationsLine(consumption),
        'Sin aplicaciones vigentes · 1 revertida (${bs(8300)}, no cuenta)',
      );
      await titularOutOfReceivables();
    },
  );

  test('M-10 · lo transferido no es consumo propio', () async {
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
    final l = await ledger();
    expect(l.ownConsumption(e.titular).activeCostMinor, 4500);
    expect(
      l
          .summaries()
          .firstWhere((r) => r.personId == e.w.familiar)
          .account
          .netMinor,
      4500,
    );
    expect((await e.w.repo.dashboard()).familyReceivableMinor, 4500);
    await titularOutOfReceivables();
  });

  test('sin titular vinculado todo sigue como en D-04', () async {
    e = await E15World.create(bind: false);
    await e.seedE1501();
    final l = await ledger();
    expect(l.ownerPersonId, isNull);
    expect(
      l.summaries().firstWhere((r) => r.personId == e.titular).account.netMinor,
      8100,
    );
    expect((await e.w.repo.dashboard()).familyReceivableMinor, 10100);
  });

  group('revisión cruzada 2 · criterio de clase y A1', () {
    /// P1 (titular desde la activación) aplica 81 el 10/08 (cargo propio) y
    /// después `changeOwner` a P2 (el familiar).
    Future<int> changedOwner({int stock = 1000}) async {
      e = await E15World.create();
      await e.buy(e.titular, 'Glifosato', stock, 4500);
      await e.buy(e.titular, 'Bellator', 200, 18000);
      final application = await e.apply(
        e.titular,
        e.chacoNorte,
        DateTime(2026, 8, 10),
        {'Glifosato': 1000, 'Bellator': 200},
      );
      await e.changeOwner(
        e.w.familiar,
        DateTime.now().toUtc().toIso8601String(),
      );
      return (await (await e.w.db).query(
            'account_transactions',
            where: "reference_type='APPLICATION' AND reference_id=?",
            whereArgs: [application],
          )).single['id']!
          as int;
    }

    test('A1 · pago de P1 tras el cambio: no se imputa a su cargo propio; '
        'queda a favor y cumple I-2', () async {
      final own = await changedOwner();
      final payment = await e.w.repo.registerAccountPayment(
        personId: e.titular,
        amountBobMinor: 8100,
      );
      expect(payment.imputed, isEmpty);
      expect(payment.unappliedMinor, 8100);
      expect(await e.w.allocationsOf(payment.paymentId), isEmpty);
      final l = await ledger();
      final p1 = l.account(e.titular);
      expect(p1.netMinor, -8100);
      expect(p1.netMinor, p1.signedSumMinor, reason: 'I-2');
      expect(l.ownAccount(e.titular).charges.containsKey(own), isTrue);
      final dash = await e.w.repo.dashboard();
      expect(dash.familyReceivableMinor, 0);
      expect(dash.familyCreditMinor, 8100);
    });

    test('A1 · pago de P1 con fecha de su intervalo: es propio, se imputa a su '
        'cargo propio y P1 queda con N = 0', () async {
      final own = await changedOwner();
      final payment = await e.w.repo.registerAccountPayment(
        personId: e.titular,
        amountBobMinor: 8100,
        date: DateTime(2026, 9, 1),
      );
      expect(await e.w.allocationsOf(payment.paymentId), {own: 8100});
      final l = await ledger();
      expect(l.account(e.titular).netMinor, 0);
      expect(l.account(e.titular).entries, isEmpty);
      expect((await e.w.repo.dashboard()).familyReceivableMinor, 0);
    });

    test(
      'A1 inverso · un pago propio no cancela un cargo por cobrar',
      () async {
        final own = await changedOwner(stock: 2000);
        // P1 aplica hoy, ya no titular: cargo por cobrar de 45.
        final application = await e.apply(
          e.titular,
          e.chacoNorte,
          DateTime.now(),
          {'Glifosato': 1000},
        );
        final receivable =
            (await (await e.w.db).query(
                  'account_transactions',
                  where: "reference_type='APPLICATION' AND reference_id=?",
                  whereArgs: [application],
                )).single['id']!
                as int;
        final payment = await e.w.repo.registerAccountPayment(
          personId: e.titular,
          amountBobMinor: 4500,
          date: DateTime(2026, 9, 1),
        );
        expect(await e.w.allocationsOf(payment.paymentId), {own: 4500});
        final l = await ledger();
        expect(l.account(e.titular).charges.containsKey(receivable), isTrue);
        expect(l.account(e.titular).netMinor, 4500);
        expect((await e.w.repo.dashboard()).familyReceivableMinor, 4500);
      },
    );

    test('A1 · imputación cruzada histórica: no cuenta como aplicada y se '
        'rotula', () async {
      final own = await changedOwner();
      final q = await e.w.rawPayment(
        e.titular,
        8100,
        date: DateTime.now().toUtc().toIso8601String(),
      );
      await e.w.rawAllocation(q, own, 8100);
      final s = await e.w.repo.accountStatement(e.titular);
      final entry = s.lines.single.entry;
      expect(
        statusText(s.ledger, s.account, entry),
        'Imputado a un cargo propio de cuando era titular: ${bs(8100)}. '
        'Queda a favor.',
      );
      expect(s.account.netMinor, -8100);
      expect(s.account.netMinor, s.account.signedSumMinor, reason: 'I-2');
      expect(s.ledger.ownAccount(e.titular).charges[own]!.appliedMinor, 0);
    });

    test('borde del día del cambio: lo del día del cambio ya no es del '
        'titular anterior', () async {
      e = await E15World.create();
      final before = await e.w.charge(
        e.titular,
        e.w.invierno,
        at(10, 21),
        1000,
      );
      final sameDay = await e.w.charge(
        e.titular,
        e.w.invierno,
        at(10, 22, 9),
        2000,
      );
      final newOwner = await e.w.charge(
        e.w.familiar,
        e.w.invierno,
        at(10, 22, 9),
        3000,
      );
      await e.changeOwner(e.w.familiar, at(10, 22, 14));
      final l = await ledger();
      final ownP1 = {for (final x in l.ownAccount(e.titular).entries) x.id};
      final receivableP1 = {for (final x in l.account(e.titular).entries) x.id};
      expect(ownP1, contains(before));
      expect(receivableP1, contains(sameDay));
      expect({
        for (final x in l.ownAccount(e.w.familiar).entries) x.id,
      }, contains(newOwner));
      expect(l.account(e.titular).netMinor, 2000);
    });

    test('primer vínculo posterior a los datos: lo anterior es del primer '
        'titular aunque ya no sea el vigente', () async {
      e = await E15World.create(bind: false);
      final earlier = await e.w.charge(
        e.titular,
        e.w.invierno,
        at(10, 20),
        1000,
      );
      await e.bindOwner(e.titular, at(10, 27));
      await e.changeOwner(e.w.familiar, at(10, 27, 12));
      final l = await ledger();
      expect(l.ownerPersonId, e.w.familiar);
      expect({
        for (final x in l.ownAccount(e.titular).entries) x.id,
      }, contains(earlier));
      expect(l.account(e.titular).netMinor, 0);
    });
  });
}
