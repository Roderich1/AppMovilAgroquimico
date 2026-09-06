/// Genera la comparación de motores a partir de lo que exportaron los teléfonos.
///
/// HERRAMIENTA DE DESARROLLO. No se compila dentro de la aplicación.
///
///     dart run tool/voice_benchmark/main.dart <archivo|carpeta> [...]
///     dart run tool/voice_benchmark/main.dart resultados/ -o informe.md
///
/// Acepta los `.json` y `.csv` que produce el banco de pruebas. Lee el corpus
/// desde `benchmark/voice_benchmark/assets/corpus.json` para saber qué datos
/// críticos debían sobrevivir a cada frase.
library;

import 'dart:convert';
import 'dart:io';

import 'aggregator.dart';
import 'report.dart';
import 'result_parser.dart';

const _corpusPath = 'benchmark/voice_benchmark/assets/corpus.json';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'Uso: dart run tool/voice_benchmark/main.dart <archivo|carpeta> '
      '[...] [-o salida.md]',
    );
    exitCode = 64;
    return;
  }

  String? output;
  final inputs = <String>[];
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '-o' && i + 1 < args.length) {
      output = args[++i];
    } else {
      inputs.add(args[i]);
    }
  }

  final files = _collect(inputs);
  if (files.isEmpty) {
    stderr.writeln(
      'No se encontró ningún .json ni .csv en: ${inputs.join(", ")}',
    );
    exitCode = 66;
    return;
  }

  final records = <BenchRecord>[];
  for (final file in files) {
    try {
      records.addAll(BenchResultParser.parse(file.readAsStringSync()));
      stdout.writeln('leído: ${file.path}');
    } on BenchParseException catch (e) {
      // Un archivo roto no invalida los demás, pero tiene que verse.
      stderr.writeln('OMITIDO ${file.path}: ${e.message}');
      exitCode = 65;
    }
  }

  if (records.isEmpty) {
    stderr.writeln('Ningún archivo aportó mediciones.');
    exitCode = 66;
    return;
  }

  final unique = deduplicate(records);
  final repeated = records.length - unique.length;
  if (repeated > 0) {
    // Caso normal: la misma tanda exportada en JSON y en CSV, ambos archivos en
    // la carpeta. Se avisa en vez de callar, porque el propietario tiene que
    // poder confirmar que el descarte era el esperado.
    stdout.writeln(
      'descartadas $repeated mediciones repetidas '
      '(el mismo resultado leído en más de un archivo).',
    );
  }

  final summaries = BenchAggregator.summarize(
    unique,
    criticalSlots: loadCriticalSlots(File(_corpusPath)),
  );
  final markdown = BenchReport.render(summaries);

  if (output == null) {
    stdout.writeln();
    stdout.writeln(markdown);
  } else {
    File(output).writeAsStringSync(markdown);
    stdout.writeln('informe escrito en $output');
  }
}

/// Quita las mediciones leídas más de una vez, conservando el orden.
///
/// Se compara por [BenchRecord.identity], no por el archivo de origen: lo que
/// importa es si describe la misma toma, no dónde estaba guardada.
List<BenchRecord> deduplicate(List<BenchRecord> records) {
  final seen = <String>{};
  return records.where((r) => seen.add(r.identity)).toList(growable: false);
}

/// Datos críticos por frase, según el corpus.
///
/// Si el corpus no está donde se espera, devuelve vacío: la columna quedará como
/// `NOT_MEASURED` en lugar de inventar qué debía escucharse.
CriticalSlots loadCriticalSlots(File corpus) {
  if (!corpus.existsSync()) return const {};
  final json = jsonDecode(corpus.readAsStringSync()) as Map<String, Object?>;
  final samples = json['samples'];
  if (samples is! List) return const {};

  final slots = <String, List<String>>{};
  for (final sample in samples) {
    if (sample is! Map) continue;
    final id = sample['id'];
    final values = sample['slots'];
    if (id is! String || values is! Map) continue;
    slots[id] = values.values
        .map((v) => '$v')
        // Un valor con `|` describe varios productos de una misma frase.
        .expand((v) => v.split('|'))
        .where((v) => v.isNotEmpty)
        .toList(growable: false);
  }
  return slots;
}

List<File> _collect(List<String> inputs) {
  final files = <File>[];
  for (final input in inputs) {
    final directory = Directory(input);
    if (directory.existsSync()) {
      files.addAll(
        directory.listSync(recursive: true).whereType<File>().where(_isResult),
      );
      continue;
    }
    final file = File(input);
    if (file.existsSync()) files.add(file);
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

bool _isResult(File file) =>
    file.path.endsWith('.json') || file.path.endsWith('.csv');
