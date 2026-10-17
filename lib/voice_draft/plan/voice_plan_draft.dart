/// Borrador de planificación por voz (#14, F09-VOZ-06).
///
/// Se convierte en la misma llamada que el formulario de planificación:
/// `addPlanMulti(farmId, campaignId, areaM2, items: [PlanItemDraft(productId,
/// doseBasePerHa)])`. El plan del dominio es **área + dosis por hectárea**; la
/// cantidad necesaria se calcula, igual que en el formulario (decisión
/// pendiente D-F09-3: el texto de #14 habla de «cantidades y unidades»).
library;

import '../../domain/models.dart';
import '../../domain/money.dart';
import '../catalog/voice_catalog.dart';
import '../core/draft_field.dart';
import '../core/voice_draft_controller.dart';
import '../text/units.dart';

/// Dosis dicha: milésimas por hectárea y unidad («dos litros por hectárea»).
final class SpokenDose {
  const SpokenDose(this.thousandthsPerHa, this.unit);
  final int thousandthsPerHa;
  final SpokenUnit unit;

  @override
  bool operator ==(Object other) =>
      other is SpokenDose &&
      other.thousandthsPerHa == thousandthsPerHa &&
      other.unit == unit;

  @override
  int get hashCode => Object.hash(thousandthsPerHa, unit);
}

final class VoicePlanLine {
  const VoicePlanLine({
    required this.key,
    this.product = const DraftField.missing(message: 'Falta el producto.'),
    this.dose = const DraftField.missing(
      message: 'Falta la dosis por hectárea.',
    ),
  });

  final int key;
  final DraftField<CatalogEntry> product;
  final DraftField<SpokenDose> dose;

  VoicePlanLine copyWith({
    DraftField<CatalogEntry>? product,
    DraftField<SpokenDose>? dose,
  }) => VoicePlanLine(
    key: key,
    product: product ?? this.product,
    dose: dose ?? this.dose,
  );

  /// Dosis en unidad base por hectárea (ML/ha o G/ha), si es compatible.
  int? get doseBasePerHa {
    final d = dose.value;
    final unit = product.value?.unit;
    if (!dose.isResolved || d == null || unit == null) return null;
    if (d.unit.family != unit) return null;
    final base = d.unit.toBase(d.thousandthsPerHa);
    return base == null || base <= 0 ? null : base;
  }

  /// Cantidad necesaria para [areaM2], como la calcula `addPlanMulti`.
  int? requiredBase(int? areaM2) {
    final dose = doseBasePerHa;
    if (dose == null || areaM2 == null || areaM2 <= 0) return null;
    return divideRoundedHalfUp(areaM2 * dose, 10000);
  }
}

final class VoicePlanDraft implements VoiceDraft<VoicePlanDraft> {
  const VoicePlanDraft({
    required this.campaign,
    this.farm = const DraftField.missing(message: 'Falta el chaco.'),
    this.area = const DraftField.missing(message: 'Falta el área.'),
    this.lines = const [],
    this.nextLineKey = 1,
  });

  factory VoicePlanDraft.start(VoiceCatalog catalog) => VoicePlanDraft(
    campaign: catalog.activeCampaign == null
        ? const DraftField.missing(
            message: 'Active una campaña antes de planificar.',
          )
        : DraftField.resolved(
            catalog.activeCampaign!,
            origin: FieldOrigin.preset,
          ),
  );

  final DraftField<CatalogEntry> campaign;
  final DraftField<CatalogEntry> farm;

  /// Área en m². Al resolver el chaco se propone su área, como el formulario.
  final DraftField<int> area;
  final List<VoicePlanLine> lines;
  final int nextLineKey;

  VoicePlanDraft copyWith({
    DraftField<CatalogEntry>? campaign,
    DraftField<CatalogEntry>? farm,
    DraftField<int>? area,
    List<VoicePlanLine>? lines,
    int? nextLineKey,
  }) => VoicePlanDraft(
    campaign: campaign ?? this.campaign,
    farm: farm ?? this.farm,
    area: area ?? this.area,
    lines: lines ?? this.lines,
    nextLineKey: nextLineKey ?? this.nextLineKey,
  );

  VoicePlanDraft addEmptyLine() => copyWith(
    lines: [
      ...lines,
      VoicePlanLine(key: nextLineKey),
    ],
    nextLineKey: nextLineKey + 1,
  );

  VoicePlanDraft removeLine(int key) => copyWith(
    lines: [
      for (final l in lines)
        if (l.key != key) l,
    ],
  );

  VoicePlanDraft updateLine(
    int key,
    VoicePlanLine Function(VoicePlanLine line) update,
  ) => copyWith(lines: [for (final l in lines) l.key == key ? update(l) : l]);

  @override
  List<String> get blockers {
    final out = <String>[];
    void head(String name, DraftField<Object?> f) {
      switch (f.status) {
        case FieldStatus.resolved:
          break;
        case FieldStatus.missing:
          out.add(f.message ?? 'Falta $name.');
        case FieldStatus.ambiguous:
          out.add(
            'Elija $name: «${f.heard ?? ''}» tiene varias opciones o no es exacto.',
          );
        case FieldStatus.invalid:
          out.add('Revise $name. ${f.message ?? ''}'.trim());
      }
    }

    head('la campaña', campaign);
    head('el chaco', farm);
    head('el área', area);
    if (lines.isEmpty) out.add('Añada al menos un producto al plan.');
    final seen = <int>{};
    for (var i = 0; i < lines.length; i++) {
      final n = 'Producto ${i + 1}';
      final l = lines[i];
      if (!l.product.isResolved) {
        out.add(
          l.product.status == FieldStatus.ambiguous
              ? '$n: elija el producto («${l.product.heard ?? ''}»).'
              : '$n: ${l.product.message ?? 'falta el producto.'}',
        );
      }
      if (!l.dose.isResolved) {
        out.add('$n: ${l.dose.message ?? 'falta la dosis por hectárea.'}');
      } else if (l.product.isResolved && l.doseBasePerHa == null) {
        out.add('$n: la dosis no corresponde a la unidad del producto.');
      }
      final id = l.product.value?.id;
      if (l.product.isResolved && id != null && !seen.add(id)) {
        out.add('$n: el producto está repetido.');
      }
    }
    return out;
  }

  /// Los mismos datos que entrega el formulario a `addPlanMulti`.
  ({int farmId, int campaignId, int areaM2, List<PlanItemDraft> items})
  toDomain() {
    if (blockers.isNotEmpty) {
      throw StateError('El borrador tiene bloqueos y no se puede convertir.');
    }
    return (
      farmId: farm.value!.id,
      campaignId: campaign.value!.id,
      areaM2: area.value!,
      items: [
        for (final l in lines)
          PlanItemDraft(
            productId: l.product.value!.id,
            doseBasePerHa: l.doseBasePerHa!,
          ),
      ],
    );
  }
}
