// Modo individual — lecturas de «Chacos» (sesión C, 2026-11-13). Comprueba
// que las cifras salen de los mismos criterios que los informes existentes
// (`farmCostReport`, `productCostReport`), con el alcance del titular en modo
// individual, sin escribir nada en la base.
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/ind_c_chacos_reads.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/presentation/widgets/ind_c_chacos_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_app_access.dart';
import 'support/f04_mode_fixtures.dart';

void main() {
  sqfliteFfiInit();

  /// Titular con dos chacos (Norte 3 ha y un nombre largo de 0,5 ha), una
  /// hermana con su chaco, dos productos de unidades distintas (L y kg) y
  /// una segunda campaña sin aplicaciones.
  Future<
    ({
      AgroRepository repo,
      Household h,
      int norte,
      int largo,
      int kg,
      int campaign2,
    })
  >
  world(String name) async {
    final database = openDb(await tempDbPath(name));
    final binding = await seedActivatedInstallation(database);
    final repo = AgroRepository(database);
    final relative = await repo.addPerson(
      name: 'Hermana',
      role: PersonRole.family,
    );
    final h = Household(repo, binding.personId, relative, relative)
      ..supplier = await repo.addSupplier(name: 'Proveedor')
      ..campaign = await repo.addCampaign(
        name: 'Invierno 2026',
        start: DateTime.utc(2026, 1, 1),
      )
      ..product = await repo.addProduct(name: 'Herbicida');
    h
      ..titularFarm = await repo.addFarm(
        ownerId: binding.personId,
        name: 'Chaco Norte',
        areaM2: 30000,
      )
      ..relativeFarm = await repo.addFarm(
        ownerId: relative,
        name: 'Chaco hermana',
        areaM2: 5000,
      );
    final largo = await repo.addFarm(
      ownerId: binding.personId,
      name: 'Chaco de la loma grande junto al río Piraí, parcela del fondo',
      areaM2: 5000,
    );
    final kg = await repo.addProduct(name: 'Fertilizante foliar', unit: 'KG');
    // Compras del titular: 11 L de herbicida a 100 Bs/L y 4 kg de
    // fertilizante a 50 Bs/kg. La hermana no tiene existencias ni saldo (si
    // no, el paso a modo individual se bloquearía).
    await h.buy(h.titular, 11000);
    await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: h.supplier,
        campaignId: h.campaign,
        purchaseDate: DateTime.utc(2026, 1, 3),
        items: [
          PurchaseItemDraft(
            productId: kg,
            quantityBase: 4000,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 5000,
            allocations: [
              AllocationDraft(personId: h.titular, quantityBase: 4000),
            ],
          ),
        ],
      ),
    );
    // Norte: 2 L con 1 ha tratada y 6 L con 3 ha tratadas; la loma: 1 kg
    // sin superficie tratada; en el chaco de la hermana, 1 L que aplicó el
    // titular en el modo con varias personas (historial ajeno al titular).
    await repo.confirmApplication(
      ApplicationDraft(
        personId: h.titular,
        farmId: h.titularFarm,
        campaignId: h.campaign,
        appliedAt: DateTime.utc(2026, 2, 1),
        treatedAreaM2: 10000,
        lines: [ApplicationLineDraft(productId: h.product, quantityBase: 2000)],
      ),
    );
    await repo.confirmApplication(
      ApplicationDraft(
        personId: h.titular,
        farmId: h.titularFarm,
        campaignId: h.campaign,
        appliedAt: DateTime.utc(2026, 2, 2),
        treatedAreaM2: 30000,
        lines: [ApplicationLineDraft(productId: h.product, quantityBase: 6000)],
      ),
    );
    await repo.confirmApplication(
      ApplicationDraft(
        personId: h.titular,
        farmId: largo,
        campaignId: h.campaign,
        appliedAt: DateTime.utc(2026, 2, 3),
        lines: [ApplicationLineDraft(productId: kg, quantityBase: 1000)],
      ),
    );
    await h.apply(h.titular, h.relativeFarm, 1000);
    final campaign2 = await repo.addCampaign(
      name: 'Verano 2027',
      start: DateTime.utc(2026, 9, 1),
    );
    return (
      repo: repo,
      h: h,
      norte: h.titularFarm,
      largo: largo,
      kg: kg,
      campaign2: campaign2,
    );
  }

  Future<void> personal(AgroRepository repo) =>
      OperationModeStore(repo.appDatabase)
          .apply(OperationMode.personal, confirmed: true);

  test('modo individual: sólo los chacos del titular, con el costo del '
      'informe «Costo por chaco» y el costo por hectárea sobre la superficie '
      'del chaco', () async {
    final w = await world('ind_c_personal');
    await personal(w.repo);
    final db = await w.repo.appDatabase.database;
    final before = await dumpTables(db);

    final chacos = await w.repo.indCChacos(useActiveCampaign: true);
    expect(chacos.scope.personal, isTrue);
    expect(chacos.campaign?.name, 'Invierno 2026');
    expect(chacos.farms.map((f) => f.name), [
      'Chaco de la loma grande junto al río Piraí, parcela del fondo',
      'Chaco Norte',
    ]);
    final report = {
      for (final row in await w.repo.farmCostReport(campaignId: w.h.campaign))
        row['id']! as int: row['total_cost_bob_minor']! as int,
    };
    final norte = chacos.farms.firstWhere((f) => f.farmId == w.norte);
    expect(norte.appliedCostMinor, report[w.norte]);
    expect(norte.appliedCostMinor, 80000); // 8 L × 100 Bs
    expect(norte.applicationCount, 2);
    // 800,00 Bs ÷ 3 ha = 266,67 Bs/ha (no se divide por la tratada, 4 ha).
    expect(norte.costPerHectareMinor, 26667);
    expect(norte.treatedAreaM2, 40000);
    expect(norte.applicationsWithTreatedArea, 2);
    expect(
      indCTreatedAreaLine(norte),
      'Superficie tratada acumulada: 4 ha en 2 aplicaciones',
    );
    final largo = chacos.farms.firstWhere((f) => f.farmId == w.largo);
    expect(largo.appliedCostMinor, report[w.largo]);
    expect(largo.applicationsWithTreatedArea, 0);
    expect(indCTreatedAreaLine(largo), isNull);
    // Total: sólo los del titular (sin el chaco de la hermana).
    expect(chacos.appliedCostMinor, report[w.norte]! + report[w.largo]!);
    expect(
      chacos.appliedCostMinor,
      isNot(report.values.reduce((a, b) => a + b)),
    );

    // Leer no escribe nada.
    expect(await dumpTables(db), before);
  });

  test('modo con varias personas: todos los chacos y el mismo total que el '
      'informe', () async {
    final w = await world('ind_c_shared');
    final chacos = await w.repo.indCChacos(campaignId: w.h.campaign);
    expect(chacos.scope.personal, isFalse);
    expect(chacos.farms, hasLength(3));
    final report = await w.repo.farmCostReport(campaignId: w.h.campaign);
    expect(
      chacos.appliedCostMinor,
      report.fold<int>(0, (s, r) => s + (r['total_cost_bob_minor']! as int)),
    );
  });

  test('por producto: cantidades separadas por unidad y el costo de '
      '«Costo por producto»', () async {
    final w = await world('ind_c_products');
    await personal(w.repo);
    final products = await w.repo.indCProductCosts(campaignId: w.h.campaign);
    final herbicida = products.firstWhere((p) => p.unit == 'L');
    final fertilizante = products.firstWhere((p) => p.unit == 'KG');
    // Del titular: 8 L (no los 9 L con la hermana) y 1 kg.
    expect(herbicida.quantityBase, 8000);
    expect(herbicida.costMinor, 80000);
    expect(herbicida.applicationCount, 2);
    expect(fertilizante.quantityBase, 1000);
    expect(fertilizante.costMinor, 5000);

    // Sin la hermana, coincide con el informe existente.
    final shared = await w.repo.productCostReport(campaignId: w.h.campaign);
    final reportHerb = shared.firstWhere((r) => r['unit'] == 'L');
    expect(reportHerb['quantity_base'], 9000); // incluye la hermana
    final reportKg = shared.firstWhere((r) => r['unit'] == 'KG');
    expect(reportKg['total_cost_bob_minor'], fertilizante.costMinor);
  });

  test('alcance: otra campaña sin aplicaciones no muestra costos y «todas» '
      'suma lo de la activa; una aplicación anulada no cuenta', () async {
    final w = await world('ind_c_scope');
    await personal(w.repo);
    final other = await w.repo.indCChacos(campaignId: w.campaign2);
    expect(other.campaign?.name, 'Verano 2027');
    expect(other.applicationCount, 0);
    expect(other.appliedCostMinor, 0);
    final norteOther = other.farms.firstWhere((f) => f.farmId == w.norte);
    expect(norteOther.costPerHectareMinor, isNull);
    expect(
      indCPerHectareUnavailableReason(norteOther),
      'Sin aplicaciones en este alcance: no hay costo que repartir.',
    );
    final all = await w.repo.indCChacos();
    final active = await w.repo.indCChacos(campaignId: w.h.campaign);
    expect(all.campaign, isNull);
    expect(all.appliedCostMinor, active.appliedCostMinor);

    // Anular la aplicación de la loma: su costo deja de contar.
    final app = (await w.repo.applications(farmId: w.largo)).single;
    await w.repo.reverseApplicationUnauditedForTesting(
      app['id']! as int,
      reason: 'prueba',
    );
    final after = await w.repo.indCChacos(campaignId: w.h.campaign);
    final largo = after.farms.firstWhere((f) => f.farmId == w.largo);
    expect(largo.applicationCount, 0);
    expect(largo.appliedCostMinor, 0);
    final campaigns = await w.repo.indCCampaignCosts();
    expect(campaigns.map((c) => c.campaign.name), [
      'Verano 2027',
      'Invierno 2026',
    ]);
    expect(campaigns.last.costMinor, 80000);
    expect(campaigns.last.applicationCount, 2);
    expect(campaigns.first.applicationCount, 0);
  });

  test('sin superficie utilizable (fila anómala): «No disponible», nunca '
      'cero', () {
    const farm = IndCFarm(
      farmId: 1,
      name: 'Antiguo',
      areaM2: 0,
      ownerPersonId: 1,
      ownerName: 'Titular',
      active: true,
      applicationCount: 2,
      appliedCostMinor: 50000,
      treatedAreaM2: 0,
      applicationsWithTreatedArea: 0,
      pendingPlanCount: 0,
    );
    expect(farm.hasArea, isFalse);
    expect(farm.costPerHectareMinor, isNull);
    expect(
      indCPerHectareUnavailableReason(farm),
      'Falta registrar la superficie del chaco.',
    );
  });

  test('detalle: plan por hacer sin tocar existencias, aplicaciones con su '
      'superficie tratada y productos utilizados; un chaco ajeno no se abre '
      'en modo individual', () async {
    final w = await world('ind_c_detail');
    await w.repo.addPlan(
      farmId: w.norte,
      campaignId: w.h.campaign,
      productId: w.h.product,
      areaM2: 30000,
      doseBasePerHa: 2000,
      plannedDate: DateTime.utc(2026, 11, 20),
    );
    await personal(w.repo);
    final db = await w.repo.appDatabase.database;
    final stockBefore = await stockByPersonProduct(db);

    final d = (await w.repo.indCChacoDetail(w.norte))!;
    expect(d.campaign?.name, 'Invierno 2026');
    expect(d.farm.areaM2, 30000);
    expect(d.plans, hasLength(1));
    expect(d.plans.single.items.single.quantityBase, 6000); // 3 ha × 2 L
    expect(d.plans.single.plannedDate, startsWith('2026-11-20'));
    expect(d.farm.pendingPlanCount, 1);
    expect(d.applications.map((a) => a.treatedAreaM2), [30000, 10000]);
    expect(d.applications.map((a) => a.costMinor), [60000, 20000]);
    expect(d.products.single.quantityBase, 8000);
    // El plan no descontó nada.
    expect(await stockByPersonProduct(db), stockBefore);

    expect(await w.repo.indCChacoDetail(w.h.relativeFarm), isNull);
  });

  test('un chaco archivado con aplicaciones sigue en los costos y sale de la '
      'lista', () async {
    final w = await world('ind_c_archived');
    await personal(w.repo);
    await w.repo.archiveCatalog('farms', w.largo);
    final chacos = await w.repo.indCChacos(campaignId: w.h.campaign);
    expect(chacos.farms.map((f) => f.farmId), contains(w.largo));
    expect(chacos.activeFarms.map((f) => f.farmId), isNot(contains(w.largo)));
    expect(chacos.appliedCostMinor, 85000);
  });
}
