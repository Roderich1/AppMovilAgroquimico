// Propiedad de un respaldo local antes de restaurarlo (RU-11, RF-01; v1.5
// §3.11: «Copia de otro propietario: acceso denegado»).
//
// Regla pura, sin E/S. Compara lo que la copia declara (origen, vínculo de
// titular, instalación activada) con el contexto vigente (vínculo de la base
// actual, sesión legible e instalación) y predice con el mismo clasificador
// el estado que tendría la base restaurada. Las referencias de la copia no
// demuestran identidad: sólo permiten rechazar lo que se sabe ajeno.
import 'installation_access.dart';

/// Lo que la copia declara sobre su propietario, leído sin modificarla.
class BackupOwnership {
  const BackupOwnership({
    required this.origin,
    required this.binding,
    required this.activatedInstallationRef,
  });

  /// Copia anterior a la política (esquema < 8): sin vínculo; al restaurarla,
  /// la migración la marca como histórica.
  const BackupOwnership.historical()
    : origin = InstallOrigin.legacyPrePolicy,
      binding = null,
      activatedInstallationRef = null;

  final InstallOrigin origin;
  final OwnerScope? binding;
  final String? activatedInstallationRef;
}

/// Contexto vigente cuando se pide restaurar.
class RestoreContext {
  const RestoreContext({
    required this.currentBinding,
    required this.session,
    required this.sessionScope,
    required this.currentInstallationRef,
  });

  /// Vínculo activo de la base que se va a reemplazar.
  final OwnerScope? currentBinding;
  final LocalSessionCondition session;
  final OwnerScope? sessionScope;
  final String? currentInstallationRef;
}

enum RestoreRejection {
  /// La copia es de otro Member o de otro tenant.
  otherOwner,

  /// La copia viene de una activación sin terminar (base nueva sin titular):
  /// restaurarla bloquearía la instalación sin ser de nadie.
  incompleteActivation,
}

class RestoreOwnershipVerdict {
  const RestoreOwnershipVerdict.accepted(InstallationAccessState this.predicted)
    : rejection = null;

  const RestoreOwnershipVerdict.rejected(RestoreRejection this.rejection)
    : predicted = null;

  /// Estado que tendrá la instalación con la base restaurada.
  final InstallationAccessState? predicted;
  final RestoreRejection? rejection;

  bool get accepted => rejection == null;

  /// Mensaje para el usuario, sin identificadores.
  String get message => switch (rejection) {
    RestoreRejection.otherOwner =>
      'Esta copia pertenece a otro titular (otra cuenta o sindicato). No se '
          'restauró; sus datos actuales se conservan.',
    RestoreRejection.incompleteActivation =>
      'Esta copia procede de una activación sin terminar y no tiene titular. '
          'No se restauró; sus datos actuales se conservan.',
    null => switch (predicted!) {
      InstallationAccessState.legacyUnbound =>
        'Copia anterior a la vinculación con una cuenta: quedará sin titular y '
            'no se atribuirá a ninguna cuenta.',
      InstallationAccessState.restoredRequiresActivation =>
        'Esta copia se activó en otra instalación: después de restaurar deberá '
            'activar en línea con la misma cuenta antes de registrar.',
      _ => 'La copia corresponde al titular de esta instalación.',
    },
  };
}

RestoreOwnershipVerdict evaluateRestoreOwnership(
  BackupOwnership backup,
  RestoreContext context,
) {
  final backupBinding = backup.binding;
  final current = context.currentBinding;
  if (backupBinding != null && current != null && backupBinding != current) {
    return const RestoreOwnershipVerdict.rejected(RestoreRejection.otherOwner);
  }
  final predicted = classifyInstallation(
    InstallationAccessInputs(
      origin: backup.origin,
      activeBinding: backupBinding,
      activatedInstallationRef: backup.activatedInstallationRef,
      currentInstallationRef: context.currentInstallationRef,
      session: context.session,
      sessionScope: context.session == LocalSessionCondition.readable
          ? context.sessionScope
          : null,
    ),
  );
  return switch (predicted) {
    InstallationAccessState.identityMismatch =>
      const RestoreOwnershipVerdict.rejected(RestoreRejection.otherOwner),
    InstallationAccessState.newRequiresActivation ||
    InstallationAccessState.activationPendingOwner ||
    InstallationAccessState.sessionDamagedNotActivated =>
      const RestoreOwnershipVerdict.rejected(
        RestoreRejection.incompleteActivation,
      ),
    _ => RestoreOwnershipVerdict.accepted(predicted),
  };
}
