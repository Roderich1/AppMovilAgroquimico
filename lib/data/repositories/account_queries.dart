import 'repository_session.dart';

/// Consultas de sólo lectura heredadas de cuentas, liquidaciones y reportes de
/// costos por chaco y producto.
class AccountQueries {
  AccountQueries(this._session);

  final RepositorySession _session;

  /// Heredada: sólo caracterización (EVO-004); la app usa `accountStatement` (D-04).
  Future<Map<String, Object?>> personCampaignBalance(
    int personId,
    int campaignId,
  ) async {
    final db = await _session.db;
    final campaign = (await db.query(
      'campaigns',
      columns: ['start_date'],
      where: 'id=?',
      whereArgs: [campaignId],
    )).single;
    final start = campaign['start_date'];
    final rows = await db.rawQuery(
      '''SELECT
      COALESCE(SUM(CASE WHEN c.start_date < ? THEN t.amount_bob_minor_signed ELSE 0 END),0) opening_balance,
      COALESCE(SUM(CASE WHEN t.campaign_id=? AND t.amount_bob_minor_signed>0 THEN t.amount_bob_minor_signed ELSE 0 END),0) campaign_charges,
      COALESCE(-SUM(CASE WHEN t.campaign_id=? AND t.amount_bob_minor_signed<0 THEN t.amount_bob_minor_signed ELSE 0 END),0) campaign_payments,
      COALESCE(SUM(t.amount_bob_minor_signed),0) total_balance
      FROM account_transactions t LEFT JOIN campaigns c ON c.id=t.campaign_id
      WHERE t.person_id=?''',
      [start, campaignId, campaignId, personId],
    );
    return rows.single;
  }

  /// Heredada: sólo caracterización (EVO-004); la app usa `accountSummaries` (D-04).
  Future<List<Map<String, Object?>>> settlements({int? campaignId}) async =>
      (await _session.db).rawQuery(
        '''SELECT p.id, p.name, p.role,
    COALESCE(SUM(t.amount_bob_minor_signed),0) balance,
    COALESCE(SUM(CASE WHEN t.amount_bob_minor_signed>0 THEN t.amount_bob_minor_signed ELSE 0 END),0) charges,
    COALESCE(-SUM(CASE WHEN t.amount_bob_minor_signed<0 THEN t.amount_bob_minor_signed ELSE 0 END),0) payments
    FROM persons p LEFT JOIN account_transactions t ON t.person_id=p.id ${campaignId == null ? '' : 'AND t.campaign_id=?'}
    WHERE p.role<>'ADMIN' GROUP BY p.id ORDER BY balance DESC, p.name''',
        [if (campaignId != null) campaignId],
      );

  Future<List<Map<String, Object?>>> topSettlements({int limit = 5}) async =>
      (await _session.db).rawQuery(
        '''SELECT p.id, p.name, p.role, COALESCE(SUM(t.amount_bob_minor_signed),0) balance
        FROM persons p LEFT JOIN account_transactions t ON t.person_id=p.id
        WHERE p.role<>'ADMIN' GROUP BY p.id ORDER BY balance DESC,p.name LIMIT ?''',
        [limit],
      );

  /// Heredada: sólo caracterización (EVO-004); la app usa `accountStatement` (D-04).
  Future<List<Map<String, Object?>>> statement(
    int personId, {
    int? campaignId,
  }) async => (await _session.db).rawQuery(
    '''SELECT * FROM account_transactions
    WHERE person_id=? ${campaignId == null ? '' : 'AND campaign_id=?'} ORDER BY transaction_date,id''',
    [personId, if (campaignId != null) campaignId],
  );

  /// Heredada: sólo caracterización (EVO-004); la app usa `accountStatement`; Personas la usa hasta E-15 (D-04).
  Future<List<Map<String, Object?>>> detailedStatement(
    int personId, {
    int? campaignId,
  }) async => (await _session.db).rawQuery(
    '''SELECT t.*,
    COALESCE(
      (SELECT GROUP_CONCAT(p.name, ', ') FROM application_items i JOIN products p ON p.id=i.product_id
       WHERE i.application_id=t.reference_id AND t.reference_type='APPLICATION'),
      (SELECT p.name FROM purchase_allocations a JOIN purchase_items i ON i.id=a.purchase_item_id
       JOIN products p ON p.id=i.product_id WHERE a.id=t.reference_id AND t.reference_type='PURCHASE_ALLOCATION'),
      t.notes, t.type) concept,
    (SELECT f.name FROM applications a JOIN farms f ON f.id=a.farm_id
     WHERE a.id=t.reference_id AND t.reference_type='APPLICATION') farm_name
    FROM account_transactions t WHERE t.person_id=?
    ${campaignId == null ? '' : 'AND t.campaign_id=?'} ORDER BY t.transaction_date,t.id''',
    [personId, if (campaignId != null) campaignId],
  );

  Future<List<Map<String, Object?>>> farmCostReport({int? campaignId}) async =>
      (await _session.db).rawQuery(
        '''SELECT f.id, f.name, f.area_m2, p.name owner_name,
        COALESCE(SUM(a.total_cost_bob_minor),0) total_cost_bob_minor
        FROM farms f JOIN persons p ON p.id=f.owner_person_id
        LEFT JOIN applications a ON a.farm_id=f.id AND a.reversed_at IS NULL
        ${campaignId == null ? '' : 'AND a.campaign_id=?'} GROUP BY f.id ORDER BY f.name''',
        campaignId == null ? null : [campaignId],
      );

  Future<List<Map<String, Object?>>> productCostReport({
    int? campaignId,
  }) async => (await _session.db).rawQuery(
    '''SELECT p.id, p.name, p.unit,
        COALESCE(SUM(CASE WHEN a.id IS NOT NULL THEN i.quantity_base ELSE 0 END),0) quantity_base,
        COALESCE(SUM(CASE WHEN a.id IS NOT NULL THEN i.cost_bob_minor ELSE 0 END),0) total_cost_bob_minor
        FROM products p LEFT JOIN application_items i ON i.product_id=p.id
        LEFT JOIN applications a ON a.id=i.application_id AND a.reversed_at IS NULL
        ${campaignId == null ? '' : 'AND a.campaign_id=?'} GROUP BY p.id ORDER BY p.name''',
    campaignId == null ? null : [campaignId],
  );
}
