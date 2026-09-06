/// Renderizado del informe comparativo del benchmark de voz.
///
/// HERRAMIENTA DE DESARROLLO. Vive en `tool/` y no se compila dentro de la
/// aplicación.
library;

import 'aggregator.dart';

/// Marca única para toda métrica que nadie tomó.
const notMeasured = 'NOT_MEASURED';

/// Arma la tabla comparativa en Markdown.
abstract final class BenchReport {
  static String render(List<EngineSummary> summaries) {
    final buffer = StringBuffer()
      ..writeln('# EVOLUTION-3 — Comparación de motores de voz')
      ..writeln()
      ..writeln(
        'Generado por `tool/voice_benchmark/main.dart` a partir de los archivos '
        'exportados por los teléfonos. Ninguna celda se completa por estimación: '
        'lo que no se midió dice `$notMeasured`.',
      )
      ..writeln();

    if (summaries.isEmpty) {
      buffer
        ..writeln('No se leyó ninguna medición.')
        ..writeln()
        ..write(_pendientes());
      return buffer.toString();
    }

    buffer
      ..writeln('## Resumen por motor y dispositivo')
      ..writeln()
      ..writeln(
        '| Motor | Modelo | Dispositivo | Android | Corpus | Muestras | '
        'Con resultado | Errores | Exactitud | WER mediana | Datos críticos | '
        'Parcial p50 | Parcial p95 | Final p50 | Final p95 | Memoria pico | '
        'Modo avión | Locale distinto |',
      )
      ..writeln(
        '|---|---|---|---|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|',
      );

    for (final s in summaries) {
      buffer.writeln(
        '| ${s.engine} '
        '| ${s.model.isEmpty ? "—" : s.model} '
        '| ${s.device.isEmpty ? "—" : s.device} '
        '| ${_android(s)} '
        '| ${s.split} '
        '| ${s.total} '
        '| ${s.withResult} '
        '| ${s.failed} '
        '| ${_percent(s.exactMatchRate)} '
        '| ${_ratio(s.medianWer)} '
        '| ${_percent(s.criticalTokenRate)} '
        '| ${_ms(s.partialP50)} '
        '| ${_ms(s.partialP95)} '
        '| ${_ms(s.finalP50)} '
        '| ${_ms(s.finalP95)} '
        '| ${_bytes(s.peakMemoryBytes)} '
        '| ${s.airplaneRuns} '
        '| ${s.localeFallbacks} |',
      );
    }

    buffer
      ..writeln()
      ..writeln('## Errores observados')
      ..writeln();

    final conErrores = summaries.where((s) => s.errorCounts.isNotEmpty);
    if (conErrores.isEmpty) {
      buffer.writeln('Ninguna medición terminó en error.');
    } else {
      buffer
        ..writeln('| Motor | Dispositivo | Corpus | Código | Veces |')
        ..writeln('|---|---|---|---|--:|');
      for (final s in conErrores) {
        final codes = s.errorCounts.keys.toList()..sort();
        for (final code in codes) {
          buffer.writeln(
            '| ${s.engine} | ${s.device} | ${s.split} | $code '
            '| ${s.errorCounts[code]} |',
          );
        }
      }
    }

    final redactadas = summaries.fold<int>(0, (sum, s) => sum + s.redacted);
    if (redactadas > 0) {
      buffer
        ..writeln()
        ..writeln(
          '> $redactadas mediciones llegaron sin transcripción porque quien '
          'ejecutó la prueba decidió no exportarla. Su exactitud no puede '
          'calcularse y no se cuenta como acierto ni como error.',
        );
    }

    buffer
      ..writeln()
      ..write(_pendientes());
    return buffer.toString();
  }

  static String _pendientes() {
    final buffer = StringBuffer()
      ..writeln('## Métricas que esta fase no puede producir')
      ..writeln()
      ..writeln('| Métrica | Estado | Motivo |')
      ..writeln('|---|---|---|');
    final keys = metricasNoMedibles.keys.toList()..sort();
    for (final key in keys) {
      buffer.writeln('| $key | `$notMeasured` | ${metricasNoMedibles[key]} |');
    }
    return buffer.toString();
  }

  static String _android(EngineSummary s) {
    if (s.androidRelease.isEmpty && s.androidSdk == null) return '—';
    final sdk = s.androidSdk == null ? '' : ' / API ${s.androidSdk}';
    return '${s.androidRelease}$sdk';
  }

  static String _percent(double? value) =>
      value == null ? notMeasured : '${(value * 100).toStringAsFixed(1)} %';

  static String _ratio(double? value) =>
      value == null ? notMeasured : value.toStringAsFixed(3);

  static String _ms(int? value) => value == null ? notMeasured : '$value ms';

  static String _bytes(int? value) {
    if (value == null) return notMeasured;
    final mib = value / (1024 * 1024);
    return '${mib.toStringAsFixed(1)} MiB';
  }
}
