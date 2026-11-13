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
const thirdCallId = '9b1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';

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
    final sequence = body['sequence'] as int;
    // E2 §10.6: decisión sobre el consentimiento, con orden propio.
    if (path.endsWith('/consent')) {
      final current = accepted[id];
      if (current == null) {
        return jsonResponse({'errorCode': 'PARTICIPATION_REQUIRED'}, 409);
      }
      final scopeSequence =
          (current['consent_scope'] as Map?)?['sequence'] as int? ?? 0;
      if (sequence <= scopeSequence) {
        return jsonResponse({
          'errorCode': 'STALE_SEQUENCE',
          'participation': current,
        }, 409);
      }
      final consent = body['consent'] as Map<String, dynamic>;
      accepted[id] = {
        ...current,
        'consent_scope': {
          'scope': body['scope'],
          'version': consent['version'],
          'decided_at': consent['decided_at'],
          'received_at': now.toIso8601String(),
          'sequence': sequence,
        },
      };
      final response = jsonResponse({
        'outcome': 'ACCEPTED',
        'participation': accepted[id],
      }, 200);
      seenOps[opId] = response;
      return response;
    }
    final last = accepted[id]?['last_sequence'] as int? ?? 0;
    if (sequence <= last) {
      return jsonResponse({
        'errorCode': 'STALE_SEQUENCE',
        'participation': accepted[id],
      }, 409);
    }
    final withdraw = path.endsWith('/withdraw');
    final keptScope = accepted[id]?['consent_scope'];
    // E4: el texto aceptado al participar tampoco se reescribe.
    final keptConsent = accepted[id]?['consent'];
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
    // Las cantidades nunca cambian el alcance (E2 §10.6).
    if (keptScope != null) {
      accepted[id] = {...accepted[id]!, 'consent_scope': keptScope};
    }
    if (keptConsent != null) {
      accepted[id] = {...accepted[id]!, 'consent': keptConsent};
    }
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
        'consent': {'version': 'CONV-4', 'accepted_at': now.toIso8601String()},
        'lines': [
          {'product_ref': litreRef, 'quantity_base': '25000'},
          {'product_ref': kiloRef, 'quantity_base': '4500'},
        ],
      });
      expect(requests.first.headers['authorization'], 'Bearer token-sintetico');
      // N7 y E4 §7.1: cada petición dice qué contrato lee el teléfono.
      expect(requests.first.headers['x-joint-purchase-contract'], '4');
      expect(requests.last.headers['x-joint-purchase-contract'], '4');
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

  test('E4 §7.2: ACCEPTED con forma inválida → RECEIVED sin adoptar nada ni reintentar; un 2xx que no es del sindicato se reintenta', () async {
    final op = await confirm({litreRef: 25000});
    respond = (request) => request.method == 'GET'
        ? central(request)
        : jsonResponse({
            'outcome': 'ACCEPTED',
            'participation': participationJson(),
            'total_requested': '99000',
          }, 200);
    final report = await sender.run(access());
    expect(report.received, 1);
    expect(report.retried, 0);
    final stored = (await store.op(op.operationId))!;
    expect(stored.sendStatus, JointPurchaseOpStatus.received);
    expect(stored.lastCode, JointPurchaseCodes.responseUnreadable);
    expect(stored.nextAttemptAt, isNull);
    // Nada de esa respuesta se guardó (ni el dato ajeno).
    expect((await store.call(callId))!.serverParticipation, isNull);
    // Un ciclo más no lo vuelve a enviar.
    requests.clear();
    now = now.add(const Duration(hours: 1));
    await sender.run(access());
    expect(calls().where((c) => !c.startsWith('GET')), isEmpty);

    // Otra versión del contrato en un 2xx: lo mismo.
    await seedCalls(store, memberA, [callJson(id: otherCallId)]);
    final other = await store.confirm(
      callId: otherCallId,
      lines: {litreRef: 1000},
      consentVersion: jointPurchaseConsentVersion,
      consentAcceptedAt: now,
    );
    respond = (request) => request.method == 'GET'
        ? central(request)
        : jsonResponse({
            'contractVersion': 5,
            'outcome': 'ACCEPTED',
            'participation': participationJson(),
          }, 200);
    await sender.run(access());
    expect(
      (await store.op(other.operationId))!.lastCode,
      JointPurchaseCodes.responseUnreadable,
    );

    // Un 2xx que no tiene forma de respuesta del sindicato (por ejemplo, la
    // página de un portal de acceso) puede ser pasajero: sigue pendiente.
    await seedCalls(store, memberA, [callJson(id: thirdCallId)]);
    final portal = await store.confirm(
      callId: thirdCallId,
      lines: {litreRef: 1000},
      consentVersion: jointPurchaseConsentVersion,
      consentAcceptedAt: now,
    );
    respond = (request) => request.method == 'GET'
        ? central(request)
        : http.Response('<html>Inicie sesión en la red</html>', 200);
    final retried = await sender.run(access());
    expect(retried.retried, 1);
    final kept = (await store.op(portal.operationId))!;
    expect(kept.sendStatus, JointPurchaseOpStatus.pendingSend);
    expect(kept.lastCode, 'INVALID_RESPONSE');
  });

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

  // --- E4 §4.2 y §7.2 (reescritas desde P-C, E2 §10.6) y N7 ---------------

  Future<JointPurchaseConsentOp?> decide(String scope) =>
      store.decideAccess(callId: callId, scope: scope, decidedAt: now);

  /// Una decisión anterior a E4 guardada en la cola v18/v19 por la
  /// aplicación anterior, todavía pendiente de envío.
  Future<String> insertLegacyDecision({
    required String scope,
    required int sequence,
    bool authorizeResponsible = false,
    String id = '5e1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d',
  }) async {
    await (await fixture.database.database).insert(
      JointPurchaseStore.consentOpsTable,
      {
        'operation_id': id,
        'call_id': callId,
        'tenant_id': memberA.tenantId,
        'member_id': memberA.memberId,
        'sequence': sequence,
        'scope': scope,
        'consent_version': 'CONV-3',
        'decided_at': '2026-11-12T09:00:00.000Z',
        'send_status': JointPurchaseOpStatus.pendingSend,
        'attempts': 0,
        'created_at': '2026-11-12T09:00:00.000Z',
        'updated_at': '2026-11-12T09:00:00.000Z',
        'responsible_version': authorizeResponsible ? 1 : null,
        'authorize_responsible': authorizeResponsible ? 1 : 0,
      },
    );
    return id;
  }

  test('E4: modificar no lleva consentimiento; «Revisar» va aparte, después de las cantidades, con CONV-4', () async {
    // Una participación anterior a E4 en el sindicato.
    accepted[callId] = participationJson(
      consentVersion: 'CONV-3',
      consentScope: 'RESPONSIBLE_ONLY',
      consentScopeVersion: 'CONV-3',
    );
    await sender.run(access(), forceList: true);
    expect((await store.call(callId))!.needsAccessReview, isTrue);
    final modified = await store.confirm(
      callId: callId,
      lines: {litreRef: 30000},
      consentVersion: jointPurchaseConsentVersion,
      consentAcceptedAt: now,
    );
    expect(modified.consentVersion, isNull);
    final review = (await decide(JointPurchaseConsentScope.administration))!;
    requests.clear();
    final report = await sender.run(access());
    expect(report.received, 2);
    expect(calls(), [
      'PUT /$callId/participation',
      'POST /$callId/participation/consent',
      'GET ',
    ]);
    expect(
      (jsonDecode(requests.first.body) as Map).containsKey('consent'),
      isFalse,
    );
    expect(jsonDecode(requests[1].body), {
      'operation_id': review.operationId,
      'sequence': 1,
      'scope': 'ADMINISTRATION',
      'consent': {'version': 'CONV-4', 'decided_at': now.toIso8601String()},
    });
    expect(requests[1].headers['x-joint-purchase-contract'], '4');
    final call = (await store.call(callId))!;
    expect(call.serverParticipation!.consentScope, 'ADMINISTRATION');
    expect(call.serverParticipation!.lines, {litreRef: 30000});
    // El texto aceptado al participar no se reescribe.
    expect(call.serverParticipation!.consentVersion, 'CONV-3');
    expect(call.pendingConsentOp, isNull);
    expect(call.latestConsentOp!.sendStatus, JointPurchaseOpStatus.received);
    expect(call.needsAccessReview, isFalse);
  });

  test('E4: sin conexión la retirada queda pendiente y no se da por aplicada; con red sale igual', () async {
    await confirm({litreRef: 25000});
    await sender.run(access());
    expect(
      (await store.call(callId))!.serverParticipation!.consentScope,
      'ADMINISTRATION',
    );
    final retract = (await decide(JointPurchaseConsentScope.totalsOnly))!;
    respond = (_) => throw http.ClientException('sin red');
    final report = await sender.run(access(), forceList: true);
    expect(report.retried, 1);
    expect(report.listProblem, JointPurchaseListProblem.offline);
    final call = (await store.call(callId))!;
    // Lo vigente sigue siendo lo que el sindicato aceptó.
    expect(call.serverParticipation!.consentScope, 'ADMINISTRATION');
    expect(call.pendingConsentOp!.operationId, retract.operationId);
    // Con red, el mismo operation_id y la misma sequence.
    respond = central;
    now = now.add(const Duration(hours: 1));
    requests.clear();
    await sender.run(access());
    expect(
      jsonDecode(requests.first.body)['operation_id'],
      retract.operationId,
    );
    expect(jsonDecode(requests.first.body)['sequence'], 1);
    final after = (await store.call(callId))!;
    expect(after.serverParticipation!.consentScope, 'TOTALS_ONLY');
    // La participación y sus cantidades siguen.
    expect(after.serverParticipation!.isActive, isTrue);
    expect(after.serverParticipation!.lines, {litreRef: 25000});
  });

  test('E4: la primera participación aún sin aceptar: la decisión espera mientras la confirmación siga por enviar', () async {
    await confirm({litreRef: 25000});
    await decide(JointPurchaseConsentScope.totalsOnly);
    var failConfirm = true;
    respond = (request) {
      if (failConfirm && request.method == 'PUT') {
        return jsonResponse({'errorCode': 'TEMPORARILY_UNAVAILABLE'}, 503);
      }
      return central(request);
    };
    await sender.run(access());
    final pending = (await store.consentOps(callId)).single;
    expect(pending.sendStatus, JointPurchaseOpStatus.pendingSend);
    expect(pending.lastCode, 'PARTICIPATION_REQUIRED');
    failConfirm = false;
    now = now.add(const Duration(hours: 1));
    await sender.run(access());
    expect(
      (await store.call(callId))!.serverParticipation!.consentScope,
      'TOTALS_ONLY',
    );
  });

  test('E4: PARTICIPATION_REQUIRED sin confirmación por enviar → REJECTED, sin reintento infinito', () async {
    await confirm({litreRef: 25000});
    await decide(JointPurchaseConsentScope.totalsOnly);
    // La confirmación termina rechazada (por ejemplo, fuera de plazo): el
    // sindicato nunca tendrá la participación.
    respond = (request) => switch (request.method) {
      'PUT' => jsonResponse({
        'errorCode': 'CALL_NOT_OPEN',
        'reason': 'DEADLINE_PASSED',
      }, 409),
      'POST' => jsonResponse({'errorCode': 'PARTICIPATION_REQUIRED'}, 409),
      _ => central(request),
    };
    final report = await sender.run(access());
    expect(report.outOfTime, 1);
    expect(report.rejected, 1);
    final decision = (await store.consentOps(callId)).single;
    expect(decision.sendStatus, JointPurchaseOpStatus.rejected);
    expect(decision.lastCode, 'PARTICIPATION_REQUIRED');
    expect(decision.nextAttemptAt, isNull);
    requests.clear();
    now = now.add(const Duration(days: 1));
    await sender.run(access(), includePaused: true);
    expect(calls().where((c) => c.startsWith('POST')), isEmpty);
  });

  test('E4 §7.2: CONSENT_VERSION_RETIRED, APP_UPDATE_REQUIRED y WIDENING_NOT_ALLOWED son definitivos y no se borran', () async {
    // Decisiones: una ampliación anterior guardada por la versión anterior
    // (sale tal cual) y decisiones nuevas rechazadas por el sindicato.
    accepted[callId] = participationJson(
      consentVersion: 'CONV-3',
      consentScope: 'RESPONSIBLE_ONLY',
      consentScopeVersion: 'CONV-3',
    );
    await sender.run(access(), forceList: true);
    final cases = [
      (
        'CONSENT_VERSION_RETIRED',
        <String, Object?>{'errorCode': 'CONSENT_VERSION_RETIRED'},
      ),
      (
        'APP_UPDATE_REQUIRED',
        <String, Object?>{'errorCode': 'APP_UPDATE_REQUIRED'},
      ),
      (
        'WIDENING_NOT_ALLOWED',
        <String, Object?>{
          'errorCode': 'WIDENING_NOT_ALLOWED',
          'status': 'CANCELLED',
        },
      ),
    ];
    var sequence = 1;
    for (final (code, body) in cases) {
      final id = await insertLegacyDecision(
        scope: 'COLLABORATORS',
        sequence: sequence++,
        authorizeResponsible: true,
        id: '5e1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4${sequence.toRadixString(16)}',
      );
      respond = (request) =>
          request.method == 'POST' ? jsonResponse(body, 409) : central(request);
      requests.clear();
      final report = await sender.run(access());
      expect(report.rejected, 1, reason: code);
      // Salió tal como se guardó.
      expect(
        jsonDecode(requests.first.body),
        containsPair('authorize_responsible', true),
        reason: code,
      );
      final stored = (await store.consentOp(id))!;
      expect(stored.sendStatus, JointPurchaseOpStatus.rejected, reason: code);
      expect(stored.lastCode, code);
      expect(stored.nextAttemptAt, isNull);
      // Ningún ciclo posterior lo reenvía.
      requests.clear();
      now = now.add(const Duration(hours: 1));
      await sender.run(access(), includePaused: true);
      expect(calls().where((c) => c.startsWith('POST')), isEmpty, reason: code);
    }
    // Las tres siguen en el teléfono; lo aplicado no cambió.
    expect((await store.consentOps(callId)).length, 3);
    expect(
      (await store.call(callId))!.serverParticipation!.consentScope,
      'RESPONSIBLE_ONLY',
    );

    // Y en la cola de cantidades: APP_UPDATE_REQUIRED también es definitivo.
    final op = await store.confirm(callId: callId, lines: {litreRef: 7000});
    respond = (request) => request.method == 'PUT'
        ? jsonResponse({'errorCode': 'APP_UPDATE_REQUIRED'}, 409)
        : central(request);
    await sender.run(access());
    final rejected = (await store.op(op.operationId))!;
    expect(rejected.sendStatus, JointPurchaseOpStatus.rejected);
    expect(rejected.lastCode, 'APP_UPDATE_REQUIRED');
    expect(rejected.nextAttemptAt, isNull);
  });

  test('E4 §7.2: una confirmación pendiente con CONV-3 se envía tal cual y el sindicato la acepta con su alcance anterior', () async {
    final db = await fixture.database.database;
    const legacyId = '9c1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';
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
      'consent_version': 'CONV-3',
      'consent_accepted_at': '2026-11-12T00:00:00.000Z',
      'responsible_version': 1,
      'send_status': JointPurchaseOpStatus.pendingSend,
      'attempts': 0,
      'created_at': '2026-11-12T00:00:00.000Z',
      'updated_at': '2026-11-12T00:00:00.000Z',
    });
    final pendingCall = (await store.call(callId))!;
    // Mientras no llega, se sabe que regirá un alcance anterior.
    expect(pendingCall.pendingInitialScope, 'RESPONSIBLE_ONLY');
    expect(pendingCall.needsAccessReview, isTrue);
    respond = (request) {
      if (request.method == 'PUT') {
        accepted[callId] = participationJson(
          lines: {litreRef: 10000},
          consentVersion: 'CONV-3',
          consentScope: 'RESPONSIBLE_ONLY',
          consentScopeVersion: 'CONV-3',
        );
        return jsonResponse({
          'outcome': 'ACCEPTED',
          'participation': accepted[callId],
        }, 200);
      }
      return central(request);
    };
    final report = await sender.run(access());
    expect(report.received, 1);
    expect(jsonDecode(requests.first.body), {
      'operation_id': legacyId,
      'sequence': 1,
      'consent': {
        'version': 'CONV-3',
        'accepted_at': '2026-11-12T00:00:00.000Z',
      },
      'responsible_version': 1,
      'lines': [
        {'product_ref': litreRef, 'quantity_base': '10000'},
      ],
    });
    final call = (await store.call(callId))!;
    expect(call.serverParticipation!.consentScope, 'RESPONSIBLE_ONLY');
    expect(call.needsAccessReview, isTrue);
  });

  test('E4: una decisión atrasada no revierte la posterior (STALE_SEQUENCE adopta la vigente)', () async {
    await confirm({litreRef: 25000});
    await sender.run(access());
    final retract = (await decide(JointPurchaseConsentScope.totalsOnly))!;
    // Otro teléfono del mismo titular ya volvió a autorizar con orden 3.
    accepted[callId] = {
      ...accepted[callId]!,
      'consent_scope': {
        'scope': 'ADMINISTRATION',
        'version': 'CONV-4',
        'decided_at': now.toIso8601String(),
        'received_at': now.toIso8601String(),
        'sequence': 3,
      },
    };
    final report = await sender.run(access());
    expect(report.superseded, 1);
    expect(
      (await store.consentOp(retract.operationId))!.sendStatus,
      JointPurchaseOpStatus.superseded,
    );
    final call = (await store.call(callId))!;
    expect(call.serverParticipation!.consentScope, 'ADMINISTRATION');
    expect(call.serverParticipation!.consentScopeSequence, 3);
  });

  test(
    'E4: un envío repetido devuelve lo mismo y no duplica la decisión',
    () async {
      await confirm({litreRef: 25000});
      await sender.run(access());
      final retract = (await decide(JointPurchaseConsentScope.totalsOnly))!;
      // La primera respuesta se pierde (plazo); el reenvío lleva el mismo
      // operation_id y el servidor repite su respuesta.
      var lose = true;
      respond = (request) {
        final response = central(request);
        if (lose && request.method == 'POST') {
          lose = false;
          throw http.ClientException('respuesta perdida');
        }
        return response;
      };
      await sender.run(access());
      expect(
        (await store.consentOp(retract.operationId))!.sendStatus,
        JointPurchaseOpStatus.pendingSend,
      );
      now = now.add(const Duration(hours: 1));
      requests.clear();
      await sender.run(access());
      final posts = [
        for (final r in requests)
          if (r.method == 'POST') jsonDecode(r.body) as Map<String, dynamic>,
      ];
      expect(posts.single['operation_id'], retract.operationId);
      expect(posts.single['sequence'], 1);
      expect(
        (await store.consentOp(retract.operationId))!.sendStatus,
        JointPurchaseOpStatus.received,
      );
      expect(
        (await store.call(callId))!.serverParticipation!.consentScope,
        'TOTALS_ONLY',
      );
      expect((await store.consentOps(callId)).length, 1);
    },
  );

  test('E4: una respuesta de cantidades con un alcance más viejo no pisa la decisión aplicada', () async {
    await confirm({litreRef: 25000});
    await sender.run(access());
    await decide(JointPurchaseConsentScope.totalsOnly);
    await sender.run(access());
    final modified = await store.confirm(
      callId: callId,
      lines: {litreRef: 40000},
    );
    // El servidor responde con cantidades nuevas pero un alcance anterior.
    respond = (request) => jsonResponse({
      'outcome': 'ACCEPTED',
      'participation': participationJson(
        lastSequence: modified.sequence,
        lines: {litreRef: 40000},
        consentScope: 'ADMINISTRATION',
      ),
    }, 200);
    await sender.run(access());
    final call = (await store.call(callId))!;
    expect(call.serverParticipation!.lines, {litreRef: 40000});
    expect(call.serverParticipation!.consentScope, 'TOTALS_ONLY');
  });

  test('N7: incompatibilidad de versión, sin conexión y fallo temporal se distinguen', () async {
    respond = (_) => jsonResponse({
      ...listJson(const []),
      'contractVersion': 1,
      'consent': {'version': 'CONV-1', 'text': 'texto anterior'},
    }, 200);
    var report = await sender.run(access(), forceList: true);
    expect(report.listProblem, JointPurchaseListProblem.incompatibleVersion);
    respond = (_) => jsonResponse(listJson(const []), 503);
    report = await sender.run(access(), forceList: true);
    expect(report.listProblem, JointPurchaseListProblem.temporary);
    respond = (_) => throw http.ClientException('sin red');
    report = await sender.run(access(), forceList: true);
    expect(report.listProblem, JointPurchaseListProblem.offline);
    // Nada de lo guardado se borró.
    expect(await store.call(callId), isNotNull);
  });
}
