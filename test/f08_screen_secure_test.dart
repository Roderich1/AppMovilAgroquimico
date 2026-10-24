// F08-ADR-003 §3.4: FLAG_SECURE mientras se muestra, se confirma o se escribe
// la clave de recuperación. Se simula el canal de Android; la marca real en la
// ventana se comprueba en el dispositivo (DEVICE, lo opera A).
import 'dart:async';

import 'package:agroquimicos/presentation/screens/backup_recovery_key_screen.dart';
import 'package:agroquimicos/services/backup/backup_keyring.dart';
import 'package:agroquimicos/services/backup/remote_backup_providers.dart';
import 'package:agroquimicos/services/backup/screen_secure.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryVault implements BackupKeyVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
}

/// Canal simulado: anota cada petición y responde como Android, o con el
/// retraso o el fallo que pida la prueba.
class _FakeWindow {
  final calls = <bool>[];
  bool secure = false;
  Completer<void>? hold;
  bool fail = false;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(ScreenSecure.channelName),
          (call) async {
            expect(call.method, 'setSecure');
            final wanted = (call.arguments as Map)['secure'] as bool;
            calls.add(wanted);
            if (hold != null) await hold!.future;
            if (fail) throw PlatformException(code: 'WINDOW');
            secure = wanted;
            return secure;
          },
        );
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(ScreenSecure.channelName),
          null,
        );
  }
}

void main() {
  late _FakeWindow window;

  setUp(() {
    window = _FakeWindow()..install();
  });
  tearDown(() => window.uninstall());

  group('cuenta de pantallas protegidas', () {
    test('anidadas: se protege una vez y sólo se desprotege al devolver la '
        'última', () async {
      final secure = ScreenSecure(enabled: true);
      final screen = await secure.acquire();
      final dialog = await secure.acquire();
      expect(window.calls, [true]);
      await dialog.release();
      expect(window.calls, [true]);
      expect(window.secure, isTrue);
      await dialog.release();
      expect(secure.holders, 1, reason: 'devolver dos veces no cuenta doble');
      await screen.release();
      expect(window.calls, [true, false]);
      expect(window.secure, isFalse);
    });

    test(
      'mientras Android no responde, la segunda espera a la primera',
      () async {
        final secure = ScreenSecure(enabled: true);
        window.hold = Completer<void>();
        var secondReady = false;
        final first = secure.acquire();
        final second = secure.acquire().then((lease) {
          secondReady = true;
          return lease;
        });
        await Future<void>.delayed(Duration.zero);
        expect(secondReady, isFalse);
        window.hold!.complete();
        await first;
        await second;
        expect(window.secure, isTrue);
        expect(window.calls, [true]);
      },
    );

    test(
      'si Android no la confirma, no hay permiso y no queda nadie contado',
      () async {
        final secure = ScreenSecure(enabled: true);
        window.fail = true;
        await expectLater(
          secure.acquire(),
          throwsA(isA<ScreenSecureUnavailable>()),
        );
        expect(secure.holders, 0);
        window.fail = false;
        final lease = await secure.acquire();
        expect(window.secure, isTrue);
        await lease.release();
        expect(window.secure, isFalse);
      },
    );

    test('si falla quitarla, la pantalla sigue protegida y la siguiente no '
        'vuelve a pedirla', () async {
      final secure = ScreenSecure(enabled: true);
      final lease = await secure.acquire();
      window.fail = true;
      await lease.release();
      expect(window.secure, isTrue);
      window.fail = false;
      await secure.acquire();
      expect(window.calls, [true, false]);
    });

    test('fuera de Android no llama al canal', () async {
      final secure = ScreenSecure(enabled: false);
      final lease = await secure.acquire();
      await lease.release();
      expect(window.calls, isEmpty);
    });
  });

  group('pantallas y diálogos de la clave', () {
    late BackupKeyring keyring;
    late ScreenSecure secure;

    Future<void> pumpHost(
      WidgetTester tester,
      Widget Function(BuildContext context, WidgetRef ref) home,
    ) async {
      keyring = BackupKeyring(
        _MemoryVault(),
        consumeAuthorization: (authorization, action, keyId) async {},
      );
      secure = ScreenSecure(enabled: true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backupKeyringProvider.overrideWithValue(keyring),
            screenSecureProvider.overrideWithValue(secure),
            backupKeyAuthorizerProvider.overrideWithValue(
              (context, ref, action, keyIdHex) async => Object(),
            ),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) => Scaffold(body: home(context, ref)),
            ),
          ),
        ),
      );
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('la clave no se pinta antes de que Android confirme la marca; '
        'sigue protegida en segundo plano y se libera al salir', (
      tester,
    ) async {
      await pumpHost(
        tester,
        (context, ref) => FilledButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<bool>(
              builder: (_) => const BackupRecoveryKeyScreen(),
            ),
          ),
          child: const Text('Abrir'),
        ),
      );
      window.hold = Completer<void>();
      await tester.tap(find.text('Abrir'));
      await settle(tester);
      final key = await keyring.pendingKey();
      final firstGroup = key.displayText.split('-').first;
      expect(window.calls, [true]);
      expect(find.textContaining(firstGroup), findsNothing);
      expect(find.byType(RecoveryKeyDisplay), findsNothing);

      window.hold!.complete();
      window.hold = null;
      await settle(tester);
      expect(window.secure, isTrue);
      expect(find.byType(RecoveryKeyDisplay), findsOneWidget);

      // Segundo plano y vuelta: la marca sigue y la clave también.
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
      }
      expect(window.calls, [true]);
      expect(window.secure, isTrue);
      expect(find.byType(RecoveryKeyDisplay), findsOneWidget);

      // Cancelar: se descarta y se libera al cerrar la pantalla.
      final discard = find.text('Descartar esta clave y no subir respaldos');
      await tester.scrollUntilVisible(
        discard,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(discard);
      await settle(tester);
      expect(find.byType(BackupRecoveryKeyScreen), findsNothing);
      expect(window.calls, [true, false]);
      expect(secure.holders, 0);
    });

    testWidgets('si Android no confirma la marca, la clave no aparece y se '
        'puede reintentar', (tester) async {
      window.fail = true;
      await pumpHost(tester, (context, ref) => const BackupRecoveryKeyScreen());
      await settle(tester);
      expect(find.byType(RecoveryKeyDisplay), findsNothing);
      expect(
        find.text(const ScreenSecureUnavailable().message),
        findsOneWidget,
      );
      window.fail = false;
      await tester.tap(find.text('Reintentar'));
      await settle(tester);
      expect(find.byType(RecoveryKeyDisplay), findsOneWidget);
      expect(window.secure, isTrue);
    });

    testWidgets('el diálogo que vuelve a mostrar la clave, sobre otra pantalla '
        'protegida, no la desprotege al cerrarse', (tester) async {
      await pumpHost(
        tester,
        (context, ref) => ScreenSecureScope(
          child: FilledButton(
            onPressed: () => revealActiveRecoveryKey(context, ref),
            child: const Text('Ver'),
          ),
        ),
      );
      final key = await keyring.pendingKey();
      await keyring.confirmPending(key.displayText);
      await settle(tester);
      expect(window.calls, [true]);

      await tester.tap(find.text('Ver'));
      await settle(tester);
      expect(find.byType(RecoveryKeyDisplay), findsOneWidget);
      expect(secure.holders, 2);
      expect(window.calls, [true]);

      await tester.tap(find.text('Cerrar'));
      await settle(tester);
      expect(find.byType(RecoveryKeyDisplay), findsNothing);
      expect(secure.holders, 1);
      expect(window.calls, [true]);
      expect(window.secure, isTrue);
    });

    testWidgets('pedir la clave para recuperar: protegida, usable, sin menú de '
        'copiar y pegar, y liberada al cancelar o al aceptar', (tester) async {
      String? typed = 'sin respuesta';
      await pumpHost(
        tester,
        (context, ref) => FilledButton(
          onPressed: () async => typed = await askRecoveryKey(context),
          child: const Text('Pedir'),
        ),
      );

      await tester.tap(find.text('Pedir'));
      await settle(tester);
      expect(window.secure, isTrue);
      await tester.tap(find.text('Cancelar'));
      await settle(tester);
      expect(typed, isNull);
      expect(window.calls, [true, false]);

      await tester.tap(find.text('Pedir'));
      await settle(tester);
      final field = find.byType(TextField);
      await tester.enterText(field, 'ABCD-EFGH');
      await tester.longPress(field);
      await settle(tester);
      expect(find.text('Paste'), findsNothing);
      expect(find.text('Copy'), findsNothing);
      expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
      await tester.tap(find.text('Descifrar'));
      await settle(tester);
      expect(typed, 'ABCD-EFGH');
      expect(window.calls, [true, false, true, false]);
      expect(secure.holders, 0);
    });
  });
}
