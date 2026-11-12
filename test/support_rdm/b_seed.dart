// Datos sintéticos de la sesión B del rediseño (Inicio, Actividad, Almacén,
// Personas): nombres largos, decimales, litros y kilos, lotes vencidos, que
// vencen hoy y por vencer, saldo con el proveedor, deudas de un familiar y
// un tercero, un plan pendiente y una transferencia. Nada es real.
import 'package:agroquimicos/domain/models.dart';

import '../support/f04_mode_fixtures.dart';

/// Lo que [seedSessionB] creó, para que las capturas y las pruebas lleguen a
/// cada pantalla.
class SeedB {
  SeedB({
    required this.longProduct,
    required this.insecticide,
    required this.urea,
    required this.partialPurchase,
    required this.unpaidPurchase,
    required this.plan,
  });

  final int longProduct;
  final int insecticide;
  final int urea;
  final int partialPurchase;
  final int unpaidPurchase;
  final int plan;
}

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Siembra sobre un hogar ya creado ([Household]): titular, «Hermana»
/// (familiar) y «Vecino» (tercero). [today] fija el día local de los
/// vencimientos.
Future<SeedB> seedSessionB(Household h, {DateTime? today}) async {
  final repo = h.repo;
  final now = today ?? DateTime.now();
  final day = DateTime(now.year, now.month, now.day);
  DateTime ago(int days) => DateTime.utc(day.year, day.month, day.day - days);

  final supplier = await repo.addSupplier(name: 'Agroinsumos del Valle');
  final longProduct = await repo.addProduct(
    name: 'Fungicida sistémico de amplio espectro Carbendazim 50 SC',
  );
  final insecticide = await repo.addProduct(name: 'Insecticida');
  final urea = await repo.addProduct(name: 'Urea granulada', unit: 'KG');

  PurchaseItemDraft item(
    int product,
    int quantity,
    int price,
    List<AllocationDraft> allocations, {
    String? expiry,
    String? lot,
  }) => PurchaseItemDraft(
    productId: product,
    quantityBase: quantity,
    currency: CurrencyCode.bob,
    originalUnitPriceMinor: price,
    allocations: allocations,
    expiryDay: expiry,
    lotNumber: lot,
  );

  // Compra con pago parcial: un lote vence hoy y otro venció ayer.
  final partial = await repo.confirmPurchase(
    PurchaseDraft(
      supplierId: supplier,
      campaignId: h.campaign,
      purchaseDate: ago(12),
      invoiceNumber: 'SINT-002',
      items: [
        item(
          longProduct,
          10000,
          15000,
          [AllocationDraft(personId: h.titular, quantityBase: 10000)],
          expiry: _day(day),
          lot: 'L-2291',
        ),
        item(insecticide, 4000, 9000, [
          AllocationDraft(personId: h.thirdParty, quantityBase: 4000),
        ], expiry: _day(day.subtract(const Duration(days: 1)))),
      ],
    ),
  );
  await repo.addProviderPayment(
    purchaseId: partial,
    payerPersonId: h.titular,
    amountBobMinor: 60000,
    method: PaymentMethod.transfer,
    date: ago(11),
  );

  // Compra sin pagar, repartida con decimales, por vencer en 15 días.
  final unpaid = await repo.confirmPurchase(
    PurchaseDraft(
      supplierId: h.supplier,
      campaignId: h.campaign,
      purchaseDate: ago(8),
      items: [
        item(h.product, 14500, 10050, [
          AllocationDraft(personId: h.titular, quantityBase: 8500),
          AllocationDraft(personId: h.relative, quantityBase: 6000),
        ], expiry: _day(day.add(const Duration(days: 15)))),
      ],
    ),
  );

  // Compra pagada en kilos, sin vencimiento.
  await repo.confirmPurchase(
    PurchaseDraft(
      supplierId: supplier,
      campaignId: h.campaign,
      purchaseDate: ago(6),
      items: [
        item(urea, 50000, 450, [
          AllocationDraft(personId: h.titular, quantityBase: 50000),
        ]),
      ],
    ),
    paidInFull: ProviderPaymentDetails(
      method: PaymentMethod.cash,
      date: ago(6),
    ),
  );

  await repo.confirmApplication(
    ApplicationDraft(
      personId: h.relative,
      farmId: h.relativeFarm,
      campaignId: h.campaign,
      appliedAt: ago(4),
      lines: [ApplicationLineDraft(productId: h.product, quantityBase: 5000)],
    ),
  );
  await repo.confirmApplication(
    ApplicationDraft(
      personId: h.titular,
      farmId: h.titularFarm,
      campaignId: h.campaign,
      appliedAt: ago(3),
      lines: [ApplicationLineDraft(productId: h.product, quantityBase: 2500)],
    ),
  );

  await repo.transferProductFifo(
    fromPersonId: h.titular,
    toPersonId: h.relative,
    productId: longProduct,
    quantityBase: 2000,
    date: ago(2),
  );

  final plan = await repo.addPlan(
    farmId: h.titularFarm,
    campaignId: h.campaign,
    productId: longProduct,
    areaM2: 10000,
    doseBasePerHa: 6000,
    plannedDate: ago(-3),
  );

  await repo.addAccountPayment(
    personId: h.relative,
    campaignId: h.campaign,
    amountBobMinor: 20000,
    date: ago(1),
  );

  await repo.setProductAlertSettingsWithoutPinForTesting(
    insecticide,
    minStockBase: 5000,
    leadDays: null,
  );
  await repo.setProductAlertSettingsWithoutPinForTesting(
    h.product,
    minStockBase: 10000,
    leadDays: 30,
  );

  return SeedB(
    longProduct: longProduct,
    insecticide: insecticide,
    urea: urea,
    partialPurchase: partial,
    unpaidPurchase: unpaid,
    plan: plan,
  );
}
