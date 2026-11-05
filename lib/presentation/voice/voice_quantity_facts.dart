/// Qué cantidades, unidades y monedas leería la app en un texto dictado.
///
/// Lo usa la segunda pasada de voz local (#166) para no aceptar nunca una
/// revisión que cambie lo que después se interpreta. Vive aquí, y no en
/// `lib/voice/`, porque la captura no conoce los borradores; se inyecta al
/// arrancar (`reviewFactsProvider`). Usa el mismo lector que el intérprete.
library;

import '../../voice_draft/text/normalize.dart' show tokenize;
import '../../voice_draft/text/spanish_numbers.dart' show readNumberAt;
import '../../voice_draft/text/units.dart' show currencyWord, unitWord;

/// Cantidades (en milésimas), unidades y monedas, en orden. `n?` es una cifra
/// que el lector rechaza («1,500» es ambiguo).
List<String> voiceQuantityFacts(String text) {
  final words = tokenize(text);
  final out = <String>[];
  var i = 0;
  while (i < words.length) {
    final number = readNumberAt(words, i);
    if (number != null && number.end > i) {
      out.add(number.isValid ? 'n${number.thousandths}' : 'n?');
      i = number.end;
      continue;
    }
    final unit = unitWord(words[i]);
    if (unit != null) out.add('u${unit.name}');
    final currency = currencyWord(words[i]);
    if (currency != null) out.add('c${currency.name}');
    i++;
  }
  return out;
}
