import 'dart:io';

import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Tests de las consultas de LECTURA: reportes, dashboard, inventario y
/// perfiles. Cubren el hueco identificado como STAB-006.
///
/// Los valores esperados se derivan a mano en los comentarios, nunca
/// reproduciendo la fórmula de producción. Un error en una consulta de lectura
/// es silencioso —muestra un número equivocado sin fallar—, así que el valor
/// esperado tiene que calcularse de forma independiente.
void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late AgroRepository repo;
  late int family, admin, supplier, farm, campaign1, campaign2;
  late int glifosato, paraquat;

  // ── Escenario base ────────────────────────────────────────────────────────
  //
  // Chaco: 10 ha  (100 000 m²), propiedad del familiar.
  //
  // Compra (campaña 1):
  //   Glifosato  20 L  a Bs 100,00/L  -> 20 × 100      = Bs 2 000,00
  //   Paraquat   10 KG a Bs  50,00/KG -> 10 ×  50      = Bs   500,00
  //                                       total compra = Bs 2 500,00
  //   'Aceite' se da de alta pero NO se compra ni se aplica nunca.
  //
  // Aplicación (campaña 1): 5 L de Glifosato
  //   costo FIFO = 5 L × Bs 100,00/L = Bs 500,00
  //
  // En unidades internas: cantidad ×1000, dinero ×100.
  setUp(() async {
    database = AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    repo = AgroRepository(database);

    family = await repo.addPerson(name: 'Familiar', role: PersonRole.family);
    admin = await repo.addPerson(name: 'Admin', role: PersonRole.admin);
    supplier = await repo.addSupplier(name: 'Proveedor');
    farm = await repo.addFarm(
      ownerId: family,
      name: 'Chaco Grande',
      areaM2: 100000,
    );
    campaign1 = await repo.addCampaign(
      name: 'Campaña 1',
      start: DateTime.utc(2026, 1, 1),
    );
    glifosato = await repo.addProduct(name: 'Glifosato');
    paraquat = await repo.addProduct(name: 'Paraquat', unit: 'KG');
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
              AllocationDraft(personId: family, quantityBase: 20000),
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

    campaign2 = await repo.addCampaign(
      name: 'Campaña 2',
      start: DateTime.utc(2026, 7, 1),
    );
  });

  tearDown(() => database.close());

  group('productCostReport', () {
    test('sin filtro incluye TODOS los productos, con y sin consumo', () async {
      final rows = await repo.productCostReport();
      // Los tres productos del catálogo deben aparecer.
      expect(
        rows.map((r) => r['name']),
        containsAll(['Glifosato', 'Paraquat', 'Aceite']),
      );
      expect(rows, hasLength(3));

      final glifo = rows.firstWhere((r) => r['name'] == 'Glifosato');
      expect(glifo['quantity_base'], 5000); // 5 L aplicados
      expect(glifo['total_cost_bob_minor'], 50000); // Bs 500,00

      final para = rows.firstWhere((r) => r['name'] == 'Paraquat');
      expect(para['quantity_base'], 0);
      expect(para['total_cost_bob_minor'], 0);
    });

    test('STAB-005: filtrado por campaña sigue incluyendo los productos sin consumo', () async {
      final rows = await repo.productCostReport(campaignId: campaign1);

      // Un producto sin aplicaciones en la campaña debe aparecer en CERO,
      // no desaparecer del reporte: "Aceite" y "Paraquat" nunca se aplicaron.
      expect(
        rows.map((r) => r['name']),
        containsAll(['Glifosato', 'Paraquat', 'Aceite']),
        reason:
            'Poner la condición de campaña en el WHERE convierte el LEFT JOIN '
            'en INNER JOIN y elimina los productos sin consumo.',
      );
      expect(rows, hasLength(3));

      final glifo = rows.firstWhere((r) => r['name'] == 'Glifosato');
      expect(glifo['quantity_base'], 5000);
      expect(glifo['total_cost_bob_minor'], 50000);

      for (final name in ['Paraquat', 'Aceite']) {
        final row = rows.firstWhere((r) => r['name'] == name);
        expect(row['quantity_base'], 0, reason: '$name no se aplicó nunca');
        expect(
          row['total_cost_bob_minor'],
          0,
          reason: '$name no se aplicó nunca',
        );
      }
    });

    test(
      'una campaña sin aplicaciones da todos los productos en cero',
      () async {
        final rows = await repo.productCostReport(campaignId: campaign2);
        expect(rows, hasLength(3));
        for (final row in rows) {
          expect(row['quantity_base'], 0);
          expect(row['total_cost_bob_minor'], 0);
        }
      },
    );

    test('una aplicación revertida deja de contar', () async {
      final applicationId = (await repo.applications()).single['id']! as int;
      await repo.reverseApplication(applicationId);

      final rows = await repo.productCostReport(campaignId: campaign1);
      final glifo = rows.firstWhere((r) => r['name'] == 'Glifosato');
      expect(glifo['total_cost_bob_minor'], 0);
      expect(glifo['quantity_base'], 0);
    });
  });

  group('farmCostReport', () {
    test('suma el costo de las aplicaciones del chaco', () async {
      final rows = await repo.farmCostReport();
      expect(rows, hasLength(1));
      // Única aplicación: Bs 500,00.
      expect(rows.single['total_cost_bob_minor'], 50000);
      expect(rows.single['area_m2'], 100000);
      expect(rows.single['name'], 'Chaco Grande');
    });

    test(
      'filtrado por campaña sin aplicaciones da cero, sin perder el chaco',
      () async {
        final rows = await repo.farmCostReport(campaignId: campaign2);
        expect(rows, hasLength(1), reason: 'El chaco debe seguir apareciendo.');
        expect(rows.single['total_cost_bob_minor'], 0);
      },
    );

    test('una aplicación revertida no suma', () async {
      final applicationId = (await repo.applications()).single['id']! as int;
      await repo.reverseApplication(applicationId);
      final rows = await repo.farmCostReport(campaignId: campaign1);
      expect(rows.single['total_cost_bob_minor'], 0);
    });
  });

  group('dashboard', () {
    test('resume compras, stock y saldos con los valores esperados', () async {
      final summary = await repo.dashboard();

      // Total comprado = Bs 2 000 + Bs 500 = Bs 2 500,00
      expect(summary.purchasesBobMinor, 250000);

      // Sin pagos a proveedor registrados.
      expect(summary.providerPaidMinor, 0);

      // El familiar se cobra por consumo: única aplicación = Bs 500,00.
      expect(summary.familyReceivableMinor, 50000);

      // No hay terceros en el escenario.
      expect(summary.thirdPartyReceivableMinor, 0);

      // Sin pagos ni adelantos recibidos.
      expect(summary.receivedMinor, 0);

      // Stock físico = comprado 20 000 + 10 000, consumido 5 000 => 25 000.
      expect(summary.stockBase, 25000);
    });

    test('refleja pagos de proveedor y de cuenta', () async {
      final purchaseId = (await repo.purchases()).single['id']! as int;
      await repo.addProviderPayment(
        purchaseId: purchaseId,
        payerPersonId: admin,
        amountBobMinor: 100000, // Bs 1 000,00
        method: 'TRANSFER',
      );
      await repo.addAccountPayment(
        personId: family,
        campaignId: campaign1,
        amountBobMinor: 20000, // Bs 200,00
      );

      final summary = await repo.dashboard();
      expect(summary.providerPaidMinor, 100000);
      expect(summary.receivedMinor, 20000);
      // Saldo del familiar: cargo 50 000 - pago 20 000 = 30 000.
      expect(summary.familyReceivableMinor, 30000);
    });

    test('base vacía devuelve todo en cero sin lanzar', () async {
      // Se usa un archivo temporal, no `:memory:`: sqflite_common_ffi comparte
      // la misma base entre aperturas con esa ruta, así que una segunda base
      // "vacía" en memoria vería los datos del setUp.
      final directory = await Directory.systemTemp.createTemp('agro_empty_');
      addTearDown(() => directory.delete(recursive: true));
      final empty = AppDatabase(
        factory: databaseFactoryFfi,
        path: p.join(directory.path, 'empty.db'),
      );
      addTearDown(empty.close);
      final summary = await AgroRepository(empty).dashboard();
      expect(summary.purchasesBobMinor, 0);
      expect(summary.providerPaidMinor, 0);
      expect(summary.familyReceivableMinor, 0);
      expect(summary.thirdPartyReceivableMinor, 0);
      expect(summary.receivedMinor, 0);
      expect(summary.stockBase, 0);
    });
  });

  group('inventorySummary', () {
    test(
      'separa unidades y calcula físico, comprometido y proyectado',
      () async {
        final rows = await repo.inventorySummary();
        expect(rows, hasLength(3));

        final glifo = rows.firstWhere((r) => r['product_name'] == 'Glifosato');
        expect(glifo['unit'], 'L');
        expect(glifo['purchased_base'], 20000);
        expect(glifo['consumed_base'], 5000);
        expect(glifo['available_base'], 15000); // 20 000 - 5 000
        expect(glifo['committed_base'], 0); // aún no hay planes
        expect(glifo['projected_base'], 15000);

        final para = rows.firstWhere((r) => r['product_name'] == 'Paraquat');
        expect(para['unit'], 'KG');
        expect(para['available_base'], 10000);

        final oil = rows.firstWhere((r) => r['product_name'] == 'Aceite');
        expect(oil['available_base'], 0);
      },
    );

    test('un plan pendiente compromete stock y reduce la proyección', () async {
      // 10 ha × 1 L/ha = 10 L = 10 000 base.
      await repo.addPlanMulti(
        farmId: farm,
        campaignId: campaign1,
        areaM2: 100000,
        items: [PlanItemDraft(productId: glifosato, doseBasePerHa: 1000)],
      );

      final glifo = (await repo.inventorySummary()).firstWhere(
        (r) => r['product_name'] == 'Glifosato',
      );
      expect(glifo['committed_base'], 10000);
      // Físico 15 000 - comprometido 10 000 = 5 000.
      expect(glifo['projected_base'], 5000);
    });

    test('STAB-011: el valor del inventario usa redondeo mitad arriba, no truncamiento', () async {
      // Se compra una cantidad que fuerza una división no exacta:
      // 1 unidad base (1 ml) a Bs 1,00/L -> 1 × 100 / 1000 = 0,1 centavos.
      // Con redondeo mitad arriba el resultado es 0; con truncamiento también.
      // El caso discriminante es 5 unidades base: 5 × 100 / 1000 = 0,5
      // -> mitad arriba = 1 centavo, truncamiento = 0.
      final producto = await repo.addProduct(name: 'Redondeo');
      await repo.confirmPurchase(
        PurchaseDraft(
          supplierId: supplier,
          campaignId: campaign1,
          purchaseDate: DateTime.utc(2026, 3, 1),
          items: [
            PurchaseItemDraft(
              productId: producto,
              quantityBase: 5,
              currency: CurrencyCode.bob,
              originalUnitPriceMinor: 100,
              allocations: [AllocationDraft(personId: family, quantityBase: 5)],
            ),
          ],
        ),
      );

      final row = (await repo.inventorySummary()).firstWhere(
        (r) => r['product_name'] == 'Redondeo',
      );
      expect(
        row['available_value_bob_minor'],
        1,
        reason:
            'El proyecto redondea mitad arriba en todo cálculo monetario '
            '(divideRoundedHalfUp). El valor de inventario no debe truncar.',
      );
    });
  });

  group('personProfiles', () {
    test('expone superficie y saldo del familiar', () async {
      final rows = await repo.personProfiles();
      final person = rows.firstWhere((r) => r['id'] == family);
      expect(person['area_m2'], 100000); // 10 ha
      expect(person['balance'], 50000); // cargo por consumo Bs 500,00
    });

    test('personProfile individual coincide con el listado', () async {
      final profile = await repo.personProfile(family);
      expect(profile['area_m2'], 100000);
      expect(profile['balance'], 50000);
    });
  });

  group('campaignCloseSummary', () {
    test('cuenta compras, aplicaciones y saldo por cobrar', () async {
      final summary = await repo.campaignCloseSummary(campaign1);
      expect(summary['purchases_count'], 1);
      expect(summary['purchases_bob_minor'], 250000); // Bs 2 500,00
      expect(summary['applications_count'], 1);
      expect(summary['applications_bob_minor'], 50000); // Bs 500,00
      expect(summary['pending_plans'], 0);
      expect(summary['receivable_bob_minor'], 50000);
    });

    test('cuenta los planes pendientes', () async {
      await repo.addPlanMulti(
        farmId: farm,
        campaignId: campaign1,
        areaM2: 100000,
        items: [PlanItemDraft(productId: glifosato, doseBasePerHa: 1000)],
      );
      final summary = await repo.campaignCloseSummary(campaign1);
      expect(summary['pending_plans'], 1);
    });
  });
}
