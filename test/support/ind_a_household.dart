// Hogar sintético en MODO INDIVIDUAL (sesión A del rediseño individual,
// 2026-11-13): instalación activada con titular, sin familiares ni terceros,
// un proveedor, una campaña, dos productos con existencias del titular y un
// chaco del titular. Cumple de verdad las condiciones del modo individual
// (`evaluateModeTransition`): no se fuerza la bandera sobre datos de terceros.
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:flutter_test/flutter_test.dart';

import 'f04_app_access.dart';
import 'f04_mode_fixtures.dart';

class IndAHousehold {
  IndAHousehold(this.repo, this.titular);
  final AgroRepository repo;
  final int titular;
  late int supplier;
  late int campaign;
  late int herbicida;
  late int fungicida;
  late int farm;
}

/// Compra sintética del titular: [quantityBase] en unidad base a
/// [unitPriceMinor] céntimos por unidad comercial.
Future<int> indABuy(
  IndAHousehold h, {
  required int product,
  required int quantityBase,
  required int unitPriceMinor,
}) => h.repo.confirmPurchase(
  PurchaseDraft(
    supplierId: h.supplier,
    campaignId: h.campaign,
    purchaseDate: DateTime.utc(2026, 7, 2),
    items: [
      PurchaseItemDraft(
        productId: product,
        quantityBase: quantityBase,
        currency: CurrencyCode.bob,
        originalUnitPriceMinor: unitPriceMinor,
        allocations: [
          AllocationDraft(personId: h.titular, quantityBase: quantityBase),
        ],
      ),
    ],
  ),
);

/// Hogar individual. Con [stock], Herbicida 26 L (120 Bs/L) y Fungicida
/// 14 L (150 Bs/L) en el almacén del titular.
Future<({AppDatabase database, IndAHousehold household})> personalHousehold(
  WidgetTester tester,
  String name, {
  bool stock = true,
}) async {
  final file = await tester.runAsync(() => tempDbPath(name));
  final database = openDb(file!);
  final household = await tester.runAsync(() async {
    final binding = await seedActivatedInstallation(database);
    final repo = AgroRepository(database);
    final h = IndAHousehold(repo, binding.personId)
      ..supplier = await repo.addSupplier(name: 'Agroinsumos')
      ..campaign = await repo.addCampaign(
        name: 'Invierno 2026',
        start: DateTime.utc(2026, 6, 21),
      )
      ..herbicida = await repo.addProduct(name: 'Herbicida')
      ..fungicida = await repo.addProduct(name: 'Fungicida');
    h.farm = await repo.addFarm(
      ownerId: binding.personId,
      name: 'Chaco Norte',
      areaM2: 30000,
    );
    if (stock) {
      await indABuy(
        h,
        product: h.herbicida,
        quantityBase: 26000,
        unitPriceMinor: 12000,
      );
      await indABuy(
        h,
        product: h.fungicida,
        quantityBase: 14000,
        unitPriceMinor: 15000,
      );
    }
    await OperationModeStore(database)
        .apply(OperationMode.personal, confirmed: true);
    return h;
  });
  return (database: database, household: household!);
}
