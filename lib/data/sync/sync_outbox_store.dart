import 'dart:math';

import 'package:sqflite/sqflite.dart' show DatabaseExecutor, Transaction;

import '../../domain/sync/intention_planner.dart';
import '../../domain/sync/operation_id.dart';
import '../../domain/sync/sync_types.dart';
import '../agro_repository.dart' show BusinessRuleException;
import '../../domain/campaign_calendar.dart' show CampaignPeriod;
import '../../domain/sync/campaign_period_check.dart'
    show CentralPeriod, periodMismatch;
import '../app_database.dart';
import '../owner_binding_store.dart' show SyncQueueInspector;
import 'central_binding_store.dart' show CentralBindingStore;

class SyncConflictPendingException extends BusinessRuleException {
  SyncConflictPendingException()
    : super(
        'El sindicato registró un conflicto con esta necesidad. Resuélvalo '
        'primero desde Sincronización.',
      );
}

/// Una intención cambió de estado mientras se preparaba la escritura (p. ej.
/// el worker la envió): se reintenta la operación del agricultor.
class SyncOutboxRaceException extends BusinessRuleException {
  SyncOutboxRaceException()
    : super('La sincronización está en curso. Intente de nuevo.');
}

/// D-F04-C2 (C2-R2): al ir a marcar el envío, la compatibilidad temporal del
/// vínculo de la campaña ya no está demostrada. No se marcó, no se contó el
/// intento y no se llamó al transporte.
class SyncHeldForPeriodException extends BusinessRuleException {
  SyncHeldForPeriodException()
    : super(
        'El período de la campaña dejó de ser compatible con el sindicato: '
        'el envío queda retenido.',
      );
}

/// Contribución a la que pertenece una intención (F05 §5): el titular y la
/// clave de dominio. El operationId es aparte.
class ContributionTarget {
  const ContributionTarget({
    required this.ownerBindingId,
    required this.projectionType,
    required this.campaignRef,
    required this.productRef,
    required this.baseUnit,
  });

  final int ownerBindingId;
  final ProjectionType projectionType;
  final String campaignRef;
  final String productRef;
  final BaseUnit baseUnit;
}

/// Resumen para el indicador y la pantalla de sincronización.
class SyncQueueSummary {
  const SyncQueueSummary(
    this.counts,
    this.lastAcceptedAt, {
    this.heldForPeriod = 0,
    this.uncertainValues = 0,
  });

  final Map<OutboxStatus, int> counts;
  final String? lastAcceptedAt;

  /// Intenciones con valor sin asentar (PENDING, SENDING u OUTCOME_UNKNOWN)
  /// que el worker retiene porque la compatibilidad temporal del vínculo de su
  /// campaña no está demostrada (D-F04-C2). No salen por POST; las que ya
  /// salieron alguna vez se concilian por consulta. Siguen contadas en
  /// [counts] con su estado.
  final int heldForPeriod;

  /// Intenciones con valor sin asentar que ya salieron alguna vez
  /// (attempts > 0), retenidas o no: sólo si hay alguna vale la pena buscar
  /// qué conciliar (ahorra consultas en cada ciclo).
  final int uncertainValues;

  int count(OutboxStatus status) => counts[status] ?? 0;

  int get waiting =>
      count(OutboxStatus.pending) +
      count(OutboxStatus.sending) +
      count(OutboxStatus.outcomeUnknown);

  int get needsAttention =>
      count(OutboxStatus.conflict) +
      count(OutboxStatus.rejected) +
      count(OutboxStatus.failed) +
      count(OutboxStatus.authPaused) +
      count(OutboxStatus.ownerPaused) +
      count(OutboxStatus.restorePaused) +
      count(OutboxStatus.versionMismatch);
}

const _sendableStatuses = "('PENDING','SENDING','OUTCOME_UNKNOWN')";

/// La outbox de F05 (SYNC-01/02). Escribe en la misma transacción que la
/// operación de negocio que la origina, y registra los resultados del worker.
/// Nunca borra filas ni reasigna una intención a otro vínculo.
class SyncOutboxStore {
  SyncOutboxStore(this._database, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _database;
  final DateTime Function() _clock;

  String _now() => _clock().toUtc().toIso8601String();

  /// Escrituras del worker: sin la compuerta del agricultor (no son una
  /// operación suya), pero dentro de la exclusión de sustitución.
  Future<T> _write<T>(Future<T> Function(Transaction txn) body) => _database
      .replacement
      .write(() async => (await _database.database).transaction(body));

  // ---------------------------------------------------------------------
  // Dentro de la transacción del agricultor.

  /// Última intención de la contribución que pudo cambiar el estado central
  /// (excluye rechazadas, fallidas y descartadas).
  static Future<OutboxEntry?> latestEffective(
    DatabaseExecutor db,
    ContributionTarget target,
  ) async {
    final rows = await db.query(
      'sync_outbox',
      where:
          'owner_binding_id=? AND projection_type=? AND campaign_ref=? '
          "AND product_ref=? AND base_unit=? "
          "AND status NOT IN ('REJECTED','FAILED','DISCARDED')",
      whereArgs: [
        target.ownerBindingId,
        target.projectionType.code,
        target.campaignRef,
        target.productRef,
        target.baseUnit.code,
      ],
      orderBy: 'id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : OutboxEntry.fromRow(rows.single);
  }

  /// Aplica [plan] en [txn] y devuelve el operationId que lleva la intención,
  /// o null si no hay nada que enviar. Una reescritura sólo prospera si la
  /// fila sigue sin enviarse: si el worker la tomó entretanto, falla y nada
  /// se escribe.
  static Future<String?> applyPlan(
    Transaction txn,
    IntentionPlan plan,
    ContributionTarget target, {
    required String now,
    Random? random,
  }) async {
    switch (plan) {
      case NothingToSendPlan():
        return null;
      case ResolveConflictFirstPlan():
        throw SyncConflictPendingException();
      case DiscardPlan(:final entry):
        final changed = await txn.update(
          'sync_outbox',
          {'status': OutboxStatus.discarded.code, 'updated_at': now},
          where: "id=? AND status='PENDING' AND attempts=0",
          whereArgs: [entry.id],
        );
        if (changed != 1) throw SyncOutboxRaceException();
        return null;
      case RewritePlan(:final entry, :final intention):
        final changed = await txn.update(
          'sync_outbox',
          {..._intentionColumns(intention), 'updated_at': now},
          where: "id=? AND status='PENDING' AND attempts=0",
          whereArgs: [entry.id],
        );
        if (changed != 1) throw SyncOutboxRaceException();
        return entry.operationId;
      case EnqueuePlan(:final intention):
        final operationId = newOperationId(random);
        await txn.insert('sync_outbox', {
          'operation_id': operationId,
          'owner_binding_id': target.ownerBindingId,
          'projection_type': target.projectionType.code,
          'campaign_ref': target.campaignRef,
          'product_ref': target.productRef,
          'base_unit': target.baseUnit.code,
          ..._intentionColumns(intention),
          'status': OutboxStatus.pending.code,
          'attempts': 0,
          'created_at': now,
          'updated_at': now,
        });
        return operationId;
    }
  }

  static Map<String, Object?> _intentionColumns(PlannedIntention intention) => {
    'action': intention.action.code,
    'quantity_base': intention.quantityBase,
    'predecessor_operation_id': intention.causal.predecessorOperationId,
    'predecessor_kind': intention.causal.predecessorKind?.code,
    'reconciliation_reference': intention.causal.reconciliationReference,
  };

  /// Marca [conflict] como resuelto por el propietario sobre el head que
  /// Central mostró. La intención en conflicto no se modifica.
  static Future<void> markConflictResolved(
    Transaction txn,
    OutboxEntry conflict, {
    required String headOperationId,
    required PredecessorKind headKind,
    required String now,
  }) async {
    final changed = await txn.update(
      'sync_outbox',
      {
        'resolution_head_operation_id': headOperationId,
        'resolution_head_kind': headKind.code,
        'resolved_at': now,
        'updated_at': now,
      },
      where: "id=? AND status='CONFLICT' AND resolved_at IS NULL",
      whereArgs: [conflict.id],
    );
    if (changed != 1) throw SyncOutboxRaceException();
  }

  // ---------------------------------------------------------------------
  // Worker.

  /// Tras un cierre forzado, lo que quedó «enviando» pudo llegar o no a
  /// Central: se reenvía igual (mismo operationId y contenido).
  Future<int> recoverInterrupted() => _write(
    (txn) => txn.update('sync_outbox', {
      'status': OutboxStatus.outcomeUnknown.code,
      'updated_at': _now(),
    }, where: "status='SENDING'"),
  );

  /// Pausa las intenciones de cualquier vínculo que no sea [activeBindingId]:
  /// no se envían bajo otra identidad, no se reasignan y no se borran.
  Future<int> pauseOtherOwners(int? activeBindingId) => _write(
    (txn) => txn.update(
      'sync_outbox',
      {'status': OutboxStatus.ownerPaused.code, 'updated_at': _now()},
      where: activeBindingId == null
          ? 'status IN $_sendableStatuses'
          : 'owner_binding_id<>? AND status IN $_sendableStatuses',
      whereArgs: activeBindingId == null ? null : [activeBindingId],
    ),
  );

  /// D-F04-C2: una intención que publica o sustituye un **valor** bajo una
  /// campaña cuya compatibilidad temporal con el sindicato no está demostrada
  /// se retiene: Central la aceptaría sin notar que el total lleva días fuera
  /// de su período. Da igual cuántos intentos lleve (C2-R1): un intento
  /// registrado no demuestra que Central la recibiera, así que un reenvío
  /// podría ser la primera aceptación. Lo que ya salió alguna vez se concilia
  /// por la consulta de operaciones ([heldUncertain]), nunca por otro POST.
  /// Una retirada (CANCEL) sí sale (F06 §6).
  static bool _heldForPeriod(OutboxEntry entry, Set<String> heldRefs) =>
      entry.action != SyncAction.cancel && heldRefs.contains(entry.campaignRef);

  static bool _mayBeHeld(OutboxEntry entry) =>
      entry.status.isSendable && entry.action != SyncAction.cancel;

  /// Intenciones listas: como máximo una por contribución, la más antigua sin
  /// asentar, y sólo si su antecesora local ya fue aceptada (orden causal).
  /// [exclude]: las que este ciclo ya intentó marcar y resultaron retenidas.
  Future<List<OutboxEntry>> readyToSend({
    required int activeBindingId,
    required DateTime now,
    Set<String> exclude = const {},
  }) async {
    final db = await _database.database;
    final rows = await db.query(
      'sync_outbox',
      where: "owner_binding_id=? AND status NOT IN ('ACKED','REJECTED','FAILED','DISCARDED')",
      whereArgs: [activeBindingId],
      orderBy: 'id',
    );
    final entries = rows.map(OutboxEntry.fromRow).toList();
    // Sólo hace falta mirar los vínculos si hay algo que pudiera retenerse.
    final heldRefs = entries.any(_mayBeHeld)
        ? await CentralBindingStore.periodHeldCampaignRefs(db)
        : const <String>{};
    final byOperation = {for (final e in entries) e.operationId: e};
    final seen = <String>{};
    final ready = <OutboxEntry>[];
    for (final entry in entries) {
      // Un conflicto ya resuelto no bloquea: la resolución lo sustituye. Uno
      // sin resolver detiene a toda su contribución.
      if (entry.status == OutboxStatus.conflict && entry.resolvedAt != null) {
        continue;
      }
      if (!seen.add(entry.contributionKey)) continue;
      if (!entry.status.isSendable) continue;
      if (_heldForPeriod(entry, heldRefs)) continue;
      if (exclude.contains(entry.operationId)) continue;
      final next = entry.nextAttemptAt;
      if (next != null && DateTime.parse(next).isAfter(now)) continue;
      final predecessor = entry.predecessorOperationId;
      // Una antecesora local todavía sin aceptar bloquea a su sucesora. Una
      // antecesora que no está en esta outbox (head remoto de una
      // resolución) la valida Central.
      if (predecessor != null && byOperation.containsKey(predecessor)) {
        continue;
      }
      ready.add(entry);
    }
    return ready;
  }

  /// Registra el intento **antes** de enviarlo: sobrevive a un cierre forzado
  /// y, desde aquí, la intención ya no puede reescribirse.
  ///
  /// D-F04-C2 (C2-R2): la elegibilidad temporal se vuelve a comprobar **en
  /// esta misma transacción**, contra la fila y el vínculo actuales. Si la
  /// campaña dejó de ser compatible entre la selección y el marcado, no se
  /// marca SENDING, no se cuenta el intento y no se llama al transporte:
  /// [SyncHeldForPeriodException]. Una retirada (CANCEL) no se retiene.
  Future<OutboxEntry> markSending(OutboxEntry entry) => _write((txn) async {
    final current = await txn.query(
      'sync_outbox',
      where: 'id=? AND status IN $_sendableStatuses',
      whereArgs: [entry.id],
    );
    if (current.length != 1) throw SyncOutboxRaceException();
    final row = OutboxEntry.fromRow(current.single);
    if (row.action != SyncAction.cancel &&
        (await CentralBindingStore.periodHeldCampaignRefs(txn))
            .contains(row.campaignRef)) {
      throw SyncHeldForPeriodException();
    }
    final changed = await txn.rawUpdate(
      'UPDATE sync_outbox SET status=?, attempts=attempts+1, updated_at=? '
      'WHERE id=? AND status IN $_sendableStatuses',
      [OutboxStatus.sending.code, _now(), entry.id],
    );
    if (changed != 1) throw SyncOutboxRaceException();
    final rows = await txn.query(
      'sync_outbox',
      where: 'id=?',
      whereArgs: [entry.id],
    );
    return OutboxEntry.fromRow(rows.single);
  });

  /// Resultado de una **consulta** (GET de operaciones) sobre una intención
  /// retenida: queda visible en `last_code` sin cambiar estado, intentos,
  /// identidad ni contenido (C2-R1: un 404 o una respuesta inválida no
  /// autorizan publicar ni demuestran que una petición anterior no pueda
  /// terminar después). Sólo si la fila sigue sin asentar.
  Future<void> recordHeldQuery(
    OutboxEntry entry,
    String code, {
    DateTime? nextAttemptAt,
  }) => _write(
    (txn) => txn.update(
      'sync_outbox',
      {
        'last_code': code,
        // C2-R3: espacia la próxima consulta (y, si el período vuelve a
        // caber, el próximo envío) sin tocar los intentos.
        if (nextAttemptAt != null)
          'next_attempt_at': nextAttemptAt.toUtc().toIso8601String(),
        'updated_at': _now(),
      },
      where: 'id=? AND status IN $_sendableStatuses',
      whereArgs: [entry.id],
    ),
  );

  /// Aceptación confirmada por un ACK válido del POST o por la consulta de
  /// operaciones (conciliación, D-F04-C2). Con [onlyIfUnsettled], sólo si la
  /// fila sigue sin asentar: una conciliación nunca pisa un estado posterior.
  Future<bool> recordAccepted(
    OutboxEntry entry,
    String serverAcceptedAt, {
    bool onlyIfUnsettled = false,
  }) => _write(
    (txn) async =>
        await txn.update(
          'sync_outbox',
          {
            'status': OutboxStatus.acked.code,
            'last_code': 'OK',
            'server_accepted_at': serverAcceptedAt,
            'acked_at': _now(),
            'next_attempt_at': null,
            'updated_at': _now(),
          },
          where: onlyIfUnsettled
              ? 'id=? AND status IN $_sendableStatuses'
              : 'id=?',
          whereArgs: [entry.id],
        ) ==
        1,
  );

  Future<void> recordConflict(
    OutboxEntry entry,
    String code,
    String reconciliationReference,
  ) => _write(
    (txn) => txn.update(
      'sync_outbox',
      {
        'status': OutboxStatus.conflict.code,
        'last_code': code,
        'ack_reconciliation_reference': reconciliationReference,
        'next_attempt_at': null,
        'updated_at': _now(),
      },
      where: 'id=?',
      whereArgs: [entry.id],
    ),
  );

  /// Rechazo definitivo (REJECTED o FAILED). Una sucesora que nunca salió y
  /// dependía de [entry] pasa a apoyarse en el mismo antecesor que tenía
  /// [entry], porque Central nunca aceptó a ésta.
  Future<void> recordTerminal(
    OutboxEntry entry,
    OutboxStatus status,
    String code,
  ) {
    assert(status == OutboxStatus.rejected || status == OutboxStatus.failed);
    return _write((txn) async {
      await txn.update(
        'sync_outbox',
        {
          'status': status.code,
          'last_code': code,
          'next_attempt_at': null,
          'updated_at': _now(),
        },
        where: 'id=?',
        whereArgs: [entry.id],
      );
      final successors = await txn.query(
        'sync_outbox',
        where:
            "predecessor_operation_id=? AND attempts=0 AND status<>'DISCARDED'",
        whereArgs: [entry.operationId],
      );
      for (final row in successors) {
        final successor = OutboxEntry.fromRow(row);
        final intent = successor.action.carriesValue
            ? ValueIntent(int.parse(successor.quantityBase!))
            : const CancelIntent();
        final planned = actionFor(intent, CausalContext.of(entry));
        await txn.update(
          'sync_outbox',
          planned == null
              ? {'status': OutboxStatus.discarded.code, 'updated_at': _now()}
              : {..._intentionColumns(planned), 'updated_at': _now()},
          where: 'id=?',
          whereArgs: [successor.id],
        );
      }
    });
  }

  /// Fallo temporal o resultado desconocido: mismo envelope, más tarde.
  Future<void> recordRetry(
    OutboxEntry entry, {
    required OutboxStatus status,
    required String code,
    required DateTime nextAttemptAt,
  }) {
    assert(
      status == OutboxStatus.pending || status == OutboxStatus.outcomeUnknown,
    );
    return _write(
      (txn) => txn.update(
        'sync_outbox',
        {
          'status': status.code,
          'last_code': code,
          'next_attempt_at': nextAttemptAt.toUtc().toIso8601String(),
          'updated_at': _now(),
        },
        where: 'id=?',
        whereArgs: [entry.id],
      ),
    );
  }

  /// 401: la credencial venció. La intención vuelve a la cola sin cambios y
  /// espera a que el agricultor verifique el acceso.
  Future<void> recordAuthRequired(OutboxEntry entry) => _write(
    (txn) => txn.update(
      'sync_outbox',
      {
        'status': OutboxStatus.pending.code,
        'last_code': 'AUTH_REQUIRED',
        'updated_at': _now(),
      },
      where: 'id=?',
      whereArgs: [entry.id],
    ),
  );

  Future<void> recordVersionMismatch(OutboxEntry entry) => _write(
    (txn) => txn.update(
      'sync_outbox',
      {
        'status': OutboxStatus.versionMismatch.code,
        'last_code': 'CONTRACT_VERSION_MISMATCH',
        'next_attempt_at': null,
        'updated_at': _now(),
      },
      where: 'id=?',
      whereArgs: [entry.id],
    ),
  );

  /// 403: el contexto de la cuenta no está autorizado. Se pausa toda la cola
  /// del vínculo; nada se borra.
  Future<int> pauseForAuthorization(int bindingId) => _write(
    (txn) => txn.update(
      'sync_outbox',
      {
        'status': OutboxStatus.authPaused.code,
        'last_code': 'AUTH_CONTEXT_FORBIDDEN',
        'updated_at': _now(),
      },
      where: 'owner_binding_id=? AND status IN $_sendableStatuses',
      whereArgs: [bindingId],
    ),
  );

  /// Tras una verificación de acceso correcta del mismo titular.
  Future<int> resumeAuthorizationPaused(int bindingId) => _write(
    (txn) => txn.update(
      'sync_outbox',
      {'status': OutboxStatus.pending.code, 'updated_at': _now()},
      where: "owner_binding_id=? AND status='AUTH_PAUSED'",
      whereArgs: [bindingId],
    ),
  );

  /// Una base restaurada no publica sus intenciones por sí sola (F05 §11,
  /// F06 §8): todo lo que estaba por enviar queda pausado hasta que el
  /// titular lo libere. Se ejecuta dentro de la sustitución.
  static Future<int> pauseAfterRestore(DatabaseExecutor db, String now) =>
      db.update(
        'sync_outbox',
        {'status': OutboxStatus.restorePaused.code, 'updated_at': now},
        where: "status IN ('PENDING','SENDING','OUTCOME_UNKNOWN','AUTH_PAUSED','OWNER_PAUSED')",
      );

  /// El titular libera las intenciones restauradas de su propio vínculo. Las
  /// que ya habían salido pudieron llegar a Central: se reenvían iguales.
  Future<int> releaseRestored(int bindingId) => _write(
    (txn) => txn.rawUpdate(
      "UPDATE sync_outbox SET status = CASE WHEN attempts = 0 THEN 'PENDING' "
      "ELSE 'OUTCOME_UNKNOWN' END, updated_at=? "
      "WHERE owner_binding_id=? AND status='RESTORE_PAUSED'",
      [_now(), bindingId],
    ),
  );

  // ---------------------------------------------------------------------
  // Lecturas.

  Future<List<OutboxEntry>> entries() async {
    final db = await _database.database;
    return (await db.query(
      'sync_outbox',
      orderBy: 'id DESC',
    )).map(OutboxEntry.fromRow).toList();
  }

  Future<OutboxEntry?> byOperationId(String operationId) async {
    final db = await _database.database;
    final rows = await db.query(
      'sync_outbox',
      where: 'operation_id=?',
      whereArgs: [operationId],
    );
    return rows.isEmpty ? null : OutboxEntry.fromRow(rows.single);
  }

  Future<SyncQueueSummary> summary() async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      'SELECT status, COUNT(*) AS n, '
      "SUM(CASE WHEN action<>'CANCEL' THEN 1 ELSE 0 END) AS values_n, "
      "SUM(CASE WHEN action<>'CANCEL' AND attempts>0 THEN 1 ELSE 0 END) AS uncertain_n "
      'FROM sync_outbox GROUP BY status',
    );
    final last = await db.rawQuery(
      "SELECT MAX(acked_at) AS last FROM sync_outbox WHERE status='ACKED'",
    );
    // Sólo se miran los vínculos si hay alguna intención con valor sin
    // asentar: el resumen se pide en cada ciclo.
    var unsettledValues = 0;
    var uncertainValues = 0;
    for (final row in rows) {
      if (!OutboxStatus.fromCode(row['status']).isSendable) continue;
      unsettledValues += (row['values_n'] as int?) ?? 0;
      uncertainValues += (row['uncertain_n'] as int?) ?? 0;
    }
    return SyncQueueSummary(
      {
        for (final row in rows)
          OutboxStatus.fromCode(row['status']): row['n']! as int,
      },
      last.single['last'] as String?,
      heldForPeriod: unsettledValues == 0 ? 0 : (await heldForPeriod()).length,
      uncertainValues: uncertainValues,
    );
  }

  /// Intenciones con valor sin asentar que el worker retiene por el período
  /// de su campaña (D-F04-C2): requieren revisión del titular, no se
  /// reescriben. Incluye las que ya salieron alguna vez (SENDING,
  /// OUTCOME_UNKNOWN o PENDING con intentos): tampoco se reenvían. Una sola
  /// consulta: cada intención con el vínculo y la campaña de su referencia,
  /// del tenant del titular de esa intención.
  Future<List<OutboxEntry>> heldForPeriod({int? ownerBindingId}) async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      'SELECT o.*, b.central_start_day AS b_start, b.central_end_day AS b_end, '
      'c.id AS c_id, c.name AS c_name, c.status AS c_status, '
      'c.start_date AS c_start, c.end_date AS c_end '
      'FROM sync_outbox o '
      'JOIN owner_bindings w ON w.id = o.owner_binding_id '
      'JOIN campaign_bindings b ON b.campaign_ref = o.campaign_ref '
      'AND b.tenant_id = w.tenant_id '
      'JOIN campaigns c ON c.id = b.campaign_id '
      "WHERE o.status IN $_sendableStatuses AND o.action<>'CANCEL'"
      '${ownerBindingId == null ? '' : ' AND o.owner_binding_id=?'} '
      'ORDER BY o.id',
      ownerBindingId == null ? null : [ownerBindingId],
    );
    final held = <OutboxEntry>[];
    for (final row in rows) {
      final start = row['b_start'] as String?;
      final central = start == null
          ? null
          : CentralPeriod(startDay: start, endDay: row['b_end'] as String?);
      final local = CampaignPeriod.fromRow({
        'id': row['c_id'],
        'name': row['c_name'],
        'status': row['c_status'],
        'start_date': row['c_start'],
        'end_date': row['c_end'],
      });
      if (central == null || periodMismatch(local, central) != null) {
        held.add(OutboxEntry.fromRow(row));
      }
    }
    return held;
  }

  /// Intenciones retenidas que **ya salieron alguna vez** (attempts > 0) del
  /// titular [activeBindingId]: Central pudo recibirlas o no. El worker las
  /// resuelve con la consulta de operaciones (C2-R1), nunca con otro POST.
  /// Una consulta ya hecha fija `next_attempt_at` (C2-R3): hasta esa hora no
  /// se vuelve a consultar.
  Future<List<OutboxEntry>> heldUncertain({
    required int activeBindingId,
    required DateTime now,
  }) async => [
    for (final entry in await heldForPeriod(ownerBindingId: activeBindingId))
      if (entry.attempts > 0 &&
          (entry.nextAttemptAt == null ||
              !DateTime.parse(entry.nextAttemptAt!).isAfter(now)))
        entry,
  ];
}

/// Puerto de F04 (`changeOwner`): mientras el vínculo tenga intenciones que
/// cambiaron o pueden cambiar su contribución central, no se cambia de
/// titular. La contribución central es por Member: publicar totales de otra
/// persona bajo el mismo Member la reasignaría en la práctica.
class SyncOutboxInspector implements SyncQueueInspector {
  const SyncOutboxInspector();

  @override
  Future<int> operationsBoundTo(DatabaseExecutor db, int bindingId) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM sync_outbox WHERE owner_binding_id=? '
      "AND status NOT IN ('REJECTED','FAILED','DISCARDED')",
      [bindingId],
    );
    return rows.single['n']! as int;
  }
}
