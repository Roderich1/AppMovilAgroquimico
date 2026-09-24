import 'installation_client_id_store.dart';
import 'app_log.dart';

enum InstallationIdentityStatus { ready, corrupt, unavailable }

class InstallationIdentityInitialization {
  const InstallationIdentityInitialization(this.status);

  final InstallationIdentityStatus status;

  bool get isReady => status == InstallationIdentityStatus.ready;
}

typedef InstallationIdentityDiagnostic = void Function(String message);

/// Inicializa la identidad auxiliar sin convertir su indisponibilidad en un
/// bloqueo del dominio local. El resultado debe estar READY antes de que una
/// futura capa remota intente registrar, sincronizar o asociar sesiones.
Future<InstallationIdentityInitialization> initializeInstallationIdentity({
  InstallationClientIdStore? store,
  InstallationIdentityDiagnostic? diagnostic,
}) async {
  final target = store ?? InstallationClientIdStore();
  final report = diagnostic ?? AppLog.error;

  try {
    await target.getOrCreate();
    return const InstallationIdentityInitialization(
      InstallationIdentityStatus.ready,
    );
  } on InstallationClientIdCorruptException {
    report(
      'La identidad de instalación está corrupta; '
      'la operación local continúa sin identidad remota.',
    );
    return const InstallationIdentityInitialization(
      InstallationIdentityStatus.corrupt,
    );
  } on Object catch (error) {
    report(
      'La identidad de instalación no está disponible '
      '(${error.runtimeType}); la operación local continúa.',
    );
    return const InstallationIdentityInitialization(
      InstallationIdentityStatus.unavailable,
    );
  }
}

/// Punto de bootstrap aislable: la inicialización anterior absorbe los fallos
/// recuperables y siempre permite ejecutar el arranque de la aplicación local.
Future<InstallationIdentityInitialization> bootstrapWithInstallationIdentity({
  InstallationClientIdStore? store,
  InstallationIdentityDiagnostic? diagnostic,
  required void Function() continueStartup,
}) async {
  final result = await initializeInstallationIdentity(
    store: store,
    diagnostic: diagnostic,
  );
  continueStartup();
  return result;
}
