// Contrato E2 §4.2 y §5 con MockClient: emisor de participaciones. ACCEPTED,
// reintento idempotente con el mismo operation_id, STALE_SEQUENCE adopta lo
// del servidor, CALL_NOT_OPEN con DEADLINE_PASSED → «Fuera de plazo», 503 se
// reintenta, 401 pausa, otra cuenta no envía nada, una respuesta vieja no
// pisa lo aceptado más nuevo, y la lista se valida con lista cerrada. Sin red
// real; datos sintéticos.
import 'dart:convert';
import 'dart:math';

import 'package:agroquimicos/data/sync/joint_purchase_store.dart';
import 'package:agroquimicos/domain/installation_access.dart';
import 'package:agroquimicos/domain/sync/joint_purchase_call_view.dart';
import 'package:agroquimicos/services/auth/api_endpoint_config.dart';
import 'package:agroquimicos/services/auth/auth_api_exception.dart';
import 'package:agroquimicos/services/auth/auth_http_client.dart';
import 'package:agroquimicos/services/sync/joint_purchase_api.dart';
import 'package:agroquimicos/services/sync/joint_purchase_sender.dart';
import 'package:agroquimicos/services/sync/sync_access.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/e2_joint_purchase_fixtures.dart';
import 'support/f04_mode_fixtures.dart';
import 'support/f05_sync_fixtures.dart';

const _base = '/api/v1/me/joint-purchase-calls';

void main() {
  sqfliteFfiInit();

  late SyncFixture fixture;
  late JointPurchaseStore store;
  late JointPurchaseSender sender;
  late List<http.Request> requests;
  late http.Response Function(http.Request request) respond;
  late DateTime now;
  late List<Map<String, Object?>> served;
  final config = ApiEndpointConfig(Uri.parse('https://sindicato.example'));

  VerifiedAccess access([OwnerScope scope = memberA]) => VerifiedAccess(
    accessToken: 'token-sintetico',
    scope: scope,
    obtainedAt: now,
  );

  /// Servidor sintético: acepta y guarda la participación por convocatoria.
  final accepted = <String, Map<String, Object?>>{};
  final seenOps = <String, http.Response>{};
  http.Response central(http.Request request) {
    final path = request.url.path;
    if (request.method == 'GET' && path == _base) {
      return jsonResponse(
        listJson([
          for (final call in served)
            {...call, 'participation': accepted[call['call_id']]},
        ]),
        200,
      );
    }
    final id = path.split('/')[5];
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final opId = body['operation_id'] as String;
    final replay = seenOps[opId];
    if (replay != null) return replay;
    final last = accepted[id]?['last_sequence'] as int? ?? 0;
    final sequence = body['sequence'] as int;
    if (sequence <= last) {
      return jsonResponse({
        'errorCode': 'STALE_SEQUENCE',
        'participation': accepted[id],
      }, 409);
    }
    final withdraw = path.endsWith('/withdraw');
    accepted[id] = participationJson(
      lastSequence: sequence,
      withdrawn: withdraw,
      lines: withdraw
          ? const {}
          : {
              for (final line in body['lines'] as List<dynamic>)
                (line as Map)['product_ref'] as String: int.parse(
                  line['quantity_base'] as String,
                ),
            },
    );
    final response = jsonResponse({
      'outcome': 'ACCEPTED',
      'participation': accepted[id],
    }, 200);
    seenOps[opId] = response;
    return response;
  }

  setUp(() async {
    now = DateTime.utc(2026, 11, 11, 18, 20);
    accepted.clear();
    seenOps.clear();
    served = [callJson()];
    fixture = await seedSyncFixture();
    store = JointPurchaseStore(
      fixture.database,
      clock: () => now,
      random: Random(5),
    );
    await seedCalls(store, memberA, served);
    requests = [];
    respond = central;
    final client = MockClient((request) async {
      requests.add(request);
      return respond(request);
    });
    final api = JointPurchaseApi(
      json: AuthHttpClient(config: config, client: client),
      clock: () => now,
    );
    sender = JointPurchaseSender(
      store: store,
      owners: fixture.owners,
      api: () => api,
      random: Random(7),
      clock: () => now,
    );
  });

  Future<JointPurchaseOp> confirm(Map<String, int> lines) => store.confirm(
    callId: callId,
    lines: lines,
    consentVersion: jointPurchaseConsentVersion,
    consentAcceptedAt: now,
  );

  List<String> calls() => [
    for (final r in requests)
      '${r.method} ${r.url.path.replaceFirst(_base, '')}',
  ];

  test(
    'ACCEPTED: cuerpo exacto del contrato, RECEIVED y se adopta lo aceptado',
    () async {
      final op = await confirm({litreRef: 25000, kiloRef: 4500});
      final report = await sender.run(access());
      expect(report.received, 1);
      expect(calls(), ['PUT /$callId/participation', 'GET ']);
      final body = jsonDecode(requests.first.body) as Map<String, dynamic>;
      expect(body, {
        'operation_id': op.operationId,
        'sequence': 1,
        'consent': {'version': 'CONV-2', 'accepted_at': now.toIso8601String()},
        'lines': [
          {'product_ref': litreRef, 'quantity_base': '25000'},
          {'product_ref': kiloRef, 'quantity_base': '4500'},
        ],
      });
      expect(requests.first.headers['authorization'], 'Bearer token-sintetico');
      final stored = (await store.op(op.operationId))!;
      expect(stored.sendStatus, JointPurchaseOpStatus.received);
      final call = (await store.call(callId))!;
      expect(call.serverParticipation!.lines, {litreRef: 25000, kiloRef: 4500});
      expect(call.pendingOp, isNull);
    },
  );

  test('retiro: POST /withdraw con {operation_id, sequence}', () async {
    await confirm({litreRef: 25000});
    await sender.run(access());
    final withdraw = (await store.withdraw(callId))!;
    requests.clear();
    await sender.run(access());
    expect(calls().first, 'POST /$callId/participation/withdraw');
    expect(jsonDecode(requests.first.body), {
      'operation_id': withdraw.operationId,
      'sequence': 2,
    });
    final call = (await store.call(callId))!;
    expect(call.serverParticipation!.isActive, isFalse);
    expect(call.acceptedActive, isNull);
  });

  test('503: sigue pendiente y se reintenta con el mismo operation_id, sequence y cuerpo', () async {
    final op = await confirm({litreRef: 25000});
    respond = (request) => request.method == 'GET'
        ? central(request)
        : http.Response('', 503, headers: {'retry-after': '30'});
    final first = await sender.run(access());
    expect(first.retried, 1);
    var stored = (await store.op(op.operationId))!;
    expect(stored.sendStatus, JointPurchaseOpStatus.pendingSend);
    expect(stored.isTerminal, isFalse);
    expect(stored.lastCode, 'HTTP_503');
    expect(
      DateTime.parse(stored.nextAttemptAt!).difference(now),
      greaterThanOrEqualTo(const Duration(seconds: 30)),
    );
    final firstBody = requests.first.body;

    // Antes del reintento no sale nada.
    requests.clear();
    await sender.run(access());
    expect(calls().where((c) => c.startsWith('PUT')), isEmpty);

    // «Enviar ahora» lo vence ya, sin volverlo terminal; el reenvío es igual.
    await store.sendNow(callId);
    respond = central;
    requests.clear();
    final second = await sender.run(access(), includePaused: true);
    expect(second.received, 1);
    expect(requests.first.body, firstBody);
    stored = (await store.op(op.operationId))!;
    expect(stored.sendStatus, JointPurchaseOpStatus.received);
  });

  test(
    'la misma operación reenviada tras perder la respuesta no duplica nada',
    () async {
      final op = await confirm({litreRef: 25000});
      var lose = true;
      respond = (request) {
        final response = central(request);
        if (request.method == 'PUT' && lose) {
          lose = false;
          throw http.ClientException('respuesta perdida');
        }
        return response;
      };
      final first = await sender.run(access());
      expect(first.retried, 1);
      await store.sendNow(callId);
      final second = await sender.run(access());
      expect(second.received, 1);
      final puts = requests.where((r) => r.method == 'PUT').toList();
      expect(puts, hasLength(2));
      expect(puts[0].body, puts[1].body);
      expect(accepted[callId]!['last_sequence'], 1);
      expect(
        (await store.op(op.operationId))!.sendStatus,
        JointPurchaseOpStatus.received,
      );
    },
  );

  test(
    'STALE_SEQUENCE: la operación queda SUPERSEDED y se adopta lo del servidor',
    () async {
      accepted[callId] = participationJson(
        lines: {kiloRef: 9000},
        lastSequence: 4,
      );
      // El teléfono no lo sabía (p. ej. restauró un respaldo viejo).
      final op = await confirm({litreRef: 25000});
      expect(op.sequence, 1);
      final report = await sender.run(access());
      expect(report.superseded, 1);
      final stored = (await store.op(op.operationId))!;
      expect(stored.sendStatus, JointPurchaseOpStatus.superseded);
      expect(stored.lastCode, 'STALE_SEQUENCE');
      final call = (await store.call(callId))!;
      expect(call.serverParticipation!.lines, {kiloRef: 9000});
      expect(call.serverParticipation!.lastSequence, 4);
      // La siguiente parte de la del servidor.
      expect((await confirm({litreRef: 1000})).sequence, 5);
    },
  );

  test(
    'CALL_NOT_OPEN con DEADLINE_PASSED → OUT_OF_TIME; nunca se da por aceptada',
    () async {
      final op = await confirm({litreRef: 25000});
      respond = (request) => request.method == 'GET'
          ? central(request)
          : jsonResponse({
              'errorCode': 'CALL_NOT_OPEN',
              'reason': 'DEADLINE_PASSED',
            }, 409);
      final report = await sender.run(access());
      expect(report.outOfTime, 1);
      final stored = (await store.op(op.operationId))!;
      expect(stored.sendStatus, JointPurchaseOpStatus.outOfTime);
      expect(stored.isTerminal, isTrue);
      expect((await store.call(callId))!.serverParticipation, isNull);
      // Terminal: «Enviar ahora» no lo reenvía.
      await store.sendNow(callId);
      requests.clear();
      await sender.run(access(), includePaused: true);
      expect(calls().where((c) => c.startsWith('PUT')), isEmpty);
    },
  );

  test(
    'CALL_NOT_OPEN CLOSED/CANCELLED → REJECTED y la copia local toma el estado',
    () async {
      for (final reason in ['CLOSED', 'CANCELLED']) {
        await seedCalls(store, memberA, [callJson()]);
        final op = await confirm({litreRef: 1000 + reason.length});
        respond = (request) => request.method == 'GET'
            ? jsonResponse(listJson(const []), 200)
            : jsonResponse({
                'errorCode': 'CALL_NOT_OPEN',
                'reason': reason,
              }, 409);
        await sender.run(access());
        final stored = (await store.op(op.operationId))!;
        expect(stored.sendStatus, JointPurchaseOpStatus.rejected);
        expect(stored.lastCode, 'CALL_$reason');
        // Ausente de la lista pero con operaciones: se conserva.
        expect((await store.call(callId))!.status, reason);
      }
    },
  );

  test('códigos terminales del contrato → REJECTED sin reintento', () async {
    for (final (code, status) in [
      ('OPERATION_ID_REUSED', 409),
      ('CONSENT_REQUIRED', 409),
      ('PRODUCT_NOT_IN_CALL', 422),
      ('QUANTITY_INVALID', 422),
      ('PAYLOAD_INVALID', 400),
      ('CALL_NOT_FOUND', 404),
    ]) {
      final op = await confirm({litreRef: 1000 + code.length + status});
      respond = (request) => request.method == 'GET'
          ? central(request)
          : jsonResponse({'errorCode': code}, status);
      await sender.run(access());
      final stored = (await store.op(op.operationId))!;
      expect(stored.sendStatus, JointPurchaseOpStatus.rejected, reason: code);
      expect(stored.lastCode, code);
      expect(stored.nextAttemptAt, isNull);
    }
  });

  test(
    '401: AUTH_PAUSED, el ciclo se detiene y sólo se reanuda a pedido',
    () async {
      final op = await confirm({litreRef: 25000});
      respond = (_) => jsonResponse({'errorCode': 'UNAUTHORIZED'}, 401);
      final report = await sender.run(access());
      expect(report.authFailed, isTrue);
      expect(calls(), ['PUT /$callId/participation']);
      expect(
        (await store.op(op.operationId))!.sendStatus,
        JointPurchaseOpStatus.authPaused,
      );

      respond = central;
      requests.clear();
      await sender.run(access(), forceList: true);
      expect(calls(), ['GET ']);
      final resumed = await sender.run(access(), includePaused: true);
      expect(resumed.received, 1);
    },
  );

  test(
    'otra cuenta en sesión: no se envía ni se consulta nada (E2-D16)',
    () async {
      await confirm({litreRef: 25000});
      final report = await sender.run(access(memberB), includePaused: true);
      expect(report.ownerMismatch, isTrue);
      expect(requests, isEmpty);
    },
  );

  test(
    'operaciones de un titular anterior no salen con la cuenta del actual',
    () async {
      await confirm({litreRef: 25000});
      final rows = await (await fixture.database.database).query(
        JointPurchaseStore.opsTable,
      );
      // Cambia el titular: B ahora es el activo (mismo tenant).
      final db = await fixture.database.database;
      final current = (await db.query(
        'owner_bindings',
        where: 'ended_at IS NULL',
      )).single;
      await db.update(
        'owner_bindings',
        {'ended_at': '2026-11-11T18:30:00.000Z', 'end_reason': 'OWNER_CHANGED'},
        where: 'id=?',
        whereArgs: [current['id']],
      );
      await db.insert('owner_bindings', {
        'person_id': current['person_id'],
        'member_id': memberB.memberId,
        'tenant_id': memberB.tenantId,
        'owner_role': current['owner_role'],
        'bound_at': '2026-11-11T18:30:00.000Z',
      });
      final report = await sender.run(access(memberB), includePaused: true);
      expect(report.ownerMismatch, isFalse);
      expect(calls().where((c) => !c.startsWith('GET')), isEmpty);
      expect(
        (await store.op(rows.single['operation_id']! as String))!.sendStatus,
        JointPurchaseOpStatus.pendingSend,
      );
    },
  );

  test(
    'una operación vieja aceptada tarde nunca pisa lo aceptado más nuevo',
    () async {
      await seedCalls(store, memberA, [
        callJson(
          participation: participationJson(
            lines: {litreRef: 40000},
            lastSequence: 5,
          ),
        ),
      ]);
      // Operación vieja (p. ej. de un respaldo restaurado) aún pendiente.
      final db = await fixture.database.database;
      const oldId = '9d1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';
      await db.insert(JointPurchaseStore.opsTable, {
        'operation_id': oldId,
        'call_id': callId,
        'tenant_id': memberA.tenantId,
        'member_id': memberA.memberId,
        'sequence': 3,
        'kind': 'CONFIRM',
        'lines_json': jsonEncode([
          {'product_ref': litreRef, 'quantity_base': '10000'},
        ]),
        'consent_version': 'CONV-1',
        'consent_accepted_at': '2026-11-10T00:00:00.000Z',
        'send_status': JointPurchaseOpStatus.pendingSend,
        'attempts': 1,
        'created_at': '2026-11-10T00:00:00.000Z',
        'updated_at': '2026-11-10T00:00:00.000Z',
      });
      // El servidor repite su respuesta de entonces (mismo operation_id).
      respond = (request) => request.method == 'GET'
          ? jsonResponse(
              listJson([
                callJson(
                  participation: participationJson(
                    lines: {litreRef: 40000},
                    lastSequence: 5,
                  ),
                ),
              ]),
              200,
            )
          : jsonResponse({
              'outcome': 'ACCEPTED',
              'participation': participationJson(
                lines: {litreRef: 10000},
                lastSequence: 3,
              ),
            }, 200);
      await sender.run(access());
      expect(
        (await store.op(oldId))!.sendStatus,
        JointPurchaseOpStatus.received,
      );
      final call = (await store.call(callId))!;
      expect(call.serverParticipation!.lines, {litreRef: 40000});
      expect(call.serverParticipation!.lastSequence, 5);
    },
  );

  test(
    'lista con una clave desconocida: se rechaza entera y no se guarda nada',
    () async {
      await store.markSeen(callId);
      respond = (_) => jsonResponse(
        listJson([
          callJson(name: 'Cambiada'),
          callJson(id: otherCallId, extra: const {'other_participants': 3}),
        ]),
        200,
      );
      final report = await sender.run(access(), forceList: true);
      expect(report.listUnavailable, isTrue);
      expect(report.listed, isFalse);
      expect((await store.call(callId))!.name, 'Compra conjunta de herbicida');
      expect(await store.call(otherCallId), isNull);
    },
  );

  test(
    'respuesta ACCEPTED con forma inválida: sigue pendiente, se reintenta',
    () async {
      final op = await confirm({litreRef: 25000});
      respond = (request) => request.method == 'GET'
          ? central(request)
          : jsonResponse({
              'outcome': 'ACCEPTED',
              'participation': participationJson(),
              'total_requested': '99000',
            }, 200);
      final report = await sender.run(access());
      expect(report.retried, 1);
      final stored = (await store.op(op.operationId))!;
      expect(stored.sendStatus, JointPurchaseOpStatus.pendingSend);
      expect(stored.lastCode, 'INVALID_RESPONSE');
    },
  );

  test('las lecturas automáticas de la lista se espacian; «Actualizar» lee siempre', () async {
    await sender.run(access());
    expect(calls(), ['GET ']);
    requests.clear();
    await sender.run(access());
    expect(requests, isEmpty);
    await sender.run(access(), forceList: true);
    expect(calls(), ['GET ']);
    now = now.add(const Duration(minutes: 11));
    requests.clear();
    await sender.run(access());
    expect(calls(), ['GET ']);
  });

  test('sin dirección del sindicato: ninguna lectura ni llamada', () async {
    final offline = JointPurchaseSender(
      store: store,
      owners: fixture.owners,
      api: () => throw const AuthApiException(AuthApiErrorKind.configuration),
    );
    await confirm({litreRef: 25000});
    final report = await offline.run(access(), forceList: true);
    expect(report.apiUnavailable, isTrue);
    expect(report.changed, isFalse);
  });

  test(
    'la ruta del agricultor está en la lista cerrada y sólo con UUID v4',
    () {
      expect(config.endpoint(_base).path, _base);
      expect(
        config.endpoint('$_base/$callId/participation').path,
        '$_base/$callId/participation',
      );
      expect(
        config.endpoint('$_base/$callId/participation/withdraw').path,
        '$_base/$callId/participation/withdraw',
      );
      for (final bad in [
        '$_base/$callId',
        '$_base/$callId/participants',
        '$_base/${callId.toUpperCase()}/participation',
        '$_base/$campaignRef/participation/withdraw/x',
        '$_base/../backups',
      ]) {
        expect(
          () => config.endpoint(bad),
          throwsA(isA<AuthApiException>()),
          reason: bad,
        );
      }
    },
  );

  // --- E2 §10.1 y §10.2: CONV-1 heredado e historial ----------------------

  test('una confirmación guardada con CONV-1 antes de actualizar se envía como CONV-1', () async {
    final db = await fixture.database.database;
    const legacyId = '9a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';
    await db.insert(JointPurchaseStore.opsTable, {
      'operation_id': legacyId,
      'call_id': callId,
      'tenant_id': memberA.tenantId,
      'member_id': memberA.memberId,
      'sequence': 1,
      'kind': 'CONFIRM',
      'lines_json': jsonEncode([
        {'product_ref': litreRef, 'quantity_base': '10000'},
      ]),
      'consent_version': 'CONV-1',
      'consent_accepted_at': '2026-11-10T00:00:00.000Z',
      'send_status': JointPurchaseOpStatus.pendingSend,
      'attempts': 0,
      'created_at': '2026-11-10T00:00:00.000Z',
      'updated_at': '2026-11-10T00:00:00.000Z',
    });
    final report = await sender.run(access());
    expect(report.received, 1);
    final body = jsonDecode(requests.first.body) as Map<String, dynamic>;
    expect(body['consent'], {
      'version': 'CONV-1',
      'accepted_at': '2026-11-10T00:00:00.000Z',
    });
    expect(
      (await store.op(legacyId))!.sendStatus,
      JointPurchaseOpStatus.received,
    );
    expect((await store.op(legacyId))!.consentVersion, 'CONV-1');
  });

  test('la lista guarda history.older_count del titular', () async {
    respond = (_) => jsonResponse(listJson([callJson()], olderCount: 2), 200);
    final report = await sender.run(access(), forceList: true);
    expect(report.listed, isTrue);
    final overview = await store.overviewForActiveOwner();
    expect(overview.olderCount, 2);
    expect(overview.missingOlder, 2);
  });

  const oldId = 'fb1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';
  const olderId = '0b1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';
  const cursor = 'WyIyMDI2LTAzLTAxVDEyOjAwOjAwLjAwMFoiLCJmYiJd';

  test('historial paginado: primera página con cursor, «Ver más» con before; se guarda sin borrar nada', () async {
    respond = (request) {
      expect(request.method, 'GET');
      expect(request.url.path, '$_base/history');
      return request.url.queryParameters['before'] == null
          ? jsonResponse(
              historyJson([oldCallJson(oldId)], nextCursor: cursor),
              200,
            )
          : jsonResponse(
              historyJson([
                oldCallJson(
                  olderId,
                  status: 'CANCELLED',
                  finishedAt: '2026-01-15T12:00:00.000Z',
                ),
              ]),
              200,
            );
    };
    final first = await sender.fetchHistory(access());
    expect(first.outcome, JointPurchaseHistoryOutcome.saved);
    expect(first.saved, 1);
    expect(first.nextCursor, cursor);
    expect(requests.single.url.queryParameters, {'limit': '20'});
    expect(requests.single.headers['authorization'], 'Bearer token-sintetico');

    final second = await sender.fetchHistory(access(), before: cursor);
    expect(second.outcome, JointPurchaseHistoryOutcome.saved);
    expect(second.nextCursor, isNull);
    expect(requests.last.url.queryParameters, {
      'before': cursor,
      'limit': '20',
    });

    final overview = await store.overviewForActiveOwner();
    // La abierta de setUp sigue; las dos anteriores se añadieron.
    expect(overview.recent.map((c) => c.callId), [callId]);
    expect(overview.older.map((c) => c.callId), [oldId, olderId]);
    // Pedir el historial no envía operaciones ni lee la lista.
    expect(calls(), ['GET /history', 'GET /history']);
  });

  test('historial sin conexión, con error o con una respuesta inválida: no guarda nada', () async {
    Future<JointPurchaseHistoryOutcome> outcome(
      http.Response Function(http.Request) server, {
      String? before,
    }) async {
      respond = server;
      return (await sender.fetchHistory(access(), before: before)).outcome;
    }

    expect(
      await outcome((_) => throw http.ClientException('sin red')),
      JointPurchaseHistoryOutcome.offline,
    );
    expect(
      await outcome((_) => jsonResponse({'errorCode': 'UNAVAILABLE'}, 503)),
      JointPurchaseHistoryOutcome.unavailable,
    );
    expect(
      await outcome(
        (_) => jsonResponse({'errorCode': 'PAYLOAD_INVALID'}, 400),
        before: cursor,
      ),
      JointPurchaseHistoryOutcome.invalidCursor,
    );
    expect(
      await outcome((_) => jsonResponse({'errorCode': 'AUTH_REQUIRED'}, 401)),
      JointPurchaseHistoryOutcome.authFailed,
    );
    // Una abierta en el historial: la página entera se rechaza.
    expect(
      await outcome(
        (_) => jsonResponse(
          historyJson([oldCallJson(oldId), callJson(id: otherCallId)]),
          200,
        ),
      ),
      JointPurchaseHistoryOutcome.unavailable,
    );
    // Más convocatorias que las pedidas.
    expect(
      await outcome(
        (_) => jsonResponse(
          historyJson([
            for (var i = 0; i < 21; i++)
              oldCallJson(
                '${(i + 10).toRadixString(16).padLeft(2, '0')}1b2c3d-'
                '4e5f-4a6b-8c7d-9e0f1a2b3c4d',
              ),
          ]),
          200,
        ),
      ),
      JointPurchaseHistoryOutcome.unavailable,
    );
    final requestsSoFar = requests.length;
    // Un cursor que el sindicato no pudo emitir no sale del teléfono.
    expect(
      await outcome((_) => fail('no debe pedir'), before: 'a b'),
      JointPurchaseHistoryOutcome.invalidCursor,
    );
    expect(requests.length, requestsSoFar);
    expect(await store.call(oldId), isNull);
    expect((await store.overviewForActiveOwner()).older, isEmpty);
    expect(await store.call(callId), isNotNull);
  });

  test(
    'historial: otra cuenta en sesión o sin servidor configurado no pide nada',
    () async {
      respond = (_) => fail('no debe pedir');
      expect(
        (await sender.fetchHistory(access(memberB))).outcome,
        JointPurchaseHistoryOutcome.ownerMismatch,
      );
      final offline = JointPurchaseSender(
        store: store,
        owners: fixture.owners,
        api: () => throw const AuthApiException(AuthApiErrorKind.configuration),
      );
      expect(
        (await offline.fetchHistory(access())).outcome,
        JointPurchaseHistoryOutcome.apiUnavailable,
      );
      expect(requests, isEmpty);
    },
  );

  test('la ruta del historial sólo admite before y limit válidos', () {
    expect(
      config.endpoint('$_base/history', query: {'limit': '20'}).toString(),
      'https://sindicato.example$_base/history?limit=20',
    );
    expect(
      config
          .endpoint('$_base/history', query: {'before': cursor, 'limit': '50'})
          .queryParameters,
      {'before': cursor, 'limit': '50'},
    );
    expect(config.endpoint('$_base/history').path, '$_base/history');
    for (final bad in <Map<String, String>>[
      {'limit': '0'},
      {'limit': '51'},
      {'limit': '020'},
      {'before': 'a b'},
      {'before': ''},
      {'cursor': cursor},
      {'limit': '20', 'member_id': 'x'},
    ]) {
      expect(
        () => config.endpoint('$_base/history', query: bad),
        throwsA(isA<AuthApiException>()),
        reason: '$bad',
      );
    }
    expect(
      () => config.endpoint('$_base/history/x'),
      throwsA(isA<AuthApiException>()),
    );
    expect(
      () => config.endpoint(_base, query: {'limit': '20'}),
      throwsA(isA<AuthApiException>()),
    );
  });
}
