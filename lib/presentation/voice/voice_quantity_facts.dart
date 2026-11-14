/// Qué cantidades, unidades y monedas leería la app en un texto dictado.
///
/// Lo usa la segunda pasada de voz local (#166) para no aceptar nunca una
/// revisión que cambie lo que después se interpreta. Vive aquí, y no en
/// `lib/voice/`, porque la captura no conoce los borradores; se inyecta al
/// arrancar (`reviewFactsProvider`). Usa el mismo lector que el intérprete.
///
/// ## Valor, no forma (POCO 2026-11-08)
///
/// Lee las cantidades **como las lee el intérprete** (`readMeasureAt` y
/// `readAreaAt`, con el «y medio» dicho después de la unidad), no número a
/// número. Antes «un litro y medio» daba `n1000 uliter n500` y «1,5 litros»
/// `n1500 uliter`: la misma cantidad parecía un desacuerdo. Ahora las dos dan
/// `n1500 uliter`, igual que «uno y medio litros» y «litro y medio».
///
/// Las palabras que no son cifras, unidades ni monedas no cuentan, ni la
/// puntuación ni las mayúsculas.
library;

import '../../voice_draft/interpretation/phrases.dart'
    show hectareWords, readAreaAt, readMeasureAt, SpokenMeasure;
import '../../voice_draft/text/normalize.dart' show tokenize;
import '../../voice_draft/text/spanish_numbers.dart' show readNumberAt;
import '../../voice_draft/text/units.dart' show currencyWord, unitWord;

/// Unidad de área: el intérprete lee «hectáreas» aparte de litros y kilos.
const _hectare = 'uha';

/// Cantidades (en milésimas), unidades y monedas, en orden. `n?` es una cifra
/// que el lector rechaza («1,500» es ambiguo); `n?<milésimas>` una que rechaza
/// pero que tiene un único valor posible («1.5», con punto decimal).
List<String> voiceQuantityFacts(String text) {
  final words = tokenize(text);
  final out = <String>[];
  var i = 0;
  while (i < words.length) {
    final measure = readMeasureAt(words, i);
    if (measure != null) {
      out
        ..add(_measureFact(words, measure))
        ..add('u${unitWord(measure.unitWord)!.name}');
      i = measure.end;
      continue;
    }
    final area = readAreaAt(words, i);
    if (area != null) {
      out
        ..add(_measureFact(words, area))
        ..add(_hectare);
      i = area.end;
      continue;
    }
    final number = readNumberAt(words, i);
    if (number != null && number.end > i) {
      out.add(
        number.isValid ? 'n${number.thousandths}' : _unreadable(words[i]),
      );
      i = number.end;
      continue;
    }
    final unit = unitWord(words[i]);
    if (unit != null) out.add('u${unit.name}');
    if (hectareWords.contains(words[i])) out.add(_hectare);
    final currency = currencyWord(words[i]);
    if (currency != null) out.add('c${currency.name}');
    i++;
  }
  return out;
}

/// Marca de papel: la cifra que sigue es un **precio** (POCO 2026-11-09).
const priceRoleFact = 'P';

/// Como [voiceQuantityFacts], pero con el **papel** de cada cifra para el
/// diagnóstico y la política B: antes de una cifra que es precio va
/// [priceRoleFact]. La regla A sigue usando [voiceQuantityFacts], sin
/// cambios, para seguir siendo reproducible.
///
/// Una cifra es precio si no va pegada a una unidad (eso es cantidad) y:
/// - la precede «a», «al» o «precio»; o
/// - la sigue una moneda; o
/// - la sigue (con una palabra de más como mucho) «el/la/de/del/por/cada»
///   + unidad («120V de litro», «120 boliganos del litro»).
///
/// Una cifra ilegible conserva su papel («120V» sigue siendo el precio) sin
/// limpiarse ni convertirse en otra cosa.
List<String> voiceFieldFacts(String text) {
  final words = tokenize(text);
  final out = <String>[];
  var i = 0;
  bool perUnitAfter(int k) {
    for (final skip in const [0, 1]) {
      final a = k + skip;
      if (a + 1 < words.length &&
          const {'el', 'la', 'de', 'del', 'por', 'cada'}.contains(words[a]) &&
          unitWord(words[a + 1]) != null) {
        return true;
      }
    }
    return false;
  }

  while (i < words.length) {
    final measure = readMeasureAt(words, i);
    if (measure != null) {
      out
        ..add(_measureFact(words, measure))
        ..add('u${unitWord(measure.unitWord)!.name}');
      i = measure.end;
      continue;
    }
    final area = readAreaAt(words, i);
    if (area != null) {
      out
        ..add(_measureFact(words, area))
        ..add(_hectare);
      i = area.end;
      continue;
    }
    final number = readNumberAt(words, i);
    if (number != null && number.end > i) {
      final prev = i > 0 ? words[i - 1] : null;
      final next = number.end < words.length ? words[number.end] : null;
      final isPrice =
          const {'a', 'al', 'precio'}.contains(prev) ||
          (next != null && currencyWord(next) != null) ||
          perUnitAfter(number.end) ||
          (next != null &&
              currencyWord(next) == null &&
              perUnitAfter(number.end + 1) &&
              unitWord(next) == null);
      if (isPrice) out.add(priceRoleFact);
      out.add(
        number.isValid ? 'n${number.thousandths}' : _unreadable(words[i]),
      );
      i = number.end;
      continue;
    }
    final unit = unitWord(words[i]);
    if (unit != null) out.add('u${unit.name}');
    if (hectareWords.contains(words[i])) out.add(_hectare);
    final currency = currencyWord(words[i]);
    if (currency != null) out.add('c${currency.name}');
    i++;
  }
  return out;
}

String _measureFact(List<String> words, SpokenMeasure m) {
  if (m.isValid) return 'n${m.thousandths}';
  // Una cifra de una sola palabra que el lector rechaza, sin «y medio».
  if (m.unitIndex == m.start + 1 && m.end == m.unitIndex + 1) {
    return _unreadable(words[m.start]);
  }
  return 'n?';
}

/// Cifra escrita que el convenio es-BO rechaza. Si un punto seguido de una o
/// dos cifras («1.5», «2.75») sólo puede ser decimal —un punto de miles
/// siempre va seguido de tres—, se anota su valor para reconocer que es la
/// misma cantidad dicha de otra forma. Todo lo demás queda sin valor.
String _unreadable(String word) {
  final decimal = RegExp(r'^(\d+)\.(\d{1,2})$').firstMatch(word);
  if (decimal == null) return 'n?';
  final whole = int.tryParse(decimal.group(1)!);
  if (whole == null || whole > 1000000000) return 'n?';
  final fraction = int.parse(decimal.group(2)!.padRight(3, '0'));
  return 'n?${whole * 1000 + fraction}';
}
