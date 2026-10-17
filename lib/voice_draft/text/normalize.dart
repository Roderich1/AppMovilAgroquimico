/// Normalización del texto dictado para interpretarlo (EVO-010).
///
/// Sólo sirve para **comparar**: el texto original se conserva aparte y es el
/// que se muestra junto a cada campo («oído: …»). Nada de lo que hay aquí
/// sustituye el nombre de un producto o de una persona del catálogo.
library;

import 'spanish_numbers.dart';

const _accents = {
  'á': 'a',
  'à': 'a',
  'ä': 'a',
  'é': 'e',
  'è': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ö': 'o',
  'ú': 'u',
  'ù': 'u',
  'ü': 'u',
  'ñ': 'n',
};

/// Minúsculas y sin tildes. La «ñ» pasa a «n» sólo para comparar.
String fold(String text) {
  final lower = text.toLowerCase();
  final out = StringBuffer();
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    out.write(_accents[ch] ?? ch);
  }
  return out.toString();
}

/// Separa en palabras. Las comas y puntos que separan frases se devuelven
/// como la palabra `,`; los que están dentro de una cifra («1.500», «1,5») se
/// conservan en ella, porque los interpreta el parser central.
List<String> tokenize(String text) {
  final folded = fold(text)
      .replaceAll(' ', ' ')
      .replaceAll(RegExp(r'[-–—/]'), ' ')
      .replaceAll(RegExp(r'[¿?¡!;:"“”«»()]'), ' ');
  final words = <String>[];
  for (final raw in folded.split(RegExp(r'\s+'))) {
    if (raw.isEmpty) continue;
    var word = raw;
    var trailingPause = false;
    while (word.isNotEmpty && (word.endsWith(',') || word.endsWith('.'))) {
      word = word.substring(0, word.length - 1);
      trailingPause = true;
    }
    while (word.isNotEmpty && (word.startsWith(',') || word.startsWith('.'))) {
      word = word.substring(1);
    }
    if (word.isNotEmpty) words.add(word);
    if (trailingPause) words.add(',');
  }
  return words;
}

/// Forma canónica de un nombre para compararlo con lo dictado: palabras
/// normalizadas y los números, dichos o escritos, como cifra.
///
/// Así «Germi-100», «germi 100» y «germi cien» comparan igual, sin añadir
/// ningún alias al catálogo.
List<String> canonicalTokens(String text) {
  final words = tokenize(text).where((w) => w != ',').toList();
  final out = <String>[];
  var i = 0;
  while (i < words.length) {
    final number = readNumberAt(words, i);
    if (number != null && number.end > i) {
      out.add(_digits(number.thousandths));
      i = number.end;
    } else {
      out.add(words[i]);
      i++;
    }
  }
  return out;
}

String canonicalName(String text) => canonicalTokens(text).join(' ');

String _digits(int thousandths) {
  final whole = thousandths ~/ 1000;
  final fraction = thousandths % 1000;
  if (fraction == 0) return '$whole';
  final decimals = fraction
      .toString()
      .padLeft(3, '0')
      .replaceAll(RegExp(r'0+$'), '');
  return '$whole,$decimals';
}
