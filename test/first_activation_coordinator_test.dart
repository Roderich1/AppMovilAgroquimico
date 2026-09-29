import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/installation_client_id_store.dart';
import 'package:agroquimicos/data/installation_identity_initializer.dart';
import 'package:agroquimicos/services/auth/api_endpoint_config.dart';
import 'package:agroquimicos/services/auth/auth_api_exception.dart';
import 'package:agroquimicos/services/auth/auth_http_client.dart';
import 'package:agroquimicos/services/auth/auth_v2_api.dart';
import 'package:agroquimicos/services/auth/first_activation_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _clientId = '550e8400-e29b-41d4-a716-446655440000';
const _registrationId = '550e8400-e29b-41d4-a716-446655440001';
const _access = 'access-secret-for-test';
const _refresh = 'refresh-secret-for-test';
const _password = 'password-for-test';
const _loginPath = '/api/v1/auth/v2/login';
const _registerPath = '/api/v1/auth/clients';
const _bindPath = '/api/v1/auth/v2/session/client';
const _mePath = '/api/v1/auth/v2/me';
const _logoutPath = '/api/v1/auth/v2/logout';

Map<String, Object?> _context({
  String? registrationId,
  String accountId = 'account-1',
  String role = 'AGRICULTOR',
  bool accountActive = true,
  bool memberActive = true,
  bool tenantActive = true,
}) => {
  'account': {
    'id': accountId,
    'name': 'Test User',
    'email': 'farmer@example.test',
    'isActive': accountActive,
  },
  'member': {'id': 'member-1', 'role': role, 'isActive': memberActive},
  'tenant': {
    'id': 'tenant-1',
    'name': 'Sindicato',
    'slug': 'sindicato',
    'isActive': tenantActive,
  },
  'role': role,
  'session': {
    'id': 'session-1',
    'status': 'ACTIVE',
    'refreshTransport': 'BODY',
    'createdAt': '2026-09-29T10:00:00.000Z',
    'lastSeenAt': '2026-09-29T10:00:00.000Z',
    'expiresAt': '2026-10-05T10:00:00.000Z',
    'clientRegistrationId': registrationId,
  },
};

Map<String, Object?> _authResponse({Map<String, Object?>? context}) => {
  'contractVersion': 2,
  'accessToken': _access,
  'refreshToken': _refresh,
  'refreshTransport': 'BODY',
  'sessionExpiresAt': '2026-10-05T10:00:00.000Z',
  'context': context ?? _context(),
};

http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status);

class _IdentityStore extends InstallationClientIdStore {
  _IdentityStore({this.value = _clientId, this.readError});

  final String? value;
  final Object? readError;
  int reads = 0;
  int creations = 0;
  int rotations = 0;

  @override
  Future<String?> read() async {
    reads++;
    if (readError != null) throw readError!;
    return value;
  }

  @override
  Future<String> getOrCreate() async {
    creations++;
    throw StateError('Activation must not create an identity');
  }

  @override
  Future<String> rotate() async {
    rotations++;
    throw StateError('Activation must not rotate an identity');
  }
}

class _CommitPort implements SecureSessionCommitPort {
  int calls = 0;
  SessionCommitCandidate? candidate;
  Object? failure;
  Completer<void>? pending;

  @override
  Future<void> commitAndVerify(SessionCommitCandidate value) async {
    calls++;
    candidate = value;
    if (pending != null) await pending!.future;
    if (failure != null) throw failure!;
  }
}

class _BackendHarness {
  final requests = <http.Request>[];
  final overrides =
      <String, Future<http.Response> Function(http.Request request)>{};

  List<String> get paths =>
      requests.map((request) => request.url.path).toList();

  Future<http.Response> respond(http.Request request) async {
    requests.add(request);
    expect(request.followRedirects, isFalse);
    final replacement = overrides[request.url.path];
    if (replacement != null) return replacement(request);
    switch (request.url.path) {
      case _loginPath:
        expect(request.method, 'POST');
        expect(jsonDecode(request.body), {
          'email': 'farmer@example.test',
          'password': _password,
          'refreshTransport': 'BODY',
        });
        return _json(200, _authResponse());
      case _registerPath:
        expect(request.method, 'POST');
        expect(request.headers['authorization'], 'Bearer $_access');
        expect(jsonDecode(request.body), {'clientId': _clientId});
        return _json(201, {
          'registrationId': _registrationId,
          'status': 'ACTIVE',
          'createdAt': '2026-09-29T10:00:00.000Z',
          'lastSeenAt': '2026-09-29T10:00:00.000Z',
          'revokedAt': null,
        });
      case _bindPath:
        expect(request.method, 'POST');
        expect(request.headers['authorization'], 'Bearer $_access');
        expect(jsonDecode(request.body), {'registrationId': _registrationId});
        return _json(201, {
          'registrationId': _registrationId,
          'status': 'ACTIVE',
        });
      case _mePath:
        expect(request.method, 'GET');
        expect(request.headers['authorization'], 'Bearer $_access');
        return _json(200, _context(registrationId: _registrationId));
      case _logoutPath:
        expect(request.method, 'POST');
        expect(jsonDecode(request.body), {'refreshToken': _refresh});
        return http.Response('', 204);
    }
    fail('Unexpected auth path');
  }
}

FirstActivationCoordinator _coordinator({
  required _IdentityStore identityStore,
  required _CommitPort secureSession,
  required _BackendHarness backend,
  InstallationIdentityStatus identityStatus = InstallationIdentityStatus.ready,
  Duration timeout = const Duration(seconds: 1),
  void Function(FirstActivationState)? onStateChanged,
  AuthV2Api Function()? apiFactory,
}) => FirstActivationCoordinator(
  identity: InstallationIdentityInitialization(identityStatus),
  identityStore: identityStore,
  apiFactory:
      apiFactory ??
      () => AuthV2Api(
        AuthHttpClient(
          config: ApiEndpointConfig(Uri.parse('https://api.example.test')),
          client: MockClient(backend.respond),
          timeout: timeout,
        ),
      ),
  secureSession: secureSession,
  clock: () => DateTime.utc(2026, 9, 29),
  onStateChanged: onStateChanged,
);

Future<FirstActivationState> _activate(
  FirstActivationCoordinator coordinator,
) => coordinator.activate(email: 'farmer@example.test', password: _password);

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(condition(), isTrue);
}

void main() {
  sqfliteFfiInit();

  test(
    'READY uses existing UUID and follows login/register/bind/me/commit',
    () async {
      final store = _IdentityStore();
      final commit = _CommitPort();
      final backend = _BackendHarness();
      final phases = <FirstActivationPhase>[];
      final coordinator = _coordinator(
        identityStore: store,
        secureSession: commit,
        backend: backend,
        onStateChanged: (state) => phases.add(state.phase),
      );

      final result = await _activate(coordinator);

      expect(result.isCompleted, isTrue);
      expect(backend.paths, [_loginPath, _registerPath, _bindPath, _mePath]);
      expect(phases, [
        FirstActivationPhase.checkingIdentity,
        FirstActivationPhase.preparingClient,
        FirstActivationPhase.loggingIn,
        FirstActivationPhase.registeringClient,
        FirstActivationPhase.bindingSession,
        FirstActivationPhase.verifyingContext,
        FirstActivationPhase.committingSession,
        FirstActivationPhase.completed,
      ]);
      expect(store.reads, 1);
      expect(store.creations, 0);
      expect(store.rotations, 0);
      expect(commit.calls, 1);
      expect(commit.candidate!.installationClientId, _clientId);
      expect(commit.candidate!.registrationId, _registrationId);
      expect(commit.candidate!.accountId, 'account-1');
      expect(commit.candidate!.refreshToken, _refresh);
      expect(commit.candidate.toString(), isNot(contains(_refresh)));
      expect(result.toString(), isNot(contains(_clientId)));
    },
  );

  for (final status in [
    InstallationIdentityStatus.corrupt,
    InstallationIdentityStatus.unavailable,
  ]) {
    test('$status blocks before identity read, API factory or HTTP', () async {
      final store = _IdentityStore();
      final commit = _CommitPort();
      final backend = _BackendHarness();
      var factories = 0;
      final coordinator = _coordinator(
        identityStore: store,
        secureSession: commit,
        backend: backend,
        identityStatus: status,
        apiFactory: () {
          factories++;
          throw StateError('Must not construct HTTP client');
        },
      );

      final result = await _activate(coordinator);

      expect(result.phase, FirstActivationPhase.failed);
      expect(
        result.problem,
        status == InstallationIdentityStatus.corrupt
            ? FirstActivationProblem.identityCorrupt
            : FirstActivationProblem.identityUnavailable,
      );
      expect(store.reads, 0);
      expect(store.creations, 0);
      expect(store.rotations, 0);
      expect(factories, 0);
      expect(backend.paths, isEmpty);
      expect(commit.calls, 0);
      expect(result.problem!.safeMessage, contains('datos locales'));
    });
  }

  test(
    'missing or corrupt existing UUID never creates or rotates identity',
    () async {
      for (final store in [
        _IdentityStore(value: null),
        _IdentityStore(value: 'not-a-uuid'),
        _IdentityStore(
          readError: const InstallationClientIdCorruptException('secret-path'),
        ),
      ]) {
        final backend = _BackendHarness();
        final coordinator = _coordinator(
          identityStore: store,
          secureSession: _CommitPort(),
          backend: backend,
        );
        final result = await _activate(coordinator);
        expect(result.isCompleted, isFalse);
        expect(
          result.problem,
          anyOf([
            FirstActivationProblem.identityCorrupt,
            FirstActivationProblem.identityUnavailable,
          ]),
        );
        expect(store.creations, 0);
        expect(store.rotations, 0);
        expect(backend.paths, isEmpty);
        expect(result.toString(), isNot(contains('secret-path')));
      }
    },
  );

  test('missing HTTPS configuration is safe and sends no request', () async {
    final backend = _BackendHarness();
    final coordinator = _coordinator(
      identityStore: _IdentityStore(),
      secureSession: _CommitPort(),
      backend: backend,
      apiFactory: () =>
          throw const AuthApiException(AuthApiErrorKind.configuration),
    );
    final result = await _activate(coordinator);
    expect(result.problem, FirstActivationProblem.configuration);
    expect(result.cleanup, RemoteCleanup.notNeeded);
    expect(backend.paths, isEmpty);
  });

  for (final entry in <int, FirstActivationProblem>{
    400: FirstActivationProblem.invalidRequest,
    401: FirstActivationProblem.invalidCredentials,
    429: FirstActivationProblem.rateLimited,
  }.entries) {
    test('login HTTP ${entry.key} maps safely without retry', () async {
      final backend = _BackendHarness();
      backend.overrides[_loginPath] = (_) async =>
          http.Response('$_password $_access $_refresh $_clientId', entry.key);
      final result = await _activate(
        _coordinator(
          identityStore: _IdentityStore(),
          secureSession: _CommitPort(),
          backend: backend,
        ),
      );
      expect(result.problem, entry.value);
      expect(result.cleanup, RemoteCleanup.notNeeded);
      expect(backend.paths, [_loginPath]);
      for (final secret in [_password, _access, _refresh, _clientId]) {
        expect(result.toString(), isNot(contains(secret)));
        expect(result.problem!.safeMessage, isNot(contains(secret)));
      }
    });
  }

  test('register conflict performs one logout, no bind or commit', () async {
    final backend = _BackendHarness();
    final commit = _CommitPort();
    backend.overrides[_registerPath] = (_) async => http.Response('', 409);
    final result = await _activate(
      _coordinator(
        identityStore: _IdentityStore(),
        secureSession: commit,
        backend: backend,
      ),
    );
    expect(result.problem, FirstActivationProblem.conflict);
    expect(result.cleanup, RemoteCleanup.confirmed);
    expect(backend.paths, [_loginPath, _registerPath, _logoutPath]);
    expect(commit.calls, 0);
  });

  test('revoked registration cannot be bound or committed', () async {
    final backend = _BackendHarness();
    final commit = _CommitPort();
    backend.overrides[_registerPath] = (_) async => _json(201, {
      'registrationId': _registrationId,
      'status': 'REVOKED',
      'createdAt': '2026-09-29T10:00:00.000Z',
      'lastSeenAt': '2026-09-29T10:00:00.000Z',
      'revokedAt': '2026-09-29T10:01:00.000Z',
    });
    final result = await _activate(
      _coordinator(
        identityStore: _IdentityStore(),
        secureSession: commit,
        backend: backend,
      ),
    );
    expect(result.problem, FirstActivationProblem.contextMismatch);
    expect(result.cleanup, RemoteCleanup.confirmed);
    expect(backend.paths, [_loginPath, _registerPath, _logoutPath]);
    expect(commit.calls, 0);
  });

  test(
    'inactive or non-farmer login context stops before registration',
    () async {
      for (final badContext in [
        _context(accountActive: false),
        _context(memberActive: false),
        _context(tenantActive: false),
        _context(role: 'DIRECTIVA'),
      ]) {
        final backend = _BackendHarness();
        final commit = _CommitPort();
        backend.overrides[_loginPath] = (_) async =>
            _json(200, _authResponse(context: badContext));
        final result = await _activate(
          _coordinator(
            identityStore: _IdentityStore(),
            secureSession: commit,
            backend: backend,
          ),
        );
        expect(result.problem, FirstActivationProblem.contextMismatch);
        expect(result.cleanup, RemoteCleanup.confirmed);
        expect(backend.paths, [_loginPath, _logoutPath]);
        expect(commit.calls, 0);
      }
    },
  );

  test('wrong binding ID prevents context check and secure commit', () async {
    final backend = _BackendHarness();
    final commit = _CommitPort();
    backend.overrides[_bindPath] = (_) async => _json(201, {
      'registrationId': '550e8400-e29b-41d4-a716-446655440099',
      'status': 'ACTIVE',
    });
    final result = await _activate(
      _coordinator(
        identityStore: _IdentityStore(),
        secureSession: commit,
        backend: backend,
      ),
    );
    expect(result.problem, FirstActivationProblem.contextMismatch);
    expect(result.cleanup, RemoteCleanup.confirmed);
    expect(backend.paths, [_loginPath, _registerPath, _bindPath, _logoutPath]);
    expect(commit.calls, 0);
  });

  test('me must match account, session and bound registration', () async {
    for (final badContext in [
      _context(registrationId: _registrationId, accountId: 'other-account'),
      _context(registrationId: null),
      _context(registrationId: _registrationId, memberActive: false),
      _context(registrationId: _registrationId, role: 'DIRECTIVA'),
    ]) {
      final backend = _BackendHarness();
      final commit = _CommitPort();
      backend.overrides[_mePath] = (_) async => _json(200, badContext);
      final result = await _activate(
        _coordinator(
          identityStore: _IdentityStore(),
          secureSession: commit,
          backend: backend,
        ),
      );
      expect(result.problem, FirstActivationProblem.contextMismatch);
      expect(result.cleanup, RemoteCleanup.confirmed);
      expect(backend.paths.last, _logoutPath);
      expect(commit.calls, 0);
    }
  });

  test(
    'invalid login JSON leaves remote result unknown and no false success',
    () async {
      final backend = _BackendHarness();
      backend.overrides[_loginPath] = (_) async =>
          http.Response('not-json', 200);
      final result = await _activate(
        _coordinator(
          identityStore: _IdentityStore(),
          secureSession: _CommitPort(),
          backend: backend,
        ),
      );
      expect(result.problem, FirstActivationProblem.invalidResponse);
      expect(result.remoteOutcomeUnknown, isTrue);
      expect(result.cleanup, RemoteCleanup.notNeeded);
      expect(backend.paths, [_loginPath]);
    },
  );

  test('login timeout does not retry a possibly created session', () async {
    final backend = _BackendHarness();
    backend.overrides[_loginPath] = (_) => Completer<http.Response>().future;
    final result = await _activate(
      _coordinator(
        identityStore: _IdentityStore(),
        secureSession: _CommitPort(),
        backend: backend,
        timeout: const Duration(milliseconds: 10),
      ),
    );
    expect(result.problem, FirstActivationProblem.timeout);
    expect(result.remoteOutcomeUnknown, isTrue);
    expect(backend.paths, [_loginPath]);
  });

  test('cancelled login timeout preserves unknown remote outcome', () async {
    final backend = _BackendHarness();
    backend.overrides[_loginPath] = (_) => Completer<http.Response>().future;
    final coordinator = _coordinator(
      identityStore: _IdentityStore(),
      secureSession: _CommitPort(),
      backend: backend,
      timeout: const Duration(milliseconds: 10),
    );
    final activation = _activate(coordinator);
    await _waitUntil(() => backend.paths.contains(_loginPath));
    expect(coordinator.requestCancel(), isTrue);
    final result = await activation;
    expect(result.phase, FirstActivationPhase.cancelled);
    expect(result.remoteOutcomeUnknown, isTrue);
    expect(result.cleanup, RemoteCleanup.notNeeded);
    expect(backend.paths, [_loginPath]);
  });

  test('network failure after login attempts one cleanup and preserves uncertainty', () async {
    final backend = _BackendHarness();
    backend.overrides[_registerPath] = (_) async =>
        throw http.ClientException('$_access $_refresh $_clientId');
    backend.overrides[_logoutPath] = (_) async =>
        throw http.ClientException(_refresh);
    final result = await _activate(
      _coordinator(
        identityStore: _IdentityStore(),
        secureSession: _CommitPort(),
        backend: backend,
      ),
    );
    expect(result.problem, FirstActivationProblem.connection);
    expect(result.cleanup, RemoteCleanup.unconfirmed);
    expect(result.remoteOutcomeUnknown, isTrue);
    expect(backend.paths, [_loginPath, _registerPath, _logoutPath]);
    expect(result.toString(), isNot(contains(_refresh)));
  });

  test(
    'overlapping activations cannot issue duplicate login requests',
    () async {
      final backend = _BackendHarness();
      final pending = Completer<http.Response>();
      backend.overrides[_loginPath] = (_) => pending.future;
      final coordinator = _coordinator(
        identityStore: _IdentityStore(),
        secureSession: _CommitPort(),
        backend: backend,
      );
      final first = _activate(coordinator);
      final second = await _activate(coordinator);
      expect(second.problem, FirstActivationProblem.alreadyRunning);
      await _waitUntil(() => backend.paths.contains(_loginPath));
      expect(backend.paths.where((path) => path == _loginPath), hasLength(1));
      pending.complete(_json(200, _authResponse()));
      expect((await first).isCompleted, isTrue);
    },
  );

  test(
    'cancel during registration cleans known session, never binds',
    () async {
      final backend = _BackendHarness();
      final pending = Completer<http.Response>();
      backend.overrides[_registerPath] = (_) => pending.future;
      final commit = _CommitPort();
      final coordinator = _coordinator(
        identityStore: _IdentityStore(),
        secureSession: commit,
        backend: backend,
      );
      final activation = _activate(coordinator);
      await _waitUntil(() => backend.paths.contains(_registerPath));
      expect(coordinator.requestCancel(), isTrue);
      pending.complete(
        _json(201, {
          'registrationId': _registrationId,
          'status': 'ACTIVE',
          'createdAt': '2026-09-29T10:00:00.000Z',
          'lastSeenAt': '2026-09-29T10:00:00.000Z',
          'revokedAt': null,
        }),
      );
      final result = await activation;
      expect(result.phase, FirstActivationPhase.cancelled);
      expect(result.problem, FirstActivationProblem.cancelled);
      expect(result.cleanup, RemoteCleanup.confirmed);
      expect(backend.paths, [_loginPath, _registerPath, _logoutPath]);
      expect(commit.calls, 0);
    },
  );

  test('cancel is rejected once secure commit begins', () async {
    final backend = _BackendHarness();
    final commit = _CommitPort()..pending = Completer<void>();
    final coordinator = _coordinator(
      identityStore: _IdentityStore(),
      secureSession: commit,
      backend: backend,
    );
    final activation = _activate(coordinator);
    await _waitUntil(
      () => coordinator.state.phase == FirstActivationPhase.committingSession,
    );
    expect(coordinator.requestCancel(), isFalse);
    commit.pending!.complete();
    expect((await activation).isCompleted, isTrue);
  });

  test('failed secure commit can never declare activation complete', () async {
    final backend = _BackendHarness();
    final commit = _CommitPort()..failure = StateError(_refresh);
    final result = await _activate(
      _coordinator(
        identityStore: _IdentityStore(),
        secureSession: commit,
        backend: backend,
      ),
    );
    expect(result.isCompleted, isFalse);
    expect(result.problem, FirstActivationProblem.secureCommitFailed);
    expect(result.cleanup, RemoteCleanup.confirmed);
    expect(backend.paths.last, _logoutPath);
    expect(result.toString(), isNot(contains(_refresh)));
  });

  test('remote failure does not change SQLite individual data', () async {
    final directory = await Directory.systemTemp.createTemp('f03_activation_');
    addTearDown(() async => directory.delete(recursive: true));
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      path: '${directory.path}/local.db',
    );
    addTearDown(database.close);
    final db = await database.database;
    await db.execute('CREATE TABLE marker (id INTEGER PRIMARY KEY, note TEXT)');
    await db.insert('marker', {'id': 1, 'note': 'offline-preserved'});
    final backend = _BackendHarness();
    backend.overrides[_loginPath] = (_) async => http.Response('', 401);
    final result = await _activate(
      _coordinator(
        identityStore: _IdentityStore(),
        secureSession: _CommitPort(),
        backend: backend,
      ),
    );
    expect(result.isCompleted, isFalse);
    expect(await db.query('marker'), [
      {'id': 1, 'note': 'offline-preserved'},
    ]);
  });
}
