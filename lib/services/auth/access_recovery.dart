// F03 «Recuperar acceso» (docs/architecture/F03_RECUPERACION_IDENTIDAD_LOCAL.md
// §2–§3). Sólo crea o retira credenciales de la sesión segura: nunca borra ni
// reescribe SQLite, titulares, vínculos, historial, outbox ni archivos del
// respaldo; no libera una cola RESTORE_PAUSED ni dispara publicaciones.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/installation_access.dart';
import '../../installation_access.dart';
import '../sync/sync_access.dart';
import 'auth_api_exception.dart';
import 'auth_v2_api.dart';
import 'existing_session_providers.dart';
import 'existing_session_startup.dart';
import 'first_activation_coordinator.dart';
import 'first_activation_providers.dart';
import 'secure_session_store.dart';

/// Qué ofrece «Recuperar acceso» en cada estado (§2).
enum AccessRecoveryMode {
  /// Nada que recuperar desde aquí (la activación o la elección del titular
  /// existentes cubren el estado, o la sesión es legible y basta `/reauth`).
  none,

  /// Inicio de sesión del titular: el Member y el tenant deben ser los del
  /// vínculo activo. Instalación activada con sesión ausente o ilegible, o
  /// base restaurada en otra instalación.
  signInAsOwner,

  /// Base nueva sin vínculo y sesión ilegible: se rehace sólo la sesión; el
  /// titular se elige después (no se habilitan operaciones antes).
  rebuildSessionOnly,

  /// La sesión legible es de otro Member o tenant: primero salir de ella.
  signOutForeignSession,

  /// El almacenamiento seguro no está disponible: no se reemplaza; reintentar.
  storageUnavailable,
}

bool _unreadable(ExistingSessionStartupState session) =>
    session == ExistingSessionStartupState.corrupt ||
    session == ExistingSessionStartupState.incompatible;

AccessRecoveryMode accessRecoveryModeFor(
  InstallationAccessState? access,
  ExistingSessionStartupState session,
) {
  switch (access) {
    case InstallationAccessState.activatedSessionUnavailable:
    case InstallationAccessState.restoredRequiresActivation:
      if (session == ExistingSessionStartupState.unavailable) {
        return AccessRecoveryMode.storageUnavailable;
      }
      return session == ExistingSessionStartupState.noLocalSession ||
              _unreadable(session)
          ? AccessRecoveryMode.signInAsOwner
          : AccessRecoveryMode.none;
    case InstallationAccessState.sessionDamagedNotActivated:
      if (session == ExistingSessionStartupState.unavailable) {
        return AccessRecoveryMode.storageUnavailable;
      }
      return _unreadable(session)
          ? AccessRecoveryMode.rebuildSessionOnly
          : AccessRecoveryMode.none;
    case InstallationAccessState.identityMismatch:
      return AccessRecoveryMode.signOutForeignSession;
    case InstallationAccessState.newRequiresActivation:
    case InstallationAccessState.activationPendingOwner:
    case InstallationAccessState.activated:
    case InstallationAccessState.legacyUnbound:
    case null:
      return AccessRecoveryMode.none;
  }
}

/// El mismo almacén Android que el de la activación, como puerto de reemplazo.
final secureSessionReplacementProvider =
    Provider<UnreadableSessionReplacementPort>(
      (ref) => SecureSessionStore.android(
        identityStore: ref.watch(installationClientIdStoreProvider),
      ),
    );

/// Lectura y borrado de la sesión segura para «Salir de esta sesión».
abstract interface class StoredSessionAccess {
  Future<SessionReadResult> read();
  Future<void> delete();
}

class _AndroidStoredSessionAccess implements StoredSessionAccess {
  _AndroidStoredSessionAccess(this._store);

  final SecureSessionStore _store;

  @override
  Future<SessionReadResult> read() => _store.read();

  @override
  Future<void> delete() => _store.delete();
}

final storedSessionAccessProvider = Provider<StoredSessionAccess>(
  (ref) => _AndroidStoredSessionAccess(
    SecureSessionStore.android(
      identityStore: ref.watch(installationClientIdStoreProvider),
    ),
  ),
);

enum AccessRecoveryProblem { notApplicable, missingBinding }

/// Resultado de «Recuperar acceso». [activation] trae el detalle seguro de la
/// activación subyacente (sin credenciales).
class AccessRecoveryResult {
  const AccessRecoveryResult({this.activation, this.problem});

  final FirstActivationState? activation;
  final AccessRecoveryProblem? problem;

  bool get isCompleted => activation?.isCompleted ?? false;

  String get safeMessage => switch (problem) {
    AccessRecoveryProblem.notApplicable =>
      'En este estado no hace falta recuperar el acceso desde aquí.',
    AccessRecoveryProblem.missingBinding =>
      'No se encontró el titular de estos datos. No se cambió nada.',
    null => activation?.problem?.safeMessage ?? '',
  };
}

final accessRecoveryProvider =
    NotifierProvider<AccessRecoveryController, FirstActivationState>(
      AccessRecoveryController.new,
    );

/// Una recuperación a la vez. Reutiliza la primera activación con dos
/// condiciones (§3): el ámbito del titular, que se comprueba antes de
/// registrar el cliente, y el reemplazo de una sesión ilegible.
class AccessRecoveryController extends Notifier<FirstActivationState> {
  late FirstActivationCoordinator _coordinator;

  @override
  FirstActivationState build() {
    _coordinator = FirstActivationCoordinator(
      identity: ref.watch(installationIdentityProvider),
      identityStore: ref.watch(installationClientIdStoreProvider),
      apiFactory: () {
        if (ref.read(apiEndpointConfigProvider) == null) {
          throw const AuthApiException(AuthApiErrorKind.configuration);
        }
        return ref.read(authV2ApiProvider);
      },
      secureSession: ref.watch(secureSessionCommitProvider),
      sessionReplacement: ref.watch(secureSessionReplacementProvider),
      onStateChanged: (next) => state = next,
    );
    return _coordinator.state;
  }

  Future<AccessRecoveryResult> recover({
    required String email,
    required String password,
  }) async {
    final session = ref.read(effectiveLocalSessionProvider);
    final mode = accessRecoveryModeFor(
      ref.read(installationAccessProvider),
      session,
    );
    if (mode != AccessRecoveryMode.signInAsOwner &&
        mode != AccessRecoveryMode.rebuildSessionOnly) {
      return const AccessRecoveryResult(
        problem: AccessRecoveryProblem.notApplicable,
      );
    }
    OwnerScope? required;
    if (mode == AccessRecoveryMode.signInAsOwner) {
      required = ref.read(installationAccessProvider.notifier).boundScope;
      if (required == null) {
        return const AccessRecoveryResult(
          problem: AccessRecoveryProblem.missingBinding,
        );
      }
    }
    final result = await _coordinator.activate(
      email: email,
      password: password,
      requiredScope: required,
      replaceUnreadableSession: _unreadable(session),
      requiredScopeStillValid: () =>
          ref.read(installationAccessProvider.notifier).boundScope == required,
    );
    if (result.isCompleted) {
      // Sólo tras commitAndVerify: el acceso se recalcula con la sesión nueva.
      ref.read(runtimeSessionTransitionProvider.notifier).recovered();
    }
    return AccessRecoveryResult(activation: result);
  }

  bool requestCancel() => _coordinator.requestCancel();
}

enum ForeignSignOutOutcome {
  /// La sesión ajena se borró de forma comprobada.
  signedOut,

  /// No había sesión legible que retirar: no se cambió nada.
  nothingToSignOut,

  /// El borrado local no se pudo confirmar: el estado anterior se conserva.
  deletionUncertain,
}

/// «Salir de esta sesión» (§2, identityMismatch). Intenta cerrar la sesión en
/// el servidor con su refresh guardado y después la borra del almacén seguro.
/// No lee ni cambia SQLite: ningún dato se adopta ni se pierde.
class ForeignSessionSignOut {
  ForeignSessionSignOut({
    required StoredSessionAccess store,
    required AuthV2Api Function() apiFactory,
    required void Function() clearVerifiedAccess,
  }) : _store = store,
       _apiFactory = apiFactory,
       _clearVerifiedAccess = clearVerifiedAccess;

  final StoredSessionAccess _store;
  final AuthV2Api Function() _apiFactory;
  final void Function() _clearVerifiedAccess;

  /// [remoteConfirmed] informa si el servidor confirmó el cierre (intento
  /// único, sin reintentos). La salida local no depende de él.
  Future<({ForeignSignOutOutcome outcome, bool remoteConfirmed})>
  signOut() async {
    final read = await _store.read();
    if (read.status != SessionReadStatus.available || read.session == null) {
      return (
        outcome: ForeignSignOutOutcome.nothingToSignOut,
        remoteConfirmed: false,
      );
    }
    // El acceso verificado en memoria de esa cuenta deja de valer ya.
    _clearVerifiedAccess();
    var remoteConfirmed = false;
    try {
      await _apiFactory().logout(refreshToken: read.session!.refreshToken);
      remoteConfirmed = true;
    } on Object {
      // Sin red o rechazo: la salida local sigue; el servidor la caduca.
    }
    try {
      await _store.delete();
    } on Object {
      return (
        outcome: ForeignSignOutOutcome.deletionUncertain,
        remoteConfirmed: remoteConfirmed,
      );
    }
    return (
      outcome: ForeignSignOutOutcome.signedOut,
      remoteConfirmed: remoteConfirmed,
    );
  }
}

final foreignSessionSignOutProvider = Provider<ForeignSessionSignOut>(
  (ref) => ForeignSessionSignOut(
    store: ref.watch(storedSessionAccessProvider),
    apiFactory: () {
      if (ref.read(apiEndpointConfigProvider) == null) {
        throw const AuthApiException(AuthApiErrorKind.configuration);
      }
      return ref.read(authV2ApiProvider);
    },
    clearVerifiedAccess: ref.read(syncAccessHolderProvider).clear,
  ),
);

/// Ejecuta la salida y, si se confirmó, recalcula el acceso sin la sesión.
Future<({ForeignSignOutOutcome outcome, bool remoteConfirmed})>
signOutForeignSession(WidgetRef ref) async {
  final result = await ref.read(foreignSessionSignOutProvider).signOut();
  if (result.outcome == ForeignSignOutOutcome.signedOut) {
    ref.read(runtimeSessionTransitionProvider.notifier).signedOut();
  }
  return result;
}
