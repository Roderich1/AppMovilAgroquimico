/// Libro de cuentas por persona: deuda pendiente por cargo, pagos aplicados
/// desde las imputaciones guardadas y crédito no aplicado a deuda.
///
/// D-04, decisión del autor (Roderich Rendón) del 2026-10-27, desarrollada en
/// `docs/architecture/D04_E15_CUENTAS_IMPUTACION_Y_COSTO_PROPIO.md` §2.
///
/// Todo es Dart puro sobre las filas que el repositorio lee en **una**
/// consulta. Nada de aquí escribe: las imputaciones guardadas se leen tal como
/// están y nunca se fabrica ninguna (I-8).
library;

import 'campaign_calendar.dart';

/// Clase de un asiento (§2.1). Sale de su signo y de `reversal_of_id`, no de
/// una lista cerrada de tipos: un tipo futuro cae en una de las cuatro.
enum LedgerEntryClass {
  /// Importe > 0 y sin `reversal_of_id`.
  charge,

  /// Importe < 0 y `reversal_of_id` apunta a un cargo.
  chargeReversal,

  /// Importe < 0 que no revierte un cargo: pagos, adelantos y créditos sin
  /// cargo de origen.
  credit,

  /// Importe > 0 con `reversal_of_id`: compensa un crédito. No existe hoy.
  creditCompensation,
}

/// Fila de `account_transactions`.
final class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.personId,
    required this.campaignId,
    required this.transactionDate,
    required this.type,
    required this.amountMinor,
    this.reversalOfId,
    this.concept,
    this.farmName,
    this.notes,
  });

  final int id;
  final int personId;
  final int? campaignId;
  final String transactionDate;
  final String type;
  final int amountMinor;
  final int? reversalOfId;
  final String? concept;
  final String? farmName;
  final String? notes;

  /// Día local efectivo (F04 §2.3).
  String get day => storedLocalDay(transactionDate);
}

/// Fila de `payment_allocations`.
final class LedgerAllocation {
  const LedgerAllocation({
    required this.paymentId,
    required this.chargeId,
    required this.amountMinor,
  });
  final int paymentId;
  final int chargeId;
  final int amountMinor;
}

final class LedgerPerson {
  const LedgerPerson({
    required this.id,
    required this.name,
    required this.role,
  });
  final int id;
  final String name;
  final String role;
}

/// Orden de todo el libro: día local y, dentro del día, `id`.
int compareByDayThenId(LedgerEntry a, LedgerEntry b) {
  final byDay = a.day.compareTo(b.day);
  return byDay != 0 ? byDay : a.id.compareTo(b.id);
}

/// Estado de un cargo a hoy.
final class ChargeState {
  ChargeState(this.entry);

  final LedgerEntry entry;
  int reversedMinor = 0;
  String? reversalDay;
  int allocatedMinor = 0;

  int get netMinor => entry.amountMinor - reversedMinor;
  bool get isReversed => reversedMinor > 0;

  /// La parte de lo imputado que cancela deuda real.
  int get appliedMinor {
    final net = netMinor < 0 ? 0 : netMinor;
    return allocatedMinor < net ? allocatedMinor : net;
  }

  /// Lo imputado a un cargo que quedó revertido: queda a favor.
  int get releasedMinor => allocatedMinor - appliedMinor;

  int get pendingMinor => netMinor - appliedMinor;
}

final class CreditAllocation {
  const CreditAllocation(this.charge, this.amountMinor);
  final ChargeState charge;
  final int amountMinor;
}

/// Estado de un crédito (pago, adelanto o crédito sin cargo de origen).
final class CreditState {
  CreditState(this.entry);

  final LedgerEntry entry;

  /// En orden FIFO del cargo (día y luego `id`).
  final List<CreditAllocation> allocations = [];

  int get allocatedMinor =>
      allocations.fold(0, (sum, allocation) => sum + allocation.amountMinor);

  int get unappliedMinor => -entry.amountMinor - allocatedMinor;
}

/// Desglose de una campaña de origen (o el total, con `campaignId` nulo).
final class CampaignDebt {
  CampaignDebt(this.campaignId);

  final int? campaignId;
  int chargesMinor = 0;
  int reversedMinor = 0;
  int appliedMinor = 0;
  int releasedMinor = 0;
  int pendingMinor = 0;

  bool get hasCharges => chargesMinor != 0;

  void add(ChargeState charge) {
    chargesMinor += charge.entry.amountMinor;
    reversedMinor += charge.reversedMinor;
    appliedMinor += charge.appliedMinor;
    releasedMinor += charge.releasedMinor;
    pendingMinor += charge.pendingMinor;
  }
}

/// Cuenta de una persona.
final class PersonAccount {
  PersonAccount(this.person);

  final LedgerPerson person;

  /// Ordenados por día local y luego `id`.
  final List<LedgerEntry> entries = [];
  final Map<int, LedgerEntryClass> classes = {};
  final Map<int, ChargeState> charges = {};
  final Map<int, CreditState> credits = {};
  final Map<int?, CampaignDebt> _byCampaign = {};
  final CampaignDebt total = CampaignDebt(null);

  /// Σ de lo no imputado de los créditos (*u*).
  int unappliedMinor = 0;

  /// Σ de las compensaciones de créditos (*X*).
  int compensationMinor = 0;

  int get pendingMinor => total.pendingMinor;
  int get releasedMinor => total.releasedMinor;

  /// A favor, no aplicado a deuda: *F* = *u* + *L* − *X*.
  int get creditMinor => unappliedMinor + releasedMinor - compensationMinor;

  /// Saldo neto *N* = *P* − *F*; igual a la suma con signo de sus asientos.
  int get netMinor => pendingMinor - creditMinor;

  int get signedSumMinor =>
      entries.fold(0, (sum, entry) => sum + entry.amountMinor);

  /// Desglose de la campaña de origen [campaignId], o el total si es nulo.
  CampaignDebt debtFor(int? campaignId) => campaignId == null
      ? total
      : _byCampaign[campaignId] ?? CampaignDebt(campaignId);

  /// Campañas de origen con cargos, en el orden de [campaignOrder].
  List<CampaignDebt> debtsByCampaign(List<int> campaignOrder) => [
    for (final id in campaignOrder)
      if (_byCampaign[id]?.hasCharges ?? false) _byCampaign[id]!,
    // Un cargo con campaña desconocida no desaparece del desglose.
    for (final entry in _byCampaign.entries)
      if (entry.value.hasCharges && !campaignOrder.contains(entry.key))
        entry.value,
  ];

  LedgerEntryClass classOf(LedgerEntry entry) => classes[entry.id]!;
}

/// Libro de todas las personas leídas.
final class AccountLedger {
  AccountLedger._(this.persons, this.campaigns, this.accounts);

  final List<LedgerPerson> persons;

  /// Por inicio y luego `id`.
  final List<CampaignPeriod> campaigns;
  final Map<int, PersonAccount> accounts;

  factory AccountLedger.build({
    required List<LedgerPerson> persons,
    required List<CampaignPeriod> campaigns,
    required List<LedgerEntry> entries,
    required List<LedgerAllocation> allocations,
  }) {
    final sortedCampaigns = [...campaigns]
      ..sort((a, b) {
        final byStart = a.startDay.compareTo(b.startDay);
        return byStart != 0 ? byStart : a.id.compareTo(b.id);
      });
    final accounts = <int, PersonAccount>{
      for (final person in persons) person.id: PersonAccount(person),
    };
    final sorted = [...entries]..sort(compareByDayThenId);
    final byId = {for (final entry in sorted) entry.id: entry};
    bool isCharge(LedgerEntry e) => e.amountMinor > 0 && e.reversalOfId == null;
    for (final entry in sorted) {
      final account = accounts.putIfAbsent(
        entry.personId,
        () =>
            PersonAccount(LedgerPerson(id: entry.personId, name: '', role: '')),
      );
      account.entries.add(entry);
      final LedgerEntryClass cls;
      if (isCharge(entry)) {
        cls = LedgerEntryClass.charge;
        account.charges[entry.id] = ChargeState(entry);
      } else if (entry.amountMinor < 0) {
        final target = entry.reversalOfId == null
            ? null
            : byId[entry.reversalOfId];
        cls = target != null && isCharge(target)
            ? LedgerEntryClass.chargeReversal
            : LedgerEntryClass.credit;
        if (cls == LedgerEntryClass.credit) {
          account.credits[entry.id] = CreditState(entry);
        }
      } else if (entry.amountMinor > 0) {
        cls = LedgerEntryClass.creditCompensation;
        account.compensationMinor += entry.amountMinor;
      } else {
        // Importe cero: no mueve ninguna cifra; se trata como crédito vacío.
        cls = LedgerEntryClass.credit;
        account.credits[entry.id] = CreditState(entry);
      }
      account.classes[entry.id] = cls;
    }
    // Reversiones: se aplican a su cargo (de la misma persona).
    for (final account in accounts.values) {
      for (final entry in account.entries) {
        if (account.classes[entry.id] != LedgerEntryClass.chargeReversal) {
          continue;
        }
        final charge = accounts[byId[entry.reversalOfId]!.personId]
            ?.charges[entry.reversalOfId];
        if (charge == null) continue;
        charge.reversedMinor += -entry.amountMinor;
        final day = entry.day;
        if (charge.reversalDay == null ||
            day.compareTo(charge.reversalDay!) > 0) {
          charge.reversalDay = day;
        }
      }
    }
    // Imputaciones guardadas: sólo de un crédito a un cargo.
    final chargesById = {
      for (final account in accounts.values) ...account.charges,
    };
    final creditsById = {
      for (final account in accounts.values) ...account.credits,
    };
    for (final allocation in allocations) {
      final charge = chargesById[allocation.chargeId];
      final credit = creditsById[allocation.paymentId];
      if (charge == null || credit == null) continue;
      charge.allocatedMinor += allocation.amountMinor;
      credit.allocations.add(CreditAllocation(charge, allocation.amountMinor));
    }
    for (final credit in creditsById.values) {
      credit.allocations.sort(
        (a, b) => compareByDayThenId(a.charge.entry, b.charge.entry),
      );
    }
    for (final account in accounts.values) {
      for (final charge in account.charges.values) {
        account.total.add(charge);
        account._byCampaign
            .putIfAbsent(
              charge.entry.campaignId,
              () => CampaignDebt(charge.entry.campaignId),
            )
            .add(charge);
      }
      for (final credit in account.credits.values) {
        account.unappliedMinor += credit.unappliedMinor;
      }
    }
    return AccountLedger._(persons, sortedCampaigns, accounts);
  }

  /// Lee el resultado de la consulta única del repositorio
  /// (`AgroRepository.accountLedger`). Cada fila lleva `kind`:
  /// K campaña, P persona, T asiento, L imputación.
  factory AccountLedger.fromRows(List<Map<String, Object?>> rows) {
    final persons = <LedgerPerson>[];
    final campaigns = <CampaignPeriod>[];
    final entries = <LedgerEntry>[];
    final allocations = <LedgerAllocation>[];
    for (final row in rows) {
      switch (row['kind']) {
        case 'K':
          final end = row['d2'] as String?;
          campaigns.add(
            CampaignPeriod(
              id: row['id']! as int,
              name: row['name']! as String,
              status: row['code']! as String,
              startDay: storedLocalDay(row['d1']! as String),
              endDay: end == null ? null : storedLocalDay(end),
            ),
          );
        case 'P':
          persons.add(
            LedgerPerson(
              id: row['id']! as int,
              name: row['name']! as String,
              role: row['code']! as String,
            ),
          );
        case 'T':
          entries.add(
            LedgerEntry(
              id: row['id']! as int,
              personId: row['person_id']! as int,
              campaignId: row['ref1'] as int?,
              transactionDate: row['d1']! as String,
              type: row['code']! as String,
              amountMinor: row['amount']! as int,
              reversalOfId: row['ref2'] as int?,
              concept: row['concept'] as String?,
              farmName: row['farm_name'] as String?,
              notes: row['notes'] as String?,
            ),
          );
        case 'L':
          allocations.add(
            LedgerAllocation(
              paymentId: row['ref1']! as int,
              chargeId: row['ref2']! as int,
              amountMinor: row['amount']! as int,
            ),
          );
      }
    }
    return AccountLedger.build(
      persons: persons,
      campaigns: campaigns,
      entries: entries,
      allocations: allocations,
    );
  }

  List<int> get campaignOrder => [for (final c in campaigns) c.id];

  CampaignPeriod? campaign(int? id) {
    if (id == null) return null;
    for (final campaign in campaigns) {
      if (campaign.id == id) return campaign;
    }
    return null;
  }

  String campaignName(int? id) => campaign(id)?.name ?? 'Campaña #$id';

  PersonAccount account(int personId) =>
      accounts[personId] ??
      PersonAccount(
        persons.firstWhere(
          (p) => p.id == personId,
          orElse: () => LedgerPerson(id: personId, name: '', role: ''),
        ),
      );

  /// Filas de la lista de Cuentas (§2.3): personas no ADMIN, con el alcance
  /// de [campaignId] (nulo = todas las campañas).
  List<AccountSummary> summaries({int? campaignId}) {
    final rows = [
      for (final person in persons)
        if (person.role != 'ADMIN')
          AccountSummary(account: account(person.id), campaignId: campaignId),
    ];
    rows.sort((a, b) {
      final byAmount = campaignId == null
          ? b.account.netMinor.compareTo(a.account.netMinor)
          : b.scope.pendingMinor.compareTo(a.scope.pendingMinor);
      return byAmount != 0
          ? byAmount
          : a.account.person.name.compareTo(b.account.person.name);
    });
    return rows;
  }

  /// Σ de la deuda pendiente por origen de [campaignId], sin ADMIN (D-R6).
  int pendingForCampaign(int campaignId) => [
    for (final person in persons)
      if (person.role != 'ADMIN') account(person.id).debtFor(campaignId),
  ].fold(0, (sum, debt) => sum + debt.pendingMinor);

  /// Cifras de Inicio por rol privado (§2.7).
  ({int receivableMinor, int creditMinor}) receivableByRole(String role) {
    var receivable = 0;
    var credit = 0;
    for (final person in persons) {
      if (person.role != role) continue;
      final net = account(person.id).netMinor;
      if (net > 0) receivable += net;
      if (net < 0) credit += -net;
    }
    return (receivableMinor: receivable, creditMinor: credit);
  }

  /// «Pagos recibidos»: Σ de pagos y adelantos.
  int receivedMinor() {
    var total = 0;
    for (final account in accounts.values) {
      for (final credit in account.credits.values) {
        if (credit.entry.type == 'PAYMENT' || credit.entry.type == 'ADVANCE') {
          total += -credit.entry.amountMinor;
        }
      }
    }
    return total;
  }

  /// Estado de cuenta de [personId]: desglose por origen y cronológico del
  /// período de [campaignId] (o de todas las campañas).
  AccountStatement statement(int personId, {int? campaignId}) {
    final account = this.account(personId);
    final period = campaign(campaignId);
    int? opening;
    final inScope = <LedgerEntry>[];
    if (period == null) {
      inScope.addAll(account.entries);
    } else {
      opening = 0;
      for (final entry in account.entries) {
        final day = entry.day;
        if (day.compareTo(period.startDay) < 0) {
          opening = opening! + entry.amountMinor;
        } else if (period.contains(day)) {
          inScope.add(entry);
        }
      }
    }
    var balance = opening ?? 0;
    final lines = <LedgerStatementLine>[];
    for (final entry in inScope) {
      balance += entry.amountMinor;
      lines.add(LedgerStatementLine(entry: entry, balanceMinor: balance));
    }
    return AccountStatement(
      ledger: this,
      account: account,
      period: period,
      openingMinor: opening,
      lines: lines,
      closingMinor: balance,
    );
  }
}

/// Fila de la lista de Cuentas.
final class AccountSummary {
  AccountSummary({required this.account, required this.campaignId});

  final PersonAccount account;
  final int? campaignId;

  CampaignDebt get scope => account.debtFor(campaignId);
  int get personId => account.person.id;
  String get name => account.person.name;
  String get role => account.person.role;
}

/// Movimiento del cronológico con su acumulado.
final class LedgerStatementLine {
  const LedgerStatementLine({required this.entry, required this.balanceMinor});
  final LedgerEntry entry;
  final int balanceMinor;
}

/// Estado de cuenta de una persona (§2.5).
final class AccountStatement {
  const AccountStatement({
    required this.ledger,
    required this.account,
    required this.period,
    required this.openingMinor,
    required this.lines,
    required this.closingMinor,
  });

  final AccountLedger ledger;
  final PersonAccount account;

  /// Campaña filtrada, o nula con «Todas las campañas».
  final CampaignPeriod? period;

  /// Saldo al inicio del período; nulo con «Todas las campañas».
  final int? openingMinor;
  final List<LedgerStatementLine> lines;
  final int closingMinor;

  /// El cierre es «Saldo al cierre del período» sólo si la campaña está
  /// cerrada con fin; si no, «Saldo a hoy».
  bool get periodClosed =>
      period != null && period!.status == 'CLOSED' && period!.endDay != null;

  List<CampaignDebt> get debts => account.debtsByCampaign(ledger.campaignOrder);
}
