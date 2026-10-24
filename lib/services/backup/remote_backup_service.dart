// Respaldo privado remoto (F08-BKP-04/05, MOB #35/#36): generar, subir,
// listar, descargar, verificar y restaurar, siempre por acción explícita del
// agricultor.
//
// Desde F08-ADR-003 la copia se **cifra en el teléfono** antes de subirla
// (formato 2): el servidor y el proveedor sólo guardan bytes cifrados y no
// tienen la clave. El contenedor legible se genera en la carpeta privada de
// la app, se cifra, se comprueba que se sabe descifrar y se borra; nunca pasa
// por `Descargas`.
//
// Restaurar desde el servidor, en este orden:
//   1. la sesión del mismo titular (el servidor sólo sirve sus copias);
//   2. el tamaño y el SHA-256 de transporte de los bytes cifrados;
//   3. el descifrado con la etiqueta verificada, a un `.part` privado que sólo
//      se renombra tras verificarla;
//   4. la validación interna (manifiesto, base, esquema, fotografías) y la
//      propiedad de la copia;
//   5. la confirmación de la persona;
//   6. el camino local protegido (`GuardedRestore`): exclusión de escrituras,
//      copia previa, WAL/rollback, pausa RESTORE_PAUSED y recálculo de la
//      autorización.
// Si falla cualquiera, los datos vigentes no se tocan. Nada de esto publica
// en Sync.
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../data/backup_encryption.dart';
import '../../data/backup_service.dart';
import '../../domain/installation_access.dart' show OwnerScope;
import '../../domain/restore_ownership.dart';
import '../../guarded_restore.dart';
import '../sync/sync_access.dart';
import 'backup_keyring.dart';
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

/// No hay una clave de recuperación confirmada: antes de depender de la
/// copia cifrada hay que crearla, anotarla fuera del teléfono y confirmarla.
class RecoveryKeyNotConfirmed implements Exception {
  const RecoveryKeyNotConfirmed();

  String get message =>
      'Antes de subir un respaldo cifrado, cree su clave de recuperación, '
      'anótela fuera del teléfono y confírmela. No se subió nada.';

  @override
  String toString() => message;
}

/// La copia necesita una clave de recuperación que este teléfono no tiene.
/// La copia cifrada ya se descargó y comprobó: [pending] permite descifrarla
/// con la clave escrita sin volver a descargarla.
class RecoveryKeyRequired implements Exception {
  const RecoveryKeyRequired(this.pending);
  final PendingDecryption pending;

  String get message =>
      'Esta copia está cifrada con una clave de recuperación que este '
      'teléfono no tiene. Escriba la clave que anotó.';

  @override
  String toString() => message;
}

/// Copia cifrada descargada (SHA-256 de transporte ya verificado), a la espera
/// de la clave de recuperación.
class PendingDecryption {
  const PendingDecryption(this.entry, this.envelope);
  final RemoteBackupEntry entry;

  /// En la carpeta privada de la app; se borra al descifrar o descartar.
  final File envelope;
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

/// Copia descargada, descifrada y verificada, lista para confirmar su
/// restauración.
class PreparedRemoteRestore {
  const PreparedRemoteRestore({
    required this.entry,
    required this.file,
    required this.validation,
    required this.ownership,
    this.containerSha256,
    this.recoveredKey,
  });

  final RemoteBackupEntry entry;

  /// Contenedor legible, en la carpeta privada de la app; se borra al
  /// restaurar o descartar.
  final File file;
  final BackupValidation validation;
  final RestoreOwnershipVerdict ownership;

  /// SHA-256 del contenedor descifrado, para volver a cotejarlo justo antes
  /// de restaurar. Null en una copia sin cifrar (se coteja el de transporte).
  final String? containerSha256;

  /// Clave escrita por la persona para esta copia: se guarda en el llavero
  /// sólo si la restauración termina.
  final BackupRecoveryKey? recoveredKey;

  /// Copia del formato anterior, guardada sin cifrar en el servidor.
  bool get unencrypted => entry.formatVersion == 1;
}

class RemoteBackupService {
  RemoteBackupService({
    required RemoteBackupApi Function() api,
    required Future<VerifiedAccess> Function() access,
    required BackupService backups,
    required GuardedRestore restorer,
    required Future<OwnerScope?> Function() ownerScope,
    required Future<Directory> Function() workDirectory,
    required BackupKeyring keyring,
    BackupEncryption encryption = const BackupEncryption(),
    void Function()? onAccessRejected,
  }) : _onAccessRejected = onAccessRejected,
       _api = api,
       _access = access,
       _backups = backups,
       _restorer = restorer,
       _ownerScope = ownerScope,
       _workDirectory = workDirectory,
       _keyring = keyring,
       _encryption = encryption;

  final RemoteBackupApi Function() _api;
  final Future<VerifiedAccess> Function() _access;
  final BackupService _backups;
  final GuardedRestore _restorer;
  final Future<OwnerScope?> Function() _ownerScope;
  final Future<Directory> Function() _workDirectory;
  final BackupKeyring _keyring;
  final BackupEncryption _encryption;

  /// Formato que sube esta versión: siempre cifrado.
  static const uploadFormatVersion = BackupEnvelopeHeader.formatVersion;

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

  int get _maxContainerBytes => _backups.extractionLimits.maxContainerBytes;

  /// Genera un respaldo nuevo, lo cifra con la clave activa y lo sube. Sólo
  /// la cuenta del titular de esta instalación puede subir sus datos
  /// privados, y sólo con una clave de recuperación ya confirmada.
  Future<RemoteUploadResult> uploadNew() async {
    final access = await _access();
    if (await _ownerScope() != access.scope) {
      throw const RemoteBackupOwnerMismatch();
    }
    final active = await _keyring.activeKey();
    if (active == null) throw const RecoveryKeyNotConfirmed();

    final work = Directory(p.join((await _workDirectory()).path, 'subida'));
    await _clear(work);
    await work.create(recursive: true);
    final envelope = File(p.join(work.path, 'respaldo.agroenc'));
    try {
      final prepared = await _backups.withPrivateContainer((
        container,
        info,
      ) async {
        final validation = await _backups.validate(container.path);
        if (!validation.isValid) throw BackupException(validation.problem!);
        final plainSha = await BackupService.sha256OfFile(container);
        await _encryption.encryptFile(container, envelope, active.key);
        await _checkDecryptable(envelope, active.key, plainSha, work);
        return (info: info, schemaVersion: validation.schemaVersion!);
      });
      final digest = await BackupService.sha256OfFile(envelope);
      final entry = await _upload(
        envelope,
        digest,
        prepared.schemaVersion,
        access,
        prepared.info,
      );
      await _keyring.recordUpload(entry.entry.id, active.keyId);
      return entry;
    } finally {
      // El contenedor legible ya se borró (withPrivateContainer); aquí sólo
      // quedan el cifrado y su comprobación.
      try {
        if (await work.exists()) await work.delete(recursive: true);
      } on FileSystemException {
        // Se limpia al empezar la siguiente subida.
      }
    }
  }

  /// Un respaldo que no se sabe releer no protege: antes de subirlo se
  /// descifra en la carpeta privada y se coteja con el contenedor original.
  Future<void> _checkDecryptable(
    File envelope,
    BackupRecoveryKey key,
    String plainSha,
    Directory work,
  ) async {
    final check = File(p.join(work.path, 'comprobacion.agrobackup'));
    try {
      final decrypted = await _encryption.decryptFile(
        envelope,
        check,
        keyFor: (_) async => key,
        maxPlaintextBytes: _maxContainerBytes,
      );
      if (decrypted == null || decrypted.sha256 != plainSha) {
        throw const BackupException(
          'El respaldo cifrado no se pudo comprobar. No se subió nada.',
        );
      }
    } finally {
      await _deleteQuietly(check);
    }
  }

  Future<RemoteUploadResult> _upload(
    File envelope,
    String digest,
    int schemaVersion,
    VerifiedAccess access,
    BackupExportResult info,
  ) async {
    try {
      final entry = await _call(
        () => _api().upload(
          envelope,
          sha256: digest,
          formatVersion: uploadFormatVersion,
          schemaVersion: schemaVersion,
          accessToken: access.accessToken,
        ),
      );
      return RemoteUploadResult(entry, info);
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
          return RemoteUploadResult(entry, info, confirmedByListing: true);
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

  /// Qué clave necesita cada copia cifrada, según este teléfono.
  Future<Map<String, RemoteCopyKey>> keysFor(
    Iterable<RemoteBackupEntry> entries,
  ) => _keyring.classify([
    for (final entry in entries)
      if (entry.formatVersion == uploadFormatVersion) entry.id,
  ]);

  /// Descarga [entry] (SHA-256 de transporte), la descifra si está cifrada,
  /// valida el contenedor y lee de quién es, sin modificar nada.
  ///
  /// Si la copia está cifrada con una clave que este teléfono no tiene,
  /// lanza [RecoveryKeyRequired]: la persona escribe su clave y se continúa
  /// con [prepareWithRecoveryKey].
  Future<PreparedRemoteRestore> prepareRestore(RemoteBackupEntry entry) async {
    final access = await _access();
    final work = await _workDirectory();
    await _clear(work);
    final file = await _call(
      () => _api().download(entry, work, access.accessToken),
    );
    try {
      final isEnvelope = await BackupEncryption.isEnvelope(file);
      if (entry.formatVersion == uploadFormatVersion) {
        if (!isEnvelope) {
          throw const BackupEnvelopeException(BackupEnvelopeProblem.malformed);
        }
        return await _decryptAndPrepare(
          PendingDecryption(entry, file),
          keyFor: _keyring.keyFor,
        );
      }
      if (entry.formatVersion != 1 || isEnvelope) {
        throw const BackupEnvelopeException(BackupEnvelopeProblem.unsupported);
      }
      // Formato 1, anterior al cifrado: se sigue pudiendo restaurar, y la
      // interfaz avisa de que se guardó sin cifrar.
      return await _prepareContainer(entry, file);
    } on RecoveryKeyRequired {
      rethrow;
    } on Object {
      await _deleteQuietly(file);
      rethrow;
    }
  }

  /// Continúa [prepareRestore] con la clave que escribió la persona. Una
  /// clave equivocada no descifra ni borra la copia descargada: se puede
  /// volver a intentar o descartar.
  Future<PreparedRemoteRestore> prepareWithRecoveryKey(
    PendingDecryption pending,
    String typedKey,
  ) async {
    final key = BackupRecoveryKey.parse(typedKey);
    try {
      return await _decryptAndPrepare(
        pending,
        keyFor: (_) async => key,
        recoveredKey: key,
      );
    } on BackupEnvelopeException catch (error) {
      if (error.problem != BackupEnvelopeProblem.wrongKey) {
        await _deleteQuietly(pending.envelope);
      }
      rethrow;
    }
  }

  Future<void> discardPending(PendingDecryption pending) =>
      _deleteQuietly(pending.envelope);

  Future<PreparedRemoteRestore> _decryptAndPrepare(
    PendingDecryption pending, {
    required Future<BackupRecoveryKey?> Function(List<int> keyId) keyFor,
    BackupRecoveryKey? recoveredKey,
  }) async {
    final target = File(
      p.join(pending.envelope.parent.path, '${pending.entry.id}.descifrado'),
    );
    final decrypted = await _encryption.decryptFile(
      pending.envelope,
      target,
      keyFor: keyFor,
      maxPlaintextBytes: _maxContainerBytes,
    );
    if (decrypted == null) throw RecoveryKeyRequired(pending);
    // Lo cifrado ya no hace falta: lo verificado es el contenedor descifrado.
    await _deleteQuietly(pending.envelope);
    try {
      return await _prepareContainer(
        pending.entry,
        decrypted.file,
        containerSha256: decrypted.sha256,
        recoveredKey: recoveredKey,
      );
    } on Object {
      await _deleteQuietly(decrypted.file);
      rethrow;
    }
  }

  Future<PreparedRemoteRestore> _prepareContainer(
    RemoteBackupEntry entry,
    File file, {
    String? containerSha256,
    BackupRecoveryKey? recoveredKey,
  }) async {
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
      containerSha256: containerSha256,
      recoveredKey: recoveredKey,
    );
  }

  /// Restaura una copia preparada. Vuelve a cotejar justo antes el SHA-256
  /// de lo que se verificó (el del contenedor descifrado o, sin cifrar, el de
  /// transporte); la validación interna, el titular, la pausa de la outbox y
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
      final expected = prepared.containerSha256 ?? prepared.entry.sha256;
      if (await BackupService.sha256OfFile(prepared.file) != expected) {
        throw const RemoteBackupException(RemoteBackupErrorKind.integrity);
      }
      final outcome = await _restorer.restore(prepared.file.path);
      final recovered = prepared.recoveredKey;
      if (recovered != null) {
        // La persona demostró tener la clave fuera del teléfono. Un fallo al
        // guardarla no deshace una restauración que ya terminó: se le
        // volverá a pedir al restaurar otra copia.
        try {
          await _keyring.adoptRecovered(recovered);
        } on Object {
          // Ver arriba.
        }
      }
      return outcome;
    } finally {
      await discard(prepared);
    }
  }

  Future<void> discard(PreparedRemoteRestore prepared) =>
      _deleteQuietly(prepared.file);

  /// Restos de una operación anterior interrumpida (la app se cerró antes de
  /// terminar). La carpeta es privada y sólo la usa esto.
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
