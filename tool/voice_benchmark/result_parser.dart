/// Lectura de los archivos que exportan los teléfonos.
///
/// HERRAMIENTA DE DESARROLLO. Vive en `tool/` y no se compila dentro de la
/// aplicación.
///
/// Acepta el JSON y el CSV que produce el banco de pruebas. Un campo ausente
/// queda `null` y llega así al informe como `NOT_MEASURED`: el agregador nunca
/// rellena un hueco con cero.
library;

import 'dart:convert';

/// Una medición de una frase con un motor, tal como la exportó el teléfono.
class BenchRecord {
  const BenchRecord({
    required this.sampleId,
    required this.split,
    required this.intent,
    required this.expectedText,
    required this.engine,
    required this.airplaneMode,
    this.obtainedText,
    this.model = '',
    this.requestedLocale = '',
    this.effectiveLocale,
    this.device = '',
    this.androidRelease = '',
    this.androidSdk,
    this.partialLatencyMs,
    this.finalLatencyMs,
    this.audioDurationMs,
    this.memoryBytes,
    this.errorCode,
    this.errorDetail,
    this.attempt = 1,
    this.notes,
    this.transcriptRedacted = false,
  });

  final String sampleId;
  final String split;
  final String intent;
  final String expectedText;
  final String? obtainedText;
  final String engine;
  final String model;
  final String requestedLocale;
  final String? effectiveLocale;
  final String device;
  final String androidRelease;
  final int? androidSdk;
  final bool airplaneMode;
  final int? partialLatencyMs;
  final int? finalLatencyMs;
  final int? audioDurationMs;
  final int? memoryBytes;
  final String? errorCode;
  final String? errorDetail;
  final int attempt;
  final String? notes;
  final bool transcriptRedacted;

  /// Hubo transcripción utilizable.
  bool get succeeded => errorCode == null && (obtainedText ?? '').isNotEmpty;

  /// La transcripción no puede evaluarse porque se quitó a propósito.
  bool get comparable => !transcriptRedacted && succeeded;
}

/// Error de lectura con contexto suficiente para arreglar el archivo.
class BenchParseException implements Exception {
  const BenchParseException(this.message);

  final String message;

  @override
  String toString() => 'BenchParseException: $message';
}

/// Convierte el contenido de un archivo exportado en mediciones.
abstract final class BenchResultParser {
  /// Detecta el formato por el contenido, no por la extensión: un archivo
  /// renombrado a mano no debe romper el informe.
  static List<BenchRecord> parse(String source) {
    final trimmed = source.trimLeft();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      return parseJson(source);
    }
    return parseCsv(source);
  }

  static List<BenchRecord> parseJson(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw BenchParseException('JSON inválido: ${e.message}');
    }

    final List<Object?> rows;
    Map<String, Object?> envelope = const {};
    if (decoded is List) {
      rows = decoded;
    } else if (decoded is Map<String, Object?>) {
      envelope = decoded;
      final results = decoded['results'];
      if (results is! List) {
        throw const BenchParseException('El JSON no trae la lista "results".');
      }
      rows = results;
    } else {
      throw const BenchParseException('El JSON no es un objeto ni una lista.');
    }

    return rows
        .map((row) {
          if (row is! Map) {
            throw const BenchParseException('Un resultado no es un objeto.');
          }
          return _fromMap(row.cast<String, Object?>(), envelope);
        })
        .toList(growable: false);
  }

  static List<BenchRecord> parseCsv(String source) {
    final rows = _csvRows(source);
    if (rows.isEmpty) return const [];

    final header = rows.first;
    return rows
        .skip(1)
        .where((r) => r.any((c) => c.isNotEmpty))
        .map((row) {
          final map = <String, Object?>{};
          for (var i = 0; i < header.length && i < row.length; i++) {
            map[header[i]] = row[i].isEmpty ? null : row[i];
          }
          return _fromMap(map, const {});
        })
        .toList(growable: false);
  }

  static BenchRecord _fromMap(
    Map<String, Object?> row,
    Map<String, Object?> envelope,
  ) {
    String text(String key, {String fallback = ''}) {
      final value = row[key] ?? envelope[key];
      return value == null ? fallback : '$value';
    }

    final sampleId = text('sampleId');
    if (sampleId.isEmpty) {
      throw const BenchParseException('Hay un resultado sin `sampleId`.');
    }

    return BenchRecord(
      sampleId: sampleId,
      split: text('split', fallback: 'desconocido'),
      intent: text('intent', fallback: 'desconocido'),
      expectedText: text('expectedText'),
      obtainedText: _optionalText(row['obtainedText']),
      engine: text('engine', fallback: 'desconocido'),
      model: text('model'),
      requestedLocale: text('requestedLocale'),
      effectiveLocale: _optionalText(row['effectiveLocale']),
      device: text('device'),
      androidRelease: text('androidRelease'),
      androidSdk: _optionalInt(row['androidSdk'] ?? envelope['androidSdk']),
      airplaneMode: _bool(row['airplaneMode']),
      partialLatencyMs: _optionalInt(row['partialLatencyMs']),
      finalLatencyMs: _optionalInt(row['finalLatencyMs']),
      audioDurationMs: _optionalInt(row['audioDurationMs']),
      memoryBytes: _optionalInt(row['memoryBytes']),
      errorCode: _optionalText(row['errorCode']),
      errorDetail: _optionalText(row['errorDetail']),
      attempt: _optionalInt(row['attempt']) ?? 1,
      notes: _optionalText(row['notes']),
      transcriptRedacted: _bool(row['transcriptRedacted']),
    );
  }

  static String? _optionalText(Object? value) {
    if (value == null) return null;
    final text = '$value';
    return text.isEmpty ? null : text;
  }

  static int? _optionalInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse('$value'.trim());
  }

  static bool _bool(Object? value) {
    if (value is bool) return value;
    final text = '$value'.trim().toLowerCase();
    return text == 'true' || text == '1' || text == 'si' || text == 'sí';
  }

  /// Lector de CSV con comillas, comas dentro de celda y saltos de línea.
  static List<List<String>> _csvRows(String source) {
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var quoted = false;

    for (var i = 0; i < source.length; i++) {
      final char = source[i];
      if (quoted) {
        if (char == '"') {
          if (i + 1 < source.length && source[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          cell.write(char);
        }
        continue;
      }
      switch (char) {
        case '"':
          quoted = true;
        case ',':
          row.add(_unescape(cell.toString()));
          cell.clear();
        case '\r':
          break;
        case '\n':
          row.add(_unescape(cell.toString()));
          cell.clear();
          rows.add(row);
          row = <String>[];
        default:
          cell.write(char);
      }
    }
    if (cell.isNotEmpty || row.isNotEmpty) {
      row.add(_unescape(cell.toString()));
      rows.add(row);
    }
    return rows;
  }

  /// Deshace la neutralización de fórmulas que aplica el exportador.
  static String _unescape(String cell) =>
      cell.startsWith("'=") || cell.startsWith("'+") || cell.startsWith("'@")
      ? cell.substring(1)
      : cell;
}
