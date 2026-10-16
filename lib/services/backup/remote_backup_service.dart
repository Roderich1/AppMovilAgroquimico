// Respaldo privado remoto (F08-BKP-04/05, MOB #35/#36): generar, subir,
// listar, descargar, verificar y restaurar, siempre por acción explícita del
// agricultor.
//
// Restaurar desde el servidor reutiliza el camino local protegido
// (`GuardedRestore`): exclusión de escrituras, comprobación del titular de la
// copia, pausa RESTORE_PAUSED de la outbox restaurada y recálculo de la
// autorización. Antes de llegar ahí la copia descargada pasa dos controles:
// el SHA-256 exterior que registró el servidor y la validación interna del
// contenedor (manifiesto, SHA-256 de la base y de cada fotografía). Si falla
// cualquiera, los datos vigentes no se tocan. Nada de esto publica en Sync.
import 'dart:io';

import '../../data/backup_service.dart';
import '../../domain/installation_access.dart' show OwnerScope;
import '../../domain/restore_ownership.dart';
import '../../guarded_restore.dart';
import '../sync/sync_access.dart';
import 'remote_backup_api.dart';

/// La cuenta en sesión no es la del titular de esta instalación.
class RemoteBackupOwnerMismatch implements Exception {
  const RemoteBackupOwnerMismatch();

  String get message =>
      'La cuenta en sesión no es la del titular de esta instalación. No se '
      'subió nada.';

  @override
  String toString() => message;
}

class RemoteUploadResult {
  const RemoteUploadResult(
    this.entry,
    this.export, {
    this.confirmedByListing = false,
  });
  final RemoteBackupEntry entry;
  final BackupExportResult export;

  /// La respuesta de la subida no llegó, pero la lista del servidor ya tenía
  /// una copia con el mismo SHA-256: se da por subida sin repetir el envío.
  final bool confirmedByListing;
}

/// Copia descargada y verificada, lista para confirmar su restauración.
class PreparedRemoteRestore {
  const PreparedRemoteRestore({
    required this.entry,
    required this.file,
    required this.validation,
    required this.ownership,
  });

  final RemoteBackupEntry entry;

  /// En la carpeta privada de la app; se borra al restaurar o descartar.
  final File file;
  final BackupValidation validation;
  final RestoreOwnershipVerdict ownership;
}

class RemoteBackupService {
  RemoteBackupService({
    required RemoteBackupApi Function() api,
    required Future<VerifiedAccess> Function() access,
    required BackupService backups,
    required GuardedRestore restorer,
    required Future<OwnerScope?> Function() ownerScope,
    required Future<Directory> Function() workDirectory,
    void Function()? onAccessRejected,
  }) : _onAccessRejected = onAccessRejected,
       _api = api,
       _access = access,
       _backups = backups,
       _restorer = restorer,
       _ownerScope = ownerScope,
       _workDirectory = workDirectory;

  final RemoteBackupApi Function() _api;
  final Future<VerifiedAccess> Function() _access;
  final BackupService _backups;
  final GuardedRestore _restorer;
  final Future<OwnerScope?> Function() _ownerScope;
  final Future<Directory> Function() _workDirectory;

  /// Ante un 401/403 se descarta el acceso en memoria (como hace Sync): la
  /// siguiente acción vuelve a verificarlo en línea.
  final void Function()? _onAccessRejected;

  Future<T> _call<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on RemoteBackupException catch (error) {
      if (error.kind == RemoteBackupErrorKind.authRequired ||
          error.kind == RemoteBackupErrorKind.forbidden) {
        _onAccessRejected?.call();
      }
      rethrow;
    }
  }

  Future<List<RemoteBackupEntry>> list() async {
    final token = (await _access()).accessToken;
    return _call(() => _api().list(token));
  }

  /// Genera un respaldo local nuevo y lo sube. Sólo la cuenta del titular de
  /// esta instalación puede subir sus datos privados.
  Future<RemoteUploadResult> uploadNew() async {
    final access = await _access();
    if (await _ownerScope() != access.scope) {
      throw const RemoteBackupOwnerMismatch();
    }
    final exported = await _backups.export();
    final file = File(exported.path);
    final validation = await _backups.validate(file.path);
    if (!validation.isValid) throw BackupException(validation.problem!);
    final digest = await BackupService.sha256OfFile(file);
    try {
      final entry = await _call(
        () => _api().upload(
          file,
          sha256: digest,
          formatVersion: BackupService.backupFormatVersion,
          schemaVersion: validation.schemaVersion!,
          accessToken: access.accessToken,
        ),
      );
      return RemoteUploadResult(entry, exported);
    } on RemoteBackupException catch (error) {
      if (!error.outcomeUncertain) rethrow;
      // Sin respuesta fiable: el servidor pudo completarla. Antes de que el
      // agricultor reintente (y genere otra copia), se comprueba la lista.
      final List<RemoteBackupEntry> remote;
      try {
        remote = await _call(() => _api().list(access.accessToken));
      } on RemoteBackupException {
        throw error;
      }
      for (final entry in remote) {
        if (entry.sha256 == digest) {
          return RemoteUploadResult(entry, exported, confirmedByListing: true);
        }
      }
      rethrow;
    }
  }

  /// Elimina la copia remota. Los respaldos locales no cambian.
  Future<void> delete(RemoteBackupEntry entry) async {
    final token = (await _access()).accessToken;
    await _call(() => _api().delete(entry.id, token));
  }

  /// Descarga [entry] (SHA-256 exterior), valida el contenedor y lee de quién
  /// es, sin modificar nada.
  Future<PreparedRemoteRestore> prepareRestore(RemoteBackupEntry entry) async {
    final access = await _access();
    final work = await _workDirectory();
    await _clear(work);
    final file = await _call(
      () => _api().download(entry, work, access.accessToken),
    );
    try {
      final validation = await _backups.validate(file.path);
      if (!validation.isValid) throw BackupException(validation.problem!);
      if (validation.format != BackupFormat.container) {
        // El servicio sólo guarda contenedores generados por la app.
        throw const BackupException(
          'La copia del servidor no es un contenedor de respaldo de la app.',
        );
      }
      return PreparedRemoteRestore(
        entry: entry,
        file: file,
        validation: validation,
        ownership: await _restorer.preview(file.path),
      );
    } on Object {
      await _deleteQuietly(file);
      rethrow;
    }
  }

  /// Restaura una copia preparada. Vuelve a comprobar el SHA-256 exterior
  /// justo antes; la validación interna, el titular, la pausa de la outbox y
  /// el recálculo de la autorización los hace `GuardedRestore`.
  Future<GuardedRestoreOutcome> restorePrepared(
    PreparedRemoteRestore prepared,
  ) async {
    try {
      if (!prepared.ownership.accepted) {
        throw BackupOwnershipRejectedException(
          prepared.ownership.message,
          prepared.ownership.rejection!,
        );
      }
      if (await BackupService.sha256OfFile(prepared.file) !=
          prepared.entry.sha256) {
        throw const RemoteBackupException(RemoteBackupErrorKind.integrity);
      }
      return await _restorer.restore(prepared.file.path);
    } finally {
      await discard(prepared);
    }
  }

  Future<void> discard(PreparedRemoteRestore prepared) =>
      _deleteQuietly(prepared.file);

  /// Restos de una preparación anterior interrumpida (la app se cerró antes
  /// de restaurar o descartar). La carpeta es privada y sólo la usa esto.
  static Future<void> _clear(Directory work) async {
    if (!await work.exists()) return;
    await for (final entity in work.list()) {
      if (entity is File) await _deleteQuietly(entity);
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Limpieza de la carpeta privada: no cambia el resultado.
    }
  }
}
