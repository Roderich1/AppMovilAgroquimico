import 'dart:io';

import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/typed_reads.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Paridad legacy/tipado (`EVO-004-REQ-002`).
///
/// Cada método tipado se compara con su método legacy sobre la MISMA base:
/// mismo número de filas, mismo orden y mismos enteros. Si alguien cambiara una
/// consulta creyendo que sólo afecta al camino tipado, aquí se vería.
void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late AgroRepository repo;
  late int family, third;
  late int campaign1, campaign2;

  setUp(() async {
    database = AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    repo = AgroRepository(database);

    await repo.addPerson(name: 'Administrador', role: PersonRole.admin);
    family = await repo.addPerson(
      name: 'Ana Familiar',
      role: PersonRole.family,
    );
    third = await repo.addPerson(
      name: 'Beto Tercero',
      role: PersonRole.thirdParty,
    );
    final supplier = await repo.addSupplier(name: 'Proveedor');
    final farm = await repo.addFarm(
      ownerId: family,
      name: 'Chaco Uno',
      areaM2: 100000,
    );
    campaign1 = await repo.addCampaign(
      name: 'Campaña 1',
      start: DateTime.utc(2026, 1, 1),
    );
    final glifosato = await repo.addProduct(name: 'Glifosato');
    final paraquat = await repo.addProduct(name: 'Paraquat', unit: 'KG');
    // Un producto que nunca se compra ni se aplica: las consultas de costo e
    // inventario lo incluyen con ceros y la paridad tiene que verlo igual.
    await repo.addProduct(name: 'Aceite');

    await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: supplier,
        campaignId: campaign1,
        purchaseDate: DateTime.utc(2026, 1, 10),
        items: [
          PurchaseItemDraft(
            productId: glifosato,
            quantityBase: 20000,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 10000,
            allocations: [
              AllocationDraft(personId: family, quantityBase: 15000),
              AllocationDraft(personId: third, quantityBase: 5000),
            ],
          ),
          PurchaseItemDraft(
            productId: paraquat,
            quantityBase: 10000,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 5000,
            allocations: [
              AllocationDraft(personId: family, quantityBase: 10000),
            ],
          ),
        ],
      ),
    );

    await repo.confirmApplication(
      ApplicationDraft(
        personId: family,
        farmId: farm,
        campaignId: campaign1,
        appliedAt: DateTime.utc(2026, 2, 1),
        treatedAreaM2: 100000,
        lines: [ApplicationLineDraft(productId: glifosato, quantityBase: 5000)],
      ),
    );

    await repo.addAccountPayment(
      personId: family,
      campaignId: campaign1,
      amountBobMinor: 20000,
      date: DateTime.utc(2026, 3, 1),
    );

    campaign2 = await repo.addCampaign(
      name: 'Campaña 2',
      start: DateTime.utc(2026, 7, 1),
    );
  });

  tearDown(() => database.close());

  test('campaignsTyped conserva filas, orden y valores', () async {
    final legacy = await repo.campaigns();
    final typed = await repo.campaignsTyped();
    expect(typed, hasLength(legacy.length));
    for (var i = 0; i < legacy.length; i++) {
      expect(typed[i].id, legacy[i]['id']);
      expect(typed[i].name, legacy[i]['name']);
      expect(typed[i].startDate, legacy[i]['start_date']);
      expect(typed[i].endDate, legacy[i]['end_date']);
      expect(typed[i].status, legacy[i]['status']);
    }
  });

  test('peopleTyped conserva filas, orden y valores', () async {
    final legacy = await repo.people();
    final typed = await repo.peopleTyped();
    expect(typed, hasLength(legacy.length));
    for (var i = 0; i < legacy.length; i++) {
      expect(typed[i].id, legacy[i]['id']);
      expect(typed[i].name, legacy[i]['name']);
      expect(typed[i].role, legacy[i]['role']);
      expect(typed[i].phone, legacy[i]['phone']);
    }
  });

  test('inventorySummaryTyped conserva filas, orden y valores', () async {
    final legacy = await repo.inventorySummary();
    final typed = await repo.inventorySummaryTyped();
    expect(typed, hasLength(legacy.length));
    for (var i = 0; i < legacy.length; i++) {
      expect(typed[i].productId, legacy[i]['product_id']);
      expect(typed[i].productName, legacy[i]['product_name']);
      expect(typed[i].unit, legacy[i]['unit']);
      expect(typed[i].purchasedBase, legacy[i]['purchased_base']);
      expect(typed[i].consumedBase, legacy[i]['consumed_base']);
      expect(typed[i].availableBase, legacy[i]['available_base']);
      expect(typed[i].committedBase, legacy[i]['committed_base']);
      expect(typed[i].projectedBase, legacy[i]['projected_base']);
      expect(
        typed[i].availableValueBobMinor,
        legacy[i]['available_value_bob_minor'],
      );
      expect(typed[i].peopleCount, legacy[i]['people_count']);
    }
  });

  test('inventorySummaryTyped respeta el límite', () async {
    final legacy = await repo.inventorySummary(limit: 2);
    final typed = await repo.inventorySummaryTyped(limit: 2);
    expect(typed, hasLength(2));
    expect(typed, hasLength(legacy.length));
    expect(typed.first.productId, legacy.first['product_id']);
  });

  test('settlementsTyped conserva filas, orden y valores', () async {
    for (final campaignId in <int?>[null, campaign1, campaign2]) {
      final legacy = await repo.settlements(campaignId: campaignId);
      final typed = await repo.settlementsTyped(campaignId: campaignId);
      expect(typed, hasLength(legacy.length));
      for (var i = 0; i < legacy.length; i++) {
        expect(typed[i].personId, legacy[i]['id']);
        expect(typed[i].name, legacy[i]['name']);
        expect(typed[i].role, legacy[i]['role']);
        expect(typed[i].balanceMinor, legacy[i]['balance']);
        expect(typed[i].chargesMinor, legacy[i]['charges']);
        expect(typed[i].paymentsMinor, legacy[i]['payments']);
      }
    }
  });

  test('topSettlementsTyped conserva filas, orden y límite', () async {
    for (final limit in [1, 5]) {
      final legacy = await repo.topSettlements(limit: limit);
      final typed = await repo.topSettlementsTyped(limit: limit);
      expect(typed, hasLength(legacy.length));
      for (var i = 0; i < legacy.length; i++) {
        expect(typed[i].personId, legacy[i]['id']);
        expect(typed[i].name, legacy[i]['name']);
        expect(typed[i].role, legacy[i]['role']);
        expect(typed[i].balanceMinor, legacy[i]['balance']);
      }
    }
  });

  test('productCostReportTyped conserva filas, orden y valores', () async {
    for (final campaignId in <int?>[null, campaign1, campaign2]) {
      final legacy = await repo.productCostReport(campaignId: campaignId);
      final typed = await repo.productCostReportTyped(campaignId: campaignId);
      expect(typed, hasLength(legacy.length));
      for (var i = 0; i < legacy.length; i++) {
        expect(typed[i].productId, legacy[i]['id']);
        expect(typed[i].productName, legacy[i]['name']);
        expect(typed[i].unit, legacy[i]['unit']);
        expect(typed[i].quantityBase, legacy[i]['quantity_base']);
        expect(typed[i].totalCostBobMinor, legacy[i]['total_cost_bob_minor']);
      }
    }
  });

  test('farmCostReportTyped conserva filas, orden y valores', () async {
    for (final campaignId in <int?>[null, campaign1, campaign2]) {
      final legacy = await repo.farmCostReport(campaignId: campaignId);
      final typed = await repo.farmCostReportTyped(campaignId: campaignId);
      expect(typed, hasLength(legacy.length));
      for (var i = 0; i < legacy.length; i++) {
        expect(typed[i].farmId, legacy[i]['id']);
        expect(typed[i].farmName, legacy[i]['name']);
        expect(typed[i].ownerName, legacy[i]['owner_name']);
        expect(typed[i].areaM2, legacy[i]['area_m2']);
        expect(typed[i].totalCostBobMinor, legacy[i]['total_cost_bob_minor']);
      }
    }
  });

  test('campaignCloseSummaryTyped conserva los seis totales', () async {
    for (final campaignId in [campaign1, campaign2]) {
      final legacy = await repo.campaignCloseSummary(campaignId);
      final typed = await repo.campaignCloseSummaryTyped(campaignId);
      expect(typed.purchasesCount, legacy['purchases_count']);
      expect(typed.purchasesBobMinor, legacy['purchases_bob_minor']);
      expect(typed.applicationsCount, legacy['applications_count']);
      expect(typed.applicationsBobMinor, legacy['applications_bob_minor']);
      expect(typed.pendingPlans, legacy['pending_plans']);
      expect(typed.receivableBobMinor, legacy['receivable_bob_minor']);
    }
  });

  test('personCampaignBalanceTyped conserva los cuatro totales', () async {
    for (final campaignId in [campaign1, campaign2]) {
      final legacy = await repo.personCampaignBalance(family, campaignId);
      final typed = await repo.personCampaignBalanceTyped(family, campaignId);
      expect(typed.openingBalanceMinor, legacy['opening_balance']);
      expect(typed.campaignChargesMinor, legacy['campaign_charges']);
      expect(typed.campaignPaymentsMinor, legacy['campaign_payments']);
      expect(typed.totalBalanceMinor, legacy['total_balance']);
    }
  });

  test('detailedStatementTyped conserva filas, orden y valores', () async {
    for (final personId in [family, third]) {
      for (final campaignId in <int?>[null, campaign1, campaign2]) {
        final legacy = await repo.detailedStatement(
          personId,
          campaignId: campaignId,
        );
        final typed = await repo.detailedStatementTyped(
          personId,
          campaignId: campaignId,
        );
        expect(typed, hasLength(legacy.length));
        for (var i = 0; i < legacy.length; i++) {
          expect(typed[i].id, legacy[i]['id']);
          expect(typed[i].transactionDate, legacy[i]['transaction_date']);
          expect(typed[i].type, legacy[i]['type']);
          expect(
            typed[i].amountBobMinorSigned,
            legacy[i]['amount_bob_minor_signed'],
          );
          expect(typed[i].campaignId, legacy[i]['campaign_id']);
          expect(typed[i].concept, legacy[i]['concept']);
          expect(typed[i].farmName, legacy[i]['farm_name']);
          expect(typed[i].notes, legacy[i]['notes']);
        }
      }
    }
  });

  test(
    'una reversión aparece igual en el camino legacy y en el tipado',
    () async {
      final applications = await repo.applications();
      await repo.reverseApplication(
        applications.first['id']! as int,
        reason: 'prueba',
      );
      final legacy = await repo.detailedStatement(family);
      final typed = await repo.detailedStatementTyped(family);
      expect(typed, hasLength(legacy.length));
      // La reversión añade un crédito compensatorio, no borra el cargo.
      expect(typed.map((e) => e.type), contains('CREDIT_ADJUSTMENT'));
      for (var i = 0; i < legacy.length; i++) {
        expect(
          typed[i].amountBobMinorSigned,
          legacy[i]['amount_bob_minor_signed'],
        );
      }
    },
  );

  test('una base sin datos devuelve vacío en ambos caminos', () async {
    // Base propia en disco: `inMemoryDatabasePath` comparte instancia con la
    // del `setUp`, así que no serviría para comprobar el caso vacío.
    final directory = await Directory.systemTemp.createTemp('agro_typed_');
    addTearDown(() => directory.delete(recursive: true));
    final empty = AppDatabase(
      factory: databaseFactoryFfi,
      path: p.join(directory.path, 'vacia.db'),
    );
    final emptyRepo = AgroRepository(empty);
    addTearDown(empty.close);
    expect(await emptyRepo.settlements(), isEmpty);
    expect(await emptyRepo.settlementsTyped(), isEmpty);
    expect(await emptyRepo.inventorySummary(), isEmpty);
    expect(await emptyRepo.inventorySummaryTyped(), isEmpty);
    expect(await emptyRepo.campaignsTyped(), isEmpty);
  });
}
