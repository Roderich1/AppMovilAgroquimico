// Soporte de pruebas de la sincronización F05 (vínculos, necesidad declarada,
// outbox y worker). Todos los datos son sintéticos.
import 'dart:convert';

import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/data/sync/central_binding_store.dart';
import 'package:agroquimicos/data/sync/declared_need_store.dart';
import 'package:agroquimicos/data/sync/sync_outbox_store.dart';
import 'package:agroquimicos/domain/sync/central_references.dart';
import 'package:agroquimicos/domain/sync/sync_types.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'f04_mode_fixtures.dart';

const campaignRef = '0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';
const otherCampaignRef = '1a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';
const litreRef = '2a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';
const kiloRef = '3a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';
const unitRef = '4a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';
const otherLitreRef = '5a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';

/// Fecha dentro de la campaña sembrada (inicia el 2026-09-01, sin fin).
final inCampaign = DateTime(2026, 10, 15);

CentralCampaign centralCampaign({
  String ref = campaignRef,
  String name = 'Campaña sindicato 2026',
  bool accepts = true,
}) => CentralCampaign(
  ref: ref,
  name: name,
  status: accepts ? 'ABIERTA' : 'CERRADA',
  startDate: '2026-09-01T00:00:00.000Z',
  endDate: null,
  acceptsContributions: accepts,
);

CentralProduct centralProduct({
  String ref = litreRef,
  String name = 'Herbicida central',
  String unit = 'L',
  bool active = true,
}) {
  final base = BaseUnit.forCentralUnit(unit);
  return CentralProduct(
    ref: ref,
    name: name,
    unit: unit,
    baseUnit: base,
    isActive: active,
    linkable: base != null,
  );
}

CentralReferences referencesWith({
  bool campaignAccepts = true,
  bool litreActive = true,
  bool includeLitre = true,
}) => CentralReferences(
  [centralCampaign(accepts: campaignAccepts)],
  [
    if (includeLitre) centralProduct(active: litreActive),
    centralProduct(ref: kiloRef, name: 'Fungicida central', unit: 'KG'),
    centralProduct(ref: unitRef, name: 'Coadyuvante central', unit: 'unidad'),
  ],
);

/// JSON de referencias tal como lo publica Central (F05-SYNC-07).
Map<String, Object?> referencesJson() => {
  'contractVersion': 1,
  'campaigns': [
    {
      'campaign_ref': campaignRef,
      'name': 'Campaña sindicato 2026',
      'status': 'ABIERTA',
      'start_date': '2026-09-01T00:00:00.000Z',
      'end_date': null,
      'accepts_contributions': true,
    },
  ],
  'products': [
    {
      'product_ref': litreRef,
      'name': 'Herbicida central',
      'unit': 'L',
      'base_unit': 'ML',
      'is_active': true,
      'linkable': true,
    },
    {
      'product_ref': unitRef,
      'name': 'Coadyuvante central',
      'unit': 'unidad',
      'base_unit': null,
      'is_active': true,
      'linkable': false,
    },
  ],
};

class SyncFixture {
  SyncFixture({
    required this.database,
    required this.repo,
    required this.owners,
    required this.bindings,
    required this.needs,
    required this.outbox,
    required this.ownerBindingId,
    required this.campaignId,
    required this.litreProductId,
    required this.kiloProductId,
    required this.unboundProductId,
  });

  final AppDatabase database;
  final AgroRepository repo;
  final OwnerBindingStore owners;
  final CentralBindingStore bindings;
  final DeclaredNeedStore needs;
  final SyncOutboxStore outbox;
  final int ownerBindingId;
  final int campaignId;
  final int litreProductId;
  final int kiloProductId;
  final int unboundProductId;

  Future<List<Map<String, Object?>>> outboxRows() async =>
      (await database.database).query('sync_outbox', orderBy: 'id');

  Future<List<OutboxEntry>> outboxEntries() async =>
      (await outboxRows()).map(OutboxEntry.fromRow).toList();
}

/// Los mismos datos sobre la base reabierta (tras un cierre forzado).
SyncFixture reopenFixture(
  SyncFixture old,
  AppDatabase reopened, {
  DateTime Function()? clock,
}) => SyncFixture(
  database: reopened,
  repo: AgroRepository(reopened),
  owners: OwnerBindingStore(reopened),
  bindings: CentralBindingStore(reopened, clock: clock),
  needs: DeclaredNeedStore(reopened, clock: clock),
  outbox: SyncOutboxStore(reopened, clock: clock),
  ownerBindingId: old.ownerBindingId,
  campaignId: old.campaignId,
  litreProductId: old.litreProductId,
  kiloProductId: old.kiloProductId,
  unboundProductId: old.unboundProductId,
);

/// Base con titular vinculado (Member A), una campaña vigente, productos en
/// L y KG vinculados con Central y uno en L sin vincular.
Future<SyncFixture> seedSyncFixture({
  String? path,
  bool bindCatalog = true,
  DateTime Function()? clock,
}) async {
  final database = openDb(path ?? inMemoryDatabasePath);
  final repo = AgroRepository(database);
  final owners = OwnerBindingStore(database);
  final binding = await owners.bindNewPerson(
    name: 'Titular sintético',
    scope: memberA,
    installationRef: installationHere,
  );
  final campaignId = await repo.addCampaign(
    name: 'Campaña local 2026',
    start: DateTime(2026, 9, 1),
  );
  final litre = await repo.addProduct(name: 'Herbicida local', unit: 'L');
  final kilo = await repo.addProduct(name: 'Fungicida local', unit: 'KG');
  final unbound = await repo.addProduct(name: 'Adherente local', unit: 'L');
  final bindings = CentralBindingStore(database, clock: clock);
  if (bindCatalog) {
    await bindings.bindCampaign(
      campaignId: campaignId,
      central: centralCampaign(),
      tenantId: memberA.tenantId,
    );
    await bindings.bindProduct(
      productId: litre,
      central: centralProduct(),
      tenantId: memberA.tenantId,
    );
    await bindings.bindProduct(
      productId: kilo,
      central: centralProduct(
        ref: kiloRef,
        name: 'Fungicida central',
        unit: 'KG',
      ),
      tenantId: memberA.tenantId,
    );
  }
  return SyncFixture(
    database: database,
    repo: repo,
    owners: owners,
    bindings: bindings,
    needs: DeclaredNeedStore(database, clock: clock),
    outbox: SyncOutboxStore(database, clock: clock),
    ownerBindingId: binding.id,
    campaignId: campaignId,
    litreProductId: litre,
    kiloProductId: kilo,
    unboundProductId: unbound,
  );
}

/// Cuerpo de un ACK de Central para [operationId].
String ackJson(
  String operationId, {
  String outcome = 'APPLIED',
  String? code,
  String? acceptedAt = '2026-10-15T12:00:00.000Z',
  String? reference,
}) {
  final disposition = switch (outcome) {
    'APPLIED' || 'ALREADY_APPLIED' => 'RETIRE_FROM_OUTBOX',
    'CONFLICT' => 'KEEP_FOR_RECONCILIATION',
    'REJECTED' => 'MOVE_TO_TERMINAL_FAILURE',
    _ => 'KEEP_FOR_RETRY',
  };
  final accepted = outcome == 'APPLIED' || outcome == 'ALREADY_APPLIED';
  return jsonEncode({
    'contractVersion': 1,
    'operationId': operationId,
    'outcome': outcome,
    'disposition': disposition,
    'serverAcceptedAt': accepted ? acceptedAt : null,
    'code': code ?? (accepted ? 'OK' : 'CAUSAL_FORK'),
    'reconciliationReference': outcome == 'CONFLICT'
        ? (reference ?? '6a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d')
        : null,
  });
}

String errorJson(String errorCode, String disposition) => jsonEncode({
  'contractVersion': 1,
  'operationId': null,
  'errorCode': errorCode,
  'disposition': disposition,
});
