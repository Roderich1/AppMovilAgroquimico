// DEMO de Agrocuentas (OE3, 2026-11-03): datos LOCALES sintéticos del teléfono de
// la DEMO, sembrados con el propio código de la app (AgroRepository y
// CentralBindingStore) sobre una COPIA de la base extraída del emulador, después
// de activar la cuenta y crear el titular desde la interfaz (vínculo real con el
// Member). Patrón de tool/f10_ux/seed_dsux_mobile.dart. Se ejecuta en el PC:
//
//   DEMO_DB=/ruta/absoluta/agroquimicos_v2.db \
//   DEMO_REFERENCES=/ruta/absoluta/references.json \
//   DEMO_DATE=AAAA-MM-DD \
//   flutter test tool/demo/seed_demo_mobile.dart
//
// `DEMO_REFERENCES` es el cuerpo literal de `GET /api/v1/sync/v1/references` de la
// Agricultora DEMO. Es directo (no pasa por la interfaz) y queda documentado en
// docs/evidence/OE3_DEMO_2026-11-03.md: personas, proveedor, chacos, campaña,
// productos, compras, pagos, aplicaciones, transferencia, pagos de cuenta,
// vínculos con el sindicato y niveles mínimos (sin PIN: método de pruebas). No
// crea intenciones de sincronización ni toca la sesión. Si la copia ya está
// sembrada, se niega (repetir no duplica).
// Herramienta de siembra que se ejecuta con `flutter test` (no es código de la app):
// fija los niveles mínimos sin el PIN del titular con el método de pruebas.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:convert';
import 'dart:io';

import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/sync/central_binding_store.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/domain/sync/central_references.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const marker = 'Beto Mamani (DEMO)';

void main() {
  sqfliteFfiInit();

  test('siembra local de la DEMO en la copia indicada por DEMO_DB', () async {
    final env = Platform.environment;
    final path = env['DEMO_DB'];
    expect(path, isNotNull, reason: 'Defina DEMO_DB');
    expect(p.isAbsolute(path!), isTrue);
    expect(File(path).existsSync(), isTrue, reason: 'no existe $path');
    final references = CentralReferences.fromJson(
      jsonDecode(File(env['DEMO_REFERENCES']!).readAsStringSync())
          as Map<String, dynamic>,
    );
    final day = env['DEMO_DATE']!;
    final parts = day.split('-').map(int.parse).toList();
    DateTime at(int offset, [int hour = 10]) =>
        DateTime(parts[0], parts[1], parts[2] + offset, hour);
    String dayOf(int offset) {
      final d = at(offset);
      return '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }

    expect(
      at(0).timeZoneOffset,
      const Duration(hours: -4),
      reason: 'El PC debe estar en America/La_Paz (UTC−4).',
    );

    final database = AppDatabase(factory: databaseFactoryFfi, path: path);
    final db = await database.database;
    final repo = AgroRepository(database);
    Future<int> count(String sql, [List<Object?> args = const []]) async =>
        (await db.rawQuery(sql, args)).single.values.first! as int;

    // 1. Precondiciones: titular vinculado, modo compartido y copia sin sembrar.
    final already = await count('SELECT COUNT(*) FROM persons WHERE name = ?', [
      marker,
    ]);
    expect(
      already,
      0,
      reason: 'la copia ya tiene la siembra DEMO: no se repite',
    );
    final context = await repo.operatingContext();
    final owner = context.ownerPersonId;
    expect(
      owner,
      isNotNull,
      reason: 'active la cuenta y cree el titular antes',
    );
    expect(
      context.mode,
      OperationMode.shared,
      reason: 'la DEMO usa el modo compartido',
    );
    final tenantId =
        (await db.query(
              'owner_bindings',
              columns: ['tenant_id'],
              where: 'ended_at IS NULL',
            )).single['tenant_id']!
            as String;
    final outboxBefore = await count('SELECT COUNT(*) FROM sync_outbox');

    // 2. Catálogo y personas.
    final beto = await repo.addPerson(name: marker, role: PersonRole.family);
    final carmen = await repo.addPerson(
      name: 'Carmen Choque (DEMO, tercera)',
      role: PersonRole.thirdParty,
    );
    final supplier = await repo.addSupplier(
      name: 'Agroinsumos DEMO (sintético)',
    );
    final farmAna = await repo.addFarm(
      ownerId: owner!,
      name: 'Chaco Norte DEMO',
      areaM2: 30000,
    );
    final farmBeto = await repo.addFarm(
      ownerId: beto,
      name: 'Chaco Río DEMO',
      areaM2: 20000,
    );
    final centralCampaign = references.campaigns.singleWhere(
      (c) => c.name.startsWith('Invierno ${parts[0]} (DEMO)'),
    );
    final campaign = await repo.addCampaign(
      name: 'Invierno ${parts[0]} (DEMO)',
      start: at(-20),
      end: at(130),
    );
    await repo.activateCampaign(campaign);
    final product = <String, int>{};
    for (final name in [
      'Herbicida DEMO',
      'Fungicida DEMO',
      'Insecticida DEMO',
    ]) {
      product[name] = await repo.addProduct(name: name, unit: 'L');
    }

    // 3. Compras: pagada, con saldo pendiente y con lotes vencidos, de hoy,
    //    próximos y sin fecha.
    PurchaseItemDraft line(
      String name,
      int litres,
      int priceBob,
      List<AllocationDraft> to, {
      String? expiry,
      String? lot,
    }) => PurchaseItemDraft(
      productId: product[name]!,
      quantityBase: litres * 1000,
      currency: CurrencyCode.bob,
      originalUnitPriceMinor: priceBob * 100,
      allocations: to,
      expiryDay: expiry,
      lotNumber: lot,
    );
    await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: supplier,
        campaignId: campaign,
        purchaseDate: at(-15),
        invoiceNumber: 'DEMO-001',
        items: [
          line(
            'Herbicida DEMO',
            20,
            120,
            [
              AllocationDraft(personId: owner, quantityBase: 12000),
              AllocationDraft(personId: beto, quantityBase: 8000),
            ],
            expiry: dayOf(15),
            lot: 'H-DEMO-01',
          ),
        ],
      ),
      paidInFull: ProviderPaymentDetails(
        method: PaymentMethod.cash,
        date: at(-15),
      ),
    );
    final pending = await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: supplier,
        campaignId: campaign,
        purchaseDate: at(-10),
        invoiceNumber: 'DEMO-002',
        items: [
          line(
            'Fungicida DEMO',
            10,
            150,
            [AllocationDraft(personId: owner, quantityBase: 10000)],
            expiry: dayOf(0),
            lot: 'F-DEMO-02',
          ),
          line(
            'Insecticida DEMO',
            4,
            90,
            [AllocationDraft(personId: carmen, quantityBase: 4000)],
            expiry: dayOf(-1),
            lot: 'I-DEMO-03',
          ),
        ],
      ),
    );
    await repo.addProviderPayment(
      purchaseId: pending,
      payerPersonId: owner,
      amountBobMinor: 60000,
      method: PaymentMethod.transfer,
      date: at(-9),
    );
    await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: supplier,
        campaignId: campaign,
        purchaseDate: at(-5),
        invoiceNumber: 'DEMO-003',
        items: [
          line('Herbicida DEMO', 5, 125, [
            AllocationDraft(personId: owner, quantityBase: 5000),
          ]),
        ],
      ),
    );

    // 4. Aplicaciones (consumo FIFO) y transferencia entre responsables.
    await repo.confirmApplication(
      ApplicationDraft(
        personId: owner,
        farmId: farmAna,
        campaignId: campaign,
        appliedAt: at(-8),
        lines: [
          ApplicationLineDraft(
            productId: product['Herbicida DEMO']!,
            quantityBase: 6000,
          ),
        ],
      ),
    );
    await repo.confirmApplication(
      ApplicationDraft(
        personId: beto,
        farmId: farmBeto,
        campaignId: campaign,
        appliedAt: at(-3),
        lines: [
          ApplicationLineDraft(
            productId: product['Herbicida DEMO']!,
            quantityBase: 5000,
          ),
        ],
      ),
    );
    await repo.transferProductsFifo(
      fromPersonId: owner,
      toPersonId: beto,
      items: [
        TransferItemDraft(
          productId: product['Fungicida DEMO']!,
          quantityBase: 2000,
        ),
      ],
      date: at(-4),
    );

    // 5. Cuentas entre personas: pagos de cuenta (cargos por consumo y por compra).
    await repo.registerAccountPayment(
      personId: beto,
      campaignId: campaign,
      amountBobMinor: 20000,
      date: at(-2),
    );
    await repo.registerAccountPayment(
      personId: carmen,
      campaignId: campaign,
      amountBobMinor: 15000,
      date: at(-1),
    );

    // 6. Niveles mínimos: Insecticida bajo en total (4 L < 5 L) y Herbicida bajo
    //    para Beto (3 L) con el total por encima. Sin PIN: método de pruebas.
    await repo.setProductAlertSettingsWithoutPinForTesting(
      product['Insecticida DEMO']!,
      minStockBase: 5000,
      leadDays: 30,
    );
    await repo.setProductAlertSettingsWithoutPinForTesting(
      product['Herbicida DEMO']!,
      minStockBase: 4000,
      leadDays: 30,
    );
    await repo.setProductAlertSettingsWithoutPinForTesting(
      product['Fungicida DEMO']!,
      minStockBase: 2000,
      leadDays: 30,
    );

    // 7. Vínculos con el sindicato (como «Vincular con el sindicato»).
    final bindings = CentralBindingStore(database);
    await bindings.bindCampaign(
      campaignId: campaign,
      central: centralCampaign,
      tenantId: tenantId,
    );
    for (final entry in product.entries) {
      await bindings.bindProduct(
        productId: entry.value,
        central: references.products.singleWhere((c) => c.name == entry.key),
        tenantId: tenantId,
      );
    }

    // 8. Invariantes.
    final integrity = (await db.rawQuery('PRAGMA integrity_check'))
        .single
        .values
        .first;
    expect(integrity, 'ok');
    expect(
      await count('SELECT COUNT(*) FROM sync_outbox'),
      outboxBefore,
      reason: 'la siembra no crea envíos',
    );
    expect(
      await count(
        'SELECT COUNT(*) FROM (SELECT lot_id, SUM(quantity_signed) s FROM inventory_movements GROUP BY lot_id HAVING s < 0)',
      ),
      0,
      reason: 'ningún lote negativo',
    );
    final stock = await db.rawQuery(
      'SELECT pr.name producto, pe.name persona, SUM(m.quantity_signed) neto '
      'FROM inventory_movements m JOIN products pr ON pr.id = m.product_id '
      'JOIN persons pe ON pe.id = m.owner_person_id GROUP BY 1, 2 ORDER BY 1, 2',
    );
    final expected = {
      'Fungicida DEMO|$marker': 2000,
      'Herbicida DEMO|$marker': 3000,
      'Insecticida DEMO|Carmen Choque (DEMO, tercera)': 4000,
    };
    for (final row in stock) {
      final key = '${row['producto']}|${row['persona']}';
      if (expected.containsKey(key))
        expect(row['neto'], expected[key], reason: key);
    }
    final totals = {
      for (final name in product.keys)
        name: await count(
          'SELECT COALESCE(SUM(quantity_signed),0) FROM inventory_movements WHERE product_id=?',
          [product[name]],
        ),
    };
    expect(totals, {
      'Herbicida DEMO': 14000,
      'Fungicida DEMO': 10000,
      'Insecticida DEMO': 4000,
    });
    final summary = <String, Object?>{
      'personas': await count('SELECT COUNT(*) FROM persons'),
      'compras': await count('SELECT COUNT(*) FROM purchases'),
      'aplicaciones': await count('SELECT COUNT(*) FROM applications'),
      'transferencias': await count('SELECT COUNT(*) FROM transfers'),
      'asientos': await count('SELECT COUNT(*) FROM account_transactions'),
      'pagos_proveedor': await count('SELECT COUNT(*) FROM provider_payments'),
      'lotes_con_vencimiento': await count(
        'SELECT COUNT(*) FROM inventory_lots WHERE expiry_date IS NOT NULL',
      ),
      'vinculos_campana': await count('SELECT COUNT(*) FROM campaign_bindings'),
      'vinculos_producto': await count('SELECT COUNT(*) FROM product_bindings'),
      'existencias_mL': totals,
      'por_persona': [
        for (final r in stock)
          '${r['producto']} · ${r['persona']}: ${r['neto']}',
      ],
    };
    // ignore: avoid_print
    print('DEMO_SUMMARY ${jsonEncode(summary)}');
    await database.close();
  });
}
