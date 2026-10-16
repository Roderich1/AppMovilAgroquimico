import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/presentation/screens/dashboard_screen.dart';
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

class _Guard implements RefreshGuard {
  _Guard(this.quarantined);
  bool quarantined;
  @override
  Future<bool> isQuarantined() async => quarantined;
  @override
  Future<void> quarantine() async => quarantined = true;
  @override
  Future<void> clear() async => quarantined = false;
}

class _NoCommit implements SecureSessionCommitPort {
  @override
  Future<void> commitAndVerify(SessionCommitCandidate candidate) async =>
      throw StateError('No commit expected');
}

class _FixedRemoteController extends RemoteSessionController {
  _FixedRemoteController(this.phase);
  final RemoteSessionPhase phase;
  String? receivedPassword;
  @override
  RemoteSessionState build() => RemoteSessionState(phase);

  @override
  Future<RemoteSessionState> reauthenticate({
    required String email,
    required String password,
  }) async {
    receivedPassword = password;
    return const RemoteSessionState(
      RemoteSessionPhase.requiresReauthentication,
      problem: RemoteSessionProblem.invalidCredentials,
    );
  }
}

Future<void> _settleDashboard(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (find.byType(DashboardScreen).evaluate().isNotEmpty &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      return;
    }
  }
  fail('Dashboard did not settle');
}

void main() {
  sqfliteFfiInit();

  for (final phase in [
    RemoteSessionPhase.idle,
    RemoteSessionPhase.refreshing,
    RemoteSessionPhase.requiresReauthentication,
    RemoteSessionPhase.outcomeUnknown,
    RemoteSessionPhase.configurationUnavailable,
    RemoteSessionPhase.registrationRejected,
  ]) {
    testWidgets('$phase preserves SQLite and makes no startup HTTP', (
      tester,
    ) async {
      final db = AppDatabase(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      addTearDown(db.close);
      final repository = AgroRepository(db);
      // Política #76: instalación ya activada del Member A.
      await tester.runAsync(() => seedActivatedInstallation(db));
      var calls = 0;
      final client = MockClient((http.Request request) async {
        calls++;
        return http.Response('', 500);
      });
      addTearDown(client.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(repository),
            existingSessionStartupProvider.overrideWithValue(
              ExistingSessionStartupState.localSessionAvailable,
            ),
            ...startupAccessOverrides(sessionScope: memberA),
            refreshGuardProvider.overrideWithValue(_Guard(true)),
            remoteSessionProvider.overrideWith(
              () => _FixedRemoteController(phase),
            ),
            authHttpTransportProvider.overrideWithValue(client),
          ],
          child: const AgroApp(),
        ),
      );
      await _settleDashboard(tester);
      final id = await tester.runAsync(
        () => repository.addPerson(
          name: 'Persona local',
          role: PersonRole.family,
        ),
      );
      final rows = await tester.runAsync(
        () async => (await db.database).query(
          'persons',
          where: 'id = ?',
          whereArgs: [id],
        ),
      );
      expect(rows, hasLength(1));
      expect(rows!.single['name'], 'Persona local');
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.byKey(const Key('open-first-activation')), findsNothing);
      expect(find.byKey(const Key('open-reauthentication')), findsOneWidget);
      if (phase == RemoteSessionPhase.idle) {
        await tester.tap(find.byKey(const Key('open-reauthentication')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('reauth-email')), findsOneWidget);
        expect(find.byKey(const Key('reauth-password')), findsOneWidget);
        expect(find.byKey(const Key('activation-submit')), findsNothing);
        await tester.enterText(
          find.byKey(const Key('reauth-email')),
          'farmer@example.test',
        );
        await tester.enterText(
          find.byKey(const Key('reauth-password')),
          'synthetic-password',
        );
        await tester.tap(find.byKey(const Key('reauth-submit')));
        await tester.pumpAndSettle();
        final controller = ProviderScope.containerOf(
          tester.element(find.byKey(const Key('reauth-password'))),
        ).read(remoteSessionProvider.notifier) as _FixedRemoteController;
        expect(controller.receivedPassword, 'synthetic-password');
        expect(
          tester
              .widget<TextFormField>(find.byKey(const Key('reauth-password')))
              .controller!
              .text,
          isEmpty,
        );
        expect(calls, 0);
      }
      final visible = tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data ?? '')
          .join(' ');
      for (final secret in [
        'refreshToken',
        'sessionId',
        'registrationId',
        'accountId',
        'tenantId',
        'synthetic-secret',
      ]) {
        expect(visible, isNot(contains(secret)));
      }
    });
  }

  testWidgets('missing HTTPS configuration fails before guard or network', (
    tester,
  ) async {
    final db = AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(db.close);
    // Política #76: instalación ya activada del Member A.
    await tester.runAsync(() => seedActivatedInstallation(db));
    var calls = 0;
    final client = MockClient((http.Request request) async {
      calls++;
      return http.Response('', 500);
    });
    addTearDown(client.close);
    final guard = _Guard(false);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(AgroRepository(db)),
          ...startupAccessOverrides(sessionScope: memberA),
          existingSessionStartupProvider.overrideWithValue(
            ExistingSessionStartupState.localSessionAvailable,
          ),
          refreshGuardProvider.overrideWithValue(guard),
          storedSessionReaderProvider.overrideWithValue(
            () async => SessionReadResult(
              SessionReadStatus.available,
              session: StoredSession(
                refreshToken: 'synthetic-secret',
                installationClientId: '550e8400-e29b-41d4-a716-446655440000',
                registrationId: 'registration-1',
                accountId: 'account-1',
                memberId: 'member-1',
                tenantId: 'tenant-1',
                sessionId: 'session-1',
                expiresAt: DateTime.utc(2026, 10, 5),
              ),
            ),
          ),
          secureSessionCommitProvider.overrideWithValue(_NoCommit()),
          apiEndpointConfigProvider.overrideWithValue(null),
          authHttpTransportProvider.overrideWithValue(client),
        ],
        child: const AgroApp(),
      ),
    );
    await _settleDashboard(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('verify-online-access')), findsOneWidget);
    await tester.tap(find.byKey(const Key('verify-online-access')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('conexión segura todavía no está configurada'),
      findsOneWidget,
    );
    expect(guard.quarantined, isFalse);
    expect(calls, 0);
  });

  // #83: el Dashboard mostraba a la vez «aún no fue verificado» y el estado
  // remoto vigente (visto en el POCO el 2026-10-15). Debe haber un solo
  // mensaje de estado de acceso.
  group('un solo mensaje de estado de acceso (#83)', () {
    const startupPending =
        'Cuenta vinculada en este dispositivo. '
        'El estado en línea aún no fue verificado.';
    const idleRemote = 'El acceso en línea todavía no se verificó.';
    const verified = 'Acceso en línea verificado para esta sesión.';
    const reauth =
        'Se requiere volver a autenticar para las funciones en línea. '
        'Sus datos locales siguen disponibles.';

    Future<void> pumpStatus(
      WidgetTester tester, {
      required RemoteSessionPhase phase,
      required bool quarantined,
    }) async {
      final db = AppDatabase(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      addTearDown(db.close);
      await tester.runAsync(() => seedActivatedInstallation(db));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(AgroRepository(db)),
            existingSessionStartupProvider.overrideWithValue(
              ExistingSessionStartupState.localSessionAvailable,
            ),
            ...startupAccessOverrides(sessionScope: memberA),
            refreshGuardProvider.overrideWithValue(_Guard(quarantined)),
            remoteSessionProvider.overrideWith(
              () => _FixedRemoteController(phase),
            ),
          ],
          child: const AgroApp(),
        ),
      );
      await _settleDashboard(tester);
      await tester.pumpAndSettle();
    }

    for (final (name, phase, quarantined, expected, button) in [
      (
        'arranque sin verificar',
        RemoteSessionPhase.idle,
        false,
        startupPending,
        'verify-online-access',
      ),
      (
        'verificación correcta',
        RemoteSessionPhase.remoteAvailable,
        false,
        verified,
        'verify-online-access',
      ),
      (
        'reautenticación requerida tras un 401',
        RemoteSessionPhase.requiresReauthentication,
        false,
        reauth,
        'open-reauthentication',
      ),
      (
        'reapertura con el guard en cuarentena',
        RemoteSessionPhase.idle,
        true,
        reauth,
        'open-reauthentication',
      ),
    ]) {
      testWidgets(name, (tester) async {
        await pumpStatus(tester, phase: phase, quarantined: quarantined);
        final status = find.byKey(const Key('local-session-status'));
        expect(status, findsOneWidget);
        expect(tester.widget<Text>(status).data, expected);
        for (final other in [startupPending, idleRemote, verified, reauth]) {
          if (other != expected) expect(find.text(other), findsNothing);
        }
        expect(find.byKey(Key(button)), findsOneWidget);
      });
    }
  });
}
