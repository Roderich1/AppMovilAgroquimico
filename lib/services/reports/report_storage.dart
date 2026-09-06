/// Frontera de almacenamiento de reportes (Lote G).
///
/// **No sabe qué contiene el archivo.** Recibe un nombre base, una extensión y
/// unos bytes. Ni el compositor ni los generadores tocan el disco, y este
/// archivo no sabe nada de inventarios ni de saldos: si mañana hubiera un
/// tercer formato, aquí no cambia nada.
///
/// Dos reglas que no se negocian:
///
/// 1. **Nunca queda un archivo final a medio escribir.** Se escribe primero un
///    temporal en la misma carpeta y sólo se publica el nombre definitivo
///    cuando la escritura terminó bien. Si algo falla, el temporal se borra.
/// 2. **Nunca se sobrescribe en silencio.** Si el nombre ya existe se añade un
///    sufijo determinista: `informe (2).csv`, `informe (3).csv`.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Dónde quedó el archivo, para poder decírselo al usuario.
class StoredReport {
  const StoredReport({
    required this.path,
    required this.fileName,
    required this.directory,
    required this.byteCount,
  });

  final String path;
  final String fileName;
  final String directory;
  final int byteCount;
}

/// Un reporte no se pudo guardar.
class ReportStorageException implements Exception {
  const ReportStorageException(this.message, [this.cause]);
  final String message;
  final Object? cause;
  @override
  String toString() => message;
}

/// Contrato de almacenamiento, para poder sustituirlo por un doble en pruebas.
abstract class ReportStorage {
  Future<StoredReport> save({
    required String baseName,
    required String extension,
    required Uint8List bytes,
  });

  /// Carpeta donde se guardarán los reportes, para poder nombrarla en la UI.
  Future<String> describeLocation();
}

/// Almacenamiento en la carpeta local de la aplicación.
///
/// Usa la misma resolución de carpeta que el respaldo —`getDownloadsDirectory`
/// y, si no existe, la de documentos— dentro de una subcarpeta `reportes`, para
/// no mezclar los `.csv`/`.pdf` con los `.agrobackup`.
///
/// No hay transporte de archivos: ni compartir, ni selector del sistema, ni
/// red. El archivo se queda en el teléfono.
class LocalReportStorage implements ReportStorage {
  LocalReportStorage({Future<Directory> Function()? directory})
    : _directory = directory ?? _defaultDirectory;

  static const String folderName = 'reportes';

  /// Extensiones admitidas. Una extensión libre permitiría escribir un `.db`
  /// o un `.apk` desde aquí.
  static const Set<String> allowedExtensions = {'csv', 'pdf'};

  static const String temporarySuffix = '.parcial';

  final Future<Directory> Function() _directory;

  static Future<Directory> _defaultDirectory() async {
    final base =
        await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    return Directory(p.join(base.path, folderName));
  }

  @override
  Future<String> describeLocation() async => (await _directory()).path;

  @override
  Future<StoredReport> save({
    required String baseName,
    required String extension,
    required Uint8List bytes,
  }) async {
    final safeExtension = extension.toLowerCase().replaceAll('.', '');
    if (!allowedExtensions.contains(safeExtension)) {
      throw ReportStorageException(
        'Formato de archivo no admitido: "$extension".',
      );
    }
    final safeBase = sanitizeFileName(baseName);

    final Directory directory;
    try {
      directory = await (await _directory()).create(recursive: true);
    } catch (error) {
      throw ReportStorageException(
        'No se pudo abrir la carpeta donde se guardan los reportes.',
        error,
      );
    }

    final target = await _freeName(directory, safeBase, safeExtension);
    final temporary = File('$target$temporarySuffix');

    try {
      // El temporal vive en la MISMA carpeta que el destino: así el paso final
      // es un renombrado dentro del mismo sistema de archivos y no una copia
      // que pueda quedarse a medias.
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(target);
    } catch (error) {
      await _deleteQuietly(temporary);
      throw ReportStorageException('No se pudo guardar el reporte.', error);
    }

    return StoredReport(
      path: target,
      fileName: p.basename(target),
      directory: directory.path,
      byteCount: bytes.length,
    );
  }

  /// Primer nombre libre: `base.ext`, `base (2).ext`, `base (3).ext`...
  ///
  /// Se comprueba también el temporal para no pisar una exportación que esté
  /// ocurriendo en ese momento.
  Future<String> _freeName(
    Directory directory,
    String base,
    String extension,
  ) async {
    for (var attempt = 1; attempt < 1000; attempt++) {
      final name = attempt == 1
          ? '$base.$extension'
          : '$base ($attempt).$extension';
      final candidate = p.join(directory.path, name);
      if (!await File(candidate).exists() &&
          !await File('$candidate$temporarySuffix').exists()) {
        return candidate;
      }
    }
    throw const ReportStorageException(
      'Hay demasiados reportes con ese nombre en la carpeta.',
    );
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Un temporal que no se puede borrar no debe tapar el error real que
      // llevó hasta aquí.
    }
  }
}

/// Nombre de archivo seguro a partir de un texto cualquiera.
///
/// Un nombre de campaña o de persona puede traer barras, dos puntos o
/// caracteres reservados en Windows y en Android. Se conservan letras,
/// dígitos, espacios, guiones y guiones bajos; el resto se sustituye por un
/// guion. Nunca devuelve una cadena vacía ni un nombre reservado del sistema.
String sanitizeFileName(String value) {
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    if (RegExp(r'[A-Za-z0-9 _-]').hasMatch(char)) {
      buffer.write(char);
    } else {
      buffer.write('-');
    }
  }
  var name = buffer
      .toString()
      .replaceAll(RegExp(r'-{2,}'), '-')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();
  // Windows no admite un nombre que termine en punto o espacio, y los puntos
  // iniciales esconden el archivo en Android. Los guiones de los extremos
  // también sobran: casi siempre son el rastro de un carácter sustituido.
  name = name.replaceAll(RegExp(r'^[.\-\s]+|[.\-\s]+$'), '');
  if (name.length > 80) name = name.substring(0, 80).trim();
  const reserved = {
    'CON',
    'PRN',
    'AUX',
    'NUL',
    'COM1',
    'COM2',
    'COM3',
    'COM4',
    'LPT1',
    'LPT2',
    'LPT3',
  };
  if (name.isEmpty || reserved.contains(name.toUpperCase())) {
    return 'reporte';
  }
  return name;
}
