// Credencial local del titular (F03 §4): verificador PBKDF2 real (con pocas
// iteraciones), intentos persistentes, acreditación en línea de un solo uso,
// autorización de un solo uso consumida contra el vínculo vigente (R2 de C) y
// ningún borrado de otros espacios del almacén seguro (R3 de C).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agroquimicos/domain/installation_access.dart';
import 'package:agroquimicos/services/auth/local_owner_credential.dart';
import 'package:flutter_test/flutter_test.dart';

const _owner = OwnerScope(memberId: 'member-1', tenantId: 'tenant-1');
const _other = OwnerScope(memberId: 'member-2', tenantId: 'tenant-1');
const _binding = OwnerBindingContext(bindingId: 1, personId: 7, scope: _owner);

class _Storage implements CredentialStorage {
  final values = <String, String>{};
  final touched = <String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    touched.add(key);
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    touched.add(key);
    values.remove(key);
  }
}

/// Retiene la lectura del verificador hasta abrir [gate], con el valor que
/// había al empezar a leer (una lectura lenta del almacén).
class _GatedStorage extends _Storage {
  Completer<void>? gate;

  @override
  Future<String?> read(String key) async {
    final value = values[key];
    final g = gate;
    if (key == 'verifier' && g != null) await g.future;
    return value;
  }
}

/// La escritura del verificador persiste y después falla (p. ej. el nativo
/// guardó y la llamada devolvió un error).
class _FailingAfterWriteStorage extends _Storage {
  bool failVerifierWrite = false;

  @override
  Future<void> write(String key, String value) async {
    await super.write(key, value);
    if (key == 'verifier' && failVerifierWrite) {
      throw StateError('escritura informada como fallida');
    }
  }
}

class _Clock {
  DateTime now = DateTime.utc(2026, 10, 23, 12);
  DateTime call() => now;
}

/// La acreditación en línea configurada en las credenciales de estas pruebas:
/// una sola instancia; cada [_proof] fija su resultado.
class _Online {
  bool reauthenticated = true;
  OwnerScope? sessionScope = _owner;
  DateTime Function() clock = DateTime.now;
}

final _online = _Online();
final _verification = OwnerOnlineVerification(
  reauthenticate: (_, __) async => _online.reauthenticated,
  readSessionScope: () async => _online.sessionScope,
  clock: () => _online.clock(),
);

LocalOwnerCredential _credential(_Storage storage, _Clock clock) =>
    LocalOwnerCredential(
      storage: storage,
      onlineVerification: _verification,
      iterations: 1000,
      clock: clock.call,
    );

Future<OnlineOwnerProof?> _proof(
  _Clock clock, {
  bool reauthenticated = true,
  OwnerScope? sessionScope = _owner,
}) {
  _online
    ..reauthenticated = reauthenticated
    ..sessionScope = sessionScope
    ..clock = clock.call;
  return _verification.verify(
    email: 'farmer@example.test',
    password: 'pw',
    binding: _binding,
  );
}

Future<void> _enroll(
  LocalOwnerCredential c,
  _Clock clock, [
  String pin = '284917',
]) async => c.enroll(
  pin: pin,
  pinConfirmation: pin,
  proof: await _proof(clock),
  binding: _binding,
);

void main() {
  test(
    'production defaults: at least 210 000 iterations and its own namespace',
    () {
      expect(
        LocalOwnerCredential.defaultIterations,
        greaterThanOrEqualTo(210000),
      );
      expect(
        LocalOwnerCredential.androidNamespace,
        'agrocuentas_owner_credential_v1',
      );
    },
  );

  test('PIN rules', () {
    expect(pinProblem('284917'), isNull);
    for (final bad in [
      '12345',
      '1234567',
      'abcdef',
      '111111',
      '123456',
      '987654',
      '012345',
    ]) {
      expect(pinProblem(bad), isNotNull, reason: bad);
    }
  });

  group('online proof', () {
    test(
      'only a reauthentication of the bound titular yields a proof',
      () async {
        final clock = _Clock();
        expect(await _proof(clock, reauthenticated: false), isNull);
        expect(await _proof(clock, sessionScope: _other), isNull);
        expect(await _proof(clock, sessionScope: null), isNull);
        expect(await _proof(clock), isNotNull);
      },
    );

    test('enrolment needs a fresh, unused proof of the same titular', () async {
      final storage = _Storage();
      final clock = _Clock();
      final c = _credential(storage, clock);
      await expectLater(
        c.enroll(
          pin: '284917',
          pinConfirmation: '284917',
          proof: null,
          binding: _binding,
        ),
        throwsA(isA<CredentialException>()),
      );
      final proof = await _proof(clock);
      await c.enroll(
        pin: '284917',
        pinConfirmation: '284917',
        proof: proof,
        binding: _binding,
      );
      // Single use.
      await expectLater(
        c.enroll(
          pin: '384917',
          pinConfirmation: '384917',
          proof: proof,
          binding: _binding,
        ),
        throwsA(isA<CredentialException>()),
      );
      // Expired after 5 minutes.
      final late = await _proof(clock);
      clock.now = clock.now.add(const Duration(minutes: 6));
      await expectLater(
        c.enroll(
          pin: '384917',
          pinConfirmation: '384917',
          proof: late,
          binding: _binding,
        ),
        throwsA(isA<CredentialException>()),
      );
      expect(storage.values.keys.toSet(), {'verifier', 'attempts'});
    });

    test('mismatched confirmation and weak PIN are rejected before using the proof', () async {
      final clock = _Clock();
      final c = _credential(_Storage(), clock);
      final proof = await _proof(clock);
      await expectLater(
        c.enroll(
          pin: '284917',
          pinConfirmation: '284918',
          proof: proof,
          binding: _binding,
        ),
        throwsA(isA<CredentialException>()),
      );
      await expectLater(
        c.enroll(
          pin: '123456',
          pinConfirmation: '123456',
          proof: proof,
          binding: _binding,
        ),
        throwsA(isA<CredentialException>()),
      );
      // The proof is still usable for a valid PIN.
      await c.enroll(
        pin: '284917',
        pinConfirmation: '284917',
        proof: proof,
        binding: _binding,
      );
    });
  });

  group('verification', () {
    test(
      'works offline, never stores the PIN and yields a one-shot authorization',
      () async {
        final storage = _Storage();
        final clock = _Clock();
        final c = _credential(storage, clock);
        expect((await c.status(_binding)).state, CredentialState.notEnrolled);
        await _enroll(c, clock);
        expect((await c.status(_binding)).state, CredentialState.enrolled);
        for (final value in storage.values.values) {
          expect(value, isNot(contains('284917')));
        }
        final auth = await c.verify(
          pin: '284917',
          purpose: AuthorizationPurpose.reversePurchase,
          subjectRef: 'purchase:5',
          binding: _binding,
        );
        expect(auth.method, 'LOCAL_PIN');
        expect(auth.personId, 7);
        expect(auth.bindingId, 1);
        expect(auth.toString(), isNot(contains('284917')));
      },
    );

    test(
      'lockout escalates, survives a new instance and needs online reset at 10',
      () async {
        final storage = _Storage();
        final clock = _Clock();
        await _enroll(_credential(storage, clock), clock);
        Future<void> wrong() => expectLater(
          _credential(storage, clock).verify(
            pin: '000001',
            purpose: AuthorizationPurpose.reversePurchase,
            subjectRef: 'purchase:5',
            binding: _binding,
          ),
          throwsA(isA<CredentialException>()),
        );
        for (var i = 0; i < 5; i++) {
          await wrong();
        }
        final locked = await _credential(storage, clock).status(_binding);
        expect(locked.state, CredentialState.locked);
        expect(locked.lockedUntil, clock.now.add(const Duration(seconds: 30)));
        // While locked, even the right PIN is refused.
        await expectLater(
          _credential(storage, clock).verify(
            pin: '284917',
            purpose: AuthorizationPurpose.reversePurchase,
            subjectRef: 'purchase:5',
            binding: _binding,
          ),
          throwsA(isA<CredentialException>()),
        );
        for (var i = 5; i < 10; i++) {
          clock.now = clock.now.add(const Duration(minutes: 11));
          await wrong();
        }
        clock.now = clock.now.add(const Duration(hours: 1));
        expect(
          (await _credential(storage, clock).status(_binding)).state,
          CredentialState.requiresOnlineReset,
        );
        // Online reset (same path as enrolment) restores it.
        await _enroll(_credential(storage, clock), clock, '583920');
        expect(
          (await _credential(storage, clock).status(_binding)).state,
          CredentialState.enrolled,
        );
      },
    );

    test(
      'concurrent wrong PINs, even from two instances, are all counted',
      () async {
        final storage = _Storage();
        final clock = _Clock();
        final first = _credential(storage, clock);
        final second = _credential(storage, clock);
        await _enroll(first, clock);
        Future<void> wrong(LocalOwnerCredential c) => expectLater(
          c.verify(
            pin: '000001',
            purpose: AuthorizationPurpose.reversePurchase,
            subjectRef: 's',
            binding: _binding,
          ),
          throwsA(isA<CredentialException>()),
        );
        await Future.wait([
          wrong(first),
          wrong(second),
          wrong(first),
          wrong(second),
        ]);
        expect((await first.status(_binding)).state, CredentialState.enrolled);
        await wrong(second);
        expect((await first.status(_binding)).state, CredentialState.locked);
      },
    );

    test(
      'the Android storage is one object, so every instance shares the queue',
      () {
        expect(
          identical(AndroidCredentialStorage(), AndroidCredentialStorage()),
          isTrue,
        );
      },
    );

    test('an attempt interrupted during the KDF stays counted', () async {
      final storage = _Storage();
      final clock = _Clock();
      await _enroll(_credential(storage, clock), clock);
      final interrupted = LocalOwnerCredential(
        storage: storage,
        onlineVerification: _verification,
        iterations: 1000,
        clock: clock.call,
        kdf: (_, __, ___) => Future.error(StateError('proceso terminado')),
      );
      for (var i = 0; i < 5; i++) {
        await expectLater(
          interrupted.verify(
            pin: '284917',
            purpose: AuthorizationPurpose.reversePurchase,
            subjectRef: 's',
            binding: _binding,
          ),
          throwsA(isA<StateError>()),
        );
      }
      expect(
        (await interrupted.status(_binding)).state,
        CredentialState.locked,
      );
    });

    test('a success resets the failure counter', () async {
      final storage = _Storage();
      final clock = _Clock();
      final c = _credential(storage, clock);
      await _enroll(c, clock);
      for (var i = 0; i < 4; i++) {
        await expectLater(
          c.verify(
            pin: '000001',
            purpose: AuthorizationPurpose.reversePurchase,
            subjectRef: 's',
            binding: _binding,
          ),
          throwsA(isA<CredentialException>()),
        );
      }
      await c.verify(
        pin: '284917',
        purpose: AuthorizationPurpose.reversePurchase,
        subjectRef: 's',
        binding: _binding,
      );
      for (var i = 0; i < 4; i++) {
        await expectLater(
          c.verify(
            pin: '000001',
            purpose: AuthorizationPurpose.reversePurchase,
            subjectRef: 's',
            binding: _binding,
          ),
          throwsA(isA<CredentialException>()),
        );
      }
      expect((await c.status(_binding)).state, CredentialState.enrolled);
    });

    test(
      'a verifier of another titular (restored base) is not valid',
      () async {
        final storage = _Storage();
        final clock = _Clock();
        final c = _credential(storage, clock);
        await _enroll(c, clock);
        const restored = OwnerBindingContext(
          bindingId: 3,
          personId: 9,
          scope: _other,
        );
        expect((await c.status(restored)).state, CredentialState.scopeMismatch);
        await expectLater(
          c.verify(
            pin: '284917',
            purpose: AuthorizationPurpose.reversePurchase,
            subjectRef: 's',
            binding: restored,
          ),
          throwsA(isA<CredentialException>()),
        );
      },
    );

    test('a damaged attempt counter does not lower protection', () async {
      final storage = _Storage();
      final clock = _Clock();
      final c = _credential(storage, clock);
      await _enroll(c, clock);
      storage.values['attempts'] = 'not-json';
      expect(
        (await c.status(_binding)).state,
        CredentialState.requiresOnlineReset,
      );
    });
  });

  group('consumption (R2)', () {
    Future<OwnerAuthorization> verifyWith(
      LocalOwnerCredential c, [
      String pin = '284917',
    ]) => c.verify(
      pin: pin,
      purpose: AuthorizationPurpose.reverseApplication,
      subjectRef: 'application:4',
      binding: _binding,
    );

    Future<(OwnerAuthorization, LocalOwnerCredential)> issue(
      _Clock clock,
    ) async {
      final c = _credential(_Storage(), clock);
      await _enroll(c, clock);
      return (await verifyWith(c), c);
    }

    void consumeNow(
      OwnerAuthorization auth,
      LocalOwnerCredential? installation,
      _Clock clock,
    ) => consumeOwnerAuthorization(
      auth,
      installation: installation,
      purpose: AuthorizationPurpose.reverseApplication,
      subjectRef: 'application:4',
      current: _binding,
      now: clock.now,
    );

    test('once, for its purpose, subject and current binding', () async {
      final clock = _Clock();
      final (auth, installation) = await issue(clock);
      void consume({
        AuthorizationPurpose purpose = AuthorizationPurpose.reverseApplication,
        String subject = 'application:4',
        OwnerBindingContext? current = _binding,
      }) => consumeOwnerAuthorization(
        auth,
        installation: installation,
        purpose: purpose,
        subjectRef: subject,
        current: current,
        now: clock.now,
      );
      expect(
        () => consume(purpose: AuthorizationPurpose.reversePurchase),
        throwsA(isA<OwnerAuthorizationRejected>()),
      );
      expect(
        () => consume(subject: 'application:5'),
        throwsA(isA<OwnerAuthorizationRejected>()),
      );
      // Restored base meanwhile: other binding, other person or other scope.
      expect(
        () => consume(
          current: const OwnerBindingContext(
            bindingId: 2,
            personId: 7,
            scope: _owner,
          ),
        ),
        throwsA(isA<OwnerAuthorizationRejected>()),
      );
      expect(
        () => consume(current: null),
        throwsA(isA<OwnerAuthorizationRejected>()),
      );
      consume();
      expect(consume, throwsA(isA<OwnerAuthorizationRejected>()));
      expect(
        () => consumeOwnerAuthorization(
          null,
          installation: installation,
          purpose: AuthorizationPurpose.reverseApplication,
          subjectRef: 'application:4',
          current: _binding,
          now: clock.now,
        ),
        throwsA(isA<OwnerAuthorizationRejected>()),
      );
    });

    test('expires after 120 s', () async {
      final clock = _Clock();
      final (auth, installation) = await issue(clock);
      expect(
        () => consumeOwnerAuthorization(
          auth,
          installation: installation,
          purpose: AuthorizationPurpose.reverseApplication,
          subjectRef: 'application:4',
          current: _binding,
          now: clock.now.add(const Duration(seconds: 121)),
        ),
        throwsA(isA<OwnerAuthorizationRejected>()),
      );
    });

    test(
      'a PIN reset invalidates authorizations issued before it at once',
      () async {
        final clock = _Clock();
        final c = _credential(_Storage(), clock);
        await _enroll(c, clock);
        final before = await verifyWith(c);
        await _enroll(c, clock, '583920');
        expect(await c.currentEnrolmentId(), isNot(before.enrolmentId));
        expect(
          () => consumeNow(before, c, clock),
          throwsA(isA<OwnerAuthorizationRejected>()),
        );
        // The new PIN works; the old one no longer verifies.
        consumeNow(await verifyWith(c, '583920'), c, clock);
        await expectLater(verifyWith(c), throwsA(isA<CredentialException>()));
      },
    );

    test('a reset racing a verification: either order leaves no usable pre-reset authorization', () async {
      final clock = _Clock();
      final c = _credential(_Storage(), clock);
      await _enroll(c, clock);
      // verify() queued before enroll(): issued under the old PIN, then dead.
      final first = await _proof(clock);
      final results = await Future.wait<Object?>([
        verifyWith(c),
        c.enroll(
          pin: '583920',
          pinConfirmation: '583920',
          proof: first,
          binding: _binding,
        ),
      ]);
      final raced = results.first! as OwnerAuthorization;
      expect(
        () => consumeNow(raced, c, clock),
        throwsA(isA<OwnerAuthorizationRejected>()),
      );
      // enroll() queued before verify(): the replaced PIN does not verify.
      final second = await _proof(clock);
      final late = await Future.wait<Object?>([
        c.enroll(
          pin: '691024',
          pinConfirmation: '691024',
          proof: second,
          binding: _binding,
        ),
        verifyWith(
          c,
          '583920',
        ).then<Object?>((a) => a, onError: (Object e) => e),
      ]);
      expect(late.last, isA<CredentialException>());
    });

    test('the known enrolment: unknown until read, moved by a reset at once, per storage', () async {
      final clock = _Clock();
      final storage = _Storage();
      final c = _credential(storage, clock);
      expect(c.knownEnrolmentId, isNull);
      await _enroll(c, clock);
      final first = c.knownEnrolmentId;
      expect(first, isNotNull);
      expect(first, await c.currentEnrolmentId());
      // Another instance over the same storage sees it; another storage
      // (another process, or a fabricated credential) does not.
      expect(_credential(storage, clock).knownEnrolmentId, first);
      expect(_credential(_Storage(), clock).knownEnrolmentId, isNull);
      await _enroll(c, clock, '583920');
      expect(c.knownEnrolmentId, isNot(first));
      expect(c.knownEnrolmentId, await c.currentEnrolmentId());
    });

    test(
      'a proof from another verification is refused (direct call with stubs)',
      () async {
        final storage = _Storage();
        final clock = _Clock();
        final c = _credential(storage, clock);
        final forged = await OwnerOnlineVerification(
          reauthenticate: (_, __) async => true,
          readSessionScope: () async => _owner,
        ).verify(email: 'x', password: 'y', binding: _binding);
        expect(forged, isNotNull);
        await expectLater(
          c.enroll(
            pin: '284917',
            pinConfirmation: '284917',
            proof: forged,
            binding: _binding,
          ),
          throwsA(isA<CredentialException>()),
        );
        expect(storage.values, isEmpty);
      },
    );

    test('a credential with another enrolment is refused', () async {
      final clock = _Clock();
      final installation = _credential(_Storage(), clock);
      await _enroll(installation, clock);
      final fabricated = _credential(_Storage(), clock);
      await _enroll(fabricated, clock);
      final forged = await verifyWith(fabricated);
      expect(
        () => consumeNow(forged, installation, clock),
        throwsA(isA<OwnerAuthorizationRejected>()),
      );
      expect(
        () => consumeNow(forged, null, clock),
        throwsA(isA<OwnerAuthorizationRejected>()),
      );
    });

    test('R3 de B: copying the installation enrolment into another storage is refused', () async {
      final clock = _Clock();
      final installation = _credential(_Storage(), clock);
      await _enroll(installation, clock);
      // The enrolment is not a secret (it is in the audit and the backups).
      final copied = installation.knownEnrolmentId!;
      final otherStorage = _Storage();
      final fabricated = _credential(otherStorage, clock);
      await _enroll(fabricated, clock);
      final verifier =
          jsonDecode(otherStorage.values['verifier']!) as Map<String, Object?>;
      verifier['enrolmentId'] = copied;
      otherStorage.values['verifier'] = jsonEncode(verifier);
      final forged = await verifyWith(fabricated);
      expect(forged.enrolmentId, copied);
      expect(installation.accepts(forged), isFalse);
      expect(
        () => consumeNow(forged, installation, clock),
        throwsA(isA<OwnerAuthorizationRejected>()),
      );
    });

    test('R1 de B: a slow read that started before a reset does not bring the old PIN back', () async {
      final clock = _Clock();
      final storage = _GatedStorage();
      final c = _credential(storage, clock);
      await _enroll(c, clock);
      final before = await verifyWith(c);
      storage.gate = Completer<void>();
      final slowStatus = c.status(_binding);
      final slowEnrolment = c.currentEnrolmentId();
      final gate = storage.gate!;
      storage.gate = null;
      // The reset finishes while both reads are still held with the old PIN.
      await _enroll(c, clock, '583920');
      gate.complete();
      await slowStatus;
      expect(await slowEnrolment, before.enrolmentId);
      expect(c.knownEnrolmentId, isNot(before.enrolmentId));
      expect(
        () => consumeNow(before, c, clock),
        throwsA(isA<OwnerAuthorizationRejected>()),
      );
    });

    test('R2 de B: a verifier write reported as failed leaves nothing valid until the next verification', () async {
      final clock = _Clock();
      final storage = _FailingAfterWriteStorage();
      final c = _credential(storage, clock);
      await _enroll(c, clock);
      final before = await verifyWith(c);
      storage.failVerifierWrite = true;
      await expectLater(
        _enroll(c, clock, '583920'),
        throwsA(isA<StateError>()),
      );
      storage.failVerifierWrite = false;
      expect(c.knownEnrolmentId, isNull);
      expect(
        () => consumeNow(before, c, clock),
        throwsA(isA<OwnerAuthorizationRejected>()),
      );
      // The next verification reads what was persisted and publishes it.
      consumeNow(await verifyWith(c, '583920'), c, clock);
    });
  });

  test('R3: credential, session and recovery code never call deleteAll()', () {
    for (final path in [
      'lib/services/auth/local_owner_credential.dart',
      'lib/services/auth/secure_session_store.dart',
      'lib/services/auth/access_recovery.dart',
    ]) {
      final code = File(path).readAsStringSync();
      expect(code.contains('.deleteAll('), isFalse, reason: path);
    }
  });

  test(
    'a real PBKDF2 runs in an isolate and is deterministic for a salt',
    () async {
      final a = await isolatePbkdf2('284917', List.filled(16, 1), 1000);
      final b = await isolatePbkdf2('284917', List.filled(16, 1), 1000);
      final c = await isolatePbkdf2('284918', List.filled(16, 1), 1000);
      expect(a, hasLength(32));
      expect(a, b);
      expect(a, isNot(c));
    },
  );
}
