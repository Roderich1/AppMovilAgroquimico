// E-12 (F03 §4 bis): la acreditación de activación y el primer PIN del
// titular sin contraseña. Comprueba el consumo (vigencia, sesión, instalación,
// vínculo, acceso, un solo uso), la comprobación 7 dentro de la cola de la
// credencial (H1) y la emisión desde el controlador real de la activación
// (H2, H3, H4, H6, H7), sobre una base SQLite en memoria.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/installation_identity_initializer.dart';
import 'package:agroquimicos/domain/installation_access.dart';
import 'package:agroquimicos/guarded_restore.dart';
import 'package:agroquimicos/installation_access.dart';
import 'package:agroquimicos/services/auth/activation_owner_evidence.dart';
import 'package:agroquimicos/services/auth/api_endpoint_config.dart';
import 'package:agroquimicos/services/auth/existing_session_providers.dart';
import 'package:agroquimicos/services/auth/existing_session_startup.dart';
import 'package:agroquimicos/services/auth/first_activation_providers.dart';
import 'package:agroquimicos/services/auth/local_owner_credential.dart';
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/e12_activation_harness.dart';
import 'support/f04_app_access.dart' show seedActivatedInstallation;
import 'support/f04_mode_fixtures.dart';

const _pin = '284917';
const _otherPin = '502813';

/// El mismo mensaje de ciclo de vida que envía Android (pantalla apagada,
/// cambio de app), por el canal público de la plataforma.
Future<void> _lifecycle(AppLifecycleState state) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        SystemChannels.lifecycle.name,
        SystemChannels.lifecycle.codec.encodeMessage(state.toString()),
        (_) {},
      );
}

/// Credencial y acreditación de activación con dependencias controladas.
class _Env {
  _Env() {
    evidence = ActivationOwnerEvidence(
      identity: e12Identity,
      issuedAt: clock.now,
      elapsed: clock.evidenceClock.startElapsed(),
    );
    bindingRef = ActivationBindingRef(
      bindingId: 1,
      personId: 7,
      boundAt: clock.now
          .add(const Duration(seconds: 1))
          .toUtc()
          .toIso8601String(),
      scope: memberA,
    );
    expect(evidence!.attachBinding(bindingRef), isTrue);
    active = bindingRef;
    verification = OwnerOnlineVerification(
      confirmAccount: (_, __) async => true,
      readSessionScope: () async => memberA,
      clock: () => clock.now,
      activation: ActivationEvidenceSource(
        take: () {
          takes++;
          final taken = evidence;
          evidence = null;
          return taken;
        },
        readSessionIdentity: () async => session,
        currentInstallationRef: () => currentRef,
        activatedInstallationRef: () async => activatedRef,
        activeBinding: () async => active,
        accessActivated: () => activated,
      ),
    );
    credential = LocalOwnerCredential(
      storage: storage,
      onlineVerification: verification,
      iterations: 1000,
      clock: () => clock.now,
    );
  }

  final clock = E12Clock();
  final storage = E12CredentialStorage();
  ActivationOwnerEvidence? evidence;
  late final ActivationBindingRef bindingRef;
  SessionIdentity? session = e12Identity;
  String? currentRef = e12InstallationRef;
  String? activatedRef = e12InstallationRef;
  ActivationBindingRef? active;
  bool activated = true;
  int takes = 0;
  late final OwnerOnlineVerification verification;
  late final LocalOwnerCredential credential;

  static const context = OwnerBindingContext(
    bindingId: 1,
    personId: 7,
    scope: memberA,
  );

  Future<OnlineOwnerProof?> proof([OwnerBindingContext binding = context]) =>
      verification.fromActivation(binding: binding);

  Future<void> enroll(OnlineOwnerProof? proof, {String pin = _pin}) =>
      credential.enroll(
        pin: pin,
        pinConfirmation: pin,
        proof: proof,
        binding: context,
      );

  /// Un PIN puesto por la vía (a), con la contraseña.
  Future<void> enrollWithPassword(String pin) async => credential.enroll(
    pin: pin,
    pinConfirmation: pin,
    proof: await verification.verify(
      email: 'e',
      password: 'p',
      binding: context,
    ),
    binding: context,
  );
}

SessionIdentity _identity({
  String accountId = e12AccountId,
  String memberId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  String tenantId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  String sessionId = e12SessionId,
  String registrationId = e12RegistrationId,
  String installationClientId = e12ClientId,
}) => SessionIdentity(
  accountId: accountId,
  memberId: memberId,
  tenantId: tenantId,
  sessionId: sessionId,
  registrationId: registrationId,
  installationClientId: installationClientId,
);

// --- Controlador real de la activación ---------------------------------

class _Activation {
  _Activation(this.container, this.backend, this.commit, this.clock, this.db);

  final ProviderContainer container;
  final E12Backend backend;
  final E12CommitPort commit;
  final E12Clock clock;
  final AppDatabase db;

  FirstActivationController get controller =>
      container.read(firstActivationProvider.notifier);

  E12SettableAccess get access =>
      container.read(installationAccessProvider.notifier) as E12SettableAccess;

  Future<void> activate() async {
    await controller.activate(
      email: 'agricultor@example.test',
      password: e12Password,
    );
  }

  /// Espera a que la emisión (sin await en la activación) termine.
  Future<bool> evidenceAfterIssuing() async {
    for (var i = 0; i < 50; i++) {
      if (controller.hasActivationEvidence) return true;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return controller.hasActivationEvidence;
  }
}

Future<_Activation> _activation({
  ExistingSessionStartupState startup =
      ExistingSessionStartupState.noLocalSession,
  InstallationAccessState access =
      InstallationAccessState.newRequiresActivation,
  OwnerScope? bound,
}) async {
  final db = AppDatabase(
    factory: databaseFactoryFfi,
    path: inMemoryDatabasePath,
  );
  addTearDown(db.close);
  await db.database;
  final backend = E12Backend();
  final commit = E12CommitPort();
  final clock = E12Clock();
  final client = MockClient(backend.respond);
  addTearDown(client.close);
  final container = ProviderContainer(
    overrides: [
      existingSessionStartupProvider.overrideWithValue(startup),
      databaseProvider.overrideWithValue(db),
      installationAccessProvider.overrideWith(
        () => E12SettableAccess(access, bound: bound),
      ),
      installationIdentityProvider.overrideWithValue(
        const InstallationIdentityInitialization(
          InstallationIdentityStatus.ready,
        ),
      ),
      installationClientIdStoreProvider.overrideWithValue(E12IdentityStore()),
      secureSessionCommitProvider.overrideWithValue(commit),
      apiEndpointConfigProvider.overrideWithValue(
        ApiEndpointConfig(Uri.parse('https://api.example.test')),
      ),
      authHttpTransportProvider.overrideWithValue(client),
      activationEvidenceClockProvider.overrideWithValue(clock.evidenceClock),
    ],
  );
  addTearDown(container.dispose);
  container.read(installationAccessProvider);
  return _Activation(container, backend, commit, clock, db);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('consumo de la acreditación (fromActivation + enroll)', () {
    test(
      'U1: crea el primer PIN sin contraseña ni red, y el PIN autoriza',
      () async {
        final env = _Env();
        final proof = await env.proof();
        expect(proof, isNotNull);
        await env.enroll(proof);
        expect(
          (await env.credential.status(_Env.context)).state,
          CredentialState.enrolled,
        );
        final auth = await env.credential.verify(
          pin: _pin,
          purpose: AuthorizationPurpose.reversePurchase,
          subjectRef: 'purchase:1',
          binding: _Env.context,
        );
        expect(env.credential.accepts(auth), isTrue);
        expect(env.storage.writes, [
          'verifier',
          'attempts',
          'attempts',
          'attempts',
        ]);
      },
    );

    test('U2: identidad diferente (ámbito, cuenta, sesión, vínculo) no da '
        'comprobante ni escribe', () async {
      final cases = <String, void Function(_Env)>{
        'otra cuenta': (e) => e.session = _identity(accountId: 'otra-cuenta'),
        'otro Member': (e) => e.session = _identity(memberId: memberB.memberId),
        'otro tenant': (e) => e.session = _identity(tenantId: 'otro-tenant'),
        'otra sesión': (e) => e.session = _identity(sessionId: 'otra-sesion'),
        'otro registro': (e) =>
            e.session = _identity(registrationId: 'otro-registro'),
        'sin sesión legible': (e) => e.session = null,
        'cambio de titular (otro vínculo activo)': (e) =>
            e.active = ActivationBindingRef(
              bindingId: 2,
              personId: 8,
              boundAt: e.bindingRef.boundAt,
              scope: memberA,
            ),
        'vínculo archivado': (e) => e.active = ActivationBindingRef(
          bindingId: 1,
          personId: 7,
          boundAt: e.bindingRef.boundAt,
          scope: memberA,
          active: false,
        ),
      };
      for (final entry in cases.entries) {
        final env = _Env();
        entry.value(env);
        expect(await env.proof(), isNull, reason: entry.key);
        expect(env.evidence, isNull, reason: '${entry.key}: se retiró');
        expect(env.storage.writes, isEmpty, reason: entry.key);
      }
      // El vínculo con el que se enrola es de otro Member.
      final env = _Env();
      expect(
        await env.proof(
          const OwnerBindingContext(bindingId: 1, personId: 7, scope: memberB),
        ),
        isNull,
      );
    });

    test('U3: instalación diferente no da comprobante', () async {
      final cases = <String, void Function(_Env)>{
        'identidad de instalación actual': (e) =>
            e.currentRef = installationElsewhere,
        'sin identidad de instalación': (e) => e.currentRef = null,
        'activated_installation de la base': (e) =>
            e.activatedRef = installationElsewhere,
        'installationClientId de la sesión': (e) => e.session = _identity(
          installationClientId: '22222222-2222-4222-8222-222222222222',
        ),
      };
      for (final entry in cases.entries) {
        final env = _Env();
        entry.value(env);
        expect(await env.proof(), isNull, reason: entry.key);
        expect(env.storage.writes, isEmpty, reason: entry.key);
      }
    });

    test('U4: vencida por el reloj de pared, por el cronómetro o con el reloj '
        'atrasado; el comprobante tampoco vale tras el vencimiento', () async {
      final wall = _Env()
        ..clock.advance(const Duration(minutes: 10, seconds: 1));
      expect(await wall.proof(), isNull, reason: 'reloj de pared');

      final monotonic = _Env();
      monotonic.clock.elapsed += const Duration(minutes: 10, seconds: 1);
      expect(await monotonic.proof(), isNull, reason: 'cronómetro');

      final backwards = _Env()
        ..clock.advance(const Duration(seconds: -5), monotonic: false);
      expect(await backwards.proof(), isNull, reason: 'reloj atrasado');

      final justInTime = _Env()
        ..clock.advance(const Duration(minutes: 9, seconds: 59));
      expect(await justInTime.proof(), isNotNull, reason: 'dentro de 10 min');

      // notAfter: emitido a los 9:58, usado a los 10:01 (< 5 min del
      // comprobante, pero después de la acreditación).
      final tardy = _Env()
        ..clock.advance(const Duration(minutes: 9, seconds: 58));
      final proof = await tardy.proof();
      expect(proof, isNotNull);
      tardy.clock.advance(const Duration(seconds: 3));
      await expectLater(
        tardy.enroll(proof),
        throwsA(isA<CredentialException>()),
      );
      expect(tardy.storage.writes, isEmpty);
    });

    test('U5: un solo uso de la acreditación y del comprobante', () async {
      final env = _Env();
      final proof = await env.proof();
      expect(await env.proof(), isNull, reason: 'segunda retirada');
      expect(env.takes, 2);
      await env.enroll(proof);
      final written = List<String>.of(env.storage.writes);
      await expectLater(
        env.enroll(proof, pin: _otherPin),
        throwsA(isA<CredentialException>()),
      );
      expect(env.storage.writes, written, reason: 'no se reescribe');
    });

    test('U10: tras restaurar, un vínculo con el mismo id y ámbito pero otro '
        'boundAt no vale', () async {
      final env = _Env();
      env.active = ActivationBindingRef(
        bindingId: 1,
        personId: 7,
        boundAt: '2026-01-01T00:00:00.000Z',
        scope: memberA,
      );
      expect(await env.proof(), isNull);
      expect(env.storage.writes, isEmpty);
    });

    test(
      'acceso que no es activated, o dependencias ausentes (H8): null',
      () async {
        final notActivated = _Env()..activated = false;
        expect(await notActivated.proof(), isNull);

        final noSource = OwnerOnlineVerification(
          confirmAccount: (_, __) async => true,
          readSessionScope: () async => memberA,
        );
        expect(await noSource.fromActivation(binding: _Env.context), isNull);

        final env = _Env();
        final partial = OwnerOnlineVerification(
          confirmAccount: (_, __) async => true,
          readSessionScope: () async => memberA,
          activation: ActivationEvidenceSource(
            take: () => env.evidence,
            readSessionIdentity: () async => env.session,
            currentInstallationRef: () => env.currentRef,
            activeBinding: () async => env.active,
            accessActivated: () => true,
            // Falta activatedInstallationRef.
          ),
        );
        expect(await partial.fromActivation(binding: _Env.context), isNull);
      },
    );

    test(
      'U12 (H1): con un PIN propio del titular (enrolled, locked o '
      'requiresOnlineReset) la activación no lo cambia, ni lo escribe',
      () async {
        Future<void> check(
          String label,
          Future<void> Function(_Env) prepare,
        ) async {
          final env = _Env();
          await prepare(env);
          final before = Map<String, String>.of(env.storage.values);
          final proof = await env.proof();
          expect(proof, isNotNull, reason: label);
          await expectLater(
            env.enroll(proof, pin: _otherPin),
            throwsA(
              isA<CredentialException>().having(
                (e) => e.message,
                'message',
                activationExistingPinMessage,
              ),
            ),
            reason: label,
          );
          expect(env.storage.values, before, reason: '$label: sin escribir');
        }

        await check('enrolled', (e) => e.enrollWithPassword(_pin));
        await check('locked', (e) async {
          await e.enrollWithPassword(_pin);
          e.storage.values['attempts'] =
              '{"failures":5,"lockedUntil":"2099-01-01T00:00:00.000Z"}';
          expect(
            (await e.credential.status(_Env.context)).state,
            CredentialState.locked,
          );
        });
        await check('requiresOnlineReset', (e) async {
          await e.enrollWithPassword(_pin);
          e.storage.values['attempts'] = '{"failures":10,"lockedUntil":null}';
          expect(
            (await e.credential.status(_Env.context)).state,
            CredentialState.requiresOnlineReset,
          );
        });
      },
    );

    test('U12 (D-3, H8): un verificador de otro Member o ilegible se '
        'sobrescribe; la vía con contraseña sigue restableciendo', () async {
      // Verificador de otro Member: scopeMismatch para este vínculo.
      final other = _Env();
      const otherBinding = OwnerBindingContext(
        bindingId: 9,
        personId: 9,
        scope: memberB,
      );
      final otherVerification = OwnerOnlineVerification(
        confirmAccount: (_, __) async => true,
        readSessionScope: () async => memberB,
      );
      final otherCredential = LocalOwnerCredential(
        storage: other.storage,
        onlineVerification: otherVerification,
        iterations: 1000,
      );
      await otherCredential.enroll(
        pin: _otherPin,
        pinConfirmation: _otherPin,
        proof: await otherVerification.verify(
          email: 'e',
          password: 'p',
          binding: otherBinding,
        ),
        binding: otherBinding,
      );
      expect(
        (await other.credential.status(_Env.context)).state,
        CredentialState.scopeMismatch,
      );
      await other.enroll(await other.proof());
      expect(
        (await other.credential.status(_Env.context)).state,
        CredentialState.enrolled,
      );

      // Verificador ilegible: cuenta como notEnrolled y se sobrescribe.
      final unreadable = _Env();
      unreadable.storage.values['verifier'] = '{dañado';
      await unreadable.enroll(await unreadable.proof());
      expect(
        (await unreadable.credential.status(_Env.context)).state,
        CredentialState.enrolled,
      );

      // La vía (a) sigue cambiando un PIN existente.
      final reset = _Env();
      await reset.enrollWithPassword(_pin);
      await reset.enrollWithPassword(_otherPin);
      await reset.credential.verify(
        pin: _otherPin,
        purpose: AuthorizationPurpose.reversePurchase,
        subjectRef: 'purchase:1',
        binding: _Env.context,
      );
    });

    test('T17: otro camino enrola entre la oferta y la escritura: la cola lo '
        've y rechaza', () async {
      final env = _Env();
      final proof = await env.proof();
      expect(
        (await env.credential.status(_Env.context)).state,
        CredentialState.notEnrolled,
        reason: 'la oferta vio un titular sin PIN',
      );
      // Las dos escrituras entran en la misma cola; la de la contraseña va
      // primero.
      final passwordProof = await env.verification.verify(
        email: 'e',
        password: 'p',
        binding: _Env.context,
      );
      final password = env.credential.enroll(
        pin: _otherPin,
        pinConfirmation: _otherPin,
        proof: passwordProof,
        binding: _Env.context,
      );
      final activation = env.enroll(proof);
      await password;
      await expectLater(activation, throwsA(isA<CredentialException>()));
      await env.credential.verify(
        pin: _otherPin,
        purpose: AuthorizationPurpose.reversePurchase,
        subjectRef: 'purchase:1',
        binding: _Env.context,
      );
    });

    test(
      'W7: restablecer después (vía con contraseña) invalida la autorización '
      'emitida con el PIN creado en la activación',
      () async {
        final env = _Env();
        await env.enroll(await env.proof());
        final auth = await env.credential.verify(
          pin: _pin,
          purpose: AuthorizationPurpose.reversePurchase,
          subjectRef: 'purchase:1',
          binding: _Env.context,
        );
        expect(env.credential.accepts(auth), isTrue);
        await env.enrollWithPassword(_otherPin);
        expect(
          () => consumeOwnerAuthorization(
            auth,
            installation: env.credential,
            purpose: AuthorizationPurpose.reversePurchase,
            subjectRef: 'purchase:1',
            current: _Env.context,
            now: env.clock.now,
          ),
          throwsA(isA<OwnerAuthorizationRejected>()),
        );
      },
    );

    test('Separación de secretos y nada legible en textos', () async {
      final env = _Env();
      expect(env.evidence.toString(), 'ActivationOwnerEvidence(redacted)');
      expect(e12Identity.toString(), 'SessionIdentity(redacted)');
      expect(env.bindingRef.toString(), 'ActivationBindingRef(redacted)');
      await env.enroll(await env.proof());
      expect(env.storage.values.keys.toSet(), {'verifier', 'attempts'});
      final stored = env.storage.values.values.join();
      for (final secret in [_pin, e12Password, e12Access, e12Refresh]) {
        expect(stored.contains(secret), isFalse);
      }
    });

    test('la acreditación se ata una sola vez, a un vínculo activo del mismo '
        'ámbito creado después de emitirla', () {
      final clock = E12Clock();
      ActivationOwnerEvidence fresh() => ActivationOwnerEvidence(
        identity: e12Identity,
        issuedAt: clock.now,
        elapsed: clock.evidenceClock.startElapsed(),
      );
      final later = clock.now.add(const Duration(seconds: 1)).toIso8601String();
      final before = clock.now
          .subtract(const Duration(seconds: 1))
          .toIso8601String();
      ActivationBindingRef ref(String boundAt, {OwnerScope scope = memberA}) =>
          ActivationBindingRef(
            bindingId: 1,
            personId: 7,
            boundAt: boundAt,
            scope: scope,
          );
      expect(fresh().attachBinding(ref(before)), isFalse);
      expect(fresh().attachBinding(ref(later, scope: memberB)), isFalse);
      final once = fresh();
      expect(once.attachBinding(ref(later)), isTrue);
      expect(once.attachBinding(ref(later)), isFalse);
    });
  });

  group('emisión desde la activación real (FirstActivationController)', () {
    test('U1: una activación nueva sin sesión ni titular emite la acreditación '
        'de la sesión escrita', () async {
      final a = await _activation();
      await a.activate();
      expect(await a.evidenceAfterIssuing(), isTrue);
      final evidence = a.controller.takeActivationEvidence()!;
      expect(evidence.identity.sameAs(e12Identity), isTrue);
      expect(evidence.installationRef, e12InstallationRef);
      expect(a.controller.hasActivationEvidence, isFalse, reason: 'retirada');
      expect(a.controller.takeActivationEvidence(), isNull, reason: 'un uso');
    });

    test(
      'U9: con la red caída la activación falla y no hay acreditación',
      () async {
        final a = await _activation();
        a.backend.failLoginNetwork = true;
        await a.activate();
        expect(await a.evidenceAfterIssuing(), isFalse);
      },
    );

    test('U11/T9/T18: otros orígenes no emiten', () async {
      final withSession = await _activation(
        startup: ExistingSessionStartupState.localSessionAvailable,
      );
      await withSession.activate();
      expect(withSession.commit.calls, 1, reason: 'la activación terminó');
      expect(
        await withSession.evidenceAfterIssuing(),
        isFalse,
        reason: 'sesión',
      );

      final bound = await _activation(bound: memberA);
      await bound.activate();
      expect(await bound.evidenceAfterIssuing(), isFalse, reason: 'titular');

      final seeded = await _activation();
      await seedActivatedInstallation(seeded.db);
      await seeded.activate();
      expect(
        await seeded.evidenceAfterIssuing(),
        isFalse,
        reason: 'vínculo en SQLite (lectura directa)',
      );

      final unknown = await _activation();
      unknown.commit.outcomeUnknown = true;
      await unknown.activate();
      expect(
        await unknown.evidenceAfterIssuing(),
        isFalse,
        reason: 'localCommitUnknown',
      );
    });

    test('U14/T20 (H2): una base histórica no emite', () async {
      final a = await _activation(
        access: InstallationAccessState.legacyUnbound,
      );
      final db = await a.db.database;
      await db.update(
        'app_settings',
        {'value': AppDatabase.installOriginLegacy},
        where: 'key=?',
        whereArgs: [AppDatabase.installOriginKey],
      );
      await a.activate();
      expect(await a.evidenceAfterIssuing(), isFalse);
    });

    test('U6/H2: cancelar, salir al shell sin titular o un estado ajeno la '
        'anulan; la secuencia válida la conserva', () async {
      final cancel = await _activation();
      await cancel.activate();
      expect(await cancel.evidenceAfterIssuing(), isTrue);
      cancel.controller.discardActivationEvidence();
      expect(cancel.controller.hasActivationEvidence, isFalse);

      final valid = await _activation();
      await valid.activate();
      expect(await valid.evidenceAfterIssuing(), isTrue);
      valid.access.move(InstallationAccessState.activationPendingOwner);
      expect(valid.controller.hasActivationEvidence, isTrue);
      expect(
        valid.controller.attachOwnerBinding(
          ActivationBindingRef(
            bindingId: 1,
            personId: 1,
            boundAt: valid.clock.now
                .add(const Duration(seconds: 1))
                .toIso8601String(),
            scope: memberA,
          ),
        ),
        isTrue,
      );
      valid.access.move(InstallationAccessState.activated);
      expect(valid.controller.hasActivationEvidence, isTrue);

      final shell = await _activation();
      await shell.activate();
      expect(await shell.evidenceAfterIssuing(), isTrue);
      shell.access.move(InstallationAccessState.activationPendingOwner);
      shell.access.move(InstallationAccessState.activated);
      expect(
        shell.controller.hasActivationEvidence,
        isFalse,
        reason: 'activated sin vínculo atado',
      );

      final foreign = await _activation();
      await foreign.activate();
      expect(await foreign.evidenceAfterIssuing(), isTrue);
      foreign.access.move(InstallationAccessState.identityMismatch);
      expect(foreign.controller.hasActivationEvidence, isFalse);

      final wrongScope = await _activation();
      await wrongScope.activate();
      expect(await wrongScope.evidenceAfterIssuing(), isTrue);
      expect(
        wrongScope.controller.attachOwnerBinding(
          ActivationBindingRef(
            bindingId: 1,
            personId: 1,
            boundAt: wrongScope.clock.now
                .add(const Duration(seconds: 1))
                .toIso8601String(),
            scope: memberB,
          ),
        ),
        isFalse,
      );
      expect(wrongScope.controller.hasActivationEvidence, isFalse);
    });

    test(
      'T1: salir de la sesión (cambio de sesión en ejecución) la anula',
      () async {
        final a = await _activation();
        await a.activate();
        expect(await a.evidenceAfterIssuing(), isTrue);
        a.container.read(runtimeSessionTransitionProvider.notifier).signedOut();
        expect(a.controller.hasActivationEvidence, isFalse);
      },
    );

    test('U13/T16 (H3): hidden o paused la anulan; inactive no', () async {
      final hidden = await _activation();
      await hidden.activate();
      expect(await hidden.evidenceAfterIssuing(), isTrue);
      await _lifecycle(AppLifecycleState.inactive);
      expect(
        hidden.controller.hasActivationEvidence,
        isTrue,
        reason: 'inactive',
      );
      await _lifecycle(AppLifecycleState.hidden);
      expect(
        hidden.controller.hasActivationEvidence,
        isFalse,
        reason: 'hidden',
      );
      await _lifecycle(AppLifecycleState.inactive);
      await _lifecycle(AppLifecycleState.resumed);

      final paused = await _activation();
      await paused.activate();
      expect(await paused.evidenceAfterIssuing(), isTrue);
      await _lifecycle(AppLifecycleState.inactive);
      await _lifecycle(AppLifecycleState.hidden);
      await _lifecycle(AppLifecycleState.paused);
      expect(paused.controller.hasActivationEvidence, isFalse);
      await _lifecycle(AppLifecycleState.hidden);
      await _lifecycle(AppLifecycleState.inactive);
      await _lifecycle(AppLifecycleState.resumed);
    });

    test(
      'U8/T19 (H6): si el Notifier se recrea, la acreditación se pierde',
      () async {
        final a = await _activation();
        await a.activate();
        expect(await a.evidenceAfterIssuing(), isTrue);
        a.container.invalidate(firstActivationProvider);
        expect(
          a.container
              .read(firstActivationProvider.notifier)
              .hasActivationEvidence,
          isFalse,
        );
      },
    );

    test(
      'U10/T7 (H4): GuardedRestore la anula antes de sustituir la base',
      () async {
        final a = await _activation();
        await a.activate();
        expect(await a.evidenceAfterIssuing(), isTrue);
        await expectLater(
          a.container
              .read(guardedRestoreProvider)
              .restore('/no/existe.agrobackup'),
          throwsA(anything),
        );
        expect(a.controller.hasActivationEvidence, isFalse);
      },
    );
  });
}
