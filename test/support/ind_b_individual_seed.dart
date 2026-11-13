// Base SINTÉTICA del modo individual para la sesión B (Almacén, Actividad y
// Proveedores; láminas I-04, I-05, I-30, I-31, I-33). Parte de
// `activatedHousehold` (titular vinculado, otra familiar y un tercero sin
// existencias ni saldos), renombra al titular y pasa la base al modo
// individual con las condiciones reales (`OperationModeStore.apply`), sin
// forzar la bandera. Todo lo registrado es del titular.
//
//   Agroinsumos: compra 1 (hace 12 días) 14 L de herbicida, pagada entera;
//                compra 2 (hace 8 días) 10 L de fungicida + 12 L de
//                herbicida, pagó 600,00; compra 3 (hace 3 días) 4 L de
//                fungicida que vence en 10 días + 4 L de insecticida, sin
//                pagos.
//   El Sembrador: compra 4 (hace 2 días) 25 kg de fertilizante, sin pagos.
//   Aplicación (hace 5 días) en Chaco Norte: 6 L de herbicida.
//   Plan pendiente en Chaco Norte: 6 L de fungicida (1 ha × 6 L/ha).
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/operation_mode.dart';

import 'f04_mode_fixtures.dart';

const indBLongName =
    'Herbicida glifosato concentrado soluble 480 g/L, bidón azul';

class IndBSeed {
  IndBSeed({
    required this.titular,
    required this.herbicide,
    required this.fungicide,
    required this.insecticide,
    required this.fertilizer,
    required this.farm,
    required this.paidPurchase,
    required this.partialPurchase,
    required this.unpaidPurchase,
    required this.otherSupplierPurchase,
  });

  final int titular;
  final int herbicide;
  final int fungicide;
  final int insecticide;
  final int fertilizer;
  final int farm;
  final int paidPurchase;
  final int partialPurchase;
  final int unpaidPurchase;
  final int otherSupplierPurchase;
}

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Renombra al titular, siembra los datos y pasa a modo individual. Falla si
/// las condiciones reales del cambio de modo no se cumplen.
Future<IndBSeed> seedIndividualB(Household h, {DateTime? today}) async {
  final repo = h.repo;
  final db = await repo.appDatabase.database;
  await db.update(
    'persons',
    {'name': 'Rosa Vargas'},
    where: 'id=?',
    whereArgs: [h.titular],
  );
  final now = today ?? DateTime.now();
  final day = DateTime(now.year, now.month, now.day);
  DateTime ago(int days) =>
      DateTime.utc(day.year, day.month, day.day - days, 12);
  String inDays(int days) =>
      _day(DateTime(day.year, day.month, day.day + days));

  final agro = await repo.addSupplier(name: 'Agroinsumos');
  final sembrador = await repo.addSupplier(name: 'El Sembrador');
  final herbicide = await repo.addProduct(name: indBLongName);
  final fungicide = await repo.addProduct(name: 'Fungicida');
  final insecticide = await repo.addProduct(name: 'Insecticida');
  final fertilizer = await repo.addProduct(
    name: 'Fertilizante foliar',
    unit: 'KG',
  );
  final farm = await repo.addFarm(
    ownerId: h.titular,
    name: 'Chaco Norte',
    areaM2: 10000,
  );

  PurchaseItemDraft item(
    int product,
    int quantity,
    int price, {
    String? expiry,
  }) => PurchaseItemDraft(
    productId: product,
    quantityBase: quantity,
    currency: CurrencyCode.bob,
    originalUnitPriceMinor: price,
    allocations: [AllocationDraft(personId: h.titular, quantityBase: quantity)],
    expiryDay: expiry,
  );

  Future<int> buy(int supplier, DateTime date, List<PurchaseItemDraft> items) =>
      repo.confirmPurchase(
        PurchaseDraft(
          supplierId: supplier,
          campaignId: h.campaign,
          purchaseDate: date,
          items: items,
        ),
      );

  // 14 L × 60,00 = 840,00, pagada entera.
  final paid = await buy(agro, ago(12), [item(herbicide, 14000, 6000)]);
  await repo.addProviderPayment(
    purchaseId: paid,
    payerPersonId: h.titular,
    amountBobMinor: 84000,
    method: PaymentMethod.cash,
    date: ago(12),
  );
  // 10 L × 90,00 + 12 L × 80,00 = 1.860,00; pagó 600,00.
  final partial = await buy(agro, ago(8), [
    item(fungicide, 10000, 9000),
    item(herbicide, 12000, 8000),
  ]);
  await repo.addProviderPayment(
    purchaseId: partial,
    payerPersonId: h.titular,
    amountBobMinor: 60000,
    method: PaymentMethod.transfer,
    date: ago(8),
  );
  // 4 L × 95,00 + 4 L × 61,25 = 625,00; sin pagos.
  final unpaid = await buy(agro, ago(3), [
    item(fungicide, 4000, 9500, expiry: inDays(10)),
    item(insecticide, 4000, 6125),
  ]);
  // 25 kg × 12,00 = 300,00; sin pagos.
  final other = await buy(sembrador, ago(2), [item(fertilizer, 25000, 1200)]);

  await repo.confirmApplication(
    ApplicationDraft(
      personId: h.titular,
      farmId: farm,
      campaignId: h.campaign,
      appliedAt: ago(5),
      lines: [ApplicationLineDraft(productId: herbicide, quantityBase: 6000)],
    ),
  );
  await repo.addPlan(
    farmId: farm,
    campaignId: h.campaign,
    productId: fungicide,
    areaM2: 10000,
    doseBasePerHa: 6000,
    plannedDate: DateTime.utc(day.year, day.month, day.day + 7, 12),
  );

  final decision = await OperationModeStore(repo.appDatabase)
      .apply(OperationMode.personal, confirmed: true);
  if (!decision.allowed) {
    throw StateError('La base no cumple el modo individual: $decision');
  }
  return IndBSeed(
    titular: h.titular,
    herbicide: herbicide,
    fungicide: fungicide,
    insecticide: insecticide,
    fertilizer: fertilizer,
    farm: farm,
    paidPurchase: paid,
    partialPurchase: partial,
    unpaidPurchase: unpaid,
    otherSupplierPurchase: other,
  );
}
