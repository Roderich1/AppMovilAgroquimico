import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/installation_client_id_store.dart';
import 'package:agroquimicos/data/installation_identity_initializer.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/presentation/screens/first_activation_screen.dart';
import 'package:agroquimicos/services/auth/api_endpoint_config.dart';
import 'package:agroquimicos/services/auth/auth_http_client.dart';
import 'package:agroquimicos/services/auth/auth_v2_api.dart';
import 'package:agroquimicos/services/auth/first_activation_coordinator.dart';
import 'package:agroquimicos/services/auth/first_activation_providers.dart';
import 'package:agroquimicos/services/auth/secure_session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _clientId = '550e8400-e29b-41d4-a716-446655440000';
const _registrationId = '550e8400-e29b-41d4-a716-446655440001';
const _password = 'secret-not-for-display';
const _access = 'access-not-for-display';
const _refresh = 'refresh-not-for-display';

Map<String, Object?> _context({String? registrationId}) => {
  'account': {
    'id': 'account-1',
    'name': 'Farmer',
    'email': 'farmer@example.test',
    'isActive': true,
  },
  'member': {'id': 'member-1', 'role': 'AGRICULTOR', 'isActive': true},
  'tenant': {
    'id': 'tenant-1',
    'name': 'Tenant',
    'slug': 'tenant',
    'isActive': true,
  },
  'role': 'AGRICULTOR',
  'session': {
    'id': 'session-1',
    'status': 'ACTIVE',
    'refreshTransport': 'BODY',
    'createdAt': '2026-09-29T10:00:00.000Z',
    'lastSeenAt': '2026-09-29T10:00:00.000Z',
    'expiresAt': '2099-10-05T10:00:00.000Z',
    'clientRegistrationId': registrationId,
  },
};

Map<String, Object?> _login() => {
  'contractVersion': 2,
  'accessToken': _access,
  'refreshToken': _refresh,
  'refreshTransport': 'BODY',
  'sessionExpiresAt': '2099-10-05T10:00:00.000Z',
  'context': _context(),
};

http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status);

class _IdentityStore extends InstallationClientIdStore {
  int reads = 0;
  int creations = 0;
  int rotations = 0;

  @override
  Future<String?> read() async {
    reads++;
    return _clientId;
  }

  @override
  Future<String> getOrCreate() async {
    creations++;
    throw StateError('Activation may not create identity');
  }

  @override
  Future<String> rotate() async {
    rotations++;
    throw StateError('Activation may not rotate identity');
  }
}

class _CommitPort implements SecureSessionCommitPort {
  int calls = 0;
  SessionCommitCandidate? candidate;
  Completer<void>? pending;
  Object? failure;

  @override
  Future<void> commitAndVerify(SessionCommitCandidate value) async {
    calls++;
    candidate = value;
    if (pending != null) await pending!.future;
    if (failure != null) throw failure!;
  }
}

class _Backend {
  final paths = <String>[];
  int loginStatus = 200;
  int registerStatus = 201;
  int meStatus = 200;
  bool malformedLogin = false;
  bool failLoginNetwork = false;
  bool failRegisterNetwork = false;
  bool mismatchedContext = false;
  Completer<http.Response>? pendingLogin;

  int get loginCalls =>
      paths.where((path) => path == '/api/v1/auth/v2/login').length;

  Future<http.Response> respond(http.Request request) async {
    expect(request.url.scheme, 'https');
    expect(request.followRedirects, isFalse);
    paths.add(request.url.path);
    switch (request.url.path) {
      case '/api/v1/auth/v2/login':
        if (failLoginNetwork) throw http.ClientException('secret payload');
        expect(jsonDecode(request.body), {
          'email': 'farmer@example.test',
          'password': _password,
          'refreshTransport': 'BODY',
        });
        if (pendingLogin != null) return pendingLogin!.future;
        if (malformedLogin) return http.Response('{', 200);
        return _json(loginStatus, loginStatus == 200 ? _login() : {});
      case '/api/v1/auth/clients':
        if (failRegisterNetwork) throw http.ClientException('secret payload');
        return _json(registerStatus, {
          'registrationId': _registrationId,
          'status': 'ACTIVE',
          'createdAt': '2026-09-29T10:00:00.000Z',
          'lastSeenAt': '2026-09-29T10:00:00.000Z',
          'revokedAt': null,
        });
      case '/api/v1/auth/v2/session/client':
        return _json(201, {
          'registrationId': _registrationId,
          'status': 'ACTIVE',
        });
      case '/api/v1/auth/v2/me':
        return _json(
          meStatus,
          _context(registrationId: mismatchedContext ? null : _registrationId),
        );
      case '/api/v1/auth/v2/logout':
        return http.Response('', 204);
    }
    fail('Unexpected endpoint');
  }
}

class _Fixture {
  _Fixture(this.router, this.backend, this.identityStore, this.commit);

  final GoRouter router;
  final _Backend backend;
  final _IdentityStore identityStore;
  final _CommitPort commit;
}

Future<_Fixture> _mount(
  WidgetTester tester, {
  InstallationIdentityStatus identity = InstallationIdentityStatus.ready,
  _Backend? backend,
  _CommitPort? commit,
  bool shortTimeout = false,
  bool invalidConfig = false,
}) async {
  final remote = backend ?? _Backend();
  final secure = commit ?? _CommitPort();
  final identityStore = _IdentityStore();
  final mockClient = MockClient(remote.respond);
  final config = ApiEndpointConfig(Uri.parse('https://api.example.test'));
  final router = GoRouter(
    initialLocation: '/activar',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(body: Text('Local')),
      ),
      GoRoute(
        path: '/activar',
        builder: (_, __) => const FirstActivationScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);
  addTearDown(mockClient.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        installationIdentityProvider.overrideWithValue(
          InstallationIdentityInitialization(identity),
        ),
        installationClientIdStoreProvider.overrideWithValue(identityStore),
        secureSessionCommitProvider.overrideWithValue(secure),
        if (invalidConfig)
          apiEndpointConfigProvider.overrideWithValue(null)
        else
          apiEndpointConfigProvider.overrideWithValue(config),
        authHttpTransportProvider.overrideWithValue(mockClient),
        if (shortTimeout)
          authV2ApiProvider.overrideWithValue(
            AuthV2Api(
              AuthHttpClient(
                config: config,
                client: mockClient,
                timeout: const Duration(milliseconds: 1),
              ),
            ),
          ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  return _Fixture(router, remote, identityStore, secure);
}

Future<void> _fill(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('activation-email')),
    'farmer@example.test',
  );
  await tester.enterText(
    find.byKey(const Key('activation-password')),
    _password,
  );
}

Future<void> _submit(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('activation-submit')));
  await tester.pump();
}

Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  sqfliteFfiInit();

  testWidgets('empty form never starts activation', (tester) async {
    final fixture = await _mount(tester);
    await _submit(tester);
    expect(find.text('Ingrese su correo.'), findsOneWidget);
    expect(fixture.backend.paths, isEmpty);
  });

  testWidgets('password is obscured and not rendered as text', (tester) async {
    await _mount(tester);
    final passwordField = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('activation-password')),
        matching: find.byType(EditableText),
      ),
    );
    expect(passwordField.obscureText, isTrue);
    await _fill(tester);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text && (widget.data?.contains(_password) ?? false),
      ),
      findsNothing,
    );
  });

  testWidgets('valid submit calls coordinator once and commits', (
    tester,
  ) async {
    final fixture = await _mount(tester);
    await _fill(tester);
    await _submit(tester);
    await _flush(tester);
    expect(fixture.backend.loginCalls, 1);
    expect(fixture.commit.calls, 1);
    expect(fixture.commit.candidate?.refreshToken, _refresh);
    expect(fixture.router.routeInformationProvider.value.uri.path, '/');
  });

  testWidgets('double tap cannot duplicate login', (tester) async {
    final backend = _Backend()..pendingLogin = Completer<http.Response>();
    final fixture = await _mount(tester, backend: backend);
    await _fill(tester);
    await _submit(tester);
    expect(fixture.backend.loginCalls, 1);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('activation-submit')))
          .onPressed,
      isNull,
    );
    backend.pendingLogin!.complete(_json(200, _login()));
    await _flush(tester);
    expect(fixture.backend.loginCalls, 1);
  });

  testWidgets('progress disables form through secure commit', (tester) async {
    final secure = _CommitPort()..pending = Completer<void>();
    final fixture = await _mount(tester, commit: secure);
    await _fill(tester);
    await _submit(tester);
    await _flush(tester);
    expect(secure.calls, 1);
    expect(fixture.router.routeInformationProvider.value.uri.path, '/activar');
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('activation-password')))
          .enabled,
      isFalse,
    );
    expect(find.text('Guardando sesión de forma segura…'), findsOneWidget);
    secure.pending!.complete();
    await _flush(tester);
  });

  for (final (status, problem) in <(int, FirstActivationProblem)>[
    (400, FirstActivationProblem.invalidRequest),
    (401, FirstActivationProblem.invalidCredentials),
    (429, FirstActivationProblem.rateLimited),
    (403, FirstActivationProblem.remoteError),
  ]) {
    testWidgets('HTTP $status shows only safe error', (tester) async {
      final backend = _Backend()..loginStatus = status;
      final fixture = await _mount(tester, backend: backend);
      await _fill(tester);
      await _submit(tester);
      await _flush(tester);
      expect(find.text(problem.safeMessage), findsOneWidget);
      expect(fixture.commit.calls, 0);
      expect(
        fixture.router.routeInformationProvider.value.uri.path,
        '/activar',
      );
      expect(find.text(_password), findsNothing);
      expect(find.text(_access), findsNothing);
      expect(find.text(_refresh), findsNothing);
    });
  }

  testWidgets('invalid HTTPS configuration fails before HTTP', (tester) async {
    final fixture = await _mount(tester, invalidConfig: true);
    await _fill(tester);
    await _submit(tester);
    await _flush(tester);
    expect(
      find.text(FirstActivationProblem.configuration.safeMessage),
      findsOneWidget,
    );
    expect(fixture.backend.paths, isEmpty);
    expect(fixture.commit.calls, 0);
  });

  testWidgets('registration conflict is safe and does not commit', (
    tester,
  ) async {
    final backend = _Backend()..registerStatus = 409;
    final fixture = await _mount(tester, backend: backend);
    await _fill(tester);
    await _submit(tester);
    await _flush(tester);
    expect(
      find.text(FirstActivationProblem.conflict.safeMessage),
      findsOneWidget,
    );
    expect(fixture.commit.calls, 0);
    expect(fixture.backend.paths.last, '/api/v1/auth/v2/logout');
  });

  testWidgets('unauthorized context never commits', (tester) async {
    final backend = _Backend()..meStatus = 401;
    final fixture = await _mount(tester, backend: backend);
    await _fill(tester);
    await _submit(tester);
    await _flush(tester);
    expect(
      find.text(FirstActivationProblem.unauthorized.safeMessage),
      findsOneWidget,
    );
    expect(fixture.commit.calls, 0);
  });

  testWidgets('mismatched context never commits', (tester) async {
    final backend = _Backend()..mismatchedContext = true;
    final fixture = await _mount(tester, backend: backend);
    await _fill(tester);
    await _submit(tester);
    await _flush(tester);
    expect(
      find.text(FirstActivationProblem.contextMismatch.safeMessage),
      findsOneWidget,
    );
    expect(fixture.commit.calls, 0);
  });

  testWidgets('network failure at login is not retried automatically', (
    tester,
  ) async {
    final backend = _Backend()..failLoginNetwork = true;
    final fixture = await _mount(tester, backend: backend);
    await _fill(tester);
    await _submit(tester);
    await _flush(tester);
    expect(
      find.text(FirstActivationProblem.connection.safeMessage),
      findsOneWidget,
    );
    expect(find.byKey(const Key('activation-reconcile')), findsOneWidget);
    expect(fixture.backend.loginCalls, 1);
    expect(fixture.commit.calls, 0);
  });

  testWidgets('timeout cannot create completion', (tester) async {
    final backend = _Backend()..pendingLogin = Completer<http.Response>();
    final fixture = await _mount(tester, backend: backend, shortTimeout: true);
    await _fill(tester);
    await _submit(tester);
    await tester.pump(const Duration(milliseconds: 30));
    await _flush(tester);
    expect(
      find.text(FirstActivationProblem.timeout.safeMessage),
      findsOneWidget,
    );
    expect(fixture.commit.calls, 0);
    expect(fixture.router.routeInformationProvider.value.uri.path, '/activar');
  });

  for (final identity in [
    InstallationIdentityStatus.corrupt,
    InstallationIdentityStatus.unavailable,
  ]) {
    testWidgets('$identity blocks remote activation', (tester) async {
      final fixture = await _mount(tester, identity: identity);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('activation-submit')))
            .onPressed,
        isNull,
      );
      expect(fixture.backend.paths, isEmpty);
      expect(fixture.identityStore.reads, 0);
      expect(fixture.identityStore.creations, 0);
      expect(fixture.identityStore.rotations, 0);
    });
  }

  testWidgets('completed navigates once and clears password', (tester) async {
    final backend = _Backend()..pendingLogin = Completer<http.Response>();
    final fixture = await _mount(tester, backend: backend);
    var navigations = 0;
    fixture.router.routeInformationProvider.addListener(() {
      if (fixture.router.routeInformationProvider.value.uri.path == '/') {
        navigations++;
      }
    });
    await _fill(tester);
    await _submit(tester);
    backend.pendingLogin!.complete(_json(200, _login()));
    await _flush(tester);
    await _flush(tester);
    expect(navigations, 1);
    expect(find.text('Local'), findsOneWidget);
    expect(find.text(_password), findsNothing);
  });

  testWidgets('secure commit failure never navigates', (tester) async {
    final secure = _CommitPort()
      ..failure = const SecureSessionStorageException(
        SecureSessionFailure.writeFailed,
      );
    final fixture = await _mount(tester, commit: secure);
    await _fill(tester);
    await _submit(tester);
    await _flush(tester);
    expect(
      find.text(FirstActivationProblem.secureCommitFailed.safeMessage),
      findsOneWidget,
    );
    expect(fixture.router.routeInformationProvider.value.uri.path, '/activar');
  });

  testWidgets('unknown local commit requires reconciliation', (tester) async {
    final secure = _CommitPort()
      ..failure = const SecureSessionCommitUncertainException();
    final fixture = await _mount(tester, commit: secure);
    await _fill(tester);
    await _submit(tester);
    await _flush(tester);
    expect(find.byKey(const Key('activation-reconcile')), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('activation-submit')))
          .onPressed,
      isNull,
    );
    expect(fixture.router.routeInformationProvider.value.uri.path, '/activar');
  });

  testWidgets('unknown remote outcome never retries', (tester) async {
    final backend = _Backend()..failRegisterNetwork = true;
    final fixture = await _mount(tester, backend: backend);
    await _fill(tester);
    await _submit(tester);
    await _flush(tester);
    expect(find.byKey(const Key('activation-reconcile')), findsOneWidget);
    expect(fixture.backend.loginCalls, 1);
    expect(fixture.identityStore.rotations, 0);
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('activation-submit')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('cancellation clears password without false success', (
    tester,
  ) async {
    final backend = _Backend()..pendingLogin = Completer<http.Response>();
    final fixture = await _mount(tester, backend: backend);
    await _fill(tester);
    await _submit(tester);
    await tester.tap(find.byKey(const Key('activation-cancel')));
    await tester.pump();
    expect(find.text('Cancelando activación…'), findsOneWidget);
    backend.pendingLogin!.complete(_json(200, _login()));
    await _flush(tester);
    expect(
      find.text(FirstActivationProblem.cancelled.safeMessage),
      findsOneWidget,
    );
    expect(fixture.router.routeInformationProvider.value.uri.path, '/activar');
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('activation-password')))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('malformed JSON remains a safe failure', (tester) async {
    final backend = _Backend()..malformedLogin = true;
    await _mount(tester, backend: backend);
    await _fill(tester);
    await _submit(tester);
    await _flush(tester);
    expect(
      find.text(FirstActivationProblem.invalidResponse.safeMessage),
      findsOneWidget,
    );
    expect(find.text(_access), findsNothing);
  });

  testWidgets('local SQLite remains writable after authentication failure', (
    tester,
  ) async {
    final backend = _Backend()..loginStatus = 401;
    await _mount(tester, backend: backend);
    await _fill(tester);
    await _submit(tester);
    await _flush(tester);
    final id = await tester.runAsync(() async {
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      addTearDown(database.close);
      return AgroRepository(database)
          .addPerson(name: 'Persona local', role: PersonRole.family);
    });
    expect(id, greaterThan(0));
  });

  testWidgets('real app dashboard exposes activation route', (tester) async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(database.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(AgroRepository(database)),
          installationIdentityProvider.overrideWithValue(
            const InstallationIdentityInitialization(
              InstallationIdentityStatus.ready,
            ),
          ),
          secureSessionCommitProvider.overrideWithValue(_CommitPort()),
        ],
        child: const AgroApp(),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      if (find
          .byKey(const Key('open-first-activation'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }
    expect(find.byKey(const Key('open-first-activation')), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-first-activation')));
    await tester.pumpAndSettle();
    expect(find.text('Primera activación'), findsOneWidget);
  });

  test('production DI binds the Android encrypted store factory', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    if (Platform.isAndroid) {
      expect(
        container.read(secureSessionCommitProvider),
        isA<SecureSessionStore>(),
      );
    } else {
      // The production factory is Android-only, never an in-memory fallback.
      expect(
        () => container.read(secureSessionCommitProvider),
        throwsA(
          predicate<Object>(
            (error) => error.toString().contains(
              'SecureSessionStorageException(existingSessionUnreadable)',
            ),
          ),
        ),
      );
    }
  });
}
