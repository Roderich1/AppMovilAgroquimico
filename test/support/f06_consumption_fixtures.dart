// F06 (MOB #32/#33): base local con titular, un familiar, tres productos
// vinculados (dos en L y uno en KG), uno sin vincular y existencias de todos.
// Datos sintéticos.
import 'package:agroquimicos/data/sync/consumption_publisher.dart';
import 'package:agroquimicos/domain/models.dart';

import 'f04_mode_fixtures.dart';
import 'f05_sync_fixtures.dart';

const extraLitreRef = '6a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';

class ConsumptionFixture {
  ConsumptionFixture({
    required this.sync,
    required this.publisher,
    required this.ownerPersonId,
    required this.familyPersonId,
    required this.ownerFarmId,
    required this.familyFarmId,
    required this.extraLitreProductId,
  });

  final SyncFixture sync;
  final ConsumptionPublisher publisher;
  final int ownerPersonId;
  final int familyPersonId;
  final int ownerFarmId;
  final int familyFarmId;
  final int extraLitreProductId;

  /// Confirma una aplicación de [person] con estas líneas (producto → base).
  Future<int> apply(int person, Map<int, int> lines, {int? farm}) =>
      sync.repo.confirmApplication(
        ApplicationDraft(
          personId: person,
          farmId:
              farm ?? (person == ownerPersonId ? ownerFarmId : familyFarmId),
          campaignId: sync.campaignId,
          appliedAt: DateTime(2026, 10, 1, 9),
          lines: [
            for (final MapEntry(key: product, value: quantity) in lines.entries)
              ApplicationLineDraft(productId: product, quantityBase: quantity),
          ],
        ),
      );
}

Future<ConsumptionFixture> seedConsumptionFixture({String? path}) async {
  final sync = await seedSyncFixture(path: path);
  final repo = sync.repo;
  final owner = (await sync.owners.activeBinding())!.personId;
  final family = await repo.addPerson(
    name: 'Familiar sintético',
    role: PersonRole.family,
  );
  final extra = await repo.addProduct(name: 'Insecticida local', unit: 'L');
  await sync.bindings.bindProduct(
    productId: extra,
    central: centralProduct(ref: extraLitreRef, name: 'Insecticida central'),
    tenantId: memberA.tenantId,
  );
  final supplier = await repo.addSupplier(name: 'Proveedor sintético');
  final ownerFarm = await repo.addFarm(
    ownerId: owner,
    name: 'Chaco del titular',
    areaM2: 10000,
  );
  final familyFarm = await repo.addFarm(
    ownerId: family,
    name: 'Chaco familiar',
    areaM2: 10000,
  );
  await repo.confirmPurchase(
    PurchaseDraft(
      supplierId: supplier,
      campaignId: sync.campaignId,
      purchaseDate: DateTime(2026, 9, 15),
      items: [
        for (final product in [
          sync.litreProductId,
          sync.kiloProductId,
          extra,
          sync.unboundProductId,
        ])
          PurchaseItemDraft(
            productId: product,
            quantityBase: 200000,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 1000,
            allocations: [
              AllocationDraft(personId: owner, quantityBase: 150000),
              AllocationDraft(personId: family, quantityBase: 50000),
            ],
          ),
      ],
    ),
  );
  return ConsumptionFixture(
    sync: sync,
    publisher: ConsumptionPublisher(sync.database),
    ownerPersonId: owner,
    familyPersonId: family,
    ownerFarmId: ownerFarm,
    familyFarmId: familyFarm,
    extraLitreProductId: extra,
  );
}
