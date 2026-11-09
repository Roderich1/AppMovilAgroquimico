import 'package:agroquimicos/presentation/voice/voice_quantity_facts.dart';
import 'package:agroquimicos/voice/port/review_discrepancy.dart';
import 'package:agroquimicos/voice/port/review_selection.dart';
import 'package:agroquimicos/voice_draft/text/normalize.dart';
import 'package:agroquimicos/voice_draft/text/spanish_numbers.dart';
import 'package:flutter_test/flutter_test.dart';

/// «millón/millones» no se truncan (POCO 2026-11-09): antes «ciento veinte
/// millones» valía 120 y el comparador lo daba por igual a «120». TEXTO
/// INYECTADO, sintético; no prueba el reconocimiento.
void main() {
  SpokenNumber? read(String text) => readNumberAt(tokenize(text), 0);

  test('una cifra seguida de millones queda no válida, con lo oído', () {
    for (final text in const [
      'ciento veinte millones de litros',
      'dos millones',
      'un millón de litros',
      '120 millones',
    ]) {
      final n = read(text)!;
      expect(n.isValid, isFalse, reason: text);
      expect(n.heard, contains('mill'), reason: text);
    }
  });

  test('mil sigue leyéndose', () {
    expect(read('ciento veinte mil litros')!.thousandths, 120000000);
    expect(read('dos mil setecientos')!.thousandths, 2700000);
  });

  test('el comparador ya no da «ciento veinte millones» por igual a «120»', () {
    const vosk = 'y cinco litros a ciento veinte millones de litros';
    const review = 'Compré 5 litros a 120 bolivianos de litro.';
    expect(
      chooseReviewedText(vosk, review, facts: voiceQuantityFacts).verdict,
      ReviewVerdict.quantities,
    );
    final kinds = classifyFactDifferences(
      voiceQuantityFacts(vosk),
      voiceQuantityFacts(review),
    ).map((d) => d.kind);
    expect(kinds, contains(DiscrepancyKind.extractionFailed));
  });
}
