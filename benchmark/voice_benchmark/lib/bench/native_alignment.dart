/// Comprobación de compatibilidad con páginas de 16 KB de las librerías nativas.
///
/// ## Por qué existe
///
/// Desde Android 15 hay aparatos cuyo kernel usa páginas de **16 KB**. Una
/// librería nativa cuyos segmentos `LOAD` estén alineados a 4 KB **no carga**
/// allí: la aplicación revienta con `UnsatisfiedLinkError` en el primer uso del
/// motor. Es exactamente la clase de fallo por incompatibilidad de aparato que
/// abrió la Fase 0-bis, así que aquí se comprueba en vez de suponerse.
///
/// ## Las tres cosas que NO son lo mismo
///
/// Se confunden constantemente y ninguna sustituye a las otras:
///
/// 1. **Compatibilidad ELF**: los segmentos `LOAD` de cada `.so` alineados a
///    16384. Es lo que mide este archivo.
/// 2. **Alineamiento ZIP**: que el `.so` empiece en un múltiplo de 16 KB dentro
///    del APK y esté sin comprimir, para poder mapearse directamente. Lo mide
///    `zipalign -c -P 16 -v 4`.
/// 3. **Ejecución real**: arrancar en un aparato o emulador con
///    `getconf PAGE_SIZE` = `16384` y transcribir de verdad.
///
/// Este archivo cubre **sólo la primera**. El plan de benchmark exige las tres.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Alineación exigida a los segmentos `LOAD`.
const int requiredAlignment = 16384;

/// Resultado de examinar una librería nativa concreta.
final class NativeLibraryCheck {
  const NativeLibraryCheck({
    required this.path,
    required this.abi,
    required this.sizeBytes,
    required this.loadAlignments,
    this.is64Bit = true,
    this.error,
  });

  /// Ruta dentro del APK/AAR, por ejemplo `lib/arm64-v8a/libvosk.so`.
  final String path;

  /// ABI deducida de la ruta. `desconocida` si no sigue el convenio.
  final String abi;

  final int sizeBytes;

  /// Alineación de cada segmento `PT_LOAD`, en orden.
  final List<int> loadAlignments;

  /// La librería es de 64 bits.
  ///
  /// Decide si el requisito **aplica**: los aparatos con páginas de 16 KB son
  /// sólo de 64 bits y no ejecutan código de 32 bits. Exigirle 16 KB a
  /// `armeabi-v7a` inventaría un requisito que Android no tiene y bloquearía
  /// un artefacto correcto: medido contra los AAR reales de Vosk y de JNA,
  /// cuyas ABIs de 32 bits están a 4096 y así deben estar.
  final bool is64Bit;

  /// Por qué no se pudo analizar. `null` si se analizó bien.
  final String? error;

  /// El requisito de 16 KB se aplica a esta librería.
  bool get applies => is64Bit;

  /// Pasa el gate: o no le aplica, o todos sus segmentos llegan a
  /// [requiredAlignment].
  bool get isCompatible {
    if (error != null || loadAlignments.isEmpty) return false;
    if (!applies) return true;
    return loadAlignments.every((a) => a >= requiredAlignment);
  }

  /// La menor alineación encontrada, que es la que decide.
  int get worstAlignment =>
      loadAlignments.isEmpty ? 0 : loadAlignments.reduce((a, b) => a < b ? a : b);

  Map<String, Object?> toJson() => {
    'path': path,
    'abi': abi,
    'sizeBytes': sizeBytes,
    'loadAlignments': loadAlignments,
    'worstAlignment': worstAlignment,
    'is64Bit': is64Bit,
    'requirementApplies': applies,
    'compatible16k': isCompatible,
    'error': error,
  };

  @override
  String toString() {
    if (error != null) return '$path — NO ANALIZADA ($error)';
    final verdict = !applies
        ? 'no aplica (32 bits)'
        : (isCompatible ? 'OK 16 KB' : 'FALLA ($worstAlignment B)');
    return '$path  [$abi]  $sizeBytes B  align=$worstAlignment  $verdict';
  }
}

/// Lo encontrado en un APK o AAR completo.
final class NativeAlignmentReport {
  const NativeAlignmentReport({required this.archive, required this.libraries});

  final String archive;
  final List<NativeLibraryCheck> libraries;

  /// ABIs presentes en el archivo, ordenadas.
  List<String> get abis =>
      (libraries.map((l) => l.abi).toSet().toList()..sort());

  /// Las que no pasan. El gate falla si esta lista no está vacía.
  List<NativeLibraryCheck> get failures =>
      libraries.where((l) => !l.isCompatible).toList();

  /// Ninguna librería queda en 4 KB **y** hay al menos una que revisar.
  ///
  /// Un archivo sin librerías nativas no "pasa": no hay nada que afirmar, y
  /// devolver `true` haría que un APK mal construido —sin las librerías— se
  /// leyera como aprobado.
  bool get passes => libraries.isNotEmpty && failures.isEmpty;

  Map<String, Object?> toJson() => {
    'archive': archive,
    'abis': abis,
    'libraryCount': libraries.length,
    'passes': passes,
    'libraries': [for (final l in libraries) l.toJson()],
  };

  String render() {
    final buffer = StringBuffer()
      ..writeln('Compatibilidad con páginas de 16 KB — $archive')
      ..writeln('ABIs: ${abis.isEmpty ? 'ninguna' : abis.join(', ')}')
      ..writeln('Librerías nativas: ${libraries.length}')
      ..writeln();
    for (final library in libraries) {
      buffer.writeln('  $library');
    }
    buffer.writeln();
    if (libraries.isEmpty) {
      buffer.writeln(
        'SIN LIBRERÍAS NATIVAS: no hay nada que comprobar y por tanto no se '
        'aprueba. Si este APK debería llevar Vosk o Whisper, está mal '
        'construido.',
      );
    } else if (passes) {
      final checked = libraries.where((l) => l.applies).length;
      buffer.writeln(
        'RESULTADO: pasa. $checked de ${libraries.length} librerías son de 64 '
        'bits y todas están a 16 KB; al resto no le aplica el requisito.',
      );
    } else {
      buffer.writeln('RESULTADO: FALLA. Alineadas a menos de 16 KB:');
      for (final failure in failures) {
        buffer.writeln('  - ${failure.path} (${failure.worstAlignment} B)');
      }
    }
    buffer.writeln();
    buffer.writeln(
      'Esto comprueba SÓLO el ELF. Faltan `zipalign -c -P 16 -v 4` y la '
      'ejecución real en un aparato con PAGE_SIZE=16384.',
    );
    return buffer.toString();
  }
}

/// Lee las alineaciones `PT_LOAD` de un ELF de 64 bits little-endian.
///
/// Devuelve una lista vacía si el archivo no es un ELF legible; el llamador lo
/// trata como "no analizada" en vez de como aprobada.
List<int> loadSegmentAlignments(Uint8List bytes) {
  if (!isElf(bytes)) return const [];
  final wide = isElf64(bytes);
  final data = ByteData.sublistView(bytes);

  final phoff = wide
      ? data.getUint64(0x20, Endian.little)
      : data.getUint32(0x1C, Endian.little);
  final phentsize = data.getUint16(wide ? 0x36 : 0x2A, Endian.little);
  final phnum = data.getUint16(wide ? 0x38 : 0x2C, Endian.little);
  if (phentsize < (wide ? 56 : 32) || phnum == 0) return const [];

  final alignments = <int>[];
  for (var i = 0; i < phnum; i++) {
    final offset = phoff + i * phentsize;
    if (offset + phentsize > bytes.length) break;
    if (data.getUint32(offset, Endian.little) != 1) continue; // PT_LOAD
    alignments.add(
      wide
          ? data.getUint64(offset + 0x30, Endian.little)
          : data.getUint32(offset + 28, Endian.little),
    );
  }
  return alignments;
}

/// La cabecera dice ELF little-endian, de 32 o de 64 bits.
bool isElf(Uint8List bytes) =>
    bytes.length >= 52 &&
    bytes[0] == 0x7F &&
    bytes[1] == 0x45 &&
    bytes[2] == 0x4C &&
    bytes[3] == 0x46 &&
    (bytes[4] == 1 || bytes[4] == 2) &&
    bytes[5] == 1;

/// La librería es ELF de 64 bits, que es a la que le aplica el requisito.
bool isElf64(Uint8List bytes) => isElf(bytes) && bytes[4] == 2;

/// La ABI que nombra la ruta `lib/<abi>/x.so` o `jni/<abi>/x.so`.
String abiFromPath(String path) {
  final parts = path.split('/');
  for (var i = 0; i < parts.length - 1; i++) {
    if (parts[i] == 'lib' || parts[i] == 'jni') return parts[i + 1];
  }
  return 'desconocida';
}

/// Examina todas las librerías nativas de un APK o AAR.
NativeAlignmentReport inspectArchive(File archive) {
  final entries = _readZipEntries(archive.readAsBytesSync());
  final libraries = <NativeLibraryCheck>[];
  for (final entry in entries) {
    if (!entry.name.endsWith('.so')) continue;
    Uint8List? content;
    String? error;
    try {
      content = entry.read();
    } on Object catch (e) {
      error = e.runtimeType.toString();
    }
    final alignments = content == null
        ? const <int>[]
        : loadSegmentAlignments(content);
    libraries.add(
      NativeLibraryCheck(
        path: entry.name,
        abi: abiFromPath(entry.name),
        sizeBytes: entry.uncompressedSize,
        loadAlignments: alignments,
        is64Bit: content != null && isElf64(content),
        error: error ?? (alignments.isEmpty ? 'no es un ELF legible' : null),
      ),
    );
  }
  libraries.sort((a, b) => a.path.compareTo(b.path));
  return NativeAlignmentReport(
    archive: archive.path,
    libraries: libraries,
  );
}

// --------------------------------------------------------------------- ZIP

/// Una entrada del ZIP, ya localizada pero todavía no descomprimida.
final class _ZipEntry {
  _ZipEntry({
    required this.name,
    required this.bytes,
    required this.localHeaderOffset,
    required this.compressionMethod,
    required this.compressedSize,
    required this.uncompressedSize,
  });

  final String name;
  final Uint8List bytes;
  final int localHeaderOffset;
  final int compressionMethod;
  final int compressedSize;
  final int uncompressedSize;

  /// Descomprime sólo cuando hace falta: un APK con Whisper trae 190 MB de
  /// modelo que no interesa tocar.
  Uint8List read() {
    final data = ByteData.sublistView(bytes);
    if (data.getUint32(localHeaderOffset, Endian.little) != 0x04034B50) {
      throw const FormatException('cabecera local inválida');
    }
    final nameLength = data.getUint16(localHeaderOffset + 26, Endian.little);
    final extraLength = data.getUint16(localHeaderOffset + 28, Endian.little);
    final start = localHeaderOffset + 30 + nameLength + extraLength;
    final raw = Uint8List.sublistView(bytes, start, start + compressedSize);
    return switch (compressionMethod) {
      0 => Uint8List.fromList(raw),
      8 => Uint8List.fromList(ZLibCodec(raw: true).decode(raw)),
      _ => throw FormatException('compresión $compressionMethod'),
    };
  }
}

/// Lee el directorio central del ZIP. Sin dependencias externas a propósito:
/// el banco no añade paquetes de pub.
List<_ZipEntry> _readZipEntries(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final eocd = _findEndOfCentralDirectory(bytes);
  if (eocd < 0) throw const FormatException('no es un ZIP');

  var count = data.getUint16(eocd + 10, Endian.little);
  var offset = data.getUint32(eocd + 16, Endian.little);

  // ZIP64: un APK con modelos grandes puede pasar de 4 GiB de offsets.
  if (offset == 0xFFFFFFFF || count == 0xFFFF) {
    final locator = _findZip64Locator(bytes, eocd);
    if (locator >= 0) {
      final zip64 = data.getUint64(locator + 8, Endian.little);
      count = data.getUint64(zip64 + 32, Endian.little);
      offset = data.getUint64(zip64 + 48, Endian.little);
    }
  }

  final entries = <_ZipEntry>[];
  for (var i = 0; i < count; i++) {
    if (offset + 46 > bytes.length) break;
    if (data.getUint32(offset, Endian.little) != 0x02014B50) break;
    final method = data.getUint16(offset + 10, Endian.little);
    final compressed = data.getUint32(offset + 20, Endian.little);
    final uncompressed = data.getUint32(offset + 24, Endian.little);
    final nameLength = data.getUint16(offset + 28, Endian.little);
    final extraLength = data.getUint16(offset + 30, Endian.little);
    final commentLength = data.getUint16(offset + 32, Endian.little);
    final localOffset = data.getUint32(offset + 42, Endian.little);
    final name = utf8.decode(
      Uint8List.sublistView(bytes, offset + 46, offset + 46 + nameLength),
      allowMalformed: true,
    );
    entries.add(
      _ZipEntry(
        name: name,
        bytes: bytes,
        localHeaderOffset: localOffset,
        compressionMethod: method,
        compressedSize: compressed,
        uncompressedSize: uncompressed,
      ),
    );
    offset += 46 + nameLength + extraLength + commentLength;
  }
  return entries;
}

int _findEndOfCentralDirectory(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final lowest = bytes.length - 22 - 0xFFFF;
  for (var i = bytes.length - 22; i >= (lowest < 0 ? 0 : lowest); i--) {
    if (data.getUint32(i, Endian.little) == 0x06054B50) return i;
  }
  return -1;
}

int _findZip64Locator(Uint8List bytes, int eocd) {
  final data = ByteData.sublistView(bytes);
  final start = eocd - 20;
  if (start < 0) return -1;
  return data.getUint32(start, Endian.little) == 0x07064B50 ? start : -1;
}
