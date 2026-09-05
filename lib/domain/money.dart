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
