// F08-PREV-01 (MOB #172): diálogos de «Copias previas a restauraciones» en
// «Respaldo en la nube». Seguir con los datos actuales y confirmar la
// recuperación son decisiones separadas; cancelar no confirma nada; el aviso
// de una recuperación sin confirmar se presenta aunque la pantalla se
// desmonte. Registro real sobre archivos temporales (por eso las esperas van
// con `runAsync`) y servicio remoto simulado. Datos sintéticos.
import 'dart:async';
import 'dart:io';

import 'package:agroquimicos/app.dart' show backupServiceProvider;
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/backup_service.dart';
import 'package:agroquimicos/data/restore_safety_copies.dart';
import 'package:agroquimicos/domain/installation_access.dart';
import 'package:agroquimicos/domain/restore_ownership.dart';
import 'package:agroquimicos/guarded_restore.dart';
import 'package:agroquimicos/presentation/screens/remote_backup_screen.dart';
import 'package:agroquimicos/services/backup/backup_keyring.dart';
import 'package:agroquimicos/services/backup/remote_backup_api.dart';
import 'package:agroquimicos/services/backup/remote_backup_providers.dart';
import 'package:agroquimicos/services/backup/remote_backup_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _MemoryVault implements BackupKeyVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
}

/// Registro real que anota qué acciones pide la interfaz.
class _SpyCopies extends RestoreSafetyCopies {
  _SpyCopies(super.databasePath, {super.clock});

  final calls = <String>[];

  @override
  Future<void> continueWithCurrentData(String id) {
    calls.add('seguir');
    return super.continueWithCurrentData(id);
  }

  @override
  Future<void> confirmRecovery(String id) {
    calls.add('confirmar');
    return super.confirmRecovery(id);
  }
}

/// Servicio remoto con una sola copia; la restauración queda pendiente hasta
/// que la prueba la resuelva.
class _FakeRemote implements RemoteBackupService {
  _FakeRemote(this.workspace);

  final Directory workspace;
  Completer<GuardedRestoreOutcome>? restoring;

  static final entry = RemoteBackupEntry(
    id: '0b6f7c2e-1d3a-4c5b-9e8f-7a6b5c4d3e2f',
    sha256: 'a' * 64,
    sizeBytes: 2048,
    formatVersion: RemoteBackupService.uploadFormatVersion,
    schemaVersion: AppDatabase.schemaVersion,
    createdAt: DateTime.utc(2026, 10, 30, 12),
  );

  @override
  Future<void> cleanupLeftovers() async {}

  @override
  Future<List<RemoteBackupEntry>> list() async => [entry];

  @override
  Future<Map<String, RemoteCopyKey>> keysFor(
    Iterable<RemoteBackupEntry> entries,
  ) async => const {};

  @override
  Future<PreparedRemoteRestore> prepareRestore(RemoteBackupEntry entry) async =>
      PreparedRemoteRestore(
        entry: entry,
        file: File(p.join(workspace.path, 'preparada.agrobackup')),
        validation: const BackupValidation.valid(
          version: 1,
          format: BackupFormat.container,
        ),
        ownership: const RestoreOwnershipVerdict.accepted(
          InstallationAccessState.activated,
        ),
      );

  @override
  Future<GuardedRestoreOutcome> restorePrepared(
    PreparedRemoteRestore prepared,
  ) => (restoring = Completer<GuardedRestoreOutcome>()).future;

  @override
  Future<void> discard(PreparedRemoteRestore prepared) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  sqfliteFfiInit();

  late Directory workspace;
  late DateTime now;
  late _SpyCopies registry;

  String databasePath() => p.join(workspace.path, 'agro.db');
  Directory previo() => Directory(p.join(workspace.path, 'previo'));

  /// Opera con una instancia nueva del registro, con su propio estado de
  /// proceso, y lo olvida al terminar. La cola del registro de la pantalla
  /// avanza con `pump`: compartirla con lo que la prueba espera dentro de
  /// `runAsync` lo bloquearía. Se usa siempre dentro de `runAsync`.
  Future<T> outsideScreen<T>(
    Future<T> Function(RestoreSafetyCopies copies) body,
  ) async {
    RestoreSafetyCopies.forgetProcessStateForTesting();
    try {
      return await body(
        RestoreSafetyCopies(() async => databasePath(), clock: () => now),
      );
    } finally {
      RestoreSafetyCopies.forgetProcessStateForTesting();
    }
  }

  /// Copia de una restauración sin resolver, tal como la deja un rollback sin
  /// comprobar o una restauración cortada: entrada `interrupted` y su base.
  Future<SafetyCopyEntry> unresolvedCopy() async {
    await outsideScreen((copies) async {
      final slot = await copies.begin();
      await File(slot.databasePath).writeAsString('datos de entonces');
    });
    // Otro proceso la encuentra en preparación: pasa a interrumpida.
    return outsideScreen((copies) async {
      await copies.maintain();
      return (await copies.entries()).single;
    });
  }

  Future<SafetyCopyEntry> current() =>
      outsideScreen((copies) async => (await copies.entries()).single);

  setUp(() async {
    RestoreSafetyCopies.forgetProcessStateForTesting();
    workspace = await Directory.systemTemp.createTemp('agro_f08_prev01_ui_');
    now = DateTime.utc(2026, 10, 31, 12);
    registry = _SpyCopies(() async => databasePath(), clock: () => now);
  });
  tearDown(() async {
    try {
      await workspace.delete(recursive: true);
    } on FileSystemException {
      // En Windows el motor puede retener un archivo; es temporal.
    }
  });

  /// Deja que terminen las operaciones de archivo y pinta.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Como [settle], hasta que aparezca [finder] (como mucho 100 vueltas): la
  /// pantalla vuelve a leer el registro tras cada acción.
  Future<void> settleUntil(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<(_FakeRemote, ValueNotifier<bool>)> pumpScreen(
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final remote = _FakeRemote(workspace);
    final shown = ValueNotifier(true);
    addTearDown(shown.dispose);
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      path: databasePath(),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backupServiceProvider.overrideWithValue(
            BackupService(database, safetyCopies: registry),
          ),
          remoteBackupServiceProvider.overrideWithValue(remote),
          backupKeyringProvider.overrideWithValue(
            BackupKeyring(_MemoryVault()),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: shown,
              builder: (_, show, _) => show
                  ? const RemoteBackupScreen()
                  : const Text('Pantalla de acceso'),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    return (remote, shown);
  }

  Finder inDialog(String text) =>
      find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

  Future<void> startRemoteRestore(WidgetTester tester) async {
    await tester.tap(find.text('Ver copias en el servidor'));
    await settle(tester);
    await tester.tap(find.byTooltip('Restaurar'));
    await settle(tester);
    await tester.tap(inDialog('Restaurar'));
    await settle(tester);
  }

  const unverified = RestoreRecoveryUnverifiedException(
    RecoveryCheckFailure.mismatch,
    BackupException('simulado'),
    StackTrace.empty,
    keptCopy: true,
  );

  group('aviso de una recuperación sin confirmar', () {
    test('el mensaje del bloqueo no dice que los datos estén bien ni que '
        'haya copia', () {
      final message = RestoreBlockedException.unresolved.message;
      expect(message, contains('no pudimos confirmar'));
      expect(message, isNot(contains('están bien')));
      expect(message, isNot(contains('Conservamos la copia')));
      expect(message, isNot(contains('Lo más probable')));
    });

    testWidgets('se presenta aunque la pantalla se desmonte al recalcular el '
        'acceso', (tester) async {
      final (remote, shown) = await pumpScreen(tester);
      await startRemoteRestore(tester);
      expect(remote.restoring, isNotNull);

      // Como el router al recalcular el acceso: la pantalla desaparece
      // antes de que llegue el error.
      shown.value = false;
      await tester.pump();
      expect(find.byType(RemoteBackupScreen), findsNothing);
      remote.restoring!.completeError(unverified);
      await settle(tester);

      expect(find.text('Pantalla de acceso'), findsOneWidget);
      expect(
        find.textContaining('No pudimos confirmar que sus datos anteriores'),
        findsOneWidget,
      );
      expect(find.textContaining('Conservamos la copia'), findsOneWidget);
    });

    testWidgets('con la pantalla abierta se presenta y la sección se recarga '
        'con la copia sobre la que decidir', (tester) async {
      final (remote, _) = await pumpScreen(tester);
      expect(find.text('Copias previas a restauraciones'), findsNothing);
      await startRemoteRestore(tester);

      // Lo que deja un rollback sin comprobar.
      await tester.runAsync(unresolvedCopy);
      remote.restoring!.completeError(unverified);
      await settle(tester);

      expect(
        find.textContaining('No pudimos confirmar que sus datos anteriores'),
        findsOneWidget,
      );
      expect(find.text('Copias previas a restauraciones'), findsOneWidget);
      expect(find.textContaining('RESTAURACIÓN SIN RESOLVER'), findsOneWidget);
      expect(find.text('Decidir'), findsOneWidget);
      expect(registry.calls, isEmpty);
    });
  });

  group('«Decidir» sobre una copia sin resolver', () {
    testWidgets('«Seguir con los actuales» la deja protegida, sin confirmar la '
        'recuperación', (tester) async {
      final entry = (await tester.runAsync(unresolvedCopy))!;
      await pumpScreen(tester);
      expect(find.textContaining('RESTAURACIÓN SIN RESOLVER'), findsOneWidget);

      await tester.tap(find.text('Decidir'));
      await settle(tester);
      expect(
        find.textContaining('Conservamos la copia de seguridad de los datos'),
        findsOneWidget,
      );
      await tester.tap(inDialog('Seguir con los actuales'));
      await settle(tester);

      expect(registry.calls, ['seguir']);
      final kept = (await tester.runAsync(current))!;
      expect(kept.state, SafetyCopyState.retained);
      expect(kept.isProtected, isTrue);
      expect(kept.resolvedAt, isNull);
      expect(
        File(p.join(previo().path, entry.databaseName)).existsSync(),
        isTrue,
      );
      await settleUntil(
        tester,
        find.text('Recuperación sin confirmar: copia protegida'),
      );
      expect(
        find.text('Recuperación sin confirmar: copia protegida'),
        findsOneWidget,
      );
      // Ya no bloquea y sigue ofreciendo confirmar, aparte.
      expect(find.text('Decidir'), findsNothing);
      expect(find.text('Mis datos están bien'), findsOneWidget);
      await tester.runAsync(
        () => outsideScreen((copies) => copies.ensureCanStartRestore()),
      );
    });

    testWidgets('cancelar o cerrar los diálogos no confirma nada', (
      tester,
    ) async {
      await tester.runAsync(unresolvedCopy);
      await pumpScreen(tester);

      // «Cancelar» en «Decidir».
      await tester.tap(find.text('Decidir'));
      await settle(tester);
      await tester.tap(inDialog('Cancelar'));
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing);

      // Tocar fuera del diálogo.
      await tester.tap(find.text('Decidir'));
      await settle(tester);
      await tester.tapAt(const Offset(5, 5));
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing);

      // Elegir «Mis datos están bien» y cancelar la confirmación.
      await tester.tap(find.text('Decidir'));
      await settle(tester);
      await tester.tap(inDialog('Mis datos están bien'));
      await settle(tester);
      expect(inDialog('¿Sus datos actuales están bien?'), findsOneWidget);
      await tester.tap(inDialog('Cancelar'));
      await settle(tester);

      // Y cerrar la confirmación tocando fuera.
      await tester.tap(find.text('Decidir'));
      await settle(tester);
      await tester.tap(inDialog('Mis datos están bien'));
      await settle(tester);
      await tester.tapAt(const Offset(5, 5));
      await settle(tester);

      expect(registry.calls, isEmpty);
      expect(
        (await tester.runAsync(current))!.state,
        SafetyCopyState.interrupted,
      );
      expect(find.text('Decidir'), findsOneWidget);
    });

    testWidgets('«Mis datos están bien» exige confirmarlo en otro diálogo que '
        'explica la limpieza normal', (tester) async {
      await tester.runAsync(unresolvedCopy);
      await pumpScreen(tester);

      await tester.tap(find.text('Decidir'));
      await settle(tester);
      await tester.tap(inDialog('Mis datos están bien'));
      await settle(tester);

      // Todavía nada: hace falta la confirmación explícita.
      expect(registry.calls, isEmpty);
      expect(inDialog('¿Sus datos actuales están bien?'), findsOneWidget);
      final detail = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('Hágalo sólo después de revisarlos'),
      );
      expect(detail, findsOneWidget);
      final text = tester.widget<Text>(detail).data!;
      expect(text, contains('dejará de estar protegida'));
      expect(text, contains('puede retirarse en la próxima limpieza'));
      expect(text, contains('como máximo dos, durante siete días'));
      expect(
        (await tester.runAsync(current))!.state,
        SafetyCopyState.interrupted,
      );

      await tester.tap(inDialog('Mis datos están bien'));
      await settle(tester);
      expect(registry.calls, ['confirmar']);
      final confirmed = (await tester.runAsync(current))!;
      expect(confirmed.state, SafetyCopyState.rolledBack);
      expect(confirmed.resolvedAt, now);
      await settleUntil(tester, find.text('restauración deshecha'));
      expect(find.text('restauración deshecha'), findsOneWidget);
    });

    testWidgets('sin copia en disco, el diálogo no dice que se conserve', (
      tester,
    ) async {
      final entry = (await tester.runAsync(unresolvedCopy))!;
      await tester.runAsync(
        () => File(p.join(previo().path, entry.databaseName)).delete(),
      );
      await pumpScreen(tester);

      await tester.tap(find.text('Decidir'));
      await settle(tester);
      expect(find.textContaining('no quedó ninguna copia'), findsOneWidget);
      expect(find.textContaining('Conservamos la copia'), findsNothing);
      await tester.tap(inDialog('Mis datos están bien'));
      await settle(tester);
      expect(find.textContaining('sin copia en este teléfono'), findsOneWidget);
    });
  });

  group('copia conservada con «Seguir con los actuales»', () {
    testWidgets('«Mis datos están bien» pide la misma confirmación y sólo '
        'entonces la pasa a las reglas normales', (tester) async {
      final entry = (await tester.runAsync(unresolvedCopy))!;
      await tester.runAsync(
        () =>
            outsideScreen((copies) => copies.continueWithCurrentData(entry.id)),
      );
      await pumpScreen(tester);

      await tester.tap(find.text('Mis datos están bien'));
      await settle(tester);
      expect(inDialog('¿Sus datos actuales están bien?'), findsOneWidget);
      await tester.tap(inDialog('Cancelar'));
      await settle(tester);
      expect(registry.calls, isEmpty);
      expect((await tester.runAsync(current))!.state, SafetyCopyState.retained);

      await tester.tap(find.text('Mis datos están bien'));
      await settle(tester);
      await tester.tap(inDialog('Mis datos están bien'));
      await settle(tester);
      expect(registry.calls, ['confirmar']);
      expect(
        (await tester.runAsync(current))!.state,
        SafetyCopyState.rolledBack,
      );
    });
  });
}
