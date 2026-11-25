import 'account_ledger.dart';
import 'models.dart';
import 'person_roles.dart';
import 'read_models.dart';
import 'repository_types.dart';

/// Puerto de lectura y escritura de dominio consumido por presentación y voz
/// sin depender de la implementación en `lib/data/`.
abstract interface class AgroGateway {
  Future<int> addPerson({
    required String name,
    required PersonRole role,
    SettlementPolicy? policy,
    String? phone,
  });

  Future<int> addFarm({
    required int ownerId,
    required String name,
    required int areaM2,
    String? location,
  });

  Future<int> addCampaign({
    required String name,
    required DateTime start,
    DateTime? end,
  });

  Future<DateTime> suggestedCampaignStart();
  Future<Map<String, Object?>?> activeCampaign();
  Future<void> activateCampaign(int campaignId, {bool closeCurrent = false});
  Future<void> closeCampaign(int campaignId, {DateTime? end});
  Future<Map<String, Object?>> campaignCloseSummary(int campaignId);
  Future<int> addProduct({
    required String name,
    String? activeIngredient,
    String unit = 'L',
  });
  Future<int> addSupplier({required String name, String? phone, String? notes});

  Future<int> addPlanMulti({
    required int farmId,
    required int campaignId,
    required int areaM2,
    required List<PlanItemDraft> items,
    DateTime? plannedDate,
    String? notes,
  });

  Future<int> confirmPurchase(
    PurchaseDraft draft, {
    ProviderPaymentDetails? paidInFull,
  });

  Future<int> confirmApplication(ApplicationDraft draft);

  Future<List<Map<String, Object?>>> availableProductsForOwner(
    int personId, {
    String query = '',
    int limit = 100,
  });

  Future<List<Map<String, Object?>>> people();
  Future<WriteContext> operatingContext();
  Future<List<Map<String, Object?>>> peopleFor(PersonPurpose purpose);
  Future<({List<Map<String, Object?>> people, WriteContext context})>
  peopleAndContextFor(PersonPurpose purpose);
  Future<List<Map<String, Object?>>> products();
  Future<List<Map<String, Object?>>> suppliers();
  Future<List<Map<String, Object?>>> campaigns();
  Future<List<Map<String, Object?>>> farms();
  Future<({List<Map<String, Object?>> farms, WriteContext context})>
  farmsAndContext();
  Future<List<Map<String, Object?>>> purchases({int limit = 200});
  Future<List<Map<String, Object?>>> plans({
    int limit = 400,
    bool includeApplied = false,
  });
  Future<List<Map<String, Object?>>> planForApplication(int planId);
  Future<List<Map<String, Object?>>> inventorySummary({int? limit});
  Future<List<Map<String, Object?>>> personProfiles();
  Future<AccountLedger> accountLedger({int? personId, bool withDetails = true});
  Future<int> estimateFifoCost({
    required int personId,
    required int productId,
    required int quantityBase,
  });
  Future<List<ApplicationLotPreview>> previewApplicationLots({
    required int personId,
    required int productId,
    required int quantityBase,
    required DateTime appliedAt,
  });
  Future<List<Map<String, Object?>>> settlements({int? campaignId});
  Future<List<Map<String, Object?>>> topSettlements({int limit = 5});
  Future<List<Map<String, Object?>>> detailedStatement(
    int personId, {
    int? campaignId,
  });
  Future<List<Map<String, Object?>>> farmCostReport({int? campaignId});
  Future<List<Map<String, Object?>>> productCostReport({int? campaignId});
  Future<Map<String, Object?>> personCampaignBalance(
    int personId,
    int campaignId,
  );
}

/// Adaptadores tipados compartidos sobre [AgroGateway].
extension AgroGatewayTypedReads on AgroGateway {
  Future<List<CampaignRead>> campaignsTyped() async =>
      CampaignRead.fromRows(await campaigns());

  Future<List<PersonRead>> peopleTyped() async =>
      PersonRead.fromRows(await people());

  Future<List<InventoryLineRead>> inventorySummaryTyped({int? limit}) async =>
      InventoryLineRead.fromRows(await inventorySummary(limit: limit));

  Future<List<SettlementRead>> settlementsTyped({int? campaignId}) async =>
      SettlementRead.fromRows(await settlements(campaignId: campaignId));

  Future<List<TopSettlementRead>> topSettlementsTyped({int limit = 5}) async =>
      TopSettlementRead.fromRows(await topSettlements(limit: limit));

  Future<List<ProductCostRead>> productCostReportTyped({
    int? campaignId,
  }) async =>
      ProductCostRead.fromRows(await productCostReport(campaignId: campaignId));

  Future<List<FarmCostRead>> farmCostReportTyped({int? campaignId}) async =>
      FarmCostRead.fromRows(await farmCostReport(campaignId: campaignId));

  Future<CampaignSummaryRead> campaignCloseSummaryTyped(int campaignId) async =>
      CampaignSummaryRead.fromRow(await campaignCloseSummary(campaignId));

  Future<PersonCampaignBalanceRead> personCampaignBalanceTyped(
    int personId,
    int campaignId,
  ) async => PersonCampaignBalanceRead.fromRow(
    await personCampaignBalance(personId, campaignId),
  );

  Future<List<StatementEntryRead>> detailedStatementTyped(
    int personId, {
    int? campaignId,
  }) async => StatementEntryRead.fromRows(
    await detailedStatement(personId, campaignId: campaignId),
  );
}
