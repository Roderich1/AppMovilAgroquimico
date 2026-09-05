enum PersonRole { admin, family, thirdParty }

enum SettlementPolicy { byActualUsage, byPurchaseAllocation, manual }

enum CurrencyCode { bob, usd }

enum ExchangeRateSource { agreedWithSupplier, officialReference, manual, other }

extension EnumCode on Enum {
  String get code => name
      .replaceAllMapped(RegExp(r'([A-Z])'), (match) => '_${match.group(1)}')
      .toUpperCase();
}

class AllocationDraft {
  const AllocationDraft({required this.personId, required this.quantityBase});
  final int personId;
  final int quantityBase;
}

class PurchaseItemDraft {
  const PurchaseItemDraft({
    required this.productId,
    required this.quantityBase,
    required this.currency,
    required this.originalUnitPriceMinor,
    this.exchangeRateScaled,
    required this.allocations,
  });

  final int productId;
  final int quantityBase;
  final CurrencyCode currency;
  final int originalUnitPriceMinor;
  final int? exchangeRateScaled;
  final List<AllocationDraft> allocations;
}

class PurchaseDraft {
  const PurchaseDraft({
    required this.supplierId,
    required this.campaignId,
    required this.purchaseDate,
    this.invoiceNumber,
    this.exchangeRateSource,
    this.exchangeRateNote,
    this.notes,
    this.invoiceImagePath,
    required this.items,
  });

  final int supplierId;
  final int campaignId;
  final DateTime purchaseDate;
  final String? invoiceNumber;
  final ExchangeRateSource? exchangeRateSource;
  final String? exchangeRateNote;
  final String? notes;
  final String? invoiceImagePath;
  final List<PurchaseItemDraft> items;
}

class ApplicationLineDraft {
  const ApplicationLineDraft({
    required this.productId,
    required this.quantityBase,
    this.treatedAreaM2,
    this.doseBasePerHa,
    this.theoreticalQuantityBase,
  });
  final int productId;
  final int quantityBase;
  final int? treatedAreaM2;
  final int? doseBasePerHa;
  final int? theoreticalQuantityBase;
}

class ApplicationDraft {
  const ApplicationDraft({
    required this.personId,
    required this.farmId,
    required this.campaignId,
    required this.appliedAt,
    required this.lines,
    this.treatedAreaM2,
    this.planId,
    this.notes,
  });
  final int personId;
  final int farmId;
  final int campaignId;
  final DateTime appliedAt;
  final List<ApplicationLineDraft> lines;
  final int? treatedAreaM2;
  final int? planId;
  final String? notes;
}

class PlanItemDraft {
  const PlanItemDraft({required this.productId, required this.doseBasePerHa});
  final int productId;
  final int doseBasePerHa;
}

class TransferItemDraft {
  const TransferItemDraft({
    required this.productId,
    required this.quantityBase,
  });
  final int productId;
  final int quantityBase;
}

class DashboardSummary {
  const DashboardSummary({
    required this.purchasesBobMinor,
    required this.providerPaidMinor,
    required this.familyReceivableMinor,
    required this.thirdPartyReceivableMinor,
    required this.receivedMinor,
    required this.stockBase,
  });
  final int purchasesBobMinor;
  final int providerPaidMinor;
  final int familyReceivableMinor;
  final int thirdPartyReceivableMinor;
  final int receivedMinor;
  final int stockBase;
}
