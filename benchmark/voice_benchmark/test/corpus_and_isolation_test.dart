import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_benchmark/bench/bench_export.dart';
import 'package:voice_benchmark/bench/bench_result.dart';
import 'package:voice_benchmark/bench/corpus.dart';

/// Categorías que el corpus debe cubrir sí o sí.
///
/// La lista viene de `EVOLUTION-3_VOICE_GRAMMAR_AND_EXAMPLES.md` y del alcance
/// aprobado. Este test es la guarda: si alguien recorta el corpus, falla antes
/// de que las mediciones se hagan sobre un conjunto incompleto.
const _categoriasObligatorias = <String>[
  'frase_corta',
  'multiproducto',
  'pronunciacion_dificil',
  'germi_cien',
  'germi_uno_cero_cero',
  'expansive',
  'litros',
  'kilos',
  'precio_unitario',
  'bolivianos',
  'dolares',
  'tipo_de_cambio',
  'proveedor',
  'propietario',
  'aplicacion_planificada',
  'correccion_cantidad',
  'pago',
  'homonimo',
  'pausas',
  'autocorreccion',
  'ruido_de_campo',
  'fuera_de_alcance',
  'dos_intenciones',
  'alias',
  'nombre_parecido',
  'fecha',
  'decimales',
  'unidad_incompatible',
  'habla_rapida',
];

void main() {
  final corpus = Corpus.fromJsonString(
    File('assets/corpus.json').readAsStringSync(),
  );

  group('corpus', () {
    test('tiene al menos 100 muestras', () {
      expect(corpus.samples.length, greaterThanOrEqualTo(100));
    });

    test('está separado en ajuste y aceptación', () {
      expect(corpus.ajuste, isNotEmpty);
      expect(corpus.aceptacion, isNotEmpty);
      expect(
        corpus.ajuste.length + corpus.aceptacion.length,
        corpus.samples.length,
      );
    });

    test('ninguna frase de aceptación se repite en ajuste', () {
      // Es la regla que impide afinar el motor con las frases reservadas para
      // decidir. Sin ella, el resultado de aceptacion no significaria nada.
      final ajuste = corpus.ajuste.map((s) => s.text).toSet();
      final repetidas = corpus.aceptacion
          .where((s) => ajuste.contains(s.text))
          .map((s) => s.id);

      expect(repetidas, isEmpty);
    });

    test('los identificadores son únicos', () {
      final ids = corpus.samples.map((s) => s.id).toList();

      expect(ids.toSet().length, ids.length);
    });

    test('cubre todas las categorías obligatorias', () {
      final presentes = corpus.samples.expand((s) => s.tags).toSet();
      final faltantes = _categoriasObligatorias
          .where((c) => !presentes.contains(c))
          .toList();

      expect(faltantes, isEmpty, reason: 'faltan categorías: $faltantes');
    });

    test('cubre las tres intenciones y también lo que debe rechazarse', () {
      final intenciones = corpus.samples.map((s) => s.intent).toSet();

      expect(
        intenciones,
        containsAll(<String>[
          'compra',
          'aplicacion',
          'pago',
          'fuera_de_alcance',
          'mezclada',
        ]),
      );
    });

    test('ambos corpus incluyen casos que deben quedar bloqueados', () {
      for (final split in ['ajuste', 'aceptacion']) {
        final bloqueantes = corpus
            .bySplit(split)
            .where((s) => s.hasBlockingAmbiguity);

        expect(
          bloqueantes,
          isNotEmpty,
          reason: '$split necesita casos ambiguos para medir falsa aceptación',
        );
      }
    });

    test('toda muestra declara al menos una condición de ejecución', () {
      final sinCondicion = corpus.samples.where((s) => s.conditions.isEmpty);

      expect(sinCondicion, isEmpty);
    });

    test('las frases llevan ortografía española real', () {
      // El corpus se dicta en voz alta: sin tildes ni eñe, "campana" no es
      // "campaña" y quien lo lea pronunciaría otra palabra.
      final acentuadas = corpus.samples.where(
        (s) => s.text.contains(RegExp('[áéíóúñÁÉÍÓÚÑ]')),
      );

      expect(acentuadas.length, greaterThan(corpus.samples.length ~/ 2));
    });
  });

  group('aislamiento del spike', () {
    test('nada del banco importa la aplicación Agrocuentas ni SQLite', () {
      final prohibidos = <String>[
        'package:agroquimicos',
        'sqflite',
        'agro_repository',
        'app_database',
      ];
      final ofensores = <String>[];

      for (final file
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        final source = file.readAsStringSync();
        for (final prohibido in prohibidos) {
          if (source.contains(prohibido)) {
            ofensores.add('${file.path}: $prohibido');
          }
        }
      }

      expect(
        ofensores,
        isEmpty,
        reason: 'el banco de pruebas no puede alcanzar el dominio ni la base',
      );
    });

    test('el banco no declara dependencias de red ni de base de datos', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();

      for (final prohibido in ['sqflite', 'http:', 'dio:', 'firebase']) {
        expect(pubspec, isNot(contains(prohibido)));
      }
    });
  });

  group('exportación segura', () {
    BenchResult sample(String? text) => BenchResult(
      sampleId: 'AC-001',
      split: 'aceptacion',
      intent: 'compra',
      expectedText: 'Anota una compra.',
      obtainedText: text,
      engine: 'fake',
      model: '',
      requestedLocale: 'es-BO',
      effectiveLocale: 'es-ES',
      device: 'equipo',
      androidRelease: '16',
      androidSdk: 36,
      airplaneMode: false,
      startedAt: DateTime(2026, 9, 6),
    );

    BenchRun run(BenchResult result) => BenchRun(
      engine: 'fake',
      model: '',
      device: 'equipo',
      androidRelease: '16',
      androidSdk: 36,
      corpusVersion: '1.0.0',
      appVersion: 'test',
      results: [result],
    );

    test('una celda que parece fórmula se neutraliza', () {
      // Una transcripción empieza por donde el motor quiera. Si empieza con `=`,
      // una planilla la ejecutaría al abrir el archivo.
      final csv = BenchExport.toCsv(run(sample('=1+1')));

      expect(csv, contains("'=1+1"));
      expect(csv, isNot(contains(',=1+1')));
    });

    test('comillas y comas no rompen la fila', () {
      final csv = BenchExport.toCsv(run(sample('dijo "medio", luego pausó')));
      final lineas = csv.trim().split('\n');

      expect(lineas, hasLength(2));
      expect(csv, contains('""medio""'));
    });

    test('redactar borra el texto y deja la marca', () {
      final redacted = sample('cincuenta litros').redacted();

      expect(redacted.obtainedText, isNull);
      expect(redacted.transcriptRedacted, isTrue);
      expect(BenchExport.toCsv(run(redacted)), isNot(contains('cincuenta')));
    });

    test('las métricas sin medir se exportan vacías, no como cero', () {
      final csv = BenchExport.toCsv(run(sample('algo')));
      final fila = csv.trim().split('\n')[1].split(',');
      final indice = BenchExport.csvHeader.indexOf('memoryBytes');

      expect(fila[indice], isEmpty);
    });
  });
}
