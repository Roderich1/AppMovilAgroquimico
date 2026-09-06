/// Modelo tabular neutral de un reporte (EVO-005-REQ-001).
///
/// Es el único punto por el que pasan CSV y PDF. Ninguno de los dos vuelve a
/// consultar SQLite ni recibe modelos de lectura: reciben esta tabla, con los
/// **mismos enteros**, y sólo deciden cómo pintarla. Así no puede ocurrir que
/// el PDF diga una cifra y el CSV otra.
///
/// No conoce widgets, SQLite ni filesystem.
///
/// ## Por qué no hay `double` en ninguna parte
///
/// El dinero vive en centavos y las cantidades en milésimas de unidad. Pasar
/// por `double` para escribir "1.234,56" reintroduce el error de coma flotante
/// justo en el paso donde el número deja la aplicación y se convierte en la
/// cifra que alguien va a cobrar. [decimalFromScaled] hace la conversión con
/// división y módulo enteros: es exacta por construcción.
library;

import '../money.dart';

/// Separador decimal es-BO.
const String decimalSeparator = ',';

/// Separador de miles es-BO. Sólo se usa al PRESENTAR, nunca en el CSV: una
/// hoja de cálculo interpreta "1.234,56" según su locale y puede leer 1,23456.
const String groupSeparator = '.';

/// Convierte un entero escalado a su decimal exacto.
///
/// [value] es el número multiplicado por `10^[decimals]`: 123456 con 2
/// decimales es 1234,56. No hay redondeo porque no hay nada que redondear;
/// la operación es un cambio de representación.
String decimalFromScaled(
  int value,
  int decimals, {
  bool grouped = false,
  bool trimTrailingZeros = false,
}) {
  final negative = value < 0;
  final absolute = negative ? -value : value;
  var scale = 1;
  for (var i = 0; i < decimals; i++) {
    scale *= 10;
  }
  final whole = absolute ~/ scale;
  var fraction = decimals == 0
      ? ''
      : (absolute % scale).toString().padLeft(decimals, '0');
  if (trimTrailingZeros) {
    while (fraction.isNotEmpty && fraction.endsWith('0')) {
      fraction = fraction.substring(0, fraction.length - 1);
    }
  }
  final wholeText = grouped ? _group(whole.toString()) : whole.toString();
  final buffer = StringBuffer();
  if (negative && (whole != 0 || fraction.isNotEmpty)) buffer.write('-');
  buffer.write(wholeText);
  if (fraction.isNotEmpty) {
    buffer
      ..write(decimalSeparator)
      ..write(fraction);
  }
  return buffer.toString();
}

String _group(String digits) {
  if (digits.length <= 3) return digits;
  final buffer = StringBuffer();
  final firstGroup = digits.length % 3 == 0 ? 3 : digits.length % 3;
  buffer.write(digits.substring(0, firstGroup));
  for (var i = firstGroup; i < digits.length; i += 3) {
    buffer
      ..write(groupSeparator)
      ..write(digits.substring(i, i + 3));
  }
  return buffer.toString();
}

/// Una celda del reporte.
///
/// Guarda el valor **entero** y su significado, no una cadena ya formateada:
/// así CSV y PDF derivan su texto del mismo número y la equivalencia entre
/// ambos es demostrable.
sealed class ReportCell {
  const ReportCell();

  /// `true` si el contenido es un número generado por la aplicación.
  ///
  /// Lo usa el CSV para decidir la neutralización de fórmulas: un importe
  /// negativo empieza por `-`, pero es un número, no una fórmula.
  bool get isNumeric;

  /// Texto para el CSV: sin separador de miles, sin símbolo y sin unidad, para
  /// que una hoja de cálculo lo lea como número.
  String get csvText;

  /// Texto para el PDF: el mismo número con separador de miles.
  String get displayText;
}

/// Texto libre: nombres, conceptos, unidades, etiquetas.
final class ReportText extends ReportCell {
  const ReportText(this.value);
  final String value;

  @override
  bool get isNumeric => false;
  @override
  String get csvText => value;
  @override
  String get displayText => value;
}

/// Importe en centavos de boliviano.
final class ReportMoney extends ReportCell {
  const ReportMoney(this.minor);
  final int minor;

  @override
  bool get isNumeric => true;
  @override
  String get csvText => decimalFromScaled(minor, 2);
  @override
  String get displayText => decimalFromScaled(minor, 2, grouped: true);
}

/// Cantidad en unidad base (milésimas de litro o de kilo).
///
/// La unidad va en su propia columna (`EVO-005-REQ-004`).
final class ReportQuantity extends ReportCell {
  const ReportQuantity(this.base);
  final int base;

  @override
  bool get isNumeric => true;
  @override
  String get csvText => decimalFromScaled(base, 3, trimTrailingZeros: true);
  @override
  String get displayText =>
      decimalFromScaled(base, 3, grouped: true, trimTrailingZeros: true);
}

/// Superficie guardada en metros cuadrados y expresada en hectáreas.
final class ReportArea extends ReportCell {
  const ReportArea(this.areaM2);
  final int areaM2;

  @override
  bool get isNumeric => true;
  @override
  String get csvText => decimalFromScaled(areaM2, 4, trimTrailingZeros: true);
  @override
  String get displayText =>
      decimalFromScaled(areaM2, 4, grouped: true, trimTrailingZeros: true);
}

/// Conteo sin decimales.
final class ReportCount extends ReportCell {
  const ReportCount(this.value);
  final int value;

  @override
  bool get isNumeric => true;
  @override
  String get csvText => decimalFromScaled(value, 0);
  @override
  String get displayText => decimalFromScaled(value, 0, grouped: true);
}

/// Fecha ISO de la base, presentada como `dd/mm/aaaa`.
final class ReportDate extends ReportCell {
  const ReportDate(this.iso);
  final String iso;

  @override
  bool get isNumeric => false;
  @override
  String get csvText => formatDate(iso);
  @override
  String get displayText => formatDate(iso);
}

/// Celda sin valor. No es cero: es "aquí no aplica".
final class ReportBlank extends ReportCell {
  const ReportBlank();

  @override
  bool get isNumeric => false;
  @override
  String get csvText => '';
  @override
  String get displayText => '';
}

/// Columna del reporte.
class ReportColumn {
  const ReportColumn(this.header, {this.numeric = false, this.weight = 1});

  final String header;

  /// Alinea a la derecha en el PDF.
  final bool numeric;

  /// Ancho relativo dentro de la tabla del PDF.
  final double weight;
}

/// Filtro aplicado, tal como debe leerse en la cabecera del reporte.
class ReportFilter {
  const ReportFilter(this.label, this.value);
  final String label;
  final String value;
}

/// Total al pie del reporte.
class ReportTotal {
  const ReportTotal(this.label, this.cell);
  final String label;
  final ReportCell cell;
}

/// La composición de un reporte es incoherente.
///
/// No es un error del usuario: es un fallo de programación que se detiene antes
/// de generar ningún byte.
class ReportCompositionException implements Exception {
  const ReportCompositionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Un reporte listo para exportar, independiente del formato.
class ReportTable {
  ReportTable({
    required this.title,
    required this.generatedAt,
    required this.columns,
    required this.rows,
    this.filters = const [],
    this.totals = const [],
    this.emptyMessage = 'No hay datos para los filtros elegidos.',
  }) {
    if (columns.isEmpty) {
      throw const ReportCompositionException(
        'Un reporte necesita al menos una columna.',
      );
    }
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].length != columns.length) {
        throw ReportCompositionException(
          'La fila ${i + 1} tiene ${rows[i].length} celdas y el reporte '
          'declara ${columns.length} columnas.',
        );
      }
    }
  }

  final String title;
  final DateTime generatedAt;
  final List<ReportColumn> columns;
  final List<List<ReportCell>> rows;
  final List<ReportFilter> filters;
  final List<ReportTotal> totals;

  /// Qué decir cuando no hay filas. El reporte se genera igual, con cabeceras
  /// y filtros, para que quede constancia de qué se consultó.
  final String emptyMessage;

  bool get isEmpty => rows.isEmpty;
}
