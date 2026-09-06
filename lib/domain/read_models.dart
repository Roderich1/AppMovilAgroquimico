/// Modelos de lectura tipados (EVO-004).
///
/// Las escrituras ya estaban tipadas con los `Draft` de `models.dart`, pero las
/// consultas devolvían `Map<String, Object?>` y cada pantalla repetía los alias
/// SQL y los `as int` por clave. Un alias renombrado no rompía la compilación:
/// reventaba en tiempo de ejecución dentro de un widget, con un
/// `_TypeError: Null is not a subtype of int` que no dice ni qué columna ni de
/// qué consulta venía.
///
/// Aquí cada consulta crítica tiene un modelo inmutable y un mapper que valida
/// presencia y tipo de cada columna. Una fila inválida falla en el mapper, con
/// [RowMappingException] y contexto suficiente para arreglarla
/// (`EVO-004-REQ-006`).
///
/// **El SQL no cambia.** Estos modelos se montan sobre las consultas ya
/// probadas de `AgroRepository`; los adaptadores viven en
/// `data/typed_reads.dart`.
library;

import 'money.dart';

/// Una fila de SQLite no encaja en el modelo que la espera.
///
/// El mensaje nombra la consulta, la columna y el tipo esperado, y **nunca el
/// valor**: un importe, un teléfono o un nombre no tienen por qué acabar en un
/// registro o en un mensaje de pantalla (`09_SECURITY_AND_PRIVACY`).
class RowMappingException implements Exception {
  const RowMappingException(this.source, this.column, this.problem);

  /// Consulta de origen, p. ej. `settlements`.
  final String source;

  /// Columna o alias que falló.
  final String column;

  /// Qué pasó, sin incluir el valor.
  final String problem;

  String get message => 'Lectura "$source", columna "$column": $problem.';

  @override
  String toString() => message;
}

/// Acceso validado a una fila de SQLite.
///
/// Distingue tres fallos que antes eran el mismo `as int` en un widget:
/// la columna no existe, la columna es nula donde no puede serlo, y la columna
/// trae otro tipo.
class RowReader {
  const RowReader(this.row, this.source);

  final Map<String, Object?> row;
  final String source;

  Object? _cell(String column) {
    if (!row.containsKey(column)) {
      throw RowMappingException(source, column, 'la fila no trae esa columna');
    }
    return row[column];
  }

  int requireInt(String column) {
    final value = _cell(column);
    if (value == null) {
      throw RowMappingException(
        source,
        column,
        'se esperaba un entero y llegó nulo',
      );
    }
    if (value is int) return value;
    throw RowMappingException(
      source,
      column,
      'se esperaba un entero y llegó ${value.runtimeType}',
    );
  }

  int? optionalInt(String column) {
    final value = _cell(column);
    if (value == null) return null;
    if (value is int) return value;
    throw RowMappingException(
      source,
      column,
      'se esperaba un entero o nulo y llegó ${value.runtimeType}',
    );
  }

  String requireString(String column) {
    final value = _cell(column);
    if (value == null) {
      throw RowMappingException(
        source,
        column,
        'se esperaba un texto y llegó nulo',
      );
    }
    if (value is String) return value;
    throw RowMappingException(
      source,
      column,
      'se esperaba un texto y llegó ${value.runtimeType}',
    );
  }

  String? optionalString(String column) {
    final value = _cell(column);
    if (value == null) return null;
    if (value is String) return value;
    throw RowMappingException(
      source,
      column,
      'se esperaba un texto o nulo y llegó ${value.runtimeType}',
    );
  }
}

/// Campaña del catálogo. Fuente: `AgroRepository.campaigns()`.
class CampaignRead {
  const CampaignRead({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.status,
  });

  static const source = 'campaigns';

  final int id;
  final String name;
  final String startDate;

  /// Una campaña abierta no tiene fecha de fin.
  final String? endDate;
  final String status;

  bool get isActive => status == 'ACTIVE';

  factory CampaignRead.fromRow(Map<String, Object?> row) {
    final reader = RowReader(row, source);
    return CampaignRead(
      id: reader.requireInt('id'),
      name: reader.requireString('name'),
      startDate: reader.requireString('start_date'),
      endDate: reader.optionalString('end_date'),
      status: reader.requireString('status'),
    );
  }

  static List<CampaignRead> fromRows(List<Map<String, Object?>> rows) =>
      rows.map(CampaignRead.fromRow).toList(growable: false);
}

/// Persona activa del catálogo. Fuente: `AgroRepository.people()`.
class PersonRead {
  const PersonRead({
    required this.id,
    required this.name,
    required this.role,
    required this.phone,
  });

  static const source = 'people';

  final int id;
  final String name;
  final String role;

  /// El teléfono es opcional en el alta.
  final String? phone;

  factory PersonRead.fromRow(Map<String, Object?> row) {
    final reader = RowReader(row, source);
    return PersonRead(
      id: reader.requireInt('id'),
      name: reader.requireString('name'),
      role: reader.requireString('role'),
      phone: reader.optionalString('phone'),
    );
  }

  static List<PersonRead> fromRows(List<Map<String, Object?>> rows) =>
      rows.map(PersonRead.fromRow).toList(growable: false);
}

/// Línea del inventario global. Fuente: `AgroRepository.inventorySummary()`.
///
/// Todas las cantidades están en unidad base (×1000) y el valor en centavos.
class InventoryLineRead {
  const InventoryLineRead({
    required this.productId,
    required this.productName,
    required this.unit,
    required this.purchasedBase,
    required this.consumedBase,
    required this.availableBase,
    required this.committedBase,
    required this.projectedBase,
    required this.availableValueBobMinor,
    required this.peopleCount,
  });

  static const source = 'inventorySummary';

  final int productId;
  final String productName;

  /// `L` o `KG`.
  final String unit;
  final int purchasedBase;
  final int consumedBase;

  /// Stock físico.
  final int availableBase;

  /// Reservado por planes pendientes de la campaña activa.
  final int committedBase;

  /// `availableBase - committedBase`; puede ser negativo.
  final int projectedBase;
  final int availableValueBobMinor;
  final int peopleCount;

  factory InventoryLineRead.fromRow(Map<String, Object?> row) {
    final reader = RowReader(row, source);
    return InventoryLineRead(
      productId: reader.requireInt('product_id'),
      productName: reader.requireString('product_name'),
      unit: reader.requireString('unit'),
      purchasedBase: reader.requireInt('purchased_base'),
      consumedBase: reader.requireInt('consumed_base'),
      availableBase: reader.requireInt('available_base'),
      committedBase: reader.requireInt('committed_base'),
      projectedBase: reader.requireInt('projected_base'),
      availableValueBobMinor: reader.requireInt('available_value_bob_minor'),
      peopleCount: reader.requireInt('people_count'),
    );
  }

  static List<InventoryLineRead> fromRows(List<Map<String, Object?>> rows) =>
      rows.map(InventoryLineRead.fromRow).toList(growable: false);
}

/// Saldo de una persona. Fuente: `AgroRepository.settlements()`.
class SettlementRead {
  const SettlementRead({
    required this.personId,
    required this.name,
    required this.role,
    required this.balanceMinor,
    required this.chargesMinor,
    required this.paymentsMinor,
  });

  static const source = 'settlements';

  final int personId;
  final String name;
  final String role;

  /// Positivo = debe; negativo = a favor.
  final int balanceMinor;
  final int chargesMinor;

  /// Ya viene en positivo desde la consulta (`-SUM` de los asientos negativos).
  final int paymentsMinor;

  factory SettlementRead.fromRow(Map<String, Object?> row) {
    final reader = RowReader(row, source);
    return SettlementRead(
      personId: reader.requireInt('id'),
      name: reader.requireString('name'),
      role: reader.requireString('role'),
      balanceMinor: reader.requireInt('balance'),
      chargesMinor: reader.requireInt('charges'),
      paymentsMinor: reader.requireInt('payments'),
    );
  }

  static List<SettlementRead> fromRows(List<Map<String, Object?>> rows) =>
      rows.map(SettlementRead.fromRow).toList(growable: false);
}

/// Deudor del resumen de Inicio. Fuente: `AgroRepository.topSettlements()`.
///
/// Es una consulta distinta de `settlements`: no trae cargos ni pagos, así que
/// tiene su propio modelo en vez de dejar dos campos mintiendo a cero.
class TopSettlementRead {
  const TopSettlementRead({
    required this.personId,
    required this.name,
    required this.role,
    required this.balanceMinor,
  });

  static const source = 'topSettlements';

  final int personId;
  final String name;
  final String role;
  final int balanceMinor;

  factory TopSettlementRead.fromRow(Map<String, Object?> row) {
    final reader = RowReader(row, source);
    return TopSettlementRead(
      personId: reader.requireInt('id'),
      name: reader.requireString('name'),
      role: reader.requireString('role'),
      balanceMinor: reader.requireInt('balance'),
    );
  }

  static List<TopSettlementRead> fromRows(List<Map<String, Object?>> rows) =>
      rows.map(TopSettlementRead.fromRow).toList(growable: false);
}

/// Costo consumido por producto. Fuente: `AgroRepository.productCostReport()`.
class ProductCostRead {
  const ProductCostRead({
    required this.productId,
    required this.productName,
    required this.unit,
    required this.quantityBase,
    required this.totalCostBobMinor,
  });

  static const source = 'productCostReport';

  final int productId;
  final String productName;
  final String unit;
  final int quantityBase;
  final int totalCostBobMinor;

  factory ProductCostRead.fromRow(Map<String, Object?> row) {
    final reader = RowReader(row, source);
    return ProductCostRead(
      productId: reader.requireInt('id'),
      productName: reader.requireString('name'),
      unit: reader.requireString('unit'),
      quantityBase: reader.requireInt('quantity_base'),
      totalCostBobMinor: reader.requireInt('total_cost_bob_minor'),
    );
  }

  static List<ProductCostRead> fromRows(List<Map<String, Object?>> rows) =>
      rows.map(ProductCostRead.fromRow).toList(growable: false);
}

/// Costo por chaco. Fuente: `AgroRepository.farmCostReport()`.
class FarmCostRead {
  const FarmCostRead({
    required this.farmId,
    required this.farmName,
    required this.ownerName,
    required this.areaM2,
    required this.totalCostBobMinor,
  });

  static const source = 'farmCostReport';

  final int farmId;
  final String farmName;
  final String ownerName;
  final int areaM2;
  final int totalCostBobMinor;

  /// Costo por hectárea en centavos, con el mismo redondeo entero que usa la
  /// pantalla de Liquidación. `null` cuando no se puede calcular.
  ///
  /// El esquema declara `CHECK(area_m2 > 0)`, así que el divisor cero no
  /// debería existir; la guarda está porque un reporte no puede reventar por
  /// una fila anómala que la base antigua sí pudiera contener.
  int? get costPerHectareMinor {
    if (areaM2 <= 0 || totalCostBobMinor < 0) return null;
    return divideRoundedHalfUp(totalCostBobMinor * 10000, areaM2);
  }

  factory FarmCostRead.fromRow(Map<String, Object?> row) {
    final reader = RowReader(row, source);
    return FarmCostRead(
      farmId: reader.requireInt('id'),
      farmName: reader.requireString('name'),
      ownerName: reader.requireString('owner_name'),
      areaM2: reader.requireInt('area_m2'),
      totalCostBobMinor: reader.requireInt('total_cost_bob_minor'),
    );
  }

  static List<FarmCostRead> fromRows(List<Map<String, Object?>> rows) =>
      rows.map(FarmCostRead.fromRow).toList(growable: false);
}

/// Resumen de una campaña. Fuente: `AgroRepository.campaignCloseSummary()`.
class CampaignSummaryRead {
  const CampaignSummaryRead({
    required this.purchasesCount,
    required this.purchasesBobMinor,
    required this.applicationsCount,
    required this.applicationsBobMinor,
    required this.pendingPlans,
    required this.receivableBobMinor,
  });

  static const source = 'campaignCloseSummary';

  final int purchasesCount;
  final int purchasesBobMinor;
  final int applicationsCount;
  final int applicationsBobMinor;
  final int pendingPlans;
  final int receivableBobMinor;

  factory CampaignSummaryRead.fromRow(Map<String, Object?> row) {
    final reader = RowReader(row, source);
    return CampaignSummaryRead(
      purchasesCount: reader.requireInt('purchases_count'),
      purchasesBobMinor: reader.requireInt('purchases_bob_minor'),
      applicationsCount: reader.requireInt('applications_count'),
      applicationsBobMinor: reader.requireInt('applications_bob_minor'),
      pendingPlans: reader.requireInt('pending_plans'),
      receivableBobMinor: reader.requireInt('receivable_bob_minor'),
    );
  }
}

/// Saldos de una persona dentro de una campaña.
/// Fuente: `AgroRepository.personCampaignBalance()`.
class PersonCampaignBalanceRead {
  const PersonCampaignBalanceRead({
    required this.openingBalanceMinor,
    required this.campaignChargesMinor,
    required this.campaignPaymentsMinor,
    required this.totalBalanceMinor,
  });

  static const source = 'personCampaignBalance';

  /// Lo que arrastraba de campañas anteriores.
  final int openingBalanceMinor;
  final int campaignChargesMinor;
  final int campaignPaymentsMinor;
  final int totalBalanceMinor;

  factory PersonCampaignBalanceRead.fromRow(Map<String, Object?> row) {
    final reader = RowReader(row, source);
    return PersonCampaignBalanceRead(
      openingBalanceMinor: reader.requireInt('opening_balance'),
      campaignChargesMinor: reader.requireInt('campaign_charges'),
      campaignPaymentsMinor: reader.requireInt('campaign_payments'),
      totalBalanceMinor: reader.requireInt('total_balance'),
    );
  }
}

/// Movimiento del estado de cuenta.
/// Fuente: `AgroRepository.detailedStatement()`.
class StatementEntryRead {
  const StatementEntryRead({
    required this.id,
    required this.transactionDate,
    required this.type,
    required this.amountBobMinorSigned,
    required this.campaignId,
    required this.concept,
    required this.farmName,
    required this.notes,
  });

  static const source = 'detailedStatement';

  final int id;
  final String transactionDate;
  final String type;

  /// Positivo = cargo; negativo = pago o crédito.
  final int amountBobMinorSigned;

  /// Los adelantos sin campaña quedan fuera de toda campaña.
  final int? campaignId;

  /// `COALESCE(productos, producto, notas, tipo)`: la consulta garantiza un
  /// valor, pero se lee como opcional porque el último término es el tipo y no
  /// hay constraint que lo imponga.
  final String? concept;

  /// Sólo los cargos por consumo nombran un chaco.
  final String? farmName;
  final String? notes;

  /// Cargo: el importe cuando es positivo.
  int get chargeMinor => amountBobMinorSigned > 0 ? amountBobMinorSigned : 0;

  /// Crédito: el importe en positivo cuando el asiento es negativo.
  int get creditMinor => amountBobMinorSigned < 0 ? -amountBobMinorSigned : 0;

  factory StatementEntryRead.fromRow(Map<String, Object?> row) {
    final reader = RowReader(row, source);
    return StatementEntryRead(
      id: reader.requireInt('id'),
      transactionDate: reader.requireString('transaction_date'),
      type: reader.requireString('type'),
      amountBobMinorSigned: reader.requireInt('amount_bob_minor_signed'),
      campaignId: reader.optionalInt('campaign_id'),
      concept: reader.optionalString('concept'),
      farmName: reader.optionalString('farm_name'),
      notes: reader.optionalString('notes'),
    );
  }

  static List<StatementEntryRead> fromRows(List<Map<String, Object?>> rows) =>
      rows.map(StatementEntryRead.fromRow).toList(growable: false);
}

/// Movimiento con su saldo acumulado.
///
/// El acumulado se calculaba por separado en `settlements_screen` y en
/// `person_detail_screen`, cada uno con su propio bucle. Es la misma regla:
/// vive una sola vez y sobre enteros.
class StatementLine {
  const StatementLine({required this.entry, required this.balanceMinor});

  final StatementEntryRead entry;

  /// Saldo después de aplicar [entry].
  final int balanceMinor;

  /// Recorre [entries] en orden acumulando desde [openingMinor].
  static List<StatementLine> runningBalance(
    List<StatementEntryRead> entries, {
    int openingMinor = 0,
  }) {
    var balance = openingMinor;
    final lines = <StatementLine>[];
    for (final entry in entries) {
      balance += entry.amountBobMinorSigned;
      lines.add(StatementLine(entry: entry, balanceMinor: balance));
    }
    return List.unmodifiable(lines);
  }
}
