import 'dart:math';

import 'package:sqflite/sqflite.dart' show DatabaseExecutor, Transaction;

import '../../domain/sync/intention_planner.dart';
import '../../domain/sync/operation_id.dart';
import '../../domain/sync/sync_types.dart';
import '../agro_repository.dart' show BusinessRuleException;
import '../app_database.dart';
import '../owner_binding_store.dart' show SyncQueueInspector;

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
  const SyncQueueSummary(this.counts, this.lastAcceptedAt);

  final Map<OutboxStatus, int> counts;
  final String? lastAcceptedAt;

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

  /// Intenciones listas: como máximo una por contribución, la más antigua sin
  /// asentar, y sólo si su antecesora local ya fue aceptada (orden causal).
  Future<List<OutboxEntry>> readyToSend({
    required int activeBindingId,
    required DateTime now,
  }) async {
    final db = await _database.database;
    final rows = await db.query(
      'sync_outbox',
      where: "owner_binding_id=? AND status NOT IN ('ACKED','REJECTED','FAILED','DISCARDED')",
      whereArgs: [activeBindingId],
      orderBy: 'id',
    );
    final entries = rows.map(OutboxEntry.fromRow).toList();
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
  Future<OutboxEntry> markSending(OutboxEntry entry) => _write((txn) async {
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

  Future<void> recordAccepted(OutboxEntry entry, String serverAcceptedAt) =>
      _write(
        (txn) => txn.update(
          'sync_outbox',
          {
            'status': OutboxStatus.acked.code,
            'last_code': 'OK',
            'server_accepted_at': serverAcceptedAt,
            'acked_at': _now(),
            'next_attempt_at': null,
            'updated_at': _now(),
          },
          where: 'id=?',
          whereArgs: [entry.id],
        ),
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
      'SELECT status, COUNT(*) AS n FROM sync_outbox GROUP BY status',
    );
    final last = await db.rawQuery(
      "SELECT MAX(acked_at) AS last FROM sync_outbox WHERE status='ACKED'",
    );
    return SyncQueueSummary({
      for (final row in rows)
        OutboxStatus.fromCode(row['status']): row['n']! as int,
    }, last.single['last'] as String?);
  }
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
