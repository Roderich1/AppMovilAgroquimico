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
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart'
    show Mac, SecretBoxAuthenticationError, SecretKeyData;
import 'package:cryptography/dart.dart'
    show DartChacha20, DartHkdf, DartHmac, DartSha256;

/// Clave de recuperación del respaldo: 32 bytes aleatorios del titular.
///
/// No se deriva del PIN ni de la contraseña y no se relaciona con ellos. Se
/// presenta una sola vez para anotarla fuera del teléfono ([displayText]) y
/// se lee con [parse], que detecta errores de escritura antes de descifrar.
///
/// [toString] nunca muestra el secreto.
class BackupRecoveryKey {
  BackupRecoveryKey._(List<int> bytes)
    : _bytes = Uint8List.fromList(bytes),
      assert(bytes.length == keyLength);

  /// Clave nueva del generador criptográfico del sistema.
  factory BackupRecoveryKey.generate([Random? random]) {
    final source = random ?? Random.secure();
    return BackupRecoveryKey._(
      List<int>.generate(keyLength, (_) => source.nextInt(256)),
    );
  }

  /// Sólo para el llavero local: bytes ya guardados en el almacén seguro.
  factory BackupRecoveryKey.fromStoredBytes(List<int> bytes) {
    if (bytes.length != keyLength) {
      throw const RecoveryKeyFormatException(RecoveryKeyProblem.malformed);
    }
    return BackupRecoveryKey._(bytes);
  }

  static const keyLength = 32;
  static const _version = 0x01;
  static const _checksumLength = 2;

  /// Base32 de Crockford: sin I, L, O ni U, que se confunden al copiar.
  static const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  final Uint8List _bytes;

  /// Bytes de la clave, para guardarla en el almacén seguro. No salen de
  /// este archivo y del llavero.
  List<int> get storedBytes => List<int>.unmodifiable(_bytes);

  static List<int> _checksum(List<int> key) => hashes.sha256
      .convert([...utf8.encode('agrocuentas/recovery-key/v1'), ...key])
      .bytes
      .sublist(0, _checksumLength);

  /// 56 caracteres en 14 grupos de 4, p. ej. `1A2B-3C4D-…`.
  String get displayText {
    final payload = [_version, ..._bytes, ..._checksum(_bytes)];
    final text = StringBuffer();
    var buffer = 0;
    var bits = 0;
    for (final byte in payload) {
      buffer = (buffer << 8) | byte;
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        text.write(_alphabet[(buffer >> bits) & 0x1f]);
      }
      buffer &= (1 << bits) - 1;
    }
    if (bits > 0) text.write(_alphabet[(buffer << (5 - bits)) & 0x1f]);
    final raw = text.toString();
    return [for (var i = 0; i < raw.length; i += 4) raw.substring(i, i + 4)]
        .join('-');
  }

  /// Lee una clave escrita a mano: admite minúsculas, espacios y guiones, y
  /// trata `O` como `0` e `I`/`L` como `1`.
  static BackupRecoveryKey parse(String text) {
    final cleaned = text
        .toUpperCase()
        .replaceAll(RegExp(r'[\s\-]'), '')
        .replaceAll('O', '0')
        .replaceAll(RegExp('[IL]'), '1');
    // 35 bytes = 280 bits = 56 caracteres exactos.
    if (cleaned.length != 56) {
      throw const RecoveryKeyFormatException(RecoveryKeyProblem.malformed);
    }
    final bytes = <int>[];
    var buffer = 0;
    var bits = 0;
    for (final char in cleaned.split('')) {
      final value = _alphabet.indexOf(char);
      if (value < 0) {
        throw const RecoveryKeyFormatException(RecoveryKeyProblem.malformed);
      }
      buffer = (buffer << 5) | value;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        bytes.add((buffer >> bits) & 0xff);
        buffer &= (1 << bits) - 1;
      }
    }
    if (bytes.length != 1 + keyLength + _checksumLength) {
      throw const RecoveryKeyFormatException(RecoveryKeyProblem.malformed);
    }
    if (bytes.first != _version) {
      throw const RecoveryKeyFormatException(RecoveryKeyProblem.version);
    }
    final key = bytes.sublist(1, 1 + keyLength);
    final checksum = bytes.sublist(1 + keyLength);
    final expected = _checksum(key);
    if (checksum[0] != expected[0] || checksum[1] != expected[1]) {
      throw const RecoveryKeyFormatException(RecoveryKeyProblem.checksum);
    }
    return BackupRecoveryKey._(key);
  }

  /// Identificador no secreto: HKDF de la clave con su propio `info`. Va en
  /// la cabecera de cada copia para elegir la clave y detectar una clave
  /// equivocada sin descifrar.
  Future<List<int>> keyId() async {
    final derived =
        await const DartHkdf(
          hmac: DartHmac(DartSha256()),
          outputLength: BackupEnvelopeHeader.keyIdLength,
        ).deriveKey(
          secretKey: SecretKeyData(_bytes),
          info: utf8.encode('agrocuentas/backup/key-id/v1'),
        );
    return derived.bytes;
  }

  Future<SecretKeyData> _fileKey(List<int> salt) =>
      const DartHkdf(hmac: DartHmac(DartSha256()), outputLength: 32).deriveKey(
        secretKey: SecretKeyData(_bytes),
        nonce: salt,
        info: utf8.encode('agrocuentas/backup/file-key/v1'),
      );

  /// Igualdad en tiempo constante.
  bool sameAs(BackupRecoveryKey other) {
    var diff = 0;
    for (var i = 0; i < keyLength; i++) {
      diff |= _bytes[i] ^ other._bytes[i];
    }
    return diff == 0;
  }

  @override
  String toString() => 'BackupRecoveryKey(redacted)';
}

enum RecoveryKeyProblem {
  /// Longitud o caracteres que no corresponden a una clave.
  malformed,

  /// La suma de comprobación no coincide: hay un error de escritura.
  checksum,

  /// Clave de una versión que esta aplicación no conoce.
  version,
}

class RecoveryKeyFormatException implements Exception {
  const RecoveryKeyFormatException(this.problem);
  final RecoveryKeyProblem problem;

  String get message => switch (problem) {
    RecoveryKeyProblem.malformed =>
      'La clave debe tener 56 caracteres (14 grupos de 4). Revise lo que '
          'escribió.',
    RecoveryKeyProblem.checksum =>
      'La clave tiene un error de escritura: algún carácter no coincide con '
          'lo anotado. Revísela grupo por grupo.',
    RecoveryKeyProblem.version =>
      'Esta clave es de una versión más reciente de la aplicación.',
  };

  @override
  String toString() => message;
}

/// Cabecera exterior del formato 2 (ADR §4). Es el AAD del cifrado: cambiar
/// cualquier campo invalida la etiqueta.
class BackupEnvelopeHeader {
  const BackupEnvelopeHeader({
    required this.keyId,
    required this.salt,
    required this.nonce,
    required this.plaintextLength,
    this.raw,
  });

  static const magic = [0x41, 0x47, 0x52, 0x4f, 0x45, 0x4e, 0x43, 0x00];
  static const formatVersion = 2;
  static const algorithmChacha20Poly1305Hkdf = 1;
  static const length = 80;
  static const tagLength = 16;
  static const keyIdLength = 16;
  static const saltLength = 32;
  static const nonceLength = 12;

  final List<int> keyId;
  final List<int> salt;
  final List<int> nonce;
  final int plaintextLength;

  /// Los 80 bytes tal como se leyeron del archivo; null en una cabecera
  /// construida para cifrar. Al descifrar, el AAD son estos bytes, no una
  /// reconstrucción.
  final List<int>? raw;

  /// Tamaño total que debe tener el archivo con esta cabecera.
  int get envelopeLength => length + plaintextLength + tagLength;

  static bool hasMagic(List<int> prefix) {
    if (prefix.length < magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (prefix[i] != magic[i]) return false;
    }
    return true;
  }

  Uint8List toBytes() {
    final bytes = Uint8List(length);
    final view = ByteData.sublistView(bytes);
    bytes.setRange(0, 8, magic);
    view.setUint16(8, formatVersion);
    bytes[10] = algorithmChacha20Poly1305Hkdf;
    bytes[11] = 0;
    bytes.setRange(12, 28, keyId);
    bytes.setRange(28, 60, salt);
    bytes.setRange(60, 72, nonce);
    view.setUint64(72, plaintextLength);
    return bytes;
  }

  /// Interpreta los primeros [length] bytes. No comprueba la etiqueta: eso
  /// sólo lo hace el descifrado.
  static BackupEnvelopeHeader parse(List<int> bytes) {
    if (bytes.length < length || !hasMagic(bytes)) {
      throw const BackupEnvelopeException(BackupEnvelopeProblem.malformed);
    }
    final view = ByteData.sublistView(Uint8List.fromList(bytes.sublist(0, 80)));
    if (view.getUint16(8) != formatVersion) {
      throw const BackupEnvelopeException(BackupEnvelopeProblem.unsupported);
    }
    if (bytes[10] != algorithmChacha20Poly1305Hkdf || bytes[11] != 0) {
      throw const BackupEnvelopeException(BackupEnvelopeProblem.unsupported);
    }
    final plaintextLength = view.getUint64(72);
    if (plaintextLength < 0) {
      throw const BackupEnvelopeException(BackupEnvelopeProblem.malformed);
    }
    return BackupEnvelopeHeader(
      keyId: bytes.sublist(12, 28),
      salt: bytes.sublist(28, 60),
      nonce: bytes.sublist(60, 72),
      plaintextLength: plaintextLength,
      raw: List<int>.unmodifiable(bytes.sublist(0, length)),
    );
  }
}

enum BackupEnvelopeProblem {
  /// No tiene la forma del formato 2 (cabecera, tamaño).
  malformed,

  /// Versión, algoritmo o indicadores que esta aplicación no conoce.
  unsupported,

  /// El contenido descifrado superaría los límites admitidos.
  tooLarge,

  /// La clave de esta copia no es la indicada (identificador distinto).
  wrongKey,

  /// La etiqueta no coincide: la copia está alterada, truncada o se usó otra
  /// clave. No se usa nada de lo descifrado.
  authenticationFailed,

  /// No se pudo escribir en el teléfono (p. ej. sin espacio).
  localStorage,
}

class BackupEnvelopeException implements Exception {
  const BackupEnvelopeException(this.problem);
  final BackupEnvelopeProblem problem;

  String get message => switch (problem) {
    BackupEnvelopeProblem.malformed =>
      'La copia cifrada está dañada o incompleta. No se usó y sus datos '
          'actuales se conservan.',
    BackupEnvelopeProblem.unsupported =>
      'La copia usa un formato de cifrado que esta aplicación no conoce. '
          'Actualice la aplicación.',
    BackupEnvelopeProblem.tooLarge =>
      'La copia supera los límites de tamaño admitidos y no se abrirá.',
    BackupEnvelopeProblem.wrongKey =>
      'La clave de recuperación no corresponde a esta copia. Sus datos '
          'actuales se conservan.',
    BackupEnvelopeProblem.authenticationFailed =>
      'La copia no supera la comprobación del cifrado: está alterada o '
          'incompleta. No se usó y sus datos actuales se conservan.',
    BackupEnvelopeProblem.localStorage =>
      'No se pudo guardar la copia en el teléfono (¿falta espacio?). Sus '
          'datos actuales se conservan.',
  };

  @override
  String toString() => message;
}

/// Resultado de descifrar: el SHA-256 del contenedor interior, para volver a
/// cotejarlo justo antes de restaurar.
class DecryptedBackup {
  const DecryptedBackup(this.file, this.sha256);
  final File file;
  final String sha256;
}

/// Cifra y descifra archivos de respaldo en streaming, sin cargarlos enteros
/// en memoria.
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
    final fileKey = await key._fileKey(header.salt);
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
    final fileKey = await key._fileKey(header.salt);
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
