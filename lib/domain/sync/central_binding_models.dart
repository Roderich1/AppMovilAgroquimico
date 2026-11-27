import '../campaign_calendar.dart';
import '../repository_exceptions.dart' show BusinessRuleException;
import 'campaign_period_check.dart';
import 'central_references.dart';
import 'sync_types.dart';

class CentralBindingException extends BusinessRuleException {
  CentralBindingException(super.message);
}

enum BindingStatus {
  valid('VALID'),
  invalid('INVALID');

  const BindingStatus(this.code);
  final String code;

  static BindingStatus fromCode(Object? code) =>
      values.firstWhere((status) => status.code == code);
}

/// Por qué un vínculo dejó de admitir publicaciones nuevas.
enum BindingInvalidReason {
  referenceMissing('REFERENCE_MISSING', 'Ya no figura en el sindicato.'),
  notAccepting('NOT_ACCEPTING', 'La campaña no admite nuevos aportes.'),
  inactive('INACTIVE', 'El producto está inactivo en el sindicato.'),

  /// `refreshFrom` lo usa también cuando la unidad central sigue siendo L o
  /// KG pero ya no es la del vínculo: el texto cubre los dos casos.
  notLinkable(
    'NOT_LINKABLE',
    'La unidad del sindicato ya no es L ni KG, o ya no coincide con la local.',
  ),

  /// D-F04-C2: el período local no cabe en el de la campaña central.
  periodIncompatible(
    'PERIOD_INCOMPATIBLE',
    'El período local no cabe en el de la campaña del sindicato.',
  ),

  /// D-F04-C2: vínculo anterior a la regla, sin el período central guardado.
  /// Hasta actualizar las referencias no se puede demostrar que quepa.
  periodUnverified(
    'PERIOD_UNVERIFIED',
    'El período de la campaña del sindicato no se ha comprobado: actualice '
        'las referencias.',
  );

  const BindingInvalidReason(this.code, this.message);
  final String code;
  final String message;

  /// Motivos que bloquean el envío de intenciones nuevas desde el teléfono:
  /// Central no los detecta por sí sola (aceptaría un total con días fuera
  /// de su período).
  bool get holdsQueue => this == periodIncompatible || this == periodUnverified;

  static BindingInvalidReason? fromCode(Object? code) {
    for (final reason in values) {
      if (reason.code == code) return reason;
    }
    return null;
  }
}

class CampaignBinding {
  const CampaignBinding({
    required this.campaignId,
    required this.tenantId,
    required this.campaignRef,
    required this.centralName,
    required this.centralStartDay,
    required this.centralEndDay,
    required this.status,
    required this.invalidReason,
    required this.boundAt,
    required this.checkedAt,
  });

  final int campaignId;
  final String tenantId;
  final String campaignRef;
  final String centralName;

  /// Período central (días civiles) leído al vincular o al refrescar; nulo en
  /// vínculos anteriores a la regla, hasta que se actualicen las referencias.
  final String? centralStartDay;
  final String? centralEndDay;
  final BindingStatus status;
  final BindingInvalidReason? invalidReason;
  final String boundAt;
  final String checkedAt;

  bool get isValid => status == BindingStatus.valid;

  CentralPeriod? get centralPeriod => centralStartDay == null
      ? null
      : CentralPeriod(startDay: centralStartDay!, endDay: centralEndDay);

  /// D-F04-C2 (C2-R1): la compatibilidad temporal **no está demostrada** para
  /// [local], sea cual sea el motivo de invalidez guardado. Sin período
  /// central conocido, o sin período local (campaña que no se pudo leer), no
  /// se puede comprobar y se retiene: falla cerrado. Con los dos, el local
  /// tiene que caber. Decide la retención de la cola, aparte del motivo que
  /// se muestra.
  bool periodHold(CampaignPeriod? local) {
    final central = centralPeriod;
    if (central == null || local == null) return true;
    return periodMismatch(local, central) != null;
  }

  CampaignBinding withStatus(BindingInvalidReason? reason) => CampaignBinding(
    campaignId: campaignId,
    tenantId: tenantId,
    campaignRef: campaignRef,
    centralName: centralName,
    centralStartDay: centralStartDay,
    centralEndDay: centralEndDay,
    status: reason == null ? BindingStatus.valid : BindingStatus.invalid,
    invalidReason: reason,
    boundAt: boundAt,
    checkedAt: checkedAt,
  );

  static CampaignBinding fromRow(Map<String, Object?> row) => CampaignBinding(
    campaignId: row['campaign_id']! as int,
    tenantId: row['tenant_id']! as String,
    campaignRef: row['campaign_ref']! as String,
    centralName: row['central_name']! as String,
    centralStartDay: row['central_start_day'] as String?,
    centralEndDay: row['central_end_day'] as String?,
    status: BindingStatus.fromCode(row['status']),
    invalidReason: BindingInvalidReason.fromCode(row['invalid_reason']),
    boundAt: row['bound_at']! as String,
    checkedAt: row['checked_at']! as String,
  );
}

class ProductBinding {
  const ProductBinding({
    required this.productId,
    required this.tenantId,
    required this.productRef,
    required this.centralName,
    required this.centralUnit,
    required this.baseUnit,
    required this.status,
    required this.invalidReason,
    required this.boundAt,
    required this.checkedAt,
  });

  final int productId;
  final String tenantId;
  final String productRef;
  final String centralName;
  final String centralUnit;
  final BaseUnit baseUnit;
  final BindingStatus status;
  final BindingInvalidReason? invalidReason;
  final String boundAt;
  final String checkedAt;

  bool get isValid => status == BindingStatus.valid;

  static ProductBinding fromRow(Map<String, Object?> row) => ProductBinding(
    productId: row['product_id']! as int,
    tenantId: row['tenant_id']! as String,
    productRef: row['product_ref']! as String,
    centralName: row['central_name']! as String,
    centralUnit: row['central_unit']! as String,
    baseUnit: BaseUnit.fromCode(row['base_unit'])!,
    status: BindingStatus.fromCode(row['status']),
    invalidReason: BindingInvalidReason.fromCode(row['invalid_reason']),
    boundAt: row['bound_at']! as String,
    checkedAt: row['checked_at']! as String,
  );
}

/// Un vínculo de campaña que requiere revisión del titular (D-F04-C2), con
/// los aportes que lo usan: los aceptados por Central y los que esperan en la
/// cola. Nada de esto se reescribe ni se reasigna; se muestra.
class CampaignBindingReview {
  const CampaignBindingReview({
    required this.binding,
    required this.local,
    required this.acceptedContributions,
    required this.heldIntentions,
  });

  final CampaignBinding binding;
  final CampaignPeriod local;

  /// Contribuciones con una intención aceptada (ACKED) bajo esta referencia.
  final int acceptedContributions;

  /// Intenciones con valor sin asentar (nunca enviadas o con resultado
  /// desconocido) que el worker retiene: no salen por POST; las inciertas se
  /// concilian por consulta.
  final int heldIntentions;
}

/// Estados de la outbox que todavía pueden cambiar el estado central: con
/// alguno de ellos, el vínculo de esa referencia no se corrige ni se quita.
const String unsettledOutboxStatuses =
    "('PENDING','SENDING','OUTCOME_UNKNOWN','CONFLICT','AUTH_PAUSED',"
    "'OWNER_PAUSED','RESTORE_PAUSED','VERSION_MISMATCH')";

/// Texto del problema de período de [binding] frente a [local], con los dos
/// períodos; `null` si no hay problema de período.
String? centralBindingPeriodProblem(
  CampaignBinding binding,
  CampaignPeriod local,
) {
  final central = binding.centralPeriod;
  if (central == null) {
    return '«${local.name}» va ${local.describe}; el período de '
        '«${binding.centralName}» del sindicato no se ha comprobado todavía. '
        'Actualice las referencias del sindicato.';
  }
  final mismatch = periodMismatch(local, central);
  if (mismatch == null) return null;
  return periodMismatchMessage(
    localName: local.name,
    local: local,
    centralName: binding.centralName,
    central: central,
    mismatch: mismatch,
  );
}

/// Contrato de vínculos centrales para la presentación.
abstract interface class CentralBindingGateway {
  Future<List<CampaignBinding>> campaignBindings();
  Future<List<ProductBinding>> productBindings();
  Future<List<CampaignBindingReview>> reviewsForCampaigns({
    required List<CampaignBinding> bindings,
    required Map<int, CampaignPeriod> periods,
  });
  Future<CampaignBinding> bindCampaign({
    required int campaignId,
    required CentralCampaign central,
    required String tenantId,
    DateTime? plannedEnd,
  });
  Future<ProductBinding> bindProduct({
    required int productId,
    required CentralProduct central,
    required String tenantId,
  });
  Future<void> unbindCampaign(int campaignId);
  Future<void> unbindProduct(int productId);
}
