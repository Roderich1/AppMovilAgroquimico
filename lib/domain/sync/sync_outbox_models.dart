import '../repository_exceptions.dart' show BusinessRuleException;
import 'sync_types.dart';

class SyncConflictPendingException extends BusinessRuleException {
  SyncConflictPendingException()
    : super(
        'El sindicato registró un conflicto con este envío. Decida primero '
        'qué versión vale: en «Necesidad declarada» con «Resolver '
        'conflicto…», o en «Consumo para el sindicato» con «Enviar mi total '
        'actual».',
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

/// Contrato de lectura de la cola de sincronización para la presentación.
abstract interface class SyncOutboxGateway {
  Future<List<OutboxEntry>> entries();
  Future<SyncQueueSummary> summary();
}
