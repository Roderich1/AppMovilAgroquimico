import 'dart:io' show Directory;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../domain/account_ledger.dart'
    show AccountLedger, AccountStatement, AccountSummary;
import '../domain/account_texts.dart' show AccountPaymentResult;
import '../domain/agro_gateway.dart';
import '../domain/campaign_calendar.dart';
import '../domain/inventory_alerts.dart'
    show InventoryAlerts, ProductAlertSettings;
import '../domain/models.dart';
import '../domain/person_roles.dart' show PersonPurpose;
import '../domain/product_photo.dart';
import '../services/auth/local_owner_credential.dart'
    show LocalOwnerCredential, OwnerAuthorization;
import 'app_database.dart';
import 'farmer_operation_gate.dart';
import 'repositories/account_repository.dart';
import 'repositories/application_plan_repository.dart';
import 'repositories/campaign_repository.dart';
import 'repositories/catalog_repository.dart';
import 'repositories/inventory_repository.dart';
import 'repositories/late_operation_repository.dart';
import 'repositories/purchase_repository.dart';
import 'repositories/repository_session.dart';
import 'repositories/repository_types.dart';
import 'repositories/reversal_repository.dart';
import 'repositories/stock_fifo_queries.dart';
import 'repositories/transfer_repository.dart';

export 'repositories/repository_exceptions.dart';
export 'repositories/repository_types.dart';

class AgroRepository implements AgroGateway {
  /// [ownerCredential] da la credencial del titular de la instalación: las
  /// acciones autorizadas exigen que la autorización la haya emitido ella con
  /// el PIN vigente (`LocalOwnerCredential.accepts`), dentro de su
  /// transacción y sin esperar. Sin ella, ninguna autorización vale.
  AgroRepository(
    this.appDatabase, {
    FarmerOperationGate gate = const FarmerOperationGate.unrestricted(),
    LocalOwnerCredential? Function()? ownerCredential,
    @visibleForTesting Future<Directory> Function()? productPhotoDocuments,
  }) : _session = RepositorySession(
         appDatabase,
         gate: gate,
         ownerCredential: ownerCredential,
       ),
       _productPhotoDocuments = productPhotoDocuments;

  final AppDatabase appDatabase;
  final RepositorySession _session;
  final StockFifoQueries _fifoQueries = const StockFifoQueries();
  late final CatalogRepository _catalogs = CatalogRepository(
    _session,
    productPhotoDocuments: _productPhotoDocuments,
  );
  late final CampaignRepository _campaigns = CampaignRepository(_session);
  late final PurchaseRepository _purchases = PurchaseRepository(
    _session,
    _campaigns,
  );
  late final ApplicationPlanRepository _applications =
      ApplicationPlanRepository(_session, _campaigns, _fifoQueries);
  late final InventoryRepository _inventory = InventoryRepository(_session);
  late final TransferRepository _transfers = TransferRepository(_session);
  late final AccountRepository _accounts = AccountRepository(_session);
  late final ReversalRepository _reversals = ReversalRepository(_session);
  late final LateOperationRepository _lateOperations = LateOperationRepository(
    _session,
    _campaigns,
    _purchases,
    _applications,
    _fifoQueries,
  );

  /// Carpeta de documentos para las fotos de producto; sólo pruebas.
  final Future<Directory> Function()? _productPhotoDocuments;

  @override
  Future<int> addPerson({
    required String name,
    required PersonRole role,
    SettlementPolicy? policy,
    String? phone,
  }) =>
      _catalogs.addPerson(name: name, role: role, policy: policy, phone: phone);

  @override
  Future<int> addFarm({
    required int ownerId,
    required String name,
    required int areaM2,
    String? location,
  }) => _catalogs.addFarm(
    ownerId: ownerId,
    name: name,
    areaM2: areaM2,
    location: location,
  );

  /// Alta de campaña (RN-16: los períodos no se solapan).
  @override
  Future<int> addCampaign({
    required String name,
    required DateTime start,
    DateTime? end,
  }) => _campaigns.addCampaign(name: name, start: start, end: end);

  /// Inicio que propone el alta: hoy, salvo que el orden del calendario
  /// exija uno posterior.
  @override
  Future<DateTime> suggestedCampaignStart() =>
      _campaigns.suggestedCampaignStart();

  /// Fin previsto de una campaña activa o planificada (D-F04-C2).
  Future<void> setCampaignEnd(int campaignId, {required DateTime end}) =>
      _campaigns.setCampaignEnd(campaignId, end: end);

  @override
  Future<void> setCampaignPeriod(
    CampaignPeriod before,
    CampaignPeriod proposed,
  ) => _campaigns.setCampaignPeriod(before, proposed);

  @override
  Future<Map<String, Object?>?> activeCampaign() => _campaigns.activeCampaign();

  @override
  Future<void> activateCampaign(int campaignId, {bool closeCurrent = false}) =>
      _campaigns.activateCampaign(campaignId, closeCurrent: closeCurrent);

  /// Cierre sin sucesora.
  @override
  Future<void> closeCampaign(int campaignId, {DateTime? end}) =>
      _campaigns.closeCampaign(campaignId, end: end);

  /// Estados en los que un plan todavía **no se ha consumido**.
  ///
  /// `DRAFT` es el valor por defecto histórico de la columna; `addPlanMulti`
  /// siempre escribe `PLANNED`. Se aceptan los dos para no dejar fuera a bases
  /// antiguas.
  static const pendingPlanStatuses =
      ApplicationPlanRepository.pendingPlanStatuses;

  /// Estado de un plan ya consumido por su aplicación.
  static const appliedPlanStatus = ApplicationPlanRepository.appliedPlanStatus;

  @override
  Future<int> addProduct({
    required String name,
    String? activeIngredient,
    String unit = 'L',
  }) => _catalogs.addProduct(
    name: name,
    activeIngredient: activeIngredient,
    unit: unit,
  );

  @override
  Future<int> addSupplier({
    required String name,
    String? phone,
    String? notes,
  }) => _catalogs.addSupplier(name: name, phone: phone, notes: notes);

  Future<int> addPlan({
    required int farmId,
    required int campaignId,
    required int productId,
    required int areaM2,
    required int doseBasePerHa,
    DateTime? plannedDate,
  }) => _applications.addPlan(
    farmId: farmId,
    campaignId: campaignId,
    productId: productId,
    areaM2: areaM2,
    doseBasePerHa: doseBasePerHa,
    plannedDate: plannedDate,
  );

  @override
  Future<int> addPlanMulti({
    required int farmId,
    required int campaignId,
    required int areaM2,
    required List<PlanItemDraft> items,
    DateTime? plannedDate,
    String? notes,
  }) => _applications.addPlanMulti(
    farmId: farmId,
    campaignId: campaignId,
    areaM2: areaM2,
    items: items,
    plannedDate: plannedDate,
    notes: notes,
  );

  /// Confirma la compra y, con [paidInFull], registra en la **misma
  /// transacción** el pago del total al proveedor a nombre del titular vigente.
  @override
  Future<int> confirmPurchase(
    PurchaseDraft draft, {
    ProviderPaymentDetails? paidInFull,
  }) => _purchases.confirmPurchase(draft, paidInFull: paidInFull);

  /// Pago posterior al proveedor.
  Future<int> addProviderPayment({
    required int purchaseId,
    required int payerPersonId,
    required int amountBobMinor,
    required PaymentMethod method,
    DateTime? date,
  }) => _purchases.addProviderPayment(
    purchaseId: purchaseId,
    payerPersonId: payerPersonId,
    amountBobMinor: amountBobMinor,
    method: method,
    date: date,
  );

  @override
  Future<int> confirmApplication(ApplicationDraft draft) =>
      _applications.confirmApplication(draft);

  // ---------------------------------------------------------------------
  // RF-03: operaciones tardías con revisión
  // (docs/architecture/F04_RF13_RF03_ACTOR_Y_TARDIAS.md §2)
  // ---------------------------------------------------------------------

  /// Guarda una compra de una campaña cerrada como borrador pendiente (§2.1).
  Future<String> captureLatePurchase(
    PurchaseDraft draft, {
    required String reason,
  }) => _lateOperations.captureLatePurchase(draft, reason: reason);

  /// Guarda una aplicación de una campaña cerrada como borrador pendiente (§2.1).
  Future<String> captureLateApplication(
    ApplicationDraft draft, {
    required String reason,
  }) => _lateOperations.captureLateApplication(draft, reason: reason);

  /// Borradores tardíos, los pendientes primero.
  Future<List<Map<String, Object?>>> lateOperationDrafts() =>
      _lateOperations.lateOperationDrafts();

  /// Confirma un borrador tardío con la autorización del titular (§2.1 paso 5).
  Future<LateResolution> confirmLateOperation(
    String draftRef, {
    required OwnerAuthorization authorization,
  }) => _lateOperations.confirmLateOperation(
    draftRef,
    authorization: authorization,
  );

  /// Rechaza un borrador tardío con la autorización del titular: sin efectos.
  Future<LateResolution> rejectLateOperation(
    String draftRef, {
    required OwnerAuthorization authorization,
    String? note,
  }) => _lateOperations.rejectLateOperation(
    draftRef,
    authorization: authorization,
    note: note,
  );

  /// Período histórico cerrado (RF-03 §2.5).
  Future<int> addHistoricalCampaign({
    required String name,
    required DateTime start,
    required DateTime end,
  }) => _campaigns.addHistoricalCampaign(name: name, start: start, end: end);

  Future<int> addAccountPayment({
    required int personId,
    int? campaignId,
    required int amountBobMinor,
    bool advance = false,
    DateTime? date,
    String? notes,
  }) => _accounts.addAccountPayment(
    personId: personId,
    campaignId: campaignId,
    amountBobMinor: amountBobMinor,
    advance: advance,
    date: date,
    notes: notes,
  );

  /// Registra un pago o adelanto y lo imputa a las deudas más antiguas de la
  /// persona (RN-38), de cualquier campaña.
  Future<AccountPaymentResult> registerAccountPayment({
    required int personId,
    int? campaignId,
    required int amountBobMinor,
    bool advance = false,
    DateTime? date,
    String? notes,
  }) => _accounts.registerAccountPayment(
    personId: personId,
    campaignId: campaignId,
    amountBobMinor: amountBobMinor,
    advance: advance,
    date: date,
    notes: notes,
  );

  /// RF-13: revierte una aplicación con la autorización del titular.
  Future<void> reverseApplication(
    int applicationId, {
    required String reason,
    required OwnerAuthorization authorization,
  }) => _reversals.reverseApplication(
    applicationId,
    reason: reason,
    authorization: authorization,
  );

  /// Sólo pruebas: los efectos de la reversión sin auditoría ni autorización.
  @visibleForTesting
  Future<void> reverseApplicationUnauditedForTesting(
    int applicationId, {
    String? reason,
  }) => _reversals.reverseApplicationUnauditedForTesting(
    applicationId,
    reason: reason,
  );

  /// RF-13: revierte una compra con la autorización del titular (§1).
  Future<void> reversePurchase(
    int purchaseId, {
    required String reason,
    required OwnerAuthorization authorization,
  }) => _reversals.reversePurchase(
    purchaseId,
    reason: reason,
    authorization: authorization,
  );

  /// Sólo pruebas: los efectos de la reversión sin auditoría ni autorización.
  @visibleForTesting
  Future<void> reversePurchaseUnauditedForTesting(
    int purchaseId, {
    String? reason,
  }) =>
      _reversals.reversePurchaseUnauditedForTesting(purchaseId, reason: reason);

  Future<int> transferStock({
    required int sourceLotId,
    required int destinationPersonId,
    required int quantityBase,
    DateTime? date,
    String? notes,
  }) => _transfers.transferStock(
    sourceLotId: sourceLotId,
    destinationPersonId: destinationPersonId,
    quantityBase: quantityBase,
    date: date,
    notes: notes,
  );

  Future<int> transferProductFifo({
    required int fromPersonId,
    required int toPersonId,
    required int productId,
    required int quantityBase,
    DateTime? date,
    String? notes,
  }) => _transfers.transferProductFifo(
    fromPersonId: fromPersonId,
    toPersonId: toPersonId,
    productId: productId,
    quantityBase: quantityBase,
    date: date,
    notes: notes,
  );

  Future<int> transferProductsFifo({
    required int fromPersonId,
    required int toPersonId,
    required List<TransferItemDraft> items,
    DateTime? date,
    String? notes,
  }) => _transfers.transferProductsFifo(
    fromPersonId: fromPersonId,
    toPersonId: toPersonId,
    items: items,
    date: date,
    notes: notes,
  );

  /// RF-13: revierte una transferencia con la autorización del titular (§1).
  Future<void> reverseTransfer(
    int transferId, {
    required String reason,
    required OwnerAuthorization authorization,
  }) => _reversals.reverseTransfer(
    transferId,
    reason: reason,
    authorization: authorization,
  );

  /// Sólo pruebas: los efectos de la reversión sin auditoría ni autorización.
  @visibleForTesting
  Future<void> reverseTransferUnauditedForTesting(
    int transferId, {
    String? reason,
  }) =>
      _reversals.reverseTransferUnauditedForTesting(transferId, reason: reason);

  /// Auditoría de la reversión de una operación.
  Future<Map<String, Object?>?> reversalAudit(String type, int operationId) =>
      _reversals.reversalAudit(type, operationId);

  Future<List<Map<String, Object?>>> transfers({int limit = 50}) =>
      _transfers.transfers(limit: limit);

  @override
  Future<List<Map<String, Object?>>> availableProductsForOwner(
    int personId, {
    String query = '',
    int limit = 100,
  }) => _transfers.availableProductsForOwner(
    personId,
    query: query,
    limit: limit,
  );

  Future<List<Map<String, Object?>>> list(String table, {String? orderBy}) =>
      _catalogs.list(table, orderBy: orderBy);

  Future<void> renameCatalog(String table, int id, String name) =>
      _catalogs.renameCatalog(table, id, name);

  Future<void> archiveCatalog(String table, int id) =>
      _catalogs.archiveCatalog(table, id);

  @override
  Future<List<Map<String, Object?>>> people() => _catalogs.people();

  /// Modalidad y titular vigentes, sólo para presentar opciones. Cada
  /// escritura los vuelve a leer dentro de su propia transacción.
  @override
  Future<WriteContext> operatingContext() => _session.operatingContext();

  /// Personas activas que pueden cumplir [purpose] según el titular y la
  /// modalidad (`person_roles.dart`). Una sola consulta: personas, modalidad
  /// y titular se leen juntos.
  @override
  Future<List<Map<String, Object?>>> peopleFor(PersonPurpose purpose) =>
      _catalogs.peopleFor(purpose);

  /// Como [peopleFor], y además la modalidad y el titular con que se
  /// filtró, para que el formulario sepa si debe ocultar la elección de
  /// persona (#26). Sigue siendo una sola consulta.
  @override
  Future<({List<Map<String, Object?>> people, WriteContext context})>
  peopleAndContextFor(PersonPurpose purpose) =>
      _catalogs.peopleAndContextFor(purpose);

  @override
  Future<List<Map<String, Object?>>> products() => _catalogs.products();
  @override
  Future<List<Map<String, Object?>>> suppliers() => _catalogs.suppliers();
  @override
  Future<List<Map<String, Object?>>> campaigns() => _campaigns.campaigns();
  @override
  Future<List<Map<String, Object?>>> farms() => _catalogs.farms();

  /// Chacos que se pueden planificar o aplicar según la modalidad: en propio,
  /// sólo los del titular (#26). Una sola consulta con modalidad y titular.
  @override
  Future<({List<Map<String, Object?>> farms, WriteContext context})>
  farmsAndContext() => _catalogs.farmsAndContext();

  @override
  Future<List<Map<String, Object?>>> purchases({int limit = 200}) =>
      _purchases.purchases(limit: limit);

  /// Detalle de una compra tal como está guardada (A2).
  Future<PurchaseDetailRead?> purchaseDetail(int purchaseId) =>
      _purchases.purchaseDetail(purchaseId);

  Future<List<Map<String, Object?>>> applications({
    int? campaignId,
    int? personId,
    int? farmId,
    int? productId,
    int? limit,
  }) => _applications.applications(
    campaignId: campaignId,
    personId: personId,
    farmId: farmId,
    productId: productId,
    limit: limit,
  );

  /// Planes con sus productos.
  @override
  Future<List<Map<String, Object?>>> plans({
    int limit = 400,
    bool includeApplied = false,
  }) => _applications.plans(limit: limit, includeApplied: includeApplied);

  @override
  Future<List<Map<String, Object?>>> planForApplication(int planId) =>
      _applications.planForApplication(planId);
  Future<List<Map<String, Object?>>> stock() => _inventory.stock();

  @override
  Future<List<Map<String, Object?>>> inventorySummary({int? limit}) =>
      _inventory.inventorySummary(limit: limit);

  Future<List<Map<String, Object?>>> personStockSummary(int personId) =>
      _inventory.personStockSummary(personId);

  Future<Map<String, Object?>> inventoryProductHeader(int productId) =>
      _inventory.inventoryProductHeader(productId);

  Future<List<Map<String, Object?>>> inventoryProductDistribution(
    int productId,
  ) => _inventory.inventoryProductDistribution(productId);

  /// Largo máximo del número de lote (decisión del autor del 2026-11-01).
  static const int maxLotNumberLength = repositoryMaxLotNumberLength;

  /// Plazo de aviso admitido, en días.
  static const int maxAlertLeadDays = repositoryMaxAlertLeadDays;

  /// Si se puede corregir la línea: existe y su compra no está revertida.
  Future<bool> canCorrectLotData(int purchaseItemId) =>
      _inventory.canCorrectLotData(purchaseItemId);

  /// Número de lote sin espacios a los lados; vacío es «sin dato» (null).
  static String? normalizeLotNumber(String? value) =>
      normalizeRepositoryLotNumber(value);

  /// Mensaje si [text] (sin los espacios de los lados) pasa del largo máximo.
  static String? lotNumberLengthError(String text) =>
      repositoryLotNumberLengthError(text);

  /// Referencia que firma la autorización de una corrección.
  static String lotDataSubjectRef(int purchaseItemId) =>
      InventoryRepository.lotDataSubjectRef(purchaseItemId);

  /// Corrige el vencimiento y el número de lote de una línea de compra (RF-42).
  Future<LotDataCorrectionResult> correctLotData(
    int purchaseItemId, {
    required String? expiryDay,
    required String? lotNumber,
    required String reason,
    required OwnerAuthorization authorization,
  }) => _inventory.correctLotData(
    purchaseItemId,
    expiryDay: expiryDay,
    lotNumber: lotNumber,
    reason: reason,
    authorization: authorization,
  );

  /// Sólo pruebas: la corrección sin autorización, para preparar datos.
  @visibleForTesting
  Future<void> setLotDataUnauditedForTesting(
    int lotId, {
    String? expiryDay,
    String? lotNumber,
  }) => _inventory.setLotDataUnauditedForTesting(
    lotId,
    expiryDay: expiryDay,
    lotNumber: lotNumber,
  );

  /// Correcciones de una línea de compra, de la más reciente a la más antigua.
  Future<List<Map<String, Object?>>> lotDataCorrections(int purchaseItemId) =>
      _inventory.lotDataCorrections(purchaseItemId);

  /// Nivel mínimo (unidad base) y plazo de aviso (días) de un producto (RF-44).
  Future<void> setProductAlertSettings(
    int productId, {
    required int? minStockBase,
    required int? leadDays,
  }) => _inventory.setProductAlertSettings(
    productId,
    minStockBase: minStockBase,
    leadDays: leadDays,
  );

  /// Configuración de avisos de un producto.
  Future<ProductAlertSettings> productAlertSettings(int productId) =>
      _inventory.productAlertSettings(productId);

  /// Avisos de existencias y vencimiento (RF-43, RF-44, CU-22).
  Future<InventoryAlerts> inventoryAlerts({DateTime? now}) =>
      _inventory.inventoryAlerts(now: now);

  Future<List<Map<String, Object?>>> inventoryProductLots(
    int productId, {
    int? personId,
    int? supplierId,
    int? campaignId,
    bool includeExhausted = false,
    String? expiryThrough,
    int limit = 500,
    int offset = 0,
  }) => _inventory.inventoryProductLots(
    productId,
    personId: personId,
    supplierId: supplierId,
    campaignId: campaignId,
    includeExhausted: includeExhausted,
    expiryThrough: expiryThrough,
    limit: limit,
    offset: offset,
  );

  Future<List<({int availableBase, String? expiryDay})>>
  inventoryProductExpiryTotals(int productId) =>
      _inventory.inventoryProductExpiryTotals(productId);

  /// Historial del producto movimiento a movimiento, del más reciente al más
  /// antiguo (E-10).
  Future<List<Map<String, Object?>>> productMovements(
    int productId, {
    int limit = 20,
    ProductMovementFilter filter = ProductMovementFilter.all,
  }) => _inventory.productMovements(productId, limit: limit, filter: filter);

  @override
  Future<List<Map<String, Object?>>> personProfiles() =>
      _catalogs.personProfiles();

  Future<Map<String, Object?>> personProfile(int personId) =>
      _catalogs.personProfile(personId);

  Future<List<Map<String, Object?>>> farmsForPerson(int personId) =>
      _catalogs.farmsForPerson(personId);

  Future<Map<String, Object?>> farmProfile(int farmId) =>
      _catalogs.farmProfile(farmId);

  Future<List<Map<String, Object?>>> farmLogbook(
    int farmId, {
    int? campaignId,
    int? productId,
  }) => _applications.farmLogbook(
    farmId,
    campaignId: campaignId,
    productId: productId,
  );

  @override
  Future<Map<String, Object?>> campaignCloseSummary(int campaignId) =>
      _campaigns.campaignCloseSummary(campaignId);

  /// Libro de cuentas en **una** consulta (`readAccountLedger`).
  @override
  Future<AccountLedger> accountLedger({
    int? personId,
    bool withDetails = true,
  }) => _accounts.accountLedger(personId: personId, withDetails: withDetails);

  /// Filas de la lista de Cuentas (§2.3).
  Future<List<AccountSummary>> accountSummaries({int? campaignId}) =>
      _accounts.accountSummaries(campaignId: campaignId);

  /// Estado de cuenta (§2.5).
  Future<AccountStatement> accountStatement(int personId, {int? campaignId}) =>
      _accounts.accountStatement(personId, campaignId: campaignId);

  /// Heredada: sólo caracterización (EVO-004); la app usa `accountStatement` (D-04).
  @override
  Future<Map<String, Object?>> personCampaignBalance(
    int personId,
    int campaignId,
  ) => _accounts.personCampaignBalance(personId, campaignId);

  Future<Map<String, Object?>> productStockInsight({
    required int personId,
    required int productId,
    required int campaignId,
  }) => _applications.productStockInsight(
    personId: personId,
    productId: productId,
    campaignId: campaignId,
  );

  /// Previsión de **sólo lectura** de los lotes que consumiría una aplicación.
  @override
  Future<List<ApplicationLotPreview>> previewApplicationLots({
    required int personId,
    required int productId,
    required int quantityBase,
    required DateTime appliedAt,
  }) => _applications.previewApplicationLots(
    personId: personId,
    productId: productId,
    quantityBase: quantityBase,
    appliedAt: appliedAt,
  );

  @override
  Future<int> estimateFifoCost({
    required int personId,
    required int productId,
    required int quantityBase,
  }) => _applications.estimateFifoCost(
    personId: personId,
    productId: productId,
    quantityBase: quantityBase,
  );

  /// Heredada: sólo caracterización (EVO-004); la app usa `accountSummaries` (D-04).
  @override
  Future<List<Map<String, Object?>>> settlements({int? campaignId}) =>
      _accounts.settlements(campaignId: campaignId);

  @override
  Future<List<Map<String, Object?>>> topSettlements({int limit = 5}) =>
      _accounts.topSettlements(limit: limit);

  /// Heredada: sólo caracterización (EVO-004); la app usa `accountStatement` (D-04).
  Future<List<Map<String, Object?>>> statement(
    int personId, {
    int? campaignId,
  }) => _accounts.statement(personId, campaignId: campaignId);

  /// Heredada: sólo caracterización (EVO-004); la app usa `accountStatement`; Personas la usa hasta E-15 (D-04).
  @override
  Future<List<Map<String, Object?>>> detailedStatement(
    int personId, {
    int? campaignId,
  }) => _accounts.detailedStatement(personId, campaignId: campaignId);

  @override
  Future<List<Map<String, Object?>>> farmCostReport({int? campaignId}) =>
      _accounts.farmCostReport(campaignId: campaignId);

  @override
  Future<List<Map<String, Object?>>> productCostReport({int? campaignId}) =>
      _accounts.productCostReport(campaignId: campaignId);

  Future<DashboardSummary> dashboard() => _accounts.dashboard();

  /// Foto de la etiqueta de [productId] (E1-D10), o null si no tiene.
  /// [ProductPhoto.exists] es falso si la base la registra pero el archivo
  /// ya no está en el teléfono.
  Future<ProductPhoto?> productPhoto(int productId) =>
      _catalogs.productPhoto(productId);

  /// Guarda como foto de la etiqueta de [productId] la imagen de
  /// [sourcePath], ya procesada: orientación aplicada, lado mayor ≤ 1600 px y
  /// JPEG sin metadatos. Reemplazar borra el archivo anterior.
  Future<ProductPhoto> setProductPhoto(
    int productId,
    String sourcePath, {
    bool? shareWithUnion,
  }) => _catalogs.setProductPhoto(
    productId,
    sourcePath,
    shareWithUnion: shareWithUnion,
  );

  /// Quita la foto de la etiqueta de [productId]: borra el archivo y deja
  /// las columnas en NULL.
  Future<void> removeProductPhoto(int productId) =>
      _catalogs.removeProductPhoto(productId);

  /// Sólo copia un archivo: basta la compuerta, no hay contexto de modalidad.
  Future<String> storeInvoiceImage(String sourcePath) =>
      _purchases.storeInvoiceImage(sourcePath);
}
