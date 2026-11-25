import 'installation_access.dart';
import 'models.dart';
import 'operation_mode.dart';
import 'person_roles.dart';
import 'repository_exceptions.dart' show BusinessRuleException;

class OwnerBinding {
  const OwnerBinding({
    required this.id,
    required this.personId,
    required this.scope,
    required this.ownerRole,
    required this.boundAt,
    this.endedAt,
    this.endReason,
  });

  final int id;
  final int personId;
  final OwnerScope scope;

  /// Rol privado con el que se aceptó al titular (no el rol central).
  final PersonRole ownerRole;
  final String boundAt;
  final String? endedAt;
  final String? endReason;

  bool get isActive => endedAt == null;

  static OwnerBinding fromRow(Map<String, Object?> row) => OwnerBinding(
    id: row['id']! as int,
    personId: row['person_id']! as int,
    scope: OwnerScope(
      memberId: row['member_id']! as String,
      tenantId: row['tenant_id']! as String,
    ),
    ownerRole: personRoleFromCode(row['owner_role'])!,
    boundAt: row['bound_at']! as String,
    endedAt: row['ended_at'] as String?,
    endReason: row['end_reason'] as String?,
  );
}

class OwnerBindingException extends BusinessRuleException {
  OwnerBindingException(super.message);
}

/// La persona figura como administradora de pagos: puede ser titular sólo si
/// se confirma explícitamente que es el agricultor propietario.
class OwnerAdministratorConfirmationRequired extends OwnerBindingException {
  OwnerAdministratorConfirmationRequired()
    : super(
        'Esta persona figura como administradora de pagos. Confirme que es el '
        'agricultor titular: conserva su rol, sus movimientos y sus reglas de '
        'cobro, y no se crea otra persona.',
      );
}

class ModeTransitionException extends BusinessRuleException {
  ModeTransitionException(super.message, {this.decision});

  final ModeTransitionDecision? decision;
}

/// Contrato de lectura y transiciones de modalidad para la presentación.
abstract interface class OperationModeGateway {
  Future<OperationMode> current();
  Future<ModeTransitionDecision> evaluate(OperationMode target);
  Future<
    ({
      List<String> withStock,
      List<String> planFarmOwners,
      List<String> withBalance,
    })
  >
  describe(ThirdPartyActivity activity);
  Future<ModeTransitionDecision> apply(
    OperationMode target, {
    required bool confirmed,
  });
}

/// Contrato de vínculo de titular para la presentación.
abstract interface class OwnerBindingGateway {
  Future<OwnerBinding?> activeBinding();
  Future<String?> activeOwnerName();
  Future<OwnerBinding> bindExistingPerson({
    required int personId,
    required OwnerScope scope,
    required String installationRef,
    bool confirmAdministrator = false,
  });
  Future<OwnerBinding> bindNewPerson({
    required String name,
    String? phone,
    required OwnerScope scope,
    required String installationRef,
  });
}
