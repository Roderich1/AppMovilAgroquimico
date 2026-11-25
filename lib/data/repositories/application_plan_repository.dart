import 'package:sqflite/sqflite.dart'
    show DatabaseExecutor, Sqflite, Transaction;

import '../../domain/campaign_calendar.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import 'application_plan_queries.dart';
import 'campaign_repository.dart';
import 'repository_exceptions.dart';
import 'repository_session.dart';
import 'repository_types.dart';
import 'stock_fifo_queries.dart';

/// Sub-repositorio de planes de aplicación y registro de aplicaciones FIFO.
class ApplicationPlanRepository {
  ApplicationPlanRepository(this._session, this._campaigns, this._fifoQueries)
    : _queries = ApplicationPlanQueries(_session, _fifoQueries);

  static const pendingPlanStatuses = ApplicationPlanQueries.pendingPlanStatuses;
  static const appliedPlanStatus = 'APPLIED';

  final RepositorySession _session;
  final CampaignRepository _campaigns;
  final StockFifoQueries _fifoQueries;
  final ApplicationPlanQueries _queries;

  Future<int> addPlan({
    required int farmId,
    required int campaignId,
    required int productId,
    required int areaM2,
    required int doseBasePerHa,
    DateTime? plannedDate,
  }) => addPlanMulti(
    farmId: farmId,
    campaignId: campaignId,
    areaM2: areaM2,
    items: [PlanItemDraft(productId: productId, doseBasePerHa: doseBasePerHa)],
    plannedDate: plannedDate,
  );

  Future<int> addPlanMulti({
    required int farmId,
    required int campaignId,
    required int areaM2,
    required List<PlanItemDraft> items,
    DateTime? plannedDate,
    String? notes,
  }) async {
    if (areaM2 <= 0 || items.isEmpty) {
      throw BusinessRuleException(
        'El plan necesita área y al menos un producto.',
      );
    }
    if (items.map((item) => item.productId).toSet().length != items.length) {
      throw BusinessRuleException('No repita productos dentro del plan.');
    }
    if (items.any((item) => item.doseBasePerHa <= 0)) {
      throw BusinessRuleException('Todas las dosis deben ser mayores a cero.');
    }
    return _session.write((txn, context) async {
      await _session.requireOwnerFarmInPersonal(txn, context, farmId);
      await _campaigns.ensureCampaignActive(txn, campaignId);
      final planId = await txn.insert('application_plans', {
        'farm_id': farmId,
        'campaign_id': campaignId,
        'planned_date': plannedDate == null ? null : _session.date(plannedDate),
        'status': 'PLANNED',
        'notes': notes,
      });
      for (final item in items) {
        final requiredBase = divideRoundedHalfUp(
          areaM2 * item.doseBasePerHa,
          10000,
        );
        await txn.insert('application_plan_items', {
          'plan_id': planId,
          'product_id': item.productId,
          'area_m2': areaM2,
          'dose_base_per_ha': item.doseBasePerHa,
          'required_quantity_base': requiredBase,
        });
      }
      return planId;
    });
  }

  /// Rechaza aplicar un plan que ya se usó (UIBUG-045).
  Future<void> _ensurePlanNotApplied(
    DatabaseExecutor executor,
    int planId,
  ) async {
    final rows = await executor.query(
      'application_plans',
      columns: ['status'],
      where: 'id=?',
      whereArgs: [planId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw BusinessRuleException('El plan indicado no existe.');
    }
    final status = rows.single['status'] as String?;
    final alreadyUsed =
        (Sqflite.firstIntValue(
              await executor.rawQuery(
                'SELECT COUNT(*) FROM applications WHERE plan_id=?',
                [planId],
              ),
            ) ??
            0) >
        0;
    if (alreadyUsed || !pendingPlanStatuses.contains(status)) {
      throw BusinessRuleException(
        'Este plan ya fue aplicado y no puede volver a aplicarse. '
        'Cree un plan nuevo si necesita repetir la aplicación.',
      );
    }
  }

  Future<int> confirmApplication(ApplicationDraft draft) async {
    if (draft.lines.isEmpty) {
      throw BusinessRuleException(
        'La aplicación necesita al menos un producto.',
      );
    }
    if (draft.lines.map((line) => line.productId).toSet().length !=
        draft.lines.length) {
      throw BusinessRuleException(
        'No repita productos dentro de la aplicación.',
      );
    }
    return _session.write((txn, context) async {
      _session.requireOwnerInPersonal(context, [
        draft.personId,
      ], 'En el modo individual la aplicación la realiza el titular.');
      await _session.requireOwnerFarmInPersonal(txn, context, draft.farmId);
      await _campaigns.ensureCampaignActive(txn, draft.campaignId);
      await _campaigns.ensureEffectiveDateInCampaign(
        txn,
        draft.campaignId,
        draft.appliedAt,
      );
      if (draft.planId != null) {
        await _ensurePlanNotApplied(txn, draft.planId!);
      }
      final day = localDay(draft.appliedAt);
      if (day == localDay(DateTime.now())) {
        return insertApplication(
          txn,
          draft,
          lotsFor: _fifoQueries.lotsAvailableNow,
        );
      }
      return insertApplication(
        txn,
        draft,
        lotsFor: (executor, productId, personId) =>
            _fifoQueries.lotsAvailableAt(executor, productId, personId, day),
        shortfall: (line, available) => _fifoQueries.historicalShortfall(
          txn,
          line,
          draft.personId,
          available,
          day,
        ),
      );
    });
  }

  /// Escribe una aplicación ya validada consumiendo de [lotsFor] (FIFO).
  Future<int> insertApplication(
    Transaction txn,
    ApplicationDraft draft, {
    required Future<List<Map<String, Object?>>> Function(
      DatabaseExecutor txn,
      int productId,
      int personId,
    )
    lotsFor,
    Future<BusinessRuleException> Function(
      ApplicationLineDraft line,
      int available,
    )?
    shortfall,
  }) async {
    final person = (await txn.query(
      'persons',
      where: 'id = ?',
      whereArgs: [draft.personId],
      limit: 1,
    )).single;
    final policy = person['settlement_policy']! as String;
    final applicationId = await txn.insert('applications', {
      'farm_id': draft.farmId,
      'person_id': draft.personId,
      'campaign_id': draft.campaignId,
      'plan_id': draft.planId,
      'applied_at': _session.date(draft.appliedAt),
      'status': 'CONFIRMED',
      'treated_area_m2': draft.treatedAreaM2 ?? draft.lines.first.treatedAreaM2,
      'notes': draft.notes,
    });
    var totalCost = 0;
    for (final line in draft.lines) {
      totalCost += await _insertApplicationLine(
        txn,
        applicationId,
        draft,
        line,
        lotsFor: lotsFor,
        shortfall: shortfall,
      );
    }
    await txn.update(
      'applications',
      {'total_cost_bob_minor': totalCost},
      where: 'id = ?',
      whereArgs: [applicationId],
    );
    if (policy == 'BY_ACTUAL_USAGE') {
      await txn.insert('account_transactions', {
        'person_id': draft.personId,
        'campaign_id': draft.campaignId,
        'transaction_date': _session.date(draft.appliedAt),
        'type': 'USAGE_CHARGE',
        'amount_bob_minor_signed': totalCost,
        'reference_type': 'APPLICATION',
        'reference_id': applicationId,
      });
    }
    if (draft.planId != null) {
      await txn.update(
        'application_plans',
        {'status': appliedPlanStatus},
        where: 'id=?',
        whereArgs: [draft.planId],
      );
    }
    return applicationId;
  }

  Future<int> _insertApplicationLine(
    Transaction txn,
    int applicationId,
    ApplicationDraft draft,
    ApplicationLineDraft line, {
    required Future<List<Map<String, Object?>>> Function(
      DatabaseExecutor txn,
      int productId,
      int personId,
    )
    lotsFor,
    Future<BusinessRuleException> Function(
      ApplicationLineDraft line,
      int available,
    )?
    shortfall,
  }) async {
    if (line.quantityBase <= 0) {
      throw BusinessRuleException(
        'La cantidad aplicada debe ser mayor a cero.',
      );
    }
    final lots = await lotsFor(txn, line.productId, draft.personId);
    final available = lots.fold<int>(
      0,
      (sum, row) => sum + (row['available']! as int),
    );
    if (available < line.quantityBase) {
      if (shortfall != null) throw await shortfall(line, available);
      throw BusinessRuleException(
        'Stock insuficiente para confirmar la aplicación.',
      );
    }
    final product = (await txn.query(
      'products',
      columns: ['unit'],
      where: 'id=?',
      whereArgs: [line.productId],
      limit: 1,
    )).single;
    final applicationItemId = await txn.insert('application_items', {
      'application_id': applicationId,
      'product_id': line.productId,
      'quantity_base': line.quantityBase,
      'cost_bob_minor': 0,
      'treated_area_m2': line.treatedAreaM2,
      'dose_base_per_ha': line.doseBasePerHa,
      'theoretical_quantity_base': line.theoreticalQuantityBase,
      'unit': product['unit'],
      'variance_quantity_base': line.theoreticalQuantityBase == null
          ? null
          : line.quantityBase - line.theoreticalQuantityBase!,
    });
    var lineCost = 0;
    for (final (:lot, :take) in fifoTakes(lots, line.quantityBase)) {
      final cost = costForBaseQuantity(
        take,
        lot['unit_cost_bob_minor_per_major_unit']! as int,
      );
      await txn.insert('application_consumptions', {
        'application_item_id': applicationItemId,
        'inventory_lot_id': lot['id'],
        'quantity_consumed_base': take,
        'cost_bob_minor': cost,
      });
      await txn.insert('inventory_movements', {
        'lot_id': lot['id'],
        'product_id': line.productId,
        'owner_person_id': draft.personId,
        'movement_date': _session.date(draft.appliedAt),
        'type': 'APPLICATION_OUT',
        'quantity_signed': -take,
        'reference_type': 'APPLICATION',
        'reference_id': applicationId,
      });
      lineCost += cost;
    }
    await txn.update(
      'application_items',
      {'cost_bob_minor': lineCost, 'fifo_estimated_cost_bob_minor': lineCost},
      where: 'id = ?',
      whereArgs: [applicationItemId],
    );
    return lineCost;
  }

  Future<List<Map<String, Object?>>> applications({
    int? campaignId,
    int? personId,
    int? farmId,
    int? productId,
    int? limit,
  }) => _queries.applications(
    campaignId: campaignId,
    personId: personId,
    farmId: farmId,
    productId: productId,
    limit: limit,
  );

  Future<List<Map<String, Object?>>> plans({
    int limit = 400,
    bool includeApplied = false,
  }) => _queries.plans(limit: limit, includeApplied: includeApplied);

  Future<List<Map<String, Object?>>> planForApplication(int planId) =>
      _queries.planForApplication(planId);

  Future<List<Map<String, Object?>>> farmLogbook(
    int farmId, {
    int? campaignId,
    int? productId,
  }) => _queries.farmLogbook(
    farmId,
    campaignId: campaignId,
    productId: productId,
  );

  Future<Map<String, Object?>> productStockInsight({
    required int personId,
    required int productId,
    required int campaignId,
  }) => _queries.productStockInsight(
    personId: personId,
    productId: productId,
    campaignId: campaignId,
  );

  Future<List<ApplicationLotPreview>> previewApplicationLots({
    required int personId,
    required int productId,
    required int quantityBase,
    required DateTime appliedAt,
  }) => _queries.previewApplicationLots(
    personId: personId,
    productId: productId,
    quantityBase: quantityBase,
    appliedAt: appliedAt,
  );

  Future<int> estimateFifoCost({
    required int personId,
    required int productId,
    required int quantityBase,
  }) => _queries.estimateFifoCost(
    personId: personId,
    productId: productId,
    quantityBase: quantityBase,
  );
}
