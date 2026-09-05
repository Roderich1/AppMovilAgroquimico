/// Interpretación de los números que teclea el usuario, con convenio **es-BO**:
/// la coma separa decimales y el punto separa miles, igual que en la salida de
/// [formatBob] y [formatQuantity].
///
/// Regla única y centralizada. Ninguna pantalla debe analizar números por su
/// cuenta: la especificación completa, con la tabla de decisión, está en
/// `docs/44_NUMERIC_INPUT_SPEC.md`.
///
/// Corrige UIBUG-003: la entrada usaba el punto como separador decimal mientras
/// la salida lo usa como separador de miles, de modo que teclear `15.000` sobre
/// un campo rotulado "15.000 KG disponibles" registraba 15 KG, y `1.500` en el
/// diálogo de pago guardaba 1,50 Bs en lugar de 1.500,00 Bs.
library;

/// Resultado de interpretar una cadena tecleada.
enum NumericInputStatus {
  /// Campo vacío. No es un error de formato: lo valida la regla de negocio.
  empty,

  /// Interpretada sin ambigüedad.
  valid,

  /// Podría leerse de dos formas separadas por un factor 1000. Se rechaza en
  /// lugar de adivinar (ver `44` §5).
  ambiguous,

  /// No respeta el convenio es-BO.
  malformed,
}

/// Entero opcionalmente agrupado en miles con `.` o con espacio, y decimales
/// opcionales tras una coma. Sin signo: el dominio sólo maneja positivos.
///
/// El primer grupo es `[1-9]\d{0,2}`, no `\d{1,3}`: un número agrupado en miles
/// nunca empieza por cero. Eso es lo que hace que `0.125` sea inválido (como
/// agrupamiento sería `0125`) en vez de interpretarse como 125.
final RegExp _plain = RegExp(r'^\d+(,\d+)?$');
final RegExp _groupedDot = RegExp(r'^[1-9]\d{0,2}(\.\d{3})+(,\d+)?$');
final RegExp _groupedSpace = RegExp(r'^[1-9]\d{0,2}( \d{3})+(,\d+)?$');

/// `N,NNN` con parte entera de 1 a 3 dígitos y sin cero a la izquierda: el
/// único patrón que colisiona entre la coma decimal es-BO (`1,5`) y la coma de
/// miles inglesa (`1500`).
final RegExp _ambiguous = RegExp(r'^([1-9]\d{0,2}),\d{3}$');

const String _malformedMessage =
    'Escriba el número como 1.500,25: use la coma para los decimales y el '
    'punto para los miles.';

String _ambiguousMessage(String raw) {
  final parts = raw.split(',');
  // Las dos lecturas posibles, escritas de forma que ya no son ambiguas.
  final asThousands = '${parts[0]}.${parts[1]}';
  final trimmed = parts[1].replaceAll(RegExp(r'0+$'), '');
  final asDecimal = '${parts[0]},${trimmed.isEmpty ? '5' : trimmed}';
  return '"$raw" es ambiguo: escriba $asThousands si son miles, '
      'o $asDecimal si es decimal.';
}

/// Escribe [value] tal como debe aparecer **dentro de un campo editable**:
/// coma decimal, **sin separador de miles** y sin ceros finales sobrantes.
///
/// Es la operación inversa de [parseNumericInput] y existe porque precargar un
/// campo con `toStringAsFixed` produce texto en convenio inglés (`20000.00`,
/// `80.0`) que esta misma aplicación ya no acepta.
///
/// No se agrupan los miles a propósito: un campo en edición es más fácil de
/// corregir sin puntos, y así el texto precargado nunca puede caer en el patrón
/// ambiguo `N,NNN` descrito en `44` §5.
///
/// Invariante garantizada por test:
/// `parseNumericInput(formatForInput(v)).value == v`.
String formatForInput(num value, {int maxDecimals = 3}) {
  var text = value.toStringAsFixed(maxDecimals);
  if (text.contains('.')) {
    text = text.replaceAll(RegExp(r'0+$'), '');
    text = text.replaceAll(RegExp(r'\.$'), '');
  }
  text = text.replaceAll('.', ',');

  // Un valor como 12,345 (1-3 enteros y exactamente 3 decimales) cae en el
  // patrón ambiguo de `44` §5 y la propia aplicación lo rechazaría al releerlo.
  // Se añade un cero final: el valor es idéntico y la cadena deja de ser
  // ambigua al tener 4 decimales.
  if (_ambiguous.hasMatch(text)) text = '${text}0';
  return text;
}

/// Interpretación de [raw] según `docs/44_NUMERIC_INPUT_SPEC.md`.
class NumericInputResult {
  const NumericInputResult._(this.status, this.value, this.message);

  /// Qué se pudo determinar.
  final NumericInputStatus status;

  /// Valor interpretado. No nulo **si y sólo si** [status] es
  /// [NumericInputStatus.valid].
  final num? value;

  /// Mensaje para el usuario. No nulo si [status] es
  /// [NumericInputStatus.ambiguous] o [NumericInputStatus.malformed].
  final String? message;

  /// `true` sólo cuando hay un valor utilizable.
  bool get isValid => status == NumericInputStatus.valid;
}

/// Analiza [raw] con convenio es-BO.
///
/// Nunca devuelve un valor mil veces distinto del que el usuario escribió: ante
/// una cadena ambigua devuelve [NumericInputStatus.ambiguous] con un mensaje que
/// ofrece las dos formas no ambiguas.
NumericInputResult parseNumericInput(String raw) {
  // NumberFormat emite espacio duro (U+00A0) y fino duro (U+202F) en algunos
  // locales: el texto copiado de la propia aplicación debe poder releerse.
  final text = raw.replaceAll(' ', ' ').replaceAll(' ', ' ').trim();

  if (text.isEmpty) {
    return const NumericInputResult._(NumericInputStatus.empty, null, null);
  }

  if (_ambiguous.hasMatch(text)) {
    return NumericInputResult._(
      NumericInputStatus.ambiguous,
      null,
      _ambiguousMessage(text),
    );
  }

  final String digits;
  if (_plain.hasMatch(text)) {
    digits = text;
  } else if (_groupedDot.hasMatch(text)) {
    digits = text.replaceAll('.', '');
  } else if (_groupedSpace.hasMatch(text)) {
    digits = text.replaceAll(' ', '');
  } else {
    return const NumericInputResult._(
      NumericInputStatus.malformed,
      null,
      _malformedMessage,
    );
  }

  final parsed = num.tryParse(digits.replaceAll(',', '.'));
  if (parsed == null) {
    return const NumericInputResult._(
      NumericInputStatus.malformed,
      null,
      _malformedMessage,
    );
  }
  return NumericInputResult._(NumericInputStatus.valid, parsed, null);
}
