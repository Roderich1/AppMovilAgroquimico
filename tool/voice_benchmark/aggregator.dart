/// Agregación de las mediciones de los teléfonos.
///
/// HERRAMIENTA DE DESARROLLO. Vive en `tool/` y no se compila dentro de la
/// aplicación.
///
/// ## Regla que gobierna todo este archivo
///
/// Ninguna métrica se inventa. Si una tanda no trae el dato, el resumen dice
/// `NOT_MEASURED` y explica por qué. Un cero y un "no medido" significan cosas
/// distintas y confundirlos es lo que llevaría a elegir mal el motor.
library;

import 'result_parser.dart';
// Con prefijo: `comparable` tambien es una propiedad de `BenchRecord` y sin el
// prefijo el codigo se leeria ambiguo.
import 'text_normalizer.dart' as text;

/// Métricas que la Fase 0 **no puede** producir, con su razón.
///
/// La Fase 0 mide transcripción. La intención, la completitud del borrador y la
/// falsa aceptación son propiedades del intérprete tipado (`EVO-010`), que
/// todavía no existe: declararlas aquí sería inventarlas.
const metricasNoMedibles = <String, String>{
  'exactitudDeIntencion':
      'Requiere el clasificador de EVO-010, que no está implementado.',
  'draftCompleto':
      'Requiere los borradores tipados de EVO-010 y sus validadores.',
  'falsaAceptacion':
      'Se define sobre un borrador marcado como listo; sin EVO-010 no existe '
      'ese estado y medirlo sobre texto crudo daría un número falso.',
};

/// Resumen de un motor sobre un dispositivo.
class EngineSummary {
  const EngineSummary({
    required this.engine,
    required this.model,
    required this.device,
    required this.androidRelease,
    required this.androidSdk,
    required this.split,
    required this.total,
    required this.withResult,
    required this.failed,
    required this.redacted,
    required this.exactMatches,
    required this.criticalTokenHits,
    required this.criticalTokenTotal,
    required this.airplaneRuns,
    required this.errorCounts,
    required this.localeFallbacks,
    this.medianWer,
    this.partialP50,
    this.partialP95,
    this.finalP50,
    this.finalP95,
    this.peakMemoryBytes,
  });

  final String engine;
  final String model;
  final String device;
  final String androidRelease;
  final int? androidSdk;
  final String split;

  /// Mediciones leídas.
  final int total;

  /// Mediciones con transcripción utilizable.
  final int withResult;

  /// Mediciones que terminaron en error.
  final int failed;

  /// Mediciones cuya transcripción se quitó antes de exportar.
  final int redacted;

  /// Transcripciones idénticas a lo dictado, ya normalizadas.
  final int exactMatches;

  /// Palabras críticas presentes en la transcripción.
  final int criticalTokenHits;
  final int criticalTokenTotal;

  final int airplaneRuns;

  /// Cuántas veces apareció cada código de error.
  final Map<String, int> errorCounts;

  /// Mediciones donde el motor escuchó en un locale distinto del pedido.
  final int localeFallbacks;

  final double? medianWer;
  final int? partialP50;
  final int? partialP95;
  final int? finalP50;
  final int? finalP95;
  final int? peakMemoryBytes;

  /// Proporción de transcripciones exactas sobre las comparables.
  double? get exactMatchRate =>
      withResult == 0 ? null : exactMatches / withResult;

  /// Proporción de datos críticos que sobrevivieron a la transcripción.
  double? get criticalTokenRate =>
      criticalTokenTotal == 0 ? null : criticalTokenHits / criticalTokenTotal;

  /// Clave que identifica la combinación medida.
  String get key => '$engine|$device|$split';
}

/// Datos críticos esperados por frase, tomados del corpus.
typedef CriticalSlots = Map<String, List<String>>;

abstract final class BenchAggregator {
  /// Agrupa por motor, dispositivo y corpus, y resume cada grupo.
  ///
  /// [criticalSlots] mapea `sampleId` a las palabras que deben sobrevivir
  /// (producto, cantidad, precio…). Si no se pasa, esa métrica queda sin medir.
  static List<EngineSummary> summarize(
    List<BenchRecord> records, {
    CriticalSlots criticalSlots = const {},
  }) {
    final groups = <String, List<BenchRecord>>{};
    for (final record in records) {
      final key = '${record.engine}|${record.device}|${record.split}';
      groups.putIfAbsent(key, () => <BenchRecord>[]).add(record);
    }

    final summaries = groups.values
        .map((group) => _summarizeGroup(group, criticalSlots))
        .toList();
    summaries.sort((a, b) => a.key.compareTo(b.key));
    return summaries;
  }

  static EngineSummary _summarizeGroup(
    List<BenchRecord> group,
    CriticalSlots criticalSlots,
  ) {
    final first = group.first;
    final comparables = group.where((r) => r.comparable).toList();

    var exact = 0;
    var criticalHits = 0;
    var criticalTotal = 0;
    final wers = <double>[];

    for (final record in comparables) {
      final obtained = record.obtainedText!;
      if (text.comparable(record.expectedText) == text.comparable(obtained)) {
        exact++;
      }
      wers.add(text.wordErrorRate(record.expectedText, obtained));

      for (final needle in criticalSlots[record.sampleId] ?? const <String>[]) {
        // `AMBIGUO` marca un dato que NO debe resolverse: no es una palabra que
        // deba aparecer en la transcripción.
        if (needle == 'AMBIGUO') continue;
        criticalTotal++;
        if (text.containsAllTokens(obtained, needle)) criticalHits++;
      }
    }

    final errorCounts = <String, int>{};
    for (final record in group) {
      final code = record.errorCode;
      if (code != null) errorCounts[code] = (errorCounts[code] ?? 0) + 1;
    }

    return EngineSummary(
      engine: first.engine,
      model: first.model,
      device: first.device,
      androidRelease: first.androidRelease,
      androidSdk: first.androidSdk,
      split: first.split,
      total: group.length,
      withResult: comparables.length,
      failed: group.where((r) => r.errorCode != null).length,
      redacted: group.where((r) => r.transcriptRedacted).length,
      exactMatches: exact,
      criticalTokenHits: criticalHits,
      criticalTokenTotal: criticalTotal,
      airplaneRuns: group.where((r) => r.airplaneMode).length,
      errorCounts: errorCounts,
      localeFallbacks: group
          .where(
            (r) =>
                r.effectiveLocale != null &&
                r.effectiveLocale != r.requestedLocale,
          )
          .length,
      medianWer: wers.isEmpty ? null : percentileDouble(wers, 50),
      partialP50: percentile(group.map((r) => r.partialLatencyMs), 50),
      partialP95: percentile(group.map((r) => r.partialLatencyMs), 95),
      finalP50: percentile(group.map((r) => r.finalLatencyMs), 50),
      finalP95: percentile(group.map((r) => r.finalLatencyMs), 95),
      peakMemoryBytes: _max(group.map((r) => r.memoryBytes)),
    );
  }

  static int? _max(Iterable<int?> values) {
    final present = values.whereType<int>().toList();
    if (present.isEmpty) return null;
    return present.reduce((a, b) => a > b ? a : b);
  }
}

/// Percentil [p] de una serie de enteros. `null` si nadie lo midió.
///
/// Devolver `null` en vez de `0` es deliberado: un motor sin parciales no tiene
/// latencia parcial cero, no tiene latencia parcial.
int? percentile(Iterable<int?> values, int p) {
  final present = values.whereType<int>().toList()..sort();
  if (present.isEmpty) return null;
  return present[_percentileIndex(present.length, p)];
}

double? percentileDouble(Iterable<double> values, int p) {
  final present = values.toList()..sort();
  if (present.isEmpty) return null;
  return present[_percentileIndex(present.length, p)];
}

/// Índice del percentil por **rango cercano**: el menor valor que deja al menos
/// el `p %` de la serie por debajo.
///
/// Se elige esta definición, y no una interpolación, porque con pocas muestras
/// (una tanda de corpus por teléfono) interpolar inventa un valor intermedio que
/// nadie midió.
int _percentileIndex(int length, int p) {
  final rank = (p / 100 * length).ceil();
  return (rank - 1).clamp(0, length - 1);
}
