// F08-PREV-01 (MOB #172): tras una restauración fallida, la copia previa sólo
// se da por resuelta (`rolledBack`) si el estado recuperado es el de antes
// (3.12.4.6; diferencia registrada en 3.14.5). Si no coincide o no se puede
// comprobar, queda protegida como interrumpida, bloquea otra restauración y
// el error no afirma que los datos anteriores se conservan. Datos sintéticos.
// La reproducción del defecto, que sólo usa la API anterior, está en
// `f08_restore_safety_copies_test.dart`.
import 'dart:io';

import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/backup_service.dart';
import 'package:agroquimicos/data/restore_safety_copies.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory workspace;
  late Directory invoices;
  late DateTime now;
  DateTime clock() => now;

  setUp(() async {
    RestoreSafetyCopies.forgetProcessStateForTesting();
    workspace = await Directory.systemTemp.createTemp('agro_f08_prev01_');
    invoices = Directory(p.join(workspace.path, 'invoices'));
    await invoices.create();
    now = DateTime.utc(2026, 10, 31, 12);
  });
  tearDown(() async {
    try {
      await workspace.delete(recursive: true);
    } on FileSystemException {
      // En Windows el motor puede retener un archivo; es temporal.
    }
  });

  String databasePath() => p.join(workspace.path, 'agro.db');
  Directory previo() => Directory(p.join(workspace.path, 'previo'));

  RestoreSafetyCopies copies() =>
      RestoreSafetyCopies(() async => databasePath(), clock: clock);

  Future<AppDatabase> database() async {
    final db = AppDatabase(factory: databaseFactoryFfi, path: databasePath());
    addTearDown(db.close);
    await AgroRepository(db).addProduct(name: 'Producto actual');
    return db;
  }

  BackupService service(
    AppDatabase db,
    RestoreSafetyCopies registry, {
    Future<void> Function()? beforeRecoveryCheck,
  }) => BackupService(
    db,
    safetyCopies: registry,
    invoicesDir: () async => invoices,
    exportDirectory: () async =>
        Directory(p.join(workspace.path, 'exportados'))..createSync(),
    beforeRecoveryCheck: beforeRecoveryCheck,
  );

  Future<AppDatabase> sourceDatabase(String name) async {
    final source = AppDatabase(
      factory: databaseFactoryFfi,
      path: p.join(workspace.path, 'origen_$name.db'),
    );
    await AgroRepository(source).addProduct(name: 'Producto $name');
    return source;
  }

  /// Base suelta (formato histórico): no toca las fotografías.
  Future<String> legacyBackup(String name) async {
    final source = await sourceDatabase(name);
    await source.close();
    final copy = p.join(workspace.path, '$name.db');
    await File(p.join(workspace.path, 'origen_$name.db')).copy(copy);
    return copy;
  }

  /// Contenedor `.agrobackup`: la restauración sí sustituye las fotografías.
  Future<String> containerBackup(String name) async {
    final source = await sourceDatabase(name);
    final photos = Directory(p.join(workspace.path, 'facturas_$name'));
    await photos.create();
    final exported = await BackupService(
      source,
      invoicesDir: () async => photos,
      exportDirectory: () async =>
          Directory(p.join(workspace.path, 'exportados'))..createSync(),
    ).export();
    await source.close();
    return exported.path;
  }

  Future<void> failAfterReplace() async =>
      throw const BackupException('simulado');

  Future<String> sha(String path) => BackupService.sha256OfFile(File(path));

  TypeMatcher<RestoreRecoveryUnverifiedException> unverified(
    RecoveryCheckFailure reason,
  ) => isA<RestoreRecoveryUnverifiedException>()
      .having((e) => e.reason, 'reason', reason)
      .having((e) => '${e.cause}', 'cause', 'simulado')
      .having((e) => e.message, 'message', contains('no se pudo confirmar'))
      .having((e) => e.message, 'message', isNot(contains('se conservan.')));

  group('recuperación correcta', () {
    test(
      'la base vuelve a ser idéntica byte a byte a la asegurada, la copia '
      'queda rolledBack, no bloquea y se informa el fallo original',
      () async {
        final db = await database();
        final registry = copies();
        await expectLater(
          service(db, registry).restore(
            await legacyBackup('falla'),
            afterReplace: failAfterReplace,
          ),
          throwsA(
            isA<BackupException>()
                .having((e) => e.message, 'message', 'simulado')
                .having(
                  (e) => e,
                  'tipo',
                  isNot(isA<RestoreRecoveryUnverifiedException>()),
                ),
          ),
        );
        final entry = (await registry.entries()).single;
        expect(entry.state, SafetyCopyState.rolledBack);
        expect(
          await sha(databasePath()),
          await sha(p.join(previo().path, entry.databaseName)),
        );
        expect(File('${databasePath()}-wal').existsSync(), isFalse);
        expect(
          (await AgroRepository(db).products()).map((r) => r['name']),
          contains('Producto actual'),
        );
        await registry.ensureCanStartRestore();
      },
    );

    test('con fotografías: vuelven las mismas, la copia queda rolledBack y '
        'su copia de fotografías se retira', () async {
      final db = await database();
      final registry = copies();
      final own = File(p.join(invoices.path, 'propia.jpg'));
      await own.writeAsBytes(List<int>.generate(512, (i) => i % 251));
      final ownBefore = await own.readAsBytes();
      await expectLater(
        service(db, registry).restore(
          await containerBackup('fotos'),
          afterReplace: failAfterReplace,
        ),
        throwsA(
          isA<BackupException>().having(
            (e) => e.message,
            'message',
            'simulado',
          ),
        ),
      );
      final entry = (await registry.entries()).single;
      expect(entry.state, SafetyCopyState.rolledBack);
      expect(await own.readAsBytes(), ownBefore);
      expect(invoices.listSync().map((e) => p.basename(e.path)), [
        'propia.jpg',
      ]);
      expect(
        Directory(p.join(previo().path, entry.invoicesName)).existsSync(),
        isFalse,
      );
    });
  });

  group('sin base anterior', () {
    // Base aún no creada: no hay nada que conservar.
    AppDatabase emptyDatabase() {
      final db = AppDatabase(factory: databaseFactoryFfi, path: databasePath());
      addTearDown(db.close);
      return db;
    }

    test('el rollback retira la base restaurada: se descarta la entrada y se '
        'informa el fallo original', () async {
      final db = emptyDatabase();
      final registry = copies();
      await expectLater(
        service(
          db,
          registry,
        ).restore(await legacyBackup('nueva'), afterReplace: failAfterReplace),
        throwsA(
          isA<BackupException>().having(
            (e) => e.message,
            'message',
            'simulado',
          ),
        ),
      );
      expect(File(databasePath()).existsSync(), isFalse);
      expect(await registry.entries(), isEmpty);
      await registry.ensureCanStartRestore();
    });

    test('queda una base donde no la había: no se resuelve y el mensaje no '
        'nombra una copia que no existe', () async {
      final db = emptyDatabase();
      final registry = copies();
      await expectLater(
        service(
          db,
          registry,
          beforeRecoveryCheck: () =>
              File(databasePath()).writeAsBytes([1, 2, 3]),
        ).restore(
          await legacyBackup('sobrante'),
          afterReplace: failAfterReplace,
        ),
        throwsA(
          unverified(RecoveryCheckFailure.mismatch).having(
            (e) => e.message,
            'message',
            isNot(contains('Se conserva la copia')),
          ),
        ),
      );
      expect(
        (await registry.entries()).single.state,
        SafetyCopyState.interrupted,
      );
    });
  });

  group('recuperación incorrecta', () {
    test('la base recuperada no tiene el SHA-256 de la asegurada', () async {
      final db = await database();
      final registry = copies();
      await expectLater(
        service(
          db,
          registry,
          beforeRecoveryCheck: () =>
              File(databasePath()).writeAsBytes([0], mode: FileMode.append),
        ).restore(await legacyBackup('hash'), afterReplace: failAfterReplace),
        throwsA(unverified(RecoveryCheckFailure.mismatch)),
      );
      expect(
        (await registry.entries()).single.state,
        SafetyCopyState.interrupted,
      );
    });

    test('queda un -shm junto a la base recuperada', () async {
      final db = await database();
      final registry = copies();
      await expectLater(
        service(
          db,
          registry,
          beforeRecoveryCheck: () =>
              File('${databasePath()}-shm').writeAsBytes([1]),
        ).restore(await legacyBackup('shm'), afterReplace: failAfterReplace),
        throwsA(unverified(RecoveryCheckFailure.mismatch)),
      );
      expect(
        (await registry.entries()).single.state,
        SafetyCopyState.interrupted,
      );
    });

    test('queda un diario -wal junto a la base recuperada', () async {
      final db = await database();
      final registry = copies();
      await expectLater(
        service(
          db,
          registry,
          beforeRecoveryCheck: () =>
              File('${databasePath()}-wal').writeAsBytes([1, 2, 3]),
        ).restore(await legacyBackup('wal'), afterReplace: failAfterReplace),
        throwsA(unverified(RecoveryCheckFailure.mismatch)),
      );
      expect(
        (await registry.entries()).single.state,
        SafetyCopyState.interrupted,
      );
    });

    test(
      'las fotografías no son las de antes: también se conserva su copia',
      () async {
        final db = await database();
        final registry = copies();
        final own = File(p.join(invoices.path, 'propia.jpg'));
        await own.writeAsBytes([1, 2, 3, 4]);
        await expectLater(
          service(
            db,
            registry,
            beforeRecoveryCheck: () => own.writeAsBytes([9, 9, 9, 9]),
          ).restore(
            await containerBackup('fotos'),
            afterReplace: failAfterReplace,
          ),
          throwsA(unverified(RecoveryCheckFailure.mismatch)),
        );
        final entry = (await registry.entries()).single;
        expect(entry.state, SafetyCopyState.interrupted);
        final kept = File(
          p.join(previo().path, entry.invoicesName, 'propia.jpg'),
        );
        expect(await kept.readAsBytes(), [1, 2, 3, 4]);
      },
    );

    test('sobra una fotografía que no estaba antes', () async {
      final db = await database();
      final registry = copies();
      await expectLater(
        service(
          db,
          registry,
          beforeRecoveryCheck: () =>
              File(p.join(invoices.path, 'ajena.jpg')).writeAsBytes([7]),
        ).restore(
          await containerBackup('sobra'),
          afterReplace: failAfterReplace,
        ),
        throwsA(unverified(RecoveryCheckFailure.mismatch)),
      );
      expect(
        (await registry.entries()).single.state,
        SafetyCopyState.interrupted,
      );
    });
  });

  group('recuperación no concluyente', () {
    test(
      'la comprobación no puede completarse: no se resuelve y bloquea',
      () async {
        final db = await database();
        final registry = copies();
        await expectLater(
          service(
            db,
            registry,
            beforeRecoveryCheck: () async =>
                throw const FileSystemException('simulado: lectura'),
          ).restore(
            await legacyBackup('dudosa'),
            afterReplace: failAfterReplace,
          ),
          throwsA(unverified(RecoveryCheckFailure.inconclusive)),
        );
        expect(
          (await registry.entries()).single.state,
          SafetyCopyState.interrupted,
        );
        await expectLater(
          registry.ensureCanStartRestore(),
          throwsA(same(RestoreBlockedException.unresolved)),
        );
      },
    );
  });

  group('el registro no se puede escribir al marcarla', () {
    test('la entrada queda en preparación fuera de la restauración en curso y '
        'bloquea igualmente', () async {
      final db = await database();
      final registry = copies();
      // Un directorio donde el registro escribe su temporal: guardar falla.
      final obstacle = Directory(p.join(previo().path, 'registro.json.tmp'));
      await expectLater(
        service(
          db,
          registry,
          beforeRecoveryCheck: () async {
            await obstacle.create(recursive: true);
            throw const FileSystemException('simulado: lectura');
          },
        ).restore(
          await legacyBackup('sinregistro'),
          afterReplace: failAfterReplace,
        ),
        throwsA(unverified(RecoveryCheckFailure.inconclusive)),
      );
      expect(
        (await registry.entries()).single.state,
        SafetyCopyState.preparing,
      );
      await obstacle.delete();
      await expectLater(
        registry.ensureCanStartRestore(),
        throwsA(same(RestoreBlockedException.unresolved)),
      );
      expect(
        (await registry.entries()).single.state,
        SafetyCopyState.interrupted,
      );
    });
  });

  group('protección frente a la limpieza', () {
    test('la copia sin recuperación comprobada sobrevive al plazo y a la cota '
        'y bloquea; sólo «Mantener los actuales» la devuelve a las reglas '
        'normales', () async {
      final db = await database();
      final registry = copies();
      await expectLater(
        service(
          db,
          registry,
          beforeRecoveryCheck: () async =>
              throw const FileSystemException('simulado: lectura'),
        ).restore(
          await legacyBackup('protegida'),
          afterReplace: failAfterReplace,
        ),
        throwsA(isA<RestoreRecoveryUnverifiedException>()),
      );
      final protected = (await registry.entries()).single;
      final protectedFile = File(p.join(previo().path, protected.databaseName));
      expect(protectedFile.existsSync(), isTrue);

      // Tres copias finalizadas más recientes: superan la cota de 2.
      for (var day = 1; day <= 3; day++) {
        now = DateTime.utc(2026, 11, day, 12);
        final slot = await registry.begin();
        await File(slot.databasePath).writeAsString('copia $day');
        await registry.markFinalized(slot);
      }
      final cap = await registry.maintain();
      expect(cap.overCap, hasLength(1));
      expect(cap.overCap, isNot(contains(protected.id)));

      // Y el plazo de siete días, muy superado.
      now = DateTime.utc(2026, 12, 31, 12);
      final expired = await registry.maintain();
      expect(expired.expired, hasLength(2));
      expect(expired.expired, isNot(contains(protected.id)));
      expect((await registry.entries()).single.id, protected.id);
      expect(protectedFile.existsSync(), isTrue);
      await expectLater(
        registry.ensureCanStartRestore(),
        throwsA(same(RestoreBlockedException.unresolved)),
      );

      // Acción expresa del titular (regla existente, sin cambios).
      await registry.keepCurrentData(protected.id);
      expect(
        (await registry.entries()).single.state,
        SafetyCopyState.rolledBack,
      );
      await registry.ensureCanStartRestore();
      now = now.add(const Duration(days: 8));
      await registry.maintain();
      expect(await registry.entries(), isEmpty);
      expect(protectedFile.existsSync(), isFalse);
    });
  });
}
