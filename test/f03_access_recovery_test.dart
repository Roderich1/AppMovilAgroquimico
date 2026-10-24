// F03 «Recuperar acceso» (docs/architecture/F03_RECUPERACION_IDENTIDAD_LOCAL.md).
// Coordinador: el ámbito del titular se comprueba antes de registrar el
// cliente; nada se guarda con otra cuenta, al cancelar o sin red. Tabla de
// modos por estado. Salida de una sesión ajena sin tocar datos.
import 'dart:async';
import 'dart:convert';

import 'package:agroquimicos/data/installation_client_id_store.dart';
import 'package:agroquimicos/data/installation_identity_initializer.dart';
import 'package:agroquimicos/domain/installation_access.dart';
import 'package:agroquimicos/services/auth/access_recovery.dart';
import 'package:agroquimicos/services/auth/api_endpoint_config.dart';
import 'package:agroquimicos/services/auth/auth_http_client.dart';
import 'package:agroquimicos/services/auth/auth_v2_api.dart';
import 'package:agroquimicos/services/auth/existing_session_startup.dart';
import 'package:agroquimicos/services/auth/first_activation_coordinator.dart';
import 'package:agroquimicos/services/auth/secure_session_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _clientId = '550e8400-e29b-41d4-a716-446655440000';
const _registrationId = '550e8400-e29b-41d4-a716-446655440001';
const _access = 'access-secret-for-test';
const _refresh = 'refresh-secret-for-test';
const _loginPath = '/api/v1/auth/v2/login';
const _registerPath = '/api/v1/auth/clients';
const _bindPath = '/api/v1/auth/v2/session/client';
const _mePath = '/api/v1/auth/v2/me';
const _logoutPath = '/api/v1/auth/v2/logout';
const _owner = OwnerScope(memberId: 'member-1', tenantId: 'tenant-1');

Map<String, Object?> _context({
  String member = 'member-1',
  String tenant = 'tenant-1',
  String? registrationId,
}) => {
  'account': {
    'id': 'account-1',
    'name': 'Synthetic Farmer',
    'email': 'farmer@example.test',
    'isActive': true,
  },
  'member': {'id': member, 'role': 'AGRICULTOR', 'isActive': true},
  'tenant': {
    'id': tenant,
    'name': 'Synthetic Union',
    'slug': 'sindicato',
    'isActive': true,
  },
  'role': 'AGRICULTOR',
  'session': {
    'id': 'session-1',
    'status': 'ACTIVE',
    'refreshTransport': 'BODY',
    'createdAt': '2026-10-23T10:00:00.000Z',
    'lastSeenAt': '2026-10-23T10:00:00.000Z',
    'expiresAt': '2026-10-30T10:00:00.000Z',
    'clientRegistrationId': registrationId,
  },
};

http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status);

class _Backend {
  _Backend({this.member = 'member-1', this.tenant = 'tenant-1'});

  final String member;
  final String tenant;
  final paths = <String>[];
  Object? registerError;
  Completer<void>? holdLogin;

  Future<http.Response> respond(http.Request request) async {
    paths.add(request.url.path);
    switch (request.url.path) {
      case _loginPath:
        if (holdLogin != null) await holdLogin!.future;
        return _json(200, {
          'contractVersion': 2,
          'accessToken': _access,
          'refreshToken': _refresh,
          'refreshTransport': 'BODY',
          'sessionExpiresAt': '2026-10-30T10:00:00.000Z',
          'context': _context(member: member, tenant: tenant),
        });
      case _registerPath:
        if (registerError != null) throw registerError!;
        return _json(201, {
          'registrationId': _registrationId,
          'status': 'ACTIVE',
          'createdAt': '2026-10-23T10:00:00.000Z',
          'lastSeenAt': '2026-10-23T10:00:00.000Z',
          'revokedAt': null,
        });
      case _bindPath:
        return _json(201, {'registrationId': _registrationId, 'status': 'ACTIVE'});
      case _mePath:
        return _json(
          200,
          _context(member: member, tenant: tenant, registrationId: _registrationId),
        );
      case _logoutPath:
        return http.Response('', 204);
    }
    fail('Unexpected auth path');
  }
}

class _Identity extends InstallationClientIdStore {
  @override
  Future<String?> read() async => _clientId;
}

class _Commit implements SecureSessionCommitPort {
  int calls = 0;

  @override
  Future<void> commitAndVerify(SessionCommitCandidate candidate) async =>
      calls++;
}

class _Replace implements UnreadableSessionReplacementPort {
  int calls = 0;
  SessionCommitCandidate? candidate;

  @override
  Future<void> replaceUnreadableAndVerify(
    SessionCommitCandidate value,
  ) async {
    calls++;
    candidate = value;
  }
}

AuthV2Api _api(_Backend backend) => AuthV2Api(
  AuthHttpClient(
    config: ApiEndpointConfig(Uri.parse('https://api.example.test')),
    client: MockClient(backend.respond),
    timeout: const Duration(seconds: 1),
  ),
);

FirstActivationCoordinator _coordinator(
  _Backend backend,
  _Commit commit, {
  _Replace? replace,
}) => FirstActivationCoordinator(
  identity: const InstallationIdentityInitialization(
    InstallationIdentityStatus.ready,
  ),
  identityStore: _Identity(),
  apiFactory: () => _api(backend),
  secureSession: commit,
  sessionReplacement: replace,
  clock: () => DateTime.utc(2026, 10, 23),
);

class _StoredSession implements StoredSessionAccess {
  _StoredSession(this.result);

  SessionReadResult result;
  int deletes = 0;
  bool failDelete = false;

  @override
  Future<SessionReadResult> read() async => result;

  @override
  Future<void> delete() async {
    deletes++;
    if (failDelete) throw StateError('deletion uncertain');
    result = const SessionReadResult(SessionReadStatus.absent);
  }
}

StoredSession _foreignSession() => StoredSession(
  refreshToken: _refresh,
  installationClientId: _clientId,
  registrationId: _registrationId,
  accountId: 'account-9',
  memberId: 'member-9',
  tenantId: 'tenant-1',
  sessionId: 'session-9',
  expiresAt: DateTime.utc(2026, 10, 30),
);

void main() {
  group('coordinator with the owner scope', () {
    test('the same titular completes with the ordinary sequence', () async {
      final backend = _Backend();
      final commit = _Commit();
      final result = await _coordinator(backend, commit).activate(
        email: 'farmer@example.test',
        password: 'pw',
        requiredScope: _owner,
      );
      expect(result.isCompleted, isTrue);
      expect(backend.paths, [_loginPath, _registerPath, _bindPath, _mePath]);
      expect(commit.calls, 1);
    });

    for (final (label, member, tenant) in [
      ('another Member', 'member-2', 'tenant-1'),
      ('another tenant', 'member-1', 'tenant-2'),
    ]) {
      test('$label aborts before registering the client and stores nothing', () async {
        final backend = _Backend(member: member, tenant: tenant);
        final commit = _Commit();
        final replace = _Replace();
        final result = await _coordinator(backend, commit, replace: replace)
            .activate(
              email: 'farmer@example.test',
              password: 'pw',
              requiredScope: _owner,
              replaceUnreadableSession: true,
            );
        expect(result.problem, FirstActivationProblem.ownerMismatch);
        // Only the login and the cleanup of that login reached the server.
        expect(backend.paths, [_loginPath, _logoutPath]);
        expect(commit.calls, 0);
        expect(replace.calls, 0);
        expect(result.toString(), isNot(contains(_refresh)));
      });
    }

    test('an unreadable session is replaced through the replacement port only', () async {
      final backend = _Backend();
      final commit = _Commit();
      final replace = _Replace();
      final result = await _coordinator(backend, commit, replace: replace)
          .activate(
            email: 'farmer@example.test',
            password: 'pw',
            requiredScope: _owner,
            replaceUnreadableSession: true,
          );
      expect(result.isCompleted, isTrue);
      expect(commit.calls, 0);
      expect(replace.calls, 1);
      expect(replace.candidate!.memberId, 'member-1');
    });

    test('without a replacement port nothing is registered or stored', () async {
      final backend = _Backend();
      final commit = _Commit();
      final result = await _coordinator(backend, commit).activate(
        email: 'farmer@example.test',
        password: 'pw',
        replaceUnreadableSession: true,
      );
      expect(result.problem, FirstActivationProblem.sessionNotReplaceable);
      expect(backend.paths, [_loginPath, _logoutPath]);
      expect(commit.calls, 0);
    });

    test('a network failure while registering stores nothing', () async {
      final backend = _Backend()..registerError = http.ClientException('down');
      final commit = _Commit();
      final replace = _Replace();
      final result = await _coordinator(backend, commit, replace: replace)
          .activate(
            email: 'farmer@example.test',
            password: 'pw',
            requiredScope: _owner,
            replaceUnreadableSession: true,
          );
      expect(result.isCompleted, isFalse);
      expect(commit.calls, 0);
      expect(replace.calls, 0);
    });

    test('cancelling during login stores nothing', () async {
      final backend = _Backend()..holdLogin = Completer<void>();
      final commit = _Commit();
      final coordinator = _coordinator(backend, commit);
      final pending = coordinator.activate(
        email: 'farmer@example.test',
        password: 'pw',
        requiredScope: _owner,
      );
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.requestCancel(), isTrue);
      backend.holdLogin!.complete();
      final result = await pending;
      expect(result.phase, FirstActivationPhase.cancelled);
      expect(backend.paths, isNot(contains(_registerPath)));
      expect(commit.calls, 0);
    });
  });

  group('recovery mode per state (§2)', () {
    const s = ExistingSessionStartupState.values;
    test('table', () {
      AccessRecoveryMode m(InstallationAccessState? a, ExistingSessionStartupState e) =>
          accessRecoveryModeFor(a, e);
      const unavailable = ExistingSessionStartupState.unavailable;
      for (final access in [
        InstallationAccessState.activatedSessionUnavailable,
        InstallationAccessState.restoredRequiresActivation,
      ]) {
        expect(m(access, ExistingSessionStartupState.noLocalSession), AccessRecoveryMode.signInAsOwner);
        expect(m(access, ExistingSessionStartupState.corrupt), AccessRecoveryMode.signInAsOwner);
        expect(m(access, ExistingSessionStartupState.incompatible), AccessRecoveryMode.signInAsOwner);
        expect(m(access, unavailable), AccessRecoveryMode.storageUnavailable);
        // A readable (possibly expired) session uses the existing /reauth.
        expect(m(access, ExistingSessionStartupState.localSessionExpired), AccessRecoveryMode.none);
      }
      expect(
        m(InstallationAccessState.sessionDamagedNotActivated, ExistingSessionStartupState.corrupt),
        AccessRecoveryMode.rebuildSessionOnly,
      );
      expect(
        m(InstallationAccessState.sessionDamagedNotActivated, unavailable),
        AccessRecoveryMode.storageUnavailable,
      );
      for (final e in s) {
        expect(m(InstallationAccessState.identityMismatch, e), AccessRecoveryMode.signOutForeignSession);
        for (final a in [
          InstallationAccessState.newRequiresActivation,
          InstallationAccessState.activationPendingOwner,
          InstallationAccessState.activated,
          InstallationAccessState.legacyUnbound,
          null,
        ]) {
          expect(m(a, e), AccessRecoveryMode.none, reason: '$a $e');
        }
      }
    });
  });

  group('signing out of a foreign session', () {
    test('logs out remotely once, deletes the session and clears verified access', () async {
      final backend = _Backend();
      final store = _StoredSession(
        SessionReadResult(SessionReadStatus.available, session: _foreignSession()),
      );
      var cleared = 0;
      final result = await ForeignSessionSignOut(
        store: store,
        apiFactory: () => _api(backend),
        clearVerifiedAccess: () => cleared++,
      ).signOut();
      expect(result.outcome, ForeignSignOutOutcome.signedOut);
      expect(result.remoteConfirmed, isTrue);
      expect(backend.paths, [_logoutPath]);
      expect(store.deletes, 1);
      expect(cleared, 1);
    });

    test('without network the local sign-out still happens, unconfirmed remotely', () async {
      final store = _StoredSession(
        SessionReadResult(SessionReadStatus.available, session: _foreignSession()),
      );
      final result = await ForeignSessionSignOut(
        store: store,
        apiFactory: () => throw http.ClientException('offline'),
        clearVerifiedAccess: () {},
      ).signOut();
      expect(result.outcome, ForeignSignOutOutcome.signedOut);
      expect(result.remoteConfirmed, isFalse);
      expect(store.deletes, 1);
    });

    test('an uncertain deletion is reported and nothing else changes', () async {
      final store = _StoredSession(
        SessionReadResult(SessionReadStatus.available, session: _foreignSession()),
      )..failDelete = true;
      final result = await ForeignSessionSignOut(
        store: store,
        apiFactory: () => _api(_Backend()),
        clearVerifiedAccess: () {},
      ).signOut();
      expect(result.outcome, ForeignSignOutOutcome.deletionUncertain);
    });

    test('with no readable session nothing is signed out or called', () async {
      final backend = _Backend();
      final store = _StoredSession(const SessionReadResult(SessionReadStatus.corrupt));
      final result = await ForeignSessionSignOut(
        store: store,
        apiFactory: () => _api(backend),
        clearVerifiedAccess: () => fail('must not clear'),
      ).signOut();
      expect(result.outcome, ForeignSignOutOutcome.nothingToSignOut);
      expect(backend.paths, isEmpty);
      expect(store.deletes, 0);
    });
  });
}
