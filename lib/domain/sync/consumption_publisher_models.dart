import '../repository_exceptions.dart' show BusinessRuleException;
import 'consumption_projection.dart';
import 'sync_outbox_models.dart';
import 'sync_types.dart';
import 'sync_wire.dart' show OperationView;

class ConsumptionPublishException extends BusinessRuleException {
  ConsumptionPublishException(super.message);
}

/// Qué pasaría con un total si se publica ahora.
enum ConsumptionChange {
  /// Nunca se publicó (o se retiró): PUBLISH.
  publish,

  /// Cambió respecto del último total enviado: SUPERSEDE.
  supersede,

  /// Ya se publicó (o está en camino) ese mismo total: nada que enviar.
  unchanged,

  /// Central registró un conflicto: decide el titular.
  conflict,

  /// El vínculo dejó de ser válido: no se publica hasta corregirlo.
  blocked,

  /// Central rechazó el último envío de este total por el estado de la
  /// campaña (`CAMPAIGN_NOT_OPEN` o `CAMPAIGN_SEALED`). Es un fallo terminal
  /// que requiere intervención (F04 §2.4): «Publicar» no lo vuelve a enviar
  /// ni lo reasigna a otra campaña. Sólo deja de estarlo si, después del
  /// rechazo, las referencias actualizadas muestran que la campaña vuelve a
  /// admitir aportes (vínculo vigente comprobado más tarde).
  rejected,
}

/// Estado de envío de un total, en las tres palabras de la pantalla.
enum ConsumptionSendState {
  /// Sin publicar todavía, en la cola o enviado sin confirmación.
  pending,

  /// Aceptado por el sindicato y sin cambios locales.
  sent,

  /// Conflicto, vínculo no vigente, rechazo del sindicato, cola pausada o
  /// acceso sin verificar: hace falta una decisión o una acción del titular.
  attention,
}

class ConsumptionPreviewRow {
  const ConsumptionPreviewRow({
    required this.campaignName,
    required this.productName,
    required this.baseUnit,
    required this.quantityBase,
    required this.change,
    required this.target,
    required this.prior,
    this.blockedDetail,
    this.lastRejection,
  });

  final String campaignName;
  final String productName;
  final BaseUnit baseUnit;

  /// Total local vigente. Cero si todas sus aplicaciones se revirtieron.
  final int quantityBase;
  final ConsumptionChange change;
  final ContributionTarget target;

  /// Última intención vigente de ese total (null si nunca se publicó).
  final OutboxEntry? prior;

  /// Por qué está bloqueado, con los dos períodos cuando es por período
  /// (D-F04-C2); null si no está bloqueado o el motivo no es de período.
  final String? blockedDetail;

  /// El último envío de este total (el más reciente no descartado) si Central
  /// lo rechazó (REJECTED o FAILED); null si no. No cuenta como antecesor.
  final OutboxEntry? lastRejection;

  bool get sends =>
      change == ConsumptionChange.publish ||
      change == ConsumptionChange.supersede;

  /// Estado de envío derivado de la outbox. Sólo presenta: no decide qué se
  /// envía ([sends] y [change] lo deciden).
  ConsumptionSendState get sendState {
    if (change == ConsumptionChange.conflict ||
        change == ConsumptionChange.blocked ||
        change == ConsumptionChange.rejected ||
        lastRejection != null) {
      return ConsumptionSendState.attention;
    }
    final last = prior;
    if (last != null && last.action != SyncAction.cancel) {
      if (_pausedStatuses.contains(last.status)) {
        return ConsumptionSendState.attention;
      }
      if (last.status.isSendable &&
          syncCodeFamily(last.lastCode) == SyncCodeFamily.authorization) {
        return ConsumptionSendState.attention;
      }
    }
    if (sends) return ConsumptionSendState.pending;
    return last?.status == OutboxStatus.acked
        ? ConsumptionSendState.sent
        : ConsumptionSendState.pending;
  }

  static const _pausedStatuses = {
    OutboxStatus.authPaused,
    OutboxStatus.ownerPaused,
    OutboxStatus.restorePaused,
    OutboxStatus.versionMismatch,
  };

  /// Un total aceptado por Central (o en camino) bajo un vínculo bloqueado:
  /// el titular puede retirarlo (CANCEL, F06 §6) con su confirmación. No se
  /// envía un cero ni se reasigna a otra campaña.
  bool get canWithdraw =>
      change == ConsumptionChange.blocked &&
      prior != null &&
      prior!.action != SyncAction.cancel &&
      !(prior!.status == OutboxStatus.conflict && prior!.resolvedAt == null);
}

/// Campaña × producto con consumo propio que no se publica, con nombres y,
/// si es por período, el detalle con los dos períodos.
typedef ExcludedPairView = ({
  String campaign,
  String product,
  ConsumptionExclusion reason,
  String? detail,
});

class ConsumptionPreview {
  const ConsumptionPreview({
    required this.ownerBindingId,
    required this.rows,
    required this.excludedLines,
    required this.excludedPairs,
  });

  /// Vínculo de titular para el que se calculó: confirmar esta vista previa
  /// no publica el consumo de otro titular.
  final int ownerBindingId;
  final List<ConsumptionPreviewRow> rows;
  final Map<ConsumptionExclusion, int> excludedLines;

  final List<ExcludedPairView> excludedPairs;

  bool get hasChanges => rows.any((row) => row.sends);
}

/// Contrato de publicación de consumo para la presentación.
abstract interface class ConsumptionGateway {
  Future<ConsumptionPreview> preview();
  Future<int> publish(ConsumptionPreview confirmed);
  Future<void> resolveConflict({
    required ConsumptionPreviewRow row,
    required OperationView view,
  });
  Future<void> withdraw(ConsumptionPreviewRow row);
}
