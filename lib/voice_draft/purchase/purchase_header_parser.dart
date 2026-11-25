part of 'purchase_interpreter.dart';

String _matchCode(FieldStatus s) => switch (s) {
  FieldStatus.resolved => 'unico',
  FieldStatus.ambiguous => 'varios',
  FieldStatus.missing => 'ninguno',
  FieldStatus.invalid => 'no-valido',
};

({VoicePurchaseLine? target, String? notice}) _placeLine(
  VoicePurchaseDraft draft,
  _HeardLine line,
  DraftField<CatalogEntry> product,
  Set<int> added,
) {
  final earlier = [
    for (final l in draft.lines)
      if (!added.contains(l.key)) l,
  ];
  if (line.explicitNew) return (target: null, notice: null);
  if (product.isResolved) {
    final same = [
      for (final l in earlier)
        if (l.product.value?.id == product.value!.id) l,
    ];
    if (same.length > 1) {
      return (
        target: null,
        notice:
            'Hay varias líneas de ${product.value!.name}: corrija a mano la '
            'que corresponda.',
      );
    }
    return (target: same.firstOrNull, notice: null);
  }
  if (line.productHeard.isEmpty) {
    final waiting = [
      for (final l in earlier)
        if (isAwaitingProduct(l.product)) l,
    ];
    if (waiting.length > 1) {
      return (
        target: null,
        notice:
            'Se oyó una cantidad, pero hay varias líneas sin producto: elija '
            'el producto en la que corresponda o quite las que sobren.',
      );
    }
    if (waiting.length == 1) return (target: waiting.single, notice: null);
    if (line.open) return (target: null, notice: null);
    final noQuantity = [
      for (final l in earlier)
        if (l.product.isResolved && l.quantity.status == FieldStatus.missing) l,
    ];
    if (noQuantity.length > 1) {
      return (
        target: null,
        notice:
            'Se oyó una cantidad sin producto y hay varias líneas sin '
            'cantidad: dígala con el producto o escríbala en su línea.',
      );
    }
    return (target: noQuantity.firstOrNull, notice: null);
  }
  final heard = canonicalName(line.productHeard);
  final same = [
    for (final l in earlier)
      if (!l.product.isResolved &&
          l.product.heard != null &&
          canonicalName(l.product.heard!) == heard)
        l,
  ];
  return (target: same.length == 1 ? same.single : null, notice: null);
}

({
  VoicePurchaseDraft draft,
  VoicePatchOutcome outcome,
  String? notice,
  String code,
})?
_productMention(
  VoicePurchaseDraft draft,
  List<String> words,
  VoiceCatalog catalog,
) {
  var start = _afterPurchaseVerb(words) ?? 0;
  while (start < words.length && _purchaseLead.contains(words[start])) {
    start++;
  }
  final lead = start > 0;
  var j = start;
  while (j < words.length &&
      !_priceConnectors.contains(words[j]) &&
      words[j] != 'precio' &&
      !_numberThenCurrency(words, j) &&
      _totalIntroEnd(words, j) == null) {
    j++;
  }
  var nameEnd = j;
  while (nameEnd > start &&
      (words[nameEnd - 1] == ',' || _glue.contains(words[nameEnd - 1]))) {
    nameEnd--;
  }
  if (nameEnd <= start) return null;
  final name = words.sublist(start, nameEnd).join(' ');
  final totalIntro = _totalIntroEnd(words, j);
  final clause = j >= words.length
      ? null
      : totalIntro != null
      ? _readClause(words, totalIntro, totalSaidBefore: true)
      : _readClause(words, j);
  final product = entryField(
    _resolveProduct(name, catalog.products),
    'producto',
  );
  final said = clause == null ? '«$name»' : '«$name» con «${clause.heard}»';
  const none = VoicePatchOutcome();

  if (product.status == FieldStatus.missing) {
    if (!lead) return null;
    return (
      draft: draft,
      outcome: none,
      notice:
          'Se oyó «$name», que no está en el catálogo: dígalo de nuevo o '
          'elíjalo en la línea.',
      code: 'ninguno-aviso',
    );
  }

  if (!lead && clause == null) {
    final already =
        product.isResolved &&
        draft.lines.any((l) => l.product.value?.id == product.value!.id);
    if (already) {
      return (
        draft: draft,
        outcome: none,
        notice: null,
        code: 'sin-verbo-ya-presente',
      );
    }
    return (
      draft: draft,
      outcome: none,
      notice:
          'Se oyó «$name» sin cantidad ni «compré»: no se añadió. Dígalo '
          'con la cantidad («compré dos litros de …») o elíjalo en una línea.',
      code: 'sin-verbo-aviso',
    );
  }

  VoicePurchaseLine? target;
  final waiting = [
    for (final l in draft.lines)
      if (isAwaitingProduct(l.product)) l,
  ];
  if (waiting.length == 1) {
    target = waiting.single;
  } else if (product.isResolved) {
    final same = [
      for (final l in draft.lines)
        if (l.product.value?.id == product.value!.id) l,
    ];
    if (same.length > 1) {
      return (
        draft: draft,
        outcome: none,
        notice:
            'Se oyó $said, pero hay varias líneas de ${product.value!.name}: '
            'corrija la que corresponda en el borrador.',
        code: 'unico-varias-lineas-aviso',
      );
    }
    if (same.length == 1) target = same.single;
  }

  if (target == null) {
    final unresolved = [
      for (var i = 0; i < draft.lines.length; i++)
        if (!draft.lines[i].product.isResolved)
          draft.lines[i].product.heard == null
              ? 'la línea ${i + 1}'
              : 'la línea ${i + 1} («${draft.lines[i].product.heard}»)',
    ];
    if (unresolved.isNotEmpty) {
      final which = unresolved.length == 1
          ? unresolved.single
          : 'una de estas: ${unresolved.join(', ')}';
      return (
        draft: draft,
        outcome: none,
        notice:
            'Se oyó $said sin cantidad. No se sabe si es el producto de '
            '$which o otra compra: elíjalo en el selector de producto de esa '
            'línea, o dígalo con la cantidad para añadir una línea nueva.',
        code: '${_matchCode(product.status)}-linea-sin-resolver-aviso',
      );
    }
  }

  DraftField<SpokenPrice>? price;
  DraftField<CurrencyCode>? currency;
  String? notice;
  if (clause != null) {
    final unit = (target?.product.value ?? product.value)?.unit;
    if (clause.perUnit != null && unit != null && clause.perUnit != unit) {
      notice = _unplaced(
        clause.heard,
        UnplacedPriceReason.unitMismatch,
      ).message;
    } else {
      (price, currency) = _priceFields(clause);
    }
  }

  if (target != null) {
    final t = target;
    final (pr, opr) = t.product.isResolved
        ? (t.product, none)
        : mergeField(t.product, product);
    final (p, op) = price == null
        ? (t.price, none)
        : mergeField(t.price, price);
    final (c, oc) = currency == null
        ? (t.currency, none)
        : mergeField(t.currency, currency);
    return (
      draft: draft.updateLine(
        t.key,
        (l) => l.copyWith(product: pr, price: p, currency: c),
      ),
      outcome: opr + op + oc,
      notice: notice,
      code: '${_matchCode(product.status)}-existente',
    );
  }

  final line = VoicePurchaseLine(
    key: draft.nextLineKey,
    product: product,
    price:
        price ?? const DraftField.missing(message: 'Diga o escriba el precio.'),
    currency:
        currency ??
        const DraftField.missing(message: 'Diga o elija la moneda.'),
  );
  return (
    draft: draft.copyWith(
      lines: [...draft.lines, line],
      nextLineKey: draft.nextLineKey + 1,
    ),
    outcome: const VoicePatchOutcome(applied: 1),
    notice: notice,
    code: '${_matchCode(product.status)}-nueva',
  );
}

String? _nameAfter(List<String> words, Set<String> keys) {
  for (var i = 0; i < words.length; i++) {
    if (!keys.contains(words[i])) continue;
    var j = i + 1;
    while (j < words.length &&
        const {'es', 'el', 'la', 'fue', 'de', 'del'}.contains(words[j])) {
      j++;
    }
    final name = _takeName(words, j);
    if (name.isNotEmpty) return name;
  }
  return null;
}

String? _recipient(List<String> words, List<CatalogEntry> people) =>
    _allFor(words) ?? _goesFor(words, people);

String? _allFor(List<String> words) {
  for (var i = 0; i < words.length; i++) {
    if (words[i] != 'todo') continue;
    var j = i + 1;
    while (j < words.length &&
        const {
          'queda',
          'va',
          'es',
          'asignado',
          'asignada',
          'asignamos',
          'lo',
        }.contains(words[j])) {
      j++;
    }
    if (j < words.length && const {'para', 'a', 'al'}.contains(words[j])) {
      j++;
      while (j < words.length && const {'el', 'la'}.contains(words[j])) {
        j++;
      }
      final name = _takeName(words, j);
      if (name.isNotEmpty) return name;
    }
  }
  return null;
}

String? _goesFor(List<String> words, List<CatalogEntry> people) {
  for (var i = 1; i < words.length; i++) {
    if (words[i] != 'para') continue;
    if (!const {'va', 'es', 'queda', 'sera', 'iba'}.contains(words[i - 1])) {
      continue;
    }
    final aboutPurchase =
        i >= 2 && const {'compra', 'compras'}.contains(words[i - 2]);
    var j = i + 1;
    final article = j < words.length && const {'el', 'la'}.contains(words[j]);
    if (article) j++;
    final name = _takeName(words, j);
    if (name.isEmpty) continue;
    final first = words[j];
    if (_isUse(first, people) || _isUseName(name)) continue;
    final firstIsPerson =
        resolveName(first, people).state != ResolutionState.missing;
    if (aboutPurchase) {
      if (article && !firstIsPerson) continue;
      return name;
    }
    if (firstIsPerson &&
        resolveName(name, people).state != ResolutionState.missing) {
      return name;
    }
  }
  return null;
}

const _determiners = {
  'el',
  'la',
  'los',
  'las',
  'un',
  'una',
  'unos',
  'unas',
  'mi',
  'mis',
  'su',
  'sus',
  'tu',
  'lo',
  'que',
  'este',
  'esta',
  'ese',
  'esa',
  'cuando',
};

bool _isUse(String first, List<CatalogEntry> people) {
  if (_determiners.contains(first)) return true;
  if (isNumberWord(first)) return true;
  final infinitive =
      first.length > 4 &&
      (first.endsWith('ar') || first.endsWith('er') || first.endsWith('ir'));
  if (!infinitive) return false;
  return !people.any((p) => canonicalTokens(p.name).contains(first));
}

bool _isUseName(String name) =>
    name.split(' ').any((w) => farmKeywords.contains(w));

String _takeName(List<String> words, int from) {
  final out = <String>[];
  for (var j = from; j < words.length; j++) {
    final w = words[j];
    if (w == ',' || w == 'y' || w == 'todo' || _supplierKeys.contains(w)) {
      break;
    }
    out.add(w);
  }
  return out.join(' ');
}

DraftField<int>? _exchangeRate(List<String> words) {
  for (var i = 0; i + 2 < words.length; i++) {
    if (!_exchangeRateAt(words, i)) continue;
    final n = readNumberAt(words, _exchangeRateNumber(words, i));
    if (n == null) return null;
    if (!n.isValid || n.thousandths <= 0) {
      return DraftField.invalid(
        message: n.invalidMessage ?? 'El tipo de cambio debe ser mayor a cero.',
        heard: n.heard,
      );
    }
    return DraftField.resolved(
      n.thousandths * 1000,
      origin: FieldOrigin.voice,
      heard: n.heard,
    );
  }
  return null;
}

bool _exchangeRateAt(List<String> words, int i) =>
    i + 2 < words.length &&
    words[i] == 'tipo' &&
    words[i + 1] == 'de' &&
    words[i + 2] == 'cambio';

int _exchangeRateNumber(List<String> words, int i) {
  var j = i + 3;
  while (j < words.length && const {'de', 'es', 'a'}.contains(words[j])) {
    j++;
  }
  return j;
}
