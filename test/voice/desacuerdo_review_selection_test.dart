import 'package:agroquimicos/presentation/voice/voice_quantity_facts.dart';
import 'package:agroquimicos/voice/port/review_selection.dart';
import 'package:flutter_test/flutter_test.dart';

ReviewChoice choose(String first, String? review) =>
    chooseReviewedText(first, review, facts: voiceQuantityFacts);

/// Desacuerdo numérico entre los dos reconocedores (POCO 2026-11-08):
/// formato frente a valor.
///
/// TEXTO INYECTADO, NO RECONOCIMIENTO REAL: los pares de este archivo son
/// frases escritas para la prueba, no salidas de Vosk ni de la revisión. Lo
/// que se prueba es la regla de selección y el lector de cifras, no lo que
/// oye un motor.
void main() {
  group('lector de cifras (voiceQuantityFacts): el valor, no la forma', () {
    test('«y medio» después de la unidad se suma a la cantidad', () {
      const expected = ['n1500', 'uliter'];
      for (final text in const [
        '1,5 litros',
        'uno y medio litros',
        'un litro y medio',
        'litro y medio',
        'uno coma cinco litros',
      ]) {
        expect(voiceQuantityFacts(text), expected, reason: text);
      }
    });

    test('las áreas se leen como el intérprete, con su unidad', () {
      expect(voiceQuantityFacts('una hectárea y media'), ['n1500', 'uha']);
      expect(voiceQuantityFacts('1,5 hectáreas'), ['n1500', 'uha']);
      expect(voiceQuantityFacts('dos litros por hectárea'), [
        'n2000',
        'uliter',
        'uha',
      ]);
    });

    test('punto decimal: valor tolerante, marcado como no legible', () {
      // «1.5» no es es-BO (el punto separa miles), pero sólo puede ser 1,5.
      expect(voiceQuantityFacts('1.5 litros'), ['n?1500', 'uliter']);
      expect(voiceQuantityFacts('2.75 kilos'), ['n?2750', 'ukilogram']);
      // «1.500» sí es es-BO: mil quinientos.
      expect(voiceQuantityFacts('1.500 litros'), ['n1500000', 'uliter']);
      // «1,500» es ambiguo: sin valor.
      expect(voiceQuantityFacts('1,500 litros'), ['n?', 'uliter']);
    });

    test('puntuación, mayúsculas y palabras no numéricas no cuentan', () {
      expect(
        voiceQuantityFacts('Compré DOS litros, de Bellator.'),
        voiceQuantityFacts('compre dos litros de bella thor'),
      );
    });
  });

  group('mismo valor con otro formato: no es desacuerdo', () {
    for (final (vosk, review) in const [
      (
        'compré uno y medio litros de glifosato',
        'Compré 1,5 litros de glifosato.',
      ),
      (
        'compré un litro y medio de glifosato',
        'Compré 1,5 litros de glifosato.',
      ),
      (
        'compré litro y medio de glifosato',
        'Compré un litro y medio de glifosato.',
      ),
      ('aplique en una hectárea y media', 'Apliqué en 1,5 hectáreas.'),
      ('compré dos litros de bella thor', 'Compré DOS litros, de Bellator.'),
    ]) {
      test('«$vosk» / «$review»: se acepta la revisión', () {
        final choice = choose(vosk, review);
        expect(choice.verdict, ReviewVerdict.accepted);
        expect(choice.text, review);
        expect(choice.numericDisagreement, isFalse);
      });
    }

    test(
      '«1.5» (punto decimal): queda Vosk, que sí se lee, sin desacuerdo',
      () {
        final choice = choose(
          'compré un litro y medio de glifosato',
          'Compré 1.5 litros de glifosato.',
        );
        expect(choice.verdict, ReviewVerdict.format);
        expect(choice.text, 'compré un litro y medio de glifosato');
        expect(choice.revised, isFalse);
        expect(choice.numericDisagreement, isFalse);
      },
    );
  });

  group('otro valor: queda Vosk y se marca el desacuerdo', () {
    test('«veinte» frente a «ciento veinte»', () {
      final choice = choose(
        'compré dos litros de glifosato a veinte bolivianos el litro',
        'Compré dos litros de glifosato a ciento veinte bolivianos el litro.',
      );
      expect(choice.verdict, ReviewVerdict.quantities);
      // Una sola transcripción: la de Vosk entera, sin mezclar.
      expect(
        choice.text,
        'compré dos litros de glifosato a veinte bolivianos el litro',
      );
      expect(choice.revised, isFalse);
      expect(choice.numericDisagreement, isTrue);
    });

    test('otra unidad, otra moneda, otra área', () {
      for (final (vosk, review) in const [
        ('dos litros de bellator', '2 kilos de Bellator.'),
        ('pagué cien bolivianos', 'Pagué 100 dólares.'),
        ('en cinco hectáreas', 'En cinco tareas.'),
        ('un litro y medio', 'Dos litros y medio.'),
      ]) {
        expect(choose(vosk, review).numericDisagreement, isTrue, reason: vosk);
      }
    });

    test('una cifra sin valor seguro no se da por igual', () {
      final choice = choose('mil quinientos litros', '1,500 litros.');
      expect(choice.verdict, ReviewVerdict.quantities);
      expect(choice.numericDisagreement, isTrue);
    });
  });

  group('sin segunda lectura válida nunca hay desacuerdo', () {
    const vosk = 'compré dos litros de glifosato a veinte bolivianos';
    for (final (name, review, verdict) in const [
      ('no llegó o falló', null, ReviewVerdict.notRun),
      ('vacía', '   ', ReviewVerdict.empty),
      ('no-habla', '[MÚSICA]', ReviewVerdict.nonSpeech),
      ('degenerada', 'litros litros litros litros', ReviewVerdict.degenerate),
      ('demasiado corta', 'Compré.', ReviewVerdict.degenerate),
    ]) {
      test(name, () {
        final choice = choose(vosk, review);
        expect(choice.verdict, verdict);
        expect(choice.text, vosk);
        expect(choice.numericDisagreement, isFalse);
      });
    }

    test('sin lector de cifras', () {
      final choice = chooseReviewedText(
        'dos litros',
        'Tres litros.',
        facts: null,
      );
      expect(choice.verdict, ReviewVerdict.unchecked);
      expect(choice.numericDisagreement, isFalse);
    });
  });

  test('el diagnóstico de la elección no lleva texto', () {
    final choice = choose('veinte bolivianos', 'Ciento veinte bolivianos.');
    expect(choice.toString(), isNot(contains('veinte')));
  });
}
