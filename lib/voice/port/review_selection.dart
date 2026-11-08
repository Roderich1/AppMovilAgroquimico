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
///
/// ## Formato frente a valor (POCO 2026-11-08)
///
/// Que la revisión no coincida **no demuestra que Vosk tenga razón**: en el
/// POCO, 4 de 12 frases de compra acabaron en `quantities` y en una el precio
/// de Vosk era el equivocado. Por eso se distinguen dos casos:
///
/// * **Mismo valor, otra forma** («1,5 litros», «uno y medio litros», «un litro
///   y medio», «1.5 litros»): no hay desacuerdo. Si el lector de la app lee la
///   revisión igual, se acepta; si sólo la entiende con una lectura tolerante
///   («1.5», que el convenio es-BO rechaza), queda Vosk ([ReviewVerdict.format]),
///   también sin desacuerdo.
/// * **Otro valor** («veinte» frente a «ciento veinte»): queda el texto de
///   Vosk —una sola transcripción, sin mezclar— y la frase lleva la marca
///   [ReviewChoice.numericDisagreement]. La marca no lleva texto; quien
///   interpreta decide qué campos quedan por revisar.
///
/// Sin segunda lectura válida (no llegó, vacía, no-habla, degenerada o sin
/// lector) no hay nada con qué discrepar: nunca es desacuerdo.
library;

/// Cantidades, unidades y monedas de un texto, en orden y en forma comparable.
///
/// Cada elemento es `n<milésimas>`, `u<unidad>` o `c<moneda>`. Una cifra que el
/// lector de la app rechaza se marca con `n?`: sola si no tiene un valor
/// seguro («1,500» es ambiguo), o `n?<milésimas>` si una lectura tolerante sí
/// lo tiene («1.5» → `n?1500`). Ninguna `n?` cuenta como igual a otra para
/// aceptar la revisión; `n?<v>` sólo sirve para reconocer que el valor es el
/// mismo y que la diferencia es de formato.
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

  /// Los dos reconocedores leen **valores distintos** de cantidad, unidad o
  /// moneda. Queda Vosk y la frase lleva la marca de desacuerdo numérico.
  quantities,

  /// Las mismas cantidades, unidades y monedas escritas de una forma que el
  /// lector de la app no acepta («1.5 litros»). Queda Vosk, que sí se lee, y
  /// no es desacuerdo: la diferencia es sólo de formato.
  format,

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

  /// Hubo una segunda lectura válida y sus cifras no coinciden en valor con
  /// las de [text] (que es la de Vosk). No lleva texto de ninguno de los dos.
  bool get numericDisagreement => verdict == ReviewVerdict.quantities;

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
  return switch (_compareFacts(facts(base), facts(candidate))) {
    _FactsMatch.same => ReviewChoice(candidate, ReviewVerdict.accepted),
    _FactsMatch.sameValues => ReviewChoice(base, ReviewVerdict.format),
    _FactsMatch.different => ReviewChoice(base, ReviewVerdict.quantities),
  };
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

enum _FactsMatch {
  /// Iguales y legibles por la app: la revisión se puede aceptar.
  same,

  /// Mismos valores, pero alguna cifra sólo se entiende con la lectura
  /// tolerante: diferencia de formato.
  sameValues,

  /// Algún valor, unidad o moneda distinto, o una cifra sin valor seguro.
  different,
}

_FactsMatch _compareFacts(List<String> a, List<String> b) {
  if (a.length != b.length) return _FactsMatch.different;
  var readable = true;
  for (var i = 0; i < a.length; i++) {
    if (a[i] == b[i] && !a[i].startsWith('n?')) continue;
    readable = false;
    final x = _valueOf(a[i]);
    if (x == null || x != _valueOf(b[i])) return _FactsMatch.different;
  }
  return readable ? _FactsMatch.same : _FactsMatch.sameValues;
}

/// El valor de un hecho, venga de la lectura de la app o de la tolerante;
/// `null` si no hay valor seguro (`n?` sola).
String? _valueOf(String fact) {
  if (!fact.startsWith('n?')) return fact;
  return fact.length > 2 ? 'n${fact.substring(2)}' : null;
}
