import 'package:flutter_test/flutter_test.dart';

import '../tool/voice_benchmark/comparison_guard.dart';
import '../tool/voice_benchmark/result_parser.dart';

/// Guarda de comparabilidad del agregador.
///
/// El informe pone dos motores en la misma tabla y el propietario lee una
/// columna al lado de la otra. Eso sólo significa algo si las dos columnas
/// salieron del mismo corpus, la misma versión, los mismos bytes, la misma
/// partición y el mismo modelo. Si no, la tabla compara dos exámenes distintos
/// y lo presenta como si midiera dos alumnos.
///
/// Es exactamente lo que estuvo a punto de pasar: C1 se midió con el corpus de
/// la Fase 0 mientras el plan pedía A–G. Sin esta guarda, esos números habrían
/// entrado en la misma tabla que C3 y C4.
void main() {
  BenchRecord record({
    String sampleId = 'HA-001',
    String engine = 'vosk-small-es-0.42',
    String candidateId = 'C1',
    String corpusId = 'hibrido-ag',
    String corpusVersion = 'hybrid-1.0.0',
    String corpusDigest =
        '52822895357baf2f9d207d346bef22b07970035d66103ec0'
        '05609dfaefb00bd0',
    String partition = 'ajuste',
    String requestedLocale = 'es-US',
    Map<String, String> modelHashes = const {
      'vosk-model-small-es-0.42':
          '09b239888f633ef2f0b4e09736e3d9936acfd810bc65d53fad45261762c6511f',
    },
    String device = 'HONOR JDY-LX3P',
  }) => BenchRecord(
    sampleId: sampleId,
    split: partition == 'sin_habla' ? 'aceptacion' : partition,
    intent: 'compra',
    expectedText: 'Registrar compra.',
    obtainedText: 'registrar compra',
    engine: engine,
    airplaneMode: true,
    systemAirplaneMode: true,
    device: device,
    requestedLocale: requestedLocale,
    corpusId: corpusId,
    corpusVersion: corpusVersion,
    corpusDigest: corpusDigest,
    partition: partition,
    candidateId: candidateId,
    modelHashes: modelHashes,
  );

  group('lo que sí es comparable', () {
    test('dos candidatos sobre el mismo corpus y partición se aceptan', () {
      final veredicto = ComparisonGuard.check([
        record(),
        record(
          engine: 'whisper-small-q5_1',
          candidateId: 'C3',
          modelHashes: {
            'ggml-small-q5_1.bin': 'ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb',
          },
        ),
      ]);

      expect(veredicto.comparable, isTrue);
      expect(veredicto.rejections, isEmpty);
    });

    test('dos aparatos distintos siguen siendo comparables entre sí', () {
      // El plan pide una tabla por dispositivo, no fusionarlos; pero el
      // dispositivo no invalida la corrida, sólo la separa.
      final veredicto = ComparisonGuard.check([
        record(),
        record(device: 'POCO X5 Pro 5G'),
      ]);

      expect(veredicto.comparable, isTrue);
    });
  });

  group('corpus distinto', () {
    test('mezclar Fase 0 con A–G se rechaza', () {
      final veredicto = ComparisonGuard.check([
        record(),
        record(
          engine: 'whisper-small-q5_1',
          candidateId: 'C3',
          corpusId: 'fase0',
          corpusVersion: '1.0.0',
          corpusDigest: '7a891fd1a6aa2d9c4f122cc79a9f7fac646ce52f634bc51dcc59a7c9683f6b6b',
          modelHashes: const {},
        ),
      ]);

      expect(veredicto.comparable, isFalse);
      expect(veredicto.rejections.single.reason, ComparisonReason.corpusId);
      expect(veredicto.rejections.single.detail, contains('fase0'));
    });

    test('misma identificación y otra versión se rechaza', () {
      final veredicto = ComparisonGuard.check([
        record(),
        record(corpusVersion: 'hybrid-1.1.0'),
      ]);

      expect(veredicto.comparable, isFalse);
      expect(
        veredicto.rejections.single.reason,
        ComparisonReason.corpusVersion,
      );
    });

    test('misma versión y otros bytes se rechaza', () {
      // El caso peligroso: alguien corrige una frase «sin cambiar la versión».
      final veredicto = ComparisonGuard.check([
        record(),
        record(corpusDigest: 'f' * 64),
      ]);

      expect(veredicto.comparable, isFalse);
      expect(veredicto.rejections.single.reason, ComparisonReason.corpusDigest);
    });
  });

  group('partición distinta', () {
    test('ajuste contra aceptación se rechaza', () {
      final veredicto = ComparisonGuard.check([
        record(),
        record(partition: 'aceptacion'),
      ]);

      expect(veredicto.comparable, isFalse);
      expect(veredicto.rejections.single.reason, ComparisonReason.partition);
    });

    test('la partición sin habla no se compara con las habladas', () {
      final veredicto = ComparisonGuard.check([
        record(),
        record(partition: 'sin_habla'),
      ]);

      expect(veredicto.comparable, isFalse);
    });
  });

  group('configuración crítica y modelo', () {
    test('dos locales solicitados distintos se rechazan', () {
      final veredicto = ComparisonGuard.check([
        record(),
        record(requestedLocale: 'es-ES'),
      ]);

      expect(veredicto.comparable, isFalse);
      expect(
        veredicto.rejections.single.reason,
        ComparisonReason.configuracionCritica,
      );
    });

    test('el mismo candidato con dos modelos distintos se rechaza', () {
      final veredicto = ComparisonGuard.check([
        record(),
        record(modelHashes: {'vosk-model-small-es-0.42': 'a' * 64}),
      ]);

      expect(veredicto.comparable, isFalse);
      expect(veredicto.rejections.single.reason, ComparisonReason.modelo);
    });
  });

  group('candidato mal identificado', () {
    test('un motor que no corresponde a su candidato se rechaza', () {
      final veredicto = ComparisonGuard.check([
        record(),
        record(engine: 'whisper-small-q5_1', candidateId: 'C1'),
      ]);

      expect(veredicto.comparable, isFalse);
      expect(veredicto.rejections.first.reason, ComparisonReason.candidato);
    });

    test(
      'dos motores bajo el mismo identificador de candidato se rechazan',
      () {
        final veredicto = ComparisonGuard.check([
          record(),
          record(engine: 'vosk-small-es-0.42', candidateId: 'C9'),
        ]);

        expect(veredicto.comparable, isFalse);
      },
    );
  });

  group('corridas anteriores a la identidad', () {
    test('sin identidad de corpus no se mezclan con las nuevas', () {
      // Los archivos de la Fase 0 no traen `corpusId`. Son válidos como
      // historia, y no pueden entrar en la misma tabla que una corrida nueva.
      final veredicto = ComparisonGuard.check([
        record(),
        record(
          corpusId: '',
          corpusVersion: '',
          corpusDigest: '',
          partition: '',
        ),
      ]);

      expect(veredicto.comparable, isFalse);
      expect(
        veredicto.rejections.single.reason,
        ComparisonReason.identidadAusente,
      );
    });

    test(
      'una tanda entera sin identidad se acepta, marcada como histórica',
      () {
        final veredicto = ComparisonGuard.check([
          record(
            corpusId: '',
            corpusVersion: '',
            corpusDigest: '',
            partition: '',
          ),
          record(
            corpusId: '',
            corpusVersion: '',
            corpusDigest: '',
            partition: '',
            engine: 'android-speech',
            candidateId: '',
            modelHashes: const {},
          ),
        ]);

        expect(veredicto.comparable, isTrue);
        expect(veredicto.identityMissing, isTrue);
      },
    );
  });

  group('el veredicto sirve para escribirlo en el informe', () {
    test('enumera todas las razones, no sólo la primera', () {
      final veredicto = ComparisonGuard.check([
        record(),
        record(corpusId: 'fase0', partition: 'aceptacion'),
      ]);

      expect(veredicto.rejections.length, greaterThanOrEqualTo(2));
      expect(
        veredicto.rejections.map((r) => r.reason),
        containsAll(<ComparisonReason>[
          ComparisonReason.corpusId,
          ComparisonReason.partition,
        ]),
      );
    });

    test('describe cada rechazo con los dos valores en conflicto', () {
      final veredicto = ComparisonGuard.check([
        record(),
        record(partition: 'aceptacion'),
      ]);

      final detalle = veredicto.rejections.single.detail;
      expect(detalle, contains('ajuste'));
      expect(detalle, contains('aceptacion'));
    });
  });
}
