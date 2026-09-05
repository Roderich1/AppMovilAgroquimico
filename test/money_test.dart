import 'package:agroquimicos/domain/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('conversión monetaria exacta', () {
    test('FX 7: 420 L x USD 16 = Bs 47.040', () {
      expect(
        subtotalMinor(
          quantityBase: 420000,
          unitPriceMinor: 1600,
          fxScaled: 7000000,
        ),
        4704000,
      );
      expect(convertedUnitPriceBobMinor(1600, 7000000), 11200);
    });

    test('FX 12.10: 420 L x USD 16 = Bs 81.312', () {
      expect(
        subtotalMinor(
          quantityBase: 420000,
          unitPriceMinor: 1600,
          fxScaled: 12100000,
        ),
        8131200,
      );
    });

    test('BOB no usa FX', () {
      expect(
        subtotalMinor(
          quantityBase: 100000,
          unitPriceMinor: 5000,
          fxScaled: null,
        ),
        500000,
      );
    });
  });
}
