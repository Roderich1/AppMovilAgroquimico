import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart'
    show Database, OpenDatabaseOptions, Sqflite;

import '../domain/installation_access.dart';
import '../domain/restore_ownership.dart';
import 'app_database.dart';
import 'backup_container_reader.dart';
import 'backup_encryption.dart' show BackupEnvelopeHeader;
import 'database_replacement.dart';
import 'invoice_storage.dart';
import 'restore_safety_copies.dart';

export '../domain/restore_ownership.dart'
    show BackupOwnership, RestoreRejection;
export 'backup_container_reader.dart' show BackupExtractionLimits;
export 'restore_safety_copies.dart'
    show RestoreBlockedException, RestoreSafetyCopies;

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
  BackupService(
    this.appDatabase, {
    Future<Directory> Function()? invoicesDir,
    Future<Directory> Function()? exportDirectory,
    @visibleForTesting Future<void> Function(File partial)? beforePublish,
    @visibleForTesting Future<void> Function(File partial)? afterSafetyCopy,
    @visibleForTesting Future<void> Function()? afterCheckpoint,
    BackupExtractionLimits extractionLimits = BackupExtractionLimits.standard,
    RestoreSafetyCopies? safetyCopies,
  }) : extractionLimits = extractionLimits,
       _containerReader = BackupContainerReader(extractionLimits),
       _invoicesDir = invoicesDir ?? resolveInvoicesDirectory,
       _exportDirectory = exportDirectory ?? _defaultExportDirectory,
       _beforePublish = beforePublish,
       _afterSafetyCopy = afterSafetyCopy,
       _afterCheckpoint = afterCheckpoint {
    this.safetyCopies =
        safetyCopies ?? RestoreSafetyCopies(appDatabase.resolvePath);
  }

  final AppDatabase appDatabase;
  final BackupExtractionLimits extractionLimits;

  /// Copias `.previo` de la base anterior a cada restauración, con su
  /// registro durable y su limpieza local (F08-ADR-003 §7).
  late final RestoreSafetyCopies safetyCopies;
  final BackupContainerReader _containerReader;
  final Future<Directory> Function() _invoicesDir;
  final Future<Directory> Function() _exportDirectory;

  /// Sólo pruebas: se ejecuta con el archivo parcial ya escrito en el destino
  /// y antes de publicarlo; si falla, la exportación se aborta.
  final Future<void> Function(File partial)? _beforePublish;

  /// Sólo pruebas: se ejecuta con la copia previa a restaurar ya escrita y
  /// antes de cotejarla con la base cerrada.
  final Future<void> Function(File partial)? _afterSafetyCopy;

  /// Sólo pruebas: se ejecuta tras el checkpoint de la copia previa y antes
  /// de cerrar la base.
  final Future<void> Function()? _afterCheckpoint;

  static Future<Directory> _defaultExportDirectory() async =>
      await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();

  /// SHA-256 (hex en minúsculas) del contenido de [file], leído por bloques.
  static Future<String> sha256OfFile(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  static final _sha256Hex = RegExp(r'^[0-9a-f]{64}$');

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

  /// Sufijo del archivo mientras se escribe en el destino. No termina en
  /// [containerExtension], así que [listAvailableBackups] nunca lo ofrece.
  static const partialSuffix = '.part';
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
    // Columnas: busy, log, checkpointed. Se lee por nombre.
    final busy = result.isEmpty ? 1 : (result.first['busy'] as int? ?? 1);
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
    // Fotografías de compras tardías pendientes de revisión (RF-03): viajan
    // igual, aunque ninguna compra confirmada las cite todavía.
    for (final path in await _draftInvoicePaths(database)) {
      byName.putIfAbsent(p.basename(path), () => []);
    }
    return byName;
  }

  /// `late_operation_drafts.invoice_image_path` (esquema v11), si existe en
  /// esta base. Una base anterior no la tiene y no aporta nada.
  static Future<bool> _hasDraftInvoices(Database database) async =>
      (await database.rawQuery(
        "SELECT 1 FROM pragma_table_info('late_operation_drafts') "
        "WHERE name = 'invoice_image_path'",
      )).isNotEmpty;

  static Future<List<String>> _draftInvoicePaths(Database database) async {
    if (!await _hasDraftInvoices(database)) return const [];
    return [
      for (final row in await database.rawQuery(
        'SELECT invoice_image_path FROM late_operation_drafts '
        'WHERE invoice_image_path IS NOT NULL',
      ))
        if ((row['invoice_image_path'] as String?)?.trim().isNotEmpty ?? false)
          (row['invoice_image_path']! as String).trim(),
    ];
  }

  /// Exporta un contenedor `.agrobackup` con la base y sus fotografías.
  ///
  /// El orden importa: se consolida, se reúne todo en una carpeta temporal, se
  /// valida lo reunido, se empaqueta, **se vuelve a validar el paquete escrito**
  /// y sólo entonces se mueve al destino definitivo. Un respaldo que la
  /// aplicación no sabe releer no protege de nada, y la única forma de saberlo
  /// es intentarlo.
  Future<BackupExportResult> export() => _buildContainer(
    (packed, attachmentCount, warnings) async => BackupExportResult(
      path: await _publish(packed),
      attachmentCount: attachmentCount,
      warnings: warnings,
    ),
  );

  /// Genera y valida un contenedor igual que [export], pero **no lo publica**
  /// en la carpeta de respaldos: [use] lo recibe en la carpeta temporal
  /// privada de la app y, al terminar (o fallar), se borra. Es lo que usa el
  /// respaldo remoto para cifrarlo sin dejar una copia legible en
  /// `Descargas` (F08-ADR-003 §5.2).
  Future<T> withPrivateContainer<T>(
    Future<T> Function(File container, BackupExportResult info) use,
  ) => _buildContainer(
    (packed, attachmentCount, warnings) => use(
      packed,
      BackupExportResult(
        path: '',
        attachmentCount: attachmentCount,
        warnings: warnings,
      ),
    ),
  );

  Future<T> _buildContainer<T>(
    Future<T> Function(File packed, int attachmentCount, List<String> warnings)
    use,
  ) async {
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

      return await use(File(packed), attachments.length, warnings);
    } finally {
      await _deleteQuietly(staging);
    }
  }

  /// Lleva el paquete validado [packed] a la carpeta de respaldos.
  ///
  /// La carpeta de destino suele estar en otro sistema de archivos que la
  /// temporal, así que se copia primero a un archivo `.part` **en el mismo
  /// directorio**, se comprueba que sus bytes son los del paquete validado, se
  /// fuerza a disco y sólo entonces se renombra al nombre definitivo. Renombrar
  /// dentro de un directorio es atómico: el nombre de respaldo aparece completo
  /// o no aparece. Si algo falla, el parcial se borra y no queda nada que
  /// parezca un respaldo.
  Future<String> _publish(File packed) async {
    final directory = await _exportDirectory();
    await directory.create(recursive: true);
    await _discardStalePartials(directory);
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    var target = p.join(
      directory.path,
      '$_fileNamePrefix$stamp$containerExtension',
    );
    for (var n = 1; await File(target).exists(); n++) {
      target = p.join(
        directory.path,
        '$_fileNamePrefix$stamp-$n$containerExtension',
      );
    }
    final partial = File('$target$partialSuffix');
    try {
      await packed.copy(partial.path);
      final handle = await partial.open(mode: FileMode.append);
      try {
        await handle.flush();
      } finally {
        await handle.close();
      }
      if (_beforePublish != null) await _beforePublish(partial);
      if (await sha256OfFile(partial) != await sha256OfFile(packed)) {
        throw const BackupException(
          'El respaldo no se pudo copiar completo a su carpeta. No se guardó; '
          'vuelva a intentarlo.',
        );
      }
      await partial.rename(target);
      return target;
    } on Object {
      await _deleteQuietly(partial);
      rethrow;
    }
  }

  /// Parciales que dejó una exportación interrumpida (p. ej. el sistema cerró
  /// la app a mitad de la copia). Nunca se ofrecieron como respaldo.
  Future<void> _discardStalePartials(Directory directory) async {
    await for (final entity in directory.list()) {
      final name = p.basename(entity.path);
      if (entity is File &&
          name.startsWith(_fileNamePrefix) &&
          name.endsWith(partialSuffix)) {
        await _deleteQuietly(entity);
      }
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
    final header = await _firstBytes(file, 8);
    if (BackupEnvelopeHeader.hasMagic(header)) {
      // Sólo el respaldo remoto descifra, con la clave de recuperación: una
      // copia cifrada no es un respaldo local que se pueda abrir sin ella.
      return const BackupValidation.invalid(
        'Esta copia está cifrada. Se restaura desde «Respaldo en la nube», '
        'con su clave de recuperación.',
      );
    }
    return _looksLikeZip(header)
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
      return (await _validateExtracted(extracted)).validation;
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

  /// Comprueba un contenedor ya extraído: el manifiesto, la base contra el
  /// tamaño y el SHA-256 que declara el manifiesto, y cada fotografía contra
  /// el suyo. Devuelve además los nombres de las fotografías verificadas: son
  /// las únicas que se restauran.
  ///
  /// El SHA-256 de la base detecta una base cambiada aunque siga siendo SQLite
  /// íntegra (`integrity_check` no puede saberlo). No es una firma: protege de
  /// daño y de una alteración que no reescriba también el manifiesto. Contra
  /// eso, la copia remota se coteja además con el hash que registró el
  /// servidor al recibirla.
  Future<({BackupValidation validation, Set<String> attachments})>
  _validateExtracted(Directory extracted) async {
    ({BackupValidation validation, Set<String> attachments}) invalid(
      String reason,
    ) => (validation: BackupValidation.invalid(reason), attachments: const {});

    final manifestFile = File(p.join(extracted.path, _manifestName));
    if (!await manifestFile.exists()) {
      return invalid(
        'El archivo no es un respaldo de Agrocuentas (falta el manifiesto).',
      );
    }

    final Map<String, Object?> manifest;
    try {
      manifest =
          jsonDecode(await manifestFile.readAsString()) as Map<String, Object?>;
    } on Object {
      return invalid(
        'El manifiesto del respaldo está dañado y no se puede leer.',
      );
    }

    if (manifest['application'] != 'agrocuentas') {
      return invalid('El archivo no es un respaldo de Agrocuentas.');
    }
    final format = manifest['backupFormatVersion'];
    if (format is! int || format > backupFormatVersion) {
      return invalid(
        'El respaldo usa un formato más reciente (versión $format) que esta '
        'aplicación (hasta $backupFormatVersion). Actualice la aplicación.',
      );
    }

    final databaseFile = File(p.join(extracted.path, _databaseName));
    if (!await databaseFile.exists()) {
      return invalid('El respaldo no contiene la base de datos.');
    }
    final declared = manifest['database'];
    final declaredSha = declared is Map ? declared['sha256'] : null;
    final declaredBytes = declared is Map ? declared['bytes'] : null;
    if (declared is! Map ||
        declared['name'] != _databaseName ||
        declaredSha is! String ||
        !_sha256Hex.hasMatch(declaredSha) ||
        declaredBytes is! int) {
      return invalid(
        'El manifiesto del respaldo no describe la integridad de la base de '
        'datos. No se puede comprobar y no se restaurará.',
      );
    }
    if (await databaseFile.length() != declaredBytes ||
        await sha256OfFile(databaseFile) != declaredSha) {
      return invalid(
        'La base de datos del respaldo no coincide con su manifiesto (SHA-256): '
        'está dañada o fue modificada. No se restaurará.',
      );
    }
    final database = await _validateDatabaseFile(databaseFile.path);
    if (!database.isValid) {
      return (validation: database, attachments: const <String>{});
    }

    final rawAttachments = manifest['attachments'] ?? const <Object?>[];
    if (rawAttachments is! List) {
      return invalid('El manifiesto describe mal las fotografías.');
    }
    final verified = <String>{};
    for (final attachment in rawAttachments) {
      final name = attachment is Map ? attachment['name'] : null;
      if (name is! String) {
        return invalid('El manifiesto describe una fotografía sin nombre.');
      }
      // Sólo un nombre de archivo: nunca una ruta que salga de la carpeta de
      // facturas al restaurar.
      if (name.isEmpty ||
          name == '.' ||
          name == '..' ||
          name.contains('/') ||
          name.contains(r'\')) {
        return invalid('El manifiesto describe una fotografía no permitida.');
      }
      final stored = File(p.join(extracted.path, _invoicesFolder, name));
      if (!await stored.exists()) {
        return invalid(
          'El respaldo anuncia la fotografía "$name" pero no la contiene.',
        );
      }
      final expected = (attachment as Map)['sha256'];
      if (expected is! String ||
          !_sha256Hex.hasMatch(expected) ||
          await sha256OfFile(stored) != expected) {
        return invalid('La fotografía "$name" del respaldo está dañada.');
      }
      verified.add(name);
    }

    return (
      validation: BackupValidation.valid(
        version: database.schemaVersion!,
        format: BackupFormat.container,
        attachmentCount: verified.length,
        createdAt: DateTime.tryParse('${manifest['createdAt']}'),
      ),
      attachments: verified,
    );
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

  /// Extrae el contenedor a una carpeta temporal, con límites de recursos
  /// comprobados antes y durante la extracción ([BackupContainerReader]).
  ///
  /// Rechaza rutas que salgan de la carpeta de destino o que no tengan la
  /// forma del contenedor: un ZIP puede contener nombres como `../../algo`, y
  /// extraerlos escribiría fuera. Ante cualquier rechazo borra lo extraído.
  Future<Directory> _extract(String path) async {
    final destination = await Directory.systemTemp.createTemp(
      'agro_backup_open_',
    );
    try {
      await _containerReader.extract(path, destination);
      return destination;
    } on BackupContainerRejected catch (error) {
      await _deleteQuietly(destination);
      throw BackupException(error.message);
    } on Object catch (error) {
      await _deleteQuietly(destination);
      if (error is Error) rethrow;
      throw BackupException(
        'El archivo no se pudo abrir como respaldo: $error',
      );
    }
  }

  /// Titular que declara una base candidata, sin modificarla. Una base
  /// anterior a la política (esquema < 8) no tiene vínculo: es histórica. Si
  /// no se puede leer, falla con [BackupOwnershipException]: no se restaura
  /// una copia cuya propiedad no se pudo comprobar.
  Future<BackupOwnership> readOwnership(String databasePath) async {
    Database? candidate;
    try {
      candidate = await appDatabase.resolvedFactory.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      final version =
          Sqflite.firstIntValue(
            await candidate.rawQuery('PRAGMA user_version'),
          ) ??
          0;
      if (version < AppDatabase.ownerBindingsSinceVersion) {
        return const BackupOwnership.historical();
      }
      final settings = {
        for (final row in await candidate.query('app_settings'))
          row['key']! as String: row['value'] as String?,
      };
      final active = await candidate.query(
        'owner_bindings',
        columns: ['member_id', 'tenant_id'],
        where: 'ended_at IS NULL',
      );
      if (active.length > 1) throw const BackupOwnershipException();
      return BackupOwnership(
        origin:
            settings[AppDatabase.installOriginKey] ==
                AppDatabase.installOriginNew
            ? InstallOrigin.newUnderPolicy
            : InstallOrigin.legacyPrePolicy,
        binding: active.isEmpty
            ? null
            : OwnerScope(
                memberId: active.single['member_id']! as String,
                tenantId: active.single['tenant_id']! as String,
              ),
        activatedInstallationRef:
            settings[AppDatabase.activatedInstallationKey],
      );
    } on BackupOwnershipException {
      rethrow;
    } on Object {
      throw const BackupOwnershipException();
    } finally {
      await candidate?.close();
    }
  }

  /// [readOwnership] de un archivo de respaldo (cualquiera de los dos
  /// formatos), para avisar antes de confirmar. No modifica nada.
  Future<BackupOwnership> inspectOwnership(String path) async {
    final validation = await validate(path);
    if (!validation.isValid) throw BackupException(validation.problem!);
    if (validation.format != BackupFormat.container) {
      return readOwnership(path);
    }
    final extracted = await _extract(path);
    try {
      return await readOwnership(p.join(extracted.path, _databaseName));
    } finally {
      await _deleteQuietly(extracted);
    }
  }

  /// Reemplaza los datos actuales por los del respaldo.
  ///
  /// Secuencia: validar el archivo → consolidar y cerrar la base actual y
  /// guardar una copia de seguridad completa y verificada de lo que hay ahora
  /// (base **y** fotografías; [_secureCurrentDatabase]) → sustituir → devolver
  /// las fotografías a su sitio → reabrir (lo que dispara las migraciones si el
  /// respaldo era más antiguo) → reconstruir las rutas de las fotos →
  /// comprobar que la base resultante sirve.
  ///
  /// Ante cualquier fallo se deshace **todo**: nunca queda una base nueva con
  /// las fotos viejas ni al revés.
  ///
  /// Todo ocurre en exclusiva ([DatabaseReplacementGuard.replace]): las
  /// escrituras en curso terminan antes y ninguna nueva entra hasta el final.
  /// Antes de tocar nada se lee el titular que declara la base del respaldo y
  /// se entrega a [verifyOwnership]; si lo rechaza, o si no se puede leer, la
  /// base y las fotografías actuales quedan intactas.
  ///
  /// [prepareRestored] se ejecuta con la base restaurada ya abierta, dentro
  /// del tramo que se deshace si falla: lo usa `GuardedRestore` para pausar
  /// la outbox restaurada antes de que nadie más vea la base. [afterReplace]
  /// sólo lo usan las pruebas: se ejecuta después y, si falla, también se
  /// deshace todo.
  Future<BackupRestoreResult> restore(
    String path, {
    Future<void> Function(BackupOwnership ownership)? verifyOwnership,
    Future<void> Function(Database restored)? prepareRestored,
    Future<void> Function()? afterReplace,
  }) => appDatabase.replacement.replace(
    () => _restoreExclusively(
      path,
      verifyOwnership,
      prepareRestored,
      afterReplace,
    ),
  );

  /// Copia privada y ya validada de un respaldo: se valida y se restaura la
  /// **misma** copia, así que lo comprobado es exactamente lo que se copia
  /// aunque el archivo original cambie entretanto.
  Future<_StagedBackup> _stage(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const BackupException('El archivo no existe.');
    }
    if (await file.length() == 0) {
      throw const BackupException('El archivo está vacío.');
    }
    final header = await _firstBytes(file, 8);
    if (BackupEnvelopeHeader.hasMagic(header)) {
      // Nunca se sustituye la base con algo que no se descifró y validó.
      throw const BackupException(
        'Esta copia está cifrada. Se restaura desde «Respaldo en la nube», '
        'con su clave de recuperación.',
      );
    }
    final isContainer = _looksLikeZip(header);
    final directory = isContainer
        ? await _extract(path)
        : await Directory.systemTemp.createTemp('agro_backup_open_');
    try {
      if (isContainer) {
        final checked = await _validateExtracted(directory);
        if (!checked.validation.isValid) {
          throw BackupException(checked.validation.problem!);
        }
        return _StagedBackup(
          directory,
          p.join(directory.path, _databaseName),
          checked.validation,
          checked.attachments,
        );
      }
      final copy = p.join(directory.path, _databaseName);
      await file.copy(copy);
      final validation = await _validateDatabaseFile(copy);
      if (!validation.isValid) throw BackupException(validation.problem!);
      return _StagedBackup(directory, copy, validation, const {});
    } on BackupException {
      await _deleteQuietly(directory);
      rethrow;
    } on Exception catch (error) {
      await _deleteQuietly(directory);
      throw BackupException('No se pudo leer el archivo de respaldo: $error');
    }
  }

  Future<BackupRestoreResult> _restoreExclusively(
    String path,
    Future<void> Function(BackupOwnership ownership)? verifyOwnership,
    Future<void> Function(Database restored)? prepareRestored,
    Future<void> Function()? afterReplace,
  ) async {
    final target = await appDatabase.resolvePath();
    if (target == ':memory:') {
      throw const BackupException(
        'Esta base de datos no admite restauración desde archivo.',
      );
    }

    // Antes de leer siquiera el respaldo: si hay una copia previa
    // indispensable sin resolver, o el registro no se puede leer, no se
    // empieza (F08-ADR-003 §7.2). También aplica el plazo y la cota.
    await safetyCopies.ensureCanStartRestore();

    final staged = await _stage(path);
    final validation = staged.validation;
    final databaseSource = staged.databasePath;
    final isContainer = validation.format == BackupFormat.container;

    // La propiedad se comprueba sobre la misma base que se va a copiar y
    // antes de guardar, cerrar o reemplazar nada.
    try {
      final ownership = await readOwnership(databaseSource);
      if (verifyOwnership != null) await verifyOwnership(ownership);
    } on Object {
      await _deleteQuietly(staged.directory);
      rethrow;
    }

    // El formato histórico no trae fotografías y no las toca: no hay motivo
    // para resolver siquiera dónde viven.
    final invoicesDirectory = isContainer ? await _invoicesDir() : null;

    // La entrada del registro se escribe **antes** que la copia: si el
    // proceso muere a mitad, la copia queda protegida como interrumpida.
    final SafetyCopySlot slot;
    try {
      slot = await safetyCopies.begin();
    } on Object {
      await _deleteQuietly(staged.directory);
      rethrow;
    }
    final safetyCopy = slot.databasePath;
    final invoicesBackup = invoicesDirectory == null
        ? null
        : Directory(slot.invoicesPath);

    // Preparación: copia previa completa de la base y de las fotografías. Si
    // algo falla aquí **no empieza el reemplazo**: la base actual sigue como
    // estaba y se descarta lo que se hubiera copiado a medias.
    final bool hadPrevious;
    final bool hadInvoices;
    try {
      await Directory(p.dirname(safetyCopy)).create(recursive: true);
      hadPrevious = await _secureCurrentDatabase(target, safetyCopy);
      // Copia de las fotografías actuales, para poder deshacer el conjunto y
      // no sólo la base.
      hadInvoices =
          invoicesBackup != null &&
          await _copyDirectory(invoicesDirectory!, invoicesBackup);
    } on Object {
      await _deleteQuietly(File('$safetyCopy$partialSuffix'));
      try {
        await safetyCopies.discard(slot);
      } on Object {
        // La entrada queda en preparación y pasará a interrumpida: protegida,
        // aunque aquí la base no llegó a sustituirse.
      }
      await _deleteQuietly(staged.directory);
      rethrow;
    }

    // Si algo falla al deshacer, la copia previa (base y fotografías) es lo
    // único que conserva los datos anteriores: no se borra.
    var keepInvoicesBackup = false;
    try {
      await File(databaseSource).copy(target);
      // Se descartan los diarios del archivo anterior. Ya no guardan nada:
      // [_secureCurrentDatabase] comprobó que el `-wal` quedó vacío tras el
      // checkpoint y el cierre, y su contenido está en la copia previa. Si
      // quedaran, corromperían la base restaurada.
      for (final suffix in const ['-wal', '-shm']) {
        final journal = File('$target$suffix');
        if (await journal.exists()) await journal.delete();
      }

      // Sólo las fotografías que describe el manifiesto y cuyo SHA-256 se
      // comprobó; cualquier otro archivo del paquete se ignora.
      var restoredAttachments = 0;
      final restoredNames = <String>{};
      if (isContainer) {
        await invoicesDirectory!.create(recursive: true);
        for (final name in staged.attachments) {
          await File(p.join(staged.directory.path, _invoicesFolder, name))
              .copy(p.join(invoicesDirectory.path, name));
          restoredNames.add(name);
          restoredAttachments++;
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

      if (prepareRestored != null) await prepareRestored(restored);
      if (afterReplace != null) await afterReplace();
      // Comprobación del estado restaurado (F08-ADR-003 §7.1): sin ella la
      // copia previa no se da por prescindible. Si falla, se deshace todo.
      await _verifyRestoredState(restored);

      // La sustitución es definitiva: la copia previa deja de ser
      // indispensable y entra en el plazo y la cota.
      await _resolveSafetyCopy(
        slot,
        hadPrevious: hadPrevious,
        resolve: safetyCopies.markFinalized,
      );
      return BackupRestoreResult(
        safetyCopyPath: hadPrevious ? safetyCopy : '',
        format: validation.format,
        restoredAttachments: restoredAttachments,
        warnings: warnings,
      );
    } on Object {
      // Deshacer el conjunto: base y fotografías vuelven a como estaban. Los
      // diarios son de la base restaurada y no deben aplicarse a la anterior.
      try {
        await appDatabase.close();
        for (final suffix in const ['-wal', '-shm']) {
          await _deleteQuietly(File('$target$suffix'));
        }
        if (hadPrevious) {
          await File(safetyCopy).copy(target);
        } else {
          await _deleteQuietly(File(target));
        }
        if (hadInvoices) {
          await _deleteQuietly(invoicesDirectory);
          await _copyDirectory(invoicesBackup, invoicesDirectory);
        }
      } on Object {
        // El rollback no terminó: la copia previa es indispensable.
        keepInvoicesBackup = true;
        try {
          await safetyCopies.markInterrupted(slot);
        } on Object {
          // Sigue en preparación y pasará a interrumpida en el siguiente
          // mantenimiento: protegida igualmente.
        }
        rethrow;
      }
      await _resolveSafetyCopy(
        slot,
        hadPrevious: hadPrevious,
        resolve: safetyCopies.markRolledBack,
      );
      rethrow;
    } finally {
      await _deleteQuietly(staged.directory);
      if (invoicesBackup != null && !keepInvoicesBackup) {
        await _deleteQuietly(invoicesBackup);
      }
    }
  }

  /// La base restaurada abre, está íntegra, tiene el esquema de esta
  /// versión ya migrado y las tablas de la aplicación. Sólo entonces la copia
  /// previa deja de ser indispensable. La propiedad no se comprueba aquí: la
  /// reclasifica `GuardedRestore` y, si no puede, deja el acceso en null
  /// (falla cerrado) sobre una base íntegra.
  Future<void> _verifyRestoredState(Database restored) async {
    const problem = BackupException(
      'La base restaurada no superó la comprobación final. No se restauró; '
      'sus datos anteriores se conservan.',
    );
    final integrity = await restored.rawQuery('PRAGMA integrity_check');
    if (integrity.isEmpty || '${integrity.first.values.first}' != 'ok') {
      throw problem;
    }
    final version = Sqflite.firstIntValue(
      await restored.rawQuery('PRAGMA user_version'),
    );
    if (version != AppDatabase.schemaVersion) throw problem;
    final tables = {
      for (final row in await restored.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      ))
        row['name'],
    };
    if (!requiredTables.every(tables.contains)) throw problem;
  }

  /// Marca la copia previa como resuelta y aplica la cota. Sin base anterior
  /// no hay nada que conservar y la entrada se retira. Un fallo aquí no
  /// cambia el resultado de la restauración: la entrada seguiría protegida,
  /// que es el lado seguro.
  Future<void> _resolveSafetyCopy(
    SafetyCopySlot slot, {
    required bool hadPrevious,
    required Future<void> Function(SafetyCopySlot) resolve,
  }) async {
    try {
      if (hadPrevious) {
        await resolve(slot);
      } else {
        await safetyCopies.discard(slot);
      }
      await safetyCopies.maintain();
    } on Object {
      // Ver arriba.
    }
  }

  /// Deja en [safetyCopy] una copia completa de la base actual y la cierra.
  /// Devuelve si había una base que conservar.
  ///
  /// En modo WAL las últimas transacciones confirmadas pueden estar sólo en
  /// `-wal`: copiar el archivo principal con la base abierta las perdería, y
  /// el rollback devolvería esa copia incompleta. Por eso, ya en exclusiva:
  ///
  /// 1. se abre la base si no lo estaba (abrirla integra el `-wal` que haya
  ///    dejado un cierre abrupto);
  /// 2. checkpoint `TRUNCATE` ([_consolidateForCopy]), que falla si no se
  ///    completa;
  /// 3. se cierra y se comprueba que no queda nada en `-wal`;
  /// 4. se copia el archivo principal a un `.part`, se fuerza a disco, se
  ///    coteja su SHA-256 con el de la base cerrada y sólo entonces se
  ///    renombra.
  ///
  /// Si un paso falla, la base no se ha sustituido; en los pasos 3 y 4 queda
  /// cerrada y se reabre con normalidad en el siguiente acceso.
  Future<bool> _secureCurrentDatabase(String target, String safetyCopy) async {
    final current = File(target);
    if (!await current.exists()) {
      await appDatabase.close();
      return false;
    }
    await _consolidateForCopy(await appDatabase.database);
    if (_afterCheckpoint != null) await _afterCheckpoint();
    await appDatabase.close();

    final wal = File('$target-wal');
    if (await wal.exists() && await wal.length() > 0) {
      throw const BackupException(
        'No se pudo cerrar la base de forma consistente antes de restaurar. '
        'No se restauró; sus datos actuales se conservan.',
      );
    }

    final partial = File('$safetyCopy$partialSuffix');
    await current.copy(partial.path);
    final handle = await partial.open(mode: FileMode.append);
    try {
      await handle.flush();
    } finally {
      await handle.close();
    }
    if (_afterSafetyCopy != null) await _afterSafetyCopy(partial);
    if (await partial.length() != await current.length() ||
        await sha256OfFile(partial) != await sha256OfFile(current)) {
      throw const BackupException(
        'No se pudo guardar una copia completa de sus datos actuales. No se '
        'restauró; sus datos actuales se conservan.',
      );
    }
    await partial.rename(safetyCopy);
    return true;
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
    if (await _hasDraftInvoices(database)) {
      for (final row in await database.rawQuery(
        'SELECT rowid AS row_ref, invoice_image_path '
        'FROM late_operation_drafts WHERE invoice_image_path IS NOT NULL',
      )) {
        final name = p.basename((row['invoice_image_path']! as String).trim());
        if (!restoredNames.contains(name)) continue;
        await database.update(
          'late_operation_drafts',
          {'invoice_image_path': p.join(invoicesDirectory.path, name)},
          where: 'rowid=?',
          whereArgs: [row['row_ref']],
        );
      }
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

class _StagedBackup {
  const _StagedBackup(
    this.directory,
    this.databasePath,
    this.validation,
    this.attachments,
  );

  final Directory directory;
  final String databasePath;
  final BackupValidation validation;

  /// Fotografías verificadas contra el manifiesto.
  final Set<String> attachments;
}

/// Error de negocio de la exportación o restauración, con mensaje presentable.
class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// No se pudo leer de quién es la copia: no se restaura.
class BackupOwnershipException extends BackupException {
  const BackupOwnershipException([
    super.message =
        'No se pudo comprobar el titular de esta copia. No se restauró; sus '
        'datos actuales se conservan.',
  ]);
}

/// La copia es de otro titular (o de una activación sin terminar).
class BackupOwnershipRejectedException extends BackupException {
  const BackupOwnershipRejectedException(super.message, this.rejection);
  final RestoreRejection rejection;
}
