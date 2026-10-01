import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../data/installation_client_id_store.dart';
import '../../data/installation_identity_initializer.dart';
import 'api_endpoint_config.dart';
import 'auth_api_exception.dart';
import 'auth_http_client.dart';
import 'auth_v2_api.dart';
import 'first_activation_coordinator.dart';
import 'secure_session_store.dart';

/// The bootstrap overrides this result. A missing override fails closed for
/// remote activation, without making the local application unavailable.
final installationIdentityProvider =
    Provider<InstallationIdentityInitialization>(
      (ref) => const InstallationIdentityInitialization(
        InstallationIdentityStatus.unavailable,
      ),
    );

final installationClientIdStoreProvider = Provider<InstallationClientIdStore>(
  (ref) => InstallationClientIdStore(),
);

final apiEndpointConfigProvider = Provider<ApiEndpointConfig?>((ref) {
  try {
    return ApiEndpointConfig.fromEnvironment();
  } on AuthApiException {
    // Configuration is a typed activation failure, not a broken provider.
    return null;
  }
});

final authHttpTransportProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final authHttpClientProvider = Provider<AuthHttpClient>(
  (ref) => AuthHttpClient(
    config:
        ref.watch(apiEndpointConfigProvider) ??
        (throw const AuthApiException(AuthApiErrorKind.configuration)),
    client: ref.watch(authHttpTransportProvider),
  ),
);

final authV2ApiProvider = Provider<AuthV2Api>(
  (ref) => AuthV2Api(ref.watch(authHttpClientProvider)),
);

/// The production binding is deliberately Android Keystore-backed. Tests may
/// override only this provider; no in-memory session exists in app wiring.
final secureSessionCommitProvider = Provider<SecureSessionCommitPort>(
  (ref) => SecureSessionStore.android(
    identityStore: ref.watch(installationClientIdStoreProvider),
  ),
);

final firstActivationProvider =
    NotifierProvider<FirstActivationController, FirstActivationState>(
      FirstActivationController.new,
    );

class FirstActivationController extends Notifier<FirstActivationState> {
  late FirstActivationCoordinator _coordinator;

  @override
  FirstActivationState build() {
    _coordinator = FirstActivationCoordinator(
      identity: ref.watch(installationIdentityProvider),
      identityStore: ref.watch(installationClientIdStoreProvider),
      // Delay URL parsing and transport creation until a real activation.
      apiFactory: () {
        if (ref.read(apiEndpointConfigProvider) == null) {
          throw const AuthApiException(AuthApiErrorKind.configuration);
        }
        return ref.read(authV2ApiProvider);
      },
      secureSession: ref.watch(secureSessionCommitProvider),
      onStateChanged: (next) => state = next,
    );
    return _coordinator.state;
  }

  Future<FirstActivationState> activate({
    required String email,
    required String password,
  }) => _coordinator.activate(email: email, password: password);

  bool requestCancel() => _coordinator.requestCancel();
}
