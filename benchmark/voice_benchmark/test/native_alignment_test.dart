import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_benchmark/bench/native_alignment.dart';

/// Gate de páginas de 16 KB.
///
/// Se prueba contra ELF y ZIP **construidos aquí**, byte a byte: un gate que
/// sólo se hubiera probado contra el APK del día no detectaría el caso que
/// importa —una librería a 4 KB colada entre varias correctas— hasta que ya
/// fuera tarde.
void main() {
  /// ELF64 little-endian mínimo con los `PT_LOAD` que se le pidan.
  Uint8List elf({required List<int> loadAlignments, List<int> other = const []}) {
    const headerSize = 64;
    const phentsize = 56;
    final phnum = loadAlignments.length + other.length;
    final bytes = Uint8List(headerSize + phnum * phentsize);
    final data = ByteData.sublistView(bytes);

    bytes.setAll(0, [0x7F, 0x45, 0x4C, 0x46]); // \x7fELF
    bytes[4] = 2; // ELFCLASS64
    bytes[5] = 1; // little-endian
    data.setUint64(0x20, headerSize, Endian.little); // e_phoff
    data.setUint16(0x36, phentsize, Endian.little); // e_phentsize
    data.setUint16(0x38, phnum, Endian.little); // e_phnum

    var offset = headerSize;
    for (final align in loadAlignments) {
      data.setUint32(offset, 1, Endian.little); // PT_LOAD
      data.setUint64(offset + 0x30, align, Endian.little);
      offset += phentsize;
    }
    for (final align in other) {
      data.setUint32(offset, 2, Endian.little); // PT_DYNAMIC: se ignora
      data.setUint64(offset + 0x30, align, Endian.little);
      offset += phentsize;
    }
    return bytes;
  }

  /// ELF32 little-endian mínimo. Las ABIs de 32 bits del AAR de Vosk y de JNA
  /// son así, y leerlas mal las convertía en falsos fallos del gate.
  Uint8List elf32({required List<int> loadAlignments}) {
    const headerSize = 52;
    const phentsize = 32;
    final phnum = loadAlignments.length;
    final bytes = Uint8List(headerSize + phnum * phentsize);
    final data = ByteData.sublistView(bytes);

    bytes.setAll(0, [0x7F, 0x45, 0x4C, 0x46]);
    bytes[4] = 1; // ELFCLASS32
    bytes[5] = 1; // little-endian
    data.setUint32(0x1C, headerSize, Endian.little); // e_phoff
    data.setUint16(0x2A, phentsize, Endian.little); // e_phentsize
    data.setUint16(0x2C, phnum, Endian.little); // e_phnum

    var offset = headerSize;
    for (final align in loadAlignments) {
      data.setUint32(offset, 1, Endian.little); // PT_LOAD
      data.setUint32(offset + 28, align, Endian.little);
      offset += phentsize;
    }
    return bytes;
  }

  /// ZIP mínimo, sin comprimir, como los `.so` dentro de un APK moderno.
  Uint8List zip(Map<String, Uint8List> files) {
    final out = BytesBuilder();
    final offsets = <String, int>{};

    files.forEach((name, content) {
      offsets[name] = out.length;
      final nameBytes = utf8.encode(name);
      final header = ByteData(30);
      header.setUint32(0, 0x04034B50, Endian.little);
      header.setUint16(4, 20, Endian.little);
      header.setUint16(8, 0, Endian.little); // sin comprimir
      header.setUint32(18, content.length, Endian.little);
      header.setUint32(22, content.length, Endian.little);
      header.setUint16(26, nameBytes.length, Endian.little);
      out
        ..add(header.buffer.asUint8List())
        ..add(nameBytes)
        ..add(content);
    });

    final centralStart = out.length;
    files.forEach((name, content) {
      final nameBytes = utf8.encode(name);
      final entry = ByteData(46);
      entry.setUint32(0, 0x02014B50, Endian.little);
      entry.setUint16(10, 0, Endian.little);
      entry.setUint32(20, content.length, Endian.little);
      entry.setUint32(24, content.length, Endian.little);
      entry.setUint16(28, nameBytes.length, Endian.little);
      entry.setUint32(42, offsets[name]!, Endian.little);
      out
        ..add(entry.buffer.asUint8List())
        ..add(nameBytes);
    });
    final centralSize = out.length - centralStart;

    final eocd = ByteData(22);
    eocd.setUint32(0, 0x06054B50, Endian.little);
    eocd.setUint16(8, files.length, Endian.little);
    eocd.setUint16(10, files.length, Endian.little);
    eocd.setUint32(12, centralSize, Endian.little);
    eocd.setUint32(16, centralStart, Endian.little);
    out.add(eocd.buffer.asUint8List());

    return out.toBytes();
  }

  File archiveWith(Map<String, Uint8List> files) {
    final dir = Directory.systemTemp.createTempSync('align16k');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/candidato.apk')..writeAsBytesSync(zip(files));
    return file;
  }

  group('lectura del ELF', () {
    test('lee la alineación de cada segmento cargable', () {
      expect(
        loadSegmentAlignments(elf(loadAlignments: [16384, 16384])),
        [16384, 16384],
      );
    });

    test('ignora los segmentos que no son PT_LOAD', () {
      // Un `PT_DYNAMIC` a 8 bytes es normal y no dice nada de la carga.
      expect(
        loadSegmentAlignments(elf(loadAlignments: [16384], other: [8])),
        [16384],
      );
    });

    test('lo que no es un ELF legible no devuelve alineaciones', () {
      expect(loadSegmentAlignments(Uint8List(0)), isEmpty);
      expect(loadSegmentAlignments(Uint8List.fromList([1, 2, 3, 4])), isEmpty);
    });

    test('lee también los ELF de 32 bits', () {
      // Medido contra los AAR reales de Vosk y JNA: sus `armeabi-v7a` y `x86`
      // son ELF32. Tratarlos como ilegibles los convertía en fallos del gate.
      expect(loadSegmentAlignments(elf32(loadAlignments: [4096])), [4096]);
    });
  });

  group('veredicto por librería', () {
    test('16384 pasa y 4096 falla', () {
      final ok = NativeLibraryCheck(
        path: 'lib/arm64-v8a/libvosk.so',
        abi: 'arm64-v8a',
        sizeBytes: 10,
        loadAlignments: const [16384, 16384],
      );
      final bad = NativeLibraryCheck(
        path: 'lib/arm64-v8a/libviejo.so',
        abi: 'arm64-v8a',
        sizeBytes: 10,
        loadAlignments: const [16384, 4096],
      );
      expect(ok.isCompatible, isTrue);
      expect(bad.isCompatible, isFalse);
      expect(
        bad.worstAlignment,
        4096,
        reason: 'manda el peor segmento, no el mejor',
      );
    });

    test('una librería que no se pudo analizar nunca se da por buena', () {
      const check = NativeLibraryCheck(
        path: 'lib/arm64-v8a/libx.so',
        abi: 'arm64-v8a',
        sizeBytes: 10,
        loadAlignments: [16384],
        error: 'no es un ELF64 legible',
      );
      expect(check.isCompatible, isFalse);
    });

    test('deduce la ABI de rutas de APK y de AAR', () {
      expect(abiFromPath('lib/arm64-v8a/libvosk.so'), 'arm64-v8a');
      expect(abiFromPath('jni/armeabi-v7a/libjnidispatch.so'), 'armeabi-v7a');
      expect(abiFromPath('algo/raro.so'), 'desconocida');
    });
  });

  group('archivo completo', () {
    test('pasa cuando todas las librerías están a 16 KB', () {
      final file = archiveWith({
        'lib/arm64-v8a/libvosk.so': elf(loadAlignments: [16384, 16384]),
        'lib/arm64-v8a/libjnidispatch.so': elf(loadAlignments: [16384]),
        'AndroidManifest.xml': Uint8List.fromList(utf8.encode('<manifest/>')),
      });

      final report = inspectArchive(file);

      expect(report.libraries, hasLength(2));
      expect(report.abis, ['arm64-v8a']);
      expect(report.passes, isTrue);
    });

    test('una sola librería a 4 KB tumba el gate entero', () {
      // El caso real: `libvosk.so` correcto y una transitiva a 4 KB. Revisar
      // sólo la principal habría dado el APK por bueno.
      final file = archiveWith({
        'lib/arm64-v8a/libvosk.so': elf(loadAlignments: [16384]),
        'lib/arm64-v8a/libjnidispatch.so': elf(loadAlignments: [4096]),
        'lib/arm64-v8a/libggml.so': elf(loadAlignments: [16384]),
      });

      final report = inspectArchive(file);

      expect(report.passes, isFalse);
      expect(report.failures.map((f) => f.path), [
        'lib/arm64-v8a/libjnidispatch.so',
      ]);
      expect(report.render(), contains('FALLA'));
    });

    test('una ABI de 32 bits a 4 KB no tumba el gate', () {
      // Los aparatos con páginas de 16 KB son sólo de 64 bits y no ejecutan
      // código de 32 bits. Exigirle 16 KB a `armeabi-v7a` sería inventar un
      // requisito que Android no tiene, y bloquearía un AAR correcto.
      final file = archiveWith({
        'jni/arm64-v8a/libvosk.so': elf(loadAlignments: [16384]),
        'jni/armeabi-v7a/libvosk.so': elf32(loadAlignments: [4096]),
      });

      final report = inspectArchive(file);

      expect(report.passes, isTrue);
      expect(report.failures, isEmpty);
      final arm32 = report.libraries.firstWhere((l) => l.abi == 'armeabi-v7a');
      expect(arm32.is64Bit, isFalse);
      expect(
        arm32.worstAlignment,
        4096,
        reason: 'se registra el dato aunque no decida el gate',
      );
    });

    test('una ABI de 64 bits a 4 KB sí tumba el gate', () {
      final file = archiveWith({
        'jni/arm64-v8a/libvosk.so': elf(loadAlignments: [4096]),
        'jni/armeabi-v7a/libvosk.so': elf32(loadAlignments: [4096]),
      });

      final report = inspectArchive(file);

      expect(report.passes, isFalse);
      expect(report.failures.single.abi, 'arm64-v8a');
    });

    test('enumera todas las ABIs presentes, no sólo la primera', () {
      final file = archiveWith({
        'lib/arm64-v8a/libvosk.so': elf(loadAlignments: [16384]),
        'lib/x86_64/libvosk.so': elf(loadAlignments: [4096]),
      });

      final report = inspectArchive(file);

      expect(report.abis, ['arm64-v8a', 'x86_64']);
      expect(report.failures.single.abi, 'x86_64');
    });

    test('un archivo sin librerías nativas NO se aprueba', () {
      // Si el APK debía llevar Vosk y no lleva ninguna `.so`, está mal
      // construido. Devolver «pasa» escondería justo eso.
      final file = archiveWith({
        'AndroidManifest.xml': Uint8List.fromList(utf8.encode('<manifest/>')),
      });

      final report = inspectArchive(file);

      expect(report.libraries, isEmpty);
      expect(report.passes, isFalse);
      expect(report.render(), contains('SIN LIBRERÍAS NATIVAS'));
    });

    test('una ABI que nadie pidió tumba el gate', () {
      // Medido de verdad: `ndk.abiFilters` no filtra las librerías que vienen
      // dentro de un AAR, y el APK de Vosk salió con armeabi-v7a y x86_64 pese
      // a construirse sólo para arm64. Con Flutter presente sólo en arm64, un
      // emulador x86_64 habría elegido esa ABI y la aplicación no arrancaría.
      final file = archiveWith({
        'lib/arm64-v8a/libvosk.so': elf(loadAlignments: [16384]),
        'lib/x86_64/libvosk.so': elf(loadAlignments: [16384]),
      });

      final report = inspectArchive(file, expectedAbis: const ['arm64-v8a']);

      expect(report.unexpectedAbis, ['x86_64']);
      expect(report.passes, isFalse);
      expect(report.render(), contains('ABIs que nadie pidió'));
    });

    test('sin lista de ABIs esperadas no se comprueba ninguna', () {
      final file = archiveWith({
        'lib/arm64-v8a/libvosk.so': elf(loadAlignments: [16384]),
        'lib/x86_64/libvosk.so': elf(loadAlignments: [16384]),
      });

      final report = inspectArchive(file);

      expect(report.unexpectedAbis, isEmpty);
      expect(report.passes, isTrue);
    });

    test('el informe recuerda que el ELF no es la prueba completa', () {
      final file = archiveWith({
        'lib/arm64-v8a/libvosk.so': elf(loadAlignments: [16384]),
      });

      final rendered = inspectArchive(file).render();

      expect(rendered, contains('zipalign'));
      expect(rendered, contains('PAGE_SIZE=16384'));
    });

    test('el JSON lleva el detalle por librería', () {
      final file = archiveWith({
        'lib/arm64-v8a/libvosk.so': elf(loadAlignments: [16384]),
      });

      final json = inspectArchive(file).toJson();

      expect(json['passes'], isTrue);
      expect(json['abis'], ['arm64-v8a']);
      final libraries = json['libraries']! as List<Object?>;
      final first = libraries.single! as Map<String, Object?>;
      expect(first['worstAlignment'], 16384);
      expect(first['compatible16k'], isTrue);
    });
  });
}
