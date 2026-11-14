// Datos SINTÉTICOS de la ronda 2 de la sesión B (detalle de producto de
// Almacén, avisos y lotes). Reproduce el caso de las capturas del autor con
// nombres inventados: dos personas, varios lotes con y sin vencimiento, con y
// sin número del fabricante, un lote por vencer, uno vencido y otros no, dos
// entradas de la misma persona el mismo día, un pase, aplicaciones y un plan
// pendiente que prevé consumo. Nada es real.
import 'package:agroquimicos/domain/models.dart';

import '../support/f04_mode_fixtures.dart';

/// Lo que [seedAlmacenB] creó, para llegar a cada pantalla.
class AlmacenSeedB {
  AlmacenSeedB({
    required this.product,
    required this.juan,
    required this.rosa,
    required this.purchaseWithLots,
    required this.purchaseWithoutNumber,
    required this.today,
  });

  /// «Herbicida sin red» (L).
  final int product;
  final int juan;
  final int rosa;

  /// Compra repartida entre Juan y Rosa, con vencimiento y número del
  /// fabricante.
  final int purchaseWithLots;

  /// Compra de Rosa sin vencimiento ni número del fabricante.
  final int purchaseWithoutNumber;

  /// Día local usado para los vencimientos.
  final DateTime today;
}

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Siembra sobre un hogar ya creado. [today] fija el día local de los
/// vencimientos (por defecto, el del equipo).
Future<AlmacenSeedB> seedAlmacenB(Household h, {DateTime? today}) async {
  final repo = h.repo;
  final now = today ?? DateTime.now();
  final day = DateTime(now.year, now.month, now.day);
  DateTime ago(int days) => DateTime.utc(day.year, day.month, day.day - days);
  String inDays(int days) =>
      _day(DateTime(day.year, day.month, day.day + days));

  final juan = await repo.addPerson(
    name: 'Juan Mamani',
    role: PersonRole.family,
  );
  final rosa = await repo.addPerson(
    name: 'Rosa Vargas',
    role: PersonRole.family,
  );
  final rio = await repo.addFarm(
    ownerId: juan,
    name: 'Chaco Rio',
    areaM2: 10000,
  );
  final norte = await repo.addFarm(
    ownerId: rosa,
    name: 'Chaco Norte',
    areaM2: 8000,
  );
  final supplier = await repo.addSupplier(name: 'Agroinsumos sin red');
  final product = await repo.addProduct(name: 'Herbicida sin red');

  PurchaseItemDraft item(
    int quantity,
    int price,
    int person, {
    String? expiry,
    String? lot,
  }) => PurchaseItemDraft(
    productId: product,
    quantityBase: quantity,
    currency: CurrencyCode.bob,
    originalUnitPriceMinor: price,
    allocations: [AllocationDraft(personId: person, quantityBase: quantity)],
    expiryDay: expiry,
    lotNumber: lot,
  );

  Future<int> buy(DateTime date, List<PurchaseItemDraft> items) =>
      repo.confirmPurchase(
        PurchaseDraft(
          supplierId: supplier,
          campaignId: h.campaign,
          purchaseDate: date,
          items: items,
        ),
      );

  // Rosa: 5 L baratos, sin vencimiento ni número del fabricante.
  final purchaseWithoutNumber = await buy(ago(30), [item(5000, 300, rosa)]);
  // Pase de 2 L de Rosa a Juan (entrega sin deuda).
  await repo.transferProductFifo(
    fromPersonId: rosa,
    toPersonId: juan,
    productId: product,
    quantityBase: 2000,
    date: ago(28),
  );
  // Juan: un lote vencido con número del fabricante.
  await buy(ago(25), [item(500, 4000, juan, expiry: inDays(-5), lot: 'VJ-07')]);
  // Juan y Rosa: una compra repartida (1 L cada uno) que vence lejos, con
  // número del fabricante.
  final purchaseWithLots = await repo.confirmPurchase(
    PurchaseDraft(
      supplierId: supplier,
      campaignId: h.campaign,
      purchaseDate: ago(20),
      invoiceNumber: 'SINT-B2',
      items: [
        PurchaseItemDraft(
          productId: product,
          quantityBase: 2000,
          currency: CurrencyCode.bob,
          originalUnitPriceMinor: 4500,
          allocations: [
            AllocationDraft(personId: juan, quantityBase: 1000),
            AllocationDraft(personId: rosa, quantityBase: 1000),
          ],
          expiryDay: inDays(200),
          lotNumber: 'HSR-2291',
        ),
      ],
    ),
  );
  // Rosa: dos entradas el mismo día (dos compras), por vencer dentro del
  // plazo inicial.
  await buy(ago(15), [item(1000, 4500, rosa, expiry: inDays(25))]);
  await buy(ago(15), [item(500, 4500, rosa, expiry: inDays(25))]);

  await repo.confirmApplication(
    ApplicationDraft(
      personId: juan,
      farmId: rio,
      campaignId: h.campaign,
      appliedAt: ago(10),
      lines: [ApplicationLineDraft(productId: product, quantityBase: 1000)],
    ),
  );
  await repo.confirmApplication(
    ApplicationDraft(
      personId: rosa,
      farmId: norte,
      campaignId: h.campaign,
      appliedAt: ago(8),
      lines: [ApplicationLineDraft(productId: product, quantityBase: 2500)],
    ),
  );
  await repo.confirmApplication(
    ApplicationDraft(
      personId: juan,
      farmId: rio,
      campaignId: h.campaign,
      appliedAt: ago(4),
      lines: [ApplicationLineDraft(productId: product, quantityBase: 500)],
    ),
  );

  // Plan pendiente: prevé 1,5 L (no aparta producto).
  await repo.addPlan(
    farmId: rio,
    campaignId: h.campaign,
    productId: product,
    areaM2: 10000,
    doseBasePerHa: 1500,
    plannedDate: ago(-3),
  );

  return AlmacenSeedB(
    product: product,
    juan: juan,
    rosa: rosa,
    purchaseWithLots: purchaseWithLots,
    purchaseWithoutNumber: purchaseWithoutNumber,
    today: day,
  );
}
