import 'dart:convert';

import 'bench_result.dart';

/// Una tanda de mediciones exportable.
///
/// La cabecera repite la identidad que ya lleva cada fila. No es redundancia
/// inútil: el JSON se lee entero y el CSV se corta, se filtra y se pega en una
/// hoja, y hace falta que las dos formas digan lo mismo por separado.
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
    this.corpusId = '',
    this.corpusDigest = '',
    this.partition = '',
    this.candidateId = '',
    this.partialEngine,
    this.finalEngine = '',
    this.modelHashes = const <String, String>{},
    this.benchCommit = '',
  });

  final String engine;
  final String model;
  final String device;
  final String androidRelease;
  final int androidSdk;
  final String abi;

  /// Corpus con el que se dictó la tanda entera.
  final String corpusId;
  final String corpusVersion;
  final String corpusDigest;
  final String partition;

  final String candidateId;
  final String? partialEngine;
  final String finalEngine;
  final Map<String, String> modelHashes;

  /// Commit del banco con el que se construyó el APK.
  final String benchCommit;

  final String appVersion;
  final List<BenchResult> results;
  final String? notes;

  /// Copia sin transcripciones, para cuando el dictado incluyó datos reales.
  ///
  /// Quita el texto y **nada más**. Sin corpus, digest ni candidato, la tanda
  /// dejaría de ser una medición para pasar a ser un puñado de latencias.
  BenchRun withoutTranscripts() => BenchRun(
    engine: engine,
    model: model,
    device: device,
    androidRelease: androidRelease,
    androidSdk: androidSdk,
    abi: abi,
    corpusId: corpusId,
    corpusVersion: corpusVersion,
    corpusDigest: corpusDigest,
    partition: partition,
    candidateId: candidateId,
    partialEngine: partialEngine,
    finalEngine: finalEngine,
    modelHashes: modelHashes,
    benchCommit: benchCommit,
    appVersion: appVersion,
    notes: notes,
    results: results.map((r) => r.redacted()).toList(growable: false),
  );

  Map<String, Object?> toJson() => {
    'schema': 'evolution-3-voice-benchmark',
    // Sube a 2 porque las filas traen identidad de corpus y de candidato. El
    // agregador distingue por este número las tandas de la Fase 0, que no la
    // llevan, de las nuevas.
    'schemaVersion': 2,
    'engine': engine,
    'model': model,
    'device': device,
    'androidRelease': androidRelease,
    'androidSdk': androidSdk,
    'abi': abi,
    'corpusId': corpusId,
    'corpusVersion': corpusVersion,
    'corpusDigest': corpusDigest,
    'partition': partition,
    'candidateId': candidateId,
    'partialEngine': partialEngine,
    'finalEngine': finalEngine,
    'modelHashes': modelHashes,
    'benchCommit': benchCommit,
    'appVersion': appVersion,
    'notes': notes,
    'exportedAt': DateTime.now().toIso8601String(),
    'results': results.map((r) => r.toJson()).toList(growable: false),
  };
}

/// Columnas del CSV, en orden. El agregador depende de estos nombres.
abstract final class BenchExportColumns {
  static const csv = <String>[
    'sampleId',
    'split',
    'partition',
    'intent',
    'expectedText',
    'obtainedText',
    'engine',
    'model',
    'corpusId',
    'corpusVersion',
    'corpusDigest',
    'candidateId',
    'partialEngine',
    'finalEngine',
    'modelHashes',
    'benchCommit',
    'abi',
    'requestedLocale',
    'effectiveLocale',
    'device',
    'androidRelease',
    'androidSdk',
    'airplaneMode',
    'systemAirplaneMode',
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
}

/// Serializa una tanda a JSON o CSV.
///
/// El JSON es la entrada del agregador del repositorio; el CSV existe para poder
/// abrir los resultados en una planilla sin herramientas.
abstract final class BenchExport {
  /// Columnas del CSV, en orden.
  static const csvHeader = BenchExportColumns.csv;

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
    // Un mapa en una celda se escribe `modelo=hash;modelo=hash`. Es legible en
    // una planilla y el agregador lo vuelve a partir sin ambigüedad: ni los
    // nombres de modelo ni los hashes contienen `=` ni `;`.
    var text = value is Map
        ? value.entries.map((e) => '${e.key}=${e.value}').join(';')
        : '$value';
    if (text.isNotEmpty && (text.startsWith(RegExp(r'''[=+\-@\t\r]''')))) {
      text = "'$text";
    }
    if (text.contains(RegExp('[",\n\r]'))) {
      text = '"${text.replaceAll('"', '""')}"';
    }
    return text;
  }
}
