/// Qué texto entrega una frase cuando hay segunda pasada local (#166).
///
/// Vosk escucha en vivo; whisper.cpp vuelve a transcribir la misma frase con la
/// pista de vocabulario del catálogo. A la sesión llega **una sola** de las dos,
/// nunca una mezcla, y la regla es conservadora: la segunda pasada sólo puede
/// cambiar palabras, **nunca cantidades, unidades ni monedas**.
///
/// La captura no conoce los borradores (lo vigila la guarda de arquitectura):
/// qué es una cantidad lo decide una [ReviewFacts] que se inyecta desde la
/// presentación (`voiceQuantityFacts`, con el lector de la propia app). Sin
/// ella no se puede comprobar nada y la revisión **no se acepta nunca**.
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

/// Cantidades, unidades y monedas de un texto, en orden y en forma comparable.
///
/// `n?` marca una cifra que el lector rechaza; nunca es igual a otra.
typedef ReviewFacts = List<String> Function(String text);

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

  /// No hay con qué comprobar las cantidades: no se arriesga.
  unchecked,

  /// La revisión no llegó dentro del tope por frase: se entregó el texto de
  /// la primera pasada sin esperar más, y lo que llegue después se descarta.
  timedOut,
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
ReviewChoice chooseReviewedText(
  String first,
  String? review, {
  required ReviewFacts? facts,
}) {
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
  if (facts == null) return ReviewChoice(base, ReviewVerdict.unchecked);
  if (!_sameFacts(facts(base), facts(candidate))) {
    return ReviewChoice(base, ReviewVerdict.quantities);
  }
  return ReviewChoice(candidate, ReviewVerdict.accepted);
}

/// Palabras en minúsculas, sin puntuación. Sólo para contar y comparar.
List<String> _words(String text) => RegExp(r'[\p{L}\p{N}]+', unicode: true)
    .allMatches(text.toLowerCase())
    .map((m) => m.group(0)!)
    .toList(growable: false);

bool _looksLikeNonSpeech(String text) {
  if (RegExp(r'[\[\]()♪*#]').hasMatch(text)) return true;
  final folded = _words(text)
      .join(' ')
      .replaceAll('í', 'i')
      .replaceAll('é', 'e');
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

bool _sameFacts(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i] || a[i] == 'n?') return false;
  }
  return true;
}
