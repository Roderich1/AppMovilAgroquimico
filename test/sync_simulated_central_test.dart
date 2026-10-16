// Recorrido completo contra un Central SIMULADO (no el Backend real): el
// brief D3 (Plan B) admite simular el paso 3 —respuesta perdida después del
// commit— y declararlo así en la evidencia. El simulador reproduce las reglas
// del contrato F05 que Mobile necesita: identidad por operationId, reenvío
// idéntico = ALREADY_APPLIED con la hora original, contenido distinto =
// IDEMPOTENCY_MISMATCH, y causalidad sin LWW (fork → CONFLICT).
import 'dart:convert';
import 'dart:math';

import 'package:agroquimicos/data/sync/declared_need_store.dart'
    show ConflictChoice, DeclaredNeedStatus;
import 'package:agroquimicos/domain/sync/sync_types.dart';
import 'package:agroquimicos/services/auth/api_endpoint_config.dart';
import 'package:agroquimicos/services/auth/auth_http_client.dart';
import 'package:agroquimicos/services/sync/sync_access.dart';
import 'package:agroquimicos/services/sync/sync_api.dart';
import 'package:agroquimicos/services/sync/sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';
import 'support/f05_sync_fixtures.dart';

class _Contribution {
  String status = 'NEVER_PUBLISHED';
  String? head;
  String? headAction;
  String? quantity;
  String? dispute;
}

class SimulatedCentral {
  final journal = <String, ({String body, String ack})>{};
  final contributions = <String, _Contribution>{};
  var _clock = 0;
  var _disputes = 0;

  /// Si es true, el próximo push se confirma y la respuesta se pierde.
  bool loseNextResponse = false;

  late final client = MockClient((request) async {
    if (request.method == 'GET') return _get(request.url.pathSegments.last);
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final canonical = jsonEncode(_canonical(body));
    final id = body['operationId'] as String;
    final prior = journal[id];
    final String ack;
    if (prior != null) {
      ack = prior.body == canonical
          ? prior.ack.replaceFirst('"APPLIED"', '"ALREADY_APPLIED"')
          : _ack(id, 'REJECTED', 'IDEMPOTENCY_MISMATCH');
    } else {
      ack = _decide(id, body);
      journal[id] = (body: canonical, ack: ack);
    }
    if (loseNextResponse) {
      loseNextResponse = false;
      throw http.ClientException('respuesta perdida después del commit');
    }
    return http.Response(ack, 200);
  });

  static List<Object?> _canonical(Map<String, dynamic> body) {
    final causal = body['causal'] as Map;
    final payload = body['payload'] as Map;
    return [
      body['contractVersion'],
      body['operationId'],
      body['projectionType'],
      body['action'],
      causal['predecessorOperationId'],
      causal['reconciliationReference'],
      payload['campaign_ref'],
      payload['product_ref'],
      payload['base_unit'],
      payload['quantity_base'],
    ];
  }

  String _key(Map<String, dynamic> body) {
    final payload = body['payload'] as Map;
    return '${body['projectionType']}|${payload['campaign_ref']}|'
        '${payload['product_ref']}|${payload['base_unit']}';
  }

  String _ack(String id, String outcome, String code, {String? reference}) {
    _clock++;
    final accepted = outcome == 'APPLIED';
    return ackJson(
      id,
      outcome: outcome,
      code: code,
      acceptedAt: accepted
          ? '2026-10-15T12:00:${_clock.toString().padLeft(2, '0')}.000Z'
          : null,
      reference: reference,
    );
  }

  String _decide(String id, Map<String, dynamic> body) {
    final c = contributions.putIfAbsent(_key(body), _Contribution.new);
    final action = body['action'] as String;
    final causal = body['causal'] as Map;
    final predecessor = causal['predecessorOperationId'] as String?;
    final reference = causal['reconciliationReference'] as String?;
    final quantity = (body['payload'] as Map)['quantity_base'] as String?;
    void apply() {
      c
        ..head = id
        ..headAction = action
        ..dispute = null
        ..status = action == 'CANCEL' ? 'CANCELLED' : 'ACTIVE'
        ..quantity = action == 'CANCEL' ? null : quantity;
    }

    if (c.dispute != null) {
      if (reference == c.dispute && predecessor == c.head) {
        apply();
        return _ack(id, 'APPLIED', 'OK');
      }
      return _ack(id, 'CONFLICT', 'RECONCILIATION_STALE', reference: c.dispute);
    }
    final continuesHead = predecessor == c.head;
    final valid = switch ((c.status, action)) {
      ('NEVER_PUBLISHED', 'PUBLISH') => predecessor == null,
      ('ACTIVE', 'SUPERSEDE' || 'CANCEL') => continuesHead,
      ('CANCELLED', 'PUBLISH') => continuesHead,
      _ => false,
    };
    if (valid) {
      apply();
      return _ack(id, 'APPLIED', 'OK');
    }
    // Un sucesor de un head anterior: fork, sin cantidad consolidable.
    c
      ..dispute =
          '${(++_disputes).toString().padLeft(8, '0')}-6666-4666-8666-666666666666'
      ..status = c.status == 'CANCELLED' ? 'CANCELLED' : 'CONTESTED'
      ..quantity = null;
    return _ack(id, 'CONFLICT', 'CAUSAL_FORK', reference: c.dispute);
  }

  http.Response _get(String operationId) {
    final record = journal[operationId];
    if (record == null) {
      return http.Response(
        errorJson('OPERATION_NOT_FOUND', 'KEEP_FOR_RETRY'),
        404,
      );
    }
    final body = jsonDecode(record.body) as List;
    final key = '${body[2]}|${body[6]}|${body[7]}|${body[8]}';
    final c = contributions[key]!;
    return http.Response(
      jsonEncode({
        'ack': jsonDecode(
          record.ack.replaceFirst('"APPLIED"', '"ALREADY_APPLIED"'),
        ),
        'contribution': {
          'status': c.status,
          'headOperationId': c.head,
          'reconciliationReference': c.dispute,
        },
      }),
      200,
    );
  }

  /// Otro teléfono del mismo Member publica una sustitución del head.
  void otherDeviceSupersedes(String quantity) {
    final c = contributions.values.single;
    final body = {
      'contractVersion': 1,
      'operationId': '88888888-8888-4888-8888-888888888888',
      'projectionType': 'DECLARED_NEED',
      'action': 'SUPERSEDE',
      'causal': {
        'predecessorOperationId': c.head,
        'reconciliationReference': null,
      },
      'payload': {
        'campaign_ref': campaignRef,
        'product_ref': litreRef,
        'base_unit': 'ML',
        'quantity_base': quantity,
      },
    };
    final id = body['operationId']! as String;
    journal[id] = (body: jsonEncode(_canonical(body)), ack: _decide(id, body));
  }
}

void main() {
  sqfliteFfiInit();

  test('recorrido simulado: pendiente sin red, ACK perdido tras el commit, SUPERSEDE, CANCEL y un solo efecto', () async {
    final central = SimulatedCentral();
    final path = await tempDbPath('simulado');
    var fixture = await seedSyncFixture(path: path);
    final access = SyncAccessHolder();
    final api = SyncApi(
      AuthHttpClient(
        config: ApiEndpointConfig(Uri.parse('https://sindicato.example')),
        client: central.client,
      ),
    );
    var clock = DateTime.utc(2026, 10, 15, 12);
    SyncWorker workerFor(SyncFixture f) => SyncWorker(
      outbox: f.outbox,
      owners: f.owners,
      api: () => api,
      access: access,
      random: Random(1),
      clock: () => clock,
    );

    // 1. Sin conexión (sin acceso verificado): queda pendiente.
    final needId = await fixture.needs.declare(
      referenceDate: inCampaign,
      productId: fixture.litreProductId,
      quantityBase: 25000,
    );
    expect(
      (await workerFor(fixture).run()).blocker,
      SyncBlocker.accessRequired,
    );
    expect(central.journal, isEmpty);
    expect(
      (await fixture.needs.needs()).single.syncStatus,
      OutboxStatus.pending,
    );

    // 2. En línea: sincronizado; Central tiene una contribución y un journal.
    access.accept('token-sintetico', memberA.memberId, memberA.tenantId);
    await workerFor(fixture).run();
    expect(central.journal, hasLength(1));
    expect(central.contributions.values.single.quantity, '25000');
    expect((await fixture.needs.needs()).single.syncStatus, OutboxStatus.acked);

    // 3. Editar; Central confirma y la respuesta se pierde. El reintento
    //    obtiene ALREADY_APPLIED y no hay un segundo efecto.
    await fixture.needs.updateQuantity(needId, 30000);
    central.loseNextResponse = true;
    expect((await workerFor(fixture).run()).blocker, SyncBlocker.unreachable);
    expect(central.journal, hasLength(2));
    clock = clock.add(const Duration(hours: 1));
    await workerFor(fixture).run();
    expect(central.journal, hasLength(2));
    expect(central.contributions.values.single.quantity, '30000');
    final supersede = (await fixture.outboxEntries()).last;
    expect(supersede.action, SyncAction.supersede);
    expect(supersede.status, OutboxStatus.acked);
    expect(supersede.attempts, 2);

    // 4. Cierre forzado durante el envío de la anulación: al reabrir se
    //    reenvía el mismo operationId.
    await fixture.needs.withdraw(needId);
    await fixture.outbox.markSending((await fixture.outboxEntries()).last);
    await fixture.database.close();
    final reopened = openDb(path);
    fixture = reopenFixture(fixture, reopened);
    await workerFor(fixture).run();
    expect(central.journal, hasLength(3));
    expect(central.contributions.values.single.status, 'CANCELLED');
    expect(central.contributions.values.single.quantity, isNull);
    final entries = await fixture.outboxEntries();
    expect(entries.map((e) => e.action), [
      SyncAction.publish,
      SyncAction.supersede,
      SyncAction.cancel,
    ]);
    expect(entries.map((e) => e.status).toSet(), {OutboxStatus.acked});
    expect(
      (await fixture.needs.needs()).single.status,
      DeclaredNeedStatus.cancelled,
    );
  });

  test('fork desde otro teléfono: CONFLICT sin cantidad; decide el propietario y Central acepta la resolución', () async {
    final central = SimulatedCentral();
    final fixture = await seedSyncFixture();
    final access = SyncAccessHolder()
      ..accept('token-sintetico', memberA.memberId, memberA.tenantId);
    final api = SyncApi(
      AuthHttpClient(
        config: ApiEndpointConfig(Uri.parse('https://sindicato.example')),
        client: central.client,
      ),
    );
    final worker = SyncWorker(
      outbox: fixture.outbox,
      owners: fixture.owners,
      api: () => api,
      access: access,
      random: Random(1),
    );
    final needId = await fixture.needs.declare(
      referenceDate: inCampaign,
      productId: fixture.litreProductId,
      quantityBase: 1000,
    );
    await worker.run();
    central.otherDeviceSupersedes('5000');
    await fixture.needs.updateQuantity(needId, 2000);
    final report = await worker.run();
    expect(report.conflicts, 1);
    expect(central.contributions.values.single.status, 'CONTESTED');
    expect(central.contributions.values.single.quantity, isNull);
    final need = (await fixture.needs.needs()).single;
    expect(need.needsResolution, isTrue);

    final view = await api.operation(need.syncOperationId!, 'token-sintetico');
    expect(view.contribution!.status, 'CONTESTED');
    await fixture.needs.resolveConflict(
      needId: needId,
      choice: ConflictChoice.keepMine,
      view: view,
    );
    await worker.run();
    final contribution = central.contributions.values.single;
    expect(contribution.status, 'ACTIVE');
    expect(contribution.quantity, '2000');
    expect(contribution.dispute, isNull);
    final resolution = (await fixture.outboxEntries()).last;
    expect(resolution.status, OutboxStatus.acked);
    expect(
      resolution.predecessorOperationId,
      '88888888-8888-4888-8888-888888888888',
    );
    expect(resolution.reconciliationReference, isNotNull);
    expect((await fixture.needs.needs()).single.needsResolution, isFalse);
  });
}
