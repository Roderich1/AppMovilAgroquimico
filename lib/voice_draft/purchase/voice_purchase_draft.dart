/// Borrador de compra por voz (#11, EVO-017).
///
/// Se convierte en el mismo `PurchaseDraft` que arma el formulario manual y se
/// registra con el mismo caso de uso. El total se calcula con las políticas
/// monetarias del dominio; nunca se toma del dictado.
library;

import '../../domain/models.dart';
import '../../domain/money.dart';
import '../catalog/voice_catalog.dart';
import '../core/draft_field.dart';
import '../core/voice_draft_controller.dart';
import '../text/units.dart';

/// Una cantidad tal como se dijo o se escribió: valor en milésimas y unidad.
final class SpokenQuantity {
  const SpokenQuantity(this.thousandths, this.unit);
  final int thousandths;
  final SpokenUnit unit;

  @override
  bool operator ==(Object other) =>
      other is SpokenQuantity &&
      other.thousandths == thousandths &&
      other.unit == unit;

  @override
  int get hashCode => Object.hash(thousandths, unit);
}

/// Un precio dicho: centavos por litro o kilo, y la unidad a la que se dijo
/// que corresponde («el litro»), si se dijo.
final class SpokenPrice {
  const SpokenPrice(this.minorPerUnit, {this.perUnit});
  final int minorPerUnit;
  final CatalogUnit? perUnit;

  @override
  bool operator ==(Object other) =>
      other is SpokenPrice &&
      other.minorPerUnit == minorPerUnit &&
      other.perUnit == perUnit;

  @override
  int get hashCode => Object.hash(minorPerUnit, perUnit);
}

final class VoicePurchaseLine {
  const VoicePurchaseLine({
    required this.key,
    this.product = const DraftField.missing(message: 'Falta el producto.'),
    this.quantity = const DraftField.missing(message: 'Falta la cantidad.'),
    this.price = const DraftField.missing(message: 'Falta el precio.'),
    this.currency = const DraftField.missing(message: 'Falta la moneda.'),
  });

  /// Identidad estable de la línea durante la sesión.
  final int key;
  final DraftField<CatalogEntry> product;
  final DraftField<SpokenQuantity> quantity;
  final DraftField<SpokenPrice> price;
  final DraftField<CurrencyCode> currency;

  VoicePurchaseLine copyWith({
    DraftField<CatalogEntry>? product,
    DraftField<SpokenQuantity>? quantity,
    DraftField<SpokenPrice>? price,
    DraftField<CurrencyCode>? currency,
  }) => VoicePurchaseLine(
    key: key,
    product: product ?? this.product,
    quantity: quantity ?? this.quantity,
    price: price ?? this.price,
    currency: currency ?? this.currency,
  );

  CatalogUnit? get _unit => product.value?.unit;

  /// Cantidad en unidad base (ML o G), si el producto y la unidad dicha son
  /// compatibles y la cantidad es un entero de ML o G.
  int? get quantityBase {
    final q = quantity.value;
    final unit = _unit;
    if (!quantity.isResolved || q == null || unit == null) return null;
    if (q.unit.family != unit) return null;
    final base = q.unit.toBase(q.thousandths);
    return base == null || base <= 0 ? null : base;
  }

  int? get unitPriceMinor {
    final p = price.value;
    if (!price.isResolved || p == null || p.minorPerUnit <= 0) return null;
    if (p.perUnit != null && _unit != null && p.perUnit != _unit) return null;
    return p.minorPerUnit;
  }

  List<String> blockers(int index, int? exchangeRateScaled) {
    final n = 'Línea ${index + 1}';
    final out = <String>[];
    out.addAll(_fieldBlocker(n, 'producto', product));
    out.addAll(_fieldBlocker(n, 'cantidad', quantity));
    out.addAll(_fieldBlocker(n, 'precio', price));
    out.addAll(_fieldBlocker(n, 'moneda', currency));
    if (product.isResolved && quantity.isResolved && quantityBase == null) {
      final unit = _unit;
      final q = quantity.value!;
      out.add(
        unit != null && q.unit.family != unit
            ? '$n: la unidad dicha no corresponde al producto, que se mide en '
                  '${unit == CatalogUnit.liter ? 'litros' : 'kilos'}.'
            : '$n: la cantidad debe ser mayor a cero y en ML o G enteros.',
      );
    }
    if (product.isResolved && price.isResolved && unitPriceMinor == null) {
      out.add('$n: el precio no corresponde a la unidad del producto.');
    }
    if (currency.value == CurrencyCode.usd && (exchangeRateScaled ?? 0) <= 0) {
      out.add('$n: una compra en dólares necesita el tipo de cambio.');
    }
    return out;
  }

  /// Subtotal en centavos de boliviano, o `null` si la línea no es válida.
  int? subtotalBobMinor(int? exchangeRateScaled) {
    final base = quantityBase;
    final price = unitPriceMinor;
    final cur = currency.value;
    if (base == null || price == null || !currency.isResolved || cur == null) {
      return null;
    }
    final fx = cur == CurrencyCode.usd ? exchangeRateScaled : null;
    if (cur == CurrencyCode.usd && (fx ?? 0) <= 0) return null;
    return subtotalMinor(
      quantityBase: base,
      unitPriceMinor: price,
      fxScaled: fx,
    );
  }
}

List<String> _fieldBlocker(String line, String name, DraftField<Object?> f) =>
    switch (f.status) {
      FieldStatus.resolved => const [],
      FieldStatus.missing => ['$line: falta $name.'],
      FieldStatus.ambiguous => [
        '$line: $name ambiguo («${f.heard ?? ''}»), elija una opción.',
      ],
      FieldStatus.invalid => [
        '$line: $name no válido. ${f.message ?? ''}'.trim(),
      ],
    };

final class VoicePurchaseDraft implements VoiceDraft<VoicePurchaseDraft> {
  const VoicePurchaseDraft({
    required this.campaign,
    required this.recipient,
    this.supplier = const DraftField.missing(message: 'Falta el proveedor.'),
    this.exchangeRate = const DraftField.missing(),
    this.lines = const [],
    this.nextLineKey = 1,
  });

  /// Borrador inicial: campaña activa y, si sólo hay una persona elegible
  /// (titular en PERSONAL), esa persona como destinataria. Los dos quedan
  /// visibles como propuestos.
  factory VoicePurchaseDraft.start(VoiceCatalog catalog) => VoicePurchaseDraft(
    campaign: catalog.activeCampaign == null
        ? const DraftField.missing(message: 'No hay una campaña activa.')
        : DraftField.resolved(
            catalog.activeCampaign!,
            origin: FieldOrigin.preset,
          ),
    recipient: catalog.people.length == 1
        ? DraftField.resolved(catalog.people.single, origin: FieldOrigin.preset)
        : const DraftField.missing(message: 'Indique para quién es la compra.'),
  );

  final DraftField<CatalogEntry> supplier;
  final DraftField<CatalogEntry> campaign;

  /// Persona que recibe toda la compra («todo para …»). En PERSONAL es el
  /// titular. El reparto por línea entre varias personas se hace en el
  /// formulario manual (límite declarado).
  final DraftField<CatalogEntry> recipient;

  /// Tipo de cambio escalado por `fxScale`. Sólo cuenta si hay líneas en USD.
  final DraftField<int> exchangeRate;

  final List<VoicePurchaseLine> lines;
  final int nextLineKey;

  bool get _usesUsd =>
      lines.any((line) => line.currency.value == CurrencyCode.usd);

  int? get _fx => exchangeRate.isResolved ? exchangeRate.value : null;

  VoicePurchaseDraft copyWith({
    DraftField<CatalogEntry>? supplier,
    DraftField<CatalogEntry>? campaign,
    DraftField<CatalogEntry>? recipient,
    DraftField<int>? exchangeRate,
    List<VoicePurchaseLine>? lines,
    int? nextLineKey,
  }) => VoicePurchaseDraft(
    supplier: supplier ?? this.supplier,
    campaign: campaign ?? this.campaign,
    recipient: recipient ?? this.recipient,
    exchangeRate: exchangeRate ?? this.exchangeRate,
    lines: lines ?? this.lines,
    nextLineKey: nextLineKey ?? this.nextLineKey,
  );

  /// Añade una línea vacía para completarla a mano.
  VoicePurchaseDraft addEmptyLine() => copyWith(
    lines: [
      ...lines,
      VoicePurchaseLine(key: nextLineKey),
    ],
    nextLineKey: nextLineKey + 1,
  );

  VoicePurchaseDraft removeLine(int key) => copyWith(
    lines: [
      for (final l in lines)
        if (l.key != key) l,
    ],
  );

  VoicePurchaseDraft updateLine(
    int key,
    VoicePurchaseLine Function(VoicePurchaseLine line) update,
  ) => copyWith(lines: [for (final l in lines) l.key == key ? update(l) : l]);

  @override
  List<String> get blockers {
    final out = <String>[];
    out.addAll(_headBlocker('el proveedor', supplier));
    out.addAll(_headBlocker('la campaña', campaign));
    out.addAll(_headBlocker('la persona que recibe la compra', recipient));
    if (lines.isEmpty) out.add('Añada al menos un producto.');
    final seen = <int>{};
    for (var i = 0; i < lines.length; i++) {
      out.addAll(lines[i].blockers(i, _fx));
      final id = lines[i].product.value?.id;
      if (lines[i].product.isResolved && id != null && !seen.add(id)) {
        out.add(
          'Línea ${i + 1}: el producto está repetido; únalo en una línea.',
        );
      }
    }
    if (_usesUsd && !exchangeRate.isResolved) {
      out.add('Falta el tipo de cambio para las líneas en dólares.');
    }
    return out;
  }

  /// Total calculado, o `null` mientras alguna línea no sea válida.
  int? get totalBobMinor {
    if (lines.isEmpty) return null;
    var total = 0;
    for (final line in lines) {
      final sub = line.subtotalBobMinor(_fx);
      if (sub == null) return null;
      total += sub;
    }
    return total;
  }

  /// El mismo `PurchaseDraft` que arma el formulario manual al confirmar.
  /// Sólo con un borrador sin bloqueos.
  ///
  /// [at] es el instante de la confirmación, igual que `DateTime.now()` en el
  /// formulario. La fecha **no** se fija al abrir el borrador: el repositorio
  /// guarda fecha y hora, y el FIFO ordena los lotes por ese instante. Una
  /// compra fechada a medianoche se consumiría antes que otra registrada a
  /// mano más temprano ese mismo día (revisión de A, B-100-1).
  ///
  /// Sin factura dictada, `invoiceNumber` es la cadena vacía, como el
  /// formulario con el campo vacío (`invoiceNumber.text.trim()`).
  PurchaseDraft toDomain({required DateTime at}) {
    if (blockers.isNotEmpty) {
      throw StateError('El borrador tiene bloqueos y no se puede convertir.');
    }
    final recipientId = recipient.value!.id;
    return PurchaseDraft(
      supplierId: supplier.value!.id,
      campaignId: campaign.value!.id,
      purchaseDate: at,
      invoiceNumber: '',
      exchangeRateSource: _usesUsd
          ? ExchangeRateSource.agreedWithSupplier
          : null,
      items: [
        for (final line in lines)
          PurchaseItemDraft(
            productId: line.product.value!.id,
            quantityBase: line.quantityBase!,
            currency: line.currency.value!,
            originalUnitPriceMinor: line.unitPriceMinor!,
            exchangeRateScaled: line.currency.value == CurrencyCode.usd
                ? _fx
                : null,
            allocations: [
              AllocationDraft(
                personId: recipientId,
                quantityBase: line.quantityBase!,
              ),
            ],
          ),
      ],
    );
  }
}

List<String> _headBlocker(String name, DraftField<Object?> f) =>
    switch (f.status) {
      FieldStatus.resolved => const [],
      FieldStatus.missing => [f.message ?? 'Falta $name.'],
      FieldStatus.ambiguous => [
        'Elija $name: «${f.heard ?? ''}» tiene varias opciones o no es exacto.',
      ],
      FieldStatus.invalid => ['Revise $name. ${f.message ?? ''}'.trim()],
    };
