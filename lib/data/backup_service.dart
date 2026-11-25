import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' show Database;

import '../domain/restore_ownership.dart';
import 'app_database.dart';
import 'backup/backup_exporter.dart';
import 'backup/backup_models.dart';
import 'backup/backup_restorer.dart';
import 'backup/backup_validator.dart';
import 'backup_container_reader.dart';
import 'invoice_storage.dart';
import 'restore_safety_copies.dart';

export '../domain/restore_ownership.dart'
    show BackupOwnership, RestoreRejection;
export 'backup/backup_models.dart'
    show
        BackupException,
        BackupExportResult,
        BackupFormat,
        BackupOwnershipException,
        BackupOwnershipRejectedException,
        BackupRestoreResult,
        BackupValidation,
        RecoveryCheckFailure,
        RestoreRecoveryUnverifiedException;
export 'backup_container_reader.dart' show BackupExtractionLimits;
export 'restore_safety_copies.dart'
    show RestoreBlockedException, RestoreSafetyCopies;

/// Fachada de exportación, validación y restauración del respaldo local.
class BackupService {
  BackupService(
    this.appDatabase, {
    Future<Directory> Function()? invoicesDir,
    Future<Directory> Function()? exportDirectory,
    @visibleForTesting Future<void> Function(File partial)? beforePublish,
    @visibleForTesting Future<void> Function(File partial)? afterSafetyCopy,
    @visibleForTesting Future<void> Function()? afterCheckpoint,
    @visibleForTesting Future<void> Function()? beforeRecoveryCheck,
    this.extractionLimits = BackupExtractionLimits.standard,
    RestoreSafetyCopies? safetyCopies,
  }) {
    final resolvedInvoicesDir = invoicesDir ?? resolveInvoicesDirectory;
    final resolvedExportDir = exportDirectory ?? _defaultExportDirectory;
    this.safetyCopies =
        safetyCopies ?? RestoreSafetyCopies(appDatabase.resolvePath);
    _validator = BackupValidator(
      appDatabase: appDatabase,
      containerReader: BackupContainerReader(extractionLimits),
    );
    _exporter = BackupExporter(
      appDatabase: appDatabase,
      validator: _validator,
      invoicesDir: resolvedInvoicesDir,
      exportDirectory: resolvedExportDir,
      beforePublish: beforePublish,
    );
    _restorer = BackupRestorer(
      appDatabase: appDatabase,
      validator: _validator,
      safetyCopies: this.safetyCopies,
      invoicesDir: resolvedInvoicesDir,
      afterSafetyCopy: afterSafetyCopy,
      afterCheckpoint: afterCheckpoint,
      beforeRecoveryCheck: beforeRecoveryCheck,
    );
  }

  final AppDatabase appDatabase;
  final BackupExtractionLimits extractionLimits;
  late final RestoreSafetyCopies safetyCopies;

  late final BackupValidator _validator;
  late final BackupExporter _exporter;
  late final BackupRestorer _restorer;

  static Future<Directory> _defaultExportDirectory() async =>
      await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();

  static Future<String> sha256OfFile(File file) => backupSha256OfFile(file);

  static const int backupFormatVersion = backupFormatVersionConst;
  static const String appVersion = backupAppVersionConst;
  static const List<String> requiredTables = backupRequiredTablesConst;
  static const String containerExtension = backupContainerExtensionConst;
  static const String partialSuffix = backupPartialSuffixConst;

  Future<BackupExportResult> export() => _exporter.export();

  Future<T> withPrivateContainer<T>(
    Future<T> Function(File container, BackupExportResult info) use,
  ) => _exporter.withPrivateContainer(use);

  Future<List<File>> listAvailableBackups() => _exporter.listAvailableBackups();

  Future<BackupValidation> validate(String path) => _validator.validate(path);

  Future<BackupOwnership> readOwnership(String databasePath) =>
      _validator.readOwnership(databasePath);

  Future<BackupOwnership> inspectOwnership(String path) =>
      _validator.inspectOwnership(path);

  Future<BackupRestoreResult> restore(
    String path, {
    Future<void> Function(BackupOwnership ownership)? verifyOwnership,
    Future<void> Function(Database restored)? prepareRestored,
    Future<void> Function()? afterReplace,
  }) => _restorer.restore(
    path,
    verifyOwnership: verifyOwnership,
    prepareRestored: prepareRestored,
    afterReplace: afterReplace,
  );
}
