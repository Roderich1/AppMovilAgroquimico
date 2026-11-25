import '../../domain/campaign_calendar.dart';
import '../../domain/inventory_alerts.dart';
import '../../domain/operation_mode.dart';
import '../app_database.dart';
import '../operation_mode_store.dart';
import 'repository_exceptions.dart';
import 'repository_session.dart';

/// Consultas de sólo lectura de existencias, distribución, lotes, movimientos
/// y avisos F04-AV.
class InventoryQueries {
  InventoryQueries(this._session);

  static const alertSettingsColumns = [
    'id',
    'name',
    'unit',
    'active',
    'min_stock_base',
    'alert_lead_days',
  ];

  final RepositorySession _session;

  static ProductAlertSettings alertSettingsOf(Map<String, Object?> row) =>
      ProductAlertSettings(
        productId: row['id']! as int,
        productName: row['name']! as String,
        unit: row['unit']! as String,
        active: row['active'] == 1,
        minStockBase: row['min_stock_base'] as int?,
        leadDays: row['alert_lead_days'] as int?,
      );

  Future<List<Map<String, Object?>>> stock() async =>
      (await _session.db).rawQuery(
        '''SELECT l.id lot_id, l.owner_person_id, pr.name product_name, pr.unit, pe.name owner_name,
    SUM(m.quantity_signed) quantity_base, l.unit_cost_bob_minor_per_major_unit unit_cost
    FROM inventory_movements m JOIN inventory_lots l ON l.id=m.lot_id JOIN products pr ON pr.id=m.product_id
    JOIN persons pe ON pe.id=m.owner_person_id GROUP BY l.id HAVING quantity_base <> 0 ORDER BY l.acquired_date''',
      );

  // Cifras netas (#46, #51): comprado y consumido descuentan sus reversiones.
  Future<List<Map<String, Object?>>> inventorySummary({int? limit}) async =>
      (await _session.db).rawQuery(
        '''SELECT p.id product_id, p.name product_name, p.unit,
        COALESCE(SUM(CASE WHEN m.type IN ('PURCHASE_IN','PURCHASE_REVERSAL') THEN m.quantity_signed ELSE 0 END),0) purchased_base,
        COALESCE(-SUM(CASE WHEN m.type IN ('APPLICATION_OUT','APPLICATION_REVERSAL') THEN m.quantity_signed ELSE 0 END),0) consumed_base,
        COALESCE(SUM(m.quantity_signed),0) available_base,
        COALESCE((SELECT SUM(pi.required_quantity_base) FROM application_plan_items pi
          JOIN application_plans ap ON ap.id=pi.plan_id JOIN campaigns c ON c.id=ap.campaign_id
          WHERE pi.product_id=p.id AND ap.status IN ('DRAFT','PLANNED') AND c.status='ACTIVE'),0) committed_base,
        COALESCE(SUM(m.quantity_signed),0) - COALESCE((SELECT SUM(pi.required_quantity_base)
          FROM application_plan_items pi JOIN application_plans ap ON ap.id=pi.plan_id
          JOIN campaigns c ON c.id=ap.campaign_id WHERE pi.product_id=p.id
          AND ap.status IN ('DRAFT','PLANNED') AND c.status='ACTIVE'),0) projected_base,
        COALESCE((SUM(m.quantity_signed*l.unit_cost_bob_minor_per_major_unit)+500)/1000,0) available_value_bob_minor,
        COUNT(DISTINCT CASE WHEN m.quantity_signed <> 0 THEN l.owner_person_id END) people_count
        FROM products p LEFT JOIN inventory_movements m ON m.product_id=p.id
        LEFT JOIN inventory_lots l ON l.id=m.lot_id GROUP BY p.id ORDER BY p.name
        ${limit == null ? '' : 'LIMIT ?'}''',
        limit == null ? null : [limit],
      );

  Future<List<Map<String, Object?>>> personStockSummary(int personId) async =>
      (await _session.db).rawQuery(
        '''SELECT p.id product_id, p.name product_name, p.unit,
        COALESCE(SUM(CASE WHEN m.type IN ('PURCHASE_IN','PURCHASE_REVERSAL','TRANSFER_IN','TRANSFER_OUT',
          'TRANSFER_REVERSAL_IN','TRANSFER_REVERSAL_OUT') THEN m.quantity_signed ELSE 0 END),0) assigned_base,
        COALESCE(-SUM(CASE WHEN m.type IN ('APPLICATION_OUT','APPLICATION_REVERSAL') THEN m.quantity_signed ELSE 0 END),0) consumed_base,
        COALESCE(SUM(m.quantity_signed),0) available_base
        FROM products p LEFT JOIN inventory_movements m ON m.product_id=p.id AND m.owner_person_id=?
        GROUP BY p.id HAVING COUNT(m.id)>0 ORDER BY p.name''',
        [personId],
      );

  Future<Map<String, Object?>> inventoryProductHeader(int productId) async {
    final rows = await (await _session.db).rawQuery(
      '''SELECT p.id product_id, p.name product_name, p.unit,
      COALESCE(SUM(CASE WHEN m.type IN ('PURCHASE_IN','PURCHASE_REVERSAL') THEN m.quantity_signed ELSE 0 END),0) purchased_base,
      COALESCE(-SUM(CASE WHEN m.type IN ('APPLICATION_OUT','APPLICATION_REVERSAL') THEN m.quantity_signed ELSE 0 END),0) consumed_base,
      COALESCE(SUM(m.quantity_signed),0) physical_base,
      COALESCE((SUM(m.quantity_signed*l.unit_cost_bob_minor_per_major_unit)+500)/1000,0) value_bob_minor,
      COALESCE((SELECT SUM(pi.required_quantity_base) FROM application_plan_items pi
        JOIN application_plans ap ON ap.id=pi.plan_id JOIN campaigns c ON c.id=ap.campaign_id
        WHERE pi.product_id=p.id AND ap.status IN ('DRAFT','PLANNED') AND c.status='ACTIVE'),0) committed_base
      FROM products p LEFT JOIN inventory_movements m ON m.product_id=p.id
      LEFT JOIN inventory_lots l ON l.id=m.lot_id WHERE p.id=? GROUP BY p.id''',
      [productId],
    );
    if (rows.isEmpty) throw BusinessRuleException('El producto no existe.');
    return rows.single;
  }

  Future<List<Map<String, Object?>>> inventoryProductDistribution(
    int productId,
  ) async => (await _session.db).rawQuery(
    '''SELECT p.id person_id, p.name person_name,
        COALESCE(SUM(CASE WHEN m.type IN ('PURCHASE_IN','PURCHASE_REVERSAL','TRANSFER_IN','TRANSFER_OUT',
          'TRANSFER_REVERSAL_IN','TRANSFER_REVERSAL_OUT') THEN m.quantity_signed ELSE 0 END),0) assigned_base,
        COALESCE(-SUM(CASE WHEN m.type IN ('APPLICATION_OUT','APPLICATION_REVERSAL') THEN m.quantity_signed ELSE 0 END),0) consumed_base,
        COALESCE(SUM(m.quantity_signed),0) available_base
        FROM persons p LEFT JOIN inventory_movements m ON m.owner_person_id=p.id AND m.product_id=?
        GROUP BY p.id HAVING COUNT(m.id)>0
        ORDER BY p.name''',
    [productId],
  );

  /// Avisos de existencias y vencimiento (RF-43, RF-44, CU-22).
  Future<InventoryAlerts> inventoryAlerts({DateTime? now}) async {
    final db = await _session.db;
    final today = localDay(now ?? DateTime.now());
    final mode = await OperationModeStore(_session.appDatabase).current(db);
    final products = await db.query('products', columns: alertSettingsColumns);
    final lots = await db.rawQuery(
      '''SELECT l.id lot_id, l.product_id, p.name product_name, p.unit,
      p.alert_lead_days, l.owner_person_id, pe.name owner_name,
      l.expiry_date, l.lot_number, COALESCE(SUM(m.quantity_signed),0) remaining_base
      FROM inventory_lots l JOIN products p ON p.id=l.product_id
      JOIN persons pe ON pe.id=l.owner_person_id
      LEFT JOIN inventory_movements m ON m.lot_id=l.id
      WHERE l.reversed_at IS NULL GROUP BY l.id HAVING remaining_base>0
      ORDER BY p.name, pe.name, l.acquired_date, l.id''',
    );
    final perPerson = await db.rawQuery(
      '''SELECT m.product_id, m.owner_person_id, pe.name person_name,
      SUM(m.quantity_signed) net_base
      FROM inventory_movements m JOIN persons pe ON pe.id=m.owner_person_id
      WHERE pe.active=1
      GROUP BY m.product_id, m.owner_person_id''',
    );
    final totals = {
      for (final row in await db.rawQuery(
        '''SELECT product_id, SUM(quantity_signed) net_base
        FROM inventory_movements GROUP BY product_id''',
      ))
        row['product_id']! as int: row['net_base']! as int,
    };
    final last = await db.rawQuery(
      'SELECT MAX(movement_date) day FROM inventory_movements',
    );
    final lastStored = last.single['day'] as String?;

    final settings = [for (final row in products) alertSettingsOf(row)];
    final byId = {for (final p in settings) p.productId: p};
    const fallback = AppDatabase.defaultAlertLeadDays;
    return computeInventoryAlerts(
      today: today,
      shared: mode != OperationMode.personal,
      defaultLeadDays: fallback,
      lastMovementDay: lastStored == null ? null : storedLocalDay(lastStored),
      products: settings,
      lots: [
        for (final row in lots)
          AlertLot(
            lotId: row['lot_id']! as int,
            productId: row['product_id']! as int,
            productName: row['product_name']! as String,
            unit: row['unit']! as String,
            ownerPersonId: row['owner_person_id']! as int,
            ownerName: row['owner_name']! as String,
            remainingBase: row['remaining_base']! as int,
            expiryDay: row['expiry_date'] as String?,
            lotNumber: row['lot_number'] as String?,
            leadDays: row['alert_lead_days'] as int? ?? fallback,
            leadDaysIsDefault: row['alert_lead_days'] == null,
          ),
      ],
      stock: [
        for (final p in settings)
          StockLine(
            productId: p.productId,
            productName: p.productName,
            unit: p.unit,
            netBase: totals[p.productId] ?? 0,
          ),
        for (final row in perPerson)
          StockLine(
            productId: row['product_id']! as int,
            productName: byId[row['product_id']]!.productName,
            unit: byId[row['product_id']]!.unit,
            netBase: row['net_base']! as int,
            personId: row['owner_person_id']! as int,
            personName: row['person_name']! as String,
          ),
      ],
    );
  }

  Future<List<Map<String, Object?>>> inventoryProductLots(
    int productId, {
    int? personId,
    int? supplierId,
    int? campaignId,
  }) async {
    final conditions = <String>['l.product_id=?', 'l.reversed_at IS NULL'];
    final args = <Object?>[productId];
    if (personId != null) {
      conditions.add('l.owner_person_id=?');
      args.add(personId);
    }
    if (supplierId != null) {
      conditions.add('pu.supplier_id=?');
      args.add(supplierId);
    }
    if (campaignId != null) {
      conditions.add('pu.campaign_id=?');
      args.add(campaignId);
    }
    return (await _session.db).rawQuery(
      '''SELECT l.id lot_id, l.acquired_date, l.initial_quantity_base,
      l.expiry_date, l.lot_number,
      l.unit_cost_bob_minor_per_major_unit unit_cost, l.currency_code,
      l.original_unit_price_minor, l.exchange_rate_scaled, l.parent_lot_id,
      pe.name owner_name, s.name supplier_name, c.name campaign_name,
      COALESCE(SUM(m.quantity_signed),0) available_base
      FROM inventory_lots l JOIN persons pe ON pe.id=l.owner_person_id
      JOIN purchase_items pi ON pi.id=l.purchase_item_id
      JOIN purchases pu ON pu.id=pi.purchase_id JOIN suppliers s ON s.id=pu.supplier_id
      JOIN campaigns c ON c.id=pu.campaign_id
      LEFT JOIN inventory_movements m ON m.lot_id=l.id
      WHERE ${conditions.join(' AND ')} GROUP BY l.id
      HAVING available_base<>0 ORDER BY l.acquired_date,l.id LIMIT 500''',
      args,
    );
  }

  /// Historial del producto movimiento a movimiento, del más reciente al más
  /// antiguo (E-10).
  Future<List<Map<String, Object?>>> productMovements(
    int productId, {
    int limit = 20,
  }) async => (await _session.db).rawQuery(
    '''SELECT MIN(m.id) id, m.movement_date, m.type, SUM(m.quantity_signed) quantity_signed,
      m.reference_type, m.reference_id, MAX(m.notes) notes, pe.name owner_name,
      CASE WHEN m.reference_type IN ('APPLICATION','APPLICATION_REVERSAL') THEN
        (SELECT f.name FROM applications a JOIN farms f ON f.id=a.farm_id
          WHERE a.id=m.reference_id) END farm_name,
      CASE WHEN m.reference_type IN ('TRANSFER','TRANSFER_REVERSAL') THEN
        (SELECT CASE WHEN t.from_person_id=m.owner_person_id THEN pt.name ELSE pf.name END
          FROM transfers t JOIN persons pf ON pf.id=t.from_person_id
          JOIN persons pt ON pt.id=t.to_person_id WHERE t.id=m.reference_id) END counterpart_name,
      CASE WHEN m.reference_type='PURCHASE_ALLOCATION' THEN
        (SELECT s.name FROM purchase_allocations pa
          JOIN purchase_items pi ON pi.id=pa.purchase_item_id
          JOIN purchases pu ON pu.id=pi.purchase_id JOIN suppliers s ON s.id=pu.supplier_id
          WHERE pa.id=m.reference_id)
        WHEN m.reference_type='PURCHASE_REVERSAL' THEN
        (SELECT s.name FROM purchases pu JOIN suppliers s ON s.id=pu.supplier_id
          WHERE pu.id=m.reference_id) END supplier_name
      FROM inventory_movements m JOIN persons pe ON pe.id=m.owner_person_id
      WHERE m.product_id=?
      GROUP BY m.reference_type, m.reference_id, m.owner_person_id, m.type
      ORDER BY m.movement_date DESC, id DESC LIMIT ?''',
    [productId, limit],
  );
}
