// F03 (DEVICE del 2026-10-24, POCO X5 Pro): con la sesión sana, «Confirmar en
// línea» del PIN del titular no salía a la red y dejaba la app en «volver a
// autenticar». La acreditación usaba reauthenticate, que sólo recupera una
// sesión en cuarentena. Esta prueba ejerce el provider real con el
// coordinador real: sólo el almacén, el guard y HTTP son dobles.
import 'dart:convert';

import 'package:agroquimicos/domain/installation_access.dart';
import 'package:agroquimicos/installation_access.dart';
import 'package:agroquimicos/services/auth/api_endpoint_config.dart';
import 'package:agroquimicos/services/auth/auth_http_client.dart';
import 'package:agroquimicos/services/auth/auth_v2_api.dart';
import 'package:agroquimicos/services/auth/first_activation_coordinator.dart';
import 'package:agroquimicos/services/auth/first_activation_providers.dart';
import 'package:agroquimicos/services/auth/local_owner_credential.dart';
import 'package:agroquimicos/services/auth/local_owner_credential_providers.dart';
import 'package:agroquimicos/services/auth/refresh_guard.dart';
import 'package:agroquimicos/services/auth/remote_session_coordinator.dart';
import 'package:agroquimicos/services/auth/remote_session_providers.dart';
import 'package:agroquimicos/services/auth/secure_session_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// El provider usa el reloj real: la sesión caduca en el futuro.
const _expiry = '2099-01-01T00:00:00.000Z';
const _loginPath = '/api/v1/auth/v2/login';
const _logoutPath = '/api/v1/auth/v2/logout';
const _scope = OwnerScope(memberId: 'member-1', tenantId: 'tenant-1');

final _stored = StoredSession(
  refreshToken: 'synthetic-old-refresh',
  installationClientId: '550e8400-e29b-41d4-a716-446655440000',
  registrationId: 'registration-1',
  accountId: 'account-1',
  memberId: 'member-1',
  tenantId: 'tenant-1',
  sessionId: 'session-1',
  expiresAt: DateTime.parse(_expiry),
);

Map<String, Object?> _login({String account = 'account-1'}) => {
  'contractVersion': 2,
  'accessToken': 'synthetic-access',
  'refreshToken': 'synthetic-login-refresh',
  'refreshTransport': 'BODY',
  'sessionExpiresAt': _expiry,
  'context': {
    'account': {
      'id': account,
      'name': 'Synthetic',
      'email': 'farmer@example.test',
      'isActive': true,
    },
    'member': {'id': 'member-1', 'role': 'AGRICULTOR', 'isActive': true},
    'tenant': {
      'id': 'tenant-1',
      'name': 'Synthetic',
      'slug': 'synthetic',
      'isActive': true,
    },
    'role': 'AGRICULTOR',
    'session': {
      'id': 'session-2',
      'status': 'ACTIVE',
      'refreshTransport': 'BODY',
      'createdAt': '2026-10-01T10:00:00.000Z',
      'lastSeenAt': '2026-10-01T10:00:00.000Z',
      'expiresAt': _expiry,
      'clientRegistrationId': null,
    },
  },
};

class _HealthyGuard implements RefreshGuard {
  final events = <String>[];

  @override
  Future<bool> isQuarantined() async {
    events.add('read');
    return false;
  }

  @override
  Future<void> quarantine() async => events.add('set');

  @override
  Future<void> clear() async => events.add('clear');
}

class _NoCommit implements SecureSessionCommitPort {
  int calls = 0;

  @override
  Future<void> commitAndVerify(SessionCommitCandidate value) async => calls++;
}

void main() {
  late List<String> paths;
  late _HealthyGuard guard;
  late _NoCommit commit;

  ProviderContainer container({String account = 'account-1'}) {
    paths = [];
    guard = _HealthyGuard();
    commit = _NoCommit();
    final config = ApiEndpointConfig(Uri.parse('https://api.example.test'));
    final api = AuthV2Api(
      AuthHttpClient(
        config: config,
        client: MockClient((request) async {
          paths.add(request.url.path);
          return switch (request.url.path) {
            _loginPath => http.Response(
              jsonEncode(_login(account: account)),
              200,
            ),
            _logoutPath => http.Response('', 204),
            _ => fail('Unexpected endpoint ${request.url.path}'),
          };
        }),
      ),
    );
    final c = ProviderContainer(
      overrides: [
        storedSessionReaderProvider.overrideWithValue(
          () async =>
              SessionReadResult(SessionReadStatus.available, session: _stored),
        ),
        secureSessionCommitProvider.overrideWithValue(commit),
        refreshGuardProvider.overrideWithValue(guard),
        apiEndpointConfigProvider.overrideWithValue(config),
        authV2ApiProvider.overrideWithValue(api),
        sessionScopeReaderProvider.overrideWithValue(() async => _scope),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  const binding = OwnerBindingContext(bindingId: 1, personId: 1, scope: _scope);

  test('healthy session: the owner is confirmed online and nothing else '
      'changes', () async {
    final c = container();
    final proof = await c
        .read(ownerOnlineVerificationProvider)
        .verify(
          email: 'farmer@example.test',
          password: 'synthetic-password',
          binding: binding,
        );
    expect(proof, isNotNull);
    expect(paths, [_loginPath, _logoutPath]);
    expect(commit.calls, 0);
    expect(guard.events, isEmpty);
    expect(
      c.read(remoteSessionProvider).phase,
      isNot(RemoteSessionPhase.requiresReauthentication),
    );
  });

  test('another account is not the owner and its login is closed', () async {
    final c = container(account: 'other');
    final proof = await c
        .read(ownerOnlineVerificationProvider)
        .verify(
          email: 'farmer@example.test',
          password: 'synthetic-password',
          binding: binding,
        );
    expect(proof, isNull);
    expect(paths, [_loginPath, _logoutPath]);
    expect(commit.calls, 0);
  });
}
