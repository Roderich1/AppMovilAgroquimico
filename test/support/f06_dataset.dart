// F06 (D4, BE #21 / GATE-F06): siembra una base local por agricultor desde
// docs/evidence/F06_DATASET.csv y lee el oráculo escrito a mano
// (F06_EXPECTED_CONTRIBUTIONS.csv y F06_EXPECTED_CELLS.csv). Datos sintéticos.
//
// Orden de siembra (lo impone la app, no el oráculo): primero se declaran las
// necesidades de ambas campañas (sus fechas no se solapan mientras C1 sigue
// abierta), después se opera C1, se activa C2 —lo que cierra C1— y se opera C2.
// NEED_CANCEL es la retirada de una necesidad **ya sincronizada**: se aplica
// aparte con [applyF06Cancellations] después del primer envío. Retirar una
// declaración que nunca salió sólo la descarta en la outbox (D3) y Central no
// llegaría a ver una aportación CANCELLED.
import 'dart:io';

import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/data/sync/central_binding_store.dart';
import 'package:agroquimicos/data/sync/consumption_publisher.dart';
import 'package:agroquimicos/data/sync/declared_need_store.dart';
import 'package:agroquimicos/data/sync/sync_outbox_store.dart';
import 'package:agroquimicos/domain/installation_access.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/sync/central_references.dart';
import 'package:agroquimicos/domain/sync/sync_types.dart';
import 'package:path/path.dart' as p;

/// Campaña central de cada campaña del dataset.
const f06CentralCampaigns = {
  'C1': 'Campana Verano 2026',
  'C2': 'Campana Invierno 2026',
};

/// Productos que el agricultor no vincula: nunca llegan a Central.
const f06Unbound = {'Adherente casero'};

/// Períodos locales del dataset. Desde #116 (D-F04-C2) el período local tiene
/// que estar contenido en el de la campaña central, con extremos inclusivos,
/// y un fin local abierto no cabe en un central con fin. Las campañas
/// centrales del seed del Backend (`Back/prisma/seed.ts`) van: «Campana
/// Verano 2026» del 01/01/2026 al 30/06/2026 y «Campana Invierno 2026» del
/// 01/07/2026 al 30/11/2026 (días civiles en UTC del contrato). Ajuste del
/// 2026-10-18 (03:14Z; noche del 17 en La Paz), sólo de fechas de preparación:
/// - C1: fin 31/08/2026 → **30/06/2026** (antes terminaba después que la
///   central);
/// - C2: sin fin → **30/11/2026** (antes quedaba abierta frente a una central
///   con fin).
/// Los inicios (01/03 y 01/09) ya cabían. Ningún evento cambia de fecha ni de
/// campaña: los de C1 van del 01/04 al 15/05 y los de C2 del 15/09 al 05/10,
/// dentro de los períodos nuevos. `F06_DATASET.csv` y los CSV esperados no se
/// tocan.
final _localCampaigns = {
  'C1': (
    name: 'Campaña verano F06',
    start: DateTime(2026, 3, 1),
    end: DateTime(2026, 6, 30),
  ),
  'C2': (
    name: 'Campaña invierno F06',
    start: DateTime(2026, 9, 1),
    end: DateTime(2026, 11, 30),
  ),
};
final _needDate = {'C1': DateTime(2026, 5, 15), 'C2': DateTime(2026, 10, 5)};
final _purchaseDate = {'C1': DateTime(2026, 4, 1), 'C2': DateTime(2026, 9, 15)};
final _applicationDate = {
  'C1': DateTime(2026, 5, 10),
  'C2': DateTime(2026, 10, 5),
};

String f06EvidenceDir() {
  for (final candidate in [
    p.join('docs', 'evidence'),
    p.join('..', 'docs', 'evidence'),
  ]) {
    if (File(p.join(candidate, 'F06_DATASET.csv')).existsSync()) {
      return candidate;
    }
  }
  throw StateError('No se encuentra docs/evidence/F06_DATASET.csv');
}

List<Map<String, String>> readF06Csv(String name) {
  final lines = File(p.join(f06EvidenceDir(), name))
      .readAsLinesSync()
      .where((line) => line.trim().isNotEmpty)
      .toList();
  final header = lines.first.split(',');
  return [
    for (final line in lines.skip(1))
      () {
        final values = line.split(',');
        if (values.length != header.length) {
          throw FormatException('Fila con ${values.length} columnas: $line');
        }
        return {for (var i = 0; i < header.length; i++) header[i]: values[i]};
      }(),
  ];
}

class F06Event {
  F06Event(Map<String, String> row)
    : row = int.parse(row['row']!),
      farmer = row['farmer']!,
      campaign = row['campaign']!,
      event = row['event']!,
      group = row['group']!,
      person = row['person']!,
      product = row['product']!,
      unit = row['unit']!,
      quantity = row['quantity_base']!.isEmpty
          ? null
          : int.parse(row['quantity_base']!);

  final int row;
  final String farmer;
  final String campaign;
  final String event;
  final String group;
  final String person;
  final String product;
  final String unit;
  final int? quantity;
}

List<F06Event> f06Events([String? farmer]) => [
  for (final row in readF06Csv('F06_DATASET.csv'))
    if (farmer == null || row['farmer'] == farmer) F06Event(row),
];

/// Clave de una aportación: campaña, proyección, producto central, unidad base.
typedef F06Key = ({
  String campaign,
  String projection,
  String product,
  String baseUnit,
});

/// Fila esperada (a mano) de F06_EXPECTED_CONTRIBUTIONS.csv.
typedef F06Expected = ({String status, int? quantity});

Map<F06Key, F06Expected> f06ExpectedContributions(String farmer) => {
  for (final row in readF06Csv('F06_EXPECTED_CONTRIBUTIONS.csv'))
    if (row['farmer'] == farmer)
      (
        campaign: row['campaign']!,
        projection: row['projection_type']!,
        product: row['product']!,
        baseUnit: row['base_unit']!,
      ): (
        status: row['status']!,
        quantity: row['quantity_base']!.isEmpty
            ? null
            : int.parse(row['quantity_base']!),
      ),
};

/// Celda esperada (a mano) de F06_EXPECTED_CELLS.csv para una etapa.
typedef F06ExpectedCell = ({String status, String? total, int? contributors});

Map<F06Key, F06ExpectedCell> f06ExpectedCells(String stage) => {
  for (final row in readF06Csv('F06_EXPECTED_CELLS.csv'))
    if (row['stage'] == stage)
      (
        campaign: row['campaign']!,
        projection: row['projection_type']!,
        product: row['product']!,
        baseUnit: row['base_unit']!,
      ): (
        status: row['status']!,
        total: row['visible_total_base']!.isEmpty
            ? null
            : row['visible_total_base'],
        contributors: row['visible_contributors']!.isEmpty
            ? null
            : int.parse(row['visible_contributors']!),
      ),
};

class F06Farm {
  F06Farm({
    required this.farmer,
    required this.database,
    required this.campaignOf,
    required this.productOf,
  }) : repo = AgroRepository(database),
       owners = OwnerBindingStore(database),
       bindings = CentralBindingStore(database),
       needs = DeclaredNeedStore(database),
       outbox = SyncOutboxStore(database),
       publisher = ConsumptionPublisher(database);

  final String farmer;
  final AppDatabase database;

  /// Campaña del dataset (C1/C2) → id local.
  final Map<String, int> campaignOf;

  /// Nombre de producto → id local.
  final Map<String, int> productOf;
  final AgroRepository repo;
  final OwnerBindingStore owners;
  final CentralBindingStore bindings;
  final DeclaredNeedStore needs;
  final SyncOutboxStore outbox;
  final ConsumptionPublisher publisher;
}

/// Siembra la base de [farmer] desde el CSV con las referencias centrales de
/// [references] (las reales del entorno o unas sintéticas).
Future<F06Farm> seedF06Farm({
  required AppDatabase database,
  required String farmer,
  required OwnerScope scope,
  required String installationRef,
  required CentralReferences references,
}) async {
  final events = f06Events(farmer);
  final repo = AgroRepository(database);
  final owners = OwnerBindingStore(database);
  final bindings = CentralBindingStore(database);
  final needs = DeclaredNeedStore(database);
  final owner = (await owners.bindNewPerson(
    name: 'Titular $farmer',
    scope: scope,
    installationRef: installationRef,
  )).personId;
  final persons = {'TITULAR': owner};
  if (events.any((e) => e.person == 'FAMILIAR')) {
    persons['FAMILIAR'] = await repo.addPerson(
      name: 'Familiar $farmer',
      role: PersonRole.family,
    );
  }
  final farms = {
    for (final MapEntry(key: role, value: person) in persons.entries)
      role: await repo.addFarm(
        ownerId: person,
        name: 'Chaco ${role.toLowerCase()} $farmer',
        areaM2: 10000,
      ),
  };
  final supplier = await repo.addSupplier(name: 'Proveedor F06 $farmer');

  final campaignOf = <String, int>{};
  for (final MapEntry(key: code, value: local) in _localCampaigns.entries) {
    campaignOf[code] = await repo.addCampaign(
      name: local.name,
      start: local.start,
      end: local.end,
    );
    final central = references.campaigns.singleWhere(
      (c) => c.name == f06CentralCampaigns[code],
    );
    await bindings.bindCampaign(
      campaignId: campaignOf[code]!,
      central: central,
      tenantId: scope.tenantId,
    );
  }
  final productOf = <String, int>{};
  for (final e in events.where((e) => e.product.isNotEmpty)) {
    if (productOf.containsKey(e.product)) continue;
    productOf[e.product] = await repo.addProduct(name: e.product, unit: e.unit);
    if (f06Unbound.contains(e.product)) continue;
    await bindings.bindProduct(
      productId: productOf[e.product]!,
      central: references.products.singleWhere((c) => c.name == e.product),
      tenantId: scope.tenantId,
    );
  }

  // 1) Necesidades declaradas de ambas campañas, en el orden del CSV.
  for (final e in events.where((e) => e.event == 'NEED')) {
    await needs.declare(
      referenceDate: _needDate[e.campaign]!,
      productId: productOf[e.product]!,
      quantityBase: e.quantity!,
    );
  }

  // 2) Compras, aplicaciones y reversiones: C1 y, tras activar C2, C2.
  final applicationOf = <String, int>{};
  for (final campaign in ['C1', 'C2']) {
    if (campaign == 'C2') {
      await repo.activateCampaign(campaignOf['C2']!, closeCurrent: true);
    }
    final rows = events.where((e) => e.campaign == campaign).toList();
    final groups = <String>[];
    for (final e in rows) {
      final key = '${e.event}:${e.group}';
      if (!groups.contains(key)) groups.add(key);
    }
    for (final key in groups) {
      final [kind, group] = key.split(':');
      final lines = rows.where((e) => e.event == kind && e.group == group);
      switch (kind) {
        case 'PURCHASE':
          final products = <String>[];
          for (final e in lines) {
            if (!products.contains(e.product)) products.add(e.product);
          }
          await repo.confirmPurchase(
            PurchaseDraft(
              supplierId: supplier,
              campaignId: campaignOf[campaign]!,
              purchaseDate: _purchaseDate[campaign]!,
              items: [
                for (final product in products)
                  () {
                    final allocations = lines.where(
                      (e) => e.product == product,
                    );
                    return PurchaseItemDraft(
                      productId: productOf[product]!,
                      quantityBase: allocations.fold(
                        0,
                        (s, e) => s + e.quantity!,
                      ),
                      currency: CurrencyCode.bob,
                      originalUnitPriceMinor: 1000,
                      allocations: [
                        for (final e in allocations)
                          AllocationDraft(
                            personId: persons[e.person]!,
                            quantityBase: e.quantity!,
                          ),
                      ],
                    );
                  }(),
              ],
            ),
          );
        case 'APPLICATION':
          final person = lines.first.person;
          applicationOf[group] = await repo.confirmApplication(
            ApplicationDraft(
              personId: persons[person]!,
              farmId: farms[person]!,
              campaignId: campaignOf[campaign]!,
              appliedAt: _applicationDate[campaign]!,
              lines: [
                for (final e in lines)
                  ApplicationLineDraft(
                    productId: productOf[e.product]!,
                    quantityBase: e.quantity!,
                  ),
              ],
            ),
          );
        case 'REVERSAL':
          await repo.reverseApplication(
            applicationOf[group]!,
            reason: 'dataset F06 fila ${lines.first.row}',
          );
        case 'NEED' || 'NEED_CANCEL':
          break;
        default:
          throw StateError('Evento desconocido: $kind');
      }
    }
  }
  return F06Farm(
    farmer: farmer,
    database: database,
    campaignOf: campaignOf,
    productOf: productOf,
  );
}

/// Retira las necesidades marcadas NEED_CANCEL (ya sincronizadas). Devuelve
/// cuántas retiró.
Future<int> applyF06Cancellations(F06Farm farm) async {
  final current = await farm.needs.needs();
  var withdrawn = 0;
  for (final e in f06Events(
    farm.farmer,
  ).where((e) => e.event == 'NEED_CANCEL')) {
    final need = current.singleWhere(
      (n) =>
          n.campaignId == farm.campaignOf[e.campaign] &&
          n.productId == farm.productOf[e.product],
    );
    await farm.needs.withdraw(need.id);
    withdrawn++;
  }
  return withdrawn;
}

/// Reabre una base ya sembrada (segunda ejecución del E2E).
Future<F06Farm> reopenF06Farm({
  required AppDatabase database,
  required String farmer,
}) async {
  final db = await database.database;
  final campaigns = await db.query('campaigns', orderBy: 'id');
  final products = await db.query('products', orderBy: 'id');
  return F06Farm(
    farmer: farmer,
    database: database,
    campaignOf: {
      for (final MapEntry(key: code, value: local) in _localCampaigns.entries)
        code:
            campaigns.singleWhere((c) => c['name'] == local.name)['id']! as int,
    },
    productOf: {
      for (final row in products) row['name']! as String: row['id']! as int,
    },
  );
}

/// Referencias centrales sintéticas con los nombres del dataset (pruebas sin
/// Backend). Los UUID son fijos y no existen en ningún entorno.
CentralReferences f06SyntheticReferences() {
  CentralProduct product(String ref, String name, String unit) {
    final base = BaseUnit.forCentralUnit(unit);
    return CentralProduct(
      ref: ref,
      name: name,
      unit: unit,
      baseUnit: base,
      isActive: true,
      linkable: base != null,
    );
  }

  return CentralReferences(
    [
      for (final (ref, name) in [
        ('a6000000-0000-4000-8000-000000000001', 'Campana Verano 2026'),
        ('a6000000-0000-4000-8000-000000000002', 'Campana Invierno 2026'),
      ])
        CentralCampaign(
          ref: ref,
          name: name,
          status: 'ABIERTA',
          startDate: '2026-01-01T00:00:00.000Z',
          endDate: null,
          acceptsContributions: true,
        ),
    ],
    [
      product('b6000000-0000-4000-8000-000000000001', 'Belator', 'L'),
      product('b6000000-0000-4000-8000-000000000002', 'Bellator', 'L'),
      product('b6000000-0000-4000-8000-000000000003', 'Glifosato F06', 'L'),
      product('b6000000-0000-4000-8000-000000000004', 'Urea F06', 'KG'),
      product('b6000000-0000-4000-8000-000000000005', 'Mancozeb F06', 'KG'),
    ],
  );
}

/// Identidad de instalación sintética (UUID v4) de un agricultor del dataset.
String f06InstallationClientId(String farmer) => switch (farmer) {
  'F1' => 'f6000000-0000-4000-8000-000000000001',
  'F2' => 'f6000000-0000-4000-8000-000000000002',
  _ => 'f6000000-0000-4000-8000-000000000003',
};

/// Referencia de instalación de esa identidad (la que guarda el titular).
String f06InstallationRef(String farmer) =>
    installationReference(f06InstallationClientId(farmer));
