import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:path/path.dart' as p;

/// Límites de recursos al abrir un contenedor `.agrobackup`.
///
/// Un ZIP pequeño puede expandirse a gigabytes («bomba de descompresión») o
/// declarar miles de entradas. Los límites se comprueban **antes** de extraer,
/// con lo que declara el directorio central, y **durante** la extracción, con
/// los bytes que realmente salen del descompresor: lo declarado nunca basta.
///
/// Valores por defecto, técnicos y holgados para un hogar agrícola. No son
/// una política institucional y pueden ajustarse:
///
/// - [maxEntries] 5002: el manifiesto, la base y hasta 5000 fotografías de
///   factura (una por compra; un hogar registra decenas o cientos al año).
/// - [maxEntryBytes] 256 MiB: la base más grande razonable. Las fotografías
///   se guardan a 1800 px y calidad 82, es decir, pocos MB cada una.
/// - [maxTotalBytes] 512 MiB: lo que se escribe en la carpeta temporal del
///   teléfono antes de validar.
/// - [maxContainerBytes] 513 MiB: un contenedor legítimo no ocupa más que su
///   contenido expandido más las cabeceras. El servidor admite además sólo
///   hasta `BACKUP_MAX_BYTES` (100 MiB por defecto).
/// - [maxNameBytes] 255: el máximo habitual de un nombre de archivo.
class BackupExtractionLimits {
  const BackupExtractionLimits({
    this.maxContainerBytes = 513 * _mib,
    this.maxEntries = 5002,
    this.maxEntryBytes = 256 * _mib,
    this.maxTotalBytes = 512 * _mib,
    this.maxNameBytes = 255,
  });

  static const _mib = 1024 * 1024;
  static const standard = BackupExtractionLimits();

  final int maxContainerBytes;
  final int maxEntries;
  final int maxEntryBytes;
  final int maxTotalBytes;
  final int maxNameBytes;
}

/// El contenedor no se puede abrir de forma segura. El mensaje es
/// presentable; nunca incluye el contenido del archivo.
class BackupContainerRejected implements Exception {
  const BackupContainerRejected(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Entrada del directorio central, tal como la declara el ZIP.
class _Entry {
  _Entry({
    required this.name,
    required this.method,
    required this.crc32,
    required this.compressedSize,
    required this.declaredSize,
    required this.localHeaderOffset,
  });

  final String name;
  final int method;
  final int crc32;
  final int compressedSize;
  final int declaredSize;
  final int localHeaderOffset;

  bool get isDirectory => name.endsWith('/');
}

/// Lector ZIP acotado para el contenedor de respaldo.
///
/// Sustituye a `ZipDecoder` de `package:archive` al abrir un respaldo porque
/// éste descomprime cada entrada **entera en memoria** antes de escribirla
/// (también al leer enlaces simbólicos durante el propio decodificado): con
/// él no hay forma de cortar una expansión excesiva a tiempo.
///
/// Admite sólo lo que escribe la aplicación (`ZipFileEncoder`): entradas
/// guardadas o deflate, sin cifrado, sin ZIP64 y con la forma
/// `manifest.json`, `database.db` e `invoices/<archivo>`.
class BackupContainerReader {
  const BackupContainerReader([this.limits = BackupExtractionLimits.standard]);

  final BackupExtractionLimits limits;

  static const _eocdSignature = 0x06054b50;
  static const _centralSignature = 0x02014b50;
  static const _localSignature = 0x04034b50;
  static const _eocdSize = 22;
  static const _centralSize = 46;
  static const _localSize = 30;
  static const _methodStored = 0;
  static const _methodDeflate = 8;
  static const _chunk = 64 * 1024;

  static const _tooLarge = BackupContainerRejected(
    'El respaldo supera los límites de tamaño admitidos y no se abrirá.',
  );
  static const _malformed = BackupContainerRejected(
    'El archivo de respaldo está dañado o no tiene el formato esperado.',
  );
  static const _forbiddenPath = BackupContainerRejected(
    'El respaldo contiene rutas no permitidas y no se abrirá.',
  );

  /// Extrae [path] en [destination], que debe existir y estar vacía.
  ///
  /// Ante cualquier rechazo lanza [BackupContainerRejected] y puede dejar
  /// archivos parciales en [destination]: quien la creó la borra.
  Future<void> extract(String path, Directory destination) async {
    final file = File(path);
    final length = await file.length();
    if (length > limits.maxContainerBytes) throw _tooLarge;

    final handle = await file.open();
    try {
      final (entries, directoryOffset) = _readDirectory(handle, length);
      var total = 0;
      for (final entry in entries) {
        if (entry.isDirectory) continue;
        total += _extractEntry(
          handle,
          entry,
          destination,
          total,
          directoryOffset,
        );
      }
    } finally {
      await handle.close();
    }
  }

  /// Lee y comprueba el directorio central completo antes de extraer nada.
  /// Devuelve las entradas y dónde empieza el directorio: los datos de cada
  /// entrada deben estar antes.
  (List<_Entry>, int) _readDirectory(RandomAccessFile handle, int length) {
    if (length < _eocdSize) throw _malformed;
    final tailLength = length < _eocdSize + 0xFFFF
        ? length
        : _eocdSize + 0xFFFF;
    final tail = _readAt(handle, length - tailLength, tailLength);

    // Registro de fin de directorio: el último cuya longitud de comentario
    // cuadra exactamente con el final del archivo.
    var eocd = -1;
    for (var i = tail.length - _eocdSize; i >= 0; i--) {
      if (_u32(tail, i) == _eocdSignature &&
          i + _eocdSize + _u16(tail, i + 20) == tail.length) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) throw _malformed;

    final diskNumber = _u16(tail, eocd + 4);
    final directoryDisk = _u16(tail, eocd + 6);
    final entriesOnDisk = _u16(tail, eocd + 8);
    final totalEntries = _u16(tail, eocd + 10);
    final directorySize = _u32(tail, eocd + 12);
    final directoryOffset = _u32(tail, eocd + 16);
    final eocdOffset = length - tailLength + eocd;

    // Varios discos o ZIP64: la aplicación nunca los escribe.
    if (diskNumber != 0 ||
        directoryDisk != 0 ||
        entriesOnDisk != totalEntries ||
        totalEntries == 0xFFFF ||
        directorySize == 0xFFFFFFFF ||
        directoryOffset == 0xFFFFFFFF) {
      throw _malformed;
    }
    if (totalEntries > limits.maxEntries) {
      throw const BackupContainerRejected(
        'El respaldo contiene más archivos de los admitidos y no se abrirá.',
      );
    }
    if (directoryOffset + directorySize > eocdOffset ||
        directorySize >
            totalEntries * (_centralSize + limits.maxNameBytes + 1024)) {
      throw _malformed;
    }

    final directory = _readAt(handle, directoryOffset, directorySize);
    final entries = <_Entry>[];
    final seen = <String>{};
    var declaredTotal = 0;
    var offset = 0;
    for (var index = 0; index < totalEntries; index++) {
      if (offset + _centralSize > directory.length ||
          _u32(directory, offset) != _centralSignature) {
        throw _malformed;
      }
      final madeBy = _u16(directory, offset + 4);
      final flags = _u16(directory, offset + 8);
      final method = _u16(directory, offset + 10);
      final crc32 = _u32(directory, offset + 16);
      final compressedSize = _u32(directory, offset + 20);
      final declaredSize = _u32(directory, offset + 24);
      final nameLength = _u16(directory, offset + 28);
      final extraLength = _u16(directory, offset + 30);
      final commentLength = _u16(directory, offset + 32);
      final externalAttributes = _u32(directory, offset + 38);
      final localHeaderOffset = _u32(directory, offset + 42);
      final nameStart = offset + _centralSize;
      final next = nameStart + nameLength + extraLength + commentLength;
      if (next > directory.length) throw _malformed;

      if (nameLength == 0 || nameLength > limits.maxNameBytes) {
        throw _forbiddenPath;
      }
      final String name;
      try {
        name = utf8.decode(
          directory.sublist(nameStart, nameStart + nameLength),
        );
      } on FormatException {
        throw _forbiddenPath;
      }
      _checkName(name);
      // Mayúsculas aparte: en un sistema de archivos que no las distingue,
      // dos entradas así escribirían el mismo archivo.
      if (!seen.add(name.toLowerCase())) throw _forbiddenPath;

      // Cifrado (bit 0) o cifrado fuerte (bit 6): la aplicación no cifra.
      if (flags & 0x41 != 0) throw _malformed;
      if (method != _methodStored && method != _methodDeflate) {
        throw _malformed;
      }
      if (compressedSize == 0xFFFFFFFF ||
          declaredSize == 0xFFFFFFFF ||
          localHeaderOffset == 0xFFFFFFFF) {
        throw _malformed;
      }
      // Enlace simbólico de Unix: nunca forma parte de un respaldo.
      if (madeBy >> 8 == 3 && (externalAttributes >> 16) & 0xF000 == 0xA000) {
        throw _forbiddenPath;
      }

      final entry = _Entry(
        name: name,
        method: method,
        crc32: crc32,
        compressedSize: compressedSize,
        declaredSize: declaredSize,
        localHeaderOffset: localHeaderOffset,
      );
      if (entry.isDirectory) {
        if (declaredSize != 0 || compressedSize > 2) throw _malformed;
      } else {
        if (method == _methodStored && compressedSize != declaredSize) {
          throw _malformed;
        }
        if (declaredSize > limits.maxEntryBytes) throw _tooLarge;
        declaredTotal += declaredSize;
        if (declaredTotal > limits.maxTotalBytes) throw _tooLarge;
      }
      if (localHeaderOffset + _localSize + compressedSize > directoryOffset) {
        throw _malformed;
      }
      entries.add(entry);
      offset = next;
    }
    return (entries, directoryOffset);
  }

  /// Sólo la forma del contenedor: `manifest.json`, `database.db` e
  /// `invoices/<archivo>` (más la carpeta `invoices/`). Rechaza cualquier
  /// otra ruta, absoluta, con `..`, con separadores de Windows o con
  /// caracteres de control.
  void _checkName(String name) {
    if (name.contains('\\') ||
        name.contains(':') ||
        name.startsWith('/') ||
        name.codeUnits.any((c) => c < 0x20 || c == 0x7F)) {
      throw _forbiddenPath;
    }
    if (name == 'manifest.json' ||
        name == 'database.db' ||
        name == 'invoices/') {
      return;
    }
    final segments = name.split('/');
    if (segments.length == 2 &&
        segments.first == 'invoices' &&
        segments.last.isNotEmpty &&
        segments.last != '.' &&
        segments.last != '..') {
      return;
    }
    throw _forbiddenPath;
  }

  /// Extrae [entry] contando los bytes **reales** que produce el
  /// descompresor. Corta en cuanto supera lo que declaró la entrada, el
  /// límite por entrada o el total. Devuelve los bytes escritos.
  int _extractEntry(
    RandomAccessFile handle,
    _Entry entry,
    Directory destination,
    int writtenBefore,
    int directoryOffset,
  ) {
    final local = _readAt(handle, entry.localHeaderOffset, _localSize);
    if (local.length < _localSize || _u32(local, 0) != _localSignature) {
      throw _malformed;
    }
    final localNameLength = _u16(local, 26);
    final localExtraLength = _u16(local, 28);
    final localName = _readAt(
      handle,
      entry.localHeaderOffset + _localSize,
      localNameLength,
    );
    if (!_sameBytes(localName, utf8.encode(entry.name))) throw _malformed;
    final dataStart =
        entry.localHeaderOffset +
        _localSize +
        localNameLength +
        localExtraLength;
    if (dataStart + entry.compressedSize > directoryOffset) throw _malformed;

    final entryLimit = entry.declaredSize < limits.maxEntryBytes
        ? entry.declaredSize
        : limits.maxEntryBytes;
    final output = File(
      p.joinAll([destination.path, ...entry.name.split('/')]),
    );
    output.parent.createSync(recursive: true);
    final sink = output.openSync(mode: FileMode.writeOnly);
    var written = 0;
    var crc = 0;
    void emit(List<int> chunk) {
      if (written + chunk.length > entryLimit ||
          writtenBefore + written + chunk.length > limits.maxTotalBytes) {
        throw _tooLarge;
      }
      sink.writeFromSync(chunk);
      crc = getCrc32(chunk, crc);
      written += chunk.length;
    }

    try {
      handle.setPositionSync(dataStart);
      var remaining = entry.compressedSize;
      if (entry.method == _methodStored) {
        while (remaining > 0) {
          final chunk = handle.readSync(
            remaining < _chunk ? remaining : _chunk,
          );
          if (chunk.isEmpty) throw _malformed;
          emit(chunk);
          remaining -= chunk.length;
        }
      } else {
        final inflater = ZLibCodec(raw: true).decoder
            .startChunkedConversion(_EmitSink(emit));
        try {
          while (remaining > 0) {
            final chunk = handle.readSync(
              remaining < _chunk ? remaining : _chunk,
            );
            if (chunk.isEmpty) throw _malformed;
            inflater.add(chunk);
            remaining -= chunk.length;
          }
          inflater.close();
        } on FormatException {
          throw _malformed;
        } on FileSystemException {
          rethrow;
        } on BackupContainerRejected {
          rethrow;
        } on Exception {
          // `ZLibDecoder` señala los datos inválidos con excepciones propias.
          throw _malformed;
        }
      }
      sink.flushSync();
    } finally {
      sink.closeSync();
    }
    if (written != entry.declaredSize || crc != entry.crc32) {
      throw _malformed;
    }
    return written;
  }

  static Uint8List _readAt(RandomAccessFile handle, int offset, int count) {
    handle.setPositionSync(offset);
    final bytes = handle.readSync(count);
    if (bytes.length != count) throw _malformed;
    return bytes;
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static int _u16(List<int> bytes, int offset) =>
      bytes[offset] | (bytes[offset + 1] << 8);

  static int _u32(List<int> bytes, int offset) =>
      bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);
}

class _EmitSink implements Sink<List<int>> {
  _EmitSink(this._emit);
  final void Function(List<int> chunk) _emit;
  @override
  void add(List<int> data) => _emit(data);
  @override
  void close() {}
}
