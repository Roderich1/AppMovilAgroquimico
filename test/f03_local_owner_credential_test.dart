// Credencial local del titular (F03 §4): verificador PBKDF2 real (con pocas
// iteraciones), intentos persistentes, acreditación en línea de un solo uso,
// autorización de un solo uso consumida contra el vínculo vigente (R2 de C) y
// ningún borrado de otros espacios del almacén seguro (R3 de C).
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

class _Clock {
  DateTime now = DateTime.utc(2026, 10, 23, 12);
  DateTime call() => now;
}

LocalOwnerCredential _credential(_Storage storage, _Clock clock) =>
    LocalOwnerCredential(storage: storage, iterations: 1000, clock: clock.call);

Future<OnlineOwnerProof?> _proof(
  _Clock clock, {
  bool reauthenticated = true,
  OwnerScope? sessionScope = _owner,
}) => OwnerOnlineVerification(
  reauthenticate: (_, __) async => reauthenticated,
  readSessionScope: () async => sessionScope,
  clock: clock.call,
).verify(email: 'farmer@example.test', password: 'pw', binding: _binding);

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
    Future<OwnerAuthorization> issue(_Clock clock) async {
      final c = _credential(_Storage(), clock);
      await _enroll(c, clock);
      return c.verify(
        pin: '284917',
        purpose: AuthorizationPurpose.reverseApplication,
        subjectRef: 'application:4',
        binding: _binding,
      );
    }

    test('once, for its purpose, subject and current binding', () async {
      final clock = _Clock();
      final auth = await issue(clock);
      void consume({
        AuthorizationPurpose purpose = AuthorizationPurpose.reverseApplication,
        String subject = 'application:4',
        OwnerBindingContext? current = _binding,
      }) => consumeOwnerAuthorization(
        auth,
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
      final auth = await issue(clock);
      expect(
        () => consumeOwnerAuthorization(
          auth,
          purpose: AuthorizationPurpose.reverseApplication,
          subjectRef: 'application:4',
          current: _binding,
          now: clock.now.add(const Duration(seconds: 121)),
        ),
        throwsA(isA<OwnerAuthorizationRejected>()),
      );
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
