import '../numeric_input.dart' show maxBaseQuantity;
import 'sync_types.dart';

/// Una línea de aplicación tal como está en SQLite: sólo lo que el total
/// necesita. Nunca viajan notas, costos, chacos ni personas (F06 §2).
class AppliedLine {
  const AppliedLine({
    required this.applicationId,
    required this.personId,
    required this.campaignId,
    required this.productId,
    required this.status,
    required this.reversed,
    required this.quantityBase,
  });

  final int applicationId;

  /// Persona cuyos lotes consumió la aplicación (`applications.person_id`).
  final int personId;
  final int campaignId;
  final int productId;

  /// `CONFIRMED` o `REVERSED` (la reversión es de la aplicación entera).
  final String status;
  final bool reversed;
  final int quantityBase;

  bool get counts => status == 'CONFIRMED' && !reversed;
}

/// Vínculo central de una campaña o un producto local, ya leído.
class BoundRef {
  const BoundRef({
    required this.ref,
    required this.localName,
    required this.centralName,
    required this.valid,
    this.baseUnit,
  });

  final String ref;
  final String localName;
  final String centralName;
  final bool valid;

  /// Sólo para productos: ML o G.
  final BaseUnit? baseUnit;
}

/// Por qué una línea o un total no entra en la publicación.
enum ConsumptionExclusion {
  /// En modo compartido, la aplicación es de un familiar o tercero (F06 §4).
  notOwner,

  /// Aplicación revertida: no suma (neto de reversiones, RF-13).
  reversed,
  campaignNotBound,
  campaignBindingInvalid,
  productNotBound,
  productBindingInvalid,

  /// El total supera el máximo exacto (int64): nunca se trunca.
  overflow,
}

/// Total de consumo de una campaña × producto vinculados.
class ConsumptionCell {
  const ConsumptionCell({
    required this.campaignId,
    required this.productId,
    required this.campaign,
    required this.product,
    required this.quantityBase,
    required this.applications,
  });

  final int campaignId;
  final int productId;
  final BoundRef campaign;
  final BoundRef product;
  final int quantityBase;

  /// Aplicaciones que aportan a este total.
  final int applications;

  BaseUnit get baseUnit => product.baseUnit!;
}

/// Una campaña × producto con consumo que no se publica, y por qué.
class ExcludedPair {
  const ExcludedPair(this.campaignId, this.productId, this.reason);

  final int campaignId;
  final int productId;
  final ConsumptionExclusion reason;
}

class ConsumptionProjection {
  const ConsumptionProjection({
    required this.cells,
    required this.excludedPairs,
    required this.excludedLines,
    this.excludedTotals = const {},
  });

  final List<ConsumptionCell> cells;

  /// Pares con consumo propio que no se publican (vínculos, desbordamiento).
  final List<ExcludedPair> excludedPairs;

  /// Líneas que no cuentan: ajenas al titular o revertidas.
  final Map<ConsumptionExclusion, int> excludedLines;

  /// Total exacto de cada par excluido por su vínculo (no por
  /// desbordamiento), para mostrarlo bloqueado con su valor real y nunca como
  /// un cero (D-F04-C2). No se publica.
  final Map<(int, int), int> excludedTotals;
}

/// `CONSUMPTION_TOTAL` (F06 §2, MOB #33): por campaña y producto vinculados,
/// suma exacta de las cantidades de las aplicaciones **confirmadas** del
/// **titular**, neta de reversiones. Una aplicación multiproducto aporta a
/// tantos totales como productos tiene (MOB #32). Función pura: no lee ni
/// escribe la base.
ConsumptionProjection buildConsumptionProjection({
  required int ownerPersonId,
  required Iterable<AppliedLine> lines,
  required Map<int, BoundRef> campaigns,
  required Map<int, BoundRef> products,
}) {
  final excludedLines = <ConsumptionExclusion, int>{};
  void exclude(ConsumptionExclusion reason) =>
      excludedLines[reason] = (excludedLines[reason] ?? 0) + 1;

  final totals = <(int, int), BigInt>{};
  final applications = <(int, int), Set<int>>{};
  for (final line in lines) {
    if (line.personId != ownerPersonId) {
      exclude(ConsumptionExclusion.notOwner);
      continue;
    }
    if (!line.counts) {
      exclude(ConsumptionExclusion.reversed);
      continue;
    }
    final key = (line.campaignId, line.productId);
    totals[key] = (totals[key] ?? BigInt.zero) + BigInt.from(line.quantityBase);
    (applications[key] ??= {}).add(line.applicationId);
  }

  final cells = <ConsumptionCell>[];
  final excludedPairs = <ExcludedPair>[];
  final excludedTotals = <(int, int), int>{};
  final max = BigInt.from(maxBaseQuantity);
  for (final MapEntry(key: (campaignId, productId), value: total)
      in totals.entries) {
    final campaign = campaigns[campaignId];
    final product = products[productId];
    final ConsumptionExclusion? problem = switch ((campaign, product)) {
      (null, _) => ConsumptionExclusion.campaignNotBound,
      (BoundRef(valid: false), _) =>
        ConsumptionExclusion.campaignBindingInvalid,
      (_, null) => ConsumptionExclusion.productNotBound,
      (_, BoundRef(valid: false)) => ConsumptionExclusion.productBindingInvalid,
      _ when total > max => ConsumptionExclusion.overflow,
      _ => null,
    };
    if (problem != null) {
      excludedPairs.add(ExcludedPair(campaignId, productId, problem));
      if (problem != ConsumptionExclusion.overflow) {
        excludedTotals[(campaignId, productId)] = total.toInt();
      }
      continue;
    }
    cells.add(
      ConsumptionCell(
        campaignId: campaignId,
        productId: productId,
        campaign: campaign!,
        product: product!,
        quantityBase: total.toInt(),
        applications: applications[(campaignId, productId)]!.length,
      ),
    );
  }
  cells.sort(
    (a, b) => a.campaignId != b.campaignId
        ? a.campaignId.compareTo(b.campaignId)
        : a.productId.compareTo(b.productId),
  );
  return ConsumptionProjection(
    cells: cells,
    excludedPairs: excludedPairs,
    excludedLines: excludedLines,
    excludedTotals: excludedTotals,
  );
}
