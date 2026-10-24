// F03 «Recuperar acceso» en la app real: base, router, compuerta y controlador
// de acceso reales; sólo se sustituyen el almacén seguro y el servidor. Cada
// caso compara el volcado completo de SQLite antes y después: la recuperación
// no borra, no reasigna y no libera una cola RESTORE_PAUSED.
import 'dart:convert';

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/installation_client_id_store.dart';
import 'package:agroquimicos/data/installation_identity_initializer.dart';
import 'package:agroquimicos/domain/installation_access.dart';
import 'package:agroquimicos/installation_access.dart';
import 'package:agroquimicos/services/auth/access_recovery.dart';
import 'package:agroquimicos/services/auth/api_endpoint_config.dart';
import 'package:agroquimicos/services/auth/auth_http_client.dart';
import 'package:agroquimicos/services/auth/auth_v2_api.dart';
import 'package:agroquimicos/services/auth/existing_session_providers.dart';
import 'package:agroquimicos/services/auth/existing_session_startup.dart';
import 'package:agroquimicos/services/auth/first_activation_coordinator.dart';
import 'package:agroquimicos/services/auth/first_activation_providers.dart';
import 'package:agroquimicos/services/auth/refresh_guard.dart';
import 'package:agroquimicos/services/auth/remote_session_coordinator.dart';
import 'package:agroquimicos/services/auth/remote_session_providers.dart';
import 'package:agroquimicos/services/auth/secure_session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_app_access.dart';
import 'support/f04_mode_fixtures.dart';

const _clientId = '11111111-1111-4111-8111-111111111111';
const _registrationId = '550e8400-e29b-41d4-a716-446655440001';

class _Identity extends InstallationClientIdStore {
  @override
  Future<String?> read() async => _clientId;
}

class _Server {
  _Server(this.signedIn);

  OwnerScope signedIn;
  final paths = <String>[];

  Map<String, Object?> _context({String? registrationId}) => {
    'account': {
      'id': 'account-1',
      'name': 'Synthetic Farmer',
      'email': 'farmer@example.test',
      'isActive': true,
    },
    'member': {'id': signedIn.memberId, 'role': 'AGRICULTOR', 'isActive': true},
    'tenant': {
      'id': signedIn.tenantId,
      'name': 'Synthetic Union',
      'slug': 'union',
      'isActive': true,
    },
    'role': 'AGRICULTOR',
    'session': {
      'id': 'session-1',
      'status': 'ACTIVE',
      'refreshTransport': 'BODY',
      'createdAt': '2026-10-23T10:00:00.000Z',
      'lastSeenAt': '2026-10-23T10:00:00.000Z',
      'expiresAt': '2099-10-30T10:00:00.000Z',
      'clientRegistrationId': registrationId,
    },
  };

  Future<http.Response> respond(http.Request request) async {
    paths.add(request.url.path);
    http.Response json(int status, Object body) =>
        http.Response(jsonEncode(body), status);
    switch (request.url.path) {
      case '/api/v1/auth/v2/login':
        return json(200, {
          'contractVersion': 2,
          'accessToken': 'access-test',
          'refreshToken': 'refresh-test',
          'refreshTransport': 'BODY',
          'sessionExpiresAt': '2099-10-30T10:00:00.000Z',
          'context': _context(),
        });
      case '/api/v1/auth/clients':
        return json(201, {
          'registrationId': _registrationId,
          'status': 'ACTIVE',
          'createdAt': '2026-10-23T10:00:00.000Z',
          'lastSeenAt': '2026-10-23T10:00:00.000Z',
          'revokedAt': null,
        });
      case '/api/v1/auth/v2/session/client':
        return json(201, {
          'registrationId': _registrationId,
          'status': 'ACTIVE',
        });
      case '/api/v1/auth/v2/me':
        return json(200, _context(registrationId: _registrationId));
      case '/api/v1/auth/v2/logout':
        return http.Response('', 204);
    }
    return http.Response('', 404);
  }
}

class _Commit implements SecureSessionCommitPort {
  int calls = 0;
  @override
  Future<void> commitAndVerify(SessionCommitCandidate candidate) async =>
      calls++;
}

class _Replace implements UnreadableSessionReplacementPort {
  int calls = 0;
  @override
  Future<void> replaceUnreadableAndVerify(SessionCommitCandidate c) async =>
      calls++;
}

class _Stored implements StoredSessionAccess {
  _Stored(this.result);
  SessionReadResult result;
  int deletes = 0;

  @override
  Future<SessionReadResult> read() async => result;

  @override
  Future<void> delete() async {
    deletes++;
    result = const SessionReadResult(SessionReadStatus.absent);
  }
}

class _ClearGuard implements RefreshGuard {
  @override
  Future<bool> isQuarantined() async => false;
  @override
  Future<void> quarantine() async {}
  @override
  Future<void> clear() async {}
}

class _IdleRemote extends RemoteSessionController {
  @override
  RemoteSessionState build() =>
      const RemoteSessionState(RemoteSessionPhase.idle);
}

void main() {
  sqfliteFfiInit();

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// Base con titular vinculado al Member A y una intención RESTORE_PAUSED.
  Future<AppDatabase> boundDatabase(
    WidgetTester tester, {
    required String activatedIn,
  }) async {
    final file = await tester.runAsync(() => tempDbPath('f03'));
    final database = openDb(file!);
    await tester.runAsync(() async {
      final binding = await seedActivatedInstallation(
        database,
        installationRef: activatedIn,
      );
      final db = await database.database;
      await db.insert('sync_outbox', {
        'operation_id': '9b2f0f1e-1111-4222-8333-444455556666',
        'owner_binding_id': binding.id,
        'projection_type': 'DECLARED_NEED',
        'action': 'PUBLISH',
        'campaign_ref': 'campaign-ref',
        'product_ref': 'product-ref',
        'base_unit': 'ML',
        'quantity_base': '1000',
        'status': 'RESTORE_PAUSED',
        'created_at': '2026-10-23T10:00:00.000Z',
        'updated_at': '2026-10-23T10:00:00.000Z',
      });
    });
    return database;
  }

  Future<Map<String, List<Map<String, Object?>>>> dump(
    WidgetTester tester,
    AppDatabase database,
  ) async =>
      (await tester.runAsync(() async => dumpTables(await database.database)))!;

  Future<ProviderContainer> pumpApp(
    WidgetTester tester,
    AppDatabase database, {
    required ExistingSessionStartupState session,
    required _Server server,
    required _Commit commit,
    required _Replace replace,
    OwnerScope? startupScope,
    _Stored? stored,
  }) async {
    OwnerScope? reread;
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        existingSessionStartupProvider.overrideWithValue(session),
        ...startupAccessOverrides(
          sessionScope: startupScope,
          installationRef: installationHere,
          // Tras una recuperación correcta, la sesión releída es la del
          // servidor; tras una salida, ninguna.
          rereadSession: () async => reread,
        ),
        refreshGuardProvider.overrideWithValue(_ClearGuard()),
        remoteSessionProvider.overrideWith(_IdleRemote.new),
        installationIdentityProvider.overrideWithValue(
          const InstallationIdentityInitialization(
            InstallationIdentityStatus.ready,
          ),
        ),
        installationClientIdStoreProvider.overrideWithValue(_Identity()),
        apiEndpointConfigProvider.overrideWithValue(
          ApiEndpointConfig(Uri.parse('https://api.example.test')),
        ),
        authV2ApiProvider.overrideWithValue(
          AuthV2Api(
            AuthHttpClient(
              config: ApiEndpointConfig(Uri.parse('https://api.example.test')),
              client: MockClient((request) async {
                final response = await server.respond(request);
                if (request.url.path == '/api/v1/auth/v2/me') {
                  reread = server.signedIn;
                }
                return response;
              }),
            ),
          ),
        ),
        secureSessionCommitProvider.overrideWithValue(commit),
        secureSessionReplacementProvider.overrideWithValue(replace),
        if (stored != null)
          storedSessionAccessProvider.overrideWithValue(stored),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const AgroApp()),
    );
    await settle(tester);
    return container;
  }

  Future<void> submitRecovery(WidgetTester tester, ProviderContainer c) async {
    c.read(routerProvider).go('/recuperar');
    await settle(tester);
    await tester.enterText(
      find.byKey(const Key('recovery-email')),
      'farmer@example.test',
    );
    await tester.enterText(find.byKey(const Key('recovery-password')), 'pw');
    await tester.tap(find.byKey(const Key('recovery-submit')));
    await settle(tester);
  }

  testWidgets(
    'activated, corrupt session: the titular recovers and nothing in SQLite changes',
    (tester) async {
      final database = await boundDatabase(
        tester,
        activatedIn: installationHere,
      );
      final before = await dump(tester, database);
      final server = _Server(memberA);
      final commit = _Commit();
      final replace = _Replace();
      final c = await pumpApp(
        tester,
        database,
        session: ExistingSessionStartupState.corrupt,
        server: server,
        commit: commit,
        replace: replace,
      );
      expect(
        c.read(installationAccessProvider),
        InstallationAccessState.activatedSessionUnavailable,
      );
      expect(find.byKey(const Key('open-access-recovery')), findsOneWidget);

      await submitRecovery(tester, c);

      expect(replace.calls, 1);
      expect(commit.calls, 0);
      expect(
        c.read(installationAccessProvider),
        InstallationAccessState.activated,
      );
      expect(
        c.read(effectiveLocalSessionProvider),
        ExistingSessionStartupState.localSessionAvailable,
      );
      expect(server.paths, [
        '/api/v1/auth/v2/login',
        '/api/v1/auth/clients',
        '/api/v1/auth/v2/session/client',
        '/api/v1/auth/v2/me',
      ]);
      // Every table, including owner_bindings and the RESTORE_PAUSED intent.
      expect(await dump(tester, database), before);
    },
  );

  testWidgets(
    'restored elsewhere: another account stores nothing; the titular activates and only the installation is recorded',
    (tester) async {
      final database = await boundDatabase(
        tester,
        activatedIn: installationElsewhere,
      );
      final before = await dump(tester, database);
      final server = _Server(memberB);
      final commit = _Commit();
      final replace = _Replace();
      final c = await pumpApp(
        tester,
        database,
        session: ExistingSessionStartupState.noLocalSession,
        server: server,
        commit: commit,
        replace: replace,
      );
      expect(
        c.read(installationAccessProvider),
        InstallationAccessState.restoredRequiresActivation,
      );
      // No free activation is offered with a bound titular.
      expect(find.byKey(const Key('access-activate')), findsNothing);
      expect(find.byKey(const Key('access-recover')), findsOneWidget);

      await submitRecovery(tester, c);
      expect(commit.calls, 0);
      expect(server.paths, ['/api/v1/auth/v2/login', '/api/v1/auth/v2/logout']);
      expect(
        c.read(installationAccessProvider),
        InstallationAccessState.restoredRequiresActivation,
      );
      expect(find.byKey(const Key('recovery-message')), findsOneWidget);
      expect(await dump(tester, database), before);

      server
        ..signedIn = memberA
        ..paths.clear();
      await tester.enterText(find.byKey(const Key('recovery-password')), 'pw');
      await tester.tap(find.byKey(const Key('recovery-submit')));
      await settle(tester);
      expect(commit.calls, 1);
      expect(
        c.read(installationAccessProvider),
        InstallationAccessState.activated,
      );
      final after = await dump(tester, database);
      // The RESTORE_PAUSED intent and the binding are unchanged.
      expect(after['sync_outbox'], before['sync_outbox']);
      expect(after['owner_bindings'], before['owner_bindings']);
      // Only the activated installation reference changed in app_settings.
      final changed = {
        for (final row in after['app_settings']!)
          if (!before['app_settings']!.any(
            (old) => old['key'] == row['key'] && old['value'] == row['value'],
          ))
            row['key'],
      };
      expect(changed, {AppDatabase.activatedInstallationKey});
    },
  );

  testWidgets(
    'foreign session: signing out deletes only that session and offers recovery',
    (tester) async {
      final database = await boundDatabase(
        tester,
        activatedIn: installationHere,
      );
      final before = await dump(tester, database);
      final stored = _Stored(
        SessionReadResult(
          SessionReadStatus.available,
          session: StoredSession(
            refreshToken: 'foreign-refresh',
            installationClientId: _clientId,
            registrationId: _registrationId,
            accountId: 'account-9',
            memberId: memberB.memberId,
            tenantId: memberB.tenantId,
            sessionId: 'session-9',
            expiresAt: DateTime.utc(2099),
          ),
        ),
      );
      final server = _Server(memberB);
      final c = await pumpApp(
        tester,
        database,
        session: ExistingSessionStartupState.localSessionAvailable,
        startupScope: memberB,
        server: server,
        commit: _Commit(),
        replace: _Replace(),
        stored: stored,
      );
      expect(
        c.read(installationAccessProvider),
        InstallationAccessState.identityMismatch,
      );
      c.read(routerProvider).go('/recuperar');
      await settle(tester);
      await tester.tap(find.byKey(const Key('recovery-signout')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('recovery-signout-confirm')));
      await settle(tester);

      expect(stored.deletes, 1);
      expect(server.paths, ['/api/v1/auth/v2/logout']);
      expect(
        c.read(effectiveLocalSessionProvider),
        ExistingSessionStartupState.noLocalSession,
      );
      expect(
        c.read(installationAccessProvider),
        InstallationAccessState.activatedSessionUnavailable,
      );
      expect(await dump(tester, database), before);
    },
  );
}
