/// Genera la comparación de motores a partir de lo que exportaron los teléfonos.
///
/// HERRAMIENTA DE DESARROLLO. No se compila dentro de la aplicación.
///
///     dart run tool/voice_benchmark/main.dart <archivo|carpeta> [...]
///     dart run tool/voice_benchmark/main.dart resultados/ -o informe.md
///
/// Acepta los `.json` y `.csv` que produce el banco de pruebas. Lee el corpus
/// **con el que se dictó cada tanda** —lo dice el propio archivo exportado—
/// para saber qué datos críticos debían sobrevivir a cada frase.
///
/// Se niega a generar el informe si lo que se le pasa no es comparable entre sí:
/// dos corpus, dos versiones, dos digests, dos particiones, dos modelos bajo el
/// mismo candidato o un candidato mal etiquetado. Ver `comparison_guard.dart`.
library;

import 'dart:convert';
import 'dart:io';

import 'aggregator.dart';
import 'comparison_guard.dart';
import 'report.dart';
import 'result_parser.dart';

/// Dónde vive cada corpus, por su identificador.
///
/// Los datos críticos que se exigen a cada frase salen del corpus con el que se
/// dictó. Leerlos siempre del de la Fase 0, como se hacía antes, daría cero
/// aciertos para toda corrida del corpus híbrido —los identificadores no
/// coinciden— y esa columna aparecería como si el motor hubiera fallado.
const _corpusPaths = <String, String>{
  'fase0': 'benchmark/voice_benchmark/assets/corpus.json',
  'hibrido-ag': 'benchmark/voice_benchmark/assets/corpus_hybrid.json',
};

/// El de la Fase 0, para las tandas que no dicen de qué corpus salieron.
const _corpusPathHistorico = 'benchmark/voice_benchmark/assets/corpus.json';

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

  // Antes de resumir nada: ¿esto se puede comparar entre sí? Poner dos corpus
  // en la misma tabla presenta como diferencia entre motores lo que es
  // diferencia entre exámenes.
  final verdict = ComparisonGuard.check(unique);
  if (!verdict.comparable) {
    stderr.writeln();
    stderr.writeln('NO SE GENERA EL INFORME: estas mediciones no son');
    stderr.writeln('comparables entre sí.');
    for (final rejection in verdict.rejections) {
      stderr.writeln('  · ${rejection.detail}');
    }
    stderr.writeln();
    stderr.writeln(
      'Pase por separado los archivos de cada corpus, versión, digest y '
      'partición. Comparar dos exámenes distintos y llamarlo comparación de '
      'motores es el defecto que esta guarda existe para impedir.',
    );
    exitCode = 65;
    return;
  }
  if (verdict.identityMissing) {
    stdout.writeln(
      'AVISO: ninguna medición dice de qué corpus salió. Son tandas anteriores '
      'a la identidad de corpus (Fase 0) y el informe lo hace constar.',
    );
  }

  final summaries = BenchAggregator.summarize(
    unique,
    criticalSlots: loadCriticalSlots(File(_corpusFor(unique))),
  );
  final markdown = BenchReport.render(
    summaries,
    corpusId: unique.first.corpusId,
    corpusVersion: unique.first.corpusVersion,
    corpusDigest: unique.first.corpusDigest,
    partition: unique.first.partition,
    identityMissing: verdict.identityMissing,
  );

  if (output == null) {
    stdout.writeln();
    stdout.writeln(markdown);
  } else {
    File(output).writeAsStringSync(markdown);
    stdout.writeln('informe escrito en $output');
  }
}

/// Corpus con el que se dictaron estas mediciones.
///
/// La guarda ya garantizó que todas vienen del mismo; basta con mirar la
/// primera. Un `corpusId` desconocido cae en el histórico y la columna de datos
/// críticos quedará vacía, que es lo correcto: no se sabe qué debía escucharse.
String _corpusFor(List<BenchRecord> records) =>
    _corpusPaths[records.first.corpusId] ?? _corpusPathHistorico;

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
