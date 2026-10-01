import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    );
    return _coordinator.state;
  }

  Future<RemoteSessionState> verifyOnline() async {
    final result = await _coordinator.refreshOnDemand();
    ref.invalidate(refreshGuardStateProvider);
    return result;
  }

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
