/// Frases comunes a los intérpretes de compra, planificación y aplicación:
/// la misma regla para resolver un nombre, un chaco o un área en las tres.
library;

import '../catalog/voice_catalog.dart';
import '../core/draft_field.dart';
import '../text/spanish_numbers.dart';
import '../text/units.dart';

const hectareWords = {'hectarea', 'hectareas', 'ha'};
const farmKeywords = {'chaco', 'parcela'};

/// Convierte una resolución de catálogo en un campo del borrador.
DraftField<CatalogEntry> entryField(Resolution r, String what) =>
    switch (r.state) {
      ResolutionState.resolved => DraftField.resolved(
        r.entry!,
        origin: FieldOrigin.voice,
        heard: r.heard,
      ),
      ResolutionState.ambiguous => DraftField.ambiguous(
        candidates: r.candidates,
        heard: r.heard,
        message: 'Elija el $what entre las opciones.',
      ),
      ResolutionState.missing => DraftField.missing(
        heard: r.heard,
        // La voz no crea nada (D-F09-2). Que se ofrezca o no el alta en el
        // selector lo dice cada pantalla.
        message:
            '«${r.heard}» no está en el catálogo. Elija uno existente; la voz '
            'no crea nada nuevo.',
      ),
    };

/// Una cantidad con su unidad, tal como se dice: «dos litros», «medio kilo»,
/// «un litro y medio», «litro y medio», «1 kilo y medio» o «tres hectáreas
/// y media».
///
/// POCO §2.1 (2026-11-05): «un litro y medio de glifosato» se leía como 1 L
/// y el producto «y medio de glifosato». El medio dicho **después** de la
/// unidad es parte de la cantidad, no del nombre. Es una regla del español
/// hablado, no de ningún producto.
final class SpokenMeasure {
  const SpokenMeasure({
    required this.thousandths,
    required this.start,
    required this.unitIndex,
    required this.end,
    required this.numberHeard,
    required this.words,
    this.invalidMessage,
  });

  /// Valor × 1000, exacto, con el medio ya sumado.
  final int thousandths;

  /// Primera palabra de la cantidad (el número, o la unidad si no se dijo
  /// número: «litro y medio»).
  final int start;

  /// Palabra de la unidad.
  final int unitIndex;

  /// Primera palabra después de toda la cantidad (unidad y medio incluidos).
  final int end;

  /// El número tal como se oyó, sin la unidad («uno cinco», «un»).
  final String numberHeard;

  final List<String> words;

  /// Se dijo algo que no se puede leer sin adivinar («1,5 litros y medio»).
  final String? invalidMessage;

  bool get isValid => invalidMessage == null;

  String get unitWord => words[unitIndex];

  /// Toda la cantidad tal como se oyó («un litro y medio»).
  String get heard => words.sublist(start, end).join(' ');
}

/// Unidades que se dicen sin número con «y medio»: «litro y medio».
const _singularUnits = {'litro', 'kilo', 'kilogramo', 'hectarea'};

/// ¿Hay «y medio» o «y media» en [k] que pertenezca a la cantidad anterior?
/// No si lo que sigue es otra unidad: «dos litros y media hectárea» son dos
/// cantidades.
bool _halfAt(List<String> words, int k) {
  if (k + 1 >= words.length ||
      words[k] != 'y' ||
      (words[k + 1] != 'medio' && words[k + 1] != 'media')) {
    return false;
  }
  final next = k + 2 < words.length ? words[k + 2] : null;
  return next == null ||
      (unitWord(next) == null && !hectareWords.contains(next));
}

SpokenMeasure? _readWithUnit(
  List<String> words,
  int i,
  bool Function(String word) isUnit,
) {
  if (i >= words.length) return null;
  final n = readNumberAt(words, i);
  if (n != null) {
    if (n.end >= words.length || !isUnit(words[n.end])) return null;
    final half = _halfAt(words, n.end + 1);
    String? invalid = n.invalidMessage;
    if (half && invalid == null && n.thousandths % 1000 != 0) {
      invalid =
          'Se oyó «${words.sublist(n.start, n.end + 3).join(' ')}»: no se '
          'sabe cuánto es. Escriba la cantidad o vuelva a dictarla.';
    }
    return SpokenMeasure(
      thousandths: n.thousandths + (half && invalid == null ? 500 : 0),
      start: n.start,
      unitIndex: n.end,
      end: n.end + 1 + (half ? 2 : 0),
      numberHeard: n.heard,
      words: words,
      invalidMessage: invalid,
    );
  }
  // «litro y medio», «kilo y medio»: la unidad sola vale uno.
  if (isUnit(words[i]) &&
      _singularUnits.contains(words[i]) &&
      _halfAt(words, i + 1)) {
    return SpokenMeasure(
      thousandths: 1500,
      start: i,
      unitIndex: i,
      end: i + 3,
      numberHeard: '',
      words: words,
    );
  }
  return null;
}

/// Cantidad de producto que empieza en [i] («un litro y medio»), o `null`.
SpokenMeasure? readMeasureAt(List<String> words, int i) =>
    _readWithUnit(words, i, (w) => unitWord(w) != null);

/// Área que empieza en [i] («una hectárea y media»), o `null`.
SpokenMeasure? readAreaAt(List<String> words, int i) =>
    _readWithUnit(words, i, hectareWords.contains);

/// Una cantidad que llega justo después de otro número dicho («uno cinco
/// litros»): no se sabe cuál de los dos se quiso decir. La cantidad queda
/// inválida con ese motivo, en vez de tomar sólo el último (revisión de A,
/// M-2).
DraftField<T>? consecutiveNumbers<T>(List<String> words, SpokenMeasure m) {
  if (m.start == 0 || m.numberHeard.isEmpty) return null;
  final previous = readNumberAt(words, m.start - 1);
  if (previous == null || previous.end != m.start) return null;
  return DraftField.invalid(
    message:
        'Se oyeron dos números seguidos '
        '(«${words[m.start - 1]} ${m.numberHeard}»). '
        'Escriba la cantidad o vuelva a dictarla.',
    heard: '${words[m.start - 1]} ${m.heard}',
  );
}

/// Campo de una cantidad dicha: inválido si no se puede leer o es cero.
DraftField<T> measureField<T>(
  List<String> words,
  SpokenMeasure m,
  T Function(int thousandths) value, {
  required String zeroMessage,
  String? heard,
  String? invalidHeard,
}) {
  final said = heard ?? m.heard;
  final wrong = invalidHeard ?? said;
  return consecutiveNumbers<T>(words, m) ??
      (!m.isValid
          ? DraftField<T>.invalid(message: m.invalidMessage!, heard: wrong)
          : m.thousandths <= 0
          ? DraftField<T>.invalid(message: zeroMessage, heard: wrong)
          : DraftField.resolved(
              value(m.thousandths),
              origin: FieldOrigin.voice,
              heard: said,
            ));
}

/// ¿Empieza en [i] una cantidad («dos litros», «tres hectáreas», «litro y
/// medio»)?
bool startsQuantity(List<String> words, int i) =>
    readMeasureAt(words, i) != null || readAreaAt(words, i) != null;

/// «el chaco Norte», «la parcela Los Limoncitos»: la palabra clave y el
/// nombre que la sigue.
(String, String)? findFarm(List<String> words) {
  for (var i = 0; i < words.length; i++) {
    if (!farmKeywords.contains(words[i])) continue;
    final out = <String>[];
    for (var j = i + 1; j < words.length; j++) {
      final w = words[j];
      if (const {',', 'y', 'con', 'en', 'para', 'a', 'al'}.contains(w)) break;
      if (startsQuantity(words, j)) break;
      out.add(w);
    }
    if (out.isNotEmpty) return (words[i], out.join(' '));
  }
  return null;
}

/// Resuelve el chaco dicho. «el chaco Titular» puede referirse a «Titular» o
/// a «Chaco titular»: se prueba sin y con la palabra clave, y sólo vale una
/// coincidencia exacta única.
Resolution resolveFarm((String, String) said, List<CatalogEntry> farms) {
  final plain = resolveName(said.$2, farms);
  if (plain.state == ResolutionState.resolved) return plain;
  final withKeyword = resolveName('${said.$1} ${said.$2}', farms);
  return withKeyword.state == ResolutionState.resolved ? withKeyword : plain;
}

/// «en cinco hectáreas»: un número seguido directamente de «hectáreas», que
/// no sea una dosis («por hectárea»). En m².
DraftField<int>? findArea(List<String> words) {
  for (var i = 0; i < words.length; i++) {
    final m = readAreaAt(words, i);
    if (m == null) continue;
    if (i > 0 && words[i - 1] == 'por') continue;
    final heard = m.heard;
    if (!m.isValid || m.thousandths <= 0) {
      return DraftField.invalid(
        message: m.invalidMessage ?? 'El área debe ser mayor a cero.',
        heard: heard,
      );
    }
    // 1 ha = 10 000 m²; una milésima de hectárea son 10 m².
    return DraftField.resolved(
      m.thousandths * 10,
      origin: FieldOrigin.voice,
      heard: heard,
    );
  }
  return null;
}
