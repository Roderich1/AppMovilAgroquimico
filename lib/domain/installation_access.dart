// Política de primera activación y acceso local (RF-01, CU-01; v1.5 §3.11.6).
//
// Reglas puras, sin E/S. Deciden si la instalación puede operar localmente a
// partir de marcas duraderas, nunca de si la base tiene filas:
//   - el origen de la base (creada bajo la política o histórica),
//   - el vínculo de titular activo (Member/tenant elegido explícitamente),
//   - la instalación en la que se activó por última vez,
//   - el estado de la sesión segura y, si es legible, su ámbito.
// Ningún estado borra, reasigna ni publica datos.
import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Origen de la base respecto de la política de activación.
enum InstallOrigin { newUnderPolicy, legacyPrePolicy }

/// Lo que se sabe de la sesión segura en el arranque, sin credenciales.
enum LocalSessionCondition {
  /// No hay sesión guardada.
  absent,

  /// Sesión legible (vigente o expirada localmente); trae su ámbito.
  readable,

  /// Sesión dañada, ilegible, incompatible o no disponible.
  unreadable,
}

/// Ámbito de negocio de una identidad: Member y tenant (contrato F05 §5).
class OwnerScope {
  const OwnerScope({required this.memberId, required this.tenantId});

  final String memberId;
  final String tenantId;

  @override
  bool operator ==(Object other) =>
      other is OwnerScope &&
      other.memberId == memberId &&
      other.tenantId == tenantId;

  @override
  int get hashCode => Object.hash(memberId, tenantId);

  @override
  String toString() => 'OwnerScope(redacted)';
}

enum InstallationAccessState {
  /// A. Base nueva sin activar: sólo activación en línea.
  newRequiresActivation,

  /// Activación en línea completada en una base nueva, pero falta elegir el
  /// titular: la activación sigue incompleta (v1.5 §3.11.6).
  activationPendingOwner,

  /// B. Vínculo activo y sesión legible del mismo Member y tenant.
  activated,

  /// C. Instalación ya activada cuya sesión falta o no se puede leer: conserva
  /// la operación local; las funciones remotas quedan en pausa.
  activatedSessionUnavailable,

  /// D. Base con vínculo que llega a otra instalación (restauración o
  /// reinstalación): restaurar no demuestra identidad; exige activar de nuevo
  /// con el mismo Member antes de operar.
  restoredRequiresActivation,

  /// La sesión legible pertenece a otro Member o tenant que el vínculo: no se
  /// habilitan datos de otro miembro (CU-01).
  identityMismatch,

  /// E. Base histórica anterior a la política y sin vínculo: compatibilidad
  /// explícita. Opera como antes, sin atribuir nada a ninguna cuenta.
  legacyUnbound,

  /// F. Base nueva sin vínculo y sesión ilegible: no se considera instalación
  /// nueva ni se borra nada; requiere tratamiento explícito.
  sessionDamagedNotActivated;

  /// Si las operaciones privadas del agricultor (escrituras locales) están
  /// habilitadas.
  bool get allowsFarmerOperations => switch (this) {
    activated || activatedSessionUnavailable || legacyUnbound => true,
    _ => false,
  };

  /// Si puede crearse el vínculo de titular: falta vínculo y el estado lo
  /// admite. Además hace falta una sesión legible, cuyo ámbito se vincula; la
  /// base histórica nunca se vincula sola a la cuenta que inicia sesión.
  bool get allowsOwnerBinding => switch (this) {
    activationPendingOwner || legacyUnbound => true,
    _ => false,
  };

  /// Mensaje para el usuario, sin identificadores.
  String get message => switch (this) {
    newRequiresActivation =>
      'Active la aplicación en línea con su cuenta para empezar a registrar.',
    activationPendingOwner =>
      'Cuenta activada. Elija el titular para terminar la activación.',
    activated => 'Instalación activada.',
    activatedSessionUnavailable =>
      'La sesión no está disponible. Los datos locales se conservan y '
          'puede seguir registrando; las funciones en línea están en pausa.',
    restoredRequiresActivation =>
      'Estos datos se activaron en otra instalación. Active la aplicación con '
          'la misma cuenta para seguir. Los datos se conservan.',
    identityMismatch =>
      'La cuenta de esta sesión no corresponde al titular de estos datos. '
          'Los datos se conservan y no se habilitan para otra cuenta.',
    legacyUnbound =>
      'Datos anteriores sin vincular a una cuenta. Puede seguir registrando; '
          'para publicar al sindicato deberá activar y elegir el titular.',
    sessionDamagedNotActivated =>
      'La sesión guardada no se puede leer y la activación no terminó. '
          'No se borra ningún dato.',
  };
}

class InstallationAccessInputs {
  const InstallationAccessInputs({
    required this.origin,
    required this.activeBinding,
    required this.activatedInstallationRef,
    required this.currentInstallationRef,
    required this.session,
    required this.sessionScope,
  });

  final InstallOrigin origin;
  final OwnerScope? activeBinding;
  final String? activatedInstallationRef;

  /// null si la identidad de instalación está dañada o no disponible.
  final String? currentInstallationRef;
  final LocalSessionCondition session;

  /// Sólo con [LocalSessionCondition.readable].
  final OwnerScope? sessionScope;
}

InstallationAccessState classifyInstallation(InstallationAccessInputs input) {
  final binding = input.activeBinding;
  final readable =
      input.session == LocalSessionCondition.readable &&
      input.sessionScope != null;

  if (binding == null) {
    if (input.origin == InstallOrigin.legacyPrePolicy) {
      return InstallationAccessState.legacyUnbound;
    }
    if (readable) return InstallationAccessState.activationPendingOwner;
    return input.session == LocalSessionCondition.absent
        ? InstallationAccessState.newRequiresActivation
        : InstallationAccessState.sessionDamagedNotActivated;
  }

  if (readable) {
    return input.sessionScope == binding
        ? InstallationAccessState.activated
        : InstallationAccessState.identityMismatch;
  }

  // Sesión ausente o ilegible con vínculo: decide la instalación. Una
  // identidad de instalación dañada (ref null) implica que el archivo existía
  // en este dispositivo, no una instalación nueva.
  final current = input.currentInstallationRef;
  final sameInstallation =
      current == null || current == input.activatedInstallationRef;
  return sameInstallation
      ? InstallationAccessState.activatedSessionUnavailable
      : InstallationAccessState.restoredRequiresActivation;
}

/// Referencia de instalación que se guarda en SQLite: un resumen de un solo
/// sentido del installationClientId, no el identificador. Viaja en los
/// respaldos, pero en otra instalación no coincide con su identidad nueva.
String installationReference(String installationClientId) => sha256
    .convert(
      utf8.encode('agrocuentas:installation-ref:v1:$installationClientId'),
    )
    .toString();
