import 'dart:convert';

import 'bench_result.dart';

/// Una tanda de mediciones exportable.
final class BenchRun {
  const BenchRun({
    required this.engine,
    required this.model,
    required this.device,
    required this.androidRelease,
    required this.androidSdk,
    required this.corpusVersion,
    required this.appVersion,
    required this.results,
    this.abi = '',
    this.notes,
  });

  final String engine;
  final String model;
  final String device;
  final String androidRelease;
  final int androidSdk;
  final String abi;
  final String corpusVersion;
  final String appVersion;
  final List<BenchResult> results;
  final String? notes;

  /// Copia sin transcripciones, para cuando el dictado incluyó datos reales.
  BenchRun withoutTranscripts() => BenchRun(
    engine: engine,
    model: model,
    device: device,
    androidRelease: androidRelease,
    androidSdk: androidSdk,
    abi: abi,
    corpusVersion: corpusVersion,
    appVersion: appVersion,
    notes: notes,
    results: results.map((r) => r.redacted()).toList(growable: false),
  );

  Map<String, Object?> toJson() => {
    'schema': 'evolution-3-voice-benchmark',
    'schemaVersion': 1,
    'engine': engine,
    'model': model,
    'device': device,
    'androidRelease': androidRelease,
    'androidSdk': androidSdk,
    'abi': abi,
    'corpusVersion': corpusVersion,
    'appVersion': appVersion,
    'notes': notes,
    'exportedAt': DateTime.now().toIso8601String(),
    'results': results.map((r) => r.toJson()).toList(growable: false),
  };
}

/// Serializa una tanda a JSON o CSV.
///
/// El JSON es la entrada del agregador del repositorio; el CSV existe para poder
/// abrir los resultados en una planilla sin herramientas.
abstract final class BenchExport {
  /// Columnas del CSV, en orden. El agregador depende de estos nombres.
  static const csvHeader = <String>[
    'sampleId',
    'split',
    'intent',
    'expectedText',
    'obtainedText',
    'engine',
    'model',
    'requestedLocale',
    'effectiveLocale',
    'device',
    'androidRelease',
    'androidSdk',
    'airplaneMode',
    'startedAt',
    'partialLatencyMs',
    'finalLatencyMs',
    'audioDurationMs',
    'memoryBytes',
    'errorCode',
    'errorDetail',
    'attempt',
    'notes',
    'transcriptRedacted',
  ];

  static String toJsonString(BenchRun run) =>
      const JsonEncoder.withIndent('  ').convert(run.toJson());

  static String toCsv(BenchRun run) {
    final buffer = StringBuffer()..writeln(csvHeader.map(_cell).join(','));
    for (final r in run.results) {
      final json = r.toJson();
      buffer.writeln(csvHeader.map((c) => _cell(json[c])).join(','));
    }
    return buffer.toString();
  }

  /// Escapa una celda y **neutraliza** las que una planilla interpretaría como
  /// fórmula.
  ///
  /// Misma regla que la exportación de EVOLUTION-2: una transcripción empieza
  /// por donde el motor quiera, y `=`, `+`, `-` o `@` al principio convierten el
  /// dato en código ejecutable al abrir el archivo.
  static String _cell(Object? value) {
    if (value == null) return '';
    var text = '$value';
    if (text.isNotEmpty && (text.startsWith(RegExp(r'''[=+\-@\t\r]''')))) {
      text = "'$text";
    }
    if (text.contains(RegExp('[",\n\r]'))) {
      text = '"${text.replaceAll('"', '""')}"';
    }
    return text;
  }
}
