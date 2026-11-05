import 'package:agroquimicos/voice/port/review_selection.dart';
import 'package:flutter_test/flutter_test.dart';

/// Qué texto llega a la sesión cuando hay segunda pasada local (#166).
///
/// Los pares Vosk/Whisper de este archivo son salidas REALES de la
/// comprobación HOST del 2026-11-05 (audio sintético, `tool/voice_local/`),
/// no frases inventadas para que la regla pase.
void main() {
  group('acepta la revisión cuando sólo cambian palabras', () {
    test('corrige el producto y el lugar sin tocar la cantidad', () {
      final choice = chooseReviewedText(
        'aplique medio litro de bella thor en el saco de abajo',
        'Aplique medio litro de Bellator en el chaco de abajo.',
      );
      expect(choice.verdict, ReviewVerdict.accepted);
      expect(choice.text, 'Aplique medio litro de Bellator en el chaco de abajo.');
    });

    test('cifras en dígitos que la app lee igual que las palabras', () {
      expect(
        chooseReviewedText(
          'compré dos litros de glifosato a ciento veinte bolivianos',
          'Compré dos litros de glifosato a 120 bolivianos.',
        ).verdict,
        ReviewVerdict.accepted,
      );
      expect(
        chooseReviewedText(
          'dos coma cinco litros de para coat',
          '2,5 litros de Paraquat.',
        ).verdict,
        ReviewVerdict.accepted,
      );
      expect(
        chooseReviewedText(
          'tres kilogramos y medio de atrás china',
          '3 kg y medio de Atrazina.',
        ).verdict,
        ReviewVerdict.accepted,
      );
    });

    test('nombres de personas', () {
      expect(
        chooseReviewedText(
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
      final choice = chooseReviewedText(
        'compré dos litros de glifosato a ciento veinte bolivianos',
        'Con 3 litros de glyfosato a 120 bolivianos.',
      );
      expect(choice.verdict, ReviewVerdict.quantities);
      expect(choice.text, 'compré dos litros de glifosato a ciento veinte bolivianos');
      expect(choice.revised, isFalse);
    });

    test('si cambia la unidad o la moneda', () {
      expect(
        chooseReviewedText('dos litros de bellator', '2 kilos de Bellator.')
            .verdict,
        ReviewVerdict.quantities,
      );
      expect(
        chooseReviewedText('pagué cien bolivianos', 'Pagué 100 dólares.').verdict,
        ReviewVerdict.quantities,
      );
    });

    test('si añade o quita una cantidad', () {
      expect(
        chooseReviewedText('compré glifosato', 'Compré 2 litros de glifosato.')
            .verdict,
        ReviewVerdict.quantities,
      );
    });

    test('si la cifra queda ambigua para el lector de la app', () {
      // «1,500» es ambiguo según la especificación numérica: no se acepta.
      expect(
        chooseReviewedText('mil quinientos litros', '1,500 litros.').verdict,
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
          chooseReviewedText('dos litros', text).verdict,
          ReviewVerdict.nonSpeech,
          reason: text,
        );
      }
    });

    test('ante repeticiones o longitud desproporcionada', () {
      expect(
        chooseReviewedText('dos litros', 'litros litros litros litros').verdict,
        ReviewVerdict.degenerate,
      );
      expect(
        chooseReviewedText(
          'compré dos litros de glifosato a ciento veinte bolivianos',
          'Compré.',
        ).verdict,
        ReviewVerdict.degenerate,
      );
    });

    test('sin revisión o vacía', () {
      expect(chooseReviewedText(' dos litros ', null).text, 'dos litros');
      expect(chooseReviewedText('dos litros', null).verdict, ReviewVerdict.notRun);
      expect(chooseReviewedText('dos litros', '  ').verdict, ReviewVerdict.empty);
    });
  });

  test('una palabra fuera del catálogo no se vuelve producto', () {
    // f16: «glicerina» no está en la pista. La revisión puede escribirla mal,
    // pero no la sustituye por un producto: la regla no conoce el catálogo.
    final choice = chooseReviewedText(
      'compré un litro de glicerina para la casa',
      'Compré un litro de glicerina para la casa.',
    );
    expect(choice.text.toLowerCase(), contains('glicerina'));
    expect(choice.text.toLowerCase(), isNot(contains('glifosato')));
  });

  test('el diagnóstico no lleva el texto', () {
    final choice = chooseReviewedText('dos litros de glifosato', null);
    expect(choice.toString(), isNot(contains('glifosato')));
  });
}
