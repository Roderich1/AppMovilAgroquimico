import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/sync_access.dart';
import 'auth_api_exception.dart';
import 'first_activation_providers.dart';
import 'refresh_guard.dart';
import 'remote_session_coordinator.dart';
import 'secure_session_store.dart';

final refreshGuardProvider = Provider<RefreshGuard>(
  (ref) => const AndroidRefreshGuard(),
);

/// A local-only read for the dashboard. It never constructs AuthV2Api.
final refreshGuardStateProvider = FutureProvider<bool>(
  (ref) => ref.watch(refreshGuardProvider).isQuarantined(),
);

final storedSessionReaderProvider =
    Provider<Future<SessionReadResult> Function()>((ref) {
      final identityStore = ref.watch(installationClientIdStoreProvider);
      return () =>
          SecureSessionStore.android(identityStore: identityStore).read();
    });

final remoteSessionProvider =
    NotifierProvider<RemoteSessionController, RemoteSessionState>(
      RemoteSessionController.new,
    );

class RemoteSessionController extends Notifier<RemoteSessionState> {
  late RemoteSessionCoordinator _coordinator;
  Future<RemoteSessionState?>? _silentRefresh;

  @override
  RemoteSessionState build() {
    _coordinator = RemoteSessionCoordinator(
      readSession: ref.read(storedSessionReaderProvider),
      secureSession: ref.read(secureSessionCommitProvider),
      guard: ref.read(refreshGuardProvider),
      apiFactory: () {
        if (ref.read(apiEndpointConfigProvider) == null) {
          throw const AuthApiException(AuthApiErrorKind.configuration);
        }
        return ref.read(authV2ApiProvider);
      },
      onStateChanged: (next) => state = next,
      // Sólo en memoria, para Sync v1 (nunca se persiste).
      onAccessVerified: ref.read(syncAccessHolderProvider).accept,
    );
    return _coordinator.state;
  }

  Future<RemoteSessionState> verifyOnline() async {
    final silent = _silentRefresh;
    if (silent != null) {
      final result = await silent;
      if (result != null &&
          result.phase != RemoteSessionPhase.remoteAvailable) {
        return result;
      }
    }
    final access = ref.read(syncAccessHolderProvider);
    if (access.current == null && access.enableGeneralAccess()) {
      return const RemoteSessionState(RemoteSessionPhase.remoteAvailable);
    }
    final result = await _coordinator.refreshOnDemand();
    ref.invalidate(refreshGuardStateProvider);
    return result;
  }

  Future<RemoteSessionState?> renewForUnionReads(
    ForegroundSessionCheck check,
  ) => _silentRefresh ??= _coordinator
      .refreshInForeground(
        check,
        onVerified: (token, member, tenant) => ref
            .read(syncAccessHolderProvider)
            .acceptForReads(token, member, tenant, check.contextIsCurrent),
      )
      .whenComplete(() {
        _silentRefresh = null;
        if (ref.mounted) ref.invalidate(refreshGuardStateProvider);
      });

  /// Acredita la cuenta de la sesión guardada sin cambiarla (F03, PIN).
  Future<bool> confirmAccount({
    required String email,
    required String password,
  }) => _coordinator.confirmAccount(email: email, password: password);

  Future<RemoteSessionState> reauthenticate({
    required String email,
    required String password,
  }) async {
    final result = await _coordinator.reauthenticate(
      email: email,
      password: password,
    );
    ref.invalidate(refreshGuardStateProvider);
    return result;
  }
}
