// F08-PREV-01 (MOB #172): reproducción del defecto con la API que ya existía
// en `6aaeeea`, para poder ejecutarla tal cual sobre esa base, donde falla:
// marcaba la copia previa `rolledBack` en cuanto el rollback terminaba sin
// error, aunque la base activa no fuera la de antes. El resto de casos, en
// `f08_prev_01_rollback_verification_test.dart`. Datos sintéticos.
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
  late DateTime now;

  setUp(() async {
    RestoreSafetyCopies.forgetProcessStateForTesting();
    workspace = await Directory.systemTemp.createTemp('agro_f08_prev01_rep_');
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

  Future<String> legacyBackup(String name) async {
    final source = AppDatabase(
      factory: databaseFactoryFfi,
      path: p.join(workspace.path, 'origen_$name.db'),
    );
    await AgroRepository(source).addProduct(name: 'Producto $name');
    await source.close();
    final copy = p.join(workspace.path, '$name.db');
    await File(p.join(workspace.path, 'origen_$name.db')).copy(copy);
    return copy;
  }

  test('la copia previa cambió después de asegurarla: el rollback deja otro '
      'estado y no se da por recuperado', () async {
    final db = AppDatabase(factory: databaseFactoryFfi, path: databasePath());
    addTearDown(db.close);
    await AgroRepository(db).addProduct(name: 'Producto actual');
    final registry = RestoreSafetyCopies(
      () async => databasePath(),
      clock: () => now,
    );
    final other = await legacyBackup('otro');
    late String copyName;
    await expectLater(
      BackupService(db, safetyCopies: registry).restore(
        await legacyBackup('falla'),
        afterReplace: () async {
          copyName = (await registry.entries()).single.databaseName;
          // El rollback copiará esto sin error, pero ya no es la base que se
          // aseguró antes de sustituir.
          await File(other).copy(p.join(previo().path, copyName));
          throw const BackupException('simulado');
        },
      ),
      throwsA(
        isA<BackupException>().having(
          (e) => e.message,
          'message',
          contains('No pudimos confirmar'),
        ),
      ),
    );
    expect(
      (await registry.entries()).single.state,
      SafetyCopyState.interrupted,
    );
    await expectLater(
      registry.ensureCanStartRestore(),
      throwsA(same(RestoreBlockedException.unresolved)),
    );
    now = now.add(const Duration(days: 30));
    await registry.maintain();
    expect(
      (await registry.entries()).single.state,
      SafetyCopyState.interrupted,
    );
    expect(File(p.join(previo().path, copyName)).existsSync(), isTrue);
  });
}
