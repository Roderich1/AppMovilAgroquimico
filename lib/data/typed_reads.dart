/// Adaptadores tipados sobre las consultas ya probadas de [AgroRepository]
/// (EVO-004).
///
/// Son una extensión y no métodos nuevos dentro del repositorio por dos
/// razones. La primera es que `AgroRepository` ya concentra catálogos,
/// campañas, compras, FIFO y cuentas en 1.700 líneas, y EVOLUTION-2 no puede
/// reescribirlo. La segunda es que así el diff deja ver de un vistazo que
/// **ninguna consulta SQL cambia**: cada método de aquí llama al método legacy
/// y sólo mapea el resultado (`EVO-004-REQ-003`).
///
/// La llamada sigue siendo virtual, así que los dobles de prueba que
/// sobrescriben los métodos legacy siguen funcionando a través de los tipados.
///
/// Los métodos legacy permanecen: los siguen usando pantallas que EVOLUTION-2
/// no toca (`EVO-004-REQ-005`).
library;

import '../domain/read_models.dart';
import 'agro_repository.dart';

extension AgroRepositoryTypedReads on AgroRepository {
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
