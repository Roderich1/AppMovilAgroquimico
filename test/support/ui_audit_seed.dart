// Dataset determinístico para la auditoría de interfaz (docs/36_UI_AUDIT_DATASET.md).
//
// NO forma parte del código de producción y NO se compila dentro de la aplicación:
// vive en `test/`, no coincide con el patrón `*_test.dart` (por lo que `flutter test`
// no lo ejecuta como suite) y `lib/` no lo referencia en ningún punto.
//
// Toda la carga se hace **a través de los métodos reales de `AgroRepository`**, de modo
// que el dataset respeta las mismas reglas de negocio que aplicaría un usuario: campaña
// activa obligatoria, asignaciones que suman la cantidad comprada, FIFO, stock suficiente
// y precondiciones de reversión. Si una regla cambia, este archivo deja de compilar o
// lanza, en vez de producir datos imposibles.
//
// Unidades (ver docs/10_DATA_MODEL.md):
//   * cantidad "base"  = mililitros o gramos  (litros/kilos × 1000)
//   * importe "minor"  = centavos             (bolivianos × 100)
//   * tipo de cambio   = escalado × 1e6
//   * superficie       = metros cuadrados     (hectáreas × 10000)

import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/domain/models.dart';

/// Identificadores generados por [seedUiAudit], para que quien lo invoque pueda
/// reportar el dataset o navegar directamente a una entidad concreta.
class UiAuditSeedResult {
  UiAuditSeedResult({
    required this.personIds,
    required this.farmIds,
    required this.productIds,
    required this.supplierIds,
    required this.campaignIds,
    required this.purchaseIds,
    required this.transferIds,
    required this.applicationIds,
    required this.planIds,
    required this.providerPaymentIds,
    required this.accountPaymentIds,
    required this.reversedPurchaseIds,
    required this.reversedTransferIds,
    required this.reversedApplicationIds,
  });

  final Map<String, int> personIds;
  final Map<String, int> farmIds;
  final Map<String, int> productIds;
  final Map<String, int> supplierIds;
  final Map<String, int> campaignIds;
  final List<int> purchaseIds;
  final List<int> transferIds;
  final List<int> applicationIds;
  final List<int> planIds;
  final List<int> providerPaymentIds;
  final List<int> accountPaymentIds;
  final List<int> reversedPurchaseIds;
  final List<int> reversedTransferIds;
  final List<int> reversedApplicationIds;

  Map<String, int> get counts => {
    'personas': personIds.length,
    'chacos': farmIds.length,
    'productos': productIds.length,
    'proveedores': supplierIds.length,
    'campañas': campaignIds.length,
    'compras': purchaseIds.length,
    'transferencias': transferIds.length,
    'aplicaciones': applicationIds.length,
    'planes': planIds.length,
    'pagos a proveedor': providerPaymentIds.length,
    'pagos de cuenta': accountPaymentIds.length,
    'compras revertidas': reversedPurchaseIds.length,
    'transferencias revertidas': reversedTransferIds.length,
    'aplicaciones revertidas': reversedApplicationIds.length,
  };
}

/// Puebla [repo] con el dataset de auditoría.
///
/// [invoiceImagePath] es la ruta **en el dispositivo** donde estará la fotografía de
/// factura de prueba; se guarda tal cual en `purchases.invoice_image_path`. Si es `null`,
/// ninguna compra lleva imagen.
Future<UiAuditSeedResult> seedUiAudit(
  AgroRepository repo, {
  String? invoiceImagePath,
}) async {
  // ---------------------------------------------------------------- PERSONAS
  // Nombres cortos, largos, compuestos y con caracteres del español (ñ, tildes).
  // Son ficticios: no corresponden a ninguna persona real.
  final personIds = <String, int>{
    'admin': await repo.addPerson(
      name: 'Administración Central',
      role: PersonRole.admin,
      phone: '700-00000',
    ),
    'juan': await repo.addPerson(
      name: 'Juan Pérez',
      role: PersonRole.family,
      phone: '700-11111',
    ),
    'maria': await repo.addPerson(
      name: 'María Fernanda Rodríguez Salvatierra',
      role: PersonRole.family,
      phone: '700-22222',
    ),
    'jose': await repo.addPerson(
      name: 'José Luis Ñáñez Álvarez',
      role: PersonRole.family,
    ),
    'ana': await repo.addPerson(name: 'Ana Áñez', role: PersonRole.family),
    'coop': await repo.addPerson(
      name: 'Cooperativa Agrícola San Julián Ltda.',
      role: PersonRole.thirdParty,
      phone: '3-3456789',
    ),
    'pedro': await repo.addPerson(
      name: 'Pedro Áñez Suárez',
      role: PersonRole.thirdParty,
    ),
  };

  // ------------------------------------------------------------------ CHACOS
  // Superficies elegidas para cubrir: entero grande, decimal .5, decimal .3
  // (comprueba el formateo de hectáreas) y un caso de 250 ha.
  final farmIds = <String, int>{
    'elCarmen': await repo.addFarm(
      ownerId: personIds['juan']!,
      name: 'El Carmen',
      areaM2: 500000, // 50 ha
      location: 'Cuatro Cañadas',
    ),
    'lote2': await repo.addFarm(
      ownerId: personIds['juan']!,
      name: 'Lote 2',
      areaM2: 25000, // 2,5 ha
    ),
    'haciendaLarga': await repo.addFarm(
      ownerId: personIds['maria']!,
      name: 'Hacienda Santa María de los Ángeles del Norte Grande',
      areaM2: 1200000, // 120 ha
      location: 'Pailón',
    ),
    'limoncito': await repo.addFarm(
      ownerId: personIds['jose']!,
      name: 'Limoncito',
      areaM2: 800000, // 80 ha
    ),
    'chacoChico': await repo.addFarm(
      ownerId: personIds['jose']!,
      name: 'Chaco Chico',
      areaM2: 3000, // 0,3 ha
    ),
    'laEsperanza': await repo.addFarm(
      ownerId: personIds['ana']!,
      name: 'La Esperanza',
      areaM2: 150000, // 15 ha
    ),
    'bloqueComunal': await repo.addFarm(
      ownerId: personIds['coop']!,
      name: 'Bloque Comunal Norte',
      areaM2: 2500000, // 250 ha
    ),
    'sanPedro': await repo.addFarm(
      ownerId: personIds['pedro']!,
      name: 'San Pedro',
      areaM2: 95000, // 9,5 ha
    ),
  };

  // --------------------------------------------------------------- PRODUCTOS
  // 22 productos: suficientes para forzar scroll en toda lista y en los selectores.
  // Incluye nombres cortos, un nombre muy largo, dos nombres casi idénticos
  // ("Glifosato 48 SL" / "Glifosato 68 SG") y ambas unidades (L y KG).
  final productSpecs = <String, (String, String?, String)>{
    'urea': ('Urea', 'Nitrógeno 46%', 'KG'),
    'glifo48': ('Glifosato 48 SL', 'Glifosato', 'L'),
    'glifo68': ('Glifosato 68 SG', 'Glifosato sal amónica', 'KG'),
    'herbicidaLargo': (
      'Herbicida Selectivo Postemergente para Cultivos Extensivos '
          'Presentación Comercial Especial',
      'Fomesafen + Fluazifop',
      'L',
    ),
    'atrazina': ('Atrazina 50', 'Atrazina', 'L'),
    'dosCuatroD': ('2,4-D Amina', '2,4-D', 'L'),
    'paraquat': ('Paraquat 27', 'Paraquat dicloruro', 'L'),
    'cipermetrina': ('Cipermetrina 25', 'Cipermetrina', 'L'),
    'lambda': ('Lambdacialotrina 5', 'Lambdacialotrina', 'L'),
    'imidacloprid': ('Imidacloprid 35', 'Imidacloprid', 'L'),
    'mancozeb': ('Mancozeb 80', 'Mancozeb', 'KG'),
    'azoxi': ('Azoxistrobina 25', 'Azoxistrobina', 'L'),
    'tebuconazole': ('Tebuconazole 43', 'Tebuconazole', 'L'),
    'fosfato': ('Fosfato Diamónico', 'DAP 18-46-0', 'KG'),
    'cloruroK': ('Cloruro de Potasio', 'KCl 60%', 'KG'),
    'sulfatoAmonio': ('Sulfato de Amonio', 'SAM 21-0-0', 'KG'),
    'coadyuvante': ('Coadyuvante Siliconado', 'Siliconado no iónico', 'L'),
    'aceite': ('Aceite Agrícola Mineral', 'Aceite parafínico', 'L'),
    'foliar': ('Fertilizante Foliar Completo', 'NPK + micros', 'L'),
    'semilla': ('Semilla Soya INTA-90', null, 'KG'),
    // Nunca comprado: debe aparecer en cero en los reportes, no desaparecer.
    'boro': ('Boro Quelatado', 'Boro EDTA', 'L'),
    // Comprado y consumido por completo: stock exactamente cero.
    'zinc': ('Zinc Quelatado', 'Zinc EDTA', 'KG'),
  };
  final productIds = <String, int>{};
  for (final entry in productSpecs.entries) {
    productIds[entry.key] = await repo.addProduct(
      name: entry.value.$1,
      activeIngredient: entry.value.$2,
      unit: entry.value.$3,
    );
  }

  // ------------------------------------------------------------- PROVEEDORES
  final supplierIds = <String, int>{
    'agroEste': await repo.addSupplier(
      name: 'Agropecuaria del Este S.R.L.',
      phone: '3-3111222',
    ),
    'insumos': await repo.addSupplier(name: 'Insumos Bolivia'),
    'casaLarga': await repo.addSupplier(
      name:
          'Casa Comercial Santa Cruz de la Sierra Importaciones y '
          'Distribuciones S.A.',
      notes: 'Proveedor con razón social larga, para probar truncamiento.',
    ),
    'donMario': await repo.addSupplier(name: 'Don Mario'),
  };

  // ----------------------------------------------------------------- CAMPAÑA
  // `addCampaign` marca ACTIVE solo la primera. Se trabaja Invierno 2025, se cierra,
  // y luego se activa Verano 2026: así queda historial real en una campaña cerrada.
  final campaignIds = <String, int>{
    'invierno2025': await repo.addCampaign(
      name: 'Invierno 2025',
      start: DateTime.utc(2025, 5, 1),
      end: DateTime.utc(2025, 10, 31),
    ),
  };
  final invierno = campaignIds['invierno2025']!;

  final purchaseIds = <int>[];
  final transferIds = <int>[];
  final applicationIds = <int>[];
  final planIds = <int>[];
  final providerPaymentIds = <int>[];
  final accountPaymentIds = <int>[];

  // ================================================= CAMPAÑA 1 · INVIERNO 2025

  // Compra mediana en bolivianos, con fotografía de factura.
  purchaseIds.add(
    await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: supplierIds['agroEste']!,
        campaignId: invierno,
        purchaseDate: DateTime.utc(2025, 5, 10),
        invoiceNumber: 'F-0001-2025',
        invoiceImagePath: invoiceImagePath,
        notes: 'Compra de arranque de campaña.',
        items: [
          PurchaseItemDraft(
            productId: productIds['urea']!,
            quantityBase: 2000000, // 2 000 kg
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 680, // 6,80 Bs/kg
            allocations: [
              AllocationDraft(
                personId: personIds['juan']!,
                quantityBase: 1200000,
              ),
              AllocationDraft(
                personId: personIds['maria']!,
                quantityBase: 800000,
              ),
            ],
          ),
          PurchaseItemDraft(
            productId: productIds['glifo48']!,
            quantityBase: 400000, // 400 L
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 4250,
            allocations: [
              AllocationDraft(
                personId: personIds['juan']!,
                quantityBase: 200000,
              ),
              AllocationDraft(
                personId: personIds['jose']!,
                quantityBase: 200000,
              ),
            ],
          ),
          PurchaseItemDraft(
            productId: productIds['atrazina']!,
            quantityBase: 300000,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 3890,
            allocations: [
              AllocationDraft(
                personId: personIds['maria']!,
                quantityBase: 300000,
              ),
            ],
          ),
          PurchaseItemDraft(
            productId: productIds['cipermetrina']!,
            quantityBase: 120000,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 9500,
            allocations: [
              AllocationDraft(
                personId: personIds['jose']!,
                quantityBase: 120000,
              ),
            ],
          ),
          PurchaseItemDraft(
            productId: productIds['mancozeb']!,
            quantityBase: 250000,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 5525,
            allocations: [
              AllocationDraft(
                personId: personIds['ana']!,
                quantityBase: 250000,
              ),
            ],
          ),
        ],
      ),
    ),
  );

  // Compra en dólares con tipo de cambio pactado: ejercita la conversión y el
  // cargo inmediato a TERCEROS (política BY_PURCHASE_ALLOCATION).
  purchaseIds.add(
    await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: supplierIds['insumos']!,
        campaignId: invierno,
        purchaseDate: DateTime.utc(2025, 5, 18),
        invoiceNumber: 'F-0002-2025',
        exchangeRateSource: ExchangeRateSource.agreedWithSupplier,
        exchangeRateNote: 'Tipo de cambio acordado con el proveedor: 6,96.',
        items: [
          PurchaseItemDraft(
            productId: productIds['imidacloprid']!,
            quantityBase: 150000,
            currency: CurrencyCode.usd,
            originalUnitPriceMinor: 1875, // 18,75 USD/L
            exchangeRateScaled: 6960000, // 6,96
            allocations: [
              AllocationDraft(
                personId: personIds['coop']!,
                quantityBase: 150000,
              ),
            ],
          ),
          PurchaseItemDraft(
            productId: productIds['lambda']!,
            quantityBase: 80000,
            currency: CurrencyCode.usd,
            originalUnitPriceMinor: 2450,
            exchangeRateScaled: 6960000,
            allocations: [
              AllocationDraft(
                personId: personIds['coop']!,
                quantityBase: 80000,
              ),
            ],
          ),
          PurchaseItemDraft(
            productId: productIds['azoxi']!,
            quantityBase: 60000,
            currency: CurrencyCode.usd,
            originalUnitPriceMinor: 3120,
            exchangeRateScaled: 6960000,
            allocations: [
              AllocationDraft(
                personId: personIds['pedro']!,
                quantityBase: 60000,
              ),
            ],
          ),
        ],
      ),
    ),
  );

  // Compra pequeña, un solo producto, cantidad con decimales.
  purchaseIds.add(
    await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: supplierIds['donMario']!,
        campaignId: invierno,
        purchaseDate: DateTime.utc(2025, 6, 2),
        invoiceNumber: 'R-77',
        items: [
          PurchaseItemDraft(
            productId: productIds['coadyuvante']!,
            quantityBase: 25500, // 25,5 L
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 2800,
            allocations: [
              AllocationDraft(
                personId: personIds['juan']!,
                quantityBase: 25500,
              ),
            ],
          ),
        ],
      ),
    ),
  );

  // Compra grande: 8 líneas, cantidad extrema (99 999,750 kg) y proveedor de
  // razón social larga. Fuerza scroll en el detalle y números de muchos dígitos.
  purchaseIds.add(
    await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: supplierIds['casaLarga']!,
        campaignId: invierno,
        purchaseDate: DateTime.utc(2025, 6, 20),
        invoiceNumber: 'F-2025-000123456',
        notes:
            'Compra consolidada de fertilizantes y agroquímicos para toda la '
            'campaña de invierno. Incluye el flete hasta el silo y la descarga. '
            'El saldo se acordó a 90 días con el proveedor.',
        items: [
          PurchaseItemDraft(
            productId: productIds['fosfato']!,
            quantityBase: 99999750, // 99 999,750 kg
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 560,
            allocations: [
              AllocationDraft(
                personId: personIds['maria']!,
                quantityBase: 50000000,
              ),
              AllocationDraft(
                personId: personIds['coop']!,
                quantityBase: 49999750,
              ),
            ],
          ),
          PurchaseItemDraft(
            productId: productIds['cloruroK']!,
            quantityBase: 15000000,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 495,
            allocations: [
              AllocationDraft(
                personId: personIds['juan']!,
                quantityBase: 15000000,
              ),
            ],
          ),
          PurchaseItemDraft(
            productId: productIds['sulfatoAmonio']!,
            quantityBase: 8000000,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 375,
            allocations: [
              AllocationDraft(
                personId: personIds['ana']!,
                quantityBase: 8000000,
              ),
            ],
          ),
          PurchaseItemDraft(
            productId: productIds['dosCuatroD']!,
            quantityBase: 500000,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 3340,
            allocations: [
              AllocationDraft(
                personId: personIds['jose']!,
                quantityBase: 500000,
              ),
            ],
          ),
          PurchaseItemDraft(
            productId: productIds['paraquat']!,
            quantityBase: 200000,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 4780,
            allocations: [
              AllocationDraft(
                personId: personIds['juan']!,
                quantityBase: 200000,
              ),
            ],
          ),
          PurchaseItemDraft(
            productId: productIds['tebuconazole']!,
            quantityBase: 90000,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 12075,
            allocations: [
              AllocationDraft(
                personId: personIds['maria']!,
                quantityBase: 90000,
              ),
            ],
          ),
          PurchaseItemDraft(
            productId: productIds['aceite']!,
            quantityBase: 300000,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 2230,
            allocations: [
              AllocationDraft(
                personId: personIds['pedro']!,
                quantityBase: 300000,
              ),
            ],
          ),
          PurchaseItemDraft(
            productId: productIds['zinc']!,
            quantityBase: 40000,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 8800,
            allocations: [
              AllocationDraft(
                personId: personIds['juan']!,
                quantityBase: 40000,
              ),
            ],
          ),
        ],
      ),
    ),
  );

  // Aplicaciones de invierno. FAMILIA se carga aquí (BY_ACTUAL_USAGE).
  applicationIds.add(
    await repo.confirmApplication(
      ApplicationDraft(
        personId: personIds['juan']!,
        farmId: farmIds['elCarmen']!,
        campaignId: invierno,
        appliedAt: DateTime.utc(2025, 6, 25),
        treatedAreaM2: 500000,
        notes: 'Primera pasada de la campaña.',
        lines: [
          ApplicationLineDraft(
            productId: productIds['urea']!,
            quantityBase: 600000,
            treatedAreaM2: 500000,
            doseBasePerHa: 12000,
            theoreticalQuantityBase: 600000,
          ),
          ApplicationLineDraft(
            productId: productIds['glifo48']!,
            quantityBase: 100000,
            treatedAreaM2: 500000,
            doseBasePerHa: 2000,
            theoreticalQuantityBase: 100000,
          ),
        ],
      ),
    ),
  );

  applicationIds.add(
    await repo.confirmApplication(
      ApplicationDraft(
        personId: personIds['maria']!,
        farmId: farmIds['haciendaLarga']!,
        campaignId: invierno,
        appliedAt: DateTime.utc(2025, 7, 1),
        treatedAreaM2: 1200000,
        lines: [
          ApplicationLineDraft(
            productId: productIds['atrazina']!,
            quantityBase: 250000,
            treatedAreaM2: 1200000,
            doseBasePerHa: 2083,
            theoreticalQuantityBase: 249960,
          ),
          ApplicationLineDraft(
            productId: productIds['fosfato']!,
            quantityBase: 30000000,
            treatedAreaM2: 1200000,
            doseBasePerHa: 250000,
            theoreticalQuantityBase: 30000000,
          ),
        ],
      ),
    ),
  );

  applicationIds.add(
    await repo.confirmApplication(
      ApplicationDraft(
        personId: personIds['jose']!,
        farmId: farmIds['limoncito']!,
        campaignId: invierno,
        appliedAt: DateTime.utc(2025, 7, 8),
        treatedAreaM2: 800000,
        notes:
            'Aplicación con observación larga para comprobar cómo se comporta el '
            'texto en la bitácora del chaco y en el detalle de la aplicación. '
            'Se aplicó en dos jornadas por lluvia intermitente, con viento del '
            'norte durante la mañana, y se completó recién al día siguiente.',
        lines: [
          ApplicationLineDraft(
            productId: productIds['glifo48']!,
            quantityBase: 150000,
            treatedAreaM2: 800000,
            doseBasePerHa: 1875,
            theoreticalQuantityBase: 150000,
          ),
          ApplicationLineDraft(
            productId: productIds['cipermetrina']!,
            quantityBase: 45500, // 45,5 L
            treatedAreaM2: 800000,
            doseBasePerHa: 569,
            theoreticalQuantityBase: 45520,
          ),
        ],
      ),
    ),
  );

  applicationIds.add(
    await repo.confirmApplication(
      ApplicationDraft(
        personId: personIds['ana']!,
        farmId: farmIds['laEsperanza']!,
        campaignId: invierno,
        appliedAt: DateTime.utc(2025, 7, 15),
        treatedAreaM2: 150000,
        lines: [
          ApplicationLineDraft(
            productId: productIds['mancozeb']!,
            quantityBase: 120000,
            treatedAreaM2: 150000,
            doseBasePerHa: 8000,
            theoreticalQuantityBase: 120000,
          ),
        ],
      ),
    ),
  );

  // Consume el 100 % del zinc: deja un producto con stock exactamente cero.
  applicationIds.add(
    await repo.confirmApplication(
      ApplicationDraft(
        personId: personIds['juan']!,
        farmId: farmIds['lote2']!,
        campaignId: invierno,
        appliedAt: DateTime.utc(2025, 7, 20),
        treatedAreaM2: 25000,
        lines: [
          ApplicationLineDraft(
            productId: productIds['zinc']!,
            quantityBase: 40000,
            treatedAreaM2: 25000,
            doseBasePerHa: 16000,
            theoreticalQuantityBase: 40000,
          ),
        ],
      ),
    ),
  );

  // Transferencias de invierno.
  transferIds.add(
    await repo.transferProductsFifo(
      fromPersonId: personIds['juan']!,
      toPersonId: personIds['jose']!,
      date: DateTime.utc(2025, 6, 28),
      notes: 'Préstamo de urea para terminar el lote vecino.',
      items: [
        TransferItemDraft(productId: productIds['urea']!, quantityBase: 100000),
      ],
    ),
  );
  transferIds.add(
    await repo.transferProductsFifo(
      fromPersonId: personIds['maria']!,
      toPersonId: personIds['ana']!,
      date: DateTime.utc(2025, 7, 3),
      items: [
        TransferItemDraft(
          productId: productIds['fosfato']!,
          quantityBase: 5000000,
        ),
        TransferItemDraft(
          productId: productIds['atrazina']!,
          quantityBase: 20000,
        ),
      ],
    ),
  );
  transferIds.add(
    await repo.transferProductsFifo(
      fromPersonId: personIds['coop']!,
      toPersonId: personIds['juan']!,
      date: DateTime.utc(2025, 7, 10),
      items: [
        TransferItemDraft(
          productId: productIds['imidacloprid']!,
          quantityBase: 20000,
        ),
      ],
    ),
  );

  // Pagos al proveedor durante invierno (los hace siempre el ADMIN).
  providerPaymentIds.add(
    await repo.addProviderPayment(
      purchaseId: purchaseIds[2], // R-77, se paga completa
      payerPersonId: personIds['admin']!,
      amountBobMinor: 71400, // 25,5 L × 28,00
      method: 'EFECTIVO',
      date: DateTime.utc(2025, 6, 3),
    ),
  );
  providerPaymentIds.add(
    await repo.addProviderPayment(
      purchaseId: purchaseIds[0], // pago parcial
      payerPersonId: personIds['admin']!,
      amountBobMinor: 1500000, // 15 000,00 Bs
      method: 'TRANSFERENCIA',
      date: DateTime.utc(2025, 6, 5),
    ),
  );

  // ================================================== CIERRE Y CAMBIO DE CAMPAÑA
  campaignIds['verano2026'] = await repo.addCampaign(
    name: 'Verano 2026',
    start: DateTime.utc(2026, 1, 1),
  );
  final verano = campaignIds['verano2026']!;
  await repo.activateCampaign(verano, closeCurrent: true);

  // Tercera campaña, que se queda en PLANNED: cubre el estado "planificada".
  campaignIds['verano2027'] = await repo.addCampaign(
    name: 'Verano 2027',
    start: DateTime.utc(2027, 1, 1),
  );

  // ==================================================== CAMPAÑA 2 · VERANO 2026

  purchaseIds.add(
    await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: supplierIds['agroEste']!,
        campaignId: verano,
        purchaseDate: DateTime.utc(2026, 1, 15),
        invoiceNumber: 'F-0101-2026',
        items: [
          PurchaseItemDraft(
            productId: productIds['glifo68']!,
            quantityBase: 500000,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 6140,
            allocations: [
              AllocationDraft(
                personId: personIds['juan']!,
                quantityBase: 250000,
              ),
              AllocationDraft(
                personId: personIds['maria']!,
                quantityBase: 250000,
              ),
            ],
          ),
          PurchaseItemDraft(
            productId: productIds['herbicidaLargo']!,
            quantityBase: 180000,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 21000,
            allocations: [
              AllocationDraft(
                personId: personIds['jose']!,
                quantityBase: 180000,
              ),
            ],
          ),
          PurchaseItemDraft(
            productId: productIds['semilla']!,
            quantityBase: 4000000,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 985,
            allocations: [
              AllocationDraft(
                personId: personIds['juan']!,
                quantityBase: 2000000,
              ),
              AllocationDraft(
                personId: personIds['ana']!,
                quantityBase: 2000000,
              ),
            ],
          ),
        ],
      ),
    ),
  );

  purchaseIds.add(
    await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: supplierIds['insumos']!,
        campaignId: verano,
        purchaseDate: DateTime.utc(2026, 1, 28),
        invoiceNumber: 'F-0102-2026',
        exchangeRateSource: ExchangeRateSource.officialReference,
        exchangeRateNote: 'Referencia oficial del día.',
        items: [
          PurchaseItemDraft(
            productId: productIds['foliar']!,
            quantityBase: 250000,
            currency: CurrencyCode.usd,
            originalUnitPriceMinor: 1240,
            exchangeRateScaled: 6970000, // 6,97
            allocations: [
              AllocationDraft(
                personId: personIds['coop']!,
                quantityBase: 250000,
              ),
            ],
          ),
          PurchaseItemDraft(
            productId: productIds['aceite']!,
            quantityBase: 150000,
            currency: CurrencyCode.usd,
            originalUnitPriceMinor: 420,
            exchangeRateScaled: 6970000,
            allocations: [
              AllocationDraft(
                personId: personIds['pedro']!,
                quantityBase: 150000,
              ),
            ],
          ),
        ],
      ),
    ),
  );

  // Caso extremo deliberado de importe: 1 litro a 9 999 999,99 Bs. Es un valor
  // válido según las reglas (precio > 0) y produce el importe más grande posible
  // de un solo dígito por encima de siete cifras enteras, para observar overflow,
  // separadores de miles y truncamiento en tarjetas, tablas y reportes.
  purchaseIds.add(
    await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: supplierIds['donMario']!,
        campaignId: verano,
        purchaseDate: DateTime.utc(2026, 2, 5),
        invoiceNumber: 'R-88',
        notes: 'Importe extremo deliberado para la auditoría de interfaz.',
        items: [
          PurchaseItemDraft(
            productId: productIds['tebuconazole']!,
            quantityBase: 1000, // 1,000 L
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 999999999, // 9 999 999,99 Bs/L
            allocations: [
              AllocationDraft(
                personId: personIds['maria']!,
                quantityBase: 1000,
              ),
            ],
          ),
        ],
      ),
    ),
  );

  // Cantidades con decimales, incluida 0,125 L.
  purchaseIds.add(
    await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: supplierIds['casaLarga']!,
        campaignId: verano,
        purchaseDate: DateTime.utc(2026, 2, 20),
        invoiceNumber: 'F-2026-000000789',
        items: [
          PurchaseItemDraft(
            productId: productIds['urea']!,
            quantityBase: 1500500, // 1 500,5 kg
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 715,
            allocations: [
              AllocationDraft(
                personId: personIds['juan']!,
                quantityBase: 750250,
              ),
              AllocationDraft(
                personId: personIds['maria']!,
                quantityBase: 750250,
              ),
            ],
          ),
          PurchaseItemDraft(
            productId: productIds['glifo48']!,
            quantityBase: 125, // 0,125 L
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 4400,
            allocations: [
              AllocationDraft(personId: personIds['jose']!, quantityBase: 125),
            ],
          ),
          PurchaseItemDraft(
            productId: productIds['cipermetrina']!,
            quantityBase: 99750, // 99,75 L
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 9750,
            allocations: [
              AllocationDraft(
                personId: personIds['ana']!,
                quantityBase: 99750,
              ),
            ],
          ),
          PurchaseItemDraft(
            productId: productIds['paraquat']!,
            quantityBase: 60000,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 4990,
            allocations: [
              AllocationDraft(
                personId: personIds['coop']!,
                quantityBase: 60000,
              ),
            ],
          ),
        ],
      ),
    ),
  );

  purchaseIds.add(
    await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: supplierIds['agroEste']!,
        campaignId: verano,
        purchaseDate: DateTime.utc(2026, 3, 1),
        invoiceNumber: 'F-0103-2026',
        invoiceImagePath: invoiceImagePath,
        items: [
          PurchaseItemDraft(
            productId: productIds['mancozeb']!,
            quantityBase: 300000,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 5700,
            allocations: [
              AllocationDraft(
                personId: personIds['maria']!,
                quantityBase: 300000,
              ),
            ],
          ),
          PurchaseItemDraft(
            productId: productIds['sulfatoAmonio']!,
            quantityBase: 2000000,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 395,
            allocations: [
              AllocationDraft(
                personId: personIds['pedro']!,
                quantityBase: 2000000,
              ),
            ],
          ),
        ],
      ),
    ),
  );

  // Compra que se revierte: deja una fila en estado "Revertida" en el historial
  // y un CREDIT_ADJUSTMENT en la cuenta del tercero.
  final purchaseToReverse = await repo.confirmPurchase(
    PurchaseDraft(
      supplierId: supplierIds['donMario']!,
      campaignId: verano,
      purchaseDate: DateTime.utc(2026, 3, 4),
      invoiceNumber: 'R-99',
      notes: 'Cargada por error.',
      items: [
        PurchaseItemDraft(
          productId: productIds['coadyuvante']!,
          quantityBase: 10000,
          currency: CurrencyCode.bob,
          originalUnitPriceMinor: 2900,
          allocations: [
            AllocationDraft(personId: personIds['pedro']!, quantityBase: 10000),
          ],
        ),
      ],
    ),
  );
  purchaseIds.add(purchaseToReverse);

  // ------------------------------------------------------------------- PLANES
  planIds.add(
    await repo.addPlanMulti(
      farmId: farmIds['elCarmen']!,
      campaignId: verano,
      areaM2: 500000,
      plannedDate: DateTime.utc(2026, 1, 20),
      items: [
        PlanItemDraft(productId: productIds['urea']!, doseBasePerHa: 12000),
        PlanItemDraft(productId: productIds['glifo48']!, doseBasePerHa: 2500),
      ],
    ),
  );
  planIds.add(
    await repo.addPlanMulti(
      farmId: farmIds['haciendaLarga']!,
      campaignId: verano,
      areaM2: 1200000,
      plannedDate: DateTime.utc(2026, 1, 22),
      notes: 'Plan completo de la hacienda.',
      items: [
        PlanItemDraft(productId: productIds['glifo68']!, doseBasePerHa: 1800),
        PlanItemDraft(productId: productIds['mancozeb']!, doseBasePerHa: 3000),
        PlanItemDraft(productId: productIds['urea']!, doseBasePerHa: 15000),
      ],
    ),
  );
  planIds.add(
    await repo.addPlanMulti(
      farmId: farmIds['limoncito']!,
      campaignId: verano,
      areaM2: 800000,
      items: [
        PlanItemDraft(
          productId: productIds['herbicidaLargo']!,
          doseBasePerHa: 1200,
        ),
      ],
    ),
  );
  planIds.add(
    await repo.addPlanMulti(
      farmId: farmIds['bloqueComunal']!,
      campaignId: verano,
      areaM2: 2500000,
      items: [
        PlanItemDraft(productId: productIds['paraquat']!, doseBasePerHa: 2000),
        PlanItemDraft(productId: productIds['foliar']!, doseBasePerHa: 800),
      ],
    ),
  );
  planIds.add(
    await repo.addPlanMulti(
      farmId: farmIds['chacoChico']!,
      campaignId: verano,
      areaM2: 3000, // 0,3 ha
      items: [
        PlanItemDraft(
          productId: productIds['cipermetrina']!,
          doseBasePerHa: 500,
        ),
      ],
    ),
  );

  // ------------------------------------------------------------- APLICACIONES
  applicationIds.add(
    await repo.confirmApplication(
      ApplicationDraft(
        personId: personIds['juan']!,
        farmId: farmIds['elCarmen']!,
        campaignId: verano,
        planId: planIds[0],
        appliedAt: DateTime.utc(2026, 1, 25),
        treatedAreaM2: 500000,
        lines: [
          ApplicationLineDraft(
            productId: productIds['urea']!,
            quantityBase: 590000,
            treatedAreaM2: 500000,
            doseBasePerHa: 12000,
            theoreticalQuantityBase: 600000,
          ),
          // Se aplica menos de lo planificado (80 L frente a 125 L teoricos):
          // deja una varianza visible en la bitacora y en el reporte de plan.
          ApplicationLineDraft(
            productId: productIds['glifo48']!,
            quantityBase: 80000,
            treatedAreaM2: 500000,
            doseBasePerHa: 2500,
            theoreticalQuantityBase: 125000,
          ),
        ],
      ),
    ),
  );
  applicationIds.add(
    await repo.confirmApplication(
      ApplicationDraft(
        personId: personIds['maria']!,
        farmId: farmIds['haciendaLarga']!,
        campaignId: verano,
        planId: planIds[1],
        appliedAt: DateTime.utc(2026, 2, 2),
        treatedAreaM2: 1200000,
        lines: [
          ApplicationLineDraft(
            productId: productIds['glifo68']!,
            quantityBase: 200000,
            treatedAreaM2: 1200000,
            doseBasePerHa: 1800,
            theoreticalQuantityBase: 216000,
          ),
          ApplicationLineDraft(
            productId: productIds['mancozeb']!,
            quantityBase: 250000,
            treatedAreaM2: 1200000,
            doseBasePerHa: 3000,
            theoreticalQuantityBase: 360000,
          ),
        ],
      ),
    ),
  );
  applicationIds.add(
    await repo.confirmApplication(
      ApplicationDraft(
        personId: personIds['jose']!,
        farmId: farmIds['limoncito']!,
        campaignId: verano,
        planId: planIds[2],
        appliedAt: DateTime.utc(2026, 2, 10),
        treatedAreaM2: 800000,
        lines: [
          ApplicationLineDraft(
            productId: productIds['herbicidaLargo']!,
            quantityBase: 96000,
            treatedAreaM2: 800000,
            doseBasePerHa: 1200,
            theoreticalQuantityBase: 96000,
          ),
        ],
      ),
    ),
  );
  applicationIds.add(
    await repo.confirmApplication(
      ApplicationDraft(
        personId: personIds['ana']!,
        farmId: farmIds['laEsperanza']!,
        campaignId: verano,
        appliedAt: DateTime.utc(2026, 2, 14),
        treatedAreaM2: 150000,
        lines: [
          ApplicationLineDraft(
            productId: productIds['semilla']!,
            quantityBase: 500000,
            treatedAreaM2: 150000,
            doseBasePerHa: 33333,
            theoreticalQuantityBase: 500000,
          ),
        ],
      ),
    ),
  );
  applicationIds.add(
    await repo.confirmApplication(
      ApplicationDraft(
        personId: personIds['coop']!,
        farmId: farmIds['bloqueComunal']!,
        campaignId: verano,
        planId: planIds[3],
        appliedAt: DateTime.utc(2026, 2, 18),
        treatedAreaM2: 2500000,
        lines: [
          ApplicationLineDraft(
            productId: productIds['paraquat']!,
            quantityBase: 50000,
            treatedAreaM2: 2500000,
            doseBasePerHa: 200,
            theoreticalQuantityBase: 50000,
          ),
          ApplicationLineDraft(
            productId: productIds['foliar']!,
            quantityBase: 100000,
            treatedAreaM2: 2500000,
            doseBasePerHa: 400,
            theoreticalQuantityBase: 100000,
          ),
        ],
      ),
    ),
  );
  applicationIds.add(
    await repo.confirmApplication(
      ApplicationDraft(
        personId: personIds['pedro']!,
        farmId: farmIds['sanPedro']!,
        campaignId: verano,
        appliedAt: DateTime.utc(2026, 2, 22),
        treatedAreaM2: 95000,
        lines: [
          ApplicationLineDraft(
            productId: productIds['aceite']!,
            quantityBase: 80000,
            treatedAreaM2: 95000,
            doseBasePerHa: 8421,
            theoreticalQuantityBase: 80000,
          ),
        ],
      ),
    ),
  );

  // Aplicación que se revierte más abajo.
  final applicationToReverse = await repo.confirmApplication(
    ApplicationDraft(
      personId: personIds['juan']!,
      farmId: farmIds['lote2']!,
      campaignId: verano,
      appliedAt: DateTime.utc(2026, 2, 25),
      treatedAreaM2: 25000,
      notes: 'Cargada por error, se revierte.',
      lines: [
        ApplicationLineDraft(
          productId: productIds['urea']!,
          quantityBase: 25000,
          treatedAreaM2: 25000,
          doseBasePerHa: 10000,
          theoreticalQuantityBase: 25000,
        ),
      ],
    ),
  );
  applicationIds.add(applicationToReverse);

  // ----------------------------------------------------------- TRANSFERENCIAS
  transferIds.add(
    await repo.transferProductsFifo(
      fromPersonId: personIds['juan']!,
      toPersonId: personIds['maria']!,
      date: DateTime.utc(2026, 1, 30),
      items: [
        TransferItemDraft(productId: productIds['urea']!, quantityBase: 200000),
      ],
    ),
  );
  transferIds.add(
    await repo.transferProductsFifo(
      fromPersonId: personIds['maria']!,
      toPersonId: personIds['jose']!,
      date: DateTime.utc(2026, 2, 6),
      notes: 'Devolución parcial del fungicida prestado la campaña pasada.',
      items: [
        TransferItemDraft(
          productId: productIds['mancozeb']!,
          quantityBase: 50000,
        ),
        TransferItemDraft(
          productId: productIds['glifo68']!,
          quantityBase: 30000,
        ),
      ],
    ),
  );
  transferIds.add(
    await repo.transferProductsFifo(
      fromPersonId: personIds['ana']!,
      toPersonId: personIds['juan']!,
      date: DateTime.utc(2026, 2, 12),
      items: [
        TransferItemDraft(
          productId: productIds['semilla']!,
          quantityBase: 300000,
        ),
      ],
    ),
  );
  // Transferencia que se revierte.
  final transferToReverse = await repo.transferProductsFifo(
    fromPersonId: personIds['coop']!,
    toPersonId: personIds['pedro']!,
    date: DateTime.utc(2026, 3, 2),
    notes: 'Destino equivocado.',
    items: [
      TransferItemDraft(productId: productIds['paraquat']!, quantityBase: 10000),
    ],
  );
  transferIds.add(transferToReverse);

  // ------------------------------------------------------------------- PAGOS
  providerPaymentIds.add(
    await repo.addProviderPayment(
      purchaseId: purchaseIds[4], // F-0101-2026, pago parcial
      payerPersonId: personIds['admin']!,
      amountBobMinor: 2000000,
      method: 'TRANSFERENCIA',
      date: DateTime.utc(2026, 1, 20),
    ),
  );
  providerPaymentIds.add(
    await repo.addProviderPayment(
      purchaseId: purchaseIds[8], // F-0103-2026
      payerPersonId: personIds['admin']!,
      amountBobMinor: 500000,
      method: 'CHEQUE',
      date: DateTime.utc(2026, 3, 3),
    ),
  );

  accountPaymentIds.add(
    await repo.addAccountPayment(
      personId: personIds['juan']!,
      campaignId: verano,
      amountBobMinor: 500000, // 5 000,00 Bs
      date: DateTime.utc(2026, 2, 1),
      notes: 'Pago a cuenta.',
    ),
  );
  accountPaymentIds.add(
    await repo.addAccountPayment(
      personId: personIds['maria']!,
      campaignId: verano,
      amountBobMinor: 1200000,
      date: DateTime.utc(2026, 2, 8),
    ),
  );
  accountPaymentIds.add(
    await repo.addAccountPayment(
      personId: personIds['coop']!,
      campaignId: verano,
      amountBobMinor: 2500000,
      date: DateTime.utc(2026, 2, 15),
      notes: 'Depósito bancario.',
    ),
  );
  accountPaymentIds.add(
    await repo.addAccountPayment(
      personId: personIds['jose']!,
      campaignId: verano,
      amountBobMinor: 80050, // 800,50 Bs
      date: DateTime.utc(2026, 2, 20),
    ),
  );
  // Adelanto: deja saldo a favor, para ver el caso "Saldo a favor" en verde.
  accountPaymentIds.add(
    await repo.addAccountPayment(
      personId: personIds['pedro']!,
      campaignId: verano,
      amountBobMinor: 900000,
      advance: true,
      date: DateTime.utc(2026, 2, 24),
      notes: 'Adelanto de campaña.',
    ),
  );

  // ------------------------------------------------------------- REVERSIONES
  // Se hacen al final para que las precondiciones (lotes intactos) se cumplan.
  await repo.reverseApplication(
    applicationToReverse,
    reason: 'Dataset de auditoría: caso revertido.',
  );
  await repo.reverseTransfer(
    transferToReverse,
    reason: 'Dataset de auditoría: caso revertido.',
  );
  await repo.reversePurchase(
    purchaseToReverse,
    reason: 'Dataset de auditoría: caso revertido.',
  );

  return UiAuditSeedResult(
    personIds: personIds,
    farmIds: farmIds,
    productIds: productIds,
    supplierIds: supplierIds,
    campaignIds: campaignIds,
    purchaseIds: purchaseIds,
    transferIds: transferIds,
    applicationIds: applicationIds,
    planIds: planIds,
    providerPaymentIds: providerPaymentIds,
    accountPaymentIds: accountPaymentIds,
    reversedPurchaseIds: [purchaseToReverse],
    reversedTransferIds: [transferToReverse],
    reversedApplicationIds: [applicationToReverse],
  );
}
