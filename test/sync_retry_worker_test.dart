// Worker de Sync v1 (MOB #31): una prueba por respuesta del contrato F05
// (§7–§11) y por regla del worker (orden causal, mismo envelope, cierre
// forzado, pausas). El transporte es un MockClient: nada sale a la red.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:agroquimicos/data/owner_binding_store.dart'
    show OwnerBindingException;
import 'package:agroquimicos/data/sync/sync_outbox_store.dart';
import 'package:agroquimicos/domain/installation_access.dart';
import 'package:agroquimicos/domain/models.dart';
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

final now = DateTime.utc(2026, 10, 15, 12);

typedef Handler = FutureOr<http.Response> Function(http.Request request);

/// Transporte con respuestas guionadas; registra cada request.
class ScriptedTransport {
  ScriptedTransport(this.handlers);
  final List<Handler> handlers;
  final requests = <http.Request>[];

  late final client = MockClient((request) async {
    requests.add(request);
    if (requests.length > handlers.length) {
      fail('request inesperado #${requests.length}: ${request.url.path}');
    }
    return handlers[requests.length - 1](request);
  });

  List<Map<String, dynamic>> get bodies => [
    for (final request in requests)
      jsonDecode(request.body) as Map<String, dynamic>,
  ];
}

http.Response ack(
  http.Request request, {
  String outcome = 'APPLIED',
  String? code,
}) {
  final id = (jsonDecode(request.body) as Map)['operationId'] as String;
  return http.Response(ackJson(id, outcome: outcome, code: code), 200);
}

http.Response error(
  int status,
  String code,
  String disposition, {
  Map<String, String> headers = const {},
}) => http.Response(errorJson(code, disposition), status, headers: headers);

class Harness {
  Harness(this.fixture, this.transport, this.access, this.worker);
  final SyncFixture fixture;
  final ScriptedTransport transport;
  final SyncAccessHolder access;
  final SyncWorker worker;

  Future<List<OutboxEntry>> entries() => fixture.outboxEntries();
}

Future<Harness> harness(
  List<Handler> handlers, {
  SyncFixture? fixture,
  OwnerScope scope = memberA,
  bool withAccess = true,
}) async {
  final seeded = fixture ?? await seedSyncFixture(clock: () => now);
  final transport = ScriptedTransport(handlers);
  final access = SyncAccessHolder(clock: () => now);
  if (withAccess)
    access.accept('token-sintetico', scope.memberId, scope.tenantId);
  final api = SyncApi(
    AuthHttpClient(
      config: ApiEndpointConfig(Uri.parse('https://sindicato.example')),
      client: transport.client,
    ),
    clock: () => now,
  );
  final worker = SyncWorker(
    outbox: seeded.outbox,
    owners: seeded.owners,
    api: () => api,
    access: access,
    random: Random(7),
    clock: () => now,
  );
  return Harness(seeded, transport, access, worker);
}

Future<int> declare(SyncFixture fixture, int quantity, {int? productId}) =>
    fixture.needs.declare(
      referenceDate: inCampaign,
      productId: productId ?? fixture.litreProductId,
      quantityBase: quantity,
    );

void main() {
  sqfliteFfiInit();

  test(
    'APPLIED: sincronizado con la hora del servidor; nada más se envía',
    () async {
      final h = await harness([(r) => ack(r)]);
      await declare(h.fixture, 1000);
      final report = await h.worker.run();
      expect(report.accepted, 1);
      final entry = (await h.entries()).single;
      expect(entry.status, OutboxStatus.acked);
      expect(entry.serverAcceptedAt, '2026-10-15T12:00:00.000Z');
      expect(entry.attempts, 1);
      expect((await h.worker.run()).sent, 0);
      expect(h.transport.requests, hasLength(1));
      final request = h.transport.requests.single;
      expect(request.url.path, '/api/v1/sync/v1/push');
      expect(request.headers['authorization'], 'Bearer token-sintetico');
    },
  );

  test('ALREADY_APPLIED también retira de la cola', () async {
    final h = await harness([(r) => ack(r, outcome: 'ALREADY_APPLIED')]);
    await declare(h.fixture, 1000);
    await h.worker.run();
    expect((await h.entries()).single.status, OutboxStatus.acked);
  });

  test('RETRYABLE: sigue pendiente con backoff y el mismo envelope', () async {
    final h = await harness([
      (r) => ack(r, outcome: 'RETRYABLE', code: 'DEPENDENCY_PENDING'),
    ]);
    await declare(h.fixture, 1000);
    await h.worker.run();
    final entry = (await h.entries()).single;
    expect(entry.status, OutboxStatus.pending);
    expect(entry.lastCode, 'DEPENDENCY_PENDING');
    expect(DateTime.parse(entry.nextAttemptAt!).isAfter(now), isTrue);
    // Antes de la hora programada no se reintenta.
    expect((await h.worker.run()).sent, 0);
  });

  test('429 con Retry-After: se espera al menos esa demora', () async {
    final h = await harness([
      (_) => error(
        429,
        'RATE_LIMITED',
        'KEEP_FOR_RETRY',
        headers: {'retry-after': '1200'},
      ),
    ]);
    await declare(h.fixture, 1000);
    final report = await h.worker.run();
    expect(report.blocker, SyncBlocker.throttled);
    final entry = (await h.entries()).single;
    expect(entry.status, OutboxStatus.pending);
    expect(
      DateTime.parse(entry.nextAttemptAt!).difference(now),
      greaterThanOrEqualTo(const Duration(seconds: 1200)),
    );
  });

  test('503 cerrado: pendiente con backoff, mismo ID', () async {
    final h = await harness([
      (_) => error(503, 'TEMPORARILY_UNAVAILABLE', 'KEEP_FOR_RETRY'),
    ]);
    await declare(h.fixture, 1000);
    await h.worker.run();
    final entry = (await h.entries()).single;
    expect(entry.status, OutboxStatus.pending);
    expect(entry.lastCode, 'TEMPORARILY_UNAVAILABLE');
  });

  for (final failure in <String, Handler>{
    'timeout': (_) => throw TimeoutException('lento'),
    'error de red': (_) => throw http.ClientException('sin red'),
    '500': (_) => error(500, 'TEMPORARILY_UNAVAILABLE', 'KEEP_FOR_RETRY'),
  }.entries) {
    test(
      '${failure.key}: resultado desconocido; el reintento envía exactamente lo mismo',
      () async {
        final h = await harness([failure.value, (r) => ack(r)]);
        await declare(h.fixture, 1000);
        final first = await h.worker.run();
        expect(first.blocker, SyncBlocker.unreachable);
        final pending = (await h.entries()).single;
        expect(pending.status, OutboxStatus.outcomeUnknown);
        // El reintento llega después del backoff.
        final later = SyncWorker(
          outbox: h.fixture.outbox,
          owners: h.fixture.owners,
          api: () => SyncApi(
            AuthHttpClient(
              config: ApiEndpointConfig(Uri.parse('https://sindicato.example')),
              client: h.transport.client,
            ),
          ),
          access: h.access,
          clock: () => now.add(const Duration(hours: 1)),
        );
        await later.run();
        expect(h.transport.bodies, hasLength(2));
        expect(h.transport.bodies[1], h.transport.bodies[0]);
        final settled = (await h.entries()).single;
        expect(settled.status, OutboxStatus.acked);
        expect(settled.operationId, pending.operationId);
        expect(settled.attempts, 2);
      },
    );
  }

  test('CONFLICT: visible, con su referencia; no se reintenta', () async {
    final h = await harness([(r) => ack(r, outcome: 'CONFLICT')]);
    await declare(h.fixture, 1000);
    final report = await h.worker.run();
    expect(report.conflicts, 1);
    final entry = (await h.entries()).single;
    expect(entry.status, OutboxStatus.conflict);
    expect(entry.lastCode, 'CAUSAL_FORK');
    expect(entry.ackReconciliationReference, isNotNull);
    expect((await h.worker.run()).sent, 0);
    // La necesidad queda esperando la decisión del propietario.
    expect((await h.fixture.needs.needs()).single.needsResolution, isTrue);
    await expectLater(
      h.fixture.needs.updateQuantity(
        (await h.fixture.needs.needs()).single.id,
        2000,
      ),
      throwsA(isA<SyncConflictPendingException>()),
    );
  });

  test('REJECTED: código visible, sin reintento; la sucesora pendiente se apoya en el antecesor real', () async {
    final h = await harness([
      (_) => throw TimeoutException('lento'),
      (r) => ack(r, outcome: 'REJECTED', code: 'CAMPAIGN_NOT_OPEN'),
    ]);
    final id = await declare(h.fixture, 1000);
    await h.worker.run(); // PUBLISH queda con resultado desconocido
    await h.fixture.needs.updateQuantity(id, 2000); // SUPERSEDE encadenado
    final later = SyncWorker(
      outbox: h.fixture.outbox,
      owners: h.fixture.owners,
      api: () => SyncApi(
        AuthHttpClient(
          config: ApiEndpointConfig(Uri.parse('https://sindicato.example')),
          client: h.transport.client,
        ),
      ),
      access: h.access,
      clock: () => now.add(const Duration(hours: 1)),
      budget: 1,
    );
    final report = await later.run();
    expect(report.rejected, 1);
    final entries = await h.entries();
    expect(entries.first.status, OutboxStatus.rejected);
    expect(entries.first.lastCode, 'CAMPAIGN_NOT_OPEN');
    // Central nunca aceptó el PUBLISH: la sucesora pasa a ser un PUBLISH
    // sin antecesor, con la cantidad vigente.
    expect(entries.last.action, SyncAction.publish);
    expect(entries.last.predecessorOperationId, isNull);
    expect(entries.last.quantityBase, '2000');
    expect(entries.last.status, OutboxStatus.pending);
  });

  test('REJECTED CAMPAIGN_SEALED: terminal, explicado, sin reintento ni al reiniciar', () async {
    final h = await harness([
      (r) => ack(r, outcome: 'REJECTED', code: 'CAMPAIGN_SEALED'),
    ]);
    await declare(h.fixture, 1000);
    final report = await h.worker.run();
    expect(report.rejected, 1);
    final entry = (await h.entries()).single;
    expect(entry.status, OutboxStatus.rejected);
    expect(entry.lastCode, 'CAMPAIGN_SEALED');
    expect(entry.interventionMessage, contains('sellada'));
    // Neither this worker nor a new one (app restart) sends it again.
    expect((await h.worker.run()).sent, 0);
    final restarted = SyncWorker(
      outbox: h.fixture.outbox,
      owners: h.fixture.owners,
      api: () => SyncApi(
        AuthHttpClient(
          config: ApiEndpointConfig(Uri.parse('https://sindicato.example')),
          client: h.transport.client,
        ),
      ),
      access: h.access,
      clock: () => now.add(const Duration(days: 1)),
      budget: 5,
    );
    expect((await restarted.run()).sent, 0);
    expect((await h.entries()).single.attempts, entry.attempts);
  });

  test('CAMPAIGN_NOT_OPEN explains without saying sealed', () {
    expect(
      rejectionExplanation('CAMPAIGN_NOT_OPEN'),
      isNot(contains('sellad')),
    );
    expect(rejectionExplanation('QUANTITY_INVALID'), isNull);
  });

  for (final rejected in [
    (400, 'INVALID_REQUEST'),
    (413, 'REQUEST_TOO_LARGE'),
    (415, 'UNSUPPORTED_MEDIA_TYPE'),
  ]) {
    test(
      '${rejected.$1}: fallo terminal visible, sin reintento automático',
      () async {
        final h = await harness([
          (_) => error(rejected.$1, rejected.$2, 'MOVE_TO_TERMINAL_FAILURE'),
        ]);
        await declare(h.fixture, 1000);
        await h.worker.run();
        final entry = (await h.entries()).single;
        expect(entry.status, OutboxStatus.failed);
        expect(entry.lastCode, rejected.$2);
        expect((await h.worker.run()).sent, 0);
      },
    );
  }

  test(
    '400 de un proxy (cuerpo no cerrado): no se confía en él, se reintenta',
    () async {
      final h = await harness([(_) => http.Response('Bad gateway', 400)]);
      await declare(h.fixture, 1000);
      await h.worker.run();
      expect((await h.entries()).single.status, OutboxStatus.outcomeUnknown);
    },
  );

  test('401: vuelve a la cola, se descarta el token y no hay bucle', () async {
    final h = await harness([
      (_) => error(401, 'AUTH_REQUIRED', 'KEEP_FOR_RETRY'),
    ]);
    await declare(h.fixture, 1000);
    final report = await h.worker.run();
    expect(report.blocker, SyncBlocker.accessRequired);
    expect(h.access.current, isNull);
    final entry = (await h.entries()).single;
    expect(entry.status, OutboxStatus.pending);
    expect(entry.lastCode, 'AUTH_REQUIRED');
    // Sin verificar de nuevo el acceso, el worker no hace ningún request.
    expect((await h.worker.run()).blocker, SyncBlocker.accessRequired);
    expect(h.transport.requests, hasLength(1));
  });

  test('403: toda la cola del titular queda pausada; nada se borra', () async {
    final h = await harness([
      (_) => error(403, 'AUTH_CONTEXT_FORBIDDEN', 'KEEP_FOR_RECONCILIATION'),
    ]);
    await declare(h.fixture, 1000);
    await declare(h.fixture, 500, productId: h.fixture.kiloProductId);
    final report = await h.worker.run();
    expect(report.blocker, SyncBlocker.forbidden);
    final entries = await h.entries();
    expect(entries, hasLength(2));
    expect(entries.map((e) => e.status).toSet(), {OutboxStatus.authPaused});
    expect(h.transport.requests, hasLength(1));
    // Tras reautenticar al mismo titular, la cola vuelve con el mismo ID.
    await h.fixture.outbox.resumeAuthorizationPaused(h.fixture.ownerBindingId);
    expect(
      (await h.entries()).map((e) => e.operationId),
      entries.map((e) => e.operationId),
    );
  });

  test(
    '422: versión no compatible; el worker se detiene por completo',
    () async {
      final h = await harness([
        (_) =>
            error(422, 'CONTRACT_VERSION_MISMATCH', 'KEEP_FOR_RECONCILIATION'),
      ]);
      await declare(h.fixture, 1000);
      await declare(h.fixture, 500, productId: h.fixture.kiloProductId);
      final report = await h.worker.run();
      expect(report.blocker, SyncBlocker.versionMismatch);
      expect((await h.entries()).first.status, OutboxStatus.versionMismatch);
      expect((await h.worker.run()).blocker, SyncBlocker.versionMismatch);
      expect(h.transport.requests, hasLength(1));
    },
  );

  for (final incoherent in <String, String Function(String id)>{
    'otro operationId': (id) => ackJson('99999999-9999-4999-8999-999999999999'),
    'ACK sin hora de aceptación': (id) =>
        ackJson(id).replaceFirst('"2026-10-15T12:00:00.000Z"', 'null'),
    'cuerpo vacío': (id) => '',
    '2xx genérico': (id) => '{"ok":true}',
  }.entries) {
    test(
      'ACK incoherente (${incoherent.key}): resultado desconocido, nunca sincronizado',
      () async {
        final h = await harness([
          (r) => http.Response(
            incoherent.value(
              (jsonDecode(r.body) as Map)['operationId'] as String,
            ),
            200,
          ),
        ]);
        await declare(h.fixture, 1000);
        await h.worker.run();
        final entry = (await h.entries()).single;
        expect(entry.status, OutboxStatus.outcomeUnknown);
        expect(entry.lastCode, 'INVALID_ACK');
        expect(entry.serverAcceptedAt, isNull);
      },
    );
  }

  test('orden causal: la sucesora espera el ACK de su antecesora', () async {
    final h = await harness([
      (_) => throw TimeoutException('lento'),
      (r) => ack(r, outcome: 'ALREADY_APPLIED'),
      (r) => ack(r),
    ]);
    final id = await declare(h.fixture, 1000);
    await h.worker.run();
    await h.fixture.needs.updateQuantity(id, 3000);
    // Mientras la antecesora no tiene ACK, la sucesora no sale.
    final blocked = await h.fixture.outbox.readyToSend(
      activeBindingId: h.fixture.ownerBindingId,
      now: now.add(const Duration(hours: 1)),
    );
    expect(blocked.map((e) => e.action), [SyncAction.publish]);
    final later = SyncWorker(
      outbox: h.fixture.outbox,
      owners: h.fixture.owners,
      api: () => SyncApi(
        AuthHttpClient(
          config: ApiEndpointConfig(Uri.parse('https://sindicato.example')),
          client: h.transport.client,
        ),
      ),
      access: h.access,
      clock: () => now.add(const Duration(hours: 1)),
    );
    await later.run();
    final bodies = h.transport.bodies;
    expect(bodies.map((b) => b['action']), ['PUBLISH', 'PUBLISH', 'SUPERSEDE']);
    expect(
      (bodies[2]['causal'] as Map)['predecessorOperationId'],
      bodies[0]['operationId'],
    );
    expect((await h.entries()).map((e) => e.status).toSet(), {
      OutboxStatus.acked,
    });
  });

  test('cierre forzado durante el envío: al reabrir se reenvía el mismo operationId', () async {
    final path = await tempDbPath('crash');
    final fixture = await seedSyncFixture(path: path, clock: () => now);
    await declare(fixture, 1000);
    // El intento quedó registrado y la app murió sin respuesta.
    final sending = await fixture.outbox.markSending(
      (await fixture.outboxEntries()).single,
    );
    await fixture.database.close();

    final reopened = openDb(path);
    final h = await harness([
      (r) => ack(r, outcome: 'ALREADY_APPLIED'),
    ], fixture: reopenFixture(fixture, reopened, clock: () => now));
    await h.worker.run();
    expect(h.transport.bodies.single['operationId'], sending.operationId);
    final entry = OutboxEntry.fromRow(
      (await (await reopened.database).query('sync_outbox')).single,
    );
    expect(entry.status, OutboxStatus.acked);
    expect(entry.attempts, 2);
  });

  test('sin acceso verificado no hay ninguna llamada de red', () async {
    final h = await harness(const [], withAccess: false);
    await declare(h.fixture, 1000);
    final report = await h.worker.run();
    expect(report.blocker, SyncBlocker.accessRequired);
    expect(h.transport.requests, isEmpty);
    expect((await h.entries()).single.status, OutboxStatus.pending);
  });

  test(
    'con nada que enviar tampoco se pide acceso ni se llama a la red',
    () async {
      final h = await harness(const [], withAccess: false);
      final report = await h.worker.run();
      expect(report.blocker, isNull);
      expect(h.transport.requests, isEmpty);
    },
  );

  test(
    'la cuenta en sesión de otro Member no publica lo de este titular',
    () async {
      final h = await harness(const [], scope: memberB);
      await declare(h.fixture, 1000);
      final report = await h.worker.run();
      expect(report.blocker, SyncBlocker.ownerMismatch);
      expect(h.transport.requests, isEmpty);
    },
  );

  test(
    'restaurar pausa la cola: nada se publica hasta que el titular la libera',
    () async {
      final h = await harness([(r) => ack(r)]);
      await declare(h.fixture, 1000);
      final db = await h.fixture.database.database;
      expect(
        await SyncOutboxStore.pauseAfterRestore(db, now.toIso8601String()),
        1,
      );
      expect((await h.worker.run()).sent, 0);
      expect(h.transport.requests, isEmpty);
      expect(
        await h.fixture.outbox.releaseRestored(h.fixture.ownerBindingId),
        1,
      );
      await h.worker.run();
      expect((await h.entries()).single.status, OutboxStatus.acked);
    },
  );

  test(
    'intenciones de un vínculo cerrado quedan pausadas, no se envían bajo otro',
    () async {
      final h = await harness(const []);
      await declare(h.fixture, 1000);
      final db = await h.fixture.database.database;
      // Simula una fila de otro vínculo (p. ej. llegada con una restauración).
      final other = await db.insert('owner_bindings', {
        'person_id': 1,
        'member_id': memberA.memberId,
        'tenant_id': memberA.tenantId,
        'owner_role': 'FAMILY',
        'bound_at': '2026-01-01T00:00:00.000Z',
        'ended_at': '2026-02-01T00:00:00.000Z',
        'end_reason': 'OWNER_CHANGED',
      });
      final row = (await h.fixture.outboxRows()).single;
      await db.insert(
        'sync_outbox',
        {
          ...row,
          'id': null,
          'operation_id': '77777777-7777-4777-8777-777777777777',
          'owner_binding_id': other,
        }..remove('id'),
      );
      await h.fixture.outbox.pauseOtherOwners(h.fixture.ownerBindingId);
      final entries = await h.entries();
      expect(
        entries.firstWhere((e) => e.ownerBindingId == other).status,
        OutboxStatus.ownerPaused,
      );
    },
  );

  test('cambiar de titular se bloquea con intenciones del vínculo; no con sólo rechazadas', () async {
    final h = await harness([
      (r) => ack(r, outcome: 'REJECTED', code: 'REFERENCE_UNAVAILABLE'),
    ]);
    final relative = await h.fixture.repo.addPerson(
      name: 'Familiar sintético',
      role: PersonRole.family,
    );
    await declare(h.fixture, 1000);
    await expectLater(
      h.fixture.owners.changeOwner(
        newPersonId: relative,
        sessionScope: memberA,
      ),
      throwsA(isA<OwnerBindingException>()),
    );
    await h.worker.run();
    expect((await h.entries()).single.status, OutboxStatus.rejected);
    final changed = await h.fixture.owners.changeOwner(
      newPersonId: relative,
      sessionScope: memberA,
    );
    expect(changed.personId, relative);
  });

  for (final requeued in <String, Handler>{
    'RETRYABLE': (r) =>
        ack(r, outcome: 'RETRYABLE', code: 'OPERATION_IN_PROGRESS'),
    '401': (_) => error(401, 'AUTH_REQUIRED', 'KEEP_FOR_RETRY'),
  }.entries) {
    test(
      'una intención que salió y volvió a la cola (${requeued.key}) no se reescribe: la edición se encadena',
      () async {
        final h = await harness([requeued.value]);
        final id = await declare(h.fixture, 1000);
        await h.worker.run();
        final sent = (await h.entries()).single;
        expect(sent.status, OutboxStatus.pending);
        expect(sent.attempts, 1);
        await h.fixture.needs.updateQuantity(id, 2000);
        final entries = await h.entries();
        expect(entries, hasLength(2));
        // La enviada conserva exactamente su contenido (Central pudo verla).
        expect(entries.first.quantityBase, '1000');
        expect(entries.first.operationId, sent.operationId);
        expect(entries.last.action, SyncAction.supersede);
        expect(entries.last.predecessorOperationId, sent.operationId);
      },
    );
  }

  test('tras un rechazo, la siguiente edición no se apoya en la intención rechazada', () async {
    final h = await harness([
      (r) => ack(r, outcome: 'REJECTED', code: 'CAMPAIGN_NOT_OPEN'),
    ]);
    final id = await declare(h.fixture, 1000);
    await h.worker.run();
    await h.fixture.needs.updateQuantity(id, 2000);
    final entries = await h.entries();
    expect(entries.first.status, OutboxStatus.rejected);
    // Central nunca aceptó la primera: la nueva es un PUBLISH sin antecesor.
    expect(entries.last.action, SyncAction.publish);
    expect(entries.last.predecessorOperationId, isNull);
    expect(entries.last.quantityBase, '2000');
  });

  test('el acceso en memoria caduca antes que el token del servidor', () {
    var clock = now;
    final holder = SyncAccessHolder(clock: () => clock)
      ..accept('token-sintetico', memberA.memberId, memberA.tenantId);
    expect(holder.current, isNotNull);
    expect(holder.current.toString(), isNot(contains('token-sintetico')));
    clock = now.add(const Duration(minutes: 10));
    expect(holder.current, isNull);
  });

  test('backoff: crece, se acota, tiene un mínimo y respeta al servidor', () {
    const backoff = SyncBackoff();
    final random = Random(3);
    for (var attempts = 1; attempts < 30; attempts++) {
      final delay = backoff.delay(attempts, random);
      expect(delay, greaterThanOrEqualTo(const Duration(seconds: 1)));
      expect(delay, lessThanOrEqualTo(const Duration(minutes: 15)));
    }
    expect(
      backoff.delay(1, random),
      lessThanOrEqualTo(const Duration(seconds: 2)),
    );
    expect(
      backoff.delay(1, random, retryAfter: const Duration(hours: 1)),
      const Duration(hours: 1),
    );
  });
}
