import 'dart:async';

import 'package:flutter/widgets.dart'
    show AppLifecycleListener, AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../app.dart' show repositoryProvider;
import '../../data/installation_client_id_store.dart';
import '../../data/installation_identity_initializer.dart';
import '../../data/owner_binding_store.dart';
import '../../domain/installation_access.dart';
import '../../installation_access.dart';
import 'activation_owner_evidence.dart';
import 'api_endpoint_config.dart';
import 'auth_api_exception.dart';
import 'auth_http_client.dart';
import 'auth_v2_api.dart';
import 'existing_session_providers.dart';
import 'existing_session_startup.dart' show ExistingSessionStartupState;
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

/// Relojes de la acreditación de activación (F03 §4 bis.3).
final activationEvidenceClockProvider = Provider<ActivationEvidenceClock>(
  (ref) => ActivationEvidenceClock.system(),
);

class FirstActivationController extends Notifier<FirstActivationState> {
  late FirstActivationCoordinator _coordinator;

  // F03 §4 bis.3: la acreditación de activación. Sólo en memoria y sólo la
  // escribe [_issueEvidence]; no hay ningún método público para fijarla. Si
  // este Notifier se recrea, se pierde (falla cerrado).
  ActivationOwnerEvidence? _evidence;
  int _evidenceGeneration = 0;
  AppLifecycleListener? _lifecycle;

  @override
  FirstActivationState build() {
    // Ayudas de anulación (H4): la garantía son las comprobaciones al
    // consumir (OwnerOnlineVerification.fromActivation y enroll).
    ref.listen(runtimeSessionTransitionProvider, (_, __) {
      discardActivationEvidence();
    });
    ref.listen(installationAccessProvider, (_, next) => _onAccess(next));
    ref.onDispose(() {
      _evidence = null;
      _evidenceGeneration++;
      _lifecycle?.dispose();
      _lifecycle = null;
    });
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
  }) async {
    // F03 §2: with a titular already bound, even this entry requires the
    // same Member and tenant (checked before the client is registered).
    // Unknown access (still evaluating or failed): never store a session.
    if (ref.read(installationAccessProvider) == null) {
      const failed = FirstActivationState(
        phase: FirstActivationPhase.failed,
        problem: FirstActivationProblem.unexpected,
      );
      state = failed;
      return failed;
    }
    final requiredScope = ref
        .read(installationAccessProvider.notifier)
        .boundScope;
    // F03 §4 bis (H7): sólo una activación sin sesión previa y sin titular
    // vinculado puede emitir la acreditación. Un intento nuevo anula la
    // anterior.
    discardActivationEvidence();
    final noSessionAtStart =
        ref.read(effectiveLocalSessionProvider) ==
        ExistingSessionStartupState.noLocalSession;
    final result = await _coordinator.activate(
      email: email,
      password: password,
      requiredScope: requiredScope,
      requiredScopeStillValid: () =>
          ref.read(installationAccessProvider.notifier).boundScope ==
          requiredScope,
    );
    // completed is emitted only after commitAndVerify has returned. Keep the
    // local binding coherent even if the activation screen has unmounted.
    if (result.isCompleted) {
      ref.read(runtimeSecureCommitCompletedProvider.notifier).markCompleted();
      // F03: the latest runtime session event (after a possible sign-out).
      if (ref.read(runtimeSessionTransitionProvider) != null) {
        ref.read(runtimeSessionTransitionProvider.notifier).recovered();
      }
      // Después de recovered(): su oyente ya no anula esta acreditación.
      final identity = _coordinator.committedIdentity;
      if (noSessionAtStart && requiredScope == null && identity != null) {
        final clock = ref.read(activationEvidenceClockProvider);
        unawaited(
          _issueEvidence(
            identity,
            issuedAt: clock.now(),
            elapsed: clock.startElapsed(),
            generation: _evidenceGeneration,
          ),
        );
      }
    }
    return result;
  }

  bool requestCancel() => _coordinator.requestCancel();

  /// H7: al recibir `completed`, SQLite (lectura directa) no tiene un vínculo
  /// activo y la base es nueva (no histórica). Sin espera antes de devolver
  /// el resultado: la activación no depende de la acreditación.
  Future<void> _issueEvidence(
    SessionIdentity identity, {
    required DateTime issuedAt,
    required Duration Function() elapsed,
    required int generation,
  }) async {
    try {
      final store = OwnerBindingStore(ref.read(repositoryProvider).appDatabase);
      final origin = await store.origin();
      final binding = await store.activeBinding();
      // H6: el Notifier pudo recrearse o la acreditación anularse mientras.
      if (!ref.mounted || generation != _evidenceGeneration) return;
      if (origin != InstallOrigin.newUnderPolicy || binding != null) return;
      final access = ref.read(installationAccessProvider);
      if (access != InstallationAccessState.newRequiresActivation &&
          access != InstallationAccessState.activationPendingOwner) {
        return;
      }
      if (!_watchLifecycle()) return;
      _evidence = ActivationOwnerEvidence(
        identity: identity,
        issuedAt: issuedAt,
        elapsed: elapsed,
      );
    } on Object {
      // Sin acreditación: el PIN se crea después con la contraseña.
    }
  }

  /// H3: salir de la app (pantalla apagada o cambio de app) la anula.
  bool _watchLifecycle() {
    if (_lifecycle != null) return true;
    try {
      _lifecycle = AppLifecycleListener(
        onStateChange: (state) {
          if (state == AppLifecycleState.hidden ||
              state == AppLifecycleState.paused) {
            discardActivationEvidence();
          }
        },
      );
      return true;
    } on Object {
      return false;
    }
  }

  /// H2: la única secuencia válida es activationPendingOwner → activated con
  /// el vínculo ya atado. Cualquier otro estado la anula.
  void _onAccess(InstallationAccessState? next) {
    final evidence = _evidence;
    if (evidence == null) return;
    final valid =
        next == InstallationAccessState.activationPendingOwner ||
        (next == InstallationAccessState.activated && evidence.binding != null);
    if (!valid) discardActivationEvidence();
  }

  /// Si hay una acreditación de activación sin consumir.
  bool get hasActivationEvidence => _evidence != null;

  /// Retira la acreditación: síncrona, sin ningún await entre leerla y
  /// anularla (F03 §4 bis.3, consumo).
  ActivationOwnerEvidence? takeActivationEvidence() {
    final evidence = _evidence;
    _evidence = null;
    _evidenceGeneration++;
    return evidence;
  }

  /// Ata la acreditación una sola vez al vínculo recién creado (H5). Si no se
  /// puede atar, la anula. false si no hay acreditación o no se ató.
  bool attachOwnerBinding(ActivationBindingRef binding) {
    final evidence = _evidence;
    if (evidence == null) return false;
    if (evidence.attachBinding(binding)) return true;
    discardActivationEvidence();
    return false;
  }

  void discardActivationEvidence() {
    _evidence = null;
    _evidenceGeneration++;
  }
}
