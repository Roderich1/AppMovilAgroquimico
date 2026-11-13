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
import 'package:sqflite/sqflite.dart';

import '../domain/operation_mode.dart';
import '../domain/read_models.dart' show FarmCostRead;
import 'agro_repository.dart';
import 'app_database.dart';

/// Campaña del alcance; `null` = todas las campañas.
typedef IndCCampaign = ({int id, String name, String status});

/// Un chaco con sus cifras en el alcance elegido.
class IndCFarm {
  const IndCFarm({
    required this.farmId,
    required this.name,
    required this.areaM2,
    required this.ownerPersonId,
    required this.ownerName,
    required this.active,
    required this.applicationCount,
    required this.appliedCostMinor,
    required this.treatedAreaM2,
    required this.applicationsWithTreatedArea,
    required this.pendingPlanCount,
  });

  final int farmId;
  final String name;

  /// Superficie del chaco en m². El esquema exige `> 0`; si una base antigua
  /// trajera un valor no positivo, se trata como «falta la superficie».
  final int areaM2;
  final int ownerPersonId;
  final String ownerName;
  final bool active;

  /// Aplicaciones no revertidas en el alcance.
  final int applicationCount;
  final int appliedCostMinor;

  /// Superficie tratada sumada de las aplicaciones del alcance que la tienen
  /// registrada ([applicationsWithTreatedArea] de [applicationCount]).
  final int treatedAreaM2;
  final int applicationsWithTreatedArea;

  /// Planes por hacer (borrador o planificado) en el alcance.
  final int pendingPlanCount;

  bool get hasArea => areaM2 > 0;

  /// Para reutilizar el cálculo del costo por hectárea del informe.
  FarmCostRead get cost => FarmCostRead(
    farmId: farmId,
    farmName: name,
    ownerName: ownerName,
    areaM2: areaM2,
    totalCostBobMinor: appliedCostMinor,
  );

  /// `null` = «No disponible» (sin superficie o sin aplicaciones).
  int? get costPerHectareMinor =>
      applicationCount == 0 ? null : cost.costPerHectareMinor;

  factory IndCFarm._fromRow(Map<String, Object?> row) => IndCFarm(
    farmId: row['id']! as int,
    name: row['name']! as String,
    areaM2: (row['area_m2'] as int?) ?? 0,
    ownerPersonId: row['owner_person_id']! as int,
    ownerName: row['owner_name']! as String,
    active: row['active'] == 1,
    applicationCount: row['application_count']! as int,
    appliedCostMinor: row['applied_cost']! as int,
    treatedAreaM2: row['treated_sum']! as int,
    applicationsWithTreatedArea: row['treated_count']! as int,
    pendingPlanCount: row['pending_plans']! as int,
  );
}

/// Costo de un producto en el alcance.
class IndCProductCost {
  const IndCProductCost({
    required this.productId,
    required this.name,
    required this.unit,
    required this.quantityBase,
    required this.costMinor,
    required this.applicationCount,
  });
  final int productId;
  final String name;
  final String unit;
  final int quantityBase;
  final int costMinor;
  final int applicationCount;
}

/// Costo aplicado de una campaña (pestaña «Por campaña»).
class IndCCampaignCost {
  const IndCCampaignCost({
    required this.campaign,
    required this.applicationCount,
    required this.costMinor,
  });
  final IndCCampaign campaign;
  final int applicationCount;
  final int costMinor;
}

/// Modalidad, titular, campañas y la campaña activa, en una consulta.
class IndCScope {
  const IndCScope({
    required this.mode,
    required this.ownerPersonId,
    required this.campaigns,
  });
  final OperationMode mode;
  final int? ownerPersonId;

  /// De la más reciente a la más antigua.
  final List<IndCCampaign> campaigns;

  bool get personal => mode == OperationMode.personal;

  /// Dueño por el que se filtran los chacos: el titular en modo individual.
  int? get ownerFilter => personal ? ownerPersonId : null;

  IndCCampaign? get activeCampaign =>
      campaigns.where((c) => c.status == 'ACTIVE').firstOrNull;

  IndCCampaign? campaign(int? id) =>
      id == null ? null : campaigns.where((c) => c.id == id).firstOrNull;
}

/// Lista de chacos (I-40) y pestaña «Por chaco» (I-42).
class IndCChacos {
  const IndCChacos({
    required this.scope,
    required this.campaign,
    required this.farms,
  });
  final IndCScope scope;

  /// Alcance de las cifras; `null` = todas las campañas.
  final IndCCampaign? campaign;

  /// Chacos activos y, además, los archivados con aplicaciones en el alcance
  /// (su costo cuenta: archivar no borra el historial).
  final List<IndCFarm> farms;

  List<IndCFarm> get activeFarms => [
    for (final farm in farms)
      if (farm.active) farm,
  ];

  int get appliedCostMinor =>
      farms.fold(0, (sum, farm) => sum + farm.appliedCostMinor);
  int get applicationCount =>
      farms.fold(0, (sum, farm) => sum + farm.applicationCount);
}

/// Una aplicación del detalle (I-41).
class IndCApplication {
  const IndCApplication({
    required this.id,
    required this.appliedAt,
    required this.campaignName,
    required this.treatedAreaM2,
    required this.costMinor,
    required this.reversed,
    required this.status,
    required this.items,
  });
  final int id;
  final String appliedAt;
  final String campaignName;
  final int? treatedAreaM2;
  final int costMinor;
  final bool reversed;
  final String status;

  /// Producto, cantidad y unidad de cada línea.
  final List<({String name, int quantityBase, String unit})> items;
}

/// Un plan por hacer del detalle (I-41).
class IndCPlan {
  const IndCPlan({
    required this.id,
    required this.plannedDate,
    required this.status,
    required this.items,
  });
  final int id;
  final String? plannedDate;
  final String status;
  final List<({String name, int quantityBase, String unit, int areaM2})> items;
}

/// Detalle de un chaco en un alcance (I-41).
class IndCChacoDetail {
  const IndCChacoDetail({
    required this.scope,
    required this.campaign,
    required this.farm,
    required this.plans,
    required this.applications,
    required this.products,
  });
  final IndCScope scope;
  final IndCCampaign? campaign;
  final IndCFarm farm;
  final List<IndCPlan> plans;

  /// Del alcance, también las revertidas (se muestran como tales y no suman).
  final List<IndCApplication> applications;
  final List<IndCProductCost> products;
}

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
    return rows.map(IndCFarm._fromRow).toList(growable: false);
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
