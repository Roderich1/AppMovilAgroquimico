import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart' show Database;

import '../../domain/restore_ownership.dart';

const int backupFormatVersionConst = 1;
const String backupAppVersionConst = '1.0.0';

const List<String> backupRequiredTablesConst = <String>[
  'persons',
  'products',
  'campaigns',
  'purchases',
  'inventory_lots',
  'inventory_movements',
  'account_transactions',
];

const String backupFileNamePrefix = 'agroquimicos_backup_';
const String backupContainerExtensionConst = '.agrobackup';
const String backupPartialSuffixConst = '.part';
const String backupManifestName = 'manifest.json';
const String backupDatabaseName = 'database.db';
const String backupInvoicesFolder = 'invoices';

final RegExp backupSha256Hex = RegExp(r'^[0-9a-f]{64}$');

Future<String> backupSha256OfFile(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

bool backupLooksLikeZip(List<int> header) =>
    header.length >= 2 && header[0] == 0x50 && header[1] == 0x4B;

Future<List<int>> backupFirstBytes(File file, int count) async {
  final handle = await file.open();
  try {
    return await handle.read(count);
  } finally {
    await handle.close();
  }
}

Future<void> backupDeleteQuietly(FileSystemEntity? entity) async {
  if (entity == null) return;
  try {
    if (await entity.exists()) await entity.delete(recursive: true);
  } on FileSystemException {
    // Limpieza temporal: no convierte en fallo la operación.
  }
}

Future<void> consolidateDatabaseForCopy(Database database) async {
  final modeRows = await database.rawQuery('PRAGMA journal_mode');
  final mode = modeRows.isEmpty
      ? ''
      : '${modeRows.first.values.first}'.toLowerCase();

  if (mode != 'wal') return;

  final result = await database.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
  final busy = result.isEmpty ? 1 : (result.first['busy'] as int? ?? 1);
  if (busy != 0) {
    throw const BackupException(
      'No se pudo consolidar la base antes de copiarla porque está en uso. '
      'Cierre los diálogos abiertos y vuelva a intentarlo.',
    );
  }
}

Future<bool> hasDraftInvoicesColumn(Database database) async =>
    (await database.rawQuery(
      "SELECT 1 FROM pragma_table_info('late_operation_drafts') "
      "WHERE name = 'invoice_image_path'",
    )).isNotEmpty;

/// Formato de un archivo de respaldo.
enum BackupFormat {
  /// Contenedor `.agrobackup`: manifiesto + base + fotografías de factura.
  container,

  /// Copia suelta de la base, tal como exportaban las versiones anteriores.
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
  final String? problem;
  final int? schemaVersion;
  final BackupFormat format;
  final int attachmentCount;
  final DateTime? createdAt;

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

  final String safetyCopyPath;
  final BackupFormat format;
  final int restoredAttachments;
  final List<String> warnings;
}

class StagedBackup {
  const StagedBackup(
    this.directory,
    this.databasePath,
    this.validation,
    this.attachments,
  );

  final Directory directory;
  final String databasePath;
  final BackupValidation validation;
  final Set<String> attachments;
}

/// Error de negocio de la exportación o restauración, con mensaje presentable.
class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Por qué no se pudo dar por recuperado el estado tras un rollback.
enum RecoveryCheckFailure { mismatch, inconclusive }

class RestoreRecoveryUnverifiedException extends BackupException {
  const RestoreRecoveryUnverifiedException(
    this.reason,
    this.cause,
    this.causeStack, {
    required bool keptCopy,
  }) : super(
         keptCopy
             ? 'No pudimos confirmar que sus datos anteriores se recuperaron '
                   'correctamente. Conservamos la copia de seguridad. Antes de '
                   'restaurar otro respaldo, elija qué hacer en «Copias '
                   'previas a restauraciones».'
             : 'No pudimos confirmar que sus datos anteriores se recuperaron '
                   'correctamente. Antes de restaurar otro respaldo, elija qué '
                   'hacer en «Copias previas a restauraciones».',
       );

  final RecoveryCheckFailure reason;
  final Object cause;
  final StackTrace causeStack;
}

class BackupOwnershipException extends BackupException {
  const BackupOwnershipException([
    super.message =
        'No se pudo comprobar el titular de esta copia. No se restauró; sus '
        'datos actuales se conservan.',
  ]);
}

class BackupOwnershipRejectedException extends BackupException {
  const BackupOwnershipRejectedException(super.message, this.rejection);
  final RestoreRejection rejection;
}
