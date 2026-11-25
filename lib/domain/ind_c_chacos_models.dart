import 'operation_mode.dart';
import 'read_models.dart' show FarmCostRead, ProductCostRead;

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
  final int areaM2;
  final int ownerPersonId;
  final String ownerName;
  final bool active;
  final int applicationCount;
  final int appliedCostMinor;
  final int treatedAreaM2;
  final int applicationsWithTreatedArea;
  final int pendingPlanCount;

  bool get hasArea => areaM2 > 0;

  FarmCostRead get cost => FarmCostRead(
    farmId: farmId,
    farmName: name,
    ownerName: ownerName,
    areaM2: areaM2,
    totalCostBobMinor: appliedCostMinor,
    applicationCount: applicationCount,
  );

  int? get costPerHectareMinor => cost.costPerHectareMinor;

  factory IndCFarm.fromRow(Map<String, Object?> row) => IndCFarm(
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
  final List<IndCCampaign> campaigns;

  bool get personal => mode == OperationMode.personal;

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
  final IndCCampaign? campaign;
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
  final List<IndCApplication> applications;
  final List<IndCProductCost> products;
}

/// Lecturas del modo individual sobre chacos y costos para desacoplar la
/// capa de presentación de SQLite/sqflite.
abstract interface class IndCChacosGateway {
  Future<IndCScope> indCScope();
  Future<IndCChacos> indCChacos({
    int? campaignId,
    bool useActiveCampaign = false,
  });
  Future<({List<FarmCostRead> lines, bool ownerOnly})> farmCostLines({
    int? campaignId,
  });
  Future<({List<ProductCostRead> lines, bool ownerOnly})> productCostLines({
    int? campaignId,
  });
  Future<List<IndCProductCost>> indCProductCosts({
    int? campaignId,
    int? farmId,
  });
  Future<List<IndCCampaignCost>> indCCampaignCosts();
  Future<IndCChacoDetail?> indCChacoDetail(
    int farmId, {
    int? campaignId,
    bool useActiveCampaign = true,
  });
}
