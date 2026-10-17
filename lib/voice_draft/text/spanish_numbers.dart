/// Números dictados en español → valores exactos, sin `double`.
///
/// EVO-010: «Reutilizar el parser y políticas numéricas centrales; no crear
/// aritmética con double». Las cifras escritas con dígitos pasan por
/// [parseBaseQuantity], el mismo parser es-BO de los formularios; aquí sólo se
/// añaden los números dichos con palabras, que el reconocedor a veces entrega
/// así («cincuenta», «ciento ochenta y seis», «dos mil setecientos»).
///
/// El valor se expresa en milésimas para admitir «y medio» y «coma cinco» sin
/// redondear. Quien lo usa lo convierte a la unidad del dominio con aritmética
/// entera.
library;

import '../../domain/numeric_input.dart';

/// Un número encontrado en una lista de palabras normalizadas.
final class SpokenNumber {
  const SpokenNumber({
    required this.thousandths,
    required this.start,
    required this.end,
    required this.heard,
    this.invalidMessage,
  });

  /// Valor × 1000, exacto. Sin sentido si [invalidMessage] no es nulo.
  final int thousandths;

  /// Primera palabra (inclusive) y última (exclusive).
  final int start;
  final int end;

  /// Las palabras tal como se oyeron.
  final String heard;

  /// Una cifra que el parser central rechaza («1,500» es ambiguo). Se marca
  /// inválida en lugar de adivinar.
  final String? invalidMessage;

  bool get isValid => invalidMessage == null;
}

const _units = <String, int>{
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
  'veintiun': 21,
  'veintiuno': 21,
  'veintiuna': 21,
  'veintidos': 22,
  'veintitres': 23,
  'veinticuatro': 24,
  'veinticinco': 25,
  'veintiseis': 26,
  'veintisiete': 27,
  'veintiocho': 28,
  'veintinueve': 29,
};

const _tens = <String, int>{
  'treinta': 30,
  'cuarenta': 40,
  'cincuenta': 50,
  'sesenta': 60,
  'setenta': 70,
  'ochenta': 80,
  'noventa': 90,
};

const _hundreds = <String, int>{
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

bool isNumberWord(String w) =>
    _units.containsKey(w) ||
    _tens.containsKey(w) ||
    _hundreds.containsKey(w) ||
    w == 'mil' ||
    w == 'medio' ||
    w == 'media' ||
    RegExp(r'^\d').hasMatch(w);

/// Busca el número que empieza en [start]; `null` si no hay ninguno.
///
/// Acepta «cincuenta», «ciento ochenta y seis», «dos mil setecientos»,
/// «medio», «uno y medio», «cinco coma cinco», «50», «1,5» y «1.500».
SpokenNumber? readNumberAt(List<String> words, int start) {
  if (start >= words.length) return null;
  final first = words[start];

  if (RegExp(r'^\d').hasMatch(first)) {
    final parsed = parseBaseQuantity(first);
    return SpokenNumber(
      thousandths: parsed.base ?? 0,
      start: start,
      end: start + 1,
      heard: first,
      invalidMessage: parsed.isValid ? null : parsed.message,
    );
  }
  if (first == 'medio' || first == 'media') {
    return SpokenNumber(
      thousandths: 500,
      start: start,
      end: start + 1,
      heard: first,
    );
  }

  var i = start;
  var total = 0;
  var group = 0;
  var any = false;
  // Lo que puede seguir dentro de un mismo grupo de tres cifras: centenas,
  // después decenas o un número de 1 a 29, y nada más. Así «uno cinco» no se
  // suma como 6: son dos números dichos seguidos y se lee sólo el primero.
  var slot = 0; // 0 libre, 1 tras centenas, 2 tras decenas/unidades.
  while (i < words.length) {
    final w = words[i];
    if (_hundreds.containsKey(w) && slot == 0) {
      group += _hundreds[w]!;
      slot = 1;
    } else if (_tens.containsKey(w) && slot < 2) {
      group += _tens[w]!;
      slot = 2;
      // «cincuenta y cinco»: la «y» sólo une decenas con unidades.
      if (i + 2 < words.length &&
          words[i + 1] == 'y' &&
          (_units[words[i + 2]] ?? 10) < 10) {
        group += _units[words[i + 2]]!;
        i += 2;
      }
    } else if (_units.containsKey(w) && slot < 2) {
      group += _units[w]!;
      slot = 2;
    } else if (w == 'mil' && total == 0) {
      total = (group == 0 ? 1 : group) * 1000;
      group = 0;
      slot = 0;
    } else {
      break;
    }
    any = true;
    i++;
  }
  if (!any) return null;
  var value = (total + group) * 1000;

  if (i + 1 < words.length &&
      words[i] == 'y' &&
      (words[i + 1] == 'medio' || words[i + 1] == 'media')) {
    value += 500;
    i += 2;
  } else if (i + 1 < words.length && words[i] == 'coma') {
    // «cinco coma cinco»: una cifra decimal dicha con palabra.
    final decimal = _units[words[i + 1]];
    if (decimal != null && decimal < 10) {
      value += decimal * 100;
      i += 2;
    }
  }
  return SpokenNumber(
    thousandths: value,
    start: start,
    end: i,
    heard: words.sublist(start, i).join(' '),
  );
}
