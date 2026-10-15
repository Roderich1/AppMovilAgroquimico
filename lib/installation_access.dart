// Estado de acceso de la instalación en tiempo de ejecución (#76, v1.5
// §3.11.6). Une lo que vive en SQLite (origen, titular, instalación activada)
// con la sesión segura leída en el arranque, y lo recalcula tras una
// activación o un vínculo de titular. No guarda credenciales ni las registra.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/app_log.dart';
import 'data/owner_binding_store.dart';
import 'domain/installation_access.dart';
import 'services/auth/existing_session_providers.dart';
import 'services/auth/existing_session_startup.dart';
import 'services/auth/first_activation_providers.dart';
import 'services/auth/secure_session_store.dart';

/// Ámbito (Member, tenant) de la sesión legible del arranque. main.dart lo
/// sobrescribe; sólo vive en memoria.
final startupSessionScopeProvider = Provider<OwnerScope?>((ref) => null);

/// `installationReference` de la identidad de instalación, o null si la
/// identidad está dañada o no disponible. main.dart lo sobrescribe.
final installationRefProvider = Provider<String?>((ref) => null);

/// Relee la sesión segura tras una activación en esta ejecución para conocer
/// su ámbito. Devuelve null si no es legible.
final sessionScopeReaderProvider = Provider<Future<OwnerScope?> Function()>((
  ref,
) {
  final store = ref.watch(installationClientIdStoreProvider);
  return () async =>
      scopeOf(await SecureSessionStore.android(identityStore: store).read());
});

OwnerScope? scopeOf(SessionReadResult result) {
  final session = result.session;
  if (result.status != SessionReadStatus.available || session == null) {
    return null;
  }
  return OwnerScope(memberId: session.memberId, tenantId: session.tenantId);
}

LocalSessionCondition sessionConditionOf(
  ExistingSessionStartupState state,
) => switch (state) {
  ExistingSessionStartupState.noLocalSession => LocalSessionCondition.absent,
  ExistingSessionStartupState.localSessionAvailable ||
  ExistingSessionStartupState.localSessionExpired =>
    LocalSessionCondition.readable,
  ExistingSessionStartupState.corrupt ||
  ExistingSessionStartupState.unavailable ||
  ExistingSessionStartupState.incompatible => LocalSessionCondition.unreadable,
};

/// null mientras se evalúa: la compuerta y el router fallan cerrados.
class InstallationAccessController extends Notifier<InstallationAccessState?> {
  OwnerScope? _scope;
  bool _scopeLoaded = false;

  /// Ámbito de la sesión legible vigente (para vincular el titular).
  OwnerScope? get sessionScope => _scope;

  @override
  InstallationAccessState? build() {
    ref.listen<bool>(runtimeSecureCommitCompletedProvider, (_, done) {
      if (done) refresh(rereadSession: true);
    });
    Future.microtask(refresh);
    return null;
  }

  /// Recalcula el estado. Ante un error (base o almacenamiento seguro no
  /// disponibles) falla cerrado: el estado queda null y la pantalla de acceso
  /// ofrece reintentar. Nunca borra ni reescribe datos por un error.
  Future<InstallationAccessState?> refresh({bool rereadSession = false}) async {
    try {
      return await _evaluate(rereadSession: rereadSession);
    } on Object catch (error) {
      AppLog.error(
        'No se pudo evaluar el acceso de la instalación (${error.runtimeType})',
      );
      return state;
    }
  }

  Future<InstallationAccessState> _evaluate({
    required bool rereadSession,
  }) async {
    if (rereadSession) {
      try {
        _scope = await ref.read(sessionScopeReaderProvider)();
      } on Object {
        // Sesión no legible tras activar: se clasifica sin ámbito (falla
        // cerrado), sin interpretar el error como instalación nueva.
        _scope = null;
      }
      _scopeLoaded = true;
    } else if (!_scopeLoaded) {
      _scope = ref.read(startupSessionScopeProvider);
      _scopeLoaded = true;
    }
    final store = OwnerBindingStore(ref.read(repositoryProvider).appDatabase);
    final currentRef = ref.read(installationRefProvider);
    final inputs = await store.accessInputs(
      session: sessionConditionOf(ref.read(effectiveLocalSessionProvider)),
      sessionScope: _scope,
      currentInstallationRef: currentRef,
    );
    final next = classifyInstallation(inputs);
    // El mismo Member reactivó en otra instalación: se registra ésta. No toca
    // el vínculo ni ninguna operación.
    if (next == InstallationAccessState.activated &&
        currentRef != null &&
        inputs.activatedInstallationRef != currentRef) {
      await store.recordActivatedInstallation(
        sessionScope: _scope!,
        installationRef: currentRef,
      );
    }
    state = next;
    return next;
  }
}

final installationAccessProvider =
    NotifierProvider<InstallationAccessController, InstallationAccessState?>(
      InstallationAccessController.new,
    );

/// Estado fijo para pruebas y para fijar un estado conocido.
class FixedInstallationAccess extends InstallationAccessController {
  FixedInstallationAccess(this.fixed, {OwnerScope? scope})
    : _fixedScope = scope;

  final InstallationAccessState fixed;
  final OwnerScope? _fixedScope;

  @override
  OwnerScope? get sessionScope => _fixedScope;

  @override
  InstallationAccessState? build() => fixed;

  @override
  Future<InstallationAccessState?> refresh({
    bool rereadSession = false,
  }) async => fixed;
}
