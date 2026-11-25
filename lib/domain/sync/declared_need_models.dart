import '../repository_exceptions.dart' show BusinessRuleException;
import 'central_binding_models.dart' show BindingInvalidReason;
import 'sync_types.dart';
import 'sync_wire.dart' show OperationView;

class DeclaredNeedException extends BusinessRuleException {
  DeclaredNeedException(super.message);
}

/// La campaña o el producto no tienen vínculo vigente con el sindicato.
class BindingRequiredException extends DeclaredNeedException {
  BindingRequiredException(super.message);
}

enum DeclaredNeedStatus {
  active('ACTIVE'),
  cancelled('CANCELLED');

  const DeclaredNeedStatus(this.code);
  final String code;

  static DeclaredNeedStatus fromCode(Object? code) =>
      values.firstWhere((status) => status.code == code);
}

/// Por qué no se puede determinar la campaña de una fecha.
enum CampaignForDateProblem {
  /// Ninguna campaña local cubre la fecha.
  none,

  /// Más de una campaña local la cubre: no se elige en silencio.
  ambiguous,

  /// La campaña no está vinculada con el sindicato.
  notBound,

  /// El vínculo dejó de estar vigente.
  bindingInvalid,
}

class CampaignForDate {
  const CampaignForDate({
    this.campaignId,
    this.name,
    this.problem,
    this.reason,
    this.detail,
  });

  final int? campaignId;
  final String? name;
  final CampaignForDateProblem? problem;
  final BindingInvalidReason? reason;

  /// Detalle del problema de período con los dos períodos (D-F04-C2).
  final String? detail;

  bool get isUsable => problem == null;

  String get message => switch (problem) {
    null => 'Campaña: $name',
    CampaignForDateProblem.none =>
      'Ninguna campaña cubre esa fecha. Revise las fechas de sus campañas.',
    CampaignForDateProblem.ambiguous =>
      'Más de una campaña cubre esa fecha. Corrija las fechas de sus campañas.',
    CampaignForDateProblem.notBound =>
      'La campaña $name requiere vinculación con el sindicato.',
    CampaignForDateProblem.bindingInvalid =>
      'La campaña $name no admite declaraciones: '
          '${detail ?? reason?.message ?? ''}',
  };
}

/// Producto local que se puede declarar: activo y con vínculo vigente.
class DeclarableProduct {
  const DeclarableProduct(this.productId, this.name, this.baseUnit);
  final int productId;
  final String name;
  final BaseUnit baseUnit;
}

class DeclaredNeed {
  const DeclaredNeed({
    required this.id,
    required this.ownerBindingId,
    required this.campaignId,
    required this.campaignName,
    required this.productId,
    required this.productName,
    required this.baseUnit,
    required this.status,
    required this.quantityBase,
    required this.referenceDate,
    required this.currentVersion,
    required this.updatedAt,
    required this.syncOperationId,
    required this.syncStatus,
    required this.syncCode,
    required this.conflictResolved,
    this.syncAttempts = 0,
    this.syncAckedAt,
  });

  final int id;
  final int ownerBindingId;
  final int campaignId;
  final String campaignName;
  final int productId;
  final String productName;
  final BaseUnit baseUnit;
  final DeclaredNeedStatus status;
  final int? quantityBase;
  final String referenceDate;
  final int currentVersion;
  final String updatedAt;

  /// Última intención de su contribución; null si no hay nada que enviar
  /// (p. ej. se anuló antes de que saliera la primera).
  final String? syncOperationId;
  final OutboxStatus? syncStatus;
  final String? syncCode;

  /// La última intención es un conflicto que el propietario ya resolvió.
  final bool conflictResolved;

  /// Intentos de envío de la última intención (0: todavía no salió del
  /// teléfono) y cuándo la confirmó el sindicato; sólo para mostrar.
  final int syncAttempts;
  final String? syncAckedAt;

  /// Conflicto pendiente de la decisión del propietario.
  bool get needsResolution =>
      syncStatus == OutboxStatus.conflict && !conflictResolved;
}

class DeclaredNeedVersion {
  const DeclaredNeedVersion({
    required this.version,
    required this.status,
    required this.quantityBase,
    required this.referenceDate,
    required this.operationId,
    required this.createdAt,
  });

  final int version;
  final DeclaredNeedStatus status;
  final int? quantityBase;
  final String referenceDate;
  final String? operationId;
  final String createdAt;
}

/// Cómo resuelve el propietario un conflicto (F05 §6): nunca lo decide la app.
enum ConflictChoice {
  /// Enviar de nuevo su valor local vigente como nueva intención.
  keepMine,

  /// Retirar su declaración.
  withdraw,
}

/// Contrato de necesidades declaradas para la presentación.
abstract interface class DeclaredNeedGateway {
  Future<List<DeclaredNeed>> needs();
  Future<List<DeclarableProduct>> declarableProducts();
  Future<CampaignForDate> campaignFor(DateTime date);
  Future<int> declare({
    required DateTime referenceDate,
    required int productId,
    required int quantityBase,
  });
  Future<int> updateQuantity(int needId, int quantityBase);
  Future<void> withdraw(int needId);
  Future<List<DeclaredNeedVersion>> history(int needId);
  Future<void> resolveConflict({
    required int needId,
    required ConflictChoice choice,
    required OperationView view,
  });
}
