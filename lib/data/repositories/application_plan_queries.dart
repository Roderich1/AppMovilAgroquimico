import 'package:sqflite/sqflite.dart' show Sqflite;

import '../../domain/campaign_calendar.dart';
import '../../domain/money.dart';
import 'repository_session.dart';
import 'repository_types.dart';
import 'stock_fifo_queries.dart';

/// Consultas de sólo lectura para aplicaciones, planes, bitácora de chaco y
/// previsiones FIFO.
class ApplicationPlanQueries {
  ApplicationPlanQueries(this._session, this._fifoQueries);

  static const pendingPlanStatuses = <String>{'PLANNED', 'DRAFT'};

  final RepositorySession _session;
  final StockFifoQueries _fifoQueries;

  Future<List<Map<String, Object?>>> applications({
    int? campaignId,
    int? personId,
    int? farmId,
    int? productId,
    int? limit,
  }) async {
    final conditions = <String>[];
    final args = <Object?>[];
    if (campaignId != null) {
      conditions.add('a.campaign_id=?');
      args.add(campaignId);
    }
    if (personId != null) {
      conditions.add('a.person_id=?');
      args.add(personId);
    }
    if (farmId != null) {
      conditions.add('a.farm_id=?');
      args.add(farmId);
    }
    if (productId != null) {
      conditions.add(
        'EXISTS (SELECT 1 FROM application_items x WHERE x.application_id=a.id AND x.product_id=?)',
      );
      args.add(productId);
    }
    if (limit != null) args.add(limit);
    return (await _session.db).rawQuery(
      '''SELECT a.*, p.name person_name, f.name farm_name,
        c.name campaign_name,
        COALESCE(SUM(i.theoretical_quantity_base),0) theoretical_quantity_base,
        COALESCE(SUM(i.quantity_base),0) real_quantity_base,
        GROUP_CONCAT(DISTINCT pr.unit) units, COUNT(i.id) item_count,
        GROUP_CONCAT(pr.name || '|' || i.quantity_base || '|' || pr.unit, ';') items_summary
        FROM applications a JOIN persons p ON p.id=a.person_id JOIN farms f ON f.id=a.farm_id
        JOIN campaigns c ON c.id=a.campaign_id
        LEFT JOIN application_items i ON i.application_id=a.id LEFT JOIN products pr ON pr.id=i.product_id
        ${conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}'}
        GROUP BY a.id ORDER BY applied_at DESC, a.id DESC ${limit == null ? '' : 'LIMIT ?'}''',
      args,
    );
  }

  /// Planes con sus productos. Por omisión devuelve **sólo los pendientes**.
  Future<List<Map<String, Object?>>> plans({
    int limit = 400,
    bool includeApplied = false,
  }) async {
    final pending = pendingPlanStatuses.map((_) => '?').join(',');
    return (await _session.db).rawQuery(
      '''SELECT i.*, p.name product_name, p.unit, f.name farm_name, f.owner_person_id, pe.name owner_name,
    c.name campaign_name, a.campaign_id, a.status plan_status, a.planned_date
    FROM application_plan_items i
    JOIN application_plans a ON a.id=i.plan_id JOIN products p ON p.id=i.product_id
    JOIN farms f ON f.id=a.farm_id JOIN persons pe ON pe.id=f.owner_person_id
    JOIN campaigns c ON c.id=a.campaign_id
    ${includeApplied ? '' : 'WHERE a.status IN ($pending)'}
    ORDER BY a.id DESC LIMIT ?''',
      [if (!includeApplied) ...pendingPlanStatuses, limit],
    );
  }

  Future<List<Map<String, Object?>>> planForApplication(int planId) async =>
      (await _session.db).rawQuery(
        '''SELECT a.id plan_id, a.campaign_id, a.farm_id,
        f.owner_person_id person_id, f.name farm_name, f.area_m2 farm_area_m2,
        i.area_m2, i.product_id, i.dose_base_per_ha,
        i.required_quantity_base, p.name product_name, p.unit
        FROM application_plans a JOIN farms f ON f.id=a.farm_id
        JOIN application_plan_items i ON i.plan_id=a.id
        JOIN products p ON p.id=i.product_id WHERE a.id=? ORDER BY i.id''',
        [planId],
      );

  Future<List<Map<String, Object?>>> farmLogbook(
    int farmId, {
    int? campaignId,
    int? productId,
  }) async {
    final conditions = <String>['a.farm_id=?'];
    final args = <Object?>[farmId];
    if (campaignId != null) {
      conditions.add('a.campaign_id=?');
      args.add(campaignId);
    }
    if (productId != null) {
      conditions.add('i.product_id=?');
      args.add(productId);
    }
    return (await _session.db).rawQuery(
      '''SELECT a.id application_id, a.applied_at, a.status, a.notes,
      c.name campaign_name, a.person_id, pe.name person_name, i.id application_item_id,
      pr.id product_id, pr.name product_name, pr.unit, i.treated_area_m2,
      i.dose_base_per_ha, i.theoretical_quantity_base, i.quantity_base,
      i.cost_bob_minor,
      (SELECT GROUP_CONCAT('#' || ac.inventory_lot_id || ': ' || ac.quantity_consumed_base)
        FROM application_consumptions ac WHERE ac.application_item_id=i.id AND ac.reversed_at IS NULL) fifo_lots
      FROM applications a JOIN campaigns c ON c.id=a.campaign_id
      JOIN persons pe ON pe.id=a.person_id JOIN application_items i ON i.application_id=a.id
      JOIN products pr ON pr.id=i.product_id
      WHERE ${conditions.join(' AND ')} ORDER BY a.applied_at DESC,a.id DESC,i.id''',
      args,
    );
  }

  Future<Map<String, Object?>> productStockInsight({
    required int personId,
    required int productId,
    required int campaignId,
  }) async {
    final db = await _session.db;
    final ownerAvailable =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COALESCE(SUM(quantity_signed),0) FROM inventory_movements WHERE owner_person_id=? AND product_id=?',
            [personId, productId],
          ),
        ) ??
        0;
    final physicalTotal =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COALESCE(SUM(quantity_signed),0) FROM inventory_movements WHERE product_id=?',
            [productId],
          ),
        ) ??
        0;
    final consumedCampaign =
        Sqflite.firstIntValue(
          await db.rawQuery(
            '''SELECT COALESCE(-SUM(m.quantity_signed),0) FROM inventory_movements m
            JOIN applications a ON a.id=m.reference_id AND m.reference_type='APPLICATION'
            WHERE m.owner_person_id=? AND m.product_id=? AND m.type='APPLICATION_OUT'
            AND a.campaign_id=? AND a.reversed_at IS NULL''',
            [personId, productId, campaignId],
          ),
        ) ??
        0;
    final lots = await db.rawQuery(
      '''SELECT l.unit_cost_bob_minor_per_major_unit unit_cost, SUM(m.quantity_signed) available
      FROM inventory_lots l JOIN inventory_movements m ON m.lot_id=l.id
      WHERE l.owner_person_id=? AND l.product_id=? AND l.reversed_at IS NULL
      GROUP BY l.id HAVING available>0 ORDER BY l.acquired_date,l.id''',
      [personId, productId],
    );
    return {
      'owner_available_base': ownerAvailable,
      'physical_total_base': physicalTotal,
      'consumed_campaign_base': consumedCampaign,
      'next_fifo_cost_minor': lots.isEmpty ? 0 : lots.first['unit_cost'],
      'available_lots': lots.length,
    };
  }

  /// Previsión de **sólo lectura** de los lotes que consumiría una aplicación.
  Future<List<ApplicationLotPreview>> previewApplicationLots({
    required int personId,
    required int productId,
    required int quantityBase,
    required DateTime appliedAt,
  }) async {
    final db = await _session.db;
    final day = localDay(appliedAt);
    final lots = day == localDay(DateTime.now())
        ? await _fifoQueries.lotsAvailableNow(db, productId, personId)
        : await _fifoQueries.lotsAvailableAt(db, productId, personId, day);
    return [
      for (final (:lot, :take) in fifoTakes(lots, quantityBase))
        (
          lotId: lot['id']! as int,
          quantityBase: take,
          expiryDay: lot['expiry_date'] as String?,
          lotNumber: lot['lot_number'] as String?,
        ),
    ];
  }

  Future<int> estimateFifoCost({
    required int personId,
    required int productId,
    required int quantityBase,
  }) async {
    final lots = await (await _session.db).rawQuery(
      '''SELECT l.unit_cost_bob_minor_per_major_unit unit_cost, SUM(m.quantity_signed) available
      FROM inventory_lots l JOIN inventory_movements m ON m.lot_id=l.id
      WHERE l.owner_person_id=? AND l.product_id=? AND l.reversed_at IS NULL
      GROUP BY l.id HAVING available>0 ORDER BY l.acquired_date,l.id''',
      [personId, productId],
    );
    var remaining = quantityBase;
    var cost = 0;
    for (final lot in lots) {
      if (remaining <= 0) break;
      final available = lot['available']! as int;
      final take = remaining < available ? remaining : available;
      cost += costForBaseQuantity(take, lot['unit_cost']! as int);
      remaining -= take;
    }
    return cost;
  }
}
