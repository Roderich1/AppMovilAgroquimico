// UIBUG-001: exportar el respaldo falla SIEMPRE en Android.
//
// `backup_service.dart` ejecutaba el checkpoint con `Database.execute(...)`. En
// Android `sqflite` mapea `execute` a `SQLiteDatabase.execSQL`, que **rechaza
// las sentencias que devuelven filas**, y `PRAGMA wal_checkpoint(FULL)` devuelve
// una. La suite no lo detectaba porque corre sobre `sqflite_common_ffi`
// (escritorio), donde `execute` sí las admite: la cobertura verde era engañosa.
//
// Este archivo cierra ese hueco reproduciendo la restricción de la plataforma:
// una fábrica que envuelve la de escritorio y hace que `execute` se comporte
// como `execSQL`. No mockea el respaldo — el archivo se escribe y se vuelve a
// leer de verdad —, sólo modela la diferencia de plataforma que el escritorio no
// tiene.

import 'dart:io';
import 'dart:typed_data';

import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/backup_service.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
// Dependencia transitiva de `path_provider`: se usa solo para sustituir la
// implementacion de plataforma en la prueba, sin tocar `pubspec.yaml`.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Devuelve siempre el directorio de trabajo de la prueba.
///
/// En el host de pruebas `getDownloadsDirectory()` lanza
/// `Unsupported operation: Functionality only available on macOS`, asi que sin
/// esto `export()` seguiria sin poder ejercitarse. En Android la
/// implementacion real si devuelve una ruta valida.
class _WorkspacePathProvider extends PathProviderPlatform {
  _WorkspacePathProvider(this.directory);
  final String directory;

  @override
  Future<String?> getDownloadsPath() async => directory;

  @override
  Future<String?> getApplicationDocumentsPath() async => directory;

  @override
  Future<String?> getTemporaryPath() async => directory;

  @override
  Future<String?> getApplicationSupportPath() async => directory;
}

/// Sentencias que devuelven filas y que, por tanto, `execSQL` rechaza.
///
/// Se limita a los PRAGMA con valor de retorno y a `SELECT`, que es lo que la
/// aplicación podría llegar a pasar por `execute` por descuido.
bool _returnsRows(String sql) {
  final normalized = sql.trim().toLowerCase();
  if (normalized.startsWith('select')) return true;
  if (!normalized.startsWith('pragma')) return false;
  // `PRAGMA foreign_keys = ON` asigna y no devuelve filas; `PRAGMA
  // wal_checkpoint(...)` e `integrity_check` sí devuelven.
  if (normalized.contains('=')) return false;
  return normalized.contains('wal_checkpoint') ||
      normalized.contains('integrity_check') ||
      normalized.contains('journal_mode');
}

/// Reproduce el error textual que Android devuelve al pasar por `execSQL` una
/// sentencia que produce filas. `DatabaseException` de sqflite es abstracta, de
/// modo que aquí se declara un equivalente con el mismo mensaje.
class _ExecSqlRejected implements Exception {
  _ExecSqlRejected(this.sql);
  final String sql;
  @override
  String toString() =>
      'DatabaseException(unknown error (code 0 SQLITE_OK): Queries can be '
      'performed using SQLiteDatabase query or rawQuery methods only.) '
      "sql '$sql' args []";
}

class _AndroidLikeDatabase implements Database {
  _AndroidLikeDatabase(this._inner);
  final Database _inner;

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    if (_returnsRows(sql)) {
      // Mensaje textual del que la auditoría capturó en el Pixel 8.
      throw _ExecSqlRejected(sql);
    }
    return _inner.execute(sql, arguments);
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) => _inner.rawQuery(sql, arguments);

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) => _inner.transaction(action, exclusive: exclusive);

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) => _inner.insert(
    table,
    values,
    nullColumnHack: nullColumnHack,
    conflictAlgorithm: conflictAlgorithm,
  );

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) => _inner.query(
    table,
    distinct: distinct,
    columns: columns,
    where: where,
    whereArgs: whereArgs,
    groupBy: groupBy,
    having: having,
    orderBy: orderBy,
    limit: limit,
    offset: offset,
  );

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) => _inner.update(
    table,
    values,
    where: where,
    whereArgs: whereArgs,
    conflictAlgorithm: conflictAlgorithm,
  );

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) =>
      _inner.delete(table, where: where, whereArgs: whereArgs);

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) =>
      _inner.rawInsert(sql, arguments);

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) =>
      _inner.rawUpdate(sql, arguments);

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) =>
      _inner.rawDelete(sql, arguments);

  @override
  Batch batch() => _inner.batch();

  @override
  Future<void> close() => _inner.close();

  @override
  bool get isOpen => _inner.isOpen;

  @override
  String get path => _inner.path;

  // Cualquier otro miembro que la implementación empiece a usar debe fallar de
  // forma ruidosa, no en silencio.
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'El doble de Android no implementa ${invocation.memberName}. '
    'Añádalo si la implementación pasa a usarlo.',
  );
}

class _AndroidLikeFactory implements DatabaseFactory {
  _AndroidLikeFactory(this._inner);
  final DatabaseFactory _inner;

  @override
  Future<Database> openDatabase(
    String path, {
    OpenDatabaseOptions? options,
  }) async =>
      _AndroidLikeDatabase(await _inner.openDatabase(path, options: options));

  @override
  Future<void> deleteDatabase(String path) => _inner.deleteDatabase(path);

  @override
  Future<bool> databaseExists(String path) => _inner.databaseExists(path);

  @override
  Future<String> getDatabasesPath() => _inner.getDatabasesPath();

  @override
  Future<void> setDatabasesPath(String path) => _inner.setDatabasesPath(path);

  @override
  Future<void> writeDatabaseBytes(String path, Uint8List bytes) =>
      _inner.writeDatabaseBytes(path, bytes);

  @override
  Future<Uint8List> readDatabaseBytes(String path) =>
      _inner.readDatabaseBytes(path);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory workspace;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('agro_backup_android_');
    // `export()` escribe donde diga path_provider. Sin esto la exportacion no
    // se puede ejercitar en el host, que es justo como UIBUG-001 llego a
    // produccion: `backup_service_test.dart` nunca llamaba a `export()`.
    PathProviderPlatform.instance = _WorkspacePathProvider(workspace.path);
  });

  tearDown(() async {
    // En Windows el archivo puede seguir bloqueado por el motor SQLite; el
    // directorio es temporal y no afecta al resultado de la prueba.
    try {
      await workspace.delete(recursive: true);
    } on FileSystemException {
      // se limpiara con el temporal del sistema
    }
  });

  String pathFor(String name) => p.join(workspace.path, name);

  /// Base con datos reales, abierta con la semántica de Android.
  Future<(AppDatabase, AgroRepository)> androidLikeDatabase(String name) async {
    final database = AppDatabase(
      factory: _AndroidLikeFactory(databaseFactoryFfi),
      path: pathFor(name),
    );
    final repo = AgroRepository(database);
    await repo.addPerson(name: 'Familiar', role: PersonRole.family);
    await repo.addCampaign(name: 'Campaña', start: DateTime.utc(2026));
    return (database, repo);
  }

  test(
    'UIBUG-001: export() no usa una sentencia que Android rechace',
    () async {
      final (database, _) = await androidLikeDatabase('android.db');
      addTearDown(database.close);
      final service = BackupService(database);

      // Antes del fix esto lanzaba:
      //   DatabaseException(unknown error (code 0 SQLITE_OK): Queries can be
      //   performed using SQLiteDatabase query or rawQuery methods only.)
      //   sql 'PRAGMA wal_checkpoint(FULL)'
      final exported = await service.export();

      expect(await File(exported).exists(), isTrue);
      expect(await File(exported).length(), greaterThan(0));
    },
  );

  test(
    'UIBUG-001: el respaldo exportado en Android es válido y restaurable',
    () async {
      final (database, repo) = await androidLikeDatabase('android_rt.db');
      final service = BackupService(database);

      final exported = await service.export();

      // El respaldo debe pasar la propia validación de la aplicación.
      final validation = await service.validate(exported);
      expect(
        validation.isValid,
        isTrue,
        reason: 'validate() rechazó el respaldo: ${validation.problem}',
      );
      expect(validation.schemaVersion, AppDatabase.schemaVersion);

      // Se altera la base después de exportar...
      await repo.addPerson(name: 'Añadido después', role: PersonRole.family);
      expect((await repo.people()).length, 2);

      // ...y la restauración debe devolver el estado anterior.
      await service.restore(exported);
      final afterRestore = await repo.people();
      expect(
        afterRestore.length,
        1,
        reason: 'la restauración debe recuperar el estado del respaldo',
      );
      expect(afterRestore.single['name'], 'Familiar');
      await database.close();
    },
  );

  test('el respaldo representa un estado consistente (integrity_check ok)', () async {
    final (database, repo) = await androidLikeDatabase('android_ci.db');
    addTearDown(database.close);
    final service = BackupService(database);

    // Escritura inmediatamente antes de exportar: si el checkpoint no dejara la
    // base en un estado consistente, esta fila podría no estar en la copia.
    await repo.addPerson(name: 'Justo antes', role: PersonRole.family);
    final exported = await service.export();

    final validation = await service.validate(exported);
    expect(validation.isValid, isTrue, reason: validation.problem);

    // La fila recién escrita tiene que estar en el respaldo.
    final copy = AppDatabase(factory: databaseFactoryFfi, path: exported);
    addTearDown(copy.close);
    final names = (await AgroRepository(
      copy,
    ).people()).map((row) => row['name']).toList();
    expect(names, contains('Justo antes'));
  });
}
