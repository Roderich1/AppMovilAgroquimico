import 'auth_api_exception.dart';
import 'auth_v2_api.dart';
import 'auth_v2_models.dart';
import 'first_activation_coordinator.dart';
import 'refresh_guard.dart';
import 'secure_session_store.dart';

enum RemoteSessionPhase {
  idle,
  refreshing,
  reauthenticating,
  remoteAvailable,
  requiresReauthentication,
  outcomeUnknown,
  configurationUnavailable,
  registrationRejected,
  guardUnavailable,
}

enum RemoteSessionProblem {
  noReadableSession,
  quarantined,
  invalidCredentials,
  rejected,
  contextMismatch,
  remoteOutcomeUnknown,
  localCommitFailed,
  localCommitUnknown,
  guardFailure,
  configuration,
  alreadyRunning,
}

/// Presentation state never carries a credential, identifier, or HTTP body.
class RemoteSessionState {
  const RemoteSessionState(
    this.phase, {
    this.problem,
    this.cleanupUnconfirmed = false,
  });

  final RemoteSessionPhase phase;
  final RemoteSessionProblem? problem;
  final bool cleanupUnconfirmed;

  bool get isBusy =>
      phase == RemoteSessionPhase.refreshing ||
      phase == RemoteSessionPhase.reauthenticating;

  String get safeMessage => switch (phase) {
    RemoteSessionPhase.idle => 'El acceso en línea todavía no se verificó.',
    RemoteSessionPhase.refreshing => 'Verificando acceso en línea…',
    RemoteSessionPhase.reauthenticating => 'Verificando credenciales…',
    RemoteSessionPhase.remoteAvailable =>
      'Acceso en línea verificado para esta sesión.',
    RemoteSessionPhase.configurationUnavailable => 'La conexión segura todavía no está configurada. Sus datos locales siguen disponibles.',
    RemoteSessionPhase.outcomeUnknown => 'El resultado remoto no puede confirmarse. No se reutilizará la credencial anterior. Sus datos locales siguen disponibles.',
    RemoteSessionPhase.registrationRejected => 'La vinculación de este dispositivo no fue aceptada. Se necesita revisión para usar funciones en línea.',
    RemoteSessionPhase.guardUnavailable => 'No se pudo verificar la protección de la sesión. Las funciones en línea permanecen bloqueadas.',
    RemoteSessionPhase.requiresReauthentication =>
      problem == RemoteSessionProblem.invalidCredentials
          ? 'Revise el correo y la contraseña. Sus datos locales siguen disponibles.'
          : 'Se requiere volver a autenticar para las funciones en línea. Sus datos locales siguen disponibles.',
  };

  @override
  String toString() =>
      'RemoteSessionState(${phase.name}, ${problem?.name}, cleanupUnconfirmed: $cleanupUnconfirmed)';
}

class _RemoteAbort implements Exception {
  const _RemoteAbort(this.phase, this.problem);
  final RemoteSessionPhase phase;
  final RemoteSessionProblem problem;
}

/// Both operations are explicit user actions. No caller at startup invokes an
/// HTTP method. The guard is durably committed before the old refresh can be
/// sent, and neither this class nor the UI ever retries that credential.
class RemoteSessionCoordinator {
  RemoteSessionCoordinator({
    required Future<SessionReadResult> Function() readSession,
    required SecureSessionCommitPort secureSession,
    required RefreshGuard guard,
    required AuthV2Api Function() apiFactory,
    DateTime Function()? clock,
    void Function(RemoteSessionState)? onStateChanged,
  }) : _readSession = readSession,
       _secureSession = secureSession,
       _guard = guard,
       _apiFactory = apiFactory,
       _clock = clock ?? DateTime.now,
       _onStateChanged = onStateChanged;

  final Future<SessionReadResult> Function() _readSession;
  final SecureSessionCommitPort _secureSession;
  final RefreshGuard _guard;
  final AuthV2Api Function() _apiFactory;
  final DateTime Function() _clock;
  final void Function(RemoteSessionState)? _onStateChanged;
  RemoteSessionState _state = const RemoteSessionState(RemoteSessionPhase.idle);
  bool _running = false;
  static bool _isolateRemoteOperationActive = false;

  RemoteSessionState get state => _state;

  Future<RemoteSessionState> refreshOnDemand() async {
    if (_running || _isolateRemoteOperationActive) return _alreadyRunning();
    _running = true;
    _isolateRemoteOperationActive = true;
    _emit(const RemoteSessionState(RemoteSessionPhase.refreshing));
    var mayHaveSent = false;
    var committing = false;
    try {
      final stored = await _requireStoredSession();
      // Constructing the API validates HTTPS before quarantine or network.
      final api = _apiFactory();
      if (await _guard.isQuarantined()) {
        throw const _RemoteAbort(
          RemoteSessionPhase.requiresReauthentication,
          RemoteSessionProblem.quarantined,
        );
      }
      try {
        await _guard.quarantine();
      } on Object {
        throw const _RemoteAbort(
          RemoteSessionPhase.guardUnavailable,
          RemoteSessionProblem.guardFailure,
        );
      }
      // From this point the old token is never eligible for another request.
      mayHaveSent = true;
      final response = await api.refresh(stored.refreshToken);
      _validateRefresh(response, stored);
      committing = true;
      await _secureSession.commitAndVerify(
        _candidate(response, stored, stored.sessionId),
      );
      // A lost clear acknowledgement is fail-closed. The new token is already
      // durably committed, but no remote availability is claimed.
      try {
        await _guard.clear();
      } on Object {
        throw const _RemoteAbort(
          RemoteSessionPhase.requiresReauthentication,
          RemoteSessionProblem.guardFailure,
        );
      }
      return _emit(
        const RemoteSessionState(RemoteSessionPhase.remoteAvailable),
      );
    } on _RemoteAbort catch (error) {
      return _emit(RemoteSessionState(error.phase, problem: error.problem));
    } on SecureSessionCommitOutcomeUnknown {
      return _emit(
        const RemoteSessionState(
          RemoteSessionPhase.requiresReauthentication,
          problem: RemoteSessionProblem.localCommitUnknown,
        ),
      );
    } on AuthApiException catch (error) {
      if (!mayHaveSent && error.kind == AuthApiErrorKind.configuration) {
        return _emit(
          const RemoteSessionState(
            RemoteSessionPhase.configurationUnavailable,
            problem: RemoteSessionProblem.configuration,
          ),
        );
      }
      if (error.kind == AuthApiErrorKind.network ||
          error.kind == AuthApiErrorKind.timeout ||
          error.kind == AuthApiErrorKind.invalidResponse) {
        return _emit(
          const RemoteSessionState(
            RemoteSessionPhase.outcomeUnknown,
            problem: RemoteSessionProblem.remoteOutcomeUnknown,
          ),
        );
      }
      return _emit(
        const RemoteSessionState(
          RemoteSessionPhase.requiresReauthentication,
          problem: RemoteSessionProblem.rejected,
        ),
      );
    } on Object {
      return _emit(
        RemoteSessionState(
          committing || mayHaveSent
              ? RemoteSessionPhase.requiresReauthentication
              : RemoteSessionPhase.guardUnavailable,
          problem: committing
              ? RemoteSessionProblem.localCommitFailed
              : RemoteSessionProblem.guardFailure,
        ),
      );
    } finally {
      _running = false;
      _isolateRemoteOperationActive = false;
    }
  }

  Future<RemoteSessionState> reauthenticate({
    required String email,
    required String password,
  }) async {
    if (_running || _isolateRemoteOperationActive) return _alreadyRunning();
    _running = true;
    _isolateRemoteOperationActive = true;
    _emit(const RemoteSessionState(RemoteSessionPhase.reauthenticating));
    AuthV2Api? api;
    V2AuthResponse? login;
    var committing = false;
    var stage = 'preflight';
    try {
      final stored = await _requireStoredSession();
      api = _apiFactory();
      stage = 'guard';
      if (!await _guard.isQuarantined()) {
        throw const _RemoteAbort(
          RemoteSessionPhase.requiresReauthentication,
          RemoteSessionProblem.quarantined,
        );
      }
      stage = 'login';
      login = await api.login(LoginV2Request(email: email, password: password));
      _validateLogin(login, stored);
      stage = 'bind';
      final binding = await api.bindSessionClient(
        accessToken: login.accessToken,
        registrationId: stored.registrationId,
      );
      if (binding.status != 'ACTIVE' ||
          binding.registrationId != stored.registrationId) {
        throw const _RemoteAbort(
          RemoteSessionPhase.registrationRejected,
          RemoteSessionProblem.contextMismatch,
        );
      }
      stage = 'me';
      final current = await api.currentContext(login.accessToken);
      _validateCurrent(login, current, stored);
      stage = 'commit';
      committing = true;
      await _secureSession.commitAndVerify(
        _candidate(login, stored, current.session.id),
      );
      stage = 'clear';
      await _guard.clear();
      return _emit(
        const RemoteSessionState(RemoteSessionPhase.remoteAvailable),
      );
    } on _RemoteAbort catch (error) {
      final unconfirmed = await _cleanupNewLogin(api, login, committing);
      return _emit(
        RemoteSessionState(
          error.phase,
          problem: error.problem,
          cleanupUnconfirmed: unconfirmed,
        ),
      );
    } on SecureSessionCommitOutcomeUnknown {
      return _emit(
        const RemoteSessionState(
          RemoteSessionPhase.requiresReauthentication,
          problem: RemoteSessionProblem.localCommitUnknown,
        ),
      );
    } on AuthApiException catch (error) {
      final unknown =
          error.kind == AuthApiErrorKind.network ||
          error.kind == AuthApiErrorKind.timeout ||
          error.kind == AuthApiErrorKind.invalidResponse;
      final unconfirmed = await _cleanupNewLogin(api, login, committing);
      return _emit(
        RemoteSessionState(
          stage == 'preflight' && error.kind == AuthApiErrorKind.configuration
              ? RemoteSessionPhase.configurationUnavailable
              : stage == 'bind' &&
                    (error.kind == AuthApiErrorKind.unauthorized ||
                        error.kind == AuthApiErrorKind.notFound ||
                        error.kind == AuthApiErrorKind.conflict)
              ? RemoteSessionPhase.registrationRejected
              : unknown
              ? RemoteSessionPhase.outcomeUnknown
              : RemoteSessionPhase.requiresReauthentication,
          problem:
              stage == 'login' && error.kind == AuthApiErrorKind.unauthorized
              ? RemoteSessionProblem.invalidCredentials
              : unknown
              ? RemoteSessionProblem.remoteOutcomeUnknown
              : RemoteSessionProblem.rejected,
          cleanupUnconfirmed: unconfirmed,
        ),
      );
    } on Object {
      // No automatic retry of login, bind, /me, or a lost secure commit ack.
      final unconfirmed = await _cleanupNewLogin(api, login, committing);
      return _emit(
        RemoteSessionState(
          stage == 'preflight' || stage == 'guard'
              ? RemoteSessionPhase.guardUnavailable
              : committing
              ? RemoteSessionPhase.requiresReauthentication
              : RemoteSessionPhase.outcomeUnknown,
          problem: stage == 'preflight' || stage == 'guard' || stage == 'clear'
              ? RemoteSessionProblem.guardFailure
              : committing
              ? RemoteSessionProblem.localCommitFailed
              : RemoteSessionProblem.remoteOutcomeUnknown,
          cleanupUnconfirmed: unconfirmed,
        ),
      );
    } finally {
      _running = false;
      _isolateRemoteOperationActive = false;
    }
  }

  Future<StoredSession> _requireStoredSession() async {
    final read = await _readSession();
    if (read.status != SessionReadStatus.available || read.session == null) {
      throw const _RemoteAbort(
        RemoteSessionPhase.requiresReauthentication,
        RemoteSessionProblem.noReadableSession,
      );
    }
    return read.session!;
  }

  void _validateRefresh(V2AuthResponse response, StoredSession stored) {
    final context = response.context;
    if (!_activeFarmer(context) ||
        response.refreshToken == stored.refreshToken ||
        context.account.id != stored.accountId ||
        context.member.id != stored.memberId ||
        context.tenant.id != stored.tenantId ||
        context.session.id != stored.sessionId ||
        context.session.clientRegistrationId != stored.registrationId ||
        !response.sessionExpiresAt.isAtSameMomentAs(
          context.session.expiresAt,
        ) ||
        !response.sessionExpiresAt.isAtSameMomentAs(stored.expiresAt) ||
        !response.sessionExpiresAt.isAfter(_clock())) {
      throw const _RemoteAbort(
        RemoteSessionPhase.requiresReauthentication,
        RemoteSessionProblem.contextMismatch,
      );
    }
  }

  void _validateLogin(V2AuthResponse login, StoredSession stored) {
    final context = login.context;
    if (!_activeFarmer(context) ||
        context.session.clientRegistrationId != null ||
        context.account.id != stored.accountId ||
        context.member.id != stored.memberId ||
        context.tenant.id != stored.tenantId ||
        !context.session.expiresAt.isAtSameMomentAs(login.sessionExpiresAt) ||
        !login.sessionExpiresAt.isAfter(_clock())) {
      throw const _RemoteAbort(
        RemoteSessionPhase.requiresReauthentication,
        RemoteSessionProblem.contextMismatch,
      );
    }
  }

  void _validateCurrent(
    V2AuthResponse login,
    V2AuthContext current,
    StoredSession stored,
  ) {
    if (!_activeFarmer(current) ||
        current.account.id != stored.accountId ||
        current.member.id != stored.memberId ||
        current.tenant.id != stored.tenantId ||
        current.session.id != login.context.session.id ||
        current.session.clientRegistrationId != stored.registrationId ||
        !current.session.expiresAt.isAtSameMomentAs(login.sessionExpiresAt)) {
      throw const _RemoteAbort(
        RemoteSessionPhase.requiresReauthentication,
        RemoteSessionProblem.contextMismatch,
      );
    }
  }

  bool _activeFarmer(V2AuthContext context) =>
      context.role == 'AGRICULTOR' &&
      context.member.role == 'AGRICULTOR' &&
      context.account.isActive &&
      context.member.isActive &&
      context.tenant.isActive &&
      context.session.status == 'ACTIVE' &&
      context.session.refreshTransport == 'BODY';

  SessionCommitCandidate _candidate(
    V2AuthResponse response,
    StoredSession stored,
    String sessionId,
  ) => SessionCommitCandidate(
    refreshToken: response.refreshToken,
    installationClientId: stored.installationClientId,
    registrationId: stored.registrationId,
    accountId: stored.accountId,
    memberId: stored.memberId,
    tenantId: stored.tenantId,
    sessionId: sessionId,
    expiresAt: response.sessionExpiresAt,
  );

  Future<bool> _cleanupNewLogin(
    AuthV2Api? api,
    V2AuthResponse? login,
    bool committing,
  ) async {
    if (api == null || login == null || committing) return false;
    try {
      await api.logout(refreshToken: login.refreshToken);
      return false;
    } on Object {
      return true;
    }
  }

  RemoteSessionState _alreadyRunning() => const RemoteSessionState(
    RemoteSessionPhase.requiresReauthentication,
    problem: RemoteSessionProblem.alreadyRunning,
  );

  RemoteSessionState _emit(RemoteSessionState next) {
    _state = next;
    try {
      _onStateChanged?.call(next);
    } on Object {
      // A presentation observer cannot change the security outcome.
    }
    return next;
  }
}
