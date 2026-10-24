// F08-ADR-003 §3.4: la clave se muestra, se anota fuera del teléfono y se
// vuelve a escribir completa antes de activarse. Clave efímera de la prueba.
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
  Future<BackupKeyring> pump(WidgetTester tester) async {
    final keyring = BackupKeyring(_MemoryVault());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [backupKeyringProvider.overrideWithValue(keyring)],
        child: const MaterialApp(home: BackupRecoveryKeyScreen()),
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
}
