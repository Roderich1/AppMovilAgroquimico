import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart'
    show Database, OpenDatabaseOptions, Sqflite;

import 'app_database.dart';

/// Resultado de validar un archivo de respaldo candidato.
class BackupValidation {
  const BackupValidation.valid(int version)
    : isValid = true,
      problem = null,
      schemaVersion = version;

  const BackupValidation.invalid(String reason)
    : isValid = false,
      problem = reason,
      schemaVersion = null;

  final bool isValid;

  /// Motivo del rechazo, en lenguaje de usuario. Nulo si el respaldo es válido.
  final String? problem;

  /// Versión de esquema del respaldo. Puede ser anterior a la actual: en ese
  /// caso la restauración disparará las migraciones normales al reabrir.
  final int? schemaVersion;
}

/// Exportación, validación y restauración del respaldo local.
///
/// Se extrae de `AgroRepository` porque es una responsabilidad distinta
/// (sistema de archivos, no reglas de negocio) y porque la restauración es la
/// operación más destructiva de la aplicación: conviene poder probarla aislada.
///
/// Limitación conocida y deliberada: el respaldo contiene **solo la base de
/// datos**. Las fotografías de factura viven en `<documentos>/invoices/` y no
/// se incluyen. Ver docs/13_LOCAL_STORAGE.md.
class BackupService {
  BackupService(this.appDatabase);

  final AppDatabase appDatabase;

  /// Tablas que debe contener cualquier respaldo legítimo de esta aplicación.
  /// Se comprueban para no restaurar una base SQLite ajena.
  static const requiredTables = <String>[
    'persons',
    'products',
    'campaigns',
    'purchases',
    'inventory_lots',
    'inventory_movements',
    'account_transactions',
  ];

  static const _fileNamePrefix = 'agroquimicos_backup_';

  /// Deja el archivo principal de la base en un estado del que se pueda hacer
  /// una copia consistente.
  ///
  /// En modo WAL las últimas transacciones confirmadas viven en el archivo
  /// `-wal`, no en el principal: copiar sólo el principal perdería datos. El
  /// checkpoint las integra.
  ///
  /// **Se consulta con `rawQuery`, no con `execute`** (UIBUG-001):
  /// `PRAGMA journal_mode` y `PRAGMA wal_checkpoint(...)` **devuelven filas**, y
  /// en Android `sqflite` mapea `execute` a `SQLiteDatabase.execSQL`, que
  /// rechaza toda sentencia con resultado. En escritorio (`sqflite_common_ffi`)
  /// `execute` sí las admitía, y por eso el defecto no se veía en la suite.
  Future<void> _consolidateForCopy(Database database) async {
    final modeRows = await database.rawQuery('PRAGMA journal_mode');
    final mode = modeRows.isEmpty
        ? ''
        : '${modeRows.first.values.first}'.toLowerCase();

    // Con diario de reversión (`delete`, `truncate`, `persist`) el archivo
    // principal ya contiene todo lo confirmado: no hay nada que integrar.
    if (mode != 'wal') return;

    // TRUNCATE hace lo mismo que FULL y además deja el `-wal` a cero, de modo
    // que copiar el archivo principal basta para tener la base completa.
    final result = await database.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    final busy = result.isEmpty ? 1 : (result.first.values.first as int? ?? 1);
    if (busy != 0) {
      // No se consolidó: copiar ahora produciría un respaldo incompleto en
      // silencio, que es peor que no tener respaldo.
      throw const BackupException(
        'No se pudo consolidar la base antes de copiarla porque está en uso. '
        'Cierre los diálogos abiertos y vuelva a intentarlo.',
      );
    }
  }

  /// Copia la base a la carpeta de descargas (o documentos como respaldo).
  ///
  /// Antes de devolver la ruta **valida el archivo escrito**: un respaldo que la
  /// aplicación no sabe releer no protege de nada, y la única forma de saberlo
  /// es intentarlo.
  Future<String> export() async {
    final database = await appDatabase.database;
    final source = appDatabase.openedPath;
    if (source == null || source == ':memory:') {
      throw const BackupException(
        'Esta base de datos no admite exportación a archivo.',
      );
    }
    await _consolidateForCopy(database);

    final directory =
        await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final target = p.join(directory.path, '$_fileNamePrefix$stamp.db');
    await File(source).copy(target);

    final validation = await validate(target);
    if (!validation.isValid) {
      // No se deja un archivo inservible con nombre de respaldo: el usuario
      // confiaría en él.
      try {
        await File(target).delete();
      } on FileSystemException {
        // si no se puede borrar, el mensaje siguiente sigue siendo lo importante
      }
      throw BackupException(
        'El respaldo se escribió pero no es legible: ${validation.problem}',
      );
    }
    return target;
  }

  /// Respaldos encontrados en las carpetas donde escribe [export], del más
  /// reciente al más antiguo.
  ///
  /// Evita depender de un selector de archivos del sistema: la aplicación
  /// siempre exporta a estas carpetas con un prefijo conocido, así que puede
  /// ofrecer la lista por sí misma.
  Future<List<File>> listAvailableBackups() async {
    final directories = <Directory?>[
      await getDownloadsDirectory(),
      await getApplicationDocumentsDirectory(),
    ];
    final found = <String, File>{};
    for (final directory in directories) {
      if (directory == null || !await directory.exists()) continue;
      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (name.startsWith(_fileNamePrefix) && name.endsWith('.db')) {
          found[entity.path] = entity;
        }
      }
    }
    final files = found.values.toList();
    files.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );
    return files;
  }

  /// Comprueba que [path] sea un respaldo de esta aplicación y esté íntegro.
  ///
  /// No modifica nada. Se ejecuta siempre antes de restaurar.
  Future<BackupValidation> validate(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return const BackupValidation.invalid('El archivo no existe.');
    }
    if (await file.length() == 0) {
      return const BackupValidation.invalid('El archivo está vacío.');
    }

    final factory = appDatabase.resolvedFactory;
    Database? candidate;
    try {
      candidate = await factory.openDatabase(
        path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );

      // `integrity_check` detecta un archivo truncado o corrupto.
      final integrity = await candidate.rawQuery('PRAGMA integrity_check');
      final verdict = integrity.isEmpty
          ? null
          : integrity.first.values.first?.toString();
      if (verdict != 'ok') {
        return BackupValidation.invalid(
          'El archivo está dañado (integrity_check: ${verdict ?? 'desconocido'}).',
        );
      }

      final tables = (await candidate.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      )).map((row) => row['name'] as String).toSet();
      final missing = requiredTables.where((t) => !tables.contains(t)).toList();
      if (missing.isNotEmpty) {
        return BackupValidation.invalid(
          'El archivo no es un respaldo de Agrocuentas '
          '(faltan tablas: ${missing.join(', ')}).',
        );
      }

      final version =
          Sqflite.firstIntValue(
            await candidate.rawQuery('PRAGMA user_version'),
          ) ??
          0;
      if (version > AppDatabase.schemaVersion) {
        return BackupValidation.invalid(
          'El respaldo procede de una versión más reciente de la aplicación '
          '(esquema $version, esta app admite hasta '
          '${AppDatabase.schemaVersion}). Actualice la aplicación.',
        );
      }
      return BackupValidation.valid(version);
    } on Exception catch (error) {
      return BackupValidation.invalid(
        'No se pudo leer el archivo como base de datos: $error',
      );
    } finally {
      await candidate?.close();
    }
  }

  /// Reemplaza la base actual por la del respaldo.
  ///
  /// Antes de sustituir nada guarda una copia de seguridad de la base vigente
  /// y la devuelve, para que una restauración equivocada siga siendo
  /// reversible. Si la copia del respaldo falla, deshace el cambio.
  ///
  /// Devuelve la ruta de la copia de seguridad previa.
  Future<String> restore(String path) async {
    final validation = await validate(path);
    if (!validation.isValid) {
      throw BackupException(validation.problem!);
    }

    final target = await appDatabase.resolvePath();
    if (target == ':memory:') {
      throw const BackupException(
        'Esta base de datos no admite restauración desde archivo.',
      );
    }

    // Se cierra la base antes de tocar el archivo.
    await appDatabase.close();

    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final safetyCopy = '$target.previo-$stamp.db';
    final current = File(target);
    final hadPrevious = await current.exists();
    if (hadPrevious) {
      await current.copy(safetyCopy);
    }

    try {
      await File(path).copy(target);
      // Se descartan los diarios de la base anterior: pertenecen a un archivo
      // que ya no existe y corromperían la base restaurada.
      for (final suffix in const ['-wal', '-shm']) {
        final journal = File('$target$suffix');
        if (await journal.exists()) await journal.delete();
      }
    } on Exception {
      if (hadPrevious) await File(safetyCopy).copy(target);
      rethrow;
    }

    // Se reabre para forzar las migraciones si el respaldo era más antiguo, y
    // se confirma que la base restaurada es utilizable.
    final restored = await appDatabase.database;
    final check = await restored.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='persons'",
    );
    if (check.isEmpty) {
      throw const BackupException(
        'La restauración no produjo una base utilizable.',
      );
    }
    return safetyCopy;
  }
}

/// Error de negocio de la exportación o restauración, con mensaje presentable.
class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}
