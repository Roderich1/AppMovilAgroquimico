// Titular, rol privado de negocio y rol central de seguridad (RF-06, CU-05;
// v1.5 §3.4.1 y RU-18). Son tres nociones distintas y no se derivan entre sí:
//
//   - Titular: la persona local que un Member eligió explícitamente
//     (`owner_bindings`). Decide de quién son los datos.
//   - Rol privado de negocio: `persons.role` (ADMIN, FAMILY, THIRD_PARTY).
//     Decide cargos y liquidación: ADMIN paga a los proveedores, su política
//     es MANUAL y no participa en la liquidación. No es un permiso.
//   - Rol central de seguridad: el del Member en el servicio (AGRICULTOR,
//     ADMINISTRADOR, DIRECTIVA). Vive en la sesión, nunca en `persons`, y no
//     concede acceso a operaciones privadas.
//
// Reglas puras, sin E/S.
import 'models.dart';
import 'operation_mode.dart';

PersonRole? personRoleFromCode(Object? code) {
  for (final role in PersonRole.values) {
    if (role.code == code) return role;
  }
  return null;
}

/// Si una persona puede quedar como titular.
enum OwnerEligibility {
  eligible,

  /// El agricultor histórico registrado como administrador de pagos: puede
  /// ser titular con una confirmación explícita. Conserva su rol privado,
  /// sus movimientos y sus reglas de cargo; no se duplica la persona.
  requiresAdministratorConfirmation,

  /// Un tercero no es el agricultor propietario de estos datos.
  notEligible,
}

OwnerEligibility ownerEligibility(PersonRole role) => switch (role) {
  PersonRole.family => OwnerEligibility.eligible,
  PersonRole.admin => OwnerEligibility.requiresAdministratorConfirmation,
  PersonRole.thirdParty => OwnerEligibility.notEligible,
};

/// Papel que una persona cumple en un formulario.
enum PersonPurpose {
  /// Recibe existencias de una compra.
  purchaseAllocation,

  /// Paga al proveedor.
  providerPayer,

  /// Realiza una aplicación.
  applicator,

  /// Origen o destino de una transferencia.
  transferParty,

  /// Dueño de un chaco.
  farmOwner,
}

/// Quién puede elegirse en cada formulario.
///
/// Modo propio: sólo el titular, y no hay transferencias (las guardas del
/// repositorio dicen lo mismo). Modo compartido: las reglas previas por rol
/// privado se conservan; además el titular puede aplicar y transferir aunque
/// figure como administrador de pagos, para que pueda completar sus propias
/// operaciones. Ningún caso cambia su rol ni sus reglas de cargo.
bool canActAs(
  PersonPurpose purpose, {
  required PersonRole? role,
  required bool isOwner,
  required OperationMode mode,
}) {
  if (mode == OperationMode.personal) {
    return isOwner && purpose != PersonPurpose.transferParty;
  }
  return switch (purpose) {
    PersonPurpose.purchaseAllocation || PersonPurpose.farmOwner => true,
    PersonPurpose.providerPayer => role == PersonRole.admin,
    PersonPurpose.applicator ||
    PersonPurpose.transferParty => role != PersonRole.admin || isOwner,
  };
}

/// Filtra filas de `persons` (con `id` y `role`) para un formulario.
List<Map<String, Object?>> eligiblePeople(
  Iterable<Map<String, Object?>> people,
  PersonPurpose purpose, {
  required int? ownerPersonId,
  required OperationMode mode,
}) => [
  for (final person in people)
    if (canActAs(
      purpose,
      role: personRoleFromCode(person['role']),
      isOwner: ownerPersonId != null && person['id'] == ownerPersonId,
      mode: mode,
    ))
      person,
];
