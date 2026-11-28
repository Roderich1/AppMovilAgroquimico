import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/installation_identity_initializer.dart';
import 'package:agroquimicos/services/auth/api_endpoint_config.dart';
import 'package:agroquimicos/services/auth/existing_session_providers.dart';
import 'package:agroquimicos/services/auth/existing_session_startup.dart';
import 'package:agroquimicos/services/auth/first_activation_providers.dart';
import 'package:agroquimicos/services/auth/local_owner_credential_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/e12_activation_harness.dart';
import 'support/f04_app_access.dart';
import 'support/f04_mode_fixtures.dart';

class _App {
  _App(this.container, this.backend, this.storage);

  final ProviderContainer container;
  final E12Backend backend;
  final E12CredentialStorage storage;
}

Future<void> _settle(WidgetTester tester, {int rounds = 20}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 60; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await _settle(tester, rounds: 1);
  }
}

Future<_App> _mount(WidgetTester tester) async {
  final database = AppDatabase(
    factory: databaseFactoryFfi,
    path: inMemoryDatabasePath,
  );
  addTearDown(database.close);
  final backend = E12Backend();
  final storage = E12CredentialStorage();
  final client = MockClient(backend.respond);
  addTearDown(client.close);
  late _App app;
  final container = ProviderContainer(
    // Sin reintentos automáticos de Riverpod: no dejan temporizadores al
    // terminar la prueba en el Inicio.
    retry: (_, __) => null,
    overrides: [
      existingSessionStartupProvider.overrideWithValue(
        ExistingSessionStartupState.noLocalSession,
      ),
      databaseProvider.overrideWithValue(database),
      ...startupAccessOverrides(
        rereadSession: () async => memberA,
        installationRef: e12InstallationRef,
      ),
      installationIdentityProvider.overrideWithValue(
        const InstallationIdentityInitialization(
          InstallationIdentityStatus.ready,
        ),
      ),
      installationClientIdStoreProvider.overrideWithValue(E12IdentityStore()),
      secureSessionCommitProvider.overrideWithValue(E12CommitPort()),
      apiEndpointConfigProvider.overrideWithValue(
        ApiEndpointConfig(Uri.parse('https://api.example.test')),
      ),
      authHttpTransportProvider.overrideWithValue(client),
      credentialStorageProvider.overrideWithValue(storage),
    ],
  );
  addTearDown(container.dispose);
  app = _App(container, backend, storage);
  tester.view.physicalSize = const Size(500, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const AgroApp()),
  );
  return app;
}

/// Activar con la contraseña y confirmar al titular.
Future<void> _activateAndConfirm(WidgetTester tester, _App app) async {
  await _activate(tester, app);
  await tester.tap(find.byKey(const Key('owner-create-new')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('owner-new-name')), 'Juana');
  await tester.ensureVisible(find.byKey(const Key('owner-confirm')));
  await tester.tap(find.byKey(const Key('owner-confirm')));
  await _waitFor(tester, find.byKey(const Key('local-session-status')));
}

/// Activar con la contraseña hasta «Titular de los datos».
Future<void> _activate(WidgetTester tester, _App app) async {
  await _waitFor(tester, find.byKey(const Key('access-activate')));
  await tester.tap(find.byKey(const Key('access-activate')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('activation-email')),
    'agricultor@example.test',
  );
  await tester.enterText(
    find.byKey(const Key('activation-password')),
    e12Password,
  );
  await tester.tap(find.byKey(const Key('activation-submit')));
  await _waitFor(tester, find.byKey(const Key('owner-confirm')));
  expect(app.backend.paths, [
    '/api/v1/auth/v2/login',
    '/api/v1/auth/clients',
    '/api/v1/auth/v2/session/client',
    '/api/v1/auth/v2/me',
  ]);
}

void main() {
  sqfliteFfiInit();

  testWidgets('activar y vincular al titular abre Inicio sin pedir un PIN', (
    tester,
  ) async {
    final app = await _mount(tester);
    await _activateAndConfirm(tester, app);
    expect(app.storage.values, isEmpty);
    expect(find.text('Crear PIN'), findsNothing);
    expect(find.byKey(const Key('pin-email')), findsNothing);

    app.container.read(routerProvider).push('/titular/pin');
    await _waitFor(tester, find.byKey(const Key('pin-email')));
    expect(
      find.textContaining('Configurar un PIN es opcional'),
      findsOneWidget,
    );
    expect(
      find.textContaining('sólo la persona titular puede aprobar'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('pin-password')), findsOneWidget);
    expect(app.storage.values, isEmpty);
  });
}
