import 'sync_types.dart';

/// Contexto causal sobre el que se apoya una intención: el antecesor (si lo
/// hay), si era un valor o una retirada, y la referencia de una disputa que
/// la intención resuelve.
class CausalContext {
  const CausalContext({
    this.predecessorOperationId,
    this.predecessorKind,
    this.reconciliationReference,
  }) : assert((predecessorOperationId == null) == (predecessorKind == null));

  /// Sin antecesor: la contribución nunca se publicó.
  static const CausalContext none = CausalContext();

  final String? predecessorOperationId;
  final PredecessorKind? predecessorKind;
  final String? reconciliationReference;

  /// Continuar una intención propia ya creada (aceptada o en camino).
  factory CausalContext.after(OutboxEntry entry) => CausalContext(
    predecessorOperationId: entry.operationId,
    predecessorKind: PredecessorKind.of(entry.action),
  );

  /// El mismo antecesor y referencia que [entry]: para reescribirla o para
  /// apoyar en su lugar a su sucesora cuando Central la rechaza.
  factory CausalContext.of(OutboxEntry entry) => CausalContext(
    predecessorOperationId: entry.predecessorOperationId,
    predecessorKind: entry.predecessorKind,
    reconciliationReference: entry.reconciliationReference,
  );
}

/// Qué se quiere expresar: un total vigente o la retirada del aporte.
sealed class Intent {
  const Intent();
}

class ValueIntent extends Intent {
  const ValueIntent(this.quantityBase) : assert(quantityBase >= 0);
  final int quantityBase;
}

class CancelIntent extends Intent {
  const CancelIntent();
}

/// Acción y causalidad resultantes, o null si no hay nada que enviar.
typedef PlannedIntention = ({
  SyncAction action,
  CausalContext causal,
  String? quantityBase,
});

/// Reglas de Central (contrato F05 §6) vistas desde Mobile:
/// - sin antecesor sólo cabe PUBLISH;
/// - tras un valor, SUPERSEDE (nuevo total) o CANCEL;
/// - tras una retirada, sólo PUBLISH; otra CANCEL sólo tiene sentido para
///   reafirmar la retirada al resolver una disputa.
PlannedIntention? actionFor(Intent intent, CausalContext causal) {
  switch (intent) {
    case ValueIntent(:final quantityBase):
      return (
        action: causal.predecessorKind == PredecessorKind.value
            ? SyncAction.supersede
            : SyncAction.publish,
        causal: causal,
        quantityBase: '$quantityBase',
      );
    case CancelIntent():
      final cancels =
          causal.predecessorKind == PredecessorKind.value ||
          (causal.predecessorKind == PredecessorKind.cancel &&
              causal.reconciliationReference != null);
      return cancels
          ? (action: SyncAction.cancel, causal: causal, quantityBase: null)
          : null;
  }
}

sealed class IntentionPlan {
  const IntentionPlan();
}

/// Crear una intención nueva con un operationId nuevo.
class EnqueuePlan extends IntentionPlan {
  const EnqueuePlan(this.intention);
  final PlannedIntention intention;
}

/// Reescribir una intención que nunca salió del teléfono.
class RewritePlan extends IntentionPlan {
  const RewritePlan(this.entry, this.intention);
  final OutboxEntry entry;
  final PlannedIntention intention;
}

/// Descartar una intención que nunca salió: Central sigue como antes de ella.
class DiscardPlan extends IntentionPlan {
  const DiscardPlan(this.entry);
  final OutboxEntry entry;
}

/// Central ya está (o estará) en el estado pedido: no se envía nada.
class NothingToSendPlan extends IntentionPlan {
  const NothingToSendPlan();
}

/// La última intención quedó en conflicto: decide el propietario primero.
class ResolveConflictFirstPlan extends IntentionPlan {
  const ResolveConflictFirstPlan(this.entry);
  final OutboxEntry entry;
}

/// Decide cómo expresar [intent] dado [prior], la última intención de la
/// misma contribución que pudo cambiar el estado central (no las rechazadas,
/// fallidas ni descartadas).
///
/// - Una intención que nunca salió se reescribe o se descarta (coalescencia
///   segura): Central no la conoce, así que no hay IDEMPOTENCY_MISMATCH.
/// - Cualquier otra no se modifica jamás: se encola una nueva que la tiene
///   por antecesora y espera su ACK.
IntentionPlan planIntention(OutboxEntry? prior, Intent intent) {
  if (prior == null) {
    final planned = actionFor(intent, CausalContext.none);
    return planned == null ? const NothingToSendPlan() : EnqueuePlan(planned);
  }
  if (prior.status == OutboxStatus.conflict) {
    if (prior.resolvedAt == null) return ResolveConflictFirstPlan(prior);
    // Ya resuelto: lo siguiente continúa el head que Central mostró al
    // resolver, no la intención en conflicto (que nunca fue aceptada).
    final planned = actionFor(
      intent,
      CausalContext(
        predecessorOperationId: prior.resolutionHeadOperationId,
        predecessorKind: prior.resolutionHeadKind,
      ),
    );
    return planned == null ? const NothingToSendPlan() : EnqueuePlan(planned);
  }
  if (prior.isUnsent) {
    final planned = actionFor(intent, CausalContext.of(prior));
    if (planned != null) return RewritePlan(prior, planned);
    // Sin nada que enviar sobre el mismo antecesor: una retirada pedida
    // antes de que saliera el primer valor, o tras una republicación nunca
    // enviada, deja a Central como estaba.
    return prior.action == SyncAction.cancel
        ? const NothingToSendPlan()
        : DiscardPlan(prior);
  }
  final planned = actionFor(intent, CausalContext.after(prior));
  return planned == null ? const NothingToSendPlan() : EnqueuePlan(planned);
}
