// F08-PREV-01 (MOB #172): tras una restauración fallida, la copia previa sólo
// se da por resuelta (`rolledBack`) si el estado recuperado es el de antes
// (3.12.4.6; diferencia registrada en 3.14.5). Si no coincide o no se puede
// comprobar, queda protegida como interrumpida, bloquea otra restauración y
// el error no afirma que los datos estén bien. Seguir con los datos actuales
// y confirmar la recuperación son decisiones separadas. Datos sintéticos.
// La reproducción del defecto, que sólo usa la API anterior, está en
// `f08_prev_01_reproduccion_test.dart`.
import 'dart:async';
import 'dart:io';

import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/backup_service.dart';
import 'package:agroquimicos/data/database_replacement.dart';
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

  // Cabecera de un diario de reversión de SQLite.
  const journalMagic = [0xd9, 0xd5, 0x05, 0xf9, 0x20, 0xa1, 0x63, 0xd7];

  Matcher original() => isA<BackupException>()
      .having((e) => e.message, 'message', 'simulado')
      .having(
        (e) => e,
        'tipo',
        isNot(isA<RestoreRecoveryUnverifiedException>()),
      );

  TypeMatcher<RestoreRecoveryUnverifiedException> unverified(
    RecoveryCheckFailure reason,
  ) => isA<RestoreRecoveryUnverifiedException>()
      .having((e) => e.reason, 'reason', reason)
      .having((e) => '${e.cause}', 'cause', 'simulado')
      .having((e) => e.message, 'message', contains('No pudimos confirmar'))
      .having((e) => e.message, 'message', isNot(contains('están bien')))
      .having((e) => e.message, 'message', isNot(contains('se conservan')));

  Future<SafetyCopyState> stateOf(RestoreSafetyCopies registry) async =>
      (await registry.entries()).single.state;

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
          throwsA(original()),
        );
        final entry = (await registry.entries()).single;
        expect(entry.state, SafetyCopyState.rolledBack);
        expect(
          await sha(databasePath()),
          await sha(p.join(previo().path, entry.databaseName)),
        );
        for (final suffix in const ['-wal', '-shm', '-journal']) {
          expect(File('${databasePath()}$suffix').existsSync(), isFalse);
        }
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
        throwsA(original()),
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

    test('instalación sin fotografías (carpeta vacía): la carpeta sigue vacía '
        'y la copia queda rolledBack', () async {
      final db = await database();
      final registry = copies();
      await expectLater(
        service(db, registry).restore(
          await containerBackup('vacia'),
          afterReplace: failAfterReplace,
        ),
        throwsA(original()),
      );
      expect(await stateOf(registry), SafetyCopyState.rolledBack);
      expect(invoices.existsSync(), isTrue);
      expect(invoices.listSync(), isEmpty);
    });

    for (final (name, bytes) in [
      ('vacío', <int>[]),
      ('con la cabecera a ceros', List.filled(512, 0)),
    ]) {
      test('-journal $name: SQLite no lo aplica, no se borra y la base abre '
          'íntegra con los datos de antes', () async {
        final db = await database();
        final registry = copies();
        final journal = File('${databasePath()}-journal');
        await expectLater(
          service(
            db,
            registry,
            beforeRecoveryCheck: () => journal.writeAsBytes(bytes),
          ).restore(
            await legacyBackup('residuo'),
            afterReplace: failAfterReplace,
          ),
          throwsA(original()),
        );
        expect(await stateOf(registry), SafetyCopyState.rolledBack);
        expect(journal.existsSync(), isTrue, reason: 'no se borra');
        final active = await db.database;
        expect(
          (await active.rawQuery('PRAGMA integrity_check')).single.values,
          ['ok'],
        );
        expect((await AgroRepository(db).products()).map((r) => r['name']), [
          'Producto actual',
        ]);
      });
    }

    for (final mode in const ['PERSIST', 'TRUNCATE']) {
      test(
        'modo $mode: los -journal reales que SQLite deja tras confirmar, '
        'de la base anterior y de la restaurada, no dan un falso positivo',
        () async {
          final db = await database();
          final active = await db.database;
          await active.rawQuery('PRAGMA journal_mode = $mode');
          await AgroRepository(db).addProduct(name: 'Producto $mode');
          final journal = File('${databasePath()}-journal');
          expect(journal.existsSync(), isTrue, reason: 'lo deja SQLite');
          final registry = copies();
          var journalAtCheck = false;
          await expectLater(
            service(
              db,
              registry,
              beforeRecoveryCheck: () async =>
                  journalAtCheck = journal.existsSync(),
            ).restore(
              await legacyBackup('modo'),
              // La base restaurada también escribe en ese modo antes del fallo.
              prepareRestored: (restored) async {
                await restored.rawQuery('PRAGMA journal_mode = $mode');
                await restored.execute('CREATE TABLE prueba_diario (x)');
                await restored.insert('prueba_diario', {'x': 1});
              },
              afterReplace: failAfterReplace,
            ),
            throwsA(original()),
          );
          expect(journalAtCheck, isTrue, reason: 'comprobado con el diario');
          expect(await stateOf(registry), SafetyCopyState.rolledBack);
          expect(
            (await AgroRepository(db).products()).map((r) => r['name']),
            unorderedEquals(['Producto actual', 'Producto $mode']),
          );
        },
      );
    }

    test('lecturas y escrituras de fuera durante la comprobación: la lectura '
        'espera sin reabrir la base, la escritura se rechaza y lo comparado '
        'no cambia', () async {
      final db = await database();
      final registry = copies();
      final repo = AgroRepository(db);
      late Future<List<Map<String, Object?>>> read;
      var readDone = false;
      Object? writeError;
      await expectLater(
        service(
          db,
          registry,
          beforeRecoveryCheck: () async {
            // Fuera de la zona de la sustitución, como la interfaz.
            read = Zone.root.run(repo.products);
            unawaited(read.then((_) => readDone = true));
            writeError = await Zone.root.run(
              () => repo
                  .addProduct(name: 'Intrusa')
                  .then<Object?>((_) => null, onError: (Object e) => e),
            );
            await Future<void>.delayed(const Duration(milliseconds: 50));
            if (readDone) throw StateError('la lectura no esperó');
          },
        ).restore(
          await legacyBackup('estable'),
          afterReplace: failAfterReplace,
        ),
        throwsA(original()),
      );
      expect(writeError, isA<DatabaseReplacementInProgressException>());
      expect(await stateOf(registry), SafetyCopyState.rolledBack);
      expect((await read).map((r) => r['name']), ['Producto actual']);
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
        throwsA(original()),
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
            isNot(contains('Conservamos la copia')),
          ),
        ),
      );
      expect(await stateOf(registry), SafetyCopyState.interrupted);
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
        throwsA(
          unverified(RecoveryCheckFailure.mismatch).having(
            (e) => e.message,
            'message',
            contains('Conservamos la copia de seguridad'),
          ),
        ),
      );
      expect(await stateOf(registry), SafetyCopyState.interrupted);
    });

    test('queda un -wal con contenido (pendiente) junto a la base', () async {
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
      expect(await stateOf(registry), SafetyCopyState.interrupted);
    });

    test('queda un -journal que SQLite aplicaría al abrir la base: no se '
        'borra', () async {
      final db = await database();
      final registry = copies();
      final journal = File('${databasePath()}-journal');
      await expectLater(
        service(
          db,
          registry,
          beforeRecoveryCheck: () =>
              journal.writeAsBytes([...journalMagic, ...List.filled(504, 0)]),
        ).restore(
          await legacyBackup('journal'),
          afterReplace: failAfterReplace,
        ),
        throwsA(unverified(RecoveryCheckFailure.mismatch)),
      );
      expect(await stateOf(registry), SafetyCopyState.interrupted);
      expect(journal.existsSync(), isTrue);
    });

    test('las fotografías no son las de antes: también se conserva su '
        'copia', () async {
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
    });

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
      expect(await stateOf(registry), SafetyCopyState.interrupted);
    });

    test('la carpeta de fotografías desapareció tras el rollback', () async {
      final db = await database();
      final registry = copies();
      await File(p.join(invoices.path, 'propia.jpg')).writeAsBytes([1, 2]);
      await expectLater(
        service(
          db,
          registry,
          beforeRecoveryCheck: () => invoices.delete(recursive: true),
        ).restore(
          await containerBackup('sincarpeta'),
          afterReplace: failAfterReplace,
        ),
        throwsA(unverified(RecoveryCheckFailure.mismatch)),
      );
      final entry = (await registry.entries()).single;
      expect(entry.state, SafetyCopyState.interrupted);
      expect(
        File(p.join(previo().path, entry.invoicesName, 'propia.jpg'))
            .existsSync(),
        isTrue,
      );
    });

    // Sólo con la carpeta inyectada: en la app `resolveInvoicesDirectory` la
    // crea siempre, y una instalación sin fotografías llega como carpeta
    // vacía (caso «instalación sin fotografías», arriba).
    test('no había carpeta de fotografías y el rollback deja una: ausente no '
        'es vacía', () async {
      final db = await database();
      final registry = copies();
      await invoices.delete();
      await expectLater(
        service(db, registry).restore(
          await containerBackup('ausente'),
          afterReplace: failAfterReplace,
        ),
        throwsA(unverified(RecoveryCheckFailure.mismatch)),
      );
      expect(await stateOf(registry), SafetyCopyState.interrupted);
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
        expect(await stateOf(registry), SafetyCopyState.interrupted);
        await expectLater(
          registry.ensureCanStartRestore(),
          throwsA(same(RestoreBlockedException.unresolved)),
        );
      },
    );

    test('queda un -wal vacío (residuo que el rollback no retiró)', () async {
      final db = await database();
      final registry = copies();
      await expectLater(
        service(
          db,
          registry,
          beforeRecoveryCheck: () =>
              File('${databasePath()}-wal').writeAsBytes(const []),
        ).restore(
          await legacyBackup('walvacio'),
          afterReplace: failAfterReplace,
        ),
        throwsA(unverified(RecoveryCheckFailure.inconclusive)),
      );
      expect(await stateOf(registry), SafetyCopyState.interrupted);
    });

    test('queda un -shm (residuo que el rollback no retiró)', () async {
      final db = await database();
      final registry = copies();
      await expectLater(
        service(
          db,
          registry,
          beforeRecoveryCheck: () =>
              File('${databasePath()}-shm').writeAsBytes([1]),
        ).restore(await legacyBackup('shm'), afterReplace: failAfterReplace),
        throwsA(unverified(RecoveryCheckFailure.inconclusive)),
      );
      expect(await stateOf(registry), SafetyCopyState.interrupted);
    });

    test('la copia previa de las fotografías desapareció', () async {
      final db = await database();
      final registry = copies();
      await File(p.join(invoices.path, 'propia.jpg')).writeAsBytes([1, 2]);
      await expectLater(
        service(db, registry).restore(
          await containerBackup('sincopia'),
          afterReplace: () async {
            final entry = (await registry.entries()).single;
            await Directory(p.join(previo().path, entry.invoicesName))
                .delete(recursive: true);
            throw const BackupException('simulado');
          },
        ),
        throwsA(unverified(RecoveryCheckFailure.inconclusive)),
      );
      expect(await stateOf(registry), SafetyCopyState.interrupted);
    });

    test('la copia previa de las fotografías está incompleta', () async {
      final db = await database();
      final registry = copies();
      await File(p.join(invoices.path, 'a.jpg')).writeAsBytes([1]);
      await File(p.join(invoices.path, 'b.jpg')).writeAsBytes([2]);
      await expectLater(
        service(db, registry).restore(
          await containerBackup('incompleta'),
          afterReplace: () async {
            final entry = (await registry.entries()).single;
            await File(p.join(previo().path, entry.invoicesName, 'b.jpg'))
                .delete();
            throw const BackupException('simulado');
          },
        ),
        throwsA(unverified(RecoveryCheckFailure.inconclusive)),
      );
      expect(await stateOf(registry), SafetyCopyState.interrupted);
    });
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
      expect(await stateOf(registry), SafetyCopyState.preparing);
      await obstacle.delete();
      await expectLater(
        registry.ensureCanStartRestore(),
        throwsA(same(RestoreBlockedException.unresolved)),
      );
      expect(await stateOf(registry), SafetyCopyState.interrupted);
    });
  });

  group('seguir con los datos actuales y confirmar la recuperación', () {
    Future<(RestoreSafetyCopies, SafetyCopyEntry, File)> unresolved() async {
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
      final entry = (await registry.entries()).single;
      return (registry, entry, File(p.join(previo().path, entry.databaseName)));
    }

    test('seguir con los actuales deja de bloquear pero no desprotege: la '
        'copia sobrevive a la cota y al plazo', () async {
      final (registry, entry, file) = await unresolved();
      await registry.continueWithCurrentData(entry.id);
      final kept = (await registry.entries()).single;
      expect(kept.state, SafetyCopyState.retained);
      expect(kept.isProtected, isTrue);
      expect(kept.resolvedAt, isNull);
      await registry.ensureCanStartRestore();

      // Tres copias finalizadas más recientes: superan la cota de 2.
      for (var day = 1; day <= 3; day++) {
        now = DateTime.utc(2026, 11, day, 12);
        final slot = await registry.begin();
        await File(slot.databasePath).writeAsString('copia $day');
        await registry.markFinalized(slot);
      }
      final cap = await registry.maintain();
      expect(cap.overCap, hasLength(1));
      expect(cap.overCap, isNot(contains(entry.id)));
      // Y el plazo de siete días, muy superado.
      now = DateTime.utc(2027, 3, 1, 12);
      final expired = await registry.maintain();
      expect(expired.expired, hasLength(2));
      expect(expired.expired, isNot(contains(entry.id)));
      expect(await stateOf(registry), SafetyCopyState.retained);
      expect(file.existsSync(), isTrue);
    });

    test(
      'sólo confirmar la recuperación la lleva a las reglas normales',
      () async {
        final (registry, entry, file) = await unresolved();
        await registry.continueWithCurrentData(entry.id);
        // Seguir otra vez no cambia nada.
        await registry.continueWithCurrentData(entry.id);
        expect(await stateOf(registry), SafetyCopyState.retained);
        await registry.confirmRecovery(entry.id);
        final confirmed = (await registry.entries()).single;
        expect(confirmed.state, SafetyCopyState.rolledBack);
        expect(confirmed.resolvedAt, now.toUtc());
        now = now.add(const Duration(days: 8));
        await registry.maintain();
        expect(await registry.entries(), isEmpty);
        expect(file.existsSync(), isFalse);
      },
    );

    test('confirmar directamente desde interrumpida', () async {
      final (registry, entry, _) = await unresolved();
      await registry.confirmRecovery(entry.id);
      expect(await stateOf(registry), SafetyCopyState.rolledBack);
      await registry.ensureCanStartRestore();
    });

    test('ninguna de las dos acciones cambia una copia ya resuelta', () async {
      final db = await database();
      final registry = copies();
      await expectLater(
        service(db, registry).restore(
          await legacyBackup('resuelta'),
          afterReplace: failAfterReplace,
        ),
        throwsA(original()),
      );
      final entry = (await registry.entries()).single;
      await registry.continueWithCurrentData(entry.id);
      await registry.confirmRecovery(entry.id);
      final after = (await registry.entries()).single;
      expect(after.state, SafetyCopyState.rolledBack);
      expect(after.resolvedAt, entry.resolvedAt);
    });

    test(
      'una copia retenida se vuelve a leer igual tras reabrir la app',
      () async {
        final (registry, entry, _) = await unresolved();
        await registry.continueWithCurrentData(entry.id);
        RestoreSafetyCopies.forgetProcessStateForTesting();
        final reopened = copies();
        expect(await stateOf(reopened), SafetyCopyState.retained);
        expect((await reopened.maintain()).interrupted, isEmpty);
        await reopened.ensureCanStartRestore();
      },
    );
  });

  group('hasFiles', () {
    test('distingue una entrada con copia de una sin ella', () async {
      final registry = copies();
      final slot = await registry.begin();
      expect(await registry.hasFiles(slot.entry), isFalse);
      await File('${slot.databasePath}.part').writeAsString('a medias');
      expect(await registry.hasFiles(slot.entry), isFalse, reason: '.part');
      await File(slot.databasePath).writeAsString('copia');
      expect(await registry.hasFiles(slot.entry), isTrue);
      await File(slot.databasePath).delete();
      await Directory(slot.invoicesPath).create(recursive: true);
      expect(await registry.hasFiles(slot.entry), isTrue, reason: 'fotos');
    });
  });

  group('protección frente a la limpieza', () {
    test('la copia sin recuperación comprobada sobrevive al plazo y a la cota '
        'y bloquea mientras nadie decide', () async {
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
      expect(await stateOf(registry), SafetyCopyState.interrupted);
      expect(protectedFile.existsSync(), isTrue);
      await expectLater(
        registry.ensureCanStartRestore(),
        throwsA(same(RestoreBlockedException.unresolved)),
      );
    });
  });
}
