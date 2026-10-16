import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;

/// Entrada de un ZIP construido byte a byte en las pruebas.
///
/// Permite lo que un codificador correcto nunca escribe: tamaños o CRC que
/// mienten, nombres peligrosos, cifrado, ZIP64 o enlaces simbólicos.
class RawZipEntry {
  RawZipEntry(
    this.name, {
    List<int>? data,
    this.compressed,
    this.deflate = true,
    this.declaredSize,
    this.crc32,
    this.flags = 0x0800,
    this.method,
    this.madeBy = 20,
    this.externalAttributes = 0,
    this.forceZip64Marker = false,
  }) : data = data ?? const [];

  final String name;

  /// Contenido sin comprimir. Se ignora si se da [compressed].
  final List<int> data;

  /// Datos ya comprimidos (deflate sin cabecera), p. ej. una bomba.
  final List<int>? compressed;
  final bool deflate;
  final int? declaredSize;
  final int? crc32;
  final int flags;
  final int? method;
  final int madeBy;
  final int externalAttributes;
  final bool forceZip64Marker;
}

/// Deflate sin cabecera de [data].
List<int> rawDeflate(List<int> data) =>
    ZLibCodec(raw: true, level: 9).encode(data);

/// Deflate sin cabecera de [mebibytes] MiB de ceros, sin tenerlos en memoria.
List<int> deflatedZeros(int mebibytes) {
  final out = BytesBuilder(copy: false);
  final sink = ZLibCodec(
    raw: true,
    level: 9,
  ).encoder.startChunkedConversion(ByteConversionSink.withCallback(out.add));
  final zeros = Uint8List(1024 * 1024);
  for (var i = 0; i < mebibytes; i++) {
    sink.add(zeros);
  }
  sink.close();
  return out.takeBytes();
}

/// Escribe un ZIP con [entries] en [path].
Future<void> writeRawZip(String path, List<RawZipEntry> entries) async {
  final out = BytesBuilder(copy: false);
  final central = BytesBuilder(copy: false);

  void u16(BytesBuilder b, int v) => b.add([v & 0xff, (v >> 8) & 0xff]);
  void u32(BytesBuilder b, int v) =>
      b.add([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);

  for (final entry in entries) {
    final name = utf8.encode(entry.name);
    final payload =
        entry.compressed ??
        (entry.deflate ? rawDeflate(entry.data) : entry.data);
    final method = entry.method ?? (entry.deflate ? 8 : 0);
    final crc = entry.crc32 ?? getCrc32(entry.data);
    final size = entry.declaredSize ?? entry.data.length;
    final compressedSize = entry.forceZip64Marker ? 0xFFFFFFFF : payload.length;
    final offset = out.length;

    u32(out, 0x04034b50);
    u16(out, 20);
    u16(out, entry.flags);
    u16(out, method);
    u16(out, 0);
    u16(out, 0x5821);
    u32(out, crc);
    u32(out, compressedSize);
    u32(out, size);
    u16(out, name.length);
    u16(out, 0);
    out.add(name);
    out.add(payload);

    u32(central, 0x02014b50);
    u16(central, entry.madeBy);
    u16(central, 20);
    u16(central, entry.flags);
    u16(central, method);
    u16(central, 0);
    u16(central, 0x5821);
    u32(central, crc);
    u32(central, compressedSize);
    u32(central, size);
    u16(central, name.length);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u32(central, entry.externalAttributes);
    u32(central, offset);
    central.add(name);
  }

  final directoryOffset = out.length;
  final directory = central.takeBytes();
  out.add(directory);
  u32(out, 0x06054b50);
  u16(out, 0);
  u16(out, 0);
  u16(out, entries.length);
  u16(out, entries.length);
  u32(out, directory.length);
  u32(out, directoryOffset);
  u16(out, 0);
  await File(path).writeAsBytes(out.takeBytes(), flush: true);
}
