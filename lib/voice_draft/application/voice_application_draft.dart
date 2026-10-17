/// Borrador de aplicación multiproducto por voz (#15, F09-VOZ-07).
///
/// Se convierte en el mismo `ApplicationDraft` que arma el formulario de
/// aplicación sin plan y se registra con `confirmApplication()`, que es la
/// autoridad de FIFO, costo, movimientos y stock. Antes de confirmar, el stock
/// sólo se **proyecta** con una lectura: nada se descuenta.
///
/// Como en el formulario, elegir el chaco fija la persona que aplica (su
/// dueño, que debe poder aplicar) y propone su área. La aplicación de un plan
/// pendiente por voz (EVO-018) queda fuera de este incremento (decisión
/// pendiente D-F09-4).
library;

import '../../domain/models.dart';
import '../catalog/voice_catalog.dart';
import '../core/draft_field.dart';
import '../core/voice_draft_controller.dart';
import '../text/units.dart';

final class VoiceApplicationLine {
  const VoiceApplicationLine({
    required this.key,
    this.product = const DraftField.missing(message: 'Falta el producto.'),
    this.quantity = const DraftField.missing(message: 'Falta la cantidad.'),
  });

  final int key;
  final DraftField<CatalogEntry> product;

  /// Cantidad real usada, tal como se dijo o escribió.
  final DraftField<SpokenAmount> quantity;

  VoiceApplicationLine copyWith({
    DraftField<CatalogEntry>? product,
    DraftField<SpokenAmount>? quantity,
  }) => VoiceApplicationLine(
    key: key,
    product: product ?? this.product,
    quantity: quantity ?? this.quantity,
  );

  int? get quantityBase {
    final q = quantity.value;
    final unit = product.value?.unit;
    if (!quantity.isResolved || q == null || unit == null) return null;
    if (q.unit.family != unit) return null;
    final base = q.unit.toBase(q.thousandths);
    return base == null || base <= 0 ? null : base;
  }
}

/// Una cantidad dicha: milésimas y unidad.
final class SpokenAmount {
  const SpokenAmount(this.thousandths, this.unit);
  final int thousandths;
  final SpokenUnit unit;

  @override
  bool operator ==(Object other) =>
      other is SpokenAmount &&
      other.thousandths == thousandths &&
      other.unit == unit;

  @override
  int get hashCode => Object.hash(thousandths, unit);
}

final class VoiceApplicationDraft implements VoiceDraft<VoiceApplicationDraft> {
  const VoiceApplicationDraft({
    required this.campaign,
    required this.appliedAt,
    this.farm = const DraftField.missing(message: 'Falta el chaco.'),
    this.person,
    this.area = const DraftField.missing(message: 'Falta el área tratada.'),
    this.lines = const [],
    this.stock = const {},
    this.stockOwnerId,
    this.nextLineKey = 1,
  });

  factory VoiceApplicationDraft.start(VoiceCatalog catalog, DateTime now) =>
      VoiceApplicationDraft(
        campaign: catalog.activeCampaign == null
            ? const DraftField.missing(
                message: 'Active una campaña antes de registrar aplicaciones.',
              )
            : DraftField.resolved(
                catalog.activeCampaign!,
                origin: FieldOrigin.preset,
              ),
        appliedAt: now,
      );

  final DraftField<CatalogEntry> campaign;

  /// Momento de la aplicación: ahora, como el formulario.
  final DateTime appliedAt;

  final DraftField<CatalogEntry> farm;

  /// Dueño del chaco: aplica y pone el stock (como en el formulario).
  final CatalogEntry? person;

  /// Área tratada en m². Se propone la del chaco.
  final DraftField<int> area;

  final List<VoiceApplicationLine> lines;

  /// Stock disponible del dueño del chaco por producto, en unidad base, leído
  /// al elegir el chaco. Es una **proyección**: la autoridad al escribir es
  /// `confirmApplication()`.
  final Map<int, int> stock;

  /// De quién es [stock]. Si no coincide con [person], el stock todavía no
  /// se leyó para el chaco elegido y no se puede confirmar.
  final int? stockOwnerId;

  final int nextLineKey;

  bool get stockLoaded => person != null && stockOwnerId == person!.id;

  VoiceApplicationDraft copyWith({
    DraftField<CatalogEntry>? campaign,
    DraftField<CatalogEntry>? farm,
    CatalogEntry? person,
    bool clearPerson = false,
    DraftField<int>? area,
    List<VoiceApplicationLine>? lines,
    Map<int, int>? stock,
    int? stockOwnerId,
    bool clearStock = false,
    int? nextLineKey,
  }) => VoiceApplicationDraft(
    campaign: campaign ?? this.campaign,
    appliedAt: appliedAt,
    farm: farm ?? this.farm,
    person: clearPerson ? null : (person ?? this.person),
    area: area ?? this.area,
    lines: lines ?? this.lines,
    stock: clearStock ? const {} : (stock ?? this.stock),
    stockOwnerId: clearStock ? null : (stockOwnerId ?? this.stockOwnerId),
    nextLineKey: nextLineKey ?? this.nextLineKey,
  );

  /// Stock leído para [ownerId]. Se ignora si el chaco cambió mientras se
  /// leía (la persona ya es otra).
  VoiceApplicationDraft withStock(int ownerId, Map<int, int> available) =>
      person?.id == ownerId
      ? copyWith(stock: available, stockOwnerId: ownerId)
      : this;

  VoiceApplicationDraft addEmptyLine() => copyWith(
    lines: [
      ...lines,
      VoiceApplicationLine(key: nextLineKey),
    ],
    nextLineKey: nextLineKey + 1,
  );

  VoiceApplicationDraft removeLine(int key) => copyWith(
    lines: [
      for (final l in lines)
        if (l.key != key) l,
    ],
  );

  VoiceApplicationDraft updateLine(
    int key,
    VoiceApplicationLine Function(VoiceApplicationLine line) update,
  ) => copyWith(lines: [for (final l in lines) l.key == key ? update(l) : l]);

  /// Stock que quedaría tras aplicar la línea, o `null` si no se puede
  /// calcular todavía.
  int? stockAfter(VoiceApplicationLine line) {
    final id = line.product.value?.id;
    final base = line.quantityBase;
    if (id == null || base == null || !stockLoaded) return null;
    return (stock[id] ?? 0) - base;
  }

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
            'Elija $name: «${f.heard ?? ''}» tiene varias opciones o no es '
            'exacto.',
          );
        case FieldStatus.invalid:
          out.add('Revise $name. ${f.message ?? ''}'.trim());
      }
    }

    head('la campaña', campaign);
    head('el chaco', farm);
    if (farm.isResolved && person == null) {
      out.add('El dueño de este chaco no puede registrar aplicaciones.');
    }
    if (person != null && !stockLoaded) {
      out.add('Leyendo el stock del dueño del chaco…');
    }
    head('el área tratada', area);
    if (lines.isEmpty) out.add('Añada al menos un producto aplicado.');
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
      if (!l.quantity.isResolved) {
        out.add('$n: ${l.quantity.message ?? 'falta la cantidad.'}');
      } else if (l.product.isResolved && l.quantityBase == null) {
        out.add('$n: la cantidad no corresponde a la unidad del producto.');
      }
      final after = stockAfter(l);
      if (after != null && after < 0) {
        out.add('$n: no hay stock suficiente del dueño del chaco.');
      }
      final id = l.product.value?.id;
      if (l.product.isResolved && id != null && !seen.add(id)) {
        out.add('$n: el producto está repetido.');
      }
    }
    return out;
  }

  /// El mismo `ApplicationDraft` que arma el formulario sin plan: sin dosis,
  /// la cantidad teórica es 0, como en el formulario con la dosis vacía.
  ApplicationDraft toDomain() {
    if (blockers.isNotEmpty) {
      throw StateError('El borrador tiene bloqueos y no se puede convertir.');
    }
    return ApplicationDraft(
      personId: person!.id,
      farmId: farm.value!.id,
      campaignId: campaign.value!.id,
      appliedAt: appliedAt,
      notes: '',
      treatedAreaM2: area.value!,
      lines: [
        for (final l in lines)
          ApplicationLineDraft(
            productId: l.product.value!.id,
            quantityBase: l.quantityBase!,
            treatedAreaM2: area.value!,
            theoreticalQuantityBase: 0,
          ),
      ],
    );
  }
}
