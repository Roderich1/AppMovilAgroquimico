// Tests de la especificación de entrada numérica es-BO (docs/44_NUMERIC_INPUT_SPEC.md).
//
// UIBUG-003: la aplicación IMPRIME con convenio es-BO (punto = miles, coma =
// decimales) pero LEÍA con convenio inglés (punto = decimales). Tecleando
// `15.000` sobre un campo que la propia app rotula "15.000 KG disponibles" se
// registraban 15 KG, y `1.500` en el diálogo de pago guardó 1,50 Bs.
//
// Estos tests fallan ANTES del fix. Ver artifacts/ui-audit/fixed/UIBUG-003/.

import 'package:agroquimicos/domain/money.dart';
// `common.dart` reexporta la API de `domain/numeric_input.dart`.
import 'package:agroquimicos/presentation/widgets/common.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('§4 · casos exigidos por el encargo — ACEPTADOS', () {
    // (entrada, valor esperado)
    const accepted = <(String, num)>[
      ('1500', 1500),
      ('1500,25', 1500.25),
      ('1.500', 1500), // <- el caso de UIBUG-003
      ('1.500,25', 1500.25),
      ('15 000', 15000),
      ('15 000,75', 15000.75),
      ('0,125', 0.125),
      ('99999,750', 99999.75),
      ('9.999.999,99', 9999999.99),
    ];

    for (final (input, expected) in accepted) {
      test('"$input" -> $expected', () {
        final result = parseNumericInput(input);
        expect(
          result.status,
          NumericInputStatus.valid,
          reason: '"$input" debe aceptarse (${result.message})',
        );
        expect(result.value, expected);
        // El envoltorio que usan las 26 llamadas de pantalla coincide.
        expect(tryParseDecimal(input), expected);
      });
    }
  });

  group('§4 · casos exigidos por el encargo — RECHAZADOS por formato', () {
    // El punto es separador de MILES: nunca decimal.
    const malformed = <String>[
      '1500.25', // .25 no es un grupo de 3
      '0.125', // como miles sería "0125": agrupamiento inválido
      '1,500.25', // orden inglés
    ];

    for (final input in malformed) {
      test('"$input" se rechaza como malformed', () {
        final result = parseNumericInput(input);
        expect(result.status, NumericInputStatus.malformed);
        expect(result.value, isNull);
        expect(result.message, isNotNull);
        expect(tryParseDecimal(input), isNull);
      });
    }
  });

  group('§5 · la única ambigüedad real: N,NNN', () {
    test('"1,500" se RECHAZA por ambiguo, no se adivina', () {
      final result = parseNumericInput('1,500');
      expect(result.status, NumericInputStatus.ambiguous);
      expect(result.value, isNull);
      // Jamás debe resolverse como 1.5 (÷1000) ni como 1500 (adivinando).
      expect(tryParseDecimal('1,500'), isNull);
    });

    test('el mensaje de ambigüedad ofrece las dos formas no ambiguas', () {
      final message = parseNumericInput('1,500').message!;
      expect(message, contains('1.500'));
      expect(message, contains('1,5'));
    });

    test('"12,500" y "999,000" también son ambiguos', () {
      expect(parseNumericInput('12,500').status, NumericInputStatus.ambiguous);
      expect(parseNumericInput('999,000').status, NumericInputStatus.ambiguous);
    });

    test('"0,125" NO es ambiguo: como miles sería "0125"', () {
      expect(parseNumericInput('0,125').status, NumericInputStatus.valid);
      expect(parseNumericInput('0,125').value, 0.125);
      expect(parseNumericInput('0,500').value, 0.5);
    });

    test('"1234,500" NO es ambiguo: parte entera de 4 dígitos', () {
      expect(parseNumericInput('1234,500').value, 1234.5);
    });

    test('"1,50" y "1,5000" NO son ambiguos: no son 3 decimales', () {
      expect(parseNumericInput('1,50').value, 1.5);
      expect(parseNumericInput('1,5000').value, 1.5);
    });
  });

  group('§4 · otros límites', () {
    test('vacío es empty, no error', () {
      for (final input in ['', '   ', '\t']) {
        expect(parseNumericInput(input).status, NumericInputStatus.empty);
        expect(parseNumericInput(input).message, isNull);
      }
    });

    test('basura es malformed', () {
      for (final input in ['abc', '12abc', '--5', '1e3', ',', '.', ',5']) {
        expect(
          parseNumericInput(input).status,
          NumericInputStatus.malformed,
          reason: '"$input"',
        );
      }
    });

    test('el signo negativo se rechaza (el dominio es positivo)', () {
      expect(parseNumericInput('-5').status, NumericInputStatus.malformed);
    });

    test('agrupamientos inválidos se rechazan', () {
      for (final input in ['1.5', '1.5000', '12.34.56', '1.500 000']) {
        expect(
          parseNumericInput(input).status,
          NumericInputStatus.malformed,
          reason: '"$input"',
        );
      }
    });

    test('decimales sin agrupamiento siempre válidos', () {
      expect(parseNumericInput('1,5').value, 1.5);
      expect(parseNumericInput('0,001').value, 0.001);
      expect(parseNumericInput('0').value, 0);
    });

    test('espacio duro y espacio fino cuentan como separador de miles', () {
      // NumberFormat de intl emite U+00A0 en algunos locales: el texto copiado
      // de la propia aplicación debe poder volver a leerse.
      expect(parseNumericInput('15 000').value, 15000);
      expect(parseNumericInput('15 000,75').value, 15000.75);
    });
  });

  group('§9 · invariante de ida y vuelta (la garantía anti-regresión)', () {
    // Si alguien cambia el formato de SALIDA sin cambiar el de ENTRADA, esto
    // se pone rojo. Es lo que impide que UIBUG-003 reaparezca.
    test('formatQuantity -> parse devuelve la cantidad original', () {
      const bases = <int>[
        125, // 0,125
        600000, // 600
        15000000, // 15.000
        1750250, // 1.750,25
        99999750, // 99.999,750
      ];
      for (final base in bases) {
        final printed = formatQuantity(base, 'KG').replaceAll(' KG', '');
        final parsed = parseNumericInput(printed);
        expect(
          parsed.status,
          NumericInputStatus.valid,
          reason: 'formatQuantity($base) = "$printed" debe poder releerse',
        );
        expect(
          tryParseBase(printed),
          base,
          reason: '"$printed" debe volver a ser $base',
        );
      }
    });

    test('formatBob -> parse devuelve el importe original', () {
      const minors = <int>[
        150000, // Bs 1.500,00  <- UIBUG-003
        80050, // Bs 800,50
        999999999, // Bs 9.999.999,99
        12, // Bs 0,12
      ];
      for (final minor in minors) {
        final printed = formatBob(minor).replaceAll('Bs', '').trim();
        expect(
          parseNumericInput(printed).status,
          NumericInputStatus.valid,
          reason: 'formatBob($minor) = "$printed" debe poder releerse',
        );
        expect(
          tryParseMinor(printed),
          minor,
          reason: '"$printed" debe volver a ser $minor',
        );
      }
    });
  });

  group('formatForInput · precarga de campos editables', () {
    // Esta regresión apareció al verificar UIBUG-002 en el Pixel 8: el diálogo
    // de pago a proveedor precargaba "20000.00" con `toStringAsFixed`, y con la
    // regla es-BO ese texto es inválido (el punto es de miles). El campo se
    // precargaba con un valor que la propia aplicación ya no sabía leer.
    test('usa coma decimal y nunca punto', () {
      expect(formatForInput(20000, maxDecimals: 2), '20000');
      expect(formatForInput(20000.5, maxDecimals: 2), '20000,5');
      expect(formatForInput(80), '80');
      expect(formatForInput(80.5), '80,5');
      expect(formatForInput(0.125), '0,125');
      for (final v in [0, 1, 1.5, 80, 20000, 99999.75, 1500.25]) {
        expect(
          formatForInput(v),
          isNot(contains('.')),
          reason: 'formatForInput($v) no debe contener punto',
        );
      }
    });

    test('lo que precarga se puede volver a leer (invariante)', () {
      const values = <num>[
        0,
        1,
        1.5,
        80,
        120.5,
        1500,
        1500.25,
        20000,
        99999.75,
        0.125,
      ];
      for (final v in values) {
        final text = formatForInput(v);
        final parsed = parseNumericInput(text);
        expect(
          parsed.status,
          NumericInputStatus.valid,
          reason:
              'formatForInput($v) = "$text" debe poder releerse '
              '(${parsed.message})',
        );
        expect(parsed.value, v, reason: '"$text" debe volver a ser $v');
      }
    });

    test('nunca produce el patrón ambiguo N,NNN', () {
      // 1.5 con 3 decimales seria "1,500", que es justo la cadena ambigua.
      expect(formatForInput(1.5), '1,5');
      expect(formatForInput(12.5), '12,5');
      for (final v in [1.5, 12.5, 999.0, 1.005]) {
        expect(
          parseNumericInput(formatForInput(v)).status,
          NumericInputStatus.valid,
          reason: 'formatForInput($v) no debe ser ambiguo',
        );
      }
    });
  });

  group('UIBUG-003 · los dos casos observados en el Pixel 8', () {
    test(
      'transferencia: "15.000" sobre "15.000 KG disponibles" = 15000 KG',
      () {
        // Antes del fix: tryParseBase('15.000') == 15000 pero por la vía
        // equivocada (15.0 * 1000), y '15.000,5' era imposible de expresar.
        expect(tryParseBase('15.000'), 15000000); // 15.000 KG en gramos
        expect(formatQuantity(tryParseBase('15.000')!, 'KG'), '15.000 KG');
      },
    );

    test('pago: "1.500" son 1.500,00 Bs, no 1,50 Bs', () {
      // Evidencia original: se guardó amount_bob_minor_signed = -150.
      expect(tryParseMinor('1.500'), 150000);
      expect(formatBob(tryParseMinor('1.500')!), contains('1.500,00'));
      // La lectura vieja (1,50 Bs) queda explícitamente descartada.
      expect(tryParseMinor('1.500'), isNot(150));
    });

    test('"1.500,25" y "0,125" se interpretan exactamente', () {
      expect(tryParseMinor('1.500,25'), 150025);
      expect(tryParseBase('0,125'), 125);
    });
  });

  group('§8 · una entrada rechazada nunca vale 1000x, vale 0', () {
    test(
      'parseMinor/parseBase degradan a 0, jamás a un valor mil veces mal',
      () {
        expect(parseMinor('1,500'), 0); // ambigua -> 0, no 150 ni 150000
        expect(parseBase('1,500'), 0);
        expect(parseMinor('abc'), 0);
        expect(parseBase(''), 0);
      },
    );

    test('pero una entrada válida sí produce el valor correcto', () {
      expect(parseMinor('1.500'), 150000);
      expect(parseBase('15.000'), 15000000);
    });
  });
}
