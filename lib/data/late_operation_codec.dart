// RF-03 (docs/architecture/F04_RF13_RF03_ACTOR_Y_TARDIAS.md §2.2): el
// borrador de una operación tardía se guarda como JSON del mismo borrador del
// formulario. La foto de factura NO va en el JSON (columna propia, R1 de C).
import 'dart:convert';

import '../domain/models.dart';

String encodeLatePurchase(PurchaseDraft draft) => jsonEncode({
  'v': 1,
  'supplierId': draft.supplierId,
  'campaignId': draft.campaignId,
  'purchaseDate': draft.purchaseDate.toUtc().toIso8601String(),
  'invoiceNumber': draft.invoiceNumber,
  'exchangeRateSource': draft.exchangeRateSource?.name,
  'exchangeRateNote': draft.exchangeRateNote,
  'notes': draft.notes,
  'items': [
    for (final item in draft.items)
      {
        'productId': item.productId,
        'quantityBase': item.quantityBase,
        'currency': item.currency.name,
        'originalUnitPriceMinor': item.originalUnitPriceMinor,
        'exchangeRateScaled': item.exchangeRateScaled,
        'allocations': [
          for (final a in item.allocations)
            {'personId': a.personId, 'quantityBase': a.quantityBase},
        ],
      },
  ],
});

PurchaseDraft decodeLatePurchase(String raw, {String? invoiceImagePath}) {
  final json = _object(raw);
  return PurchaseDraft(
    supplierId: json['supplierId'] as int,
    campaignId: json['campaignId'] as int,
    purchaseDate: DateTime.parse(json['purchaseDate'] as String),
    invoiceNumber: json['invoiceNumber'] as String?,
    exchangeRateSource: json['exchangeRateSource'] == null
        ? null
        : ExchangeRateSource.values.byName(json['exchangeRateSource'] as String),
    exchangeRateNote: json['exchangeRateNote'] as String?,
    notes: json['notes'] as String?,
    invoiceImagePath: invoiceImagePath,
    items: [
      for (final item in json['items'] as List<dynamic>)
        PurchaseItemDraft(
          productId: (item as Map<String, dynamic>)['productId'] as int,
          quantityBase: item['quantityBase'] as int,
          currency: CurrencyCode.values.byName(item['currency'] as String),
          originalUnitPriceMinor: item['originalUnitPriceMinor'] as int,
          exchangeRateScaled: item['exchangeRateScaled'] as int?,
          allocations: [
            for (final a in item['allocations'] as List<dynamic>)
              AllocationDraft(
                personId: (a as Map<String, dynamic>)['personId'] as int,
                quantityBase: a['quantityBase'] as int,
              ),
          ],
        ),
    ],
  );
}

String encodeLateApplication(ApplicationDraft draft) => jsonEncode({
  'v': 1,
  'personId': draft.personId,
  'farmId': draft.farmId,
  'campaignId': draft.campaignId,
  'appliedAt': draft.appliedAt.toUtc().toIso8601String(),
  'treatedAreaM2': draft.treatedAreaM2,
  'notes': draft.notes,
  'lines': [
    for (final line in draft.lines)
      {
        'productId': line.productId,
        'quantityBase': line.quantityBase,
        'treatedAreaM2': line.treatedAreaM2,
        'doseBasePerHa': line.doseBasePerHa,
        'theoreticalQuantityBase': line.theoreticalQuantityBase,
      },
  ],
});

ApplicationDraft decodeLateApplication(String raw) {
  final json = _object(raw);
  return ApplicationDraft(
    personId: json['personId'] as int,
    farmId: json['farmId'] as int,
    campaignId: json['campaignId'] as int,
    appliedAt: DateTime.parse(json['appliedAt'] as String),
    treatedAreaM2: json['treatedAreaM2'] as int?,
    notes: json['notes'] as String?,
    lines: [
      for (final line in json['lines'] as List<dynamic>)
        ApplicationLineDraft(
          productId: (line as Map<String, dynamic>)['productId'] as int,
          quantityBase: line['quantityBase'] as int,
          treatedAreaM2: line['treatedAreaM2'] as int?,
          doseBasePerHa: line['doseBasePerHa'] as int?,
          theoreticalQuantityBase: line['theoreticalQuantityBase'] as int?,
        ),
    ],
  );
}

Map<String, dynamic> _object(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, dynamic> || decoded['v'] != 1) {
    throw const FormatException('Borrador tardío con formato desconocido');
  }
  return decoded;
}
