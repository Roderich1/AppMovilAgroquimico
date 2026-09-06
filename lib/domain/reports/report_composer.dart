/// Composición de los cinco reportes obligatorios de EVOLUTION-2.
///
/// El compositor recibe **modelos tipados**, nunca mapas SQL, y devuelve un
/// [ReportTable]. No sabe de SQLite, de Riverpod, de widgets ni de archivos:
/// eso lo hace el servicio de exportación, que es quien lee y quien escribe.
///
/// Los totales se suman aquí, una sola vez y con enteros, para que CSV y PDF no
/// puedan discrepar.
library;

import '../labels.dart';
import '../read_models.dart';
import 'report_table.dart';

/// Los cinco reportes exportables.
enum ReportKind {
  inventory,
  productCost,
  farmCost,
  campaignSummary,
  accountStatement,
}

extension ReportKindInfo on ReportKind {
  String get label => switch (this) {
    ReportKind.inventory => 'Inventario',
    ReportKind.productCost => 'Costo por producto',
    ReportKind.farmCost => 'Costo por chaco',
    ReportKind.campaignSummary => 'Resumen de campaña',
    ReportKind.accountStatement => 'Estado de cuenta',
  };

  String get description => switch (this) {
    ReportKind.inventory =>
      'Stock físico, comprometido y proyectado, con su valor.',
    ReportKind.productCost => 'Cantidad y costo consumidos por producto.',
    ReportKind.farmCost => 'Costo total y por hectárea de cada chaco.',
    ReportKind.campaignSummary =>
      'Compras, aplicaciones, planes y cuentas de una campaña.',
    ReportKind.accountStatement =>
      'Movimientos de una persona con su saldo acumulado.',
  };

  /// Base del nombre de archivo, sin extensión ni fecha.
  String get fileBaseName => switch (this) {
    ReportKind.inventory => 'inventario',
    ReportKind.productCost => 'costo-por-producto',
    ReportKind.farmCost => 'costo-por-chaco',
    ReportKind.campaignSummary => 'resumen-de-campana',
    ReportKind.accountStatement => 'estado-de-cuenta',
  };

  /// La campaña es obligatoria en el resumen de campaña.
  bool get requiresCampaign => this == ReportKind.campaignSummary;

  /// El estado de cuenta necesita saber de quién.
  bool get requiresPerson => this == ReportKind.accountStatement;

  /// Los reportes que admiten filtrar por campaña o ver todas.
  bool get supportsCampaignFilter => switch (this) {
    ReportKind.productCost ||
    ReportKind.farmCost ||
    ReportKind.campaignSummary ||
    ReportKind.accountStatement => true,
    ReportKind.inventory => false,
  };
}

/// Reporte al que apunta un enlace de navegación, o `null` si no lo nombra.
///
/// Vive junto al enum para que una ruta nunca pueda referirse a un reporte que
/// no existe.
ReportKind? reportKindFromRoute(String? value) {
  if (value == null) return null;
  for (final kind in ReportKind.values) {
    if (kind.name == value) return kind;
  }
  return null;
}

/// Texto del filtro de campaña, con el mismo criterio en los cinco reportes.
String campaignFilterValue(String? campaignName) =>
    campaignName ?? 'Todas las campañas';

class ReportComposer {
  const ReportComposer();

  /// Inventario global: físico, comprometido, proyectado y valor.
  ///
  /// No se filtra por campaña: el stock es un hecho del almacén, no de un
  /// periodo contable.
  ReportTable inventory({
    required List<InventoryLineRead> lines,
    required DateTime generatedAt,
  }) {
    var totalValue = 0;
    final rows = <List<ReportCell>>[];
    for (final line in lines) {
      totalValue += line.availableValueBobMinor;
      rows.add([
        ReportText(line.productName),
        ReportText(line.unit),
        ReportQuantity(line.availableBase),
        ReportQuantity(line.committedBase),
        ReportQuantity(line.projectedBase),
        ReportMoney(line.availableValueBobMinor),
      ]);
    }
    return ReportTable(
      title: ReportKind.inventory.label,
      generatedAt: generatedAt,
      filters: const [ReportFilter('Alcance', 'Inventario global')],
      columns: const [
        ReportColumn('Producto', weight: 3),
        ReportColumn('Unidad'),
        ReportColumn('Físico', numeric: true, weight: 1.6),
        ReportColumn('Comprometido', numeric: true, weight: 1.8),
        ReportColumn('Proyectado', numeric: true, weight: 1.6),
        ReportColumn('Valor (Bs)', numeric: true, weight: 1.8),
      ],
      rows: rows,
      totals: [ReportTotal('Valor total (Bs)', ReportMoney(totalValue))],
      emptyMessage: 'No hay productos registrados.',
    );
  }

  /// Costo consumido por producto, opcionalmente de una campaña.
  ReportTable productCost({
    required List<ProductCostRead> lines,
    required DateTime generatedAt,
    String? campaignName,
  }) {
    var totalCost = 0;
    final rows = <List<ReportCell>>[];
    for (final line in lines) {
      totalCost += line.totalCostBobMinor;
      rows.add([
        ReportText(line.productName),
        ReportQuantity(line.quantityBase),
        ReportText(line.unit),
        ReportMoney(line.totalCostBobMinor),
      ]);
    }
    return ReportTable(
      title: ReportKind.productCost.label,
      generatedAt: generatedAt,
      filters: [ReportFilter('Campaña', campaignFilterValue(campaignName))],
      columns: const [
        ReportColumn('Producto', weight: 3),
        ReportColumn('Cantidad', numeric: true, weight: 1.6),
        ReportColumn('Unidad'),
        ReportColumn('Costo (Bs)', numeric: true, weight: 1.8),
      ],
      rows: rows,
      totals: [ReportTotal('Costo total (Bs)', ReportMoney(totalCost))],
      emptyMessage: 'No hay productos registrados.',
    );
  }

  /// Costo por chaco y por hectárea, opcionalmente de una campaña.
  ReportTable farmCost({
    required List<FarmCostRead> lines,
    required DateTime generatedAt,
    String? campaignName,
  }) {
    var totalCost = 0;
    final rows = <List<ReportCell>>[];
    for (final line in lines) {
      totalCost += line.totalCostBobMinor;
      final perHectare = line.costPerHectareMinor;
      rows.add([
        ReportText(line.farmName),
        ReportText(line.ownerName),
        ReportArea(line.areaM2),
        ReportMoney(line.totalCostBobMinor),
        // Un chaco sin superficie utilizable deja la celda vacía en vez de
        // inventar un cero que se leería como "no costó nada por hectárea".
        perHectare == null ? const ReportBlank() : ReportMoney(perHectare),
      ]);
    }
    return ReportTable(
      title: ReportKind.farmCost.label,
      generatedAt: generatedAt,
      filters: [ReportFilter('Campaña', campaignFilterValue(campaignName))],
      columns: const [
        ReportColumn('Chaco', weight: 2.6),
        ReportColumn('Propietario', weight: 2.4),
        ReportColumn('Área (ha)', numeric: true, weight: 1.4),
        ReportColumn('Costo (Bs)', numeric: true, weight: 1.8),
        ReportColumn('Costo/ha (Bs)', numeric: true, weight: 1.8),
      ],
      rows: rows,
      totals: [ReportTotal('Costo total (Bs)', ReportMoney(totalCost))],
      emptyMessage: 'No hay chacos registrados.',
    );
  }

  /// Resumen de una campaña. La campaña es obligatoria.
  ///
  /// Cantidad e importe van en columnas distintas en vez de compartir una
  /// columna "valor": mezclar conteos e importes en la misma columna deja un
  /// CSV que ninguna hoja de cálculo puede tipar.
  ReportTable campaignSummary({
    required CampaignSummaryRead summary,
    required String campaignName,
    required DateTime generatedAt,
  }) => ReportTable(
    title: ReportKind.campaignSummary.label,
    generatedAt: generatedAt,
    filters: [ReportFilter('Campaña', campaignName)],
    columns: const [
      ReportColumn('Concepto', weight: 3),
      ReportColumn('Cantidad', numeric: true, weight: 1.4),
      ReportColumn('Importe (Bs)', numeric: true, weight: 1.8),
    ],
    rows: [
      [
        const ReportText('Compras registradas'),
        ReportCount(summary.purchasesCount),
        ReportMoney(summary.purchasesBobMinor),
      ],
      [
        const ReportText('Aplicaciones registradas'),
        ReportCount(summary.applicationsCount),
        ReportMoney(summary.applicationsBobMinor),
      ],
      [
        const ReportText('Planes pendientes'),
        ReportCount(summary.pendingPlans),
        const ReportBlank(),
      ],
      [
        const ReportText('Saldo por cobrar'),
        const ReportBlank(),
        ReportMoney(summary.receivableBobMinor),
      ],
    ],
    totals: [
      ReportTotal('Compras (Bs)', ReportMoney(summary.purchasesBobMinor)),
      ReportTotal(
        'Aplicaciones (Bs)',
        ReportMoney(summary.applicationsBobMinor),
      ),
      ReportTotal(
        'Saldo por cobrar (Bs)',
        ReportMoney(summary.receivableBobMinor),
      ),
    ],
  );

  /// Estado de cuenta de una persona, con saldo acumulado.
  ///
  /// Cuando hay campaña seleccionada, [campaignBalance] aporta el saldo inicial
  /// y el acumulado arranca de ahí, igual que el diálogo de Liquidación.
  ReportTable accountStatement({
    required String personName,
    required List<StatementEntryRead> entries,
    required DateTime generatedAt,
    PersonCampaignBalanceRead? campaignBalance,
    String? campaignName,
  }) {
    final opening = campaignBalance?.openingBalanceMinor ?? 0;
    final lines = StatementLine.runningBalance(entries, openingMinor: opening);

    var charges = 0;
    var credits = 0;
    final rows = <List<ReportCell>>[];

    if (campaignBalance != null) {
      rows.add([
        const ReportBlank(),
        const ReportText('Saldo inicial de campaña'),
        const ReportBlank(),
        const ReportBlank(),
        const ReportBlank(),
        ReportMoney(opening),
      ]);
    }

    for (final line in lines) {
      final entry = line.entry;
      charges += entry.chargeMinor;
      credits += entry.creditMinor;
      rows.add([
        ReportDate(entry.transactionDate),
        ReportText(conceptLabel(entry.concept)),
        ReportText(entry.farmName ?? ''),
        entry.chargeMinor == 0
            ? const ReportBlank()
            : ReportMoney(entry.chargeMinor),
        entry.creditMinor == 0
            ? const ReportBlank()
            : ReportMoney(entry.creditMinor),
        ReportMoney(line.balanceMinor),
      ]);
    }

    final closing = lines.isEmpty ? opening : lines.last.balanceMinor;

    return ReportTable(
      title: ReportKind.accountStatement.label,
      generatedAt: generatedAt,
      filters: [
        ReportFilter('Persona', personName),
        ReportFilter('Campaña', campaignFilterValue(campaignName)),
      ],
      columns: const [
        ReportColumn('Fecha', weight: 1.4),
        ReportColumn('Concepto', weight: 3),
        ReportColumn('Chaco', weight: 2),
        ReportColumn('Cargo (Bs)', numeric: true, weight: 1.6),
        ReportColumn('Crédito (Bs)', numeric: true, weight: 1.6),
        ReportColumn('Acumulado (Bs)', numeric: true, weight: 1.8),
      ],
      rows: rows,
      totals: [
        ReportTotal('Total de cargos (Bs)', ReportMoney(charges)),
        ReportTotal('Total de créditos (Bs)', ReportMoney(credits)),
        ReportTotal('Saldo final (Bs)', ReportMoney(closing)),
      ],
      emptyMessage: 'Esta persona no tiene movimientos en el periodo elegido.',
    );
  }
}
