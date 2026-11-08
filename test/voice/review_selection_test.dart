import 'package:agroquimicos/presentation/voice/voice_quantity_facts.dart';
import 'package:agroquimicos/voice/port/review_selection.dart';
import 'package:flutter_test/flutter_test.dart';

ReviewChoice choose(String first, String? review) =>
    chooseReviewedText(first, review, facts: voiceQuantityFacts);

/// Qué texto llega a la sesión cuando hay segunda pasada local (#166).
///
/// Los pares Vosk/Whisper de este archivo son salidas REALES de la
/// comprobación HOST del 2026-11-05 (audio sintético, `tool/voice_local/`),
/// no frases inventadas para que la regla pase.
void main() {
  group('acepta la revisión cuando sólo cambian palabras', () {
    test('corrige el producto y el lugar sin tocar la cantidad', () {
      final choice = choose(
        'aplique medio litro de bella thor en el saco de abajo',
        'Aplique medio litro de Bellator en el chaco de abajo.',
      );
      expect(choice.verdict, ReviewVerdict.accepted);
      expect(
        choice.text,
        'Aplique medio litro de Bellator en el chaco de abajo.',
      );
    });

    test('cifras en dígitos que la app lee igual que las palabras', () {
      expect(
        choose(
          'compré dos litros de glifosato a ciento veinte bolivianos',
          'Compré dos litros de glifosato a 120 bolivianos.',
        ).verdict,
        ReviewVerdict.accepted,
      );
      expect(
        choose(
          'dos coma cinco litros de para coat',
          '2,5 litros de Paraquat.',
        ).verdict,
        ReviewVerdict.accepted,
      );
      expect(
        choose(
          'tres kilogramos y medio de atrás china',
          '3 kg y medio de Atrazina.',
        ).verdict,
        ReviewVerdict.accepted,
      );
    });

    test('nombres de personas', () {
      expect(
        choose(
          'de mamani recibió un litro de con sole',
          'Beto Mamani recibió un litro de Tebuconazole.',
        ).verdict,
        ReviewVerdict.accepted,
      );
    });
  });

  group('se queda con Vosk', () {
    test('si la revisión cambia una cantidad', () {
      // Whisper base sin pista, voz «Laura», frase f01.
      final choice = choose(
        'compré dos litros de glifosato a ciento veinte bolivianos',
        'Con 3 litros de glyfosato a 120 bolivianos.',
      );
      expect(choice.verdict, ReviewVerdict.quantities);
      expect(
        choice.text,
        'compré dos litros de glifosato a ciento veinte bolivianos',
      );
      expect(choice.revised, isFalse);
    });

    test('si cambia la unidad o la moneda', () {
      expect(
        choose('dos litros de bellator', '2 kilos de Bellator.').verdict,
        ReviewVerdict.quantities,
      );
      expect(
        choose('pagué cien bolivianos', 'Pagué 100 dólares.').verdict,
        ReviewVerdict.quantities,
      );
    });

    test('si añade o quita una cantidad', () {
      expect(
        choose('compré glifosato', 'Compré 2 litros de glifosato.').verdict,
        ReviewVerdict.quantities,
      );
    });

    test('si la cifra queda ambigua para el lector de la app', () {
      // «1,500» es ambiguo según la especificación numérica: no se acepta.
      expect(
        choose('mil quinientos litros', '1,500 litros.').verdict,
        ReviewVerdict.quantities,
      );
    });

    test('ante marcas de no-habla o frases de alucinación', () {
      // Salidas reales de Whisper sobre silencio y ruido rosa.
      for (final text in const [
        '[MÚSICA]',
        'Subtítulos por la comunidad de Amara.org',
        '(risas)',
      ]) {
        expect(
          choose('dos litros', text).verdict,
          ReviewVerdict.nonSpeech,
          reason: text,
        );
      }
    });

    test('ante repeticiones o longitud desproporcionada', () {
      expect(
        choose('dos litros', 'litros litros litros litros').verdict,
        ReviewVerdict.degenerate,
      );
      expect(
        choose(
          'compré dos litros de glifosato a ciento veinte bolivianos',
          'Compré.',
        ).verdict,
        ReviewVerdict.degenerate,
      );
    });

    test('sin revisión o vacía', () {
      expect(choose(' dos litros ', null).text, 'dos litros');
      expect(choose('dos litros', null).verdict, ReviewVerdict.notRun);
      expect(choose('dos litros', '  ').verdict, ReviewVerdict.empty);
    });
  });

  test('una palabra fuera del catálogo no se vuelve producto', () {
    // f16: «glicerina» no está en la pista. La revisión puede escribirla mal,
    // pero no la sustituye por un producto: la regla no conoce el catálogo.
    final choice = choose(
      'compré un litro de glicerina para la casa',
      'Compré un litro de glicerina para la casa.',
    );
    expect(choice.text.toLowerCase(), contains('glicerina'));
    expect(choice.text.toLowerCase(), isNot(contains('glifosato')));
  });

  test('sin lector de cantidades, la revisión no se acepta nunca', () {
    final choice = chooseReviewedText(
      'aplique medio litro de bella thor',
      'Aplique medio litro de Bellator.',
      facts: null,
    );
    expect(choice.verdict, ReviewVerdict.unchecked);
    expect(choice.text, 'aplique medio litro de bella thor');
  });

  test('el diagnóstico no lleva el texto', () {
    final choice = choose('dos litros de glifosato', null);
    expect(choice.toString(), isNot(contains('glifosato')));
  });
}
