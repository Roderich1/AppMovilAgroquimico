import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart'
    show Database, OpenDatabaseOptions, Sqflite;

import '../../domain/installation_access.dart';
import '../../domain/restore_ownership.dart';
import '../app_database.dart';
import '../backup_container_reader.dart';
import '../backup_encryption.dart' show BackupEnvelopeHeader;
import 'backup_models.dart';

class BackupValidator {
  const BackupValidator({
    required this.appDatabase,
    required this.containerReader,
  });

  final AppDatabase appDatabase;
  final BackupContainerReader containerReader;

  Future<BackupValidation> validate(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return const BackupValidation.invalid('El archivo no existe.');
    }
    if (await file.length() == 0) {
      return const BackupValidation.invalid('El archivo está vacío.');
    }
    final header = await backupFirstBytes(file, 8);
    if (BackupEnvelopeHeader.hasMagic(header)) {
      return const BackupValidation.invalid(
        'Esta copia está cifrada. Se restaura desde «Respaldo en la nube», '
        'con su clave de recuperación.',
      );
    }
    return backupLooksLikeZip(header)
        ? validateContainer(path)
        : validateDatabaseFile(path);
  }

  Future<BackupValidation> validateContainer(String path) async {
    Directory? extracted;
    try {
      extracted = await extract(path);
      return (await validateExtracted(extracted)).validation;
    } on BackupException catch (error) {
      return BackupValidation.invalid(error.message);
    } on Exception catch (error) {
      return BackupValidation.invalid(
        'No se pudo leer el archivo de respaldo: $error',
      );
    } finally {
      await backupDeleteQuietly(extracted);
    }
  }

  Future<({BackupValidation validation, Set<String> attachments})>
  validateExtracted(Directory extracted) async {
    ({BackupValidation validation, Set<String> attachments}) invalid(
      String reason,
    ) => (validation: BackupValidation.invalid(reason), attachments: const {});

    final manifestFile = File(p.join(extracted.path, backupManifestName));
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
    if (format is! int || format > backupFormatVersionConst) {
      return invalid(
        'El respaldo usa un formato más reciente (versión $format) que esta '
        'aplicación (hasta $backupFormatVersionConst). Actualice la aplicación.',
      );
    }

    final databaseFile = File(p.join(extracted.path, backupDatabaseName));
    if (!await databaseFile.exists()) {
      return invalid('El respaldo no contiene la base de datos.');
    }
    final declared = manifest['database'];
    final declaredSha = declared is Map ? declared['sha256'] : null;
    final declaredBytes = declared is Map ? declared['bytes'] : null;
    if (declared is! Map ||
        declared['name'] != backupDatabaseName ||
        declaredSha is! String ||
        !backupSha256Hex.hasMatch(declaredSha) ||
        declaredBytes is! int) {
      return invalid(
        'El manifiesto del respaldo no describe la integridad de la base de '
        'datos. No se puede comprobar y no se restaurará.',
      );
    }
    if (await databaseFile.length() != declaredBytes ||
        await backupSha256OfFile(databaseFile) != declaredSha) {
      return invalid(
        'La base de datos del respaldo no coincide con su manifiesto (SHA-256): '
        'está dañada o fue modificada. No se restaurará.',
      );
    }
    final database = await validateDatabaseFile(databaseFile.path);
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
      if (name.isEmpty ||
          name == '.' ||
          name == '..' ||
          name.contains('/') ||
          name.contains(r'\')) {
        return invalid('El manifiesto describe una fotografía no permitida.');
      }
      final stored = File(p.join(extracted.path, backupInvoicesFolder, name));
      if (!await stored.exists()) {
        return invalid(
          'El respaldo anuncia la fotografía "$name" pero no la contiene.',
        );
      }
      final expected = (attachment as Map)['sha256'];
      if (expected is! String ||
          !backupSha256Hex.hasMatch(expected) ||
          await backupSha256OfFile(stored) != expected) {
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

  Future<void> excludeLocalOnlyData(String path) async {
    final staged = await appDatabase.resolvedFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      await AppDatabase.discardEstimationCopies(staged);
      await AppDatabase.discardVoiceEvidence(staged);
      await staged.execute('VACUUM');
    } finally {
      await staged.close();
    }
  }

  Future<BackupValidation> validateDatabaseFile(String path) async {
    final factory = appDatabase.resolvedFactory;
    Database? candidate;
    try {
      candidate = await factory.openDatabase(
        path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );

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
      final missing = backupRequiredTablesConst
          .where((t) => !tables.contains(t))
          .toList();
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

  Future<Directory> extract(String path) async {
    final destination = await Directory.systemTemp.createTemp(
      'agro_backup_open_',
    );
    try {
      await containerReader.extract(path, destination);
      return destination;
    } on BackupContainerRejected catch (error) {
      await backupDeleteQuietly(destination);
      throw BackupException(error.message);
    } on Object catch (error) {
      await backupDeleteQuietly(destination);
      if (error is Error) rethrow;
      throw BackupException(
        'El archivo no se pudo abrir como respaldo: $error',
      );
    }
  }

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

  Future<BackupOwnership> inspectOwnership(String path) async {
    final validation = await validate(path);
    if (!validation.isValid) throw BackupException(validation.problem!);
    if (validation.format != BackupFormat.container) {
      return readOwnership(path);
    }
    final extracted = await extract(path);
    try {
      return await readOwnership(p.join(extracted.path, backupDatabaseName));
    } finally {
      await backupDeleteQuietly(extracted);
    }
  }

  Future<StagedBackup> stage(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const BackupException('El archivo no existe.');
    }
    if (await file.length() == 0) {
      throw const BackupException('El archivo está vacío.');
    }
    final header = await backupFirstBytes(file, 8);
    if (BackupEnvelopeHeader.hasMagic(header)) {
      throw const BackupException(
        'Esta copia está cifrada. Se restaura desde «Respaldo en la nube», '
        'con su clave de recuperación.',
      );
    }
    final isContainer = backupLooksLikeZip(header);
    final directory = isContainer
        ? await extract(path)
        : await Directory.systemTemp.createTemp('agro_backup_open_');
    try {
      if (isContainer) {
        final checked = await validateExtracted(directory);
        if (!checked.validation.isValid) {
          throw BackupException(checked.validation.problem!);
        }
        return StagedBackup(
          directory,
          p.join(directory.path, backupDatabaseName),
          checked.validation,
          checked.attachments,
        );
      }
      final copy = p.join(directory.path, backupDatabaseName);
      await file.copy(copy);
      final validation = await validateDatabaseFile(copy);
      if (!validation.isValid) throw BackupException(validation.problem!);
      return StagedBackup(directory, copy, validation, const {});
    } on BackupException {
      await backupDeleteQuietly(directory);
      rethrow;
    } on Exception catch (error) {
      await backupDeleteQuietly(directory);
      throw BackupException('No se pudo leer el archivo de respaldo: $error');
    }
  }
}
