/// Qué texto entrega una frase cuando hay segunda pasada local (#166).
///
/// Vosk escucha en vivo; whisper.cpp vuelve a transcribir la misma frase con la
/// pista de vocabulario del catálogo. A la sesión llega **una sola** de las dos,
/// nunca una mezcla, y la regla es conservadora: la segunda pasada sólo puede
/// cambiar palabras, **nunca cantidades, unidades ni monedas**.
///
/// ## Por qué así
///
/// En la comprobación HOST de 2026-11-05 la segunda pasada con pista acertó
/// muchos más productos (39/45 frente a 21/45), pero cambió cantidades que Vosk
/// había oído bien («dos litros» → «3 litros»). Esa es justo la clase de error
/// que no puede colarse en un borrador. Por eso se compara lo que **el lector
/// numérico de la propia app** obtendría de cada texto: si no coincide en todo,
/// se queda el de Vosk. Comparar con el mismo lector que usa el intérprete
/// garantiza que la revisión no altera lo que después se interpreta; el texto
/// no se normaliza ni se reescribe aquí.
///
/// Tampoco se acepta texto típico de alucinación sobre ruido («[MÚSICA]»,
/// «Subtítulos por…»), repeticiones degeneradas ni cambios de longitud
/// desproporcionados.
library;

import '../../voice_draft/text/normalize.dart' show tokenize;
import '../../voice_draft/text/spanish_numbers.dart' show readNumberAt;
import '../../voice_draft/text/units.dart' show currencyWord, unitWord;

/// Por qué se eligió un texto. Sólo códigos: va al diagnóstico, nunca el texto.
enum ReviewVerdict {
  /// Se usa el texto de la segunda pasada.
  accepted,

  /// No hubo segunda pasada para esta frase (no disponible, desactivada,
  /// cola llena o abortada).
  notRun,

  /// La segunda pasada no devolvió nada.
  empty,

  /// Marcas de no-habla o frases típicas de alucinación.
  nonSpeech,

  /// Repeticiones o longitud desproporcionada.
  degenerate,

  /// Cambiaría una cantidad, una unidad o una moneda.
  quantities,
}

final class ReviewChoice {
  const ReviewChoice(this.text, this.verdict);

  final String text;
  final ReviewVerdict verdict;

  bool get revised => verdict == ReviewVerdict.accepted;

  @override
  String toString() => 'ReviewChoice(${verdict.name}, chars=${text.length})';
}

/// Elige entre [first] (Vosk) y [review] (segunda pasada, o `null`).
ReviewChoice chooseReviewedText(String first, String? review) {
  final base = first.trim();
  final candidate = review?.trim() ?? '';
  if (review == null) return ReviewChoice(base, ReviewVerdict.notRun);
  if (candidate.isEmpty) return ReviewChoice(base, ReviewVerdict.empty);
  if (_looksLikeNonSpeech(candidate)) {
    return ReviewChoice(base, ReviewVerdict.nonSpeech);
  }

  final a = _words(base);
  final b = _words(candidate);
  if (b.length > a.length * 2 + 4 || b.length * 2 < a.length || _repeats(b)) {
    return ReviewChoice(base, ReviewVerdict.degenerate);
  }
  if (!_sameFacts(_facts(tokenize(base)), _facts(tokenize(candidate)))) {
    return ReviewChoice(base, ReviewVerdict.quantities);
  }
  return ReviewChoice(candidate, ReviewVerdict.accepted);
}

List<String> _words(String text) =>
    tokenize(text).where((w) => w != ',').toList(growable: false);

bool _looksLikeNonSpeech(String text) {
  if (RegExp(r'[\[\]()♪*#]').hasMatch(text)) return true;
  final folded = tokenize(text).join(' ');
  return const [
    'subtitulo',
    'amara',
    'gracias por ver',
    'suscribete',
  ].any(folded.contains);
}

/// La misma palabra cuatro veces seguidas: el bucle típico del decodificador.
bool _repeats(List<String> words) {
  var run = 1;
  for (var i = 1; i < words.length; i++) {
    run = words[i] == words[i - 1] ? run + 1 : 1;
    if (run >= 4) return true;
  }
  return false;
}

/// Cantidades, unidades y monedas en orden, tal como las leería la app.
List<String> _facts(List<String> words) {
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

bool _sameFacts(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i] || a[i] == 'n?') return false;
  }
  return true;
}
