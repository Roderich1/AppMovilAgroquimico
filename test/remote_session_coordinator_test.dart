import 'dart:async';
import 'dart:convert';

import 'package:agroquimicos/services/auth/api_endpoint_config.dart';
import 'package:agroquimicos/services/auth/auth_api_exception.dart';
import 'package:agroquimicos/services/auth/auth_http_client.dart';
import 'package:agroquimicos/services/auth/auth_v2_api.dart';
import 'package:agroquimicos/services/auth/first_activation_coordinator.dart';
import 'package:agroquimicos/services/auth/refresh_guard.dart';
import 'package:agroquimicos/services/auth/remote_session_coordinator.dart';
import 'package:agroquimicos/services/auth/secure_session_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _installation = '550e8400-e29b-41d4-a716-446655440000';
const _registration = 'registration-1';
const _oldRefresh = 'synthetic-old-refresh';
const _newRefresh = 'synthetic-new-refresh';
const _loginRefresh = 'synthetic-login-refresh';
const _access = 'synthetic-access';
const _password = 'synthetic-password';
const _expiry = '2026-10-05T10:00:00.000Z';
const _refreshPath = '/api/v1/auth/v2/refresh';
const _loginPath = '/api/v1/auth/v2/login';
const _bindPath = '/api/v1/auth/v2/session/client';
const _mePath = '/api/v1/auth/v2/me';
const _logoutPath = '/api/v1/auth/v2/logout';

StoredSession _stored() => StoredSession(
  refreshToken: _oldRefresh,
  installationClientId: _installation,
  registrationId: _registration,
  accountId: 'account-1',
  memberId: 'member-1',
  tenantId: 'tenant-1',
  sessionId: 'session-1',
  expiresAt: DateTime.parse(_expiry),
);

Map<String, Object?> _context({
  String account = 'account-1',
  String member = 'member-1',
  String tenant = 'tenant-1',
  String session = 'session-1',
  String? registration = _registration,
  String role = 'AGRICULTOR',
  bool accountActive = true,
  bool memberActive = true,
  bool tenantActive = true,
  String expiry = _expiry,
}) => {
  'account': {
    'id': account,
    'name': 'Synthetic',
    'email': 'farmer@example.test',
    'isActive': accountActive,
  },
  'member': {'id': member, 'role': role, 'isActive': memberActive},
  'tenant': {
    'id': tenant,
    'name': 'Synthetic',
    'slug': 'synthetic',
    'isActive': tenantActive,
  },
  'role': role,
  'session': {
    'id': session,
    'status': 'ACTIVE',
    'refreshTransport': 'BODY',
    'createdAt': '2026-10-01T10:00:00.000Z',
    'lastSeenAt': '2026-10-01T10:00:00.000Z',
    'expiresAt': expiry,
    'clientRegistrationId': registration,
  },
};

Map<String, Object?> _response({
  String refresh = _newRefresh,
  String expiry = _expiry,
  Map<String, Object?>? context,
}) => {
  'contractVersion': 2,
  'accessToken': _access,
  'refreshToken': refresh,
  'refreshTransport': 'BODY',
  'sessionExpiresAt': expiry,
  'context': context ?? _context(),
};

http.Response _json(int code, Object value) =>
    http.Response(jsonEncode(value), code);

class _Disk {
  bool quarantined = false;
}

class _Guard implements RefreshGuard {
  _Guard(this.disk, this.events);
  final _Disk disk;
  final List<String> events;
  bool failSet = false;
  bool failClear = false;
  bool failRead = false;

  @override
  Future<bool> isQuarantined() async {
    events.add('guard-read');
    if (failRead) throw StateError('guard unavailable');
    return disk.quarantined;
  }

  @override
  Future<void> quarantine() async {
    events.add('guard-set');
    if (failSet) throw StateError('durability not confirmed');
    if (disk.quarantined) throw StateError('already quarantined');
    disk.quarantined = true;
  }

  @override
  Future<void> clear() async {
    events.add('guard-clear');
    if (failClear) throw StateError('clear not confirmed');
    if (!disk.quarantined) throw StateError('guard not set');
    disk.quarantined = false;
  }
}

class _Commit implements SecureSessionCommitPort {
  _Commit(this.events);
  final List<String> events;
  SessionCommitCandidate? candidate;
  Object? failure;
  int calls = 0;

  @override
  Future<void> commitAndVerify(SessionCommitCandidate value) async {
    events.add('secure-commit');
    calls++;
    candidate = value;
    if (failure != null) throw failure!;
  }
}

class _Harness {
  final events = <String>[];
  final disk = _Disk();
  late final guard = _Guard(disk, events);
  late final commit = _Commit(events);
  final paths = <String>[];
  final overrides = <String, Future<http.Response> Function(http.Request)>{};
  SessionReadResult readResult = SessionReadResult(
    SessionReadStatus.available,
    session: _stored(),
  );
  int reads = 0;
  bool configMissing = false;

  /// Tokens entregados a Sync v1 y cuántos eventos había en ese momento.
  final verified = <(String, String, String)>[];
  int? verifiedAfterEvents;

  Future<http.Response> _respond(http.Request request) async {
    paths.add(request.url.path);
    events.add('http:${request.url.path}');
    final replacement = overrides[request.url.path];
    if (replacement != null) return replacement(request);
    switch (request.url.path) {
      case _refreshPath:
        expect(request.method, 'POST');
        expect(jsonDecode(request.body), {'refreshToken': _oldRefresh});
        return _json(200, _response());
      case _loginPath:
        expect(request.method, 'POST');
        expect(jsonDecode(request.body), {
          'email': 'farmer@example.test',
          'password': _password,
          'refreshTransport': 'BODY',
        });
        return _json(
          200,
          _response(
            refresh: _loginRefresh,
            context: _context(session: 'session-2', registration: null),
          ),
        );
      case _bindPath:
        expect(request.method, 'POST');
        expect(jsonDecode(request.body), {'registrationId': _registration});
        expect(request.headers['authorization'], 'Bearer $_access');
        return _json(201, {
          'registrationId': _registration,
          'status': 'ACTIVE',
        });
      case _mePath:
        expect(request.method, 'GET');
        expect(request.headers['authorization'], 'Bearer $_access');
        return _json(200, _context(session: 'session-2'));
      case _logoutPath:
        expect(request.method, 'POST');
        expect(jsonDecode(request.body), {
          'refreshToken': anyOf(_loginRefresh, _newRefresh),
        });
        return http.Response('', 204);
    }
    fail('Unexpected endpoint');
  }

  RemoteSessionCoordinator coordinator() => RemoteSessionCoordinator(
    readSession: () async {
      reads++;
      events.add('secure-read');
      return readResult;
    },
    secureSession: commit,
    guard: guard,
    apiFactory: () {
      events.add('config');
      if (configMissing) {
        throw const AuthApiException(AuthApiErrorKind.configuration);
      }
      return AuthV2Api(
        AuthHttpClient(
          config: ApiEndpointConfig(Uri.parse('https://api.example.test')),
          client: MockClient(_respond),
          timeout: const Duration(milliseconds: 20),
        ),
      );
    },
    clock: () => DateTime.utc(2026, 10, 1),
    onAccessVerified: (token, member, tenant) {
      verified.add((token, member, tenant));
      verifiedAfterEvents = events.length;
    },
  );
}

void main() {
  test(
    'el access token sólo se entrega tras commit y guarda liberada',
    () async {
      final h = _Harness();
      await h.coordinator().refreshOnDemand();
      expect(h.verified.map((v) => v.$1), [_access]);
      // Último evento: liberar la guarda; recién después se entrega.
      expect(h.verifiedAfterEvents, h.events.length);
      expect(h.events.last, 'guard-clear');

      final r = _Harness()..disk.quarantined = true;
      await r.coordinator().reauthenticate(
        email: 'farmer@example.test',
        password: _password,
      );
      expect(r.verified.map((v) => v.$1), [_access]);
      expect(r.verifiedAfterEvents, r.events.length);
    },
  );

  test('sin éxito no se entrega ningún token a Sync v1', () async {
    final mismatch = _Harness();
    mismatch.overrides[_refreshPath] = (_) async =>
        _json(200, _response(context: _context(account: 'other')));
    await mismatch.coordinator().refreshOnDemand();
    expect(mismatch.verified, isEmpty);

    final failedClear = _Harness();
    failedClear.guard.failClear = true;
    await failedClear.coordinator().refreshOnDemand();
    expect(failedClear.verified, isEmpty);

    final timeout = _Harness();
    timeout.overrides[_refreshPath] = (_) async =>
        throw http.ClientException('lost');
    await timeout.coordinator().refreshOnDemand();
    expect(timeout.verified, isEmpty);
  });

  test(
    'refresh is on demand, quarantines before HTTP, commits before clear',
    () async {
      final h = _Harness();
      expect(h.paths, isEmpty);
      final result = await h.coordinator().refreshOnDemand();
      expect(result.phase, RemoteSessionPhase.remoteAvailable);
      expect(h.paths, [_refreshPath]);
      expect(h.events, [
        'secure-read',
        'config',
        'guard-read',
        'guard-set',
        'http:$_refreshPath',
        'secure-commit',
        'guard-clear',
      ]);
      expect(h.commit.candidate!.refreshToken, _newRefresh);
      expect(h.commit.candidate!.installationClientId, _installation);
      expect(h.commit.candidate!.registrationId, _registration);
      expect(h.commit.candidate!.sessionId, 'session-1');
      expect(h.disk.quarantined, isFalse);
      expect(result.toString(), isNot(contains(_newRefresh)));
    },
  );

  test(
    'no config or unreadable session sends nothing and does not quarantine',
    () async {
      final h = _Harness()..configMissing = true;
      expect(
        (await h.coordinator().refreshOnDemand()).phase,
        RemoteSessionPhase.configurationUnavailable,
      );
      expect(h.disk.quarantined, isFalse);
      expect(h.paths, isEmpty);
      h.configMissing = false;
      h.readResult = const SessionReadResult(SessionReadStatus.corrupt);
      expect(
        (await h.coordinator().refreshOnDemand()).phase,
        RemoteSessionPhase.requiresReauthentication,
      );
      expect(h.paths, isEmpty);
    },
  );

  test(
    'expired local session may refresh; guard set failure forbids request',
    () async {
      final h = _Harness();
      h.readResult = SessionReadResult(
        SessionReadStatus.available,
        session: _stored(),
        expiredLocally: true,
      );
      h.guard.failSet = true;
      expect(
        (await h.coordinator().refreshOnDemand()).phase,
        RemoteSessionPhase.guardUnavailable,
      );
      expect(h.paths, isEmpty);
      expect(h.commit.calls, 0);
    },
  );

  test(
    'guard survives wrapper recreation and forbids old-token retry',
    () async {
      final h = _Harness();
      h.overrides[_refreshPath] = (_) async =>
          throw http.ClientException('lost');
      final first = await h.coordinator().refreshOnDemand();
      expect(first.phase, RemoteSessionPhase.outcomeUnknown);
      expect(h.disk.quarantined, isTrue);
      final newWrapper = _Guard(h.disk, h.events);
      expect(await newWrapper.isQuarantined(), isTrue);
      final second = await h.coordinator().refreshOnDemand();
      expect(second.phase, RemoteSessionPhase.requiresReauthentication);
      expect(h.paths, [_refreshPath]);
    },
  );

  test('two coordinators cannot refresh concurrently in one isolate', () async {
    final h = _Harness();
    final response = Completer<http.Response>();
    h.overrides[_refreshPath] = (_) => response.future;
    final first = h.coordinator().refreshOnDemand();
    for (var i = 0; i < 100 && h.paths.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(h.paths, [_refreshPath]);
    final second = await h.coordinator().refreshOnDemand();
    expect(second.problem, RemoteSessionProblem.alreadyRunning);
    expect(h.paths, [_refreshPath]);
    response.complete(_json(200, _response()));
    expect((await first).phase, RemoteSessionPhase.remoteAvailable);
  });

  for (final (name, response, expected) in [
    (
      '401',
      _json(401, {'message': 'unauthorized'}),
      RemoteSessionPhase.requiresReauthentication,
    ),
    (
      '400',
      _json(400, {'message': 'bad'}),
      RemoteSessionPhase.requiresReauthentication,
    ),
    (
      '429',
      _json(429, {'message': 'slow'}),
      RemoteSessionPhase.requiresReauthentication,
    ),
    (
      '500',
      _json(500, {'message': 'error'}),
      RemoteSessionPhase.requiresReauthentication,
    ),
    (
      'malformed',
      http.Response('not-json', 200),
      RemoteSessionPhase.outcomeUnknown,
    ),
  ]) {
    test('refresh $name keeps old credential quarantined', () async {
      final h = _Harness();
      h.overrides[_refreshPath] = (_) async => response;
      expect((await h.coordinator().refreshOnDemand()).phase, expected);
      expect(h.disk.quarantined, isTrue);
      expect(h.commit.calls, 0);
      expect(h.paths, [_refreshPath]);
    });
  }

  test('refresh timeout is outcomeUnknown without retry', () async {
    final h = _Harness();
    h.overrides[_refreshPath] = (_) => Completer<http.Response>().future;
    expect(
      (await h.coordinator().refreshOnDemand()).phase,
      RemoteSessionPhase.outcomeUnknown,
    );
    expect(h.disk.quarantined, isTrue);
    expect(h.paths, [_refreshPath]);
  });

  for (final (name, response) in [
    ('account mismatch', _response(context: _context(account: 'account-2'))),
    ('member mismatch', _response(context: _context(member: 'member-2'))),
    ('tenant mismatch', _response(context: _context(tenant: 'tenant-2'))),
    ('session mismatch', _response(context: _context(session: 'session-2'))),
    (
      'registration mismatch',
      _response(context: _context(registration: 'other')),
    ),
    ('wrong role', _response(context: _context(role: 'DIRECTIVA'))),
    ('inactive account', _response(context: _context(accountActive: false))),
    ('inactive member', _response(context: _context(memberActive: false))),
    ('inactive tenant', _response(context: _context(tenantActive: false))),
    ('expiry mismatch', _response(expiry: '2026-10-06T10:00:00.000Z')),
    ('unrotated refresh', _response(refresh: _oldRefresh)),
  ]) {
    test('refresh $name fails closed before secure commit', () async {
      final h = _Harness();
      h.overrides[_refreshPath] = (_) async => _json(200, response);
      expect(
        (await h.coordinator().refreshOnDemand()).phase,
        RemoteSessionPhase.requiresReauthentication,
      );
      expect(h.commit.calls, 0);
      expect(h.disk.quarantined, isTrue);
      expect(
        h.paths,
        name == 'unrotated refresh'
            ? [_refreshPath]
            : [_refreshPath, _logoutPath],
      );
    });
  }

  for (final reason in [
    SecureSessionFailure.invalidCandidate,
    SecureSessionFailure.existingSessionUnreadable,
    SecureSessionFailure.writeFailed,
  ]) {
    test('refresh definite $reason cleans new credential once', () async {
      final h = _Harness();
      h.commit.failure = SecureSessionStorageException(reason);
      final result = await h.coordinator().refreshOnDemand();
      expect(result.phase, RemoteSessionPhase.requiresReauthentication);
      expect(result.problem, RemoteSessionProblem.localCommitFailed);
      expect(result.cleanupUnconfirmed, isFalse);
      expect(h.disk.quarantined, isTrue);
      expect(h.commit.calls, 1);
      expect(h.events, isNot(contains('guard-clear')));
      expect(h.paths, [_refreshPath, _logoutPath]);
    });
  }

  test(
    'refresh definite failure reports failed cleanup without retry',
    () async {
      final h = _Harness();
      h.commit.failure = const SecureSessionStorageException(
        SecureSessionFailure.writeFailed,
      );
      h.overrides[_logoutPath] = (_) async =>
          throw http.ClientException('lost');
      final result = await h.coordinator().refreshOnDemand();
      expect(result.problem, RemoteSessionProblem.localCommitFailed);
      expect(result.cleanupUnconfirmed, isTrue);
      expect(h.paths, [_refreshPath, _logoutPath]);
      expect(h.disk.quarantined, isTrue);
    },
  );

  test('refresh uncertain commit never logs out or retries', () async {
    final h = _Harness();
    h.commit.failure = const SecureSessionCommitUncertainException();
    final result = await h.coordinator().refreshOnDemand();
    expect(result.problem, RemoteSessionProblem.localCommitUnknown);
    expect(h.paths, [_refreshPath]);
    expect(h.disk.quarantined, isTrue);
    expect(h.events, isNot(contains('guard-clear')));
  });

  test('refresh context mismatch reports failed new-token cleanup', () async {
    final h = _Harness();
    h.overrides[_refreshPath] = (_) async =>
        _json(200, _response(context: _context(account: 'other')));
    h.overrides[_logoutPath] = (_) async => throw http.ClientException('lost');
    final result = await h.coordinator().refreshOnDemand();
    expect(result.problem, RemoteSessionProblem.contextMismatch);
    expect(result.cleanupUnconfirmed, isTrue);
    expect(h.paths, [_refreshPath, _logoutPath]);
    expect(h.commit.calls, 0);
    expect(h.disk.quarantined, isTrue);
  });

  test(
    'failed clear after verified commit cannot claim remote availability',
    () async {
      final h = _Harness();
      h.guard.failClear = true;
      expect(
        (await h.coordinator().refreshOnDemand()).phase,
        RemoteSessionPhase.requiresReauthentication,
      );
      expect(h.commit.calls, 1);
      expect(h.disk.quarantined, isTrue);
    },
  );

  test('reauth binds known registration and commits same identity with new session', () async {
    final h = _Harness()..disk.quarantined = true;
    final result = await h.coordinator().reauthenticate(
      email: 'farmer@example.test',
      password: _password,
    );
    expect(result.phase, RemoteSessionPhase.remoteAvailable);
    expect(h.paths, [_loginPath, _bindPath, _mePath]);
    expect(h.paths, isNot(contains('/api/v1/auth/clients')));
    expect(h.commit.candidate!.refreshToken, _loginRefresh);
    expect(h.commit.candidate!.sessionId, 'session-2');
    expect(h.commit.candidate!.installationClientId, _installation);
    expect(h.commit.candidate!.registrationId, _registration);
    expect(h.disk.quarantined, isFalse);
    expect(
      h.events.indexOf('secure-commit'),
      lessThan(h.events.indexOf('guard-clear')),
    );
  });

  // F10 (#18, C38): otra cuenta, Member o tenant se distinguen de un
  // contexto inactivo, para que la pantalla diga por qué no se vincula.
  for (final (name, context, problem) in [
    (
      'other account',
      _context(session: 'session-2', registration: null, account: 'other'),
      RemoteSessionProblem.otherAccount,
    ),
    (
      'other member',
      _context(session: 'session-2', registration: null, member: 'other'),
      RemoteSessionProblem.otherAccount,
    ),
    (
      'other tenant',
      _context(session: 'session-2', registration: null, tenant: 'other'),
      RemoteSessionProblem.otherAccount,
    ),
    (
      'other account that is not a farmer',
      _context(
        session: 'session-2',
        registration: null,
        account: 'other',
        member: 'other',
        role: 'DIRECTIVA',
      ),
      RemoteSessionProblem.otherAccount,
    ),
    (
      'inactive',
      _context(session: 'session-2', registration: null, accountActive: false),
      RemoteSessionProblem.contextMismatch,
    ),
  ]) {
    test('reauth $name rejects and cleans up new login once', () async {
      final h = _Harness()..disk.quarantined = true;
      h.overrides[_loginPath] = (_) async =>
          _json(200, _response(refresh: _loginRefresh, context: context));
      final result = await h.coordinator().reauthenticate(
        email: 'farmer@example.test',
        password: _password,
      );
      expect(result.phase, RemoteSessionPhase.requiresReauthentication);
      expect(result.problem, problem);
      expect(h.paths, [_loginPath, _logoutPath]);
      expect(h.commit.calls, 0);
      expect(h.disk.quarantined, isTrue);
    });
  }

  for (final status in [401, 404, 409]) {
    test(
      'reauth bind $status blocks remote without new registration',
      () async {
        final h = _Harness()..disk.quarantined = true;
        h.overrides[_bindPath] = (_) async =>
            _json(status, {'error': 'rejected'});
        final result = await h.coordinator().reauthenticate(
          email: 'farmer@example.test',
          password: _password,
        );
        expect(result.phase, RemoteSessionPhase.registrationRejected);
        expect(h.paths, [_loginPath, _bindPath, _logoutPath]);
        expect(h.commit.calls, 0);
        expect(h.disk.quarantined, isTrue);
      },
    );
  }

  test('reauth /me mismatch rejects before secure commit', () async {
    final h = _Harness()..disk.quarantined = true;
    h.overrides[_mePath] = (_) async =>
        _json(200, _context(session: 'session-2', member: 'other'));
    final result = await h.coordinator().reauthenticate(
      email: 'farmer@example.test',
      password: _password,
    );
    expect(result.phase, RemoteSessionPhase.requiresReauthentication);
    expect(h.paths, [_loginPath, _bindPath, _mePath, _logoutPath]);
    expect(h.commit.calls, 0);
  });

  for (final reason in [
    SecureSessionFailure.invalidCandidate,
    SecureSessionFailure.existingSessionUnreadable,
    SecureSessionFailure.writeFailed,
  ]) {
    test('reauth definite $reason cleans new login once', () async {
      final h = _Harness()..disk.quarantined = true;
      h.commit.failure = SecureSessionStorageException(reason);
      final result = await h.coordinator().reauthenticate(
        email: 'farmer@example.test',
        password: _password,
      );
      expect(result.phase, RemoteSessionPhase.requiresReauthentication);
      expect(result.problem, RemoteSessionProblem.localCommitFailed);
      expect(result.cleanupUnconfirmed, isFalse);
      expect(h.disk.quarantined, isTrue);
      expect(h.commit.calls, 1);
      expect(h.events, isNot(contains('guard-clear')));
      expect(h.paths, [_loginPath, _bindPath, _mePath, _logoutPath]);
    });
  }

  test('reauth definite failure reports failed cleanup', () async {
    final h = _Harness()..disk.quarantined = true;
    h.commit.failure = const SecureSessionStorageException(
      SecureSessionFailure.writeFailed,
    );
    h.overrides[_logoutPath] = (_) async => throw http.ClientException('lost');
    final result = await h.coordinator().reauthenticate(
      email: 'farmer@example.test',
      password: _password,
    );
    expect(result.phase, RemoteSessionPhase.requiresReauthentication);
    expect(result.problem, RemoteSessionProblem.localCommitFailed);
    expect(result.cleanupUnconfirmed, isTrue);
    expect(h.paths, [_loginPath, _bindPath, _mePath, _logoutPath]);
    expect(h.disk.quarantined, isTrue);
  });

  test('reauth uncertain commit never logs out', () async {
    final h = _Harness()..disk.quarantined = true;
    h.commit.failure = const SecureSessionCommitUncertainException();
    final result = await h.coordinator().reauthenticate(
      email: 'farmer@example.test',
      password: _password,
    );
    expect(result.problem, RemoteSessionProblem.localCommitUnknown);
    expect(h.paths, [_loginPath, _bindPath, _mePath]);
    expect(h.disk.quarantined, isTrue);
    expect(h.events, isNot(contains('guard-clear')));
  });

  test(
    'reauth requires quarantine and never registers or rotates client',
    () async {
      final h = _Harness();
      expect(
        (await h.coordinator().reauthenticate(
          email: 'farmer@example.test',
          password: _password,
        )).phase,
        RemoteSessionPhase.requiresReauthentication,
      );
      expect(h.paths, isEmpty);
    },
  );

  test(
    'reauth login 401 keeps guard and allows corrected credentials',
    () async {
      final h = _Harness()..disk.quarantined = true;
      h.overrides[_loginPath] = (_) async => _json(401, {'message': 'invalid'});
      final result = await h.coordinator().reauthenticate(
        email: 'farmer@example.test',
        password: _password,
      );
      expect(result.phase, RemoteSessionPhase.requiresReauthentication);
      expect(result.problem, RemoteSessionProblem.invalidCredentials);
      expect(h.paths, [_loginPath]);
      expect(h.disk.quarantined, isTrue);
    },
  );

  for (final (name, response) in [
    ('network', (http.Request _) async => throw http.ClientException('lost')),
    ('timeout', (http.Request _) => Completer<http.Response>().future),
    ('malformed', (http.Request _) async => http.Response('invalid', 200)),
  ]) {
    test('reauth $name is unknown and never retries login', () async {
      final h = _Harness()..disk.quarantined = true;
      h.overrides[_loginPath] = response;
      final result = await h.coordinator().reauthenticate(
        email: 'farmer@example.test',
        password: _password,
      );
      expect(result.phase, RemoteSessionPhase.outcomeUnknown);
      expect(h.paths, [_loginPath]);
      expect(h.disk.quarantined, isTrue);
      expect(h.commit.calls, 0);
    });
  }

  test('reauth guard read failure blocks before login', () async {
    final h = _Harness()..guard.failRead = true;
    final result = await h.coordinator().reauthenticate(
      email: 'farmer@example.test',
      password: _password,
    );
    expect(result.phase, RemoteSessionPhase.guardUnavailable);
    expect(h.paths, isEmpty);
  });

  test('reauth unreadable local store never sends login', () async {
    final h = _Harness()..disk.quarantined = true;
    h.readResult = const SessionReadResult(SessionReadStatus.unavailable);
    final result = await h.coordinator().reauthenticate(
      email: 'farmer@example.test',
      password: _password,
    );
    expect(result.phase, RemoteSessionPhase.requiresReauthentication);
    expect(h.paths, isEmpty);
    expect(h.disk.quarantined, isTrue);
  });

  test(
    'failed cleanup is reported without changing old local session',
    () async {
      final h = _Harness()..disk.quarantined = true;
      h.overrides[_loginPath] = (_) async => _json(
        200,
        _response(
          refresh: _loginRefresh,
          context: _context(
            account: 'other',
            session: 'session-2',
            registration: null,
          ),
        ),
      );
      h.overrides[_logoutPath] = (_) async =>
          throw http.ClientException('lost');
      final result = await h.coordinator().reauthenticate(
        email: 'farmer@example.test',
        password: _password,
      );
      expect(result.phase, RemoteSessionPhase.requiresReauthentication);
      expect(result.cleanupUnconfirmed, isTrue);
      expect(h.paths, [_loginPath, _logoutPath]);
      expect(h.commit.calls, 0);
      expect(h.disk.quarantined, isTrue);
    },
  );

  test('state and guard contain no secret or stored identity', () async {
    final h = _Harness();
    h.overrides[_refreshPath] = (_) async => _json(401, {});
    final result = await h.coordinator().refreshOnDemand();
    final exposed =
        '${result.toString()} ${result.safeMessage} ${h.disk.quarantined}';
    for (final secret in [
      _oldRefresh,
      _newRefresh,
      _access,
      _password,
      _installation,
      _registration,
      'account-1',
      'member-1',
      'tenant-1',
    ]) {
      expect(exposed, isNot(contains(secret)));
    }
  });

  // F03 (DEVICE del 2026-10-24): acreditar al titular para el PIN con la
  // sesión sana. reauthenticate sólo recupera una sesión en cuarentena: en el
  // teléfono abortaba sin red y dejaba la pantalla en «volver a autenticar».
  group('confirmAccount (PIN del titular)', () {
    test('reauthenticate on a healthy session never reaches the network', () {
      // Control del fallo observado en el teléfono: por eso el PIN no puede
      // usar reauthenticate.
      final h = _Harness();
      return h
          .coordinator()
          .reauthenticate(email: 'farmer@example.test', password: _password)
          .then((result) {
            expect(result.problem, RemoteSessionProblem.quarantined);
            expect(h.paths, isEmpty);
          });
    });

    test('healthy session: same account confirmed, new login closed, nothing else changes', () async {
      final h = _Harness();
      final states = <RemoteSessionState>[];
      final coordinator = RemoteSessionCoordinator(
        readSession: () async => h.readResult,
        secureSession: h.commit,
        guard: h.guard,
        apiFactory: () => AuthV2Api(
          AuthHttpClient(
            config: ApiEndpointConfig(Uri.parse('https://api.example.test')),
            client: MockClient(h._respond),
            timeout: const Duration(milliseconds: 20),
          ),
        ),
        clock: () => DateTime.utc(2026, 10, 1),
        onStateChanged: states.add,
      );
      final ok = await coordinator.confirmAccount(
        email: 'farmer@example.test',
        password: _password,
      );
      expect(ok, isTrue);
      expect(h.paths, [_loginPath, _logoutPath]);
      expect(h.commit.calls, 0);
      expect(h.events, isNot(contains('guard-read')));
      expect(h.events, isNot(contains('guard-set')));
      expect(h.events, isNot(contains('guard-clear')));
      expect(states, isEmpty);
      expect(coordinator.state.phase, RemoteSessionPhase.idle);
    });

    for (final (name, context) in [
      (
        'other account',
        _context(session: 'session-2', registration: null, account: 'other'),
      ),
      (
        'other member',
        _context(session: 'session-2', registration: null, member: 'other'),
      ),
      (
        'other tenant',
        _context(session: 'session-2', registration: null, tenant: 'other'),
      ),
      (
        'inactive',
        _context(
          session: 'session-2',
          registration: null,
          accountActive: false,
        ),
      ),
    ]) {
      test('$name is not confirmed and its new login is closed', () async {
        final h = _Harness();
        h.overrides[_loginPath] = (_) async =>
            _json(200, _response(refresh: _loginRefresh, context: context));
        final ok = await h.coordinator().confirmAccount(
          email: 'farmer@example.test',
          password: _password,
        );
        expect(ok, isFalse);
        expect(h.paths, [_loginPath, _logoutPath]);
        expect(h.commit.calls, 0);
      });
    }

    test('wrong password or no network is not confirmed', () async {
      for (final response in [
        (_) async => _json(401, {'error': 'invalid'}),
        (_) async => throw http.ClientException('offline'),
      ]) {
        final h = _Harness();
        h.overrides[_loginPath] = response;
        final ok = await h.coordinator().confirmAccount(
          email: 'farmer@example.test',
          password: _password,
        );
        expect(ok, isFalse);
        expect(h.paths, [_loginPath]);
        expect(h.commit.calls, 0);
      }
    });

    test('unreadable local session never sends the login', () async {
      final h = _Harness();
      h.readResult = const SessionReadResult(SessionReadStatus.unavailable);
      final ok = await h.coordinator().confirmAccount(
        email: 'farmer@example.test',
        password: _password,
      );
      expect(ok, isFalse);
      expect(h.paths, isEmpty);
    });

    test('another remote operation in progress is not confirmed', () async {
      final h = _Harness();
      final gate = Completer<http.Response>();
      h.overrides[_refreshPath] = (_) => gate.future;
      final refreshing = h.coordinator().refreshOnDemand();
      await Future<void>.delayed(Duration.zero);
      final ok = await h.coordinator().confirmAccount(
        email: 'farmer@example.test',
        password: _password,
      );
      expect(ok, isFalse);
      expect(h.paths, isNot(contains(_loginPath)));
      gate.complete(_json(200, _response()));
      await refreshing;
    });
  });
}
