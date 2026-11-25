part of 'purchase_interpreter.dart';

enum _PerUnit { none, clean, eachOne, unclear }

final class _PriceClause {
  _PriceClause({
    required this.words,
    required this.heardFrom,
    required this.end,
    required this.connector,
    required this.number,
    required this.currencyIndex,
    required this.perUnit,
    required this.form,
    required this.total,
    required this.stray,
    this.unknownBeforeUnit,
    this.kindsContradict = false,
  });

  final List<String> words;
  final bool kindsContradict;
  final String? unknownBeforeUnit;
  final int heardFrom;
  final int end;
  final bool connector;
  final SpokenNumber number;
  final int? currencyIndex;
  final CatalogUnit? perUnit;
  final _PerUnit form;
  final bool total;
  final String? stray;

  String get heard => words.sublist(heardFrom, end).join(' ');

  String? get currencyHeard =>
      currencyIndex == null ? null : words[currencyIndex!];

  CurrencyCode? get currency =>
      currencyHeard == null ? null : currencyWord(currencyHeard!);

  bool get currencyVariant => currencyHeard != null && currency == null;

  bool get perUnitSaid => form == _PerUnit.clean || form == _PerUnit.eachOne;

  bool get cleanWithoutConnector =>
      currency != null && form == _PerUnit.clean && stray == null;
}

_PriceClause? _readClause(
  List<String> words,
  int at, {
  bool loose = false,
  String? stray,
  int? heardFrom,
  bool totalSaidBefore = false,
}) {
  var k = at;
  var connector = totalSaidBefore;
  var totalLead = totalSaidBefore;
  if (k < words.length && _priceConnectors.contains(words[k])) {
    connector = true;
    k++;
    final afterTotal = _totalLeadEnd(words, k);
    if (afterTotal != null) {
      totalLead = true;
      k = afterTotal;
    }
    if (k + 1 < words.length &&
        const {'un', 'una'}.contains(words[k]) &&
        words[k + 1] == 'precio') {
      k++;
    }
    if (k < words.length && words[k] == 'precio') k++;
    if (k < words.length && const {'de', 'del'}.contains(words[k])) k++;
  } else if (k < words.length && words[k] == 'precio') {
    connector = true;
    k++;
    if (k < words.length && words[k] == 'unitario') k++;
    if (k < words.length && const {'es', 'de', 'del'}.contains(words[k])) k++;
  }
  final number = readNumberAt(words, k);
  if (number == null || number.end <= k) return null;
  k = number.end;
  if (k < words.length && unitWord(words[k]) != null) return null;
  int? currencyIndex;
  k = _skipSeparatorComma(words, k);
  if (k < words.length && _currencyLike(words[k])) {
    currencyIndex = k;
    k++;
  } else if (!connector) {
    return null;
  }
  var form = _PerUnit.none;
  CatalogUnit? perUnit;
  var total = false;
  String? unknownBeforeUnit;
  if (k + 2 < words.length &&
      (words[k] == 'en' || _unknownPriceWord(words[k])) &&
      const {'el', 'la', 'por', 'cada', 'de', 'del'}.contains(words[k + 1]) &&
      unitWord(words[k + 2]) != null) {
    unknownBeforeUnit = words[k];
    perUnit = unitWord(words[k + 2])!.family;
    form = _PerUnit.unclear;
    k += 3;
  } else if (k + 2 < words.length &&
      words[k] == 'por' &&
      const {'cada', 'el', 'la'}.contains(words[k + 1]) &&
      unitWord(words[k + 2]) != null) {
    perUnit = unitWord(words[k + 2])!.family;
    form = _PerUnit.clean;
    k += 3;
  } else if (k + 1 < words.length &&
      const {'el', 'la', 'por', 'cada'}.contains(words[k]) &&
      unitWord(words[k + 1]) != null) {
    perUnit = unitWord(words[k + 1])!.family;
    form = _PerUnit.clean;
    k += 2;
  } else if (k + 1 < words.length &&
      words[k] == 'cada' &&
      const {'uno', 'una'}.contains(words[k + 1])) {
    form = _PerUnit.eachOne;
    k += 2;
  } else if (k + 1 < words.length &&
      const {'de', 'del'}.contains(words[k]) &&
      unitWord(words[k + 1]) != null) {
    perUnit = unitWord(words[k + 1])!.family;
    form = _PerUnit.unclear;
    if (connector || currencyIndex != null) unknownBeforeUnit = words[k];
    k += 2;
  } else if (currencyIndex != null &&
      k < words.length &&
      unitWord(words[k]) != null) {
    perUnit = unitWord(words[k])!.family;
    form = _PerUnit.unclear;
    k++;
  } else if (k < words.length && words[k] == 'total') {
    total = true;
    k++;
  } else if (k + 1 < words.length &&
      words[k] == 'en' &&
      words[k + 1] == 'total') {
    total = true;
    k += 2;
  }
  final kindsContradict = totalLead && form != _PerUnit.none;
  if (totalLead && !kindsContradict) total = true;
  if (loose && currencyIndex == null && form != _PerUnit.clean && !totalLead) {
    return null;
  }
  return _PriceClause(
    words: words,
    heardFrom: heardFrom ?? number.start,
    end: k,
    connector: connector,
    number: number,
    currencyIndex: currencyIndex,
    perUnit: perUnit,
    form: form,
    total: total,
    stray: stray,
    unknownBeforeUnit: unknownBeforeUnit,
    kindsContradict: kindsContradict,
  );
}

int? _totalLeadEnd(List<String> words, int k) {
  var t = k;
  if (t < words.length && const {'un', 'una', 'el'}.contains(words[t])) t++;
  if (t < words.length && const {'monto', 'importe'}.contains(words[t])) t++;
  if (t >= words.length || words[t] != 'total') return null;
  t++;
  if (t < words.length && const {'de', 'del'}.contains(words[t])) t++;
  return t;
}

int? _totalIntroEnd(List<String> words, int j) {
  if (j >= words.length || !const {'en', 'con', 'para'}.contains(words[j])) {
    return null;
  }
  final end = _totalLeadEnd(words, j + 1);
  if (end == null) return null;
  final n = readNumberAt(words, end);
  return n != null && n.end > end ? end : null;
}

bool _unknownPriceWord(String w) =>
    !const {
      'de',
      'del',
      'y',
      'en',
      'total',
      'el',
      'la',
      'por',
      'cada',
      'a',
      'al',
      'con',
      'para',
    }.contains(w) &&
    unitWord(w) == null &&
    !_currencyLike(w) &&
    readNumberAt([w], 0) == null;

(DraftField<SpokenPrice>, DraftField<CurrencyCode>?) _priceFields(
  _PriceClause c,
) {
  final heard = c.heard;
  DraftField<CurrencyCode>? currency() {
    final code = c.currency;
    if (code == null) return null;
    return c.connector
        ? DraftField.resolved(
            code,
            origin: FieldOrigin.voice,
            heard: c.currencyHeard,
          )
        : DraftField.toReview(
            code,
            message:
                'Se oyó «${c.currencyHeard}» sin «a» antes de la cifra: '
                'confirme la moneda.',
            heard: c.currencyHeard,
          );
  }

  if (!c.number.isValid) {
    return (
      DraftField.invalid(message: c.number.invalidMessage!, heard: heard),
      currency(),
    );
  }
  if (c.kindsContradict) {
    if (c.number.thousandths % 10 != 0 || c.number.thousandths <= 0) {
      return (
        DraftField.invalid(
          message: 'El importe debe ser mayor a cero y en centavos enteros.',
          heard: heard,
        ),
        currency(),
      );
    }
    return (
      DraftField.ambiguous(
        candidates: const [],
        heard: heard,
        value: SpokenPrice(c.number.thousandths ~/ 10),
        message:
            'Se dijo «total» y también la unidad del precio: no se sabe si '
            '${amountText(c.number.thousandths ~/ 10, c.currency)} es el '
            'total o el precio por unidad. Elija una opción o escriba el '
            'precio por unidad.',
      ),
      currency(),
    );
  }
  if (c.total) {
    if (c.number.thousandths % 10 != 0 || c.number.thousandths <= 0) {
      return (
        DraftField.invalid(
          message: 'El importe debe ser mayor a cero y en centavos enteros.',
          heard: heard,
        ),
        currency(),
      );
    }
    return (
      DraftField.ambiguous(
        candidates: const [],
        heard: heard,
        value: SpokenPrice(c.number.thousandths ~/ 10, total: true),
        message: totalSaidMessageFor(c.number.thousandths ~/ 10, c.currency),
      ),
      currency(),
    );
  }
  if (!c.connector && (c.stray != null || c.currencyVariant)) {
    return (
      DraftField.invalid(
        message:
            'Se oyó «$heard», pero el precio no se entendió bien. Dígalo de '
            'nuevo («a … bolivianos el litro») o escríbalo.',
        heard: heard,
      ),
      currency(),
    );
  }
  if (c.number.thousandths % 10 != 0 || c.number.thousandths <= 0) {
    return (
      DraftField.invalid(
        message: 'El precio debe ser mayor a cero y en centavos enteros.',
        heard: heard,
      ),
      currency(),
    );
  }
  final value = SpokenPrice(
    c.number.thousandths ~/ 10,
    perUnit: c.form == _PerUnit.clean ? c.perUnit : null,
  );
  if (c.unknownBeforeUnit != null) {
    return (
      DraftField.ambiguous(
        candidates: const [],
        heard: heard,
        value: value,
        message: perUnitQuestionMessage(
          word: c.unknownBeforeUnit!,
          minor: value.minorPerUnit,
          unit: c.perUnit == CatalogUnit.kilogram ? 'kg' : 'L',
          currency: c.currency,
        ),
      ),
      currency(),
    );
  }
  if (!c.connector) {
    if (c.cleanWithoutConnector) {
      return (
        DraftField.toReview(
          value,
          message:
              'Se entendió «$heard» sin «a» antes de la cifra: confirme el '
              'precio o corríjalo.',
          heard: heard,
        ),
        currency(),
      );
    }
    return (
      DraftField.ambiguous(
        candidates: const [],
        heard: heard,
        value: value,
        message:
            'Se oyó «$heard» sin «a» antes de la cifra. $unitNotSaidMessage',
      ),
      currency(),
    );
  }
  if (!c.perUnitSaid) {
    return (
      DraftField.ambiguous(
        candidates: const [],
        heard: heard,
        value: value,
        message: unitNotSaidMessage,
      ),
      currency(),
    );
  }
  if (c.currencyVariant) {
    return (
      DraftField.toReview(
        value,
        message:
            'Se oyó «$heard»: la moneda no se entendió bien. Confirme el '
            'precio y elija la moneda.',
        heard: heard,
      ),
      null,
    );
  }
  return (
    DraftField.resolved(value, origin: FieldOrigin.voice, heard: heard),
    currency(),
  );
}

(VoicePurchaseDraft, VoicePatchOutcome, UnplacedPrice?) _placePrice(
  VoicePurchaseDraft draft,
  _PriceClause c,
) {
  const none = VoicePatchOutcome();
  UnplacedPrice why(UnplacedPriceReason r) => _unplaced(c.heard, r);
  if (c.total) return (draft, none, why(UnplacedPriceReason.total));
  if (!c.number.isValid ||
      c.number.thousandths <= 0 ||
      c.number.thousandths % 10 != 0) {
    return (draft, none, why(UnplacedPriceReason.unclear));
  }
  if (!c.connector && (c.stray != null || c.currencyVariant)) {
    return (draft, none, why(UnplacedPriceReason.unclear));
  }
  if (c.form != _PerUnit.clean || c.perUnit == null) {
    return (draft, none, why(UnplacedPriceReason.unitNotSaid));
  }
  if (!c.connector && !c.cleanWithoutConnector) {
    return (draft, none, why(UnplacedPriceReason.unclear));
  }
  final open = [
    for (final l in draft.lines)
      if (!l.price.isResolved && !l.price.isManual) l,
  ];
  if (open.isEmpty) return (draft, none, why(UnplacedPriceReason.noLine));
  if (open.length > 1) {
    return (draft, none, why(UnplacedPriceReason.severalLines));
  }
  final target = open.single;
  final unit = target.product.value?.unit;
  if (!target.product.isResolved || unit == null) {
    return (draft, none, why(UnplacedPriceReason.noLine));
  }
  if (unit != c.perUnit) {
    return (draft, none, why(UnplacedPriceReason.unitMismatch));
  }
  final (price, currency) = _priceFields(c);
  final (p, op) = mergeField(target.price, price);
  final (cur, oc) = mergeField(target.currency, currency);
  return (
    draft.updateLine(target.key, (l) => l.copyWith(price: p, currency: cur)),
    op + oc,
    null,
  );
}

UnplacedPrice _unplaced(String heard, UnplacedPriceReason reason) {
  final said = 'Se oyó un precio («$heard»)';
  return UnplacedPrice(
    heard: heard,
    reason: reason,
    message: switch (reason) {
      UnplacedPriceReason.noLine =>
        '$said, pero no hay una línea con producto y sin precio a la que '
            'ponerlo: escríbalo en la línea.',
      UnplacedPriceReason.severalLines =>
        '$said, pero no se sabe a qué línea va: escríbalo en la línea o '
            'dígalo junto al producto.',
      UnplacedPriceReason.unitMismatch =>
        '$said, pero su unidad no corresponde a la línea sin precio: '
            'escríbalo en la línea.',
      UnplacedPriceReason.unitNotSaid =>
        '$said, pero no quedó claro si es por litro o por kilo: escríbalo en '
            'la línea o dígalo con «el litro» o «el kilo».',
      UnplacedPriceReason.total =>
        '$said, pero es un total; la compra se registra con precio por litro '
            'o kilo: escríbalo en la línea.',
      UnplacedPriceReason.unclear =>
        '$said, pero no se entendió bien: escríbalo en la línea o dígalo de '
            'nuevo junto al producto.',
      UnplacedPriceReason.notAlone =>
        '$said que no va junto a un producto: no se sabe a qué línea va. '
            'Escríbalo en la línea.',
    },
  );
}
