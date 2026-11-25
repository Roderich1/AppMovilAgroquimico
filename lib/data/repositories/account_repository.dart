import 'package:sqflite/sqflite.dart' show Sqflite, Transaction;

import '../../domain/account_ledger.dart';
import '../../domain/account_texts.dart' show AccountPaymentResult;
import '../../domain/campaign_calendar.dart';
import '../../domain/models.dart';
import '../account_ledger_query.dart';
import 'account_queries.dart';
import 'repository_exceptions.dart';
import 'repository_session.dart';

/// Sub-repositorio de cuentas entre responsables, imputación FIFO de pagos,
/// libro D-04, reportes y tablero de inicio.
class AccountRepository {
  AccountRepository(this._session) : _queries = AccountQueries(_session);

  final RepositorySession _session;
  final AccountQueries _queries;

  Future<int> addAccountPayment({
    required int personId,
    int? campaignId,
    required int amountBobMinor,
    bool advance = false,
    DateTime? date,
    String? notes,
  }) async => (await registerAccountPayment(
    personId: personId,
    campaignId: campaignId,
    amountBobMinor: amountBobMinor,
    advance: advance,
    date: date,
    notes: notes,
  )).paymentId;

  /// Registra un pago o adelanto y lo imputa a las deudas más antiguas de la
  /// persona (RN-38), de cualquier campaña (D-04, E-15).
  Future<AccountPaymentResult> registerAccountPayment({
    required int personId,
    int? campaignId,
    required int amountBobMinor,
    bool advance = false,
    DateTime? date,
    String? notes,
  }) async {
    if (amountBobMinor <= 0) {
      throw BusinessRuleException('El importe debe ser mayor a cero.');
    }
    return _session.write((txn, context) async {
      final rule = OwnershipRule([
        for (final row in await txn.query('owner_bindings'))
          LedgerBinding(
            id: row['id']! as int,
            personId: row['person_id']! as int,
            boundAt: row['bound_at']! as String,
            endedAt: row['ended_at'] as String?,
          ),
      ]);
      final paymentOwn = rule.isOwn(personId, localDay(date ?? DateTime.now()));
      if (paymentOwn) {
        throw BusinessRuleException(ownerAccountPaymentRejectedMessage);
      }
      _session.requireOwnerInPersonal(
        context,
        [personId],
        'En el modo individual no hay cuentas por cobrar: no se registran '
        'pagos de cuenta.',
      );
      final paymentId = await txn.insert('account_transactions', {
        'person_id': personId,
        'campaign_id': campaignId,
        'transaction_date': _session.date(date ?? DateTime.now()),
        'type': advance ? 'ADVANCE' : 'PAYMENT',
        'amount_bob_minor_signed': -amountBobMinor,
        'reference_type': advance ? 'ADVANCE' : 'PAYMENT',
        'notes': notes,
      });
      final charges = await _outstandingChargesFor(
        txn,
        personId: personId,
        rule: rule,
        paymentOwn: paymentOwn,
      );
      final (:imputed, :remaining) = await _allocatePaymentToCharges(
        txn,
        paymentId: paymentId,
        amountBobMinor: amountBobMinor,
        charges: charges,
      );
      return AccountPaymentResult(
        paymentId: paymentId,
        amountMinor: amountBobMinor,
        advance: advance,
        imputed: imputed,
        unappliedMinor: remaining,
      );
    });
  }

  Future<List<Map<String, Object?>>> _outstandingChargesFor(
    Transaction txn, {
    required int personId,
    required OwnershipRule rule,
    required bool paymentOwn,
  }) async {
    final charges = [
      ...await txn.rawQuery(
        '''SELECT t.id, t.transaction_date, t.campaign_id, c.name campaign_name,
        t.amount_bob_minor_signed
        - COALESCE((SELECT -SUM(r.amount_bob_minor_signed) FROM account_transactions r
            WHERE r.reversal_of_id=t.id AND r.amount_bob_minor_signed<0),0)
        - COALESCE((SELECT SUM(a.amount_bob_minor) FROM payment_allocations a
            WHERE a.charge_transaction_id=t.id),0) outstanding
        FROM account_transactions t LEFT JOIN campaigns c ON c.id=t.campaign_id
        WHERE t.person_id=? AND t.amount_bob_minor_signed>0
          AND t.reversal_of_id IS NULL''',
        [personId],
      ),
    ];
    charges.sort((a, b) {
      final byDay = storedLocalDay(a['transaction_date']! as String)
          .compareTo(storedLocalDay(b['transaction_date']! as String));
      return byDay != 0 ? byDay : (a['id']! as int).compareTo(b['id']! as int);
    });
    charges.removeWhere(
      (charge) =>
          rule.isOwn(
            personId,
            storedLocalDay(charge['transaction_date']! as String),
          ) !=
          paymentOwn,
    );
    return charges;
  }

  Future<
    ({
      List<({int? campaignId, String campaignName, int amountMinor})> imputed,
      int remaining,
    })
  >
  _allocatePaymentToCharges(
    Transaction txn, {
    required int paymentId,
    required int amountBobMinor,
    required List<Map<String, Object?>> charges,
  }) async {
    var remaining = amountBobMinor;
    final imputed =
        <({int? campaignId, String campaignName, int amountMinor})>[];
    for (final charge in charges) {
      if (remaining == 0) break;
      final outstanding = charge['outstanding']! as int;
      if (outstanding <= 0) continue;
      final allocated = remaining < outstanding ? remaining : outstanding;
      await txn.insert('payment_allocations', {
        'payment_transaction_id': paymentId,
        'charge_transaction_id': charge['id'],
        'amount_bob_minor': allocated,
      });
      imputed.add((
        campaignId: charge['campaign_id'] as int?,
        campaignName:
            charge['campaign_name'] as String? ??
            'Campaña #${charge['campaign_id']}',
        amountMinor: allocated,
      ));
      remaining -= allocated;
    }
    return (imputed: imputed, remaining: remaining);
  }

  /// Libro de cuentas en **una** consulta (`readAccountLedger`).
  Future<AccountLedger> accountLedger({
    int? personId,
    bool withDetails = true,
  }) async => readAccountLedger(
    await _session.db,
    personId: personId,
    withDetails: withDetails,
  );

  /// Filas de la lista de Cuentas (§2.3).
  Future<List<AccountSummary>> accountSummaries({int? campaignId}) async =>
      (await accountLedger(withDetails: false))
          .summaries(campaignId: campaignId);

  /// Estado de cuenta (§2.5).
  Future<AccountStatement> accountStatement(
    int personId, {
    int? campaignId,
  }) async =>
      (await accountLedger(personId: personId))
          .statement(personId, campaignId: campaignId);

  Future<Map<String, Object?>> personCampaignBalance(
    int personId,
    int campaignId,
  ) => _queries.personCampaignBalance(personId, campaignId);

  Future<List<Map<String, Object?>>> settlements({int? campaignId}) =>
      _queries.settlements(campaignId: campaignId);

  Future<List<Map<String, Object?>>> topSettlements({int limit = 5}) =>
      _queries.topSettlements(limit: limit);

  Future<List<Map<String, Object?>>> statement(
    int personId, {
    int? campaignId,
  }) => _queries.statement(personId, campaignId: campaignId);

  Future<List<Map<String, Object?>>> detailedStatement(
    int personId, {
    int? campaignId,
  }) => _queries.detailedStatement(personId, campaignId: campaignId);

  Future<List<Map<String, Object?>>> farmCostReport({int? campaignId}) =>
      _queries.farmCostReport(campaignId: campaignId);

  Future<List<Map<String, Object?>>> productCostReport({int? campaignId}) =>
      _queries.productCostReport(campaignId: campaignId);

  Future<DashboardSummary> dashboard() async {
    final db = await _session.db;
    final purchases =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COALESCE(SUM(total_bob_minor),0) FROM purchases WHERE reversed_at IS NULL',
          ),
        ) ??
        0;
    final provider =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COALESCE(SUM(amount_bob_minor),0) FROM provider_payments WHERE reversed_at IS NULL',
          ),
        ) ??
        0;
    final ledger = await accountLedger(withDetails: false);
    final family = ledger.receivableByRole('FAMILY');
    final third = ledger.receivableByRole('THIRD_PARTY');
    final received = ledger.receivedMinor();
    final stock =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COALESCE(SUM(quantity_signed),0) FROM inventory_movements',
          ),
        ) ??
        0;
    return DashboardSummary(
      purchasesBobMinor: purchases,
      providerPaidMinor: provider,
      familyReceivableMinor: family.receivableMinor,
      thirdPartyReceivableMinor: third.receivableMinor,
      familyCreditMinor: family.creditMinor,
      thirdPartyCreditMinor: third.creditMinor,
      topBalances: [
        for (final row in ledger.topBalances())
          (
            personId: row.personId,
            name: row.name,
            role: row.role,
            balanceMinor: row.account.netMinor,
          ),
      ],
      receivedMinor: received,
      stockBase: stock,
    );
  }
}
