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

  /// E-15 (A1): imputaciones guardadas hacia un cargo de la otra clase
  /// (propio frente a por cobrar). No cuentan como aplicadas: lo imputado
  /// queda sin imputar en la cuenta de este crédito.
  final List<CreditAllocation> crossAllocations = [];

  int get allocatedMinor =>
      allocations.fold(0, (sum, allocation) => sum + allocation.amountMinor);

  int get crossAllocatedMinor => crossAllocations.fold(
    0,
    (sum, allocation) => sum + allocation.amountMinor,
  );

  int get unappliedMinor => -entry.amountMinor - allocatedMinor;
}

/// Qué es «propio» (E-15; criterio de clase del coordinador, 2026-10-27,
/// documento D04_E15 §7): un asiento o una aplicación es propio si su persona
/// es el **titular vigente** (todos sus asientos, también los anteriores a su
/// vínculo) o si su persona era titular el día local del asiento
/// (día(`bound_at`) ≤ día < día(`ended_at`); lo anterior al primer vínculo es
/// del primer titular). Es un supuesto de presentación y de imputación: no
/// cambia datos guardados.
final class OwnershipRule {
  OwnershipRule(Iterable<LedgerBinding> bindings)
    : bindings = [...bindings]
        ..sort((a, b) {
          final byBound = a.boundAt.compareTo(b.boundAt);
          return byBound != 0 ? byBound : a.id.compareTo(b.id);
        });

  /// Por `bound_at` y luego `id`.
  final List<LedgerBinding> bindings;

  /// Titular vigente (vínculo sin `ended_at`), o nulo.
  int? get currentOwner {
    for (final binding in bindings) {
      if (binding.endedAt == null) return binding.personId;
    }
    return null;
  }

  bool isOwn(int personId, String day) {
    if (personId == currentOwner) return true;
    for (var i = 0; i < bindings.length; i++) {
      final binding = bindings[i];
      if (binding.personId != personId) continue;
      final start = i == 0 ? null : storedLocalDay(binding.boundAt);
      final end = binding.endedAt == null
          ? null
          : storedLocalDay(binding.endedAt!);
      if ((start == null || start.compareTo(day) <= 0) &&
          (end == null || day.compareTo(end) < 0)) {
        return true;
      }
    }
    return false;
  }
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

/// Vínculo de titular (`owner_bindings`), leído para decidir qué es propio.
final class LedgerBinding {
  const LedgerBinding({
    required this.id,
    required this.personId,
    required this.boundAt,
    this.endedAt,
  });
  final int id;
  final int personId;
  final String boundAt;
  final String? endedAt;
}

/// Aplicación de una persona que ha sido titular: base del consumo propio
/// (E-15, costo FIFO ya volcado en `total_cost_bob_minor`).
final class LedgerApplication {
  const LedgerApplication({
    required this.id,
    required this.personId,
    required this.campaignId,
    required this.appliedAt,
    required this.totalCostMinor,
    required this.reversed,
  });
  final int id;
  final int personId;
  final int? campaignId;
  final String appliedAt;
  final int totalCostMinor;
  final bool reversed;

  String get day => storedLocalDay(appliedAt);
}

/// Consumo propio de un titular en un alcance (E-15 §B.1).
final class OwnConsumption {
  int activeCount = 0;
  int activeCostMinor = 0;
  int reversedCount = 0;
  int reversedCostMinor = 0;

  void add(LedgerApplication application) {
    if (application.reversed) {
      reversedCount++;
      reversedCostMinor += application.totalCostMinor;
    } else {
      activeCount++;
      activeCostMinor += application.totalCostMinor;
    }
  }

  bool get isEmpty => activeCount == 0 && reversedCount == 0;
}

/// Libro de todas las personas leídas.
///
/// E-15 (decisión del autor del 2026-10-27; criterio Q-3 del documento
/// D04_E15 §7): un asiento o una aplicación es **propio** si su persona era
/// titular en su día local: día(`bound_at`) ≤ día < día(`ended_at`). Lo
/// anterior al primer vínculo se atribuye al primer titular. Es un supuesto
/// de presentación: no escribe ni cambia datos. Lo propio sale de las cuentas
/// por cobrar y se muestra como «Consumo y costos propios».
final class AccountLedger {
  AccountLedger._(
    this.persons,
    this.campaigns,
    this.accounts,
    this.ownAccounts,
    this.bindings,
    this._ownApplications,
  );

  final List<LedgerPerson> persons;

  /// Por inicio y luego `id`.
  final List<CampaignPeriod> campaigns;

  /// Cuentas por cobrar: sin los asientos propios.
  final Map<int, PersonAccount> accounts;

  /// Asientos propios de quien fue o es titular (registro, no deuda).
  final Map<int, PersonAccount> ownAccounts;
  final List<LedgerBinding> bindings;
  final Map<int, List<LedgerApplication>> _ownApplications;

  factory AccountLedger.build({
    required List<LedgerPerson> persons,
    required List<CampaignPeriod> campaigns,
    required List<LedgerEntry> entries,
    required List<LedgerAllocation> allocations,
    List<LedgerBinding> bindings = const [],
    List<LedgerApplication> applications = const [],
  }) {
    final sortedCampaigns = [...campaigns]
      ..sort((a, b) {
        final byStart = a.startDay.compareTo(b.startDay);
        return byStart != 0 ? byStart : a.id.compareTo(b.id);
      });
    final rule = OwnershipRule(bindings);
    final sortedBindings = rule.bindings;
    bool ownOn(int personId, String day) => rule.isOwn(personId, day);

    final names = {for (final person in persons) person.id: person};
    PersonAccount newAccount(int id) =>
        PersonAccount(names[id] ?? LedgerPerson(id: id, name: '', role: ''));
    final accounts = <int, PersonAccount>{
      for (final person in persons) person.id: PersonAccount(person),
    };
    final ownAccounts = <int, PersonAccount>{};
    final sorted = [...entries]..sort(compareByDayThenId);
    final byId = {for (final entry in sorted) entry.id: entry};
    bool isCharge(LedgerEntry e) => e.amountMinor > 0 && e.reversalOfId == null;
    bool revertsCharge(LedgerEntry e) {
      if (e.amountMinor >= 0 || e.reversalOfId == null) return false;
      final target = byId[e.reversalOfId];
      return target != null && isCharge(target);
    }

    // La reversión de un cargo sigue la propiedad de su cargo.
    final own = <int, bool>{};
    for (final entry in sorted) {
      if (!revertsCharge(entry))
        own[entry.id] = ownOn(entry.personId, entry.day);
    }
    for (final entry in sorted) {
      if (revertsCharge(entry))
        own[entry.id] = own[entry.reversalOfId] ?? false;
    }
    for (final entry in sorted) {
      final account = own[entry.id]!
          ? ownAccounts.putIfAbsent(
              entry.personId,
              () => newAccount(entry.personId),
            )
          : accounts.putIfAbsent(
              entry.personId,
              () => newAccount(entry.personId),
            );
      account.entries.add(entry);
      final LedgerEntryClass cls;
      if (isCharge(entry)) {
        cls = LedgerEntryClass.charge;
        account.charges[entry.id] = ChargeState(entry);
      } else if (revertsCharge(entry)) {
        cls = LedgerEntryClass.chargeReversal;
      } else if (entry.amountMinor > 0) {
        cls = LedgerEntryClass.creditCompensation;
        account.compensationMinor += entry.amountMinor;
      } else {
        // Negativo que no revierte un cargo, o importe cero: crédito.
        cls = LedgerEntryClass.credit;
        account.credits[entry.id] = CreditState(entry);
      }
      account.classes[entry.id] = cls;
    }
    final all = [...accounts.values, ...ownAccounts.values];
    final chargesById = {for (final account in all) ...account.charges};
    final creditsById = {for (final account in all) ...account.credits};
    // Reversiones: se aplican a su cargo.
    for (final account in all) {
      for (final entry in account.entries) {
        if (account.classes[entry.id] != LedgerEntryClass.chargeReversal) {
          continue;
        }
        final charge = chargesById[entry.reversalOfId];
        if (charge == null) continue;
        // La fila de reversión vive en la cuenta de su cargo.
        account.charges.putIfAbsent(charge.entry.id, () => charge);
        charge.reversedMinor += -entry.amountMinor;
        final day = entry.day;
        if (charge.reversalDay == null ||
            day.compareTo(charge.reversalDay!) > 0) {
          charge.reversalDay = day;
        }
      }
    }
    // Imputaciones guardadas: sólo de un crédito a un cargo.
    for (final allocation in allocations) {
      final charge = chargesById[allocation.chargeId];
      final credit = creditsById[allocation.paymentId];
      if (charge == null || credit == null) continue;
      // A1: entre clases distintas no se aplica (un cargo propio no es deuda
      // y un pago propio no es cobro).
      if (own[charge.entry.id] != own[credit.entry.id]) {
        credit.crossAllocations.add(
          CreditAllocation(charge, allocation.amountMinor),
        );
        continue;
      }
      charge.allocatedMinor += allocation.amountMinor;
      credit.allocations.add(CreditAllocation(charge, allocation.amountMinor));
    }
    for (final credit in creditsById.values) {
      credit.allocations.sort(
        (a, b) => compareByDayThenId(a.charge.entry, b.charge.entry),
      );
      credit.crossAllocations.sort(
        (a, b) => compareByDayThenId(a.charge.entry, b.charge.entry),
      );
    }
    for (final account in all) {
      final ids = {for (final entry in account.entries) entry.id};
      for (final charge in account.charges.values) {
        // Un cargo cuenta sólo en la cuenta donde está su fila.
        if (!ids.contains(charge.entry.id)) continue;
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
    final ownApplications = <int, List<LedgerApplication>>{};
    for (final application in applications) {
      if (ownOn(application.personId, application.day)) {
        ownApplications
            .putIfAbsent(application.personId, () => [])
            .add(application);
      }
    }
    return AccountLedger._(
      persons,
      sortedCampaigns,
      accounts,
      ownAccounts,
      sortedBindings,
      ownApplications,
    );
  }

  /// Titular vigente (vínculo sin `ended_at`), o nulo.
  int? get ownerPersonId {
    for (final binding in bindings) {
      if (binding.endedAt == null) return binding.personId;
    }
    return null;
  }

  /// Asientos propios de [personId] (vacío si nunca fue titular).
  PersonAccount ownAccount(int personId) =>
      ownAccounts[personId] ?? PersonAccount(account(personId).person);

  /// Consumo propio de [personId] en [campaignId] (nulo = todas).
  OwnConsumption ownConsumption(int personId, {int? campaignId}) {
    final consumption = OwnConsumption();
    for (final application in _ownApplications[personId] ?? const []) {
      if (campaignId == null || application.campaignId == campaignId) {
        consumption.add(application);
      }
    }
    return consumption;
  }

  /// Consumo propio por campaña de la aplicación, en orden de campaña.
  List<({int? campaignId, OwnConsumption consumption})>
  ownConsumptionByCampaign(int personId) {
    final byCampaign = <int?, OwnConsumption>{};
    for (final application in _ownApplications[personId] ?? const []) {
      byCampaign
          .putIfAbsent(application.campaignId, OwnConsumption.new)
          .add(application);
    }
    return [
      for (final id in campaignOrder)
        if (byCampaign.containsKey(id))
          (campaignId: id, consumption: byCampaign[id]!),
      for (final entry in byCampaign.entries)
        if (!campaignOrder.contains(entry.key))
          (campaignId: entry.key, consumption: entry.value),
    ];
  }

  /// Fue o es titular y tiene algo propio que mostrar.
  bool hasOwnRecords(int personId) =>
      (ownAccounts[personId]?.entries.isNotEmpty ?? false) ||
      (_ownApplications[personId]?.isNotEmpty ?? false);

  /// Lee el resultado de la consulta única del repositorio
  /// (`AgroRepository.accountLedger`). Cada fila lleva `kind`:
  /// K campaña, P persona, T asiento, L imputación, B vínculo de titular y
  /// A aplicación de quien ha sido titular.
  factory AccountLedger.fromRows(List<Map<String, Object?>> rows) {
    final persons = <LedgerPerson>[];
    final campaigns = <CampaignPeriod>[];
    final entries = <LedgerEntry>[];
    final allocations = <LedgerAllocation>[];
    final bindings = <LedgerBinding>[];
    final applications = <LedgerApplication>[];
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
        case 'B':
          bindings.add(
            LedgerBinding(
              id: row['id']! as int,
              personId: row['person_id']! as int,
              boundAt: row['d1']! as String,
              endedAt: row['d2'] as String?,
            ),
          );
        case 'A':
          applications.add(
            LedgerApplication(
              id: row['id']! as int,
              personId: row['person_id']! as int,
              campaignId: row['ref1'] as int?,
              appliedAt: row['d1']! as String,
              totalCostMinor: row['amount']! as int,
              reversed: row['d2'] != null,
            ),
          );
      }
    }
    return AccountLedger.build(
      persons: persons,
      campaigns: campaigns,
      entries: entries,
      allocations: allocations,
      bindings: bindings,
      applications: applications,
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
    final owner = ownerPersonId;
    final rows = [
      for (final person in persons)
        // E-15: el titular vigente no es deudor de sí mismo. Sólo aparece si
        // tiene asientos que no son propios (anteriores a su vínculo, Q-3).
        if (person.role != 'ADMIN' &&
            (person.id != owner || account(person.id).entries.isNotEmpty))
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

  /// «Principales saldos» de Inicio: las primeras filas de la lista con
  /// «Todas las campañas» (saldo neto descendente, sin ADMIN ni lo propio).
  List<AccountSummary> topBalances({int limit = 5}) =>
      summaries().take(limit).toList();

  /// «Pagos recibidos»: Σ de pagos y adelantos (sin los propios: E-15).
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
  ///
  /// [now] fija «hoy» para decidir si el período ya terminó (pruebas).
  AccountStatement statement(int personId, {int? campaignId, DateTime? now}) {
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
    final own = ownAccount(personId);
    return AccountStatement(
      ledger: this,
      account: account,
      period: period,
      openingMinor: opening,
      lines: lines,
      closingMinor: balance,
      ownAccount: own,
      ownLines: [
        for (final entry in own.entries)
          if (period == null || period.contains(entry.day)) entry,
      ],
      ownConsumption: ownConsumption(personId, campaignId: campaignId),
      isCurrentOwner: ownerPersonId == personId,
      today: localDay(now ?? DateTime.now()),
    );
  }
}

/// El período de [campaign] ya terminó: tiene fin y el fin es anterior a
/// [today]. No depende del estado: una campaña ACTIVA cuyo fin ya pasó (la
/// sucesora se creó y todavía no se activó, #125) también corta sus filas
/// en el fin (D-04, revisión cruzada).
bool periodEnded(CampaignPeriod campaign, String today) =>
    campaign.endDay != null && campaign.endDay!.compareTo(today) < 0;

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
    required this.ownAccount,
    this.ownLines = const [],
    required this.ownConsumption,
    this.isCurrentOwner = false,
    required this.today,
  });

  final AccountLedger ledger;

  /// Día local de «hoy» con el que se armó el estado.
  final String today;

  /// Cuenta por cobrar (sin lo propio).
  final PersonAccount account;

  /// E-15: asientos propios de quien es o fue titular, y los del período.
  final PersonAccount ownAccount;
  final List<LedgerEntry> ownLines;

  /// E-15: consumo propio en el alcance (campaña de la aplicación).
  final OwnConsumption ownConsumption;

  /// La persona es el titular vigente.
  final bool isCurrentOwner;

  bool get hasOwnRecords =>
      ownAccount.entries.isNotEmpty || !ownConsumption.isEmpty;

  /// Campaña filtrada, o nula con «Todas las campañas».
  final CampaignPeriod? period;

  /// Saldo al inicio del período; nulo con «Todas las campañas».
  final int? openingMinor;
  final List<LedgerStatementLine> lines;
  final int closingMinor;

  /// El cierre es «Saldo al cierre del período» si el período ya terminó
  /// (fin anterior a hoy, con cualquier estado); si no, «Saldo a hoy».
  bool get periodClosed => period != null && periodEnded(period!, today);

  List<CampaignDebt> get debts => account.debtsByCampaign(ledger.campaignOrder);
}
