import 'dart:math';

import '../../data/database_replacement.dart'
    show DatabaseReplacementInProgressException;
import '../../data/owner_binding_store.dart';
import '../../data/sync/sync_outbox_store.dart';
import '../../domain/sync/sync_types.dart';
import '../../domain/sync/sync_wire.dart';
import 'sync_access.dart';
import 'sync_api.dart';

/// Backoff exponencial con jitter completo (contrato F05 §11; valores de
/// Mobile #31): base 2 s, ×2 por intento, tope 15 min, mínimo 1 s. Una demora
/// pedida por el servidor se respeta aunque supere el tope.
class SyncBackoff {
  const SyncBackoff({
    this.base = const Duration(seconds: 2),
    this.cap = const Duration(minutes: 15),
    this.minimum = const Duration(seconds: 1),
  });

  final Duration base;
  final Duration cap;
  final Duration minimum;

  Duration delay(int attempts, Random random, {Duration? retryAfter}) {
    final exponent = max(0, min(attempts - 1, 20));
    final ceiling = min(
      cap.inMilliseconds,
      base.inMilliseconds * (1 << exponent),
    );
    final jittered = Duration(milliseconds: random.nextInt(ceiling + 1));
    final own = jittered < minimum ? minimum : jittered;
    if (retryAfter != null && retryAfter > own) return retryAfter;
    return own;
  }
}

/// Por qué el worker se detuvo sin enviar todo.
enum SyncBlocker {
  /// No hay titular vinculado.
  noOwner,

  /// No hay acceso en línea verificado (o venció): el agricultor debe
  /// verificarlo. Nada se pierde.
  accessRequired,

  /// La cuenta en sesión no es la del titular de estos datos.
  ownerMismatch,

  /// Central rechazó el contexto de la cuenta (403): cola pausada.
  forbidden,

  /// Central no acepta esta versión del contrato (422).
  versionMismatch,

  /// Sin conexión o resultado desconocido: se reintentará con backoff.
  unreachable,

  /// Central pidió esperar (429/503).
  throttled,

  /// Se está restaurando un respaldo.
  replacementInProgress,
}

class SyncRunReport {
  SyncRunReport();

  int sent = 0;
  int accepted = 0;
  int conflicts = 0;
  int rejected = 0;
  int retried = 0;
  SyncBlocker? blocker;

  @override
  String toString() =>
      'SyncRunReport(sent: $sent, accepted: $accepted, conflicts: $conflicts, '
      'rejected: $rejected, retried: $retried, blocker: ${blocker?.name})';
}

/// Worker de Sync v1 (Mobile #31). Envía como máximo una intención por
/// contribución y la sucesora sólo tras el ACK de su antecesora. Registra
/// cada intento antes de enviarlo, nunca cambia el operationId ni el
/// contenido de una intención enviada, nunca reintenta CONFLICT ni REJECTED
/// y sólo marca «sincronizado» con un ACK válido de aceptación.
class SyncWorker {
  SyncWorker({
    required SyncOutboxStore outbox,
    required OwnerBindingStore owners,
    required SyncApi Function() api,
    required SyncAccessHolder access,
    this.backoff = const SyncBackoff(),
    this.budget = 20,
    Random? random,
    DateTime Function()? clock,
  }) : _outbox = outbox,
       _owners = owners,
       _api = api,
       _access = access,
       _random = random ?? Random.secure(),
       _clock = clock ?? DateTime.now;

  final SyncOutboxStore _outbox;
  final OwnerBindingStore _owners;
  final SyncApi Function() _api;
  final SyncAccessHolder _access;
  final SyncBackoff backoff;

  /// Intentos como máximo por ciclo (F05 §11: presupuesto por ciclo).
  final int budget;
  final Random _random;
  final DateTime Function() _clock;

  Future<SyncRunReport>? _running;

  /// Un solo ciclo a la vez: una llamada concurrente espera al vigente.
  Future<SyncRunReport> run() => _running ??= _run().whenComplete(() {
    _running = null;
  });

  Future<SyncRunReport> _run() async {
    final report = SyncRunReport();
    try {
      // Lo que quedó «enviando» de un proceso anterior pudo llegar o no.
      await _outbox.recoverInterrupted();
      final owner = await _owners.activeBinding();
      await _outbox.pauseOtherOwners(owner?.id);
      if (owner == null) return report..blocker = SyncBlocker.noOwner;
      final summary = await _outbox.summary();
      if (summary.count(OutboxStatus.versionMismatch) > 0) {
        return report..blocker = SyncBlocker.versionMismatch;
      }
      for (var attempt = 0; attempt < budget; attempt++) {
        final ready = await _outbox.readyToSend(
          activeBindingId: owner.id,
          now: _clock(),
        );
        if (ready.isEmpty) break;
        final access = _access.current;
        if (access == null) return report..blocker = SyncBlocker.accessRequired;
        if (access.scope != owner.scope) {
          // Otra cuenta no publica lo de este titular (C34/C38).
          return report..blocker = SyncBlocker.ownerMismatch;
        }
        final entry = await _outbox.markSending(ready.first);
        report.sent++;
        final outcome = await _api().push(entry, access.accessToken);
        final stop = await _handle(entry, outcome, owner.id, report);
        if (stop != null) return report..blocker = stop;
      }
      return report;
    } on DatabaseReplacementInProgressException {
      return report..blocker = SyncBlocker.replacementInProgress;
    } on SyncOutboxRaceException {
      return report;
    }
  }

  DateTime _later(OutboxEntry entry, {Duration? retryAfter}) => _clock().add(
    backoff.delay(entry.attempts, _random, retryAfter: retryAfter),
  );

  /// Devuelve un bloqueo si el ciclo debe detenerse.
  Future<SyncBlocker?> _handle(
    OutboxEntry entry,
    PushOutcome outcome,
    int bindingId,
    SyncRunReport report,
  ) async {
    switch (outcome) {
      case PushAcknowledged(:final ack):
        switch (ack.outcome) {
          case AckOutcome.applied:
          case AckOutcome.alreadyApplied:
            await _outbox.recordAccepted(entry, ack.serverAcceptedAt!);
            report.accepted++;
            return null;
          case AckOutcome.conflict:
            await _outbox.recordConflict(
              entry,
              ack.code,
              ack.reconciliationReference!,
            );
            report.conflicts++;
            return null;
          case AckOutcome.rejected:
            await _outbox.recordTerminal(
              entry,
              OutboxStatus.rejected,
              ack.code,
            );
            report.rejected++;
            return null;
          case AckOutcome.retryable:
            await _outbox.recordRetry(
              entry,
              status: OutboxStatus.pending,
              code: ack.code,
              nextAttemptAt: _later(entry),
            );
            report.retried++;
            return null;
        }
      case PushRequestFailed(
        :final statusCode,
        :final error,
        :final retryAfter,
      ):
        if (statusCode == 401) {
          await _outbox.recordAuthRequired(entry);
          _access.clear();
          return SyncBlocker.accessRequired;
        }
        if (statusCode == 403) {
          await _outbox.pauseForAuthorization(bindingId);
          _access.clear();
          return SyncBlocker.forbidden;
        }
        if (statusCode == 422) {
          await _outbox.recordVersionMismatch(entry);
          return SyncBlocker.versionMismatch;
        }
        if (error != null && error.disposition == 'MOVE_TO_TERMINAL_FAILURE') {
          await _outbox.recordTerminal(
            entry,
            OutboxStatus.failed,
            error.errorCode,
          );
          report.rejected++;
          return null;
        }
        final throttled =
            error != null && (statusCode == 429 || statusCode == 503);
        await _outbox.recordRetry(
          entry,
          // Un 429/503 cerrado no prueba ausencia de commit, pero tampoco lo
          // sugiere; un 5xx u otra respuesta deja el resultado desconocido.
          status: throttled
              ? OutboxStatus.pending
              : OutboxStatus.outcomeUnknown,
          code: error?.errorCode ?? 'HTTP_$statusCode',
          nextAttemptAt: _later(entry, retryAfter: retryAfter),
        );
        report.retried++;
        return throttled ? SyncBlocker.throttled : SyncBlocker.unreachable;
      case PushUncertain(:final code):
        await _outbox.recordRetry(
          entry,
          status: OutboxStatus.outcomeUnknown,
          code: code,
          nextAttemptAt: _later(entry),
        );
        report.retried++;
        return SyncBlocker.unreachable;
    }
  }
}
