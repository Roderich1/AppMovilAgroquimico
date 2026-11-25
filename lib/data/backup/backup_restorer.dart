import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals, mapEquals;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' show Database, Sqflite;

import '../../domain/restore_ownership.dart';
import '../app_database.dart';
import '../app_log.dart';
import '../restore_safety_copies.dart';
import 'backup_models.dart';
import 'backup_validator.dart';

class BackupRestorer {
  const BackupRestorer({
    required this.appDatabase,
    required this.validator,
    required this.safetyCopies,
    required this.invoicesDir,
    this.afterSafetyCopy,
    this.afterCheckpoint,
    this.beforeRecoveryCheck,
  });

  final AppDatabase appDatabase;
  final BackupValidator validator;
  final RestoreSafetyCopies safetyCopies;
  final Future<Directory> Function() invoicesDir;
  final Future<void> Function(File partial)? afterSafetyCopy;
  final Future<void> Function()? afterCheckpoint;
  final Future<void> Function()? beforeRecoveryCheck;

  static const _journalMagic = [0xd9, 0xd5, 0x05, 0xf9, 0x20, 0xa1, 0x63, 0xd7];

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

    await safetyCopies.ensureCanStartRestore();

    final staged = await validator.stage(path);
    final validation = staged.validation;
    final databaseSource = staged.databasePath;
    final isContainer = validation.format == BackupFormat.container;

    try {
      final ownership = await validator.readOwnership(databaseSource);
      if (verifyOwnership != null) await verifyOwnership(ownership);
    } on Object {
      await backupDeleteQuietly(staged.directory);
      rethrow;
    }

    final invoicesDirectory = isContainer ? await invoicesDir() : null;

    final SafetyCopySlot slot;
    try {
      slot = await safetyCopies.begin();
    } on Object {
      await backupDeleteQuietly(staged.directory);
      rethrow;
    }
    final safetyCopy = slot.databasePath;
    final invoicesBackup = invoicesDirectory == null
        ? null
        : Directory(slot.invoicesPath);

    final String? previousDigest;
    final String? previousJournal;
    final Map<String, int>? previousInvoices;
    final bool hadInvoices;
    try {
      await Directory(p.dirname(safetyCopy)).create(recursive: true);
      previousDigest = await _secureCurrentDatabase(target, safetyCopy);
      previousJournal = await _pendingJournal(target);
      previousInvoices = invoicesDirectory == null
          ? null
          : await _listing(invoicesDirectory);
      hadInvoices =
          invoicesBackup != null &&
          await _copyDirectory(invoicesDirectory!, invoicesBackup);
    } on Object {
      await backupDeleteQuietly(File('$safetyCopy$backupPartialSuffixConst'));
      try {
        await safetyCopies.discard(slot);
      } on Object {
        // Queda protegida como en preparación/interrumpida.
      }
      await backupDeleteQuietly(staged.directory);
      rethrow;
    }
    final hadPrevious = previousDigest != null;

    var keepInvoicesBackup = false;
    try {
      await File(databaseSource).copy(target);
      for (final suffix in const ['-wal', '-shm']) {
        final journal = File('$target$suffix');
        if (await journal.exists()) await journal.delete();
      }

      var restoredAttachments = 0;
      final restoredNames = <String>{};
      if (isContainer) {
        await invoicesDirectory!.create(recursive: true);
        for (final name in staged.attachments) {
          await File(p.join(staged.directory.path, backupInvoicesFolder, name))
              .copy(p.join(invoicesDirectory.path, name));
          restoredNames.add(name);
          restoredAttachments++;
        }
      }

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

      await AppDatabase.discardEstimationCopies(restored);
      await AppDatabase.discardVoiceEvidence(restored);
      if (prepareRestored != null) await prepareRestored(restored);
      if (afterReplace != null) await afterReplace();
      await _verifyRestoredState(restored);

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
    } on Object catch (error, stack) {
      try {
        await appDatabase.close();
        for (final suffix in const ['-wal', '-shm']) {
          await backupDeleteQuietly(File('$target$suffix'));
        }
        if (hadPrevious) {
          await File(safetyCopy).copy(target);
        } else {
          await backupDeleteQuietly(File(target));
        }
        if (hadInvoices) {
          await backupDeleteQuietly(invoicesDirectory);
          await _copyDirectory(invoicesBackup, invoicesDirectory);
        }
      } on Object {
        keepInvoicesBackup = true;
        try {
          await safetyCopies.markInterrupted(slot);
        } on Object {
          // Protegida igualmente.
        }
        rethrow;
      }
      final failure = await _checkRecoveredState(
        target,
        previousDigest: previousDigest,
        previousJournal: previousJournal,
        invoicesDirectory: invoicesDirectory,
        invoicesBackup: invoicesBackup,
        previousInvoices: previousInvoices,
      );
      if (failure != null) {
        keepInvoicesBackup = true;
        AppLog.error(
          'Restauración deshecha sin estado recuperado comprobado '
          '(${failure.name}); causa: ${error.runtimeType}',
          stackTrace: stack,
        );
        try {
          await safetyCopies.markInterrupted(slot);
        } on Object {
          // Protegida igualmente.
        }
        throw RestoreRecoveryUnverifiedException(
          failure,
          error,
          stack,
          keptCopy: hadPrevious || hadInvoices,
        );
      }
      await _resolveSafetyCopy(
        slot,
        hadPrevious: hadPrevious,
        resolve: safetyCopies.markRolledBack,
      );
      rethrow;
    } finally {
      await backupDeleteQuietly(staged.directory);
      if (invoicesBackup != null && !keepInvoicesBackup) {
        await backupDeleteQuietly(invoicesBackup);
      }
    }
  }

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
    if (!backupRequiredTablesConst.every(tables.contains)) throw problem;
  }

  Future<RecoveryCheckFailure?> _checkRecoveredState(
    String target, {
    required String? previousDigest,
    required String? previousJournal,
    required Directory? invoicesDirectory,
    required Directory? invoicesBackup,
    required Map<String, int>? previousInvoices,
  }) async {
    try {
      if (beforeRecoveryCheck != null) await beforeRecoveryCheck!();
      final wal = File('$target-wal');
      if (await wal.exists() && await wal.length() > 0) {
        return RecoveryCheckFailure.mismatch;
      }
      if (await wal.exists() || await File('$target-shm').exists()) {
        return RecoveryCheckFailure.inconclusive;
      }
      if (await _pendingJournal(target) != previousJournal) {
        return RecoveryCheckFailure.mismatch;
      }
      final active = File(target);
      if (previousDigest == null) {
        if (await active.exists()) return RecoveryCheckFailure.mismatch;
      } else if (!await active.exists() ||
          await backupSha256OfFile(active) != previousDigest) {
        return RecoveryCheckFailure.mismatch;
      }
      if (invoicesDirectory != null) {
        final recovered = await _listing(invoicesDirectory);
        if (previousInvoices == null) {
          if (recovered != null) return RecoveryCheckFailure.mismatch;
        } else {
          final copy = await _listing(invoicesBackup!);
          if (copy == null || !mapEquals(copy, previousInvoices)) {
            return RecoveryCheckFailure.inconclusive;
          }
          if (recovered == null ||
              !mapEquals(recovered, previousInvoices) ||
              !mapEquals(
                await _fingerprint(invoicesDirectory),
                await _fingerprint(invoicesBackup),
              )) {
            return RecoveryCheckFailure.mismatch;
          }
        }
      }
      return null;
    } on Object {
      return RecoveryCheckFailure.inconclusive;
    }
  }

  Future<String?> _pendingJournal(String target) async {
    final journal = File('$target-journal');
    if (!await journal.exists()) return null;
    final header = await backupFirstBytes(journal, _journalMagic.length);
    if (!listEquals(header, _journalMagic)) return null;
    return backupSha256OfFile(journal);
  }

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
      // Mantiene protegida la entrada si falla el marcado final.
    }
  }

  Future<String?> _secureCurrentDatabase(
    String target,
    String safetyCopy,
  ) async {
    final current = File(target);
    if (!await current.exists()) {
      await appDatabase.close();
      return null;
    }
    await consolidateDatabaseForCopy(await appDatabase.database);
    if (afterCheckpoint != null) await afterCheckpoint!();
    await appDatabase.close();

    final wal = File('$target-wal');
    if (await wal.exists() && await wal.length() > 0) {
      throw const BackupException(
        'No se pudo cerrar la base de forma consistente antes de restaurar. '
        'No se restauró; sus datos actuales se conservan.',
      );
    }

    final partial = File('$safetyCopy$backupPartialSuffixConst');
    await current.copy(partial.path);
    final handle = await partial.open(mode: FileMode.append);
    try {
      await handle.flush();
    } finally {
      await handle.close();
    }
    if (afterSafetyCopy != null) await afterSafetyCopy!(partial);
    final digest = await backupSha256OfFile(current);
    if (await partial.length() != await current.length() ||
        await backupSha256OfFile(partial) != digest) {
      throw const BackupException(
        'No se pudo guardar una copia completa de sus datos actuales. No se '
        'restauró; sus datos actuales se conservan.',
      );
    }
    await partial.rename(safetyCopy);
    return digest;
  }

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
    if (await hasDraftInvoicesColumn(database)) {
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

  Future<Map<String, int>?> _listing(Directory directory) async {
    if (!await directory.exists()) return null;
    final files = <String, int>{};
    await for (final entity in directory.list()) {
      if (entity is File) {
        files[p.basename(entity.path)] = await entity.length();
      }
    }
    return files;
  }

  Future<Map<String, String>> _fingerprint(Directory directory) async {
    final files = <String, String>{};
    if (!await directory.exists()) return files;
    await for (final entity in directory.list()) {
      if (entity is File) {
        files[p.basename(entity.path)] = await backupSha256OfFile(entity);
      }
    }
    return files;
  }

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
}
