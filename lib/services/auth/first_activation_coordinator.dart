import '../../data/installation_client_id_store.dart';
import '../../data/installation_identity_initializer.dart';
import 'auth_api_exception.dart';
import 'auth_v2_api.dart';
import 'auth_v2_models.dart';

enum FirstActivationPhase {
  idle,
  checkingIdentity,
  preparingClient,
  loggingIn,
  registeringClient,
  bindingSession,
  verifyingContext,
  committingSession,
  cancelling,
  completed,
  failed,
  cancelled,
}

enum FirstActivationProblem {
  identityCorrupt,
  identityUnavailable,
  configuration,
  invalidCredentials,
  invalidRequest,
  unauthorized,
  conflict,
  rateLimited,
  connection,
  timeout,
  invalidResponse,
  contextMismatch,
  secureCommitFailed,
  remoteError,
  unexpected,
  alreadyRunning,
  cancelled,
}

enum RemoteCleanup { notNeeded, confirmed, unconfirmed }

extension FirstActivationProblemMessage on FirstActivationProblem {
  String get safeMessage => switch (this) {
    FirstActivationProblem.identityCorrupt => 'La identidad de esta instalación necesita revisión. Sus datos locales siguen disponibles.',
    FirstActivationProblem.identityUnavailable => 'No se pudo leer la identidad de esta instalación. Puede seguir usando sus datos locales.',
    FirstActivationProblem.configuration =>
      'La conexión segura todavía no está configurada.',
    FirstActivationProblem.invalidCredentials =>
      'Revise el correo y la contraseña antes de intentar nuevamente.',
    FirstActivationProblem.invalidRequest =>
      'La solicitud no es válida. Revise los datos ingresados.',
    FirstActivationProblem.conflict => 'No se pudo vincular esta instalación. Se necesita revisión antes de reintentar.',
    FirstActivationProblem.rateLimited =>
      'Hay demasiados intentos. Espere antes de volver a intentarlo.',
    FirstActivationProblem.connection || FirstActivationProblem.timeout => 'No se pudo confirmar la operación remota. Sus datos locales siguen disponibles.',
    FirstActivationProblem.contextMismatch ||
    FirstActivationProblem.invalidResponse ||
    FirstActivationProblem.unauthorized ||
    FirstActivationProblem.remoteError => 'No se pudo verificar la vinculación de la cuenta. Sus datos locales siguen disponibles.',
    FirstActivationProblem.secureCommitFailed =>
      'La sesión no quedó guardada de forma segura. La activación no finalizó.',
    FirstActivationProblem.alreadyRunning => 'Ya hay una activación en curso.',
    FirstActivationProblem.cancelled =>
      'La activación se canceló sin cambiar sus datos locales.',
    FirstActivationProblem.unexpected => 'No se pudo completar la activación. Sus datos locales siguen disponibles.',
  };
}

/// UI-safe state: deliberately contains no credentials, IDs, URLs or payloads.
class FirstActivationState {
  const FirstActivationState({
    required this.phase,
    this.problem,
    this.cleanup = RemoteCleanup.notNeeded,
    this.remoteOutcomeUnknown = false,
  });

  final FirstActivationPhase phase;
  final FirstActivationProblem? problem;
  final RemoteCleanup cleanup;
  final bool remoteOutcomeUnknown;

  bool get isCompleted => phase == FirstActivationPhase.completed;

  @override
  String toString() =>
      'FirstActivationState(${phase.name}, ${problem?.name}, '
      '${cleanup.name}, remoteOutcomeUnknown: $remoteOutcomeUnknown)';
}

/// Transient hand-off for #20. Never persist or log this object in #19.
class SessionCommitCandidate {
  const SessionCommitCandidate({
    required this.refreshToken,
    required this.installationClientId,
    required this.registrationId,
    required this.accountId,
    required this.memberId,
    required this.tenantId,
    required this.sessionId,
    required this.expiresAt,
  });

  final String refreshToken;
  final String installationClientId;
  final String registrationId;
  final String accountId;
  final String memberId;
  final String tenantId;
  final String sessionId;
  final DateTime expiresAt;

  @override
  String toString() => 'SessionCommitCandidate(redacted)';
}

/// #20 must implement an all-or-none durable, encrypted commit with readback.
/// Returning means the session can be recovered; throwing means no usable
/// credential remains. There is intentionally no production implementation.
abstract interface class SecureSessionCommitPort {
  Future<void> commitAndVerify(SessionCommitCandidate candidate);
}

class _ActivationAbort implements Exception {
  const _ActivationAbort(this.problem);

  final FirstActivationProblem problem;
}

/// One attempt at a time. Nothing in this class changes SQLite or backup.
/// No production route is wired until #20 supplies SecureSessionCommitPort.
class FirstActivationCoordinator {
  FirstActivationCoordinator({
    required InstallationIdentityInitialization identity,
    required InstallationClientIdStore identityStore,
    required AuthV2Api Function() apiFactory,
    required SecureSessionCommitPort secureSession,
    DateTime Function()? clock,
    void Function(FirstActivationState)? onStateChanged,
  }) : _identity = identity,
       _identityStore = identityStore,
       _apiFactory = apiFactory,
       _secureSession = secureSession,
       _clock = clock ?? DateTime.now,
       _onStateChanged = onStateChanged;

  final InstallationIdentityInitialization _identity;
  final InstallationClientIdStore _identityStore;
  final AuthV2Api Function() _apiFactory;
  final SecureSessionCommitPort _secureSession;
  final DateTime Function() _clock;
  final void Function(FirstActivationState)? _onStateChanged;

  FirstActivationState _state = const FirstActivationState(
    phase: FirstActivationPhase.idle,
  );
  bool _running = false;
  bool _cancelRequested = false;
  FirstActivationPhase? _cancelledDuring;

  FirstActivationState get state => _state;

  /// Cancellation is accepted only before the atomic secure commit begins.
  /// The in-flight HTTP request may still finish; cleanup is then attempted.
  bool requestCancel() {
    if (!_running ||
        _state.phase == FirstActivationPhase.committingSession ||
        _cancelRequested) {
      return false;
    }
    _cancelRequested = true;
    _cancelledDuring = _state.phase;
    _emit(const FirstActivationState(phase: FirstActivationPhase.cancelling));
    return true;
  }

  Future<FirstActivationState> activate({
    required String email,
    required String password,
  }) async {
    if (_running) {
      return const FirstActivationState(
        phase: FirstActivationPhase.failed,
        problem: FirstActivationProblem.alreadyRunning,
      );
    }
    _running = true;
    _cancelRequested = false;
    _cancelledDuring = null;
    AuthV2Api? api;
    V2AuthResponse? login;
    FirstActivationProblem? failure;
    var remoteOutcomeUnknown = false;

    try {
      _emit(
        const FirstActivationState(
          phase: FirstActivationPhase.checkingIdentity,
        ),
      );
      if (_identity.status != InstallationIdentityStatus.ready) {
        throw _ActivationAbort(
          _identity.status == InstallationIdentityStatus.corrupt
              ? FirstActivationProblem.identityCorrupt
              : FirstActivationProblem.identityUnavailable,
        );
      }
      final clientId = await _identityStore.read();
      if (clientId == null) {
        throw const _ActivationAbort(
          FirstActivationProblem.identityUnavailable,
        );
      }
      if (!InstallationClientIdStore.isCanonicalUuidV4(clientId)) {
        throw const _ActivationAbort(FirstActivationProblem.identityCorrupt);
      }
      _checkCancellation();

      _emit(
        const FirstActivationState(phase: FirstActivationPhase.preparingClient),
      );
      api = _apiFactory();
      _checkCancellation();

      _emit(const FirstActivationState(phase: FirstActivationPhase.loggingIn));
      login = await api.login(LoginV2Request(email: email, password: password));
      _checkCancellation();
      _validateLogin(login);

      _emit(
        const FirstActivationState(
          phase: FirstActivationPhase.registeringClient,
        ),
      );
      final registration = await api.registerClient(
        accessToken: login.accessToken,
        clientId: clientId,
      );
      _checkCancellation();
      if (registration.status != 'ACTIVE' || registration.revokedAt != null) {
        throw const _ActivationAbort(FirstActivationProblem.contextMismatch);
      }

      _emit(
        const FirstActivationState(phase: FirstActivationPhase.bindingSession),
      );
      final binding = await api.bindSessionClient(
        accessToken: login.accessToken,
        registrationId: registration.registrationId,
      );
      _checkCancellation();
      if (binding.status != 'ACTIVE' ||
          binding.registrationId != registration.registrationId) {
        throw const _ActivationAbort(FirstActivationProblem.contextMismatch);
      }

      _emit(
        const FirstActivationState(
          phase: FirstActivationPhase.verifyingContext,
        ),
      );
      final current = await api.currentContext(login.accessToken);
      _checkCancellation();
      _validateCurrent(login, current, registration.registrationId);

      _emit(
        const FirstActivationState(
          phase: FirstActivationPhase.committingSession,
        ),
      );
      await _secureSession.commitAndVerify(
        SessionCommitCandidate(
          refreshToken: login.refreshToken,
          installationClientId: clientId,
          registrationId: registration.registrationId,
          accountId: current.account.id,
          memberId: current.member.id,
          tenantId: current.tenant.id,
          sessionId: current.session.id,
          expiresAt: login.sessionExpiresAt,
        ),
      );
      _emit(const FirstActivationState(phase: FirstActivationPhase.completed));
    } on _ActivationAbort catch (error) {
      failure = error.problem;
    } on InstallationClientIdCorruptException {
      failure = FirstActivationProblem.identityCorrupt;
    } on AuthApiException catch (error) {
      final failurePhase = _cancelledDuring ?? _state.phase;
      failure = _cancelRequested
          ? FirstActivationProblem.cancelled
          : failurePhase == FirstActivationPhase.committingSession
          ? FirstActivationProblem.secureCommitFailed
          : _problemFor(error, failurePhase);
      remoteOutcomeUnknown = _remoteMayHaveChanged(error.kind, failurePhase);
    } on Object {
      final failurePhase = _cancelledDuring ?? _state.phase;
      failure = _cancelRequested
          ? FirstActivationProblem.cancelled
          : failurePhase == FirstActivationPhase.checkingIdentity
          ? FirstActivationProblem.identityUnavailable
          : failurePhase == FirstActivationPhase.committingSession
          ? FirstActivationProblem.secureCommitFailed
          : FirstActivationProblem.unexpected;
      remoteOutcomeUnknown =
          _cancelRequested &&
          (failurePhase == FirstActivationPhase.loggingIn ||
              failurePhase == FirstActivationPhase.registeringClient ||
              failurePhase == FirstActivationPhase.bindingSession);
    }

    if (failure != null) {
      final cleanup = await _cleanup(api, login);
      _emit(
        FirstActivationState(
          phase: failure == FirstActivationProblem.cancelled
              ? FirstActivationPhase.cancelled
              : FirstActivationPhase.failed,
          problem: failure,
          cleanup: cleanup,
          remoteOutcomeUnknown:
              remoteOutcomeUnknown || cleanup == RemoteCleanup.unconfirmed,
        ),
      );
    }
    _running = false;
    _cancelRequested = false;
    _cancelledDuring = null;
    return _state;
  }

  void _checkCancellation() {
    if (_cancelRequested) {
      throw const _ActivationAbort(FirstActivationProblem.cancelled);
    }
  }

  void _validateLogin(V2AuthResponse login) {
    final context = login.context;
    if (!_isActiveFarmer(context) ||
        context.session.clientRegistrationId != null ||
        !context.session.expiresAt.isAtSameMomentAs(login.sessionExpiresAt) ||
        !login.sessionExpiresAt.isAfter(_clock())) {
      throw const _ActivationAbort(FirstActivationProblem.contextMismatch);
    }
  }

  void _validateCurrent(
    V2AuthResponse login,
    V2AuthContext current,
    String registrationId,
  ) {
    final previous = login.context;
    if (!_isActiveFarmer(current) ||
        current.account.id != previous.account.id ||
        current.account.email != previous.account.email ||
        current.member.id != previous.member.id ||
        current.tenant.id != previous.tenant.id ||
        current.session.id != previous.session.id ||
        current.session.clientRegistrationId != registrationId ||
        !current.session.expiresAt.isAtSameMomentAs(login.sessionExpiresAt) ||
        !login.sessionExpiresAt.isAfter(_clock())) {
      throw const _ActivationAbort(FirstActivationProblem.contextMismatch);
    }
  }

  bool _isActiveFarmer(V2AuthContext context) =>
      context.account.isActive &&
      context.member.isActive &&
      context.tenant.isActive &&
      context.role == 'AGRICULTOR' &&
      context.member.role == context.role &&
      context.session.status == 'ACTIVE' &&
      context.session.refreshTransport == 'BODY';

  Future<RemoteCleanup> _cleanup(AuthV2Api? api, V2AuthResponse? login) async {
    if (api == null || login == null) return RemoteCleanup.notNeeded;
    try {
      // One idempotent attempt, never a blind retry of login/register/bind.
      await api.logout(refreshToken: login.refreshToken);
      return RemoteCleanup.confirmed;
    } on Object {
      return RemoteCleanup.unconfirmed;
    }
  }

  FirstActivationProblem _problemFor(
    AuthApiException error,
    FirstActivationPhase phase,
  ) => switch (error.kind) {
    AuthApiErrorKind.configuration => FirstActivationProblem.configuration,
    AuthApiErrorKind.badRequest => FirstActivationProblem.invalidRequest,
    AuthApiErrorKind.unauthorized =>
      phase == FirstActivationPhase.loggingIn
          ? FirstActivationProblem.invalidCredentials
          : FirstActivationProblem.unauthorized,
    AuthApiErrorKind.conflict => FirstActivationProblem.conflict,
    AuthApiErrorKind.rateLimited => FirstActivationProblem.rateLimited,
    AuthApiErrorKind.network => FirstActivationProblem.connection,
    AuthApiErrorKind.timeout => FirstActivationProblem.timeout,
    AuthApiErrorKind.invalidResponse => FirstActivationProblem.invalidResponse,
    _ => FirstActivationProblem.remoteError,
  };

  bool _remoteMayHaveChanged(
    AuthApiErrorKind kind,
    FirstActivationPhase phase,
  ) =>
      (kind == AuthApiErrorKind.network ||
          kind == AuthApiErrorKind.timeout ||
          kind == AuthApiErrorKind.invalidResponse) &&
      (phase == FirstActivationPhase.loggingIn ||
          phase == FirstActivationPhase.registeringClient ||
          phase == FirstActivationPhase.bindingSession);

  void _emit(FirstActivationState next) {
    _state = next;
    try {
      _onStateChanged?.call(next);
    } on Object {
      // A presentation observer must not abort an authenticated transaction.
    }
  }
}
