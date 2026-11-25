// Modo individual — lecturas de «Chacos» (láminas I-40 a I-43, sesión C,
// 2026-11-13). Sólo SELECT: ninguna escritura ni regla nueva.
//
// Criterios, los mismos de los informes existentes:
// * Costo aplicado de un chaco = Σ `applications.total_cost_bob_minor` de las
//   aplicaciones no revertidas (`reversed_at IS NULL`) del alcance, igual que
//   `AgroRepository.farmCostReport` (y su exportación «Costo por chaco»).
// * Costo por producto = Σ `application_items.cost_bob_minor` de esas
//   aplicaciones, igual que `productCostReport`; la cantidad se suma por
//   producto, y cada producto tiene una sola unidad (L o kg).
// * Costo por hectárea = `FarmCostRead.costPerHectareMinor`: costo aplicado
//   del alcance ÷ superficie del chaco (`farms.area_m2`). Nunca se divide por
//   la superficie tratada.
// * Alcance de personas: en modo individual, sólo los chacos del titular
//   vigente (`owner_bindings`), como `farmsAndContext`. En el modo con varias
//   personas, todos.
// * En modo individual, las exportaciones «Costo por chaco» y «Costo por
//   producto» salen de `farmCostLines` y `productCostLines`, que usan
//   `indCChacos` e `indCProductCosts` (decisión C del autor, 2026-11-13):
//   mismas filas, filtros y cifras que «Costos». El historial de terceros
//   sigue en la base y se exporta en el modo con varias personas.
import 'package:sqflite/sqflite.dart';

import '../domain/ind_c_chacos_models.dart';
import '../domain/operation_mode.dart';
import '../domain/read_models.dart' show FarmCostRead, ProductCostRead;
import 'agro_repository.dart';
import 'app_database.dart';
import 'typed_reads.dart';

export '../domain/ind_c_chacos_models.dart';

extension IndCChacosReads on AgroRepository {
  Future<Database> get _indDb => appDatabase.database;

  Future<IndCScope> indCScope() async => _scope(await _indDb);

  Future<IndCScope> _scope(DatabaseExecutor db) async {
    final rows = await db.rawQuery(
      'SELECT (SELECT value FROM app_settings WHERE key=?) context_mode, '
      '(SELECT person_id FROM owner_bindings WHERE ended_at IS NULL) '
      'context_owner, c.id, c.name, c.status FROM (SELECT 1) '
      'LEFT JOIN campaigns c ORDER BY c.start_date DESC, c.id DESC',
      [AppDatabase.operationModeKey],
    );
    return IndCScope(
      mode: OperationMode.fromCode(rows.first['context_mode'] as String?),
      ownerPersonId: rows.first['context_owner'] as int?,
      campaigns: [
        for (final row in rows)
          if (row['id'] != null)
            (
              id: row['id']! as int,
              name: row['name']! as String,
              status: row['status']! as String,
            ),
      ],
    );
  }

  /// Chacos con sus cifras. Con [campaignId] nulo y [useActiveCampaign], el
  /// alcance es la campaña activa (o todas si no hay activa).
  Future<IndCChacos> indCChacos({
    int? campaignId,
    bool useActiveCampaign = false,
  }) async {
    final db = await _indDb;
    final scope = await _scope(db);
    final campaign = useActiveCampaign && campaignId == null
        ? scope.activeCampaign
        : scope.campaign(campaignId);
    final farms = await _farms(db, scope, campaign?.id);
    return IndCChacos(
      scope: scope,
      campaign: campaign,
      farms: [
        for (final farm in farms)
          if (farm.active || farm.applicationCount > 0) farm,
      ],
    );
  }

  /// Líneas de «Costo por chaco» (exportación y Personas › Costos). En modo
  /// individual son los chacos de [indCChacos] con el mismo filtro de
  /// campaña: los del titular, sin los chacos de terceros del historial
  /// (`ownerOnly`). En el modo con varias personas, `farmCostReport` sin
  /// cambios. Ninguna de las dos recalcula costos: suman los costos ya
  /// guardados en `applications.total_cost_bob_minor`.
  Future<({List<FarmCostRead> lines, bool ownerOnly})> farmCostLines({
    int? campaignId,
  }) async {
    if (!(await indCScope()).personal) {
      return (
        lines: await farmCostReportTyped(campaignId: campaignId),
        ownerOnly: false,
      );
    }
    final chacos = await indCChacos(campaignId: campaignId);
    return (
      lines: [for (final farm in chacos.farms) farm.cost],
      ownerOnly: true,
    );
  }

  /// Líneas de «Costo por producto» (exportación y Personas › Costos), con
  /// el mismo criterio que [farmCostLines]: en modo individual, las de
  /// [indCProductCosts] (productos aplicados en chacos del titular, con el
  /// mismo filtro de campaña; `ownerOnly`); en el modo con varias personas,
  /// `productCostReport` sin cambios. Suman los costos guardados en
  /// `application_items.cost_bob_minor`.
  Future<({List<ProductCostRead> lines, bool ownerOnly})> productCostLines({
    int? campaignId,
  }) async {
    if (!(await indCScope()).personal) {
      return (
        lines: await productCostReportTyped(campaignId: campaignId),
        ownerOnly: false,
      );
    }
    return (
      lines: [
        for (final row in await indCProductCosts(campaignId: campaignId))
          ProductCostRead(
            productId: row.productId,
            productName: row.name,
            unit: row.unit,
            quantityBase: row.quantityBase,
            totalCostBobMinor: row.costMinor,
          ),
      ],
      ownerOnly: true,
    );
  }

  Future<List<IndCFarm>> _farms(
    DatabaseExecutor db,
    IndCScope scope,
    int? campaignId, {
    int? farmId,
  }) async {
    final app = campaignId == null ? '' : 'AND a.campaign_id=$campaignId';
    final plan = campaignId == null ? '' : 'AND pl.campaign_id=$campaignId';
    final pending = AgroRepository.pendingPlanStatuses
        .map((status) => "'$status'")
        .join(',');
    final where = <String>[
      if (scope.ownerFilter != null) 'f.owner_person_id=${scope.ownerFilter}',
      if (farmId != null) 'f.id=$farmId',
    ];
    final rows = await db.rawQuery('''
      SELECT f.id, f.name, f.area_m2, f.owner_person_id, f.active,
        p.name owner_name,
        (SELECT COUNT(*) FROM applications a WHERE a.farm_id=f.id
          AND a.reversed_at IS NULL $app) application_count,
        (SELECT COALESCE(SUM(a.total_cost_bob_minor),0) FROM applications a
          WHERE a.farm_id=f.id AND a.reversed_at IS NULL $app) applied_cost,
        (SELECT COALESCE(SUM(a.treated_area_m2),0) FROM applications a
          WHERE a.farm_id=f.id AND a.reversed_at IS NULL $app) treated_sum,
        (SELECT COUNT(a.treated_area_m2) FROM applications a
          WHERE a.farm_id=f.id AND a.reversed_at IS NULL $app) treated_count,
        (SELECT COUNT(*) FROM application_plans pl WHERE pl.farm_id=f.id
          AND pl.status IN ($pending) $plan) pending_plans
      FROM farms f JOIN persons p ON p.id=f.owner_person_id
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY f.name COLLATE NOCASE, f.id''');
    return rows.map(IndCFarm.fromRow).toList(growable: false);
  }

  /// Costo por producto del alcance (pestaña «Por producto» y «Productos
  /// utilizados» de un chaco).
  Future<List<IndCProductCost>> indCProductCosts({
    int? campaignId,
    int? farmId,
  }) async {
    final db = await _indDb;
    return _productCosts(db, await _scope(db), campaignId, farmId: farmId);
  }

  Future<List<IndCProductCost>> _productCosts(
    DatabaseExecutor db,
    IndCScope scope,
    int? campaignId, {
    int? farmId,
  }) async {
    final where = <String>[
      'a.reversed_at IS NULL',
      if (campaignId != null) 'a.campaign_id=$campaignId',
      if (farmId != null) 'a.farm_id=$farmId',
      if (scope.ownerFilter != null) 'f.owner_person_id=${scope.ownerFilter}',
    ];
    final rows = await db.rawQuery('''
      SELECT pr.id, pr.name, pr.unit,
        COALESCE(SUM(i.quantity_base),0) quantity_base,
        COALESCE(SUM(i.cost_bob_minor),0) cost,
        COUNT(DISTINCT a.id) application_count
      FROM application_items i JOIN applications a ON a.id=i.application_id
      JOIN farms f ON f.id=a.farm_id JOIN products pr ON pr.id=i.product_id
      WHERE ${where.join(' AND ')}
      GROUP BY pr.id ORDER BY cost DESC, pr.name COLLATE NOCASE''');
    return [
      for (final row in rows)
        IndCProductCost(
          productId: row['id']! as int,
          name: row['name']! as String,
          unit: row['unit']! as String,
          quantityBase: row['quantity_base']! as int,
          costMinor: row['cost']! as int,
          applicationCount: row['application_count']! as int,
        ),
    ];
  }

  /// Costo aplicado por campaña (pestaña «Por campaña»), de la más reciente
  /// a la más antigua; las campañas sin aplicaciones también figuran.
  Future<List<IndCCampaignCost>> indCCampaignCosts() async {
    final db = await _indDb;
    final scope = await _scope(db);
    final owner = scope.ownerFilter == null
        ? ''
        : 'AND a.farm_id IN (SELECT id FROM farms '
              'WHERE owner_person_id=${scope.ownerFilter})';
    final rows = await db.rawQuery('''
      SELECT c.id, c.name, c.status, COUNT(a.id) application_count,
        COALESCE(SUM(a.total_cost_bob_minor),0) cost
      FROM campaigns c LEFT JOIN applications a ON a.campaign_id=c.id
        AND a.reversed_at IS NULL $owner
      GROUP BY c.id ORDER BY c.start_date DESC, c.id DESC''');
    return [
      for (final row in rows)
        IndCCampaignCost(
          campaign: (
            id: row['id']! as int,
            name: row['name']! as String,
            status: row['status']! as String,
          ),
          applicationCount: row['application_count']! as int,
          costMinor: row['cost']! as int,
        ),
    ];
  }

  /// Detalle de un chaco (I-41). `null` si el chaco no existe o, en modo
  /// individual, no es del titular.
  Future<IndCChacoDetail?> indCChacoDetail(
    int farmId, {
    int? campaignId,
    bool useActiveCampaign = true,
  }) async {
    final db = await _indDb;
    final scope = await _scope(db);
    final campaign = useActiveCampaign && campaignId == null
        ? scope.activeCampaign
        : scope.campaign(campaignId);
    final farms = await _farms(db, scope, campaign?.id, farmId: farmId);
    if (farms.isEmpty) return null;
    final c = campaign?.id;
    final pending = AgroRepository.pendingPlanStatuses
        .map((status) => "'$status'")
        .join(',');
    final planRows = await db.rawQuery(
      '''
      SELECT pl.id, pl.planned_date, pl.status, pr.name, pr.unit,
        i.required_quantity_base, i.area_m2
      FROM application_plans pl JOIN application_plan_items i ON i.plan_id=pl.id
      JOIN products pr ON pr.id=i.product_id
      WHERE pl.farm_id=? AND pl.status IN ($pending)
        ${c == null ? '' : 'AND pl.campaign_id=$c'}
      ORDER BY pl.planned_date IS NULL, pl.planned_date, pl.id, i.id''',
      [farmId],
    );
    final plans = <int, IndCPlan>{};
    for (final row in planRows) {
      final id = row['id']! as int;
      final plan = plans.putIfAbsent(
        id,
        () => IndCPlan(
          id: id,
          plannedDate: row['planned_date'] as String?,
          status: row['status']! as String,
          items: [],
        ),
      );
      plan.items.add((
        name: row['name']! as String,
        quantityBase: row['required_quantity_base']! as int,
        unit: row['unit']! as String,
        areaM2: row['area_m2']! as int,
      ));
    }
    final appRows = await db.rawQuery(
      '''
      SELECT a.id, a.applied_at, a.status, a.reversed_at, a.treated_area_m2,
        a.total_cost_bob_minor, c.name campaign_name, pr.name product_name,
        pr.unit, i.quantity_base
      FROM applications a JOIN campaigns c ON c.id=a.campaign_id
      LEFT JOIN application_items i ON i.application_id=a.id
      LEFT JOIN products pr ON pr.id=i.product_id
      WHERE a.farm_id=? ${c == null ? '' : 'AND a.campaign_id=$c'}
      ORDER BY a.applied_at DESC, a.id DESC, i.id''',
      [farmId],
    );
    final applications = <int, IndCApplication>{};
    for (final row in appRows) {
      final id = row['id']! as int;
      final application = applications.putIfAbsent(
        id,
        () => IndCApplication(
          id: id,
          appliedAt: row['applied_at']! as String,
          campaignName: row['campaign_name']! as String,
          treatedAreaM2: row['treated_area_m2'] as int?,
          costMinor: row['total_cost_bob_minor'] as int? ?? 0,
          reversed: row['reversed_at'] != null,
          status: row['status']! as String,
          items: [],
        ),
      );
      if (row['product_name'] != null) {
        application.items.add((
          name: row['product_name']! as String,
          quantityBase: row['quantity_base']! as int,
          unit: row['unit']! as String,
        ));
      }
    }
    return IndCChacoDetail(
      scope: scope,
      campaign: campaign,
      farm: farms.single,
      plans: plans.values.toList(growable: false),
      applications: applications.values.toList(growable: false),
      products: await _productCosts(db, scope, c, farmId: farmId),
    );
  }
}

/// Adaptador concreto de [IndCChacosGateway] sobre [AgroRepository].
class DataIndCChacosGateway implements IndCChacosGateway {
  const DataIndCChacosGateway(this._repo);

  final AgroRepository _repo;

  @override
  Future<IndCScope> indCScope() => _repo.indCScope();

  @override
  Future<IndCChacos> indCChacos({
    int? campaignId,
    bool useActiveCampaign = false,
  }) => _repo.indCChacos(
    campaignId: campaignId,
    useActiveCampaign: useActiveCampaign,
  );

  @override
  Future<({List<FarmCostRead> lines, bool ownerOnly})> farmCostLines({
    int? campaignId,
  }) => _repo.farmCostLines(campaignId: campaignId);

  @override
  Future<({List<ProductCostRead> lines, bool ownerOnly})> productCostLines({
    int? campaignId,
  }) => _repo.productCostLines(campaignId: campaignId);

  @override
  Future<List<IndCProductCost>> indCProductCosts({
    int? campaignId,
    int? farmId,
  }) => _repo.indCProductCosts(campaignId: campaignId, farmId: farmId);

  @override
  Future<List<IndCCampaignCost>> indCCampaignCosts() =>
      _repo.indCCampaignCosts();

  @override
  Future<IndCChacoDetail?> indCChacoDetail(
    int farmId, {
    int? campaignId,
    bool useActiveCampaign = true,
  }) => _repo.indCChacoDetail(
    farmId,
    campaignId: campaignId,
    useActiveCampaign: useActiveCampaign,
  );
}
