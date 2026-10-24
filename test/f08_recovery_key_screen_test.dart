// F08-ADR-003 §3.4: la clave se muestra, se anota fuera del teléfono y se
// vuelve a escribir completa antes de activarse. Clave efímera de la prueba.
import 'package:agroquimicos/data/backup_encryption.dart'
    show BackupRecoveryKey;
import 'package:agroquimicos/presentation/screens/backup_recovery_key_screen.dart';
import 'package:agroquimicos/services/backup/backup_keyring.dart';
import 'package:agroquimicos/services/backup/remote_backup_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryVault implements BackupKeyVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
}

void main() {
  Future<BackupKeyring> pump(
    WidgetTester tester, {
    BackupKeyring? keyring,
    BackupRecoveryKey? rotationKey,
  }) async {
    keyring ??= BackupKeyring(_MemoryVault());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [backupKeyringProvider.overrideWithValue(keyring)],
        child: MaterialApp(
          home: BackupRecoveryKeyScreen(rotationKey: rotationKey),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return keyring;
  }

  testWidgets(
    'no se puede continuar sin marcar que se anotó; una clave distinta no se activa; la correcta sí',
    (tester) async {
      final keyring = await pump(tester);
      final key = await keyring.pendingKey();
      // Se muestran los 14 grupos.
      for (final group in key.displayText.split('-')) {
        expect(find.textContaining(group), findsWidgets);
      }
      final continuar = find.widgetWithText(FilledButton, 'Continuar');
      expect(tester.widget<FilledButton>(continuar).onPressed, isNull);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.ensureVisible(continuar);
      await tester.tap(continuar);
      await tester.pump();

      final field = find.byType(TextField);
      expect(tester.widget<TextField>(field).enableSuggestions, isFalse);
      expect(tester.widget<TextField>(field).autocorrect, isFalse);
      expect(
        tester.widget<TextField>(field).enableIMEPersonalizedLearning,
        isFalse,
      );

      final wrong = key.displayText.split('');
      wrong[10] = wrong[10] == 'A' ? 'B' : 'A';
      await tester.enterText(field, wrong.join());
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Confirmar la clave'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar la clave'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('error de escritura'), findsOneWidget);
      expect(await keyring.readiness(), KeyringReadiness.pendingConfirmation);

      await tester.enterText(field, key.displayText.toLowerCase());
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Confirmar la clave'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar la clave'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(await keyring.readiness(), KeyringReadiness.ready);
    },
  );

  testWidgets(
    'el cambio muestra la pendiente que devolvió la rotación autorizada, '
    'que pendingKey ya no entrega con una activa',
    (tester) async {
      final owner = Object();
      final keyring = BackupKeyring(
        _MemoryVault(),
        consumeAuthorization: (authorization, _, _) async {
          if (!identical(authorization, owner)) {
            throw const BackupKeyAuthorizationRequired();
          }
        },
      );
      final first = (await tester.runAsync(() async {
        final key = await keyring.pendingKey();
        await keyring.confirmPending(key.displayText);
        return key;
      }))!;
      final next = (await tester.runAsync(
        () => keyring.startRotation(authorization: owner),
      ))!;
      await pump(tester, keyring: keyring, rotationKey: next);

      expect(find.text('Cambiar la clave de recuperación'), findsOneWidget);
      for (final group in next.displayText.split('-')) {
        expect(find.textContaining(group), findsWidgets);
      }
      await tester.runAsync(
        () => expectLater(
          keyring.pendingKey(),
          throwsA(isA<BackupKeyAuthorizationRequired>()),
        ),
      );
      expect(
        (await tester.runAsync(keyring.activeKey))!.key.sameAs(first),
        isTrue,
      );
    },
  );
}
