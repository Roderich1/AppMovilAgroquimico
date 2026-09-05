import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart'
    show Database, OpenDatabaseOptions, Sqflite;

import 'app_database.dart';
import 'invoice_storage.dart';

/// Formato de un archivo de respaldo.
enum BackupFormat {
  /// Contenedor `.agrobackup`: manifiesto + base + fotografías de factura.
  container,

  /// Copia suelta de la base, tal como exportaban las versiones anteriores.
  /// Se sigue admitiendo al restaurar, pero **no contiene fotografías**.
  legacyDatabase,
}

/// Resultado de validar un archivo de respaldo candidato.
class BackupValidation {
  const BackupValidation.valid({
    required int version,
    required this.format,
    this.attachmentCount = 0,
    this.createdAt,
  }) : isValid = true,
       problem = null,
       schemaVersion = version;

  const BackupValidation.invalid(String reason)
    : isValid = false,
      problem = reason,
      schemaVersion = null,
      format = BackupFormat.legacyDatabase,
      attachmentCount = 0,
      createdAt = null;

  final bool isValid;

  /// Motivo del rechazo, en lenguaje de usuario. Nulo si el respaldo es válido.
  final String? problem;

  /// Versión de esquema del respaldo. Puede ser anterior a la actual: en ese
  /// caso la restauración disparará las migraciones normales al reabrir.
  final int? schemaVersion;

  final BackupFormat format;

  /// Fotografías que trae el respaldo. Siempre 0 en el formato histórico.
  final int attachmentCount;

  final DateTime? createdAt;

  /// Si restaurarlo dejaría las facturas sin fotografía.
  bool get isLegacyWithoutPhotos => format == BackupFormat.legacyDatabase;
}

/// Resultado de exportar.
class BackupExportResult {
  const BackupExportResult({
    required this.path,
    required this.attachmentCount,
    this.warnings = const [],
  });

  final String path;
  final int attachmentCount;

  /// Discrepancias detectadas al reunir el contenido. **Nunca se ocultan**: un
  /// respaldo incompleto en silencio es peor que no tener respaldo.
  final List<String> warnings;

  bool get hasWarnings => warnings.isNotEmpty;
}

/// Resultado de restaurar.
class BackupRestoreResult {
  const BackupRestoreResult({
    required this.safetyCopyPath,
    required this.format,
    required this.restoredAttachments,
    this.warnings = const [],
  });

  /// Copia de los datos que había antes, por si la restauración fue un error.
  final String safetyCopyPath;
  final BackupFormat format;
  final int restoredAttachments;
  final List<String> warnings;
}

/// Exportación, validación y restauración del respaldo local.
///
/// Se extrae de `AgroRepository` porque es una responsabilidad distinta
/// (sistema de archivos, no reglas de negocio) y porque la restauración es la
/// operación más destructiva de la aplicación: conviene poder probarla aislada.
///
/// **Respaldo 2.0.** Hasta ahora el respaldo era una copia suelta de la base:
/// perder el teléfono significaba conservar las cuentas y perder todas las
/// fotografías de factura, que viven en `<documentos>/invoices/`. El formato
/// nuevo es un contenedor `.agrobackup` —un ZIP corriente, no un formato
/// binario inventado— con:
///
/// ```
/// manifest.json
/// database.db
/// invoices/<archivo>…
/// ```
///
/// Los respaldos `.db` de versiones anteriores se siguen restaurando; la
/// aplicación avisa de que ese formato no incluye fotografías.
class BackupService {
  BackupService(this.appDatabase, {Future<Directory> Function()? invoicesDir})
    : _invoicesDir = invoicesDir ?? resolveInvoicesDirectory;

  final AppDatabase appDatabase;
  final Future<Directory> Function() _invoicesDir;

  /// Versión del contenedor. Sube sólo si cambia la forma del paquete; es
  /// independiente de la versión de esquema de SQLite que lleva dentro.
  static const int backupFormatVersion = 1;

  /// Versión de la aplicación que se anota en el manifiesto.
  ///
  /// Se mantiene a mano junto a `version:` de `pubspec.yaml`: leerla en
  /// ejecución exigiría una dependencia más para un dato puramente
  /// informativo.
  static const String appVersion = '1.0.0';

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
  static const containerExtension = '.agrobackup';
  static const _manifestName = 'manifest.json';
  static const _databaseName = 'database.db';
  static const _invoicesFolder = 'invoices';

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

  /// Fotografías realmente referenciadas por alguna compra, con la compra que
  /// las cita.
  Future<Map<String, List<int>>> _referencedInvoices(Database database) async {
    final rows = await database.rawQuery(
      'SELECT id, invoice_image_path FROM purchases '
      'WHERE invoice_image_path IS NOT NULL',
    );
    final byName = <String, List<int>>{};
    for (final row in rows) {
      final path = (row['invoice_image_path'] as String?)?.trim();
      if (path == null || path.isEmpty) continue;
      byName.putIfAbsent(p.basename(path), () => []).add(row['id']! as int);
    }
    return byName;
  }

  /// Exporta un contenedor `.agrobackup` con la base y sus fotografías.
  ///
  /// El orden importa: se consolida, se reúne todo en una carpeta temporal, se
  /// valida lo reunido, se empaqueta, **se vuelve a validar el paquete escrito**
  /// y sólo entonces se mueve al destino definitivo. Un respaldo que la
  /// aplicación no sabe releer no protege de nada, y la única forma de saberlo
  /// es intentarlo.
  Future<BackupExportResult> export() async {
    final database = await appDatabase.database;
    final source = appDatabase.openedPath;
    if (source == null || source == ':memory:') {
      throw const BackupException(
        'Esta base de datos no admite exportación a archivo.',
      );
    }
    await _consolidateForCopy(database);

    final referenced = await _referencedInvoices(database);
    // La carpeta sólo se resuelve si hay algo que recoger: una base sin
    // facturas fotografiadas no tiene por qué depender del almacenamiento de
    // la plataforma.
    final invoicesDirectory = referenced.isEmpty ? null : await _invoicesDir();

    final staging = await Directory.systemTemp.createTemp('agro_backup_stage_');
    try {
      final stagedDatabase = File(p.join(staging.path, _databaseName));
      await File(source).copy(stagedDatabase.path);

      // Antes de empaquetar nada: si lo copiado no es una base legible, no
      // tiene sentido seguir.
      final staged = await _validateDatabaseFile(stagedDatabase.path);
      if (!staged.isValid) {
        throw BackupException(
          'La base no se pudo copiar en un estado legible: ${staged.problem}',
        );
      }

      final attachments = <Map<String, Object?>>[];
      final missing = <Map<String, Object?>>[];
      final warnings = <String>[];

      if (referenced.isNotEmpty) {
        final stagedInvoices = Directory(p.join(staging.path, _invoicesFolder));
        await stagedInvoices.create(recursive: true);
        for (final entry in referenced.entries) {
          final origin = File(p.join(invoicesDirectory!.path, entry.key));
          if (!await origin.exists()) {
            // **La pérdida no se oculta.** Se deja constancia en el manifiesto
            // y se avisa al usuario. El respaldo se completa igualmente:
            // bloquearlo por una foto que ya no está dejaría al usuario sin
            // copia de sus cuentas, que es peor.
            missing.add({'name': entry.key, 'purchaseIds': entry.value});
            continue;
          }
          final bytes = await origin.readAsBytes();
          await File(p.join(stagedInvoices.path, entry.key))
              .writeAsBytes(bytes, flush: true);
          attachments.add({
            'name': entry.key,
            'bytes': bytes.length,
            'sha256': sha256.convert(bytes).toString(),
            'purchaseIds': entry.value,
          });
        }
        if (missing.isNotEmpty) {
          warnings.add(
            missing.length == 1
                ? 'Falta la fotografía de 1 factura: ya no está en el '
                      'teléfono. El respaldo incluye todo lo demás.'
                : 'Faltan las fotografías de ${missing.length} facturas: ya no '
                      'están en el teléfono. El respaldo incluye todo lo demás.',
          );
        }
      }

      final databaseBytes = await stagedDatabase.readAsBytes();
      final manifest = <String, Object?>{
        'backupFormatVersion': backupFormatVersion,
        'application': 'agrocuentas',
        'appVersion': appVersion,
        'databaseSchemaVersion': staged.schemaVersion,
        'createdAt': DateTime.now().toIso8601String(),
        'database': {
          'name': _databaseName,
          'bytes': databaseBytes.length,
          'sha256': sha256.convert(databaseBytes).toString(),
        },
        'attachmentCount': attachments.length,
        'attachments': attachments,
        'missingAttachments': missing,
      };
      await File(p.join(staging.path, _manifestName)).writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest),
        flush: true,
      );

      final directory =
          await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final target = p.join(
        directory.path,
        '$_fileNamePrefix$stamp$containerExtension',
      );

      // Se empaqueta primero en la carpeta temporal: así el destino nunca ve
      // un archivo a medio escribir con nombre de respaldo.
      final packed = p.join(staging.path, 'packed$containerExtension');
      final encoder = ZipFileEncoder()..create(packed);
      await encoder.addFile(
        File(p.join(staging.path, _manifestName)),
        _manifestName,
      );
      await encoder.addFile(stagedDatabase, _databaseName);
      for (final attachment in attachments) {
        final name = attachment['name']! as String;
        await encoder.addFile(
          File(p.join(staging.path, _invoicesFolder, name)),
          '$_invoicesFolder/$name',
        );
      }
      await encoder.close();

      final packedValidation = await validate(packed);
      if (!packedValidation.isValid) {
        throw BackupException(
          'El respaldo se escribió pero no es legible: '
          '${packedValidation.problem}',
        );
      }

      await File(packed).copy(target);
      return BackupExportResult(
        path: target,
        attachmentCount: attachments.length,
        warnings: warnings,
      );
    } finally {
      await _deleteQuietly(staging);
    }
  }

  /// Respaldos encontrados en las carpetas donde escribe [export], del más
  /// reciente al más antiguo.
  ///
  /// Evita depender de un selector de archivos del sistema: la aplicación
  /// siempre exporta a estas carpetas con un prefijo conocido, así que puede
  /// ofrecer la lista por sí misma. Incluye los `.db` históricos, que se siguen
  /// pudiendo restaurar.
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
        if (!name.startsWith(_fileNamePrefix)) continue;
        if (name.endsWith(containerExtension) || name.endsWith('.db')) {
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
  /// No modifica nada. Se ejecuta siempre antes de restaurar. Reconoce los dos
  /// formatos por su contenido, no por su extensión.
  Future<BackupValidation> validate(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return const BackupValidation.invalid('El archivo no existe.');
    }
    if (await file.length() == 0) {
      return const BackupValidation.invalid('El archivo está vacío.');
    }
    return _looksLikeZip(await _firstBytes(file, 4))
        ? _validateContainer(path)
        : _validateDatabaseFile(path);
  }

  static bool _looksLikeZip(List<int> header) =>
      header.length >= 2 && header[0] == 0x50 && header[1] == 0x4B;

  static Future<List<int>> _firstBytes(File file, int count) async {
    final handle = await file.open();
    try {
      return await handle.read(count);
    } finally {
      await handle.close();
    }
  }

  Future<BackupValidation> _validateContainer(String path) async {
    Directory? extracted;
    try {
      extracted = await _extract(path);
      final manifestFile = File(p.join(extracted.path, _manifestName));
      if (!await manifestFile.exists()) {
        return const BackupValidation.invalid(
          'El archivo no es un respaldo de Agrocuentas (falta el manifiesto).',
        );
      }

      final Map<String, Object?> manifest;
      try {
        manifest = jsonDecode(
          await manifestFile.readAsString(),
        ) as Map<String, Object?>;
      } on Object {
        return const BackupValidation.invalid(
          'El manifiesto del respaldo está dañado y no se puede leer.',
        );
      }

      if (manifest['application'] != 'agrocuentas') {
        return const BackupValidation.invalid(
          'El archivo no es un respaldo de Agrocuentas.',
        );
      }
      final format = manifest['backupFormatVersion'];
      if (format is! int || format > backupFormatVersion) {
        return BackupValidation.invalid(
          'El respaldo usa un formato más reciente (versión $format) que esta '
          'aplicación (hasta $backupFormatVersion). Actualice la aplicación.',
        );
      }

      final databaseFile = File(p.join(extracted.path, _databaseName));
      if (!await databaseFile.exists()) {
        return const BackupValidation.invalid(
          'El respaldo no contiene la base de datos.',
        );
      }
      final database = await _validateDatabaseFile(databaseFile.path);
      if (!database.isValid) return database;

      final attachments = (manifest['attachments'] as List? ?? const [])
          .cast<Map<String, Object?>>();
      for (final attachment in attachments) {
        final name = attachment['name'] as String?;
        if (name == null) {
          return const BackupValidation.invalid(
            'El manifiesto describe una fotografía sin nombre.',
          );
        }
        final stored = File(p.join(extracted.path, _invoicesFolder, name));
        if (!await stored.exists()) {
          return BackupValidation.invalid(
            'El respaldo anuncia la fotografía "$name" pero no la contiene.',
          );
        }
        final expected = attachment['sha256'] as String?;
        if (expected != null) {
          final actual = sha256.convert(await stored.readAsBytes()).toString();
          if (actual != expected) {
            return BackupValidation.invalid(
              'La fotografía "$name" del respaldo está dañada.',
            );
          }
        }
      }

      return BackupValidation.valid(
        version: database.schemaVersion!,
        format: BackupFormat.container,
        attachmentCount: attachments.length,
        createdAt: DateTime.tryParse('${manifest['createdAt']}'),
      );
    } on BackupException catch (error) {
      return BackupValidation.invalid(error.message);
    } on Exception catch (error) {
      return BackupValidation.invalid(
        'No se pudo leer el archivo de respaldo: $error',
      );
    } finally {
      if (extracted != null) await _deleteQuietly(extracted);
    }
  }

  /// Valida una base SQLite suelta: el formato histórico, y también la base que
  /// viaja dentro del contenedor.
  Future<BackupValidation> _validateDatabaseFile(String path) async {
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
      return BackupValidation.valid(
        version: version,
        format: BackupFormat.legacyDatabase,
      );
    } on Exception catch (error) {
      return BackupValidation.invalid(
        'No se pudo leer el archivo como base de datos: $error',
      );
    } finally {
      await candidate?.close();
    }
  }

  /// Extrae el contenedor a una carpeta temporal.
  ///
  /// Rechaza rutas que salgan de la carpeta de destino: un ZIP puede contener
  /// nombres como `../../algo`, y extraerlos escribiría fuera.
  Future<Directory> _extract(String path) async {
    final destination = await Directory.systemTemp.createTemp(
      'agro_backup_open_',
    );
    final input = InputFileStream(path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      for (final entry in archive) {
        if (!entry.isFile) continue;
        final normalized = p.normalize(entry.name).replaceAll('\\', '/');
        if (normalized.startsWith('..') || p.isAbsolute(normalized)) {
          throw const BackupException(
            'El respaldo contiene rutas no permitidas y no se abrirá.',
          );
        }
        final outputPath = p.join(destination.path, normalized);
        await Directory(p.dirname(outputPath)).create(recursive: true);
        await File(outputPath)
            .writeAsBytes(entry.readBytes() ?? const [], flush: true);
      }
      return destination;
    } on BackupException {
      await _deleteQuietly(destination);
      rethrow;
    } on Exception catch (error) {
      await _deleteQuietly(destination);
      throw BackupException(
        'El archivo no se pudo abrir como respaldo: $error',
      );
    } finally {
      await input.close();
    }
  }

  /// Reemplaza los datos actuales por los del respaldo.
  ///
  /// Secuencia: validar el archivo → guardar una copia de seguridad de lo que
  /// hay ahora (base **y** fotografías) → cerrar la base → sustituir → devolver
  /// las fotografías a su sitio → reabrir (lo que dispara las migraciones si el
  /// respaldo era más antiguo) → reconstruir las rutas de las fotos →
  /// comprobar que la base resultante sirve.
  ///
  /// Ante cualquier fallo se deshace **todo**: nunca queda una base nueva con
  /// las fotos viejas ni al revés.
  Future<BackupRestoreResult> restore(String path) async {
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

    Directory? extracted;
    if (validation.format == BackupFormat.container) {
      extracted = await _extract(path);
    }
    final databaseSource = extracted == null
        ? path
        : p.join(extracted.path, _databaseName);

    // El formato histórico no trae fotografías y no las toca: no hay motivo
    // para resolver siquiera dónde viven.
    final invoicesDirectory = extracted == null ? null : await _invoicesDir();
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final safetyCopy = '$target.previo-$stamp.db';
    final current = File(target);
    final hadPrevious = await current.exists();

    // Copia de seguridad de las fotografías actuales, para poder deshacer el
    // conjunto y no sólo la base.
    final invoicesBackup = invoicesDirectory == null
        ? null
        : Directory('${invoicesDirectory.path}.previo-$stamp');
    final hadInvoices =
        invoicesBackup != null &&
        await _copyDirectory(invoicesDirectory!, invoicesBackup);

    if (hadPrevious) await current.copy(safetyCopy);

    // Se cierra la base antes de tocar el archivo.
    await appDatabase.close();

    try {
      await File(databaseSource).copy(target);
      // Se descartan los diarios de la base anterior: pertenecen a un archivo
      // que ya no existe y corromperían la base restaurada.
      for (final suffix in const ['-wal', '-shm']) {
        final journal = File('$target$suffix');
        if (await journal.exists()) await journal.delete();
      }

      var restoredAttachments = 0;
      final restoredNames = <String>{};
      if (extracted != null) {
        final source = Directory(p.join(extracted.path, _invoicesFolder));
        if (await source.exists()) {
          await for (final entity in source.list()) {
            if (entity is! File) continue;
            final name = p.basename(entity.path);
            await entity.copy(p.join(invoicesDirectory!.path, name));
            restoredNames.add(name);
            restoredAttachments++;
          }
        }
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

      final warnings = <String>[];
      if (validation.format == BackupFormat.legacyDatabase) {
        warnings.add(
          'Este respaldo usa el formato histórico, que sólo guarda la base de '
          'datos: no contiene fotografías de factura.',
        );
      } else {
        warnings.addAll(
          await _relinkInvoicePaths(
            restored,
            invoicesDirectory!,
            restoredNames,
          ),
        );
      }

      return BackupRestoreResult(
        safetyCopyPath: safetyCopy,
        format: validation.format,
        restoredAttachments: restoredAttachments,
        warnings: warnings,
      );
    } on Object {
      // Deshacer el conjunto: base y fotografías vuelven a como estaban.
      await appDatabase.close();
      if (hadPrevious) {
        await File(safetyCopy).copy(target);
      } else {
        await _deleteQuietly(File(target));
      }
      if (hadInvoices) {
        await _deleteQuietly(invoicesDirectory);
        await _copyDirectory(invoicesBackup, invoicesDirectory);
      }
      rethrow;
    } finally {
      if (extracted != null) await _deleteQuietly(extracted);
      if (invoicesBackup != null) await _deleteQuietly(invoicesBackup);
    }
  }

  /// Reapunta `purchases.invoice_image_path` a este dispositivo.
  ///
  /// La base guarda **rutas absolutas** del teléfono donde se tomó la foto. Un
  /// respaldo restaurado en otro dispositivo —o tras reinstalar, porque la
  /// carpeta de datos cambia— apuntaría a un directorio que no existe. Se
  /// reescribe sólo la ruta de las fotografías que el respaldo traía, por su
  /// nombre de archivo: es una reconstrucción acotada, no una migración global
  /// de rutas.
  Future<List<String>> _relinkInvoicePaths(
    Database database,
    Directory invoicesDirectory,
    Set<String> restoredNames,
  ) async {
    final rows = await database.rawQuery(
      'SELECT id, invoice_image_path FROM purchases '
      'WHERE invoice_image_path IS NOT NULL',
    );
    final orphans = <String>[];
    for (final row in rows) {
      final stored = (row['invoice_image_path'] as String?)?.trim();
      if (stored == null || stored.isEmpty) continue;
      final name = p.basename(stored);
      if (!restoredNames.contains(name)) {
        // El respaldo no traía esta fotografía. No se toca la ruta: se avisa.
        if (!await File(stored).exists()) orphans.add(name);
        continue;
      }
      await database.update(
        'purchases',
        {'invoice_image_path': p.join(invoicesDirectory.path, name)},
        where: 'id=?',
        whereArgs: [row['id']],
      );
    }
    if (orphans.isEmpty) return const [];
    return [
      orphans.length == 1
          ? 'Una factura restaurada no tiene su fotografía disponible.'
          : '${orphans.length} facturas restauradas no tienen su fotografía '
                'disponible.',
    ];
  }

  /// Copia [from] a [to]. Devuelve si el origen existía.
  Future<bool> _copyDirectory(Directory from, Directory to) async {
    if (!await from.exists()) return false;
    await to.create(recursive: true);
    await for (final entity in from.list()) {
      if (entity is File) {
        await entity.copy(p.join(to.path, p.basename(entity.path)));
      }
    }
    return true;
  }

  Future<void> _deleteQuietly(FileSystemEntity entity) async {
    try {
      if (await entity.exists()) await entity.delete(recursive: true);
    } on FileSystemException {
      // Borrar una carpeta temporal es limpieza, no parte del resultado: si el
      // sistema la retiene, no debe convertirse en un fallo de la operación.
    }
  }
}

/// Error de negocio de la exportación o restauración, con mensaje presentable.
class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}
