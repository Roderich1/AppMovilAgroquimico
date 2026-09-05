import 'package:intl/intl.dart';

const int fxScale = 1000000;
const int baseUnitsPerMajor = 1000;

int divideRoundedHalfUp(int numerator, int denominator) {
  if (denominator <= 0 || numerator < 0) {
    throw ArgumentError(
      'Solo se admiten importes positivos y divisor mayor a cero.',
    );
  }
  return (numerator + denominator ~/ 2) ~/ denominator;
}

int convertedUnitPriceBobMinor(int originalUnitPriceMinor, int? fxScaled) {
  if (fxScaled == null) return originalUnitPriceMinor;
  return divideRoundedHalfUp(originalUnitPriceMinor * fxScaled, fxScale);
}

int subtotalMinor({
  required int quantityBase,
  required int unitPriceMinor,
  required int? fxScaled,
}) {
  final numerator = quantityBase * unitPriceMinor * (fxScaled ?? fxScale);
  return divideRoundedHalfUp(numerator, baseUnitsPerMajor * fxScale);
}

int costForBaseQuantity(int quantityBase, int unitCostBobMinorPerMajor) =>
    divideRoundedHalfUp(
      quantityBase * unitCostBobMinorPerMajor,
      baseUnitsPerMajor,
    );

String formatBob(int minor) => NumberFormat.currency(
  locale: 'es_BO',
  symbol: 'Bs ',
  decimalDigits: 2,
).format(minor / 100);

String formatQuantity(int base, String unit) {
  final value = base / baseUnitsPerMajor;
  return '${NumberFormat('#,##0.###', 'es_BO').format(value)} $unit';
}

/// Superficie en hectáreas con convenio es-BO.
///
/// Las pantallas interpolaban `area_m2 / 10000` en crudo, produciendo `80.0 ha`
/// (punto decimal) junto a `20.160,00 Bs` (coma decimal) en la misma línea
/// (UIBUG-024). Los enteros se muestran sin decimales: `80 ha`, no `80,0 ha`.
String formatHectares(int areaM2) {
  final hectares = areaM2 / 10000;
  return '${NumberFormat('#,##0.##', 'es_BO').format(hectares)} ha';
}

/// Fecha en formato local `dd/mm/aaaa`.
///
/// La base guarda ISO (`2026-01-25`) y varias vistas lo mostraban tal cual
/// (UIBUG-027). Si el texto no es una fecha reconocible se devuelve intacto en
/// vez de romper la pantalla.
String formatDate(Object? isoDate) {
  final text = '$isoDate';
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return text;
  // Patrón puramente numérico y **sin locale**: `DateFormat` con locale exige
  // `initializeDateFormatting`, que la aplicación no llama, y lanzaría
  // `LocaleDataException` en la bitácora, en la pestaña Cuenta y en el estado de
  // cuenta. `dd/MM/yyyy` da el mismo resultado en cualquier locale.
  return DateFormat('dd/MM/yyyy').format(parsed);
}

/// Detalle FIFO legible a partir de la cadena `#lote: cantidadBase` que arma
/// `agro_repository`.
///
/// La bitácora interpolaba ese valor en crudo y mostraba **"FIFO: #1: 600000"**:
/// gramos, sin unidad y sin formato, justo debajo de un correcto "real 600 KG"
/// (UIBUG-026). Si el texto no tiene la forma esperada se devuelve intacto.
String formatFifoLots(Object? raw, String unit) {
  final text = '$raw';
  if (raw == null || text.isEmpty) return 'sin detalle';
  final parts = text.split(',');
  final formatted = <String>[];
  for (final part in parts) {
    final pieces = part.split(':');
    if (pieces.length != 2) return text;
    final base = int.tryParse(pieces[1].trim());
    if (base == null) return text;
    formatted.add('${pieces[0].trim()} ${formatQuantity(base, unit)}');
  }
  return formatted.join(' · ');
}

/// Resumen de productos legible a partir de la cadena `nombre|base|unidad`
/// separada por `;` que arma `agro_repository`.
///
/// Antes esos resúmenes se componían en SQL con `quantity_base / 1000.0` y
/// producían `Urea 25.0 KG` o `Fosfato Diamónico 5000.0 KG`: punto decimal,
/// decimal superfluo y sin separador de miles, mientras el resto de la
/// aplicación usa `1.750,25 KG` (UIBUG-025). Ahora la consulta devuelve datos y
/// el formato lo pone la presentación.
String formatItemsSummary(Object? raw) {
  final text = '$raw';
  if (raw == null || text.isEmpty) return '';
  final parts = <String>[];
  for (final entry in text.split(';')) {
    final pieces = entry.split('|');
    if (pieces.length != 3) return text;
    final base = int.tryParse(pieces[1]);
    if (base == null) return text;
    parts.add('${pieces[0]} ${formatQuantity(base, pieces[2])}');
  }
  return parts.join(' · ');
}
