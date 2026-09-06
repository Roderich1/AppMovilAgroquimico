// Generador del archivo SQLite de auditoría de interfaz.
//
// HERRAMIENTA DE DESARROLLO. No se compila dentro de la aplicación y no forma parte
// de la suite: `flutter test` sin argumentos solo recorre `test/**_test.dart`, y este
// archivo vive en `tool/`. Se ejecuta explícitamente:
//
//     flutter test tool/seed_ui_audit.dart
//
// Usa el arnés de `flutter test` únicamente porque `AppDatabase` importa
// `package:flutter/foundation.dart`, de modo que `dart run` no puede cargarlo.
//
// Produce siempre el mismo archivo desde cero (RESET + SEED):
//
//     build/ui_audit/agroquimicos_v2.db
//
// que luego se instala en el emulador con `tool/ui_audit_push.sh`.
//
// La ruta se resuelve a **absoluta** de forma deliberada: `sqflite_common_ffi`
// reubica las rutas relativas bajo `.dart_tool/sqflite_common_ffi/databases/`,
// con lo que el RESET no borraría el archivo que realmente se abre y las
// ejecuciones se irían acumulando unas sobre otras.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test/support/ui_audit_seed.dart';

/// Ruta de la fotografía de factura **dentro del dispositivo Android**.
/// Coincide con lo que devolvería `getApplicationDocumentsDirectory()` en la app.
const String deviceInvoicePath =
    '/data/user/0/com.comunidad.agro.agroquimicos/app_flutter/invoices/'
    'invoice_ui_audit.png';

void main() {
  sqfliteFfiInit();

  test('genera build/ui_audit/agroquimicos_v2.db', () async {
    final outputDir = Directory(
      p.join(Directory.current.path, 'build', 'ui_audit'),
    );
    // RESET: el generador nunca acumula sobre una ejecución anterior.
    if (outputDir.existsSync()) {
      outputDir.deleteSync(recursive: true);
    }
    outputDir.createSync(recursive: true);
    final outputPath = p.join(outputDir.path, 'agroquimicos_v2.db');

    final database = AppDatabase(factory: databaseFactoryFfi, path: outputPath);
    final repo = AgroRepository(database);

    final result = await seedUiAudit(repo, invoiceImagePath: deviceInvoicePath);

    // Comprobaciones de que el dataset quedó como se esperaba. Si una regla de
    // negocio cambia y el dataset deja de ser representativo, esto falla en vez
    // de producir una auditoría sobre datos silenciosamente incompletos.
    final db = await database.database;
    Future<int> count(String table) async =>
        (await db.rawQuery('SELECT COUNT(*) c FROM $table')).first['c']! as int;

    expect(await count('persons'), 7);
    expect(await count('products'), 22);
    expect(await count('farms'), 8);
    expect(await count('campaigns'), 3);
    expect(await count('purchases'), 10);
    expect(await count('application_plans'), 5);
    expect(await count('applications'), 12);
    expect(await count('transfers'), 7);

    // Un producto comprado y consumido por completo, y otro nunca comprado:
    // ambos deben seguir apareciendo en los reportes, en cero.
    final summary = await repo.inventorySummary();
    expect(
      summary.where((row) => (row['available_base'] as int) == 0),
      isNotEmpty,
      reason: 'El dataset debe incluir productos con stock cero.',
    );

    await database.close();

    final bytes = File(outputPath).lengthSync();
    stdout.writeln('');
    stdout.writeln('=== DATASET DE AUDITORÍA GENERADO ===');
    stdout.writeln('Archivo: $outputPath  ($bytes bytes)');
    for (final entry in result.counts.entries) {
      stdout.writeln('  ${entry.key.padRight(28)} ${entry.value}');
    }
    final imagePath = p.join(outputDir.path, 'invoice_ui_audit.png');
    File(imagePath).writeAsBytesSync(_buildInvoicePng());
    stdout.writeln('Imagen:  $imagePath');
    stdout.writeln('Esquema: v${AppDatabase.schemaVersion}');
    stdout.writeln('');
  });
}

/// Genera una fotografia de factura sintetica (PNG 900x1200, sin dependencias
/// externas) para que el visor de facturas tenga algo real que mostrar y se
/// pueda auditar el zoom del `InteractiveViewer`.
///
/// No es una factura real ni contiene informacion de nadie: son bandas de color
/// con un marco, suficientes para distinguir orientacion, recorte y escala.
Uint8List _buildInvoicePng() {
  const width = 900;
  const height = 1200;
  final raw = BytesBuilder();
  for (var y = 0; y < height; y++) {
    raw.addByte(0); // filtro "None" para esta linea
    for (var x = 0; x < width; x++) {
      final border = x < 12 || y < 12 || x >= width - 12 || y >= height - 12;
      final band = (y ~/ 90).isEven;
      if (border) {
        raw
          ..addByte(20)
          ..addByte(40)
          ..addByte(60);
      } else if (band) {
        raw
          ..addByte(245)
          ..addByte(243)
          ..addByte(235);
      } else {
        raw
          ..addByte(214)
          ..addByte(224)
          ..addByte(214);
      }
    }
  }
  final png = BytesBuilder()..add(const [137, 80, 78, 71, 13, 10, 26, 10]);
  final ihdr = BytesBuilder()
    ..add(_u32(width))
    ..add(_u32(height))
    ..add(const [8, 2, 0, 0, 0]);
  png.add(_chunk('IHDR', ihdr.takeBytes()));
  png.add(_chunk('IDAT', ZLibCodec(level: 6).encode(raw.takeBytes())));
  png.add(_chunk('IEND', Uint8List(0)));
  return png.takeBytes();
}

List<int> _u32(int value) => [
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

List<int> _chunk(String type, List<int> data) {
  final body = <int>[...ascii.encode(type), ...data];
  return <int>[..._u32(data.length), ...body, ..._u32(_crc32(body))];
}

int _crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}
