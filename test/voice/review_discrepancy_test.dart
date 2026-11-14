import 'package:agroquimicos/presentation/voice/voice_quantity_facts.dart';
import 'package:agroquimicos/voice/port/review_discrepancy.dart';
import 'package:agroquimicos/voice/port/review_selection.dart';
import 'package:flutter_test/flutter_test.dart';

/// Diagnóstico de la selección entre Vosk y la revisión (POCO 2026-11-09).
///
/// **Pares de transcripciones sintéticos** escritos a mano: no son
/// transcripciones del teléfono ni frases del holdout de #12. Las dos primeras
/// imitan la forma de lo que Vosk entregó en el POCO (visible en pantalla) y
/// una revisión **supuesta**: lo que Whisper propuso de verdad no se conoce.
///
/// Cada caso comprueba dos cosas:
/// * el veredicto de la regla **actual**, que no cambia ([chooseReviewedText]);
/// * la clasificación de la diferencia ([classifyFactDifferences]).
void main() {
  ReviewVerdict verdict(String vosk, String review) =>
      chooseReviewedText(vosk, review, facts: voiceQuantityFacts).verdict;
  List<String> codes(String vosk, String review) => classifyFactDifferences(
    voiceQuantityFacts(vosk),
    voiceQuantityFacts(review),
  ).map((d) => d.code).toList();

  group('regla actual: un dato ausente cuenta como desacuerdo', () {
    test('a Vosk le faltan la moneda y «el litro»', () {
      const vosk =
          'compre cinco litros de vicia de ciento veinte boliviana '
          'intro';
      const review =
          'Compré cinco litros de Herbicida DEMO a ciento veinte '
          'bolivianos el litro.';
      expect(verdict(vosk, review), ReviewVerdict.quantities);
      expect(codes(vosk, review), [
        'currency:missing@revision',
        'unit:missing@revision',
      ]);
    });

    test('a Vosk le falta sólo la moneda; la unidad del precio está en los '
        'dos', () {
      const vosk =
          'compre cinco litros de herencia de a ciento veinte nivel '
          'litro';
      const review =
          'Compré 5 litros de Herbicida DEMO a 120 bolivianos el '
          'litro.';
      expect(verdict(vosk, review), ReviewVerdict.quantities);
      expect(codes(vosk, review), ['currency:missing@revision']);
    });

    test('la moneda delante de la cifra («Bs 120») es el mismo precio: la '
        'regla actual lo da por distinto, la clasificación por formato', () {
      const vosk =
          'compre cinco litros de herbicida demo a ciento veinte '
          'bolivianos el litro';
      const review = 'Compré 5 L de Herbicida DEMO a Bs 120 el litro.';
      expect(verdict(vosk, review), ReviewVerdict.quantities);
      expect(codes(vosk, review), ['price:equivalentFormat']);
    });

    test('una cifra que el lector no lee («\$120») se ve como dato ausente '
        'en la revisión, no como otro valor', () {
      const vosk =
          'compre cinco litros de herbicida demo a ciento veinte '
          'bolivianos el litro';
      const review = 'Compré cinco litros de Herbicida DEMO a \$120 el litro.';
      expect(verdict(vosk, review), ReviewVerdict.quantities);
      expect(codes(vosk, review), [
        'price:missing@vosk',
        'unit:missing@revision',
      ]);
    });
  });

  group('mismo valor', () {
    test('«cinco» y «5»: se acepta la revisión, sin diferencias', () {
      const vosk =
          'compre cuarenta litros de fungicida demo a treinta '
          'bolivianos el litro';
      const review =
          'Compré 40 litros de Fungicida DEMO a 30 bolivianos el '
          'litro.';
      expect(verdict(vosk, review), ReviewVerdict.accepted);
      expect(codes(vosk, review), isEmpty);
    });

    test('«uno y medio» y «1,5»: igual', () {
      const vosk = 'compre uno y medio litros de fungicida demo';
      const review = 'Compré 1,5 litros de Fungicida DEMO.';
      expect(verdict(vosk, review), ReviewVerdict.accepted);
      expect(codes(vosk, review), isEmpty);
    });

    test('«un litro y medio» y «1.5»: formato equivalente', () {
      const vosk = 'compre un litro y medio de fungicida demo';
      const review = 'Compré 1.5 litros de Fungicida DEMO.';
      expect(verdict(vosk, review), ReviewVerdict.format);
      expect(codes(vosk, review), ['quantity:equivalentFormat']);
    });
  });

  group('otro valor, unidad o moneda', () {
    test('«veinte» frente a «120»: valor distinto', () {
      expect(codes('compre veinte litros', 'Compré 120 litros.'), [
        'quantity:differentValue',
      ]);
    });

    test('litros frente a kilos: unidad distinta', () {
      expect(codes('compre cinco litros', 'Compré cinco kilos.'), [
        'quantity:differentUnit',
      ]);
    });

    test('bolivianos frente a dólares: moneda distinta', () {
      expect(
        codes('a treinta bolivianos el litro', 'a treinta dólares el litro'),
        ['price:differentCurrency'],
      );
    });

    test('hectáreas frente a litros con la misma cifra: unidad distinta', () {
      expect(codes('dos hectareas', 'dos litros'), ['area:differentUnit']);
    });

    test('una cifra ilegible («1,500») es extracción fallida, no otro '
        'valor', () {
      expect(codes('compre cinco litros', 'Compré 1,500 litros.'), [
        'quantity:extractionFailed',
      ]);
    });

    test('la cantidad sólo en Vosk: ausente en la revisión', () {
      expect(
        codes(
          'compre cinco litros de fungicida demo a veinte bolivianos el litro',
          'de Fungicida DEMO a veinte bolivianos el litro',
        ),
        ['quantity:missing@vosk'],
      );
    });

    test(
      'dos cantidades frente a una distinta: no se adivina cuál es cuál',
      () {
        expect(
          codes(
            'compre dos litros de fungicida demo y tres litros de insecticida',
            'Compré cuatro litros de Fungicida DEMO.',
          ),
          ['quantity:ambiguousAlignment'],
        );
      },
    );

    test('varios productos con las mismas cifras: sin diferencias', () {
      expect(
        codes(
          'compre dos litros de fungicida demo y tres kilos de mancozeb demo',
          'Compré 2 litros de Fungicida DEMO y 3 kilos de Mancozeb DEMO.',
        ),
        isEmpty,
      );
    });
  });

  group('casos negativos', () {
    test('frase ajena a una operación, sin cifras: nada que comparar', () {
      expect(
        verdict('muchas gracias', '¡Muchas gracias!'),
        ReviewVerdict.accepted,
      );
      expect(codes('muchas gracias', '¡Muchas gracias!'), isEmpty);
    });

    test('silencio: listas vacías', () {
      expect(classifyFactDifferences(const [], const []), isEmpty);
    });

    test('un nombre de producto distinto no es una diferencia de cifras', () {
      expect(
        codes(
          'compre cinco litros de vicia demo',
          'Compré cinco litros de Herbicida DEMO.',
        ),
        isEmpty,
      );
    });
  });

  test('los códigos no llevan cifras ni texto', () {
    final all = codes(
      'compre veinte litros a treinta bolivianos el litro',
      'Compré 120 kilos a treinta dólares.',
    );
    expect(all, isNotEmpty);
    for (final c in all) {
      expect(c, matches(RegExp(r'^[a-z]+:[a-zA-Z]+(@(vosk|revision))?$')));
    }
  });
}
