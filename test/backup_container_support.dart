import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

/// Utilidades para inspeccionar un contenedor `.agrobackup` desde los tests.
///
/// La aplicación no necesita abrir un respaldo "a medias" —valida y restaura el
/// paquete entero—, así que estas funciones viven en los tests y no en
/// `BackupService`: sirven para comprobar qué se escribió realmente dentro,
/// que es justo lo que un test debe verificar y el código de producción no
/// tiene por qué exponer.

/// Nombres de las entradas del contenedor en [path].
List<String> entriesOf(String path) {
  final input = InputFileStream(path);
  try {
    return ZipDecoder()
        .decodeStream(input)
        .where((entry) => entry.isFile)
        .map((entry) => entry.name)
        .toList();
  } finally {
    input.closeSync();
  }
}

/// Contenido de la entrada [name] del contenedor, o `null` si no está.
List<int>? entryBytes(String path, String name) {
  final input = InputFileStream(path);
  try {
    for (final entry in ZipDecoder().decodeStream(input)) {
      if (entry.isFile && entry.name == name) return entry.readBytes();
    }
    return null;
  } finally {
    input.closeSync();
  }
}

/// Saca `database.db` del contenedor a un archivo temporal y devuelve su ruta.
Future<String> extractDatabaseFrom(String path) async {
  final bytes = entryBytes(path, 'database.db');
  if (bytes == null) {
    throw StateError('El contenedor $path no incluye database.db');
  }
  final directory = await Directory.systemTemp.createTemp('agro_probe_');
  final file = File(p.join(directory.path, 'database.db'));
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

/// Reescribe una entrada del contenedor con [bytes], para simular corrupción.
Future<void> rewriteEntry(String path, String name, List<int> bytes) async {
  final input = InputFileStream(path);
  final kept = <String, List<int>>{};
  try {
    for (final entry in ZipDecoder().decodeStream(input)) {
      if (!entry.isFile) continue;
      kept[entry.name] = entry.name == name
          ? bytes
          : (entry.readBytes() ?? const []);
    }
  } finally {
    input.closeSync();
  }

  final staging = await Directory.systemTemp.createTemp('agro_rewrite_');
  final encoder = ZipFileEncoder()..create(path);
  try {
    for (final entry in kept.entries) {
      final file = File(p.join(staging.path, p.basename(entry.key)));
      await file.writeAsBytes(entry.value, flush: true);
      await encoder.addFile(file, entry.key);
    }
  } finally {
    await encoder.close();
    await staging.delete(recursive: true);
  }
}

/// Elimina una entrada del contenedor, para simular un paquete incompleto.
Future<void> removeEntry(String path, String name) async {
  final input = InputFileStream(path);
  final kept = <String, List<int>>{};
  try {
    for (final entry in ZipDecoder().decodeStream(input)) {
      if (!entry.isFile || entry.name == name) continue;
      kept[entry.name] = entry.readBytes() ?? const [];
    }
  } finally {
    input.closeSync();
  }

  final staging = await Directory.systemTemp.createTemp('agro_rewrite_');
  final encoder = ZipFileEncoder()..create(path);
  try {
    for (final entry in kept.entries) {
      final file = File(p.join(staging.path, p.basename(entry.key)));
      await file.writeAsBytes(entry.value, flush: true);
      await encoder.addFile(file, entry.key);
    }
  } finally {
    await encoder.close();
    await staging.delete(recursive: true);
  }
}
