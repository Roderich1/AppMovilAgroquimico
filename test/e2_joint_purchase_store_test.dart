// Contrato E2 §5: copia local de las convocatorias y cola propia de
// participación. Secuencia por convocatoria y titular, la operación pendiente
// anterior queda SUPERSEDED en la misma transacción, doble toque = una sola
// pendiente, terminal y reintentable explícitos, «Enviar ahora» nunca vuelve
// terminal un reintento. Datos sintéticos; sin red.
import 'dart:math';

import 'package:agroquimicos/data/agro_repository.dart'
    show BusinessRuleException;
import 'package:agroquimicos/data/sync/joint_purchase_store.dart';
import 'package:agroquimicos/domain/sync/joint_purchase_call_view.dart';
import 'package:agroquimicos/domain/sync/operation_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/e2_joint_purchase_fixtures.dart';
import 'support/f04_mode_fixtures.dart';
import 'support/f05_sync_fixtures.dart';

void main() {
  sqfliteFfiInit();

  late SyncFixture fixture;
  late JointPurchaseStore store;
  late DateTime now;

  setUp(() async {
    now = DateTime.utc(2026, 11, 11, 18, 20);
    fixture = await seedSyncFixture();
    store = JointPurchaseStore(
      fixture.database,
      clock: () => now,
      random: Random(3),
    );
    await seedCalls(store, memberA, [callJson()]);
  });

  Future<JointPurchaseOp> confirm(Map<String, int> lines) => store.confirm(
    callId: callId,
    lines: lines,
    consentVersion: jointPurchaseConsentVersion,
    consentAcceptedAt: now,
  );

  test(
    'la convocatoria guardada es del titular activo y nace «Nueva»',
    () async {
      final call = (await store.call(callId))!;
      expect(call.isNew, isTrue);
      expect(call.products.map((p) => p.unit), ['L', 'KG']);
      expect(call.serverParticipation, isNull);
      expect(call.latestOp, isNull);
      expect((await store.unseenNotice())!.callId, callId);

      expect(await store.markSeen(callId), isTrue);
      expect(await store.markSeen(callId), isFalse);
      expect((await store.call(callId))!.isNew, isFalse);
      expect(await store.unseenNotice(), isNull);
    },
  );

  test(
    'reemplazar la lista conserva «visto» y quita lo ausente sin operaciones',
    () async {
      await store.markSeen(callId);
      await seedCalls(store, memberA, [
        callJson(name: 'Nombre nuevo'),
        callJson(id: otherCallId),
      ]);
      expect((await store.call(callId))!.seenAt, isNotNull);
      expect((await store.call(callId))!.name, 'Nombre nuevo');
      expect((await store.call(otherCallId))!.isNew, isTrue);

      // Con una operación local, una convocatoria ausente se conserva.
      await confirm({litreRef: 1000});
      await seedCalls(store, memberA, const []);
      expect(await store.call(callId), isNotNull);
      expect(await store.call(otherCallId), isNull);
    },
  );

  test(
    'confirmar: PENDING_SEND con UUID v4, sequence 1, consentimiento CONV-2',
    () async {
      final op = await confirm({litreRef: 25000, kiloRef: 4500});
      expect(uuidV4Lowercase.hasMatch(op.operationId), isTrue);
      expect(op.sequence, 1);
      expect(op.sendStatus, JointPurchaseOpStatus.pendingSend);
      expect(op.consentVersion, 'CONV-2');
      expect(op.consentAcceptedAt, now.toIso8601String());
      expect(op.wireLines, [
        {'product_ref': litreRef, 'quantity_base': '25000'},
        {'product_ref': kiloRef, 'quantity_base': '4500'},
      ]);
      expect(op.scope, memberA);
      expect(op.isTerminal, isFalse);
    },
  );

  test(
    'modificar: sequence mayor y la pendiente anterior queda SUPERSEDED',
    () async {
      final first = await confirm({litreRef: 25000});
      final second = await confirm({litreRef: 30000});
      expect(second.sequence, 2);
      final ops = await store.ops(callId);
      expect(ops.map((op) => op.sendStatus), [
        JointPurchaseOpStatus.superseded,
        JointPurchaseOpStatus.pendingSend,
      ]);
      expect(ops.first.operationId, first.operationId);
      final sendable = await store.sendable(memberA, includePaused: true);
      expect(sendable.single.operationId, second.operationId);
    },
  );

  test('la secuencia parte de la última aceptada por el servidor', () async {
    await seedCalls(store, memberA, [
      callJson(participation: participationJson(lastSequence: 7)),
    ]);
    final op = await confirm({litreRef: 1000});
    expect(op.sequence, 8);
  });

  test(
    'doble toque con el mismo contenido: una sola operación pendiente',
    () async {
      final results = await Future.wait([
        confirm({litreRef: 25000}),
        confirm({litreRef: 25000}),
      ]);
      expect(results[0].operationId, results[1].operationId);
      final ops = await store.ops(callId);
      expect(ops, hasLength(1));
    },
  );

  test('la sustitución es atómica: si la inserción falla, la pendiente sigue', () async {
    final first = await confirm({litreRef: 25000});
    // Fuerza un choque UNIQUE(call_id, member_id, sequence) para la próxima.
    final db = await fixture.database.database;
    await db.insert(JointPurchaseStore.opsTable, {
      'operation_id': '9c1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d',
      'call_id': callId,
      'tenant_id': memberA.tenantId,
      'member_id': memberB.memberId,
      'sequence': 1,
      'kind': 'WITHDRAW',
      'send_status': JointPurchaseOpStatus.received,
      'created_at': '2026-11-11T00:00:00.000Z',
      'updated_at': '2026-11-11T00:00:00.000Z',
    });
    await db.execute(
      'CREATE TRIGGER test_fail BEFORE INSERT ON ${JointPurchaseStore.opsTable} '
      "WHEN NEW.sequence = 2 BEGIN SELECT RAISE(ABORT, 'falla'); END",
    );
    await expectLater(confirm({litreRef: 30000}), throwsA(anything));
    final ops = await store.ops(callId);
    final mine = ops.where((op) => op.memberId == memberA.memberId).toList();
    expect(mine.single.operationId, first.operationId);
    expect(mine.single.sendStatus, JointPurchaseOpStatus.pendingSend);
  });

  test(
    'confirmar exige productos de la convocatoria y cantidades > 0',
    () async {
      await expectLater(
        confirm(const {}),
        throwsA(isA<BusinessRuleException>()),
      );
      await expectLater(
        confirm({otherLitreRef: 1000}),
        throwsA(isA<BusinessRuleException>()),
      );
      await expectLater(
        confirm({litreRef: 0}),
        throwsA(isA<BusinessRuleException>()),
      );
      await expectLater(
        store.confirm(
          callId: callId,
          lines: {litreRef: 1000},
          consentVersion: 'CONV-0',
          consentAcceptedAt: now,
        ),
        throwsA(isA<BusinessRuleException>()),
      );
      expect(await store.ops(callId), isEmpty);
    },
  );

  test('una convocatoria no abierta no admite cambios locales', () async {
    await seedCalls(store, memberA, [callJson(status: 'CLOSED')]);
    await expectLater(
      confirm({litreRef: 1000}),
      throwsA(isA<BusinessRuleException>()),
    );
  });

  test('retirar lo que nunca salió sólo lo deja sin efecto; lo aceptado se retira con una operación', () async {
    await confirm({litreRef: 1000});
    expect(await store.withdraw(callId), isNull);
    expect(
      (await store.ops(callId)).single.sendStatus,
      JointPurchaseOpStatus.superseded,
    );
    await expectLater(
      store.withdraw(callId),
      throwsA(isA<BusinessRuleException>()),
    );

    await seedCalls(store, memberA, [
      callJson(participation: participationJson(lastSequence: 1)),
    ]);
    final withdraw = (await store.withdraw(callId))!;
    expect(withdraw.kind, JointPurchaseOpKind.withdraw);
    expect(withdraw.sequence, 2);
    expect(withdraw.lines, isEmpty);
    expect(withdraw.consentVersion, isNull);
  });

  test(
    'terminal y reintentable explícitos; «Enviar ahora» mantiene el reintento',
    () async {
      final op = await confirm({litreRef: 25000});
      final retryAt = now.add(const Duration(minutes: 5));
      await store.scheduleRetry(op, 'HTTP_503', retryAt);
      var stored = (await store.op(op.operationId))!;
      expect(stored.sendStatus, JointPurchaseOpStatus.pendingSend);
      expect(stored.isTerminal, isFalse);
      expect(stored.isRetryScheduled, isTrue);
      expect(stored.nextAttemptAt, retryAt.toIso8601String());
      expect(stored.attempts, 1);

      await store.sendNow(callId);
      stored = (await store.op(op.operationId))!;
      // Sigue reintentable y vence ya: nunca terminal.
      expect(stored.sendStatus, JointPurchaseOpStatus.pendingSend);
      expect(stored.isTerminal, isFalse);
      expect(stored.nextAttemptAt, now.toIso8601String());
      expect(stored.lastCode, 'HTTP_503');
      expect(
        (await store.sendable(
          memberA,
          includePaused: false,
        )).single.operationId,
        op.operationId,
      );
    },
  );

  test(
    '«Enviar ahora» devuelve lo pausado a la cola y no toca lo terminal',
    () async {
      final op = await confirm({litreRef: 25000});
      await store.markAuthPaused(op, 'AUTH_REQUIRED');
      expect(await store.sendable(memberA, includePaused: false), isEmpty);
      await store.sendNow(callId);
      expect(
        (await store.op(op.operationId))!.sendStatus,
        JointPurchaseOpStatus.pendingSend,
      );

      await store.markRejected(op, 'QUANTITY_INVALID');
      await store.sendNow(callId);
      final stored = (await store.op(op.operationId))!;
      expect(stored.sendStatus, JointPurchaseOpStatus.rejected);
      expect(stored.isTerminal, isTrue);
    },
  );

  test(
    'una transición sólo parte de lo pendiente: un terminal no cambia',
    () async {
      final op = await confirm({litreRef: 25000});
      await store.markOutOfTime(op);
      await store.markReceived(
        op,
        JointPurchaseParticipation.fromJson(participationJson()),
      );
      expect(
        (await store.op(op.operationId))!.sendStatus,
        JointPurchaseOpStatus.outOfTime,
      );
      expect((await store.call(callId))!.serverParticipation, isNull);
    },
  );

  test('una respuesta atrasada nunca restaura cantidades anteriores', () async {
    await seedCalls(store, memberA, [
      callJson(
        participation: participationJson(
          lines: {litreRef: 40000},
          lastSequence: 5,
        ),
      ),
    ]);
    // Una lista vieja con last_sequence menor no sustituye lo guardado.
    await seedCalls(store, memberA, [
      callJson(participation: participationJson(lastSequence: 2)),
    ]);
    expect(
      (await store.call(callId))!.serverParticipation!.lines[litreRef],
      40000,
    );
  });

  test(
    'necesidad declarada del titular por producto central, sólo lectura',
    () async {
      await fixture.needs.declare(
        referenceDate: inCampaign,
        productId: fixture.litreProductId,
        quantityBase: 12000,
      );
      final outboxBefore = await fixture.outboxRows();
      expect(await store.declaredNeedsFor(campaignRef), {litreRef: 12000});
      expect(await store.declaredNeedsFor(otherCampaignRef), isEmpty);
      expect(await store.declaredNeedsFor(null), isEmpty);
      expect(await fixture.outboxRows(), outboxBefore);
    },
  );

  test('otro titular no ve las convocatorias ni prepara operaciones', () async {
    await seedCalls(store, memberB, [callJson(id: otherCallId)]);
    expect((await store.callsForActiveOwner()).map((c) => c.callId), [callId]);
    await expectLater(
      store.confirm(
        callId: otherCallId,
        lines: {litreRef: 1000},
        consentVersion: jointPurchaseConsentVersion,
        consentAcceptedAt: now,
      ),
      throwsA(isA<BusinessRuleException>()),
    );
  });

  // --- E2 §10.1 y §10.2: historial y consentimiento CONV-2 -----------------

  const closedId = 'ab1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';
  const cancelledId = 'cb1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';
  const notIncludedId = 'db1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';
  const rejectedId = 'eb1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';
  const oldId = 'fb1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';
  const olderId = '0b1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';

  Future<void> insertOp(
    String call,
    String status, {
    String operationId = '9e1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d',
    String consentVersion = 'CONV-2',
    String? lastCode,
  }) async =>
      (await fixture.database.database).insert(JointPurchaseStore.opsTable, {
        'operation_id': operationId,
        'call_id': call,
        'tenant_id': memberA.tenantId,
        'member_id': memberA.memberId,
        'sequence': 1,
        'kind': 'CONFIRM',
        'lines_json': '[{"product_ref":"$litreRef","quantity_base":"1000"}]',
        'consent_version': consentVersion,
        'consent_accepted_at': '2026-11-10T00:00:00.000Z',
        'send_status': status,
        'attempts': 1,
        'last_code': lastCode,
        'created_at': '2026-11-10T00:00:00.000Z',
        'updated_at': '2026-11-10T00:00:00.000Z',
      });

  List<JointPurchaseCallView> historyPage(List<Map<String, Object?>> calls) =>
      JointPurchaseHistoryPage.fromJson(historyJson(calls)).calls;

  Map<String, Object?> closing({required bool included}) => {
    'cutoff_at': deadline,
    'closed_at': deadline,
    'included': included,
    'lines': included
        ? [
            {
              'product_ref': litreRef,
              'base_unit': 'ML',
              'quantity_base': '25000',
            },
          ]
        : <Object?>[],
  };

  test('reemplazo de la vista por defecto (§10.1 b): conserva terminadas con participación y lo que tiene operaciones; descarta abiertas ajenas sin operaciones', () async {
    await seedCalls(store, memberA, [
      callJson(),
      callJson(
        id: closedId,
        status: 'CLOSED',
        participation: participationJson(),
        closing: closing(included: true),
      ),
      callJson(
        id: cancelledId,
        status: 'CANCELLED',
        participation: participationJson(withdrawn: true),
      ),
      // Cerrada sin entrar al consolidado: no hay copia de lo aceptado.
      callJson(
        id: notIncludedId,
        status: 'CLOSED',
        participation: participationJson(withdrawn: true),
        closing: closing(included: false),
      ),
      callJson(id: rejectedId),
      callJson(id: otherCallId, participation: participationJson()),
    ]);
    expect((await store.call(notIncludedId))!.serverParticipation, isNull);
    await insertOp(
      rejectedId,
      JointPurchaseOpStatus.rejected,
      lastCode: 'QUANTITY_INVALID',
    );

    // El sindicato ya no sirve ninguna (salieron de la ventana, o la
    // abierta se canceló sin que el agricultor participara).
    await seedCalls(store, memberA, const []);
    final kept = (await store.callsForActiveOwner()).map((c) => c.callId);
    expect(
      kept,
      unorderedEquals([
        closedId,
        cancelledId,
        notIncludedId,
        rejectedId,
        otherCallId,
      ]),
    );
    // La abierta sin participación ni operaciones es la única descartada.
    expect(await store.call(callId), isNull);
    // El rechazo sigue visible con su convocatoria.
    final rejected = (await store.call(rejectedId))!;
    expect(rejected.latestOp!.sendStatus, JointPurchaseOpStatus.rejected);
    expect(rejected.latestOp!.lastCode, 'QUANTITY_INVALID');
    // La participación aceptada guardada no se pierde.
    expect((await store.call(closedId))!.serverParticipation!.lines, {
      litreRef: 25000,
    });
  });

  test('historial: se guarda sin borrar nada; filtro de presentación por fecha de término y recuento de anteriores', () async {
    await seedCalls(store, memberA, [
      callJson(),
      callJson(
        id: cancelledId,
        status: 'CANCELLED',
        participation: participationJson(withdrawn: true),
        cancelledAt: '2026-11-01T10:00:00.000Z',
      ),
    ], olderCount: 3);
    var overview = await store.overviewForActiveOwner();
    expect(overview.recent.map((c) => c.callId), [callId, cancelledId]);
    expect(overview.older, isEmpty);
    expect(overview.olderCount, 3);
    expect(overview.missingOlder, 3);

    await store.saveHistory(
      memberA,
      historyPage([
        oldCallJson(oldId, finishedAt: '2026-04-01T12:00:00.000Z'),
        oldCallJson(
          olderId,
          status: 'CANCELLED',
          finishedAt: '2026-02-01T12:00:00.000Z',
        ),
      ]),
    );
    overview = await store.overviewForActiveOwner();
    // Lo que estaba no se tocó.
    expect(overview.recent.map((c) => c.callId), [callId, cancelledId]);
    // Anteriores: de la más reciente a la más antigua.
    expect(overview.older.map((c) => c.callId), [oldId, olderId]);
    expect(overview.older.first.finishedAt, '2026-04-01T12:00:00.000Z');
    expect(overview.older.first.serverParticipation!.lines, {litreRef: 25000});
    expect(overview.missingOlder, 1);

    // La siguiente actualización de la vista por defecto no las borra.
    await seedCalls(store, memberA, [callJson()], olderCount: 3);
    overview = await store.overviewForActiveOwner();
    expect(overview.older.map((c) => c.callId), [oldId, olderId]);
    expect(overview.recent.map((c) => c.callId), [callId, cancelledId]);

    // Con el paso del tiempo, una reciente pasa a «Historial» sólo en la
    // presentación.
    now = DateTime.utc(2027, 6, 1);
    overview = await store.overviewForActiveOwner();
    expect(overview.recent.map((c) => c.callId), [callId]);
    expect(overview.older.map((c) => c.callId), [cancelledId, oldId, olderId]);
  });

  test('una convocatoria anterior conserva y muestra sus operaciones pendientes, rechazadas o fuera de plazo', () async {
    await store.saveHistory(
      memberA,
      historyPage([oldCallJson(oldId), oldCallJson(olderId)]),
    );
    await insertOp(oldId, JointPurchaseOpStatus.pendingSend);
    await insertOp(
      olderId,
      JointPurchaseOpStatus.outOfTime,
      operationId: '9f1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d',
      lastCode: JointPurchaseCodes.deadlinePassed,
    );
    await seedCalls(store, memberA, const []);
    final older = (await store.overviewForActiveOwner()).older;
    expect(older.map((c) => c.callId), unorderedEquals([oldId, olderId]));
    final byId = {for (final call in older) call.callId: call};
    expect(byId[oldId]!.pendingOp, isNotNull);
    expect(
      byId[olderId]!.latestOp!.sendStatus,
      JointPurchaseOpStatus.outOfTime,
    );
    // Lo pendiente sigue en la cola del emisor.
    expect(
      (await store.sendable(memberA, includePaused: true)).single.callId,
      oldId,
    );
  });

  test(
    'otro titular no ve el historial ni el recuento del titular activo',
    () async {
      await store.saveHistory(memberB, historyPage([oldCallJson(oldId)]));
      await seedCalls(store, memberB, [
        callJson(id: otherCallId),
      ], olderCount: 9);
      final overview = await store.overviewForActiveOwner();
      expect(overview.recent.map((c) => c.callId), [callId]);
      expect(overview.older, isEmpty);
      // El recuento del titular activo (0, de setUp), no el de memberB.
      expect(overview.olderCount, 0);
      expect(overview.missingOlder, 0);
      expect(await store.call(oldId), isNull);
    },
  );

  test('CONV-1 pendiente de antes de actualizar: se conserva; confirmar lo mismo con CONV-2 la sustituye', () async {
    await insertOp(
      callId,
      JointPurchaseOpStatus.pendingSend,
      consentVersion: jointPurchaseLegacyConsentVersion,
    );
    final legacy = (await store.sendable(memberA, includePaused: false)).single;
    expect(legacy.consentVersion, 'CONV-1');

    final renewed = await confirm({litreRef: 1000});
    expect(renewed.operationId, isNot(legacy.operationId));
    expect(renewed.consentVersion, 'CONV-2');
    expect(renewed.sequence, 2);
    expect(
      (await store.op(legacy.operationId))!.sendStatus,
      JointPurchaseOpStatus.superseded,
    );
    // Con CONV-1 no se prepara nada nuevo.
    await expectLater(
      store.confirm(
        callId: callId,
        lines: {litreRef: 2000},
        consentVersion: jointPurchaseLegacyConsentVersion,
        consentAcceptedAt: now,
      ),
      throwsA(isA<BusinessRuleException>()),
    );
  });
}
