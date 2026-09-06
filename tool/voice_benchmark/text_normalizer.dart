/// Normalización de texto para comparar lo dictado con lo transcrito.
///
/// HERRAMIENTA DE DESARROLLO. No se compila dentro de la aplicación: vive en
/// `tool/` y sólo la usa el agregador de resultados del benchmark de voz
/// (EVOLUTION-3, Fase 0). No es el parser numérico del dominio: ese es
/// `lib/domain/numeric_input.dart` y no se toca.
///
/// ## Por qué hace falta
///
/// El corpus está escrito para leerse en voz alta ("cincuenta litros"), pero un
/// reconocedor suele devolver dígitos ("50 litros"). Comparar tal cual daría un
/// error donde el motor acertó. Aquí se llevan ambos lados a la misma forma
/// antes de medir, y se informa también la comparación cruda para no esconder
/// el efecto de esta normalización.
library;

const _unidades = <String, int>{
  'cero': 0,
  'un': 1,
  'uno': 1,
  'una': 1,
  'dos': 2,
  'tres': 3,
  'cuatro': 4,
  'cinco': 5,
  'seis': 6,
  'siete': 7,
  'ocho': 8,
  'nueve': 9,
  'diez': 10,
  'once': 11,
  'doce': 12,
  'trece': 13,
  'catorce': 14,
  'quince': 15,
  'dieciseis': 16,
  'diecisiete': 17,
  'dieciocho': 18,
  'diecinueve': 19,
  'veinte': 20,
  'veintiuno': 21,
  'veintiun': 21,
  'veintidos': 22,
  'veintitres': 23,
  'veinticuatro': 24,
  'veinticinco': 25,
  'veintiseis': 26,
  'veintisiete': 27,
  'veintiocho': 28,
  'veintinueve': 29,
  'treinta': 30,
  'cuarenta': 40,
  'cincuenta': 50,
  'sesenta': 60,
  'setenta': 70,
  'ochenta': 80,
  'noventa': 90,
};

const _centenas = <String, int>{
  'cien': 100,
  'ciento': 100,
  'doscientos': 200,
  'doscientas': 200,
  'trescientos': 300,
  'trescientas': 300,
  'cuatrocientos': 400,
  'cuatrocientas': 400,
  'quinientos': 500,
  'quinientas': 500,
  'seiscientos': 600,
  'seiscientas': 600,
  'setecientos': 700,
  'setecientas': 700,
  'ochocientos': 800,
  'ochocientas': 800,
  'novecientos': 900,
  'novecientas': 900,
};

/// Quita tildes, pasa a minúsculas y deja sólo letras, dígitos y comas.
String canonical(String input) {
  const acentos = 'áàäâéèëêíìïîóòöôúùüûñç';
  const planas = 'aaaaeeeeiiiioooouuuunc';
  final buffer = StringBuffer();
  for (final rune in input.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    final index = acentos.indexOf(char);
    if (index >= 0) {
      buffer.write(planas[index]);
    } else if (RegExp('[a-z0-9,]').hasMatch(char)) {
      buffer.write(char);
    } else {
      buffer.write(' ');
    }
  }
  return _commasOnlyBetweenDigits(buffer.toString())
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Deja la coma sólo cuando separa decimales (`12,5`).
///
/// La coma de puntuación ("Compré, señor") no debe pegarse a la palabra: si
/// sobrevive, `compre,` y `compre` cuentan como palabras distintas y el WER
/// castiga una transcripción correcta.
String _commasOnlyBetweenDigits(String input) {
  final buffer = StringBuffer();
  for (var i = 0; i < input.length; i++) {
    final char = input[i];
    if (char != ',') {
      buffer.write(char);
      continue;
    }
    final previous = i > 0 ? input[i - 1] : '';
    final next = i + 1 < input.length ? input[i + 1] : '';
    final isDecimal =
        RegExp('[0-9]').hasMatch(previous) && RegExp('[0-9]').hasMatch(next);
    buffer.write(isDecimal ? ',' : ' ');
  }
  return buffer.toString();
}

/// Convierte los números escritos con palabras en dígitos.
///
/// Cubre 0–999.999, la conjunción `y` y el decimal dicho con `coma`. No
/// pretende ser exhaustivo: cubre el rango del corpus, y lo que no reconoce lo
/// deja tal cual en lugar de adivinar.
String normalizeNumbers(String input) {
  final words = canonical(input).split(' ');
  final out = <String>[];

  var i = 0;
  while (i < words.length) {
    final consumed = _readNumber(words, i);
    if (consumed == null) {
      out.add(words[i]);
      i++;
      continue;
    }
    var text = '${consumed.value}';
    var next = consumed.nextIndex;
    // Decimal dictado: "doce coma cinco" -> "12,5".
    if (next + 1 < words.length && words[next] == 'coma') {
      final decimal = _readNumber(words, next + 1);
      if (decimal != null) {
        text = '$text,${decimal.value}';
        next = decimal.nextIndex;
      }
    }
    out.add(text);
    i = next;
  }
  return out.join(' ');
}

class _Number {
  const _Number(this.value, this.nextIndex);

  final int value;
  final int nextIndex;
}

_Number? _readNumber(List<String> words, int start) {
  var i = start;
  var total = 0;
  var current = 0;
  var matched = false;

  while (i < words.length) {
    final word = words[i];

    if (word == 'mil') {
      // "mil" sin nada delante vale 1000.
      current = current == 0 ? 1 : current;
      total += current * 1000;
      current = 0;
      matched = true;
      i++;
      continue;
    }
    if (_centenas.containsKey(word)) {
      current += _centenas[word]!;
      matched = true;
      i++;
      continue;
    }
    if (_unidades.containsKey(word)) {
      current += _unidades[word]!;
      matched = true;
      i++;
      continue;
    }
    // "cuarenta y cinco": la conjuncion solo sigue si despues viene un numero.
    if (word == 'y' &&
        matched &&
        i + 1 < words.length &&
        (_unidades.containsKey(words[i + 1]) ||
            _centenas.containsKey(words[i + 1]))) {
      i++;
      continue;
    }
    break;
  }

  if (!matched) return null;
  return _Number(total + current, i);
}

/// Texto listo para comparar: sin tildes, sin puntuación y con los números en
/// dígitos.
String comparable(String input) => normalizeNumbers(input);

/// Palabras de [text], ya normalizado.
List<String> tokens(String text) {
  final normalized = comparable(text);
  return normalized.isEmpty ? const [] : normalized.split(' ');
}

/// Tasa de error por palabra (WER) entre [reference] y [hypothesis].
///
/// Es la distancia de edición sobre palabras dividida por el largo de la
/// referencia. `0` es transcripción idéntica; puede superar `1` si el motor
/// inventa más palabras de las que había.
double wordErrorRate(String reference, String hypothesis) {
  final ref = tokens(reference);
  final hyp = tokens(hypothesis);
  if (ref.isEmpty) return hyp.isEmpty ? 0 : 1;

  var previous = List<int>.generate(hyp.length + 1, (j) => j);
  for (var i = 1; i <= ref.length; i++) {
    final current = List<int>.filled(hyp.length + 1, 0);
    current[0] = i;
    for (var j = 1; j <= hyp.length; j++) {
      final cost = ref[i - 1] == hyp[j - 1] ? 0 : 1;
      current[j] = [
        current[j - 1] + 1,
        previous[j] + 1,
        previous[j - 1] + cost,
      ].reduce((a, b) => a < b ? a : b);
    }
    previous = current;
  }
  return previous[hyp.length] / ref.length;
}

/// `true` si [hypothesis] contiene todas las palabras de [needle].
///
/// Se usa para los datos críticos: interesa saber si el producto, la cantidad o
/// el precio sobrevivieron a la transcripción, no en qué posición quedaron.
bool containsAllTokens(String hypothesis, String needle) {
  final hyp = tokens(hypothesis).toSet();
  final wanted = tokens(needle);
  if (wanted.isEmpty) return false;
  return wanted.every(hyp.contains);
}
