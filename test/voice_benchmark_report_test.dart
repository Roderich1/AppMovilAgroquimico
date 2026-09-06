import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/voice_benchmark/aggregator.dart';
import '../tool/voice_benchmark/main.dart' as cli;
import '../tool/voice_benchmark/report.dart';
import '../tool/voice_benchmark/result_parser.dart';
import '../tool/voice_benchmark/text_normalizer.dart';

/// Pruebas del lector y el agregador de resultados del benchmark de voz
/// (EVOLUTION-3, Fase 0).
///
/// Estas herramientas deciden qué números llegan a `ADR-002`. Si redondean mal,
/// rellenan un hueco con cero o pierden una fila, la decisión del motor se toma
/// sobre datos falsos. Por eso se prueban aparte del banco: viven en el
/// repositorio y corren con `flutter test`.
void main() {
  group('normalización de texto', () {
    test('quita tildes y puntuación', () {
      expect(canonical('¡Compré, señor!'), 'compre senor');
    });

    test('convierte números escritos en dígitos', () {
      expect(normalizeNumbers('cincuenta litros'), '50 litros');
      expect(normalizeNumbers('ciento ochenta y seis'), '186');
      expect(normalizeNumbers('dos mil quinientos'), '2500');
      expect(normalizeNumbers('mil quinientos'), '1500');
      expect(normalizeNumbers('doscientos'), '200');
      expect(normalizeNumbers('veinticinco'), '25');
    });

    test('entiende el decimal dictado con "coma"', () {
      expect(normalizeNumbers('doce coma cinco litros'), '12,5 litros');
    });

    test('no toca lo que no es un número', () {
      expect(normalizeNumbers('bellator y germispa'), 'bellator y germispa');
    });

    test('la "y" sólo une cuando sigue un número', () {
      expect(normalizeNumbers('cuarenta y cinco kilos'), '45 kilos');
      expect(normalizeNumbers('cinco y luego'), '5 y luego');
    });

    test(
      'lo dictado en letras y lo transcrito en dígitos son equivalentes',
      () {
        // Es el caso real: el corpus dice "cincuenta", el motor devuelve "50".
        // Sin esta equivalencia se contaria como error un acierto.
        expect(
          comparable('Compré cincuenta litros'),
          comparable('compre 50 litros'),
        );
      },
    );

    group('WER', () {
      test('vale cero cuando la transcripción es idéntica', () {
        expect(wordErrorRate('cincuenta litros', '50 litros'), 0);
      });

      test('crece con cada palabra equivocada', () {
        final uno = wordErrorRate(
          'cincuenta litros de bellator',
          '50 litros de germispa',
        );
        final dos = wordErrorRate(
          'cincuenta litros de bellator',
          '50 kilos de germispa',
        );

        expect(uno, closeTo(0.25, 0.001));
        expect(dos, greaterThan(uno));
      });

      test('penaliza que el motor invente palabras', () {
        expect(wordErrorRate('hola', 'hola musica de fondo'), greaterThan(0));
      });

      test('una transcripción vacía frente a texto es error total', () {
        expect(wordErrorRate('cincuenta litros', ''), 1);
      });
    });

    test('los datos críticos se buscan sin importar la posición', () {
      expect(
        containsAllTokens('compre 50 litros de bellator', 'Bellator'),
        isTrue,
      );
      expect(
        containsAllTokens('compre 50 litros de bellator', 'cincuenta'),
        isTrue,
      );
      expect(
        containsAllTokens('compre 50 litros de bellator', 'germispa'),
        isFalse,
      );
    });
  });

  group('lectura de archivos exportados', () {
    String jsonRun(List<Map<String, Object?>> results) => jsonEncode({
      'schema': 'evolution-3-voice-benchmark',
      'engine': 'android-speech',
      'device': 'Pixel 8',
      'androidSdk': 36,
      'results': results,
    });

    test('lee un JSON con envoltorio y hereda sus campos', () {
      final records = BenchResultParser.parse(
        jsonRun([
          {
            'sampleId': 'AC-002',
            'split': 'aceptacion',
            'intent': 'compra',
            'expectedText': 'Compré cuarenta litros',
            'obtainedText': 'compre 40 litros',
            'engine': 'android-speech',
            'airplaneMode': false,
            'finalLatencyMs': 800,
          },
        ]),
      );

      expect(records, hasLength(1));
      expect(records.single.sampleId, 'AC-002');
      expect(records.single.androidSdk, 36);
      expect(records.single.finalLatencyMs, 800);
    });

    test('lee una lista JSON sin envoltorio', () {
      final records = BenchResultParser.parse(
        jsonEncode([
          {
            'sampleId': 'AC-003',
            'engine': 'whisper-tiny-q5_1',
            'expectedText': 'x',
            'airplaneMode': true,
          },
        ]),
      );

      expect(records.single.engine, 'whisper-tiny-q5_1');
      expect(records.single.airplaneMode, isTrue);
    });

    test('un campo ausente queda nulo, nunca en cero', () {
      final records = BenchResultParser.parse(
        jsonRun([
          {'sampleId': 'AC-004', 'expectedText': 'x', 'airplaneMode': false},
        ]),
      );

      expect(records.single.partialLatencyMs, isNull);
      expect(records.single.finalLatencyMs, isNull);
      expect(records.single.memoryBytes, isNull);
    });

    test('lee CSV con comas y comillas dentro de una celda', () {
      const csv =
          'sampleId,expectedText,obtainedText,engine,airplaneMode,finalLatencyMs\n'
          'AC-005,"dijo ""medio"", luego pausó",compre 40,android-speech,false,900\n';
      final records = BenchResultParser.parse(csv);

      expect(records, hasLength(1));
      expect(records.single.expectedText, 'dijo "medio", luego pausó');
      expect(records.single.finalLatencyMs, 900);
    });

    test('deshace la neutralización de fórmulas del exportador', () {
      const csv =
          'sampleId,expectedText,obtainedText,engine,airplaneMode\n'
          "AC-006,x,'=1+1,android-speech,false\n";
      final records = BenchResultParser.parse(csv);

      expect(records.single.obtainedText, '=1+1');
    });

    test('una celda vacía del CSV no se convierte en texto vacío falso', () {
      const csv =
          'sampleId,expectedText,obtainedText,engine,airplaneMode\n'
          'AC-007,x,,android-speech,false\n';
      final records = BenchResultParser.parse(csv);

      expect(records.single.obtainedText, isNull);
      expect(records.single.succeeded, isFalse);
    });

    test('un JSON inválido se rechaza con mensaje, no con datos a medias', () {
      expect(
        () => BenchResultParser.parse('{ esto no es json'),
        throwsA(isA<BenchParseException>()),
      );
    });

    test('un resultado sin identificador se rechaza', () {
      expect(
        () => BenchResultParser.parse(
          jsonRun([
            {'expectedText': 'x'},
          ]),
        ),
        throwsA(isA<BenchParseException>()),
      );
    });
  });

  group('agregación', () {
    BenchRecord record({
      required String sampleId,
      required String obtained,
      String engine = 'android-speech',
      String expected = 'Compré cincuenta litros',
      String split = 'aceptacion',
      int? partial,
      int? finalMs,
      int? memory,
      String? error,
      bool airplane = false,
      bool redacted = false,
      String requested = 'es-BO',
      String? effective,
    }) => BenchRecord(
      sampleId: sampleId,
      split: split,
      intent: 'compra',
      expectedText: expected,
      obtainedText: obtained.isEmpty ? null : obtained,
      engine: engine,
      device: 'Pixel 8',
      androidRelease: '16',
      androidSdk: 36,
      airplaneMode: airplane,
      partialLatencyMs: partial,
      finalLatencyMs: finalMs,
      memoryBytes: memory,
      errorCode: error,
      requestedLocale: requested,
      effectiveLocale: effective,
      transcriptRedacted: redacted,
    );

    test('cuenta aciertos exactos con números normalizados', () {
      final summary = BenchAggregator.summarize([
        record(sampleId: 'A', obtained: 'compre 50 litros'),
        record(sampleId: 'B', obtained: 'compre 50 kilos'),
      ]).single;

      expect(summary.total, 2);
      expect(summary.exactMatches, 1);
      expect(summary.exactMatchRate, 0.5);
    });

    test('separa por motor, dispositivo y corpus', () {
      final summaries = BenchAggregator.summarize([
        record(sampleId: 'A', obtained: 'x', engine: 'android-speech'),
        record(sampleId: 'A', obtained: 'x', engine: 'whisper-tiny-q5_1'),
        record(sampleId: 'A', obtained: 'x', split: 'ajuste'),
      ]);

      expect(summaries, hasLength(3));
    });

    test('los percentiles ignoran las mediciones sin dato', () {
      final summary = BenchAggregator.summarize([
        record(sampleId: 'A', obtained: 'x', finalMs: 100),
        record(sampleId: 'B', obtained: 'x'),
        record(sampleId: 'C', obtained: 'x', finalMs: 900),
      ]).single;

      expect(summary.finalP50, 100);
      expect(summary.finalP95, 900);
    });

    test('sin ninguna latencia parcial la métrica queda sin medir', () {
      // Es el caso de Whisper: no produce parciales. Reportar 0 ms diria que
      // responde al instante, que es lo contrario de la verdad.
      final summary = BenchAggregator.summarize([
        record(sampleId: 'A', obtained: 'x', finalMs: 500),
      ]).single;

      expect(summary.partialP50, isNull);
      expect(summary.partialP95, isNull);
    });

    test('la memoria informada es el pico observado', () {
      final summary = BenchAggregator.summarize([
        record(sampleId: 'A', obtained: 'x', memory: 100),
        record(sampleId: 'B', obtained: 'x', memory: 900),
        record(sampleId: 'C', obtained: 'x'),
      ]).single;

      expect(summary.peakMemoryBytes, 900);
    });

    test('cuenta los errores por código', () {
      final summary = BenchAggregator.summarize([
        record(sampleId: 'A', obtained: '', error: 'localeUnavailable'),
        record(sampleId: 'B', obtained: '', error: 'localeUnavailable'),
        record(sampleId: 'C', obtained: '', error: 'networkRequired'),
      ]).single;

      expect(summary.failed, 3);
      expect(summary.errorCounts, {
        'localeUnavailable': 2,
        'networkRequired': 1,
      });
      expect(summary.withResult, 0);
      expect(summary.exactMatchRate, isNull);
    });

    test('una transcripción quitada no cuenta como acierto ni como error', () {
      final summary = BenchAggregator.summarize([
        record(sampleId: 'A', obtained: 'compre 50 litros'),
        record(sampleId: 'B', obtained: '', redacted: true),
      ]).single;

      expect(summary.redacted, 1);
      expect(summary.withResult, 1);
      expect(summary.exactMatches, 1);
      expect(summary.failed, 0);
    });

    test('detecta cuántas veces el motor usó otro locale', () {
      final summary = BenchAggregator.summarize([
        record(sampleId: 'A', obtained: 'x', effective: 'es-ES'),
        record(sampleId: 'B', obtained: 'x', effective: 'es-BO'),
      ]).single;

      expect(summary.localeFallbacks, 1);
    });

    test('cuenta las pruebas hechas en modo avión', () {
      final summary = BenchAggregator.summarize([
        record(sampleId: 'A', obtained: 'x', airplane: true),
        record(sampleId: 'B', obtained: 'x'),
      ]).single;

      expect(summary.airplaneRuns, 1);
    });

    test('mide si los datos críticos sobrevivieron a la transcripción', () {
      final summary = BenchAggregator.summarize(
        [record(sampleId: 'A', obtained: 'compre 50 litros de bellator')],
        criticalSlots: {
          'A': ['Bellator', 'cincuenta', 'Germispa'],
        },
      ).single;

      expect(summary.criticalTokenTotal, 3);
      expect(summary.criticalTokenHits, 2);
    });

    test('un dato marcado AMBIGUO no se cuenta como algo que deba aparecer', () {
      // `AMBIGUO` significa que el dato NO debe resolverse solo. Contarlo como
      // palabra esperada premiaria justo lo que la politica prohibe.
      final summary = BenchAggregator.summarize(
        [record(sampleId: 'A', obtained: 'registra un pago para jose luis')],
        criticalSlots: {
          'A': ['AMBIGUO'],
        },
      ).single;

      expect(summary.criticalTokenTotal, 0);
      expect(summary.criticalTokenRate, isNull);
    });

    test('sin corpus de referencia la métrica crítica queda sin medir', () {
      final summary = BenchAggregator.summarize([
        record(sampleId: 'A', obtained: 'x'),
      ]).single;

      expect(summary.criticalTokenRate, isNull);
    });
  });

  group('mediciones repetidas', () {
    BenchRecord take({
      required String sampleId,
      required String startedAt,
      int attempt = 1,
    }) => BenchRecord(
      sampleId: sampleId,
      split: 'ajuste',
      intent: 'compra',
      expectedText: 'Compre diez litros',
      obtainedText: 'compre 10 litros',
      engine: 'android-speech',
      device: 'Xiaomi 22101320G',
      airplaneMode: false,
      attempt: attempt,
      startedAt: startedAt,
    );

    test('la misma toma leida en JSON y en CSV se cuenta una vez', () {
      // El banco exporta los dos formatos de la MISMA tanda. Dejar ambos en la
      // carpeta duplicaba las muestras y el informe declaraba el doble de
      // frases de las que se pronunciaron.
      final uno = take(sampleId: 'AJ-001', startedAt: '2026-09-06T15:21:35.1');
      final copia = take(
        sampleId: 'AJ-001',
        startedAt: '2026-09-06T15:21:35.1',
      );

      expect(cli.deduplicate([uno, copia]), hasLength(1));
    });

    test('repetir una frase de verdad sigue contando como dos tomas', () {
      // Dos tomas reales nunca comparten el instante de inicio: distinguirlas
      // importa porque el propietario repite frases cuando el motor falla.
      final primera = take(
        sampleId: 'AJ-001',
        startedAt: '2026-09-06T15:21:35.1',
      );
      final segunda = take(
        sampleId: 'AJ-001',
        startedAt: '2026-09-06T15:24:02.7',
        attempt: 2,
      );

      expect(cli.deduplicate([primera, segunda]), hasLength(2));
    });

    test('conserva el orden de lectura', () {
      final a = take(sampleId: 'AJ-001', startedAt: '2026-09-06T15:21:35.1');
      final b = take(sampleId: 'AJ-002', startedAt: '2026-09-06T15:22:00.0');

      expect(cli.deduplicate([a, b, a]).map((r) => r.sampleId), [
        'AJ-001',
        'AJ-002',
      ]);
    });

    test('el instante de la toma se lee del archivo exportado', () {
      final records = BenchResultParser.parseCsv(
        'sampleId,split,intent,expectedText,engine,airplaneMode,startedAt\n'
        'AJ-001,ajuste,compra,Registrar compra.,android-speech,false,'
        '2026-09-06T15:21:35.250644\n',
      );

      expect(records.single.startedAt, '2026-09-06T15:21:35.250644');
    });
  });

  group('percentiles', () {
    test('una serie vacía no tiene percentil', () {
      expect(percentile(const <int?>[], 50), isNull);
      expect(percentile(const <int?>[null, null], 95), isNull);
    });

    test('un solo valor es su propio p50 y p95', () {
      expect(percentile(const [7], 50), 7);
      expect(percentile(const [7], 95), 7);
    });

    test('p95 se acerca al peor caso', () {
      final valores = List<int>.generate(100, (i) => i + 1);

      expect(percentile(valores, 50), 50);
      expect(percentile(valores, 95), 95);
    });
  });

  group('informe', () {
    test('sin mediciones lo dice y no inventa una tabla', () {
      final markdown = BenchReport.render(const []);

      expect(markdown, contains('No se leyó ninguna medición'));
      expect(markdown, contains(notMeasured));
    });

    test('siempre declara las métricas que la fase no puede producir', () {
      final markdown = BenchReport.render(const []);

      for (final metrica in metricasNoMedibles.keys) {
        expect(markdown, contains(metrica));
      }
      expect(markdown, contains('EVO-010'));
    });

    test('las métricas ausentes salen como NOT_MEASURED, no como cero', () {
      final summaries = BenchAggregator.summarize([
        BenchRecord(
          sampleId: 'A',
          split: 'aceptacion',
          intent: 'compra',
          expectedText: 'x',
          obtainedText: 'x',
          engine: 'whisper-tiny-q5_1',
          airplaneMode: false,
        ),
      ]);
      final markdown = BenchReport.render(summaries);

      expect(markdown, contains(notMeasured));
      expect(markdown, isNot(contains('| 0 ms |')));
    });

    test('la tabla nombra motor, modelo y dispositivo', () {
      final summaries = BenchAggregator.summarize([
        BenchRecord(
          sampleId: 'A',
          split: 'aceptacion',
          intent: 'compra',
          expectedText: 'x',
          obtainedText: 'x',
          engine: 'whisper-tiny-q5_1',
          model: 'ggml-tiny-q5_1.bin',
          device: 'Pixel 8',
          androidRelease: '16',
          androidSdk: 36,
          airplaneMode: false,
        ),
      ]);
      final markdown = BenchReport.render(summaries);

      expect(markdown, contains('whisper-tiny-q5_1'));
      expect(markdown, contains('ggml-tiny-q5_1.bin'));
      expect(markdown, contains('Pixel 8'));
      expect(markdown, contains('API 36'));
    });
  });

  group('corpus de referencia', () {
    test('el agregador lee los datos críticos del corpus real', () {
      final slots = cli.loadCriticalSlots(
        File('benchmark/voice_benchmark/assets/corpus.json'),
      );

      expect(slots, isNotEmpty);
      expect(slots['AJ-003'], contains('Urea'));
      // Una frase con varios productos se separa en sus partes.
      expect(slots['AJ-008'], containsAll(<String>['Bellator', 'Germispa']));
    });

    test('si el corpus no está, no se inventan datos críticos', () {
      final slots = cli.loadCriticalSlots(File('no/existe/corpus.json'));

      expect(slots, isEmpty);
    });
  });
}
