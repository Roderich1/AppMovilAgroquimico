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
        message:
            '«${r.heard}» no está en el catálogo. Elija uno existente; si es '
            'nuevo, créelo primero en Catálogos.',
      ),
    };

/// Una cantidad que llega justo después de otro número dicho («uno cinco
/// litros»): no se sabe cuál de los dos se quiso decir. La cantidad queda
/// inválida con ese motivo, en vez de tomar sólo el último (revisión de A,
/// M-2).
DraftField<T>? consecutiveNumbers<T>(
  List<String> words,
  SpokenNumber n,
  String unitWord,
) {
  if (n.start == 0) return null;
  final previous = readNumberAt(words, n.start - 1);
  if (previous == null || previous.end != n.start) return null;
  return DraftField.invalid(
    message:
        'Se oyeron dos números seguidos («${words[n.start - 1]} ${n.heard}»). '
        'Escriba la cantidad o vuelva a dictarla.',
    heard: '${words[n.start - 1]} ${n.heard} $unitWord',
  );
}

/// ¿Empieza en [i] una cantidad («dos litros», «tres hectáreas»)?
bool startsQuantity(List<String> words, int i) {
  final n = readNumberAt(words, i);
  return n != null &&
      n.end < words.length &&
      (unitWord(words[n.end]) != null || hectareWords.contains(words[n.end]));
}

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
    final n = readNumberAt(words, i);
    if (n == null ||
        n.end >= words.length ||
        !hectareWords.contains(words[n.end])) {
      continue;
    }
    if (i > 0 && words[i - 1] == 'por') continue;
    final heard = '${n.heard} ${words[n.end]}';
    if (!n.isValid || n.thousandths <= 0) {
      return DraftField.invalid(
        message: n.invalidMessage ?? 'El área debe ser mayor a cero.',
        heard: heard,
      );
    }
    // 1 ha = 10 000 m²; una milésima de hectárea son 10 m².
    return DraftField.resolved(
      n.thousandths * 10,
      origin: FieldOrigin.voice,
      heard: heard,
    );
  }
  return null;
}
