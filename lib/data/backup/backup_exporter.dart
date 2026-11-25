import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' show Database;

import '../app_database.dart';
import 'backup_models.dart';
import 'backup_validator.dart';

class BackupExporter {
  const BackupExporter({
    required this.appDatabase,
    required this.validator,
    required this.invoicesDir,
    required this.exportDirectory,
    this.beforePublish,
  });

  final AppDatabase appDatabase;
  final BackupValidator validator;
  final Future<Directory> Function() invoicesDir;
  final Future<Directory> Function() exportDirectory;
  final Future<void> Function(File partial)? beforePublish;

  Future<BackupExportResult> export() => _buildContainer(
    (packed, attachmentCount, warnings) async => BackupExportResult(
      path: await _publish(packed),
      attachmentCount: attachmentCount,
      warnings: warnings,
    ),
  );

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
    for (final path in await _draftInvoicePaths(database)) {
      byName.putIfAbsent(p.basename(path), () => []);
    }
    return byName;
  }

  static Future<List<String>> _draftInvoicePaths(Database database) async {
    if (!await hasDraftInvoicesColumn(database)) return const [];
    return [
      for (final row in await database.rawQuery(
        'SELECT invoice_image_path FROM late_operation_drafts '
        'WHERE invoice_image_path IS NOT NULL',
      ))
        if ((row['invoice_image_path'] as String?)?.trim().isNotEmpty ?? false)
          (row['invoice_image_path']! as String).trim(),
    ];
  }

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
    await consolidateDatabaseForCopy(database);

    final referenced = await _referencedInvoices(database);
    final invoicesDirectory = referenced.isEmpty ? null : await invoicesDir();

    final staging = await Directory.systemTemp.createTemp('agro_backup_stage_');
    try {
      final stagedDatabase = File(p.join(staging.path, backupDatabaseName));
      await File(source).copy(stagedDatabase.path);
      await validator.excludeLocalOnlyData(stagedDatabase.path);

      final staged = await validator.validateDatabaseFile(stagedDatabase.path);
      if (!staged.isValid) {
        throw BackupException(
          'La base no se pudo copiar en un estado legible: ${staged.problem}',
        );
      }

      final attachments = <Map<String, Object?>>[];
      final missing = <Map<String, Object?>>[];
      final warnings = <String>[];

      if (referenced.isNotEmpty) {
        final stagedInvoices = Directory(
          p.join(staging.path, backupInvoicesFolder),
        );
        await stagedInvoices.create(recursive: true);
        for (final entry in referenced.entries) {
          final origin = File(p.join(invoicesDirectory!.path, entry.key));
          if (!await origin.exists()) {
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
        'backupFormatVersion': backupFormatVersionConst,
        'application': 'agrocuentas',
        'appVersion': backupAppVersionConst,
        'databaseSchemaVersion': staged.schemaVersion,
        'createdAt': DateTime.now().toIso8601String(),
        'database': {
          'name': backupDatabaseName,
          'bytes': databaseBytes.length,
          'sha256': sha256.convert(databaseBytes).toString(),
        },
        'attachmentCount': attachments.length,
        'attachments': attachments,
        'missingAttachments': missing,
      };
      await File(p.join(staging.path, backupManifestName)).writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest),
        flush: true,
      );

      final packed = p.join(
        staging.path,
        'packed$backupContainerExtensionConst',
      );
      final encoder = ZipFileEncoder()..create(packed);
      await encoder.addFile(
        File(p.join(staging.path, backupManifestName)),
        backupManifestName,
      );
      await encoder.addFile(stagedDatabase, backupDatabaseName);
      for (final attachment in attachments) {
        final name = attachment['name']! as String;
        await encoder.addFile(
          File(p.join(staging.path, backupInvoicesFolder, name)),
          '$backupInvoicesFolder/$name',
        );
      }
      await encoder.close();

      final packedValidation = await validator.validate(packed);
      if (!packedValidation.isValid) {
        throw BackupException(
          'El respaldo se escribió pero no es legible: '
          '${packedValidation.problem}',
        );
      }

      return await use(File(packed), attachments.length, warnings);
    } finally {
      await backupDeleteQuietly(staging);
    }
  }

  Future<String> _publish(File packed) async {
    final directory = await exportDirectory();
    await directory.create(recursive: true);
    await _discardStalePartials(directory);
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    var target = p.join(
      directory.path,
      '$backupFileNamePrefix$stamp$backupContainerExtensionConst',
    );
    for (var n = 1; await File(target).exists(); n++) {
      target = p.join(
        directory.path,
        '$backupFileNamePrefix$stamp-$n$backupContainerExtensionConst',
      );
    }
    final partial = File('$target$backupPartialSuffixConst');
    try {
      await packed.copy(partial.path);
      final handle = await partial.open(mode: FileMode.append);
      try {
        await handle.flush();
      } finally {
        await handle.close();
      }
      if (beforePublish != null) await beforePublish!(partial);
      if (await backupSha256OfFile(partial) !=
          await backupSha256OfFile(packed)) {
        throw const BackupException(
          'El respaldo no se pudo copiar completo a su carpeta. No se guardó; '
          'vuelva a intentarlo.',
        );
      }
      await partial.rename(target);
      return target;
    } on Object {
      await backupDeleteQuietly(partial);
      rethrow;
    }
  }

  Future<void> _discardStalePartials(Directory directory) async {
    await for (final entity in directory.list()) {
      final name = p.basename(entity.path);
      if (entity is File &&
          name.startsWith(backupFileNamePrefix) &&
          name.endsWith(backupPartialSuffixConst)) {
        await backupDeleteQuietly(entity);
      }
    }
  }

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
        if (!name.startsWith(backupFileNamePrefix)) continue;
        if (name.endsWith(backupContainerExtensionConst) ||
            name.endsWith('.db')) {
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
}
