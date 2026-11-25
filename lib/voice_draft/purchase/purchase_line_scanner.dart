part of 'purchase_interpreter.dart';

final class _HeardLine {
  _HeardLine(this.productHeard, {this.explicitNew = false, this.open = false});
  final String productHeard;
  final bool explicitNew;
  final bool open;
  DraftField<SpokenQuantity>? quantity;
  DraftField<SpokenPrice>? price;
  DraftField<CurrencyCode>? currency;
  CatalogUnit? priceUnitHeard;
  bool priceIsTotal = false;
}

final class _Heard {
  final lines = <_HeardLine>[];
  final loose = <_PriceClause>[];
  var sawMeasure = false;
}

const _another = {'otro', 'otra', 'otros', 'otras'};

_PriceClause? _looseAt(List<String> words, int i) {
  if (_priceConnectors.contains(words[i]) || words[i] == 'precio') {
    return _readClause(words, i, loose: true);
  }
  if (!_numberThenCurrency(words, i)) return null;
  final before = i > 0 ? words[i - 1] : null;
  final suspicious = before != null && !_looseLead.contains(before);
  return _readClause(
    words,
    i,
    loose: true,
    stray: suspicious ? before : null,
    heardFrom: suspicious ? i - 1 : i,
  );
}

_Heard _scan(List<String> words, List<CatalogEntry> products) {
  final out = _Heard();
  var i = 0;
  while (i < words.length) {
    if (_exchangeRateAt(words, i)) {
      final k = _exchangeRateNumber(words, i);
      final n = readNumberAt(words, k);
      i = n != null && n.end > k ? n.end : k;
      continue;
    }
    final m = readMeasureAt(words, i);
    if (m == null) {
      final loose = _looseAt(words, i);
      if (loose != null) {
        out.loose.add(loose);
        i = loose.end > i ? loose.end : i + 1;
        continue;
      }
      final n = readNumberAt(words, i);
      i = n != null && n.end > i ? n.end : i + 1;
      continue;
    }
    out.sawMeasure = true;
    final unit = unitWord(m.unitWord)!;
    var j = m.end;
    if (j < words.length && (words[j] == 'de' || words[j] == 'del')) j++;
    final nameStart = j;
    while (j < words.length && !_stop.contains(words[j])) {
      if (words[j] == 'y' && readMeasureAt(words, j + 1) != null) break;
      if (_numberThenCurrency(words, j)) break;
      if (_totalIntroEnd(words, j) != null) break;
      j++;
    }
    var nameEnd = j;

    _PriceClause? clause;
    final pause = j < words.length && words[j] == ',' ? j + 1 : j;
    final totalIntro = _totalIntroEnd(words, pause);
    if (totalIntro != null) {
      clause = _readClause(words, totalIntro, totalSaidBefore: true);
    } else if (pause < words.length &&
        (_priceConnectors.contains(words[pause]) || words[pause] == 'precio')) {
      if (pause == j && words[j] == 'precio') {
        while (nameEnd > nameStart &&
            const {'el', 'la', 'con', 'su'}.contains(words[nameEnd - 1])) {
          nameEnd--;
        }
      }
      clause = _readClause(words, pause);
    } else if (_numberThenCurrency(words, pause)) {
      String? stray;
      var heardFrom = pause;
      if (pause == j) {
        while (nameEnd - nameStart > 1 && _glue.contains(words[nameEnd - 1])) {
          nameEnd--;
        }
        if (nameEnd - nameStart > 1 &&
            resolveName(words[nameEnd - 1], products).state ==
                ResolutionState.missing) {
          nameEnd--;
          stray = words[nameEnd];
          heardFrom = nameEnd;
        }
      }
      clause = _readClause(words, pause, stray: stray, heardFrom: heardFrom);
    }
    final productWords = words.sublist(nameStart, nameEnd);

    if (productWords.isEmpty && !endsSegment(words, j)) {
      i = j;
      continue;
    }
    final line = _HeardLine(
      productWords.join(' '),
      explicitNew: m.start > 0 && _another.contains(words[m.start - 1]),
      open: productWords.isEmpty && nameStart > m.end,
    );
    line.quantity = measureField<SpokenQuantity>(
      words,
      m,
      (thousandths) => SpokenQuantity(thousandths, unit),
      zeroMessage: 'La cantidad debe ser mayor a cero.',
      invalidHeard: m.numberHeard.isEmpty ? m.heard : m.numberHeard,
    );
    if (clause != null) {
      final next = _followingClause(words, clause.end);
      final second = next != null && (clause.total || _complete(clause))
          ? next
          : null;
      if (second != null) {
        final (price, currency) = _combinePrices(
          clause,
          second,
          line.quantity?.value,
        );
        line.price = price;
        line.currency = currency;
        j = second.end;
      } else {
        final (price, currency) = _priceFields(clause);
        line.price = price;
        line.currency = currency;
        line.priceIsTotal = clause.total;
        if (clause.unknownBeforeUnit != null) {
          line.priceUnitHeard = clause.perUnit;
        }
        j = clause.end;
      }
    }
    out.lines.add(line);
    i = j > i ? j : i + 1;
  }
  if (out.lines.length > 1 && out.lines.last.priceIsTotal) {
    final last = out.lines.last;
    final said = last.price?.value?.minorPerUnit;
    last.price = DraftField.ambiguous(
      candidates: const [],
      heard: last.price?.heard ?? '',
      message:
          'Se oyó un total'
          '${said == null ? '' : ' de ${amountText(said, last.currency?.value)}'} '
          'después de varias líneas: no se sabe si es de esta línea o de toda '
          'la compra. Escriba el precio por unidad de cada línea.',
    );
    last.priceIsTotal = false;
  }
  return out;
}

_PriceClause? _followingClause(List<String> words, int from) {
  var p = from;
  while (p < words.length &&
      const {
        ',',
        'y',
        'con',
        'que',
        'es',
        'son',
        'o',
        'sea',
      }.contains(words[p])) {
    p++;
  }
  if (p >= words.length) return null;
  var t = p;
  if (t < words.length && const {'en', 'para'}.contains(words[t])) t++;
  final afterTotal = _totalLeadEnd(words, t);
  if (afterTotal != null && _numberThenCurrency(words, afterTotal)) {
    return _readClause(words, afterTotal, totalSaidBefore: true);
  }
  if (_priceConnectors.contains(words[p]) || words[p] == 'precio') {
    return _readClause(words, p, loose: true);
  }
  if (_numberThenCurrency(words, p)) return _readClause(words, p, loose: true);
  return null;
}

bool _complete(_PriceClause c) =>
    c.kindsContradict || c.currency != null || c.form != _PerUnit.none;

(DraftField<SpokenPrice>, DraftField<CurrencyCode>?) _combinePrices(
  _PriceClause a,
  _PriceClause b,
  SpokenQuantity? quantity,
) {
  final (pa, ca) = _priceFields(a);
  final (pb, cb) = _priceFields(b);
  final currenciesClash =
      a.currency != null && b.currency != null && a.currency != b.currency;
  final currency = currenciesClash ? null : (ca ?? cb);
  final heard = '${a.heard} · ${b.heard}';
  (DraftField<SpokenPrice>, DraftField<CurrencyCode>?) contradiction() => (
    DraftField.ambiguous(
      candidates: const [],
      heard: heard,
      message:
          'Se oyeron dos importes que no cuadran entre sí'
          '${currenciesClash ? ' (en monedas distintas)' : ''}: escriba el '
          'precio por unidad.',
    ),
    currency,
  );
  if (currenciesClash || a.kindsContradict || b.kindsContradict) {
    return contradiction();
  }
  if (a.total == b.total) {
    return a.number.thousandths == b.number.thousandths
        ? (pa, currency)
        : contradiction();
  }
  final unit = a.total ? b : a;
  final total = a.total ? a : b;
  final unitField = a.total ? pb : pa;
  final perUnitClear = unit.form == _PerUnit.clean && unit.perUnit != null;
  final fits =
      perUnitClear &&
      quantity != null &&
      quantity.unit.family == unit.perUnit &&
      quantity.thousandths * unit.number.thousandths ==
          total.number.thousandths * 1000;
  return fits ? (unitField, currency) : contradiction();
}
