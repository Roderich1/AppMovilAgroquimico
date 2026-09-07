import 'package:flutter_test/flutter_test.dart';
import 'package:voice_benchmark/bench/hybrid_comparison.dart';

/// Comparador del candidato híbrido.
///
/// Lo que se prueba aquí no es "que compare bien": es que **no invente**. La
/// tentación de fabricar una tercera transcripción mezclando lo mejor de cada
/// motor es exactamente lo que produciría un dato plausible y falso sobre una
/// cantidad de dinero, y por eso casi todas estas pruebas son adversariales.
void main() {
  EngineTranscript vosk(String text, {List<String> flags = const []}) =>
      EngineTranscript(
        engine: TranscriptEngine.vosk,
        text: text,
        elapsedMs: 700,
        flags: flags,
      );

  EngineTranscript whisper(String text, {List<String> flags = const []}) =>
      EngineTranscript(
        engine: TranscriptEngine.whisper,
        text: text,
        elapsedMs: 2400,
        flags: flags,
      );

  group('no fabrica una tercera transcripción', () {
    test('conserva los dos textos exactamente como llegaron', () {
      final result = compareTranscripts(
        partial: vosk('cincuenta litros de belator'),
        proposed: whisper('Cincuenta litros de Bellator.'),
      );

      expect(result.partial!.text, 'cincuenta litros de belator');
      expect(
        result.proposed!.text,
        'Cincuenta litros de Bellator.',
        reason: 'ni una mayúscula ni un punto se tocan',
      );
    });

    test('el papel de cada motor no se intercambia', () {
      final result = compareTranscripts(
        partial: vosk('dos litros'),
        proposed: whisper('doce litros'),
      );

      expect(result.partial!.engine, TranscriptEngine.vosk);
      expect(
        result.proposed!.engine,
        TranscriptEngine.whisper,
        reason: 'Whisper propone el final; Vosk sólo el parcial visible',
      );
    });
  });

  group('discrepancias críticas', () {
    test('«12» y «dos» se muestran ambas, sin elegir', () {
      // El caso medido en la Fase 0: la misma frase dio 12 y dos.
      final result = compareTranscripts(
        partial: vosk('dos litros de bellator'),
        proposed: whisper('12 litros de Bellator'),
      );

      expect(result.hasCriticalDisagreement, isTrue);
      expect(result.isAcceptableWithoutReview, isFalse);

      final digits = result.disagreements.firstWhere(
        (d) => d.kind == CriticalTokenKind.digitos,
      );
      expect(digits.left, isEmpty);
      expect(digits.right, ['12']);

      final words = result.disagreements.firstWhere(
        (d) => d.kind == CriticalTokenKind.numeroEnPalabras,
      );
      expect(words.left, ['dos']);
      expect(words.right, isEmpty);
    });

    test('NO convierte palabras a números', () {
      // «doce» y «12» son la misma cantidad para una persona, pero
      // convertirlas dentro del banco inventaría una equivalencia que nadie
      // midió y escondería el desacuerdo que hay que enseñar.
      final result = compareTranscripts(
        partial: vosk('doce litros'),
        proposed: whisper('12 litros'),
      );

      expect(result.hasCriticalDisagreement, isTrue);
    });

    test('un precio distinto es crítico', () {
      final result = compareTranscripts(
        partial: vosk('a ciento ochenta bolivianos el litro'),
        proposed: whisper('a ciento ochenta y seis bolivianos el litro'),
      );

      expect(result.hasCriticalDisagreement, isTrue);
      expect(
        result.disagreements.any(
          (d) => d.kind == CriticalTokenKind.numeroEnPalabras,
        ),
        isTrue,
      );
    });

    test('una unidad distinta es crítica', () {
      final result = compareTranscripts(
        partial: vosk('cincuenta litros de mancozeb'),
        proposed: whisper('cincuenta kilos de mancozeb'),
      );

      final unit = result.disagreements.firstWhere(
        (d) => d.kind == CriticalTokenKind.unidad,
      );
      expect(unit.left, ['litros']);
      expect(unit.right, ['kilos']);
    });

    test('una moneda distinta es crítica', () {
      final result = compareTranscripts(
        partial: vosk('doce bolivianos'),
        proposed: whisper('doce dolares'),
      );

      expect(
        result.disagreements.any((d) => d.kind == CriticalTokenKind.moneda),
        isTrue,
      );
    });

    test('un término de catálogo distinto es crítico', () {
      final result = compareTranscripts(
        partial: vosk('diez litros de belladora'),
        proposed: whisper('diez litros de bellator'),
        catalogTerms: const ['Bellator'],
      );

      final catalog = result.disagreements.firstWhere(
        (d) => d.kind == CriticalTokenKind.terminoDeCatalogo,
      );
      expect(catalog.left, isEmpty);
      expect(catalog.right, ['bellator']);
    });

    test('una persona distinta es crítica', () {
      final result = compareTranscripts(
        partial: vosk('pago para jose luis'),
        proposed: whisper('pago para maria elena'),
        catalogTerms: const ['José Luis'],
      );

      expect(result.hasCriticalDisagreement, isTrue);
    });

    test('sin vocabulario de catálogo se siguen viendo cifras y unidades', () {
      final result = compareTranscripts(
        partial: vosk('cincuenta litros'),
        proposed: whisper('cuarenta litros'),
      );

      expect(result.hasCriticalDisagreement, isTrue);
    });
  });

  group('lo que NO es una discrepancia', () {
    test('sólo cambia el formato: mayúsculas, tildes y puntuación', () {
      final result = compareTranscripts(
        partial: vosk('cincuenta litros de bellator para el chaco limoncitos'),
        proposed: whisper(
          'Cincuenta litros de Bellator, para el chaco Limoncitos.',
        ),
        catalogTerms: const ['Bellator', 'Limoncitos'],
      );

      expect(result.disagreements, isEmpty);
      expect(result.flags, contains(HybridComparison.flagIdentical));
      expect(result.isAcceptableWithoutReview, isTrue);
    });

    test('una muletilla de más no bloquea nada', () {
      final result = compareTranscripts(
        partial: vosk('este cincuenta litros de bellator'),
        proposed: whisper('cincuenta litros de bellator'),
        catalogTerms: const ['Bellator'],
      );

      expect(result.hasCriticalDisagreement, isFalse);
      expect(
        result.flags,
        isNot(contains(HybridComparison.flagIdentical)),
        reason: 'no son idénticos, pero la diferencia no es de un dato crítico',
      );
    });

    test('los separadores de un decimal no se tocan', () {
      final result = compareTranscripts(
        partial: vosk('1.500,25 bolivianos'),
        proposed: whisper('1.500,25 bolivianos'),
      );

      expect(result.disagreements, isEmpty);
      final identical = compareTranscripts(
        partial: vosk('1.500,25 bolivianos'),
        proposed: whisper('1500,25 bolivianos'),
      );
      expect(
        identical.hasCriticalDisagreement,
        isTrue,
        reason: 'quitarle el punto a un importe lo cambia: hay que enseñarlo',
      );
    });
  });

  group('silencio, ruido y motores que fallan', () {
    test('silencio en los dos nunca es texto aceptable', () {
      final result = compareTranscripts(
        partial: vosk(''),
        proposed: whisper(''),
      );

      expect(result.isNoSpeech, isTrue);
      expect(result.isAcceptableWithoutReview, isFalse);
      expect(result.flags, contains(HybridComparison.flagNoSpeech));
    });

    test('sin ningún motor tampoco se acepta nada', () {
      final result = compareTranscripts();

      expect(result.isNoSpeech, isTrue);
      expect(result.isAcceptableWithoutReview, isFalse);
    });

    test('un solo motor con texto se marca y no se da por bueno', () {
      // Whisper falló: queda lo de Vosk, pero sin nada con qué contrastarlo.
      final result = compareTranscripts(partial: vosk('cincuenta litros'));

      expect(result.flags, contains(HybridComparison.flagSingleEngine));
      expect(
        result.isAcceptableWithoutReview,
        isFalse,
        reason: 'una sola opinión no es un acuerdo',
      );
    });

    test('la alucinación de Whisper bloquea la aceptación', () {
      // Reproduce lo medido en la Fase 0: `[MÚSICA]` sobre silencio, sin error.
      final result = compareTranscripts(
        partial: vosk(''),
        proposed: whisper('[MÚSICA]', flags: const ['possibleHallucination']),
      );

      expect(result.isAcceptableWithoutReview, isFalse);
      expect(result.flags, contains('possibleHallucination'));
    });

    test('las marcas de los dos motores se conservan juntas', () {
      final result = compareTranscripts(
        partial: vosk('algo', flags: const ['lowSpeechRatio']),
        proposed: whisper('algo', flags: const ['degenerateRepetition']),
      );

      expect(
        result.flags,
        containsAll(<String>['lowSpeechRatio', 'degenerateRepetition']),
      );
      expect(result.isAcceptableWithoutReview, isFalse);
    });

    test(
      'cualquier marca impide aceptar aunque coincidan palabra por palabra',
      () {
        final result = compareTranscripts(
          partial: vosk('cincuenta litros'),
          proposed: whisper(
            'cincuenta litros',
            flags: const ['lowSpeechRatio'],
          ),
        );

        expect(result.disagreements, isEmpty);
        expect(result.isAcceptableWithoutReview, isFalse);
      },
    );
  });

  group('lo que se exporta', () {
    test('el JSON lleva ambos textos y ambas alternativas', () {
      final json = compareTranscripts(
        partial: vosk('dos litros'),
        proposed: whisper('12 litros'),
      ).toJson();

      expect((json['partial']! as Map<String, Object?>)['text'], 'dos litros');
      expect((json['proposed']! as Map<String, Object?>)['text'], '12 litros');
      expect(json['hasCriticalDisagreement'], isTrue);
      expect(json['acceptableWithoutReview'], isFalse);
      expect(json['disagreements'], isA<List<Object?>>());
    });

    test('la discrepancia se lee sin abrir el JSON', () {
      final result = compareTranscripts(
        partial: vosk('dos litros'),
        proposed: whisper('doce litros'),
      );

      expect(
        result.disagreements.first.toString(),
        contains('|'),
        reason: 'las dos alternativas, separadas, a la vista',
      );
    });
  });
}
