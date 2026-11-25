// Cifrado del respaldo en el teléfono (F08, ADR F08-ADR-003).
//
// El contenedor `.agrobackup` se cifra antes de salir del teléfono con
// ChaCha20-Poly1305 (RFC 8439) y una clave por archivo derivada con
// HKDF-SHA256 de la clave de recuperación del titular. El servidor y el
// proveedor sólo guardan estos bytes: no tienen la clave.
//
// Todo lo criptográfico es de `package:cryptography` (implementación Dart, la
// misma en el host, la CI y Android). Este archivo sólo fija el formato
// exterior, los límites y el orden de las comprobaciones; no implementa
// primitivas.
//
// Nunca registra claves, cabeceras ni contenido: los errores son tipados y
// sus mensajes, presentables.
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart'
    show Mac, SecretBoxAuthenticationError;
import 'package:cryptography/dart.dart' show DartChacha20;

import '../domain/backup_models.dart';
export '../domain/backup_models.dart';

/// Operaciones criptográficas de respaldo local/remoto.
class BackupEncryption {
  const BackupEncryption({Random? random}) : _random = random;

  final Random? _random;

  static const _cipher = DartChacha20.poly1305Aead();

  static const partialSuffix = '.part';

  List<int> _randomBytes(int count) {
    final source = _random ?? Random.secure();
    return List<int>.generate(count, (_) => source.nextInt(256));
  }

  /// ¿Empieza [file] por el magic del formato 2? No lo valida.
  static Future<bool> isEnvelope(File file) async {
    final handle = await file.open();
    try {
      return BackupEnvelopeHeader.hasMagic(
        await handle.read(BackupEnvelopeHeader.magic.length),
      );
    } finally {
      await handle.close();
    }
  }

  /// Lee y comprueba la cabecera de [file]: forma, versión, tamaño exacto y
  /// límite del contenido. No descifra.
  static Future<BackupEnvelopeHeader> readHeader(
    File file, {
    required int maxPlaintextBytes,
  }) async {
    final size = await file.length();
    if (size < BackupEnvelopeHeader.length + BackupEnvelopeHeader.tagLength) {
      throw const BackupEnvelopeException(BackupEnvelopeProblem.malformed);
    }
    final handle = await file.open();
    final List<int> prefix;
    try {
      prefix = await handle.read(BackupEnvelopeHeader.length);
    } finally {
      await handle.close();
    }
    final header = BackupEnvelopeHeader.parse(prefix);
    if (header.plaintextLength > maxPlaintextBytes) {
      throw const BackupEnvelopeException(BackupEnvelopeProblem.tooLarge);
    }
    if (header.envelopeLength != size) {
      throw const BackupEnvelopeException(BackupEnvelopeProblem.malformed);
    }
    return header;
  }

  /// Cifra [plain] en [target]. Escribe primero `target.part` y lo renombra
  /// al terminar; ante cualquier fallo no queda nada en [target].
  Future<void> encryptFile(
    File plain,
    File target,
    BackupRecoveryKey key,
  ) async {
    final header = BackupEnvelopeHeader(
      keyId: await key.keyId(),
      salt: _randomBytes(BackupEnvelopeHeader.saltLength),
      nonce: _randomBytes(BackupEnvelopeHeader.nonceLength),
      plaintextLength: await plain.length(),
    );
    final headerBytes = header.toBytes();
    final fileKey = await key.deriveFileKey(header.salt);
    final partial = File('${target.path}$partialSuffix');
    try {
      final sink = partial.openWrite();
      Mac? mac;
      try {
        sink.add(headerBytes);
        await sink.addStream(
          _cipher.encryptStream(
            plain.openRead(),
            secretKey: fileKey,
            nonce: header.nonce,
            aad: headerBytes,
            onMac: (value) => mac = value,
          ),
        );
        final tag = mac;
        if (tag == null || tag.bytes.length != BackupEnvelopeHeader.tagLength) {
          throw StateError('Cifrado sin etiqueta');
        }
        sink.add(tag.bytes);
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (await partial.length() != header.envelopeLength) {
        throw const BackupEnvelopeException(BackupEnvelopeProblem.localStorage);
      }
      if (await target.exists()) await target.delete();
      await partial.rename(target.path);
    } on FileSystemException {
      await _deleteQuietly(partial);
      throw const BackupEnvelopeException(BackupEnvelopeProblem.localStorage);
    } on Object {
      await _deleteQuietly(partial);
      rethrow;
    }
  }

  /// Descifra [envelope] en [target] con la clave de [keyFor], elegida por el
  /// identificador de la cabecera. Si [keyFor] no tiene la clave, devuelve
  /// null antes de escribir nada (hay que pedir la clave de recuperación).
  ///
  /// Escribe en `target.part` y **sólo renombra tras verificar la etiqueta**:
  /// lo descifrado antes de esa verificación no se usa nunca y se borra si
  /// falla. Ante cualquier error no queda nada en [target].
  Future<DecryptedBackup?> decryptFile(
    File envelope,
    File target, {
    required Future<BackupRecoveryKey?> Function(List<int> keyId) keyFor,
    required int maxPlaintextBytes,
  }) async {
    final header = await readHeader(
      envelope,
      maxPlaintextBytes: maxPlaintextBytes,
    );
    final key = await keyFor(header.keyId);
    if (key == null) return null;
    if (!_equal(await key.keyId(), header.keyId)) {
      throw const BackupEnvelopeException(BackupEnvelopeProblem.wrongKey);
    }
    final headerBytes = header.raw ?? header.toBytes();
    final fileKey = await key.deriveFileKey(header.salt);
    final tagOffset = BackupEnvelopeHeader.length + header.plaintextLength;
    final tagHandle = await envelope.open();
    final List<int> tag;
    try {
      await tagHandle.setPosition(tagOffset);
      tag = await tagHandle.read(BackupEnvelopeHeader.tagLength);
    } finally {
      await tagHandle.close();
    }

    final partial = File('${target.path}$partialSuffix');
    final digest = _DigestSink();
    final hasher = hashes.sha256.startChunkedConversion(digest);
    var written = 0;
    try {
      final sink = partial.openWrite();
      try {
        await for (final chunk in _cipher.decryptStream(
          envelope.openRead(BackupEnvelopeHeader.length, tagOffset),
          secretKey: fileKey,
          nonce: header.nonce,
          mac: Mac(tag),
          aad: headerBytes,
        )) {
          written += chunk.length;
          if (written > header.plaintextLength) {
            throw const BackupEnvelopeException(
              BackupEnvelopeProblem.malformed,
            );
          }
          hasher.add(chunk);
          sink.add(chunk);
        }
        hasher.close();
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (written != header.plaintextLength) {
        throw const BackupEnvelopeException(BackupEnvelopeProblem.malformed);
      }
      if (await target.exists()) await target.delete();
      await partial.rename(target.path);
      return DecryptedBackup(target, '${digest.value}');
    } on SecretBoxAuthenticationError {
      await _deleteQuietly(partial);
      throw const BackupEnvelopeException(
        BackupEnvelopeProblem.authenticationFailed,
      );
    } on FileSystemException {
      await _deleteQuietly(partial);
      throw const BackupEnvelopeException(BackupEnvelopeProblem.localStorage);
    } on Object {
      await _deleteQuietly(partial);
      rethrow;
    }
  }

  static bool _equal(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Limpieza de la carpeta privada: no cambia el resultado.
    }
  }
}

class _DigestSink implements Sink<hashes.Digest> {
  hashes.Digest? value;
  @override
  void add(hashes.Digest data) => value = data;
  @override
  void close() {}
}
