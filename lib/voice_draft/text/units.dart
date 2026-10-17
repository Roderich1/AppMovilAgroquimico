/// Unidades y monedas dictadas (EVO-010 «Números, unidades y dinero»).
///
/// El dominio guarda cantidades en unidad base entera: ML para productos en
/// litros y G para productos en kilos (`products.base_unit`). Aquí sólo se
/// traduce lo dicho a esa base; la compatibilidad con el producto la decide
/// el borrador, que marca inválida una línea de «litros» de un producto en kg.
library;

import '../../domain/models.dart';

/// Unidad del producto en el catálogo (`products.unit`).
enum CatalogUnit {
  liter('L', 'ML'),
  kilogram('KG', 'G');

  const CatalogUnit(this.code, this.baseCode);
  final String code;
  final String baseCode;

  static CatalogUnit? fromCode(String? code) => switch (code?.toUpperCase()) {
    'L' => CatalogUnit.liter,
    'KG' => CatalogUnit.kilogram,
    _ => null,
  };
}

/// Unidad dicha en una cantidad.
enum SpokenUnit {
  liter(CatalogUnit.liter, 1),
  milliliter(CatalogUnit.liter, 1000),
  kilogram(CatalogUnit.kilogram, 1),
  gram(CatalogUnit.kilogram, 1000);

  const SpokenUnit(this.family, this.divisor);

  /// Unidad del catálogo con la que es compatible.
  final CatalogUnit family;

  /// Milésimas dichas → unidad base: 1 L = 1000 ML (divisor 1) y
  /// 1 ML = 1 ML (divisor 1000).
  final int divisor;

  /// Cantidad en unidad base, o `null` si no es un entero de ML o G.
  int? toBase(int thousandths) =>
      thousandths % divisor == 0 ? thousandths ~/ divisor : null;
}

const _unitWords = <String, SpokenUnit>{
  'l': SpokenUnit.liter,
  'lt': SpokenUnit.liter,
  'lts': SpokenUnit.liter,
  'litro': SpokenUnit.liter,
  'litros': SpokenUnit.liter,
  'ml': SpokenUnit.milliliter,
  'mililitro': SpokenUnit.milliliter,
  'mililitros': SpokenUnit.milliliter,
  'cc': SpokenUnit.milliliter,
  'kg': SpokenUnit.kilogram,
  'kgs': SpokenUnit.kilogram,
  'kilo': SpokenUnit.kilogram,
  'kilos': SpokenUnit.kilogram,
  'kilogramo': SpokenUnit.kilogram,
  'kilogramos': SpokenUnit.kilogram,
  'g': SpokenUnit.gram,
  'gr': SpokenUnit.gram,
  'gramo': SpokenUnit.gram,
  'gramos': SpokenUnit.gram,
};

SpokenUnit? unitWord(String word) => _unitWords[word];

/// «el litro», «por litro», «el kilo»… marcan precio **por unidad**.
bool isPerUnitWord(String word) =>
    _unitWords.containsKey(word) || word == 'unidad' || word == 'cada';

const _currencyWords = <String, CurrencyCode>{
  'boliviano': CurrencyCode.bob,
  'bolivianos': CurrencyCode.bob,
  'bs': CurrencyCode.bob,
  'bob': CurrencyCode.bob,
  'dolar': CurrencyCode.usd,
  'dolares': CurrencyCode.usd,
  'usd': CurrencyCode.usd,
};

CurrencyCode? currencyWord(String word) => _currencyWords[word];
