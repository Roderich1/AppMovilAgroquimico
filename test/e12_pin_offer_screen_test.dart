// E-12 (F03 §4 bis.2) en la app real: activar, confirmar al titular y crear
// el primer PIN sin volver a escribir la contraseña ni salir a la red. Y los
// casos en que no se ofrece o ya no vale: «Ahora no», Atrás, vencida, salir
// de la app, otra sesión y un PIN del titular ya existente.
import 'dart:async';

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/operation_mode_controller.dart';
import 'package:agroquimicos/data/installation_identity_initializer.dart';
import 'package:agroquimicos/presentation/screens/owner_credential_screen.dart';
import 'package:agroquimicos/services/auth/activation_owner_evidence.dart';
import 'package:agroquimicos/services/auth/api_endpoint_config.dart';
import 'package:agroquimicos/services/auth/existing_session_providers.dart';
import 'package:agroquimicos/services/auth/existing_session_startup.dart';
import 'package:agroquimicos/services/auth/first_activation_providers.dart';
import 'package:agroquimicos/services/auth/local_owner_credential.dart';
import 'package:agroquimicos/services/auth/local_owner_credential_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/e12_activation_harness.dart';
import 'support/f04_app_access.dart';
import 'support/f04_mode_fixtures.dart';

const _pin = '284917';

class _App {
  _App(this.container, this.backend, this.clock, this.storage);

  final ProviderContainer container;
  final E12Backend backend;
  final E12Clock clock;
  final E12CredentialStorage storage;
  SessionIdentity? session = e12Identity;

  FirstActivationController get activation =>
      container.read(firstActivationProvider.notifier);
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

Future<void> _lifecycle(AppLifecycleState state) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        SystemChannels.lifecycle.name,
        SystemChannels.lifecycle.codec.encodeMessage(state.toString()),
        (_) {},
      );
}

/// La app real con Auth V2 y almacenes simulados; [preparePin] puede dejar
/// un PIN previo en el almacén de la credencial.
/// Retiene la recarga de la modalidad tras vincular (entre el vínculo y la
/// oferta) mientras [gate] esté abierto.
class _GatedMode extends OperationModeController {
  Completer<void>? gate;

  @override
  Future<OperationMode?> reload() async {
    final pending = gate;
    if (pending != null) await pending.future;
    return super.reload();
  }
}

Future<_App> _mount(
  WidgetTester tester, {
  Future<void> Function(E12CredentialStorage storage)? preparePin,
  List<Override> extra = const [],
}) async {
  final database = AppDatabase(
    factory: databaseFactoryFfi,
    path: inMemoryDatabasePath,
  );
  addTearDown(database.close);
  final backend = E12Backend();
  final clock = E12Clock();
  final storage = E12CredentialStorage();
  if (preparePin != null) await tester.runAsync(() => preparePin(storage));
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
      activationEvidenceClockProvider.overrideWithValue(clock.evidenceClock),
      credentialStorageProvider.overrideWithValue(storage),
      localOwnerCredentialProvider.overrideWith(
        (ref) => LocalOwnerCredential(
          storage: ref.watch(credentialStorageProvider),
          onlineVerification: ref.watch(ownerOnlineVerificationProvider),
          iterations: 1000,
        ),
      ),
      storedSessionIdentityReaderProvider.overrideWithValue(
        () async => app.session,
      ),
      ...extra,
    ],
  );
  addTearDown(container.dispose);
  app = _App(container, backend, clock, storage);
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
  await _waitFor(
    tester,
    find.byWidgetPredicate(
      (w) =>
          w.key == const Key('pin-activation-notice') ||
          w.key == const Key('local-session-status'),
    ),
  );
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
  for (var i = 0; i < 40 && !app.activation.hasActivationEvidence; i++) {
    await _settle(tester, rounds: 1);
  }
  expect(app.activation.hasActivationEvidence, isTrue);
  expect(app.backend.paths, [
    '/api/v1/auth/v2/login',
    '/api/v1/auth/clients',
    '/api/v1/auth/v2/session/client',
    '/api/v1/auth/v2/me',
  ]);
}

Future<void> _typePin(WidgetTester tester, String pin, String confirm) async {
  await tester.enterText(find.byKey(const Key('pin-new')), pin);
  await tester.enterText(find.byKey(const Key('pin-confirm')), confirm);
  await tester.ensureVisible(find.byKey(const Key('pin-activation-create')));
  await tester.tap(find.byKey(const Key('pin-activation-create')));
  await _settle(tester);
}

void expectNoSecrets() {
  for (final secret in [e12Password, e12Access, e12Refresh, _pin]) {
    expect(find.textContaining(secret), findsNothing);
  }
}

void main() {
  sqfliteFfiInit();

  testWidgets('U1/E1 en host: tras confirmar al titular se ofrece el PIN con '
      'su explicación, sin contraseña; se crea sin red y autoriza', (
    tester,
  ) async {
    final app = await _mount(tester);
    await _activateAndConfirm(tester, app);

    expect(find.byKey(const Key('pin-activation-notice')), findsOneWidget);
    expect(
      find.text(
        'Titular vinculado. Usa inventario compartido; puede cambiarlo en '
        'Operaciones › Más › Modo de uso.',
      ),
      findsOneWidget,
    );
    expect(find.text(ActivationPinTexts.offer), findsOneWidget);
    expect(find.text(ActivationPinTexts.whyNow), findsOneWidget);
    expect(find.text(ActivationPinTexts.separation), findsOneWidget);
    expect(find.text('Crear PIN'), findsOneWidget);
    expect(find.text('Ahora no'), findsOneWidget);
    expect(find.byKey(const Key('pin-email')), findsNothing);
    expect(find.byKey(const Key('pin-password')), findsNothing);
    final pathsAfterActivation = List<String>.of(app.backend.paths);

    // Un error de tecleo no gasta la acreditación.
    await _typePin(tester, _pin, '502813');
    expect(find.text('Los dos PIN no coinciden.'), findsOneWidget);
    expect(app.activation.hasActivationEvidence, isTrue);
    expect(app.storage.values, isEmpty);

    await _typePin(tester, _pin, _pin);
    expect(find.text(ActivationPinTexts.done), findsOneWidget);
    expect(app.backend.paths, pathsAfterActivation, reason: 'sin red');
    expect(app.activation.hasActivationEvidence, isFalse, reason: 'consumida');
    expect(app.storage.values.keys.toSet(), {'verifier', 'attempts'});
    final binding = await tester.runAsync(
      () => app.container.read(ownerBindingContextReaderProvider)(),
    );
    final credential = app.container.read(localOwnerCredentialProvider);
    final status = await tester.runAsync(() => credential.status(binding));
    expect(status!.state, CredentialState.enrolled);
    final auth = await tester.runAsync(
      () => credential.verify(
        pin: _pin,
        purpose: AuthorizationPurpose.reversePurchase,
        subjectRef: 'purchase:1',
        binding: binding!,
      ),
    );
    expect(credential.accepts(auth!), isTrue);
    expectNoSecrets();

    await tester.tap(find.byKey(const Key('pin-activation-continue')));
    await _waitFor(tester, find.byKey(const Key('local-session-status')));
    expect(find.byKey(const Key('local-session-status')), findsOneWidget);
  });

  testWidgets('T5/E2 en host: «Ahora no» la anula; después el PIN pide la '
      'contraseña', (tester) async {
    final app = await _mount(tester);
    await _activateAndConfirm(tester, app);
    await tester.ensureVisible(find.byKey(const Key('pin-activation-skip')));
    await tester.tap(find.byKey(const Key('pin-activation-skip')));
    await _waitFor(tester, find.byKey(const Key('local-session-status')));
    await _settle(tester);
    expect(find.text(ActivationPinTexts.skipped), findsOneWidget);
    expect(app.activation.hasActivationEvidence, isFalse);
    expect(app.storage.values, isEmpty);

    app.container.read(routerProvider).push('/titular/pin');
    await _settle(tester);
    expect(find.byKey(const Key('pin-email')), findsOneWidget);
    expect(find.byKey(const Key('pin-password')), findsOneWidget);
  });

  testWidgets('T5: Atrás en la oferta equivale a «Ahora no»', (tester) async {
    final app = await _mount(tester);
    await _activateAndConfirm(tester, app);
    await tester.binding.handlePopRoute();
    await _waitFor(tester, find.byKey(const Key('local-session-status')));
    await _settle(tester);
    expect(find.text(ActivationPinTexts.skipped), findsOneWidget);
    expect(app.activation.hasActivationEvidence, isFalse);
    expect(app.storage.values, isEmpty);
  });

  testWidgets('W8: salir de «Titular de los datos» sin vincular la anula', (
    tester,
  ) async {
    final app = await _mount(tester);
    await _activate(tester, app);
    expect(find.byKey(const Key('owner-confirm')), findsOneWidget);
    // La pantalla se cierra sin confirmar (la app sale de esa ruta).
    await tester.pumpWidget(const SizedBox());
    await _settle(tester, rounds: 2);
    expect(app.activation.hasActivationEvidence, isFalse);
  });

  testWidgets('W8b: si «Titular de los datos» se desmonta después de vincular '
      'y antes de la oferta, la acreditación se anula', (tester) async {
    final mode = _GatedMode();
    final app = await _mount(
      tester,
      extra: [operationModeProvider.overrideWith(() => mode)],
    );
    await _activate(tester, app);
    await tester.tap(find.byKey(const Key('owner-create-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('owner-new-name')), 'Juana');
    await tester.ensureVisible(find.byKey(const Key('owner-confirm')));
    mode.gate = Completer<void>();
    await tester.tap(find.byKey(const Key('owner-confirm')));
    final database = app.container.read(databaseProvider);
    OwnerBinding? bound;
    for (var i = 0; i < 40 && bound == null; i++) {
      await _settle(tester, rounds: 1);
      bound = await tester.runAsync<OwnerBinding?>(
        () => OwnerBindingStore(database).activeBinding(),
      );
    }
    expect(bound, isNotNull, reason: 'ya se vinculó');
    await _settle(tester, rounds: 3);
    expect(
      app.activation.hasActivationEvidence,
      isTrue,
      reason: 'atada y viva mientras se espera la oferta',
    );
    await tester.pumpWidget(const SizedBox());
    await _settle(tester, rounds: 2);
    expect(app.activation.hasActivationEvidence, isFalse);
    mode.gate!.complete();
    await _settle(tester, rounds: 2);
    expect(app.activation.hasActivationEvidence, isFalse);
    expect(app.storage.values, isEmpty);
  });

  testWidgets('T3: vencida (más de 10 minutos) no crea el PIN', (tester) async {
    final app = await _mount(tester);
    await _activateAndConfirm(tester, app);
    app.clock.advance(const Duration(minutes: 10, seconds: 1));
    await _typePin(tester, _pin, _pin);
    expect(find.text(ActivationPinTexts.expired), findsOneWidget);
    expect(app.storage.values, isEmpty);
    expectNoSecrets();
  });

  testWidgets(
    'T16: apagar la pantalla o cambiar de app en la oferta la anula',
    (tester) async {
      final app = await _mount(tester);
      await _activateAndConfirm(tester, app);
      await _lifecycle(AppLifecycleState.inactive);
      await _lifecycle(AppLifecycleState.hidden);
      expect(app.activation.hasActivationEvidence, isFalse);
      await _lifecycle(AppLifecycleState.inactive);
      await _lifecycle(AppLifecycleState.resumed);
      await _settle(tester, rounds: 2);
      await _typePin(tester, _pin, _pin);
      expect(find.text(ActivationPinTexts.expired), findsOneWidget);
      expect(app.storage.values, isEmpty);
    },
  );

  testWidgets('T1: otra sesión guardada entre la activación y el PIN', (
    tester,
  ) async {
    final app = await _mount(tester);
    await _activateAndConfirm(tester, app);
    app.session = const SessionIdentity(
      accountId: e12AccountId,
      memberId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      tenantId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      sessionId: 'otra-sesion',
      registrationId: e12RegistrationId,
      installationClientId: e12ClientId,
    );
    await _typePin(tester, _pin, _pin);
    expect(find.text(ActivationPinTexts.expired), findsOneWidget);
    expect(app.storage.values, isEmpty);
  });

  testWidgets('T10: con un PIN del titular ya en el teléfono no se ofrece y '
      'la acreditación se anula', (tester) async {
    final app = await _mount(
      tester,
      preparePin: (storage) async {
        const binding = OwnerBindingContext(
          bindingId: 1,
          personId: 1,
          scope: memberA,
        );
        final verification = OwnerOnlineVerification(
          confirmAccount: (_, __) async => true,
          readSessionScope: () async => memberA,
        );
        await LocalOwnerCredential(
          storage: storage,
          onlineVerification: verification,
          iterations: 1000,
        ).enroll(
          pin: _pin,
          pinConfirmation: _pin,
          proof: await verification.verify(
            email: 'e',
            password: 'p',
            binding: binding,
          ),
          binding: binding,
        );
      },
    );
    final before = Map<String, String>.of(app.storage.values);
    await _activateAndConfirm(tester, app);
    expect(find.byKey(const Key('pin-activation-notice')), findsNothing);
    expect(find.byKey(const Key('local-session-status')), findsOneWidget);
    expect(app.activation.hasActivationEvidence, isFalse);
    expect(app.storage.values, before);
  });
}
