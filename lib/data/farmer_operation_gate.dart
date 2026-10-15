import '../domain/installation_access.dart';
import 'agro_repository.dart' show BusinessRuleException;

/// Se lanza cuando la política de activación no habilita operaciones locales.
class FarmerOperationBlockedException extends BusinessRuleException {
  FarmerOperationBlockedException(InstallationAccessState this.state)
    : super(state.message);

  /// El estado de la instalación todavía se está evaluando.
  FarmerOperationBlockedException.pending()
    : state = null,
      super('Verificando el estado de la instalación. Intente de nuevo.');

  /// null mientras se evalúa.
  final InstallationAccessState? state;
}

/// Compuerta de dominio de la política de activación. [AgroRepository] la
/// consulta al inicio de cada escritura, de modo que ocultar controles en la
/// interfaz no deja una ruta directa para operar sin activación.
class FarmerOperationGate {
  /// Sin restricción: comportamiento anterior a la política. Lo usan las
  /// pruebas del dominio que no tratan la activación; la app instala la
  /// compuerta real en `repositoryProvider`.
  const FarmerOperationGate.unrestricted() : _read = null;

  /// Lee el estado vigente en cada escritura (cambia tras activar o vincular).
  /// Un estado null (aún en evaluación) falla cerrado.
  const FarmerOperationGate(InstallationAccessState? Function() read)
    : _read = read;

  final InstallationAccessState? Function()? _read;

  bool get isUnrestricted => _read == null;

  void ensureAllowed() {
    final read = _read;
    if (read == null) return;
    final state = read();
    if (state == null) throw FarmerOperationBlockedException.pending();
    if (!state.allowsFarmerOperations) {
      throw FarmerOperationBlockedException(state);
    }
  }
}
