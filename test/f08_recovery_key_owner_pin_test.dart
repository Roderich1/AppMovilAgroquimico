// Composición F03 + F08 (F08-ADR-003 §3.3): volver a ver o cambiar la clave de
// recuperación pasa por el diálogo real del PIN del titular
// (`requestOwnerAuthorization`) y el llavero consume la autorización con
// `consumeOwnerAuthorization` de A: de un solo uso, para el propósito y la
// clave exactos, y sólo del almacén de esta instalación con su PIN vigente.
import 'dart:convert';

import 'package:agroquimicos/presentation/screens/backup_recovery_key_screen.dart';
import 'package:agroquimicos/services/auth/local_owner_credential.dart';
import 'package:agroquimicos/services/auth/local_owner_credential_providers.dart';
import 'package:agroquimicos/services/backup/backup_keyring.dart';
import 'package:agroquimicos/services/backup/remote_backup_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'support/f04_mode_fixtures.dart';
import 'support/f04_owner_pin.dart';

class _MemoryVault implements BackupKeyVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
}

const _binding = OwnerBindingContext(bindingId: 1, personId: 1, scope: memberA);

/// El llavero real con el consumidor real de la composición.
List<Override> _overrides(
  LocalOwnerCredential credential,
  _MemoryVault vault,
) => [
  localOwnerCredentialProvider.overrideWithValue(credential),
  ownerBindingContextReaderProvider.overrideWithValue(() async => _binding),
  backupKeyringProvider.overrideWith(
    (ref) => BackupKeyring(
      vault,
      consumeAuthorization: ref.watch(backupKeyAuthorizationConsumerProvider),
    ),
  ),
];

void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

  testWidgets('con el PIN del titular en el diálogo real se vuelve a ver la '
      'clave activa; con un PIN erróneo o al cancelar, no', (tester) async {
    late TestOwnerPin owner;
    final vault = _MemoryVault();
    await tester.runAsync(() async {
      owner = await TestOwnerPin.enrolled(_binding);
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(owner.credential, vault),
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: FilledButton(
                onPressed: () => revealActiveRecoveryKey(context, ref),
                child: const Text('Ver la clave'),
              ),
            ),
          ),
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.text('Ver la clave')),
    );
    final keyring = container.read(backupKeyringProvider);
    final key = (await tester.runAsync(() async {
      final pending = await keyring.pendingKey();
      await keyring.confirmPending(pending.displayText);
      return pending;
    }))!;

    // PIN erróneo: el diálogo lo dice y la clave no aparece; cancelar.
    await tester.tap(find.text('Ver la clave'));
    await settle(tester);
    expect(find.byKey(const Key('owner-pin-effects')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('owner-pin-input')), '000000');
    await tester.tap(find.byKey(const Key('owner-pin-submit')));
    await settle(tester);
    expect(find.byKey(const Key('owner-pin-error')), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await settle(tester);
    expect(find.byType(RecoveryKeyDisplay), findsNothing);

    // PIN correcto: se muestra la clave activa.
    await tester.tap(find.text('Ver la clave'));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('owner-pin-input')), '284917');
    await tester.tap(find.byKey(const Key('owner-pin-submit')));
    await settle(tester);
    expect(find.byType(RecoveryKeyDisplay), findsOneWidget);
    for (final group in key.displayText.split('-')) {
      expect(find.textContaining(group), findsWidgets);
    }
    await tester.tap(find.text('Cerrar'));
    await settle(tester);
    expect(find.byType(RecoveryKeyDisplay), findsNothing);
  });

  group('el llavero de la composición consume la autorización de A', () {
    late TestOwnerPin owner;
    late ProviderContainer container;
    late BackupKeyring keyring;
    late String keyId;

    setUp(() async {
      owner = await TestOwnerPin.enrolled(_binding);
      container = ProviderContainer(
        overrides: _overrides(owner.credential, _MemoryVault()),
      );
      keyring = container.read(backupKeyringProvider);
      final key = await keyring.pendingKey();
      await keyring.confirmPending(key.displayText);
      keyId = (await keyring.activeKey())!.keyId;
    });
    tearDown(() => container.dispose());

    Future<OwnerAuthorization> authorize(
      LocalOwnerCredential credential,
      AuthorizationPurpose purpose, {
      String? subject,
      String pin = '284917',
    }) => credential.verify(
      pin: pin,
      purpose: purpose,
      subjectRef: subject ?? keyId,
      binding: _binding,
    );

    test('vale una sola vez', () async {
      final auth = await authorize(
        owner.credential,
        AuthorizationPurpose.showBackupRecoveryKey,
      );
      expect(await keyring.revealActive(authorization: auth), isNotNull);
      await expectLater(
        keyring.revealActive(authorization: auth),
        throwsA(isA<BackupKeyAuthorizationRequired>()),
      );
    });

    test('la de ver no sirve para cambiar, ni la de otra clave', () async {
      final show = await authorize(
        owner.credential,
        AuthorizationPurpose.showBackupRecoveryKey,
      );
      await expectLater(
        keyring.startRotation(authorization: show),
        throwsA(isA<BackupKeyAuthorizationRequired>()),
      );
      final other = await authorize(
        owner.credential,
        AuthorizationPurpose.showBackupRecoveryKey,
        subject: '00' * 16,
      );
      await expectLater(
        keyring.revealActive(authorization: other),
        throwsA(isA<BackupKeyAuthorizationRequired>()),
      );
      expect(await keyring.readiness(), KeyringReadiness.ready);
    });

    test(
      'la emitida por otro almacén de credencial, aun para el mismo titular, '
      'no vale',
      () async {
        final foreign = await TestOwnerPin.enrolled(_binding);
        final auth = await authorize(
          foreign.credential,
          AuthorizationPurpose.showBackupRecoveryKey,
        );
        await expectLater(
          keyring.revealActive(authorization: auth),
          throwsA(isA<BackupKeyAuthorizationRequired>()),
        );
      },
    );

    test('copiar el enrolamiento de la instalación en otro almacén no da una '
        'autorización que valga (R3 de B)', () async {
      // El enrolamiento no es secreto: está en la auditoría y en los respaldos.
      final copied = owner.credential.knownEnrolmentId!;
      final otherStorage = MemoryCredentialStorage();
      final fabricated = LocalOwnerCredential(
        storage: otherStorage,
        onlineVerification: owner.verification,
        iterations: 1000,
      );
      await fabricated.enroll(
        pin: '284917',
        pinConfirmation: '284917',
        proof: await owner.verification.verify(
          email: 'e',
          password: 'p',
          binding: _binding,
        ),
        binding: _binding,
      );
      final verifier =
          jsonDecode(otherStorage.values['verifier']!) as Map<String, Object?>;
      verifier['enrolmentId'] = copied;
      otherStorage.values['verifier'] = jsonEncode(verifier);
      final forged = await authorize(
        fabricated,
        AuthorizationPurpose.showBackupRecoveryKey,
      );
      expect(forged.enrolmentId, copied);
      await expectLater(
        keyring.revealActive(authorization: forged),
        throwsA(isA<BackupKeyAuthorizationRequired>()),
      );
      // La de la instalación, con el mismo enrolamiento, sí vale.
      final genuine = await authorize(
        owner.credential,
        AuthorizationPurpose.showBackupRecoveryKey,
      );
      expect(await keyring.revealActive(authorization: genuine), isNotNull);
    });

    test(
      'tras restablecer el PIN, la autorización anterior ya no vale',
      () async {
        final auth = await authorize(
          owner.credential,
          AuthorizationPurpose.rotateBackupRecoveryKey,
        );
        await owner.reset('195738');
        await expectLater(
          keyring.startRotation(authorization: auth),
          throwsA(isA<BackupKeyAuthorizationRequired>()),
        );
        expect(await keyring.readiness(), KeyringReadiness.ready);
        final fresh = await authorize(
          owner.credential,
          AuthorizationPurpose.rotateBackupRecoveryKey,
          pin: '195738',
        );
        final next = await keyring.startRotation(authorization: fresh);
        expect(next.sameAs((await keyring.activeKey())!.key), isFalse);
      },
    );
  });
}
