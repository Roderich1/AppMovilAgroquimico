part of 'purchase_interpreter.dart';

const _supplierKeys = {'proveedor', 'proveedora', 'provedor', 'provedora'};

const _stop = {
  ',',
  'a',
  'al',
  'por',
  'precio',
  ..._supplierKeys,
  'todo',
  'tipo',
  'en',
};

const _priceConnectors = {'a', 'al', 'por'};

const _currencyVariants = {'boliviana', 'bolivianas'};

bool _currencyLike(String w) =>
    currencyWord(w) != null || _currencyVariants.contains(w);

bool _numberThenCurrency(List<String> words, int i) {
  final n = readNumberAt(words, i);
  if (n == null || n.end <= i) return false;
  final at = _skipSeparatorComma(words, n.end);
  return at < words.length && _currencyLike(words[at]);
}

int _skipSeparatorComma(List<String> words, int at) =>
    at + 1 < words.length && words[at] == ',' && _currencyLike(words[at + 1])
    ? at + 1
    : at;

const _glue = {'de', 'del', 'y'};

const _looseLead = {
  ',',
  'y',
  'es',
  'son',
  'cuesta',
  'cuestan',
  'vale',
  'valen',
};

List<String> _purchaseWords(String text, List<CatalogEntry> products) {
  final out = <String>[];
  final words = tokenize(text);
  Set<String>? productWords;
  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    final split = _splitGluedVerb(
      w,
      () => productWords ??= {
        for (final p in products) ...canonicalTokens(p.name),
      },
    );
    if (split != null) {
      out.addAll(split);
      continue;
    }
    final glued = _gluedCurrency.firstMatch(w);
    if (glued != null) {
      out
        ..add(_dotDecimal(glued.group(1)!))
        ..add(glued.group(2)!);
      continue;
    }
    if (w == ',' &&
        out.isNotEmpty &&
        out.last == 'bs' &&
        i + 2 < words.length &&
        const {'el', 'la', 'por', 'cada'}.contains(words[i + 1]) &&
        unitWord(words[i + 2]) != null) {
      continue;
    }
    out.add(_dotDecimal(w));
  }
  return out;
}

const _gluedVerbForms = [
  'compraron',
  'compramos',
  'comprado',
  'compre',
  'compra',
];

const _afterGluedVerb = {
  'de',
  'del',
  'el',
  'la',
  'los',
  'las',
  'un',
  'una',
  'unos',
  'unas',
};

List<String>? _splitGluedVerb(String w, Set<String> Function() productWords) {
  if (_purchaseVerbs.contains(w) || !w.startsWith('compr')) return null;
  for (final verb in _gluedVerbForms) {
    if (!w.startsWith(verb) || w.length <= verb.length) continue;
    final rest = w.substring(verb.length);
    final known =
        _afterGluedVerb.contains(rest) ||
        (isNumberWord(rest) && readNumberAt([rest], 0) != null) ||
        unitWord(rest) != null ||
        productWords().contains(rest);
    return known ? [verb, rest] : null;
  }
  return null;
}

final _gluedCurrency = RegExp(r'^(\d(?:[\d.,]*\d)?)(bs|bob|usd)$');
final _dotDecimalPattern = RegExp(r'^\d+\.\d{1,2}$');

String _dotDecimal(String w) =>
    _dotDecimalPattern.hasMatch(w) ? w.replaceFirst('.', ',') : w;

const _negated = 'negacion';
const _future = 'intencion-futura';

const _futurePurchase = {
  'comprare',
  'compraremos',
  'compraran',
  'compraria',
  'comprariamos',
};

const _wantTo = {
  'quiero',
  'queremos',
  'quisiera',
  'quisieramos',
  'necesito',
  'necesitamos',
  'pienso',
  'pensamos',
  'debo',
  'debemos',
  'deberia',
  'deberiamos',
  'podria',
  'podriamos',
};

String? _purchaseMood(List<String> words) {
  String? at(int i) => i >= 0 && i < words.length ? words[i] : null;
  const negations = {'no', 'nunca', 'tampoco'};
  const pronouns = {'lo', 'la', 'los', 'las', 'le', 'les'};
  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    if (_futurePurchase.contains(w)) return _future;
    if (!_purchaseVerbs.contains(w) && w != 'compraron') continue;
    final before = at(i - 1);
    if (negations.contains(before) ||
        (pronouns.contains(before) && negations.contains(at(i - 2)))) {
      return _negated;
    }
    if (w == 'comprar') {
      if (_wantTo.contains(before)) return _future;
      if (before == 'a' &&
          const {
            'voy',
            'vamos',
            'va',
            'van',
            'iba',
            'ibamos',
          }.contains(at(i - 2))) {
        return _future;
      }
      if (before == 'que' &&
          const {'tengo', 'tenemos', 'tiene', 'hay'}.contains(at(i - 2))) {
        return _future;
      }
    }
  }
  return null;
}

const _purchaseLead = {
  'compré',
  'compre',
  'compramos',
  'también',
  'tambien',
  'además',
  'ademas',
  'y',
};

const _purchaseVerbs = {
  'compre',
  'compramos',
  'compra',
  'compras',
  'compraron',
  'comprado',
  'comprar',
};

const _beforePurchaseVerb = {
  ',',
  'bueno',
  'eh',
  'em',
  'este',
  'ya',
  'ok',
  'okey',
  'pues',
  'entonces',
  'hoy',
  'ayer',
  'anteayer',
  'antier',
  'recien',
  'esta',
  'manana',
  'tarde',
  'noche',
  'yo',
  'nosotros',
  'tambien',
  'ademas',
  'y',
  'he',
  'hemos',
};

int? _afterPurchaseVerb(List<String> words) {
  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    if (_purchaseVerbs.contains(w)) {
      var after = i + 1;
      if (w == 'compra' &&
          after < words.length &&
          const {'de', 'del'}.contains(words[after])) {
        after++;
      }
      return after;
    }
    if (!_beforePurchaseVerb.contains(w)) return null;
  }
  return null;
}

const _leadingArticles = {
  'el',
  'la',
  'los',
  'las',
  'un',
  'una',
  'unos',
  'unas',
};

const _trailingTime = <List<String>>[
  ['esta', 'manana'],
  ['esta', 'tarde'],
  ['esta', 'noche'],
  ['esta', 'semana'],
  ['hoy'],
  ['ayer'],
  ['anteayer'],
  ['antier'],
  ['recien'],
];

Resolution _resolveProduct(String heard, List<CatalogEntry> products) {
  final full = resolveName(heard, products);
  if (full.state == ResolutionState.resolved) return full;
  final words = heard.split(' ').where((w) => w.isNotEmpty).toList();
  final from = words.length > 1 && _leadingArticles.contains(words.first)
      ? 1
      : 0;
  var to = words.length;
  for (final time in _trailingTime) {
    final at = words.length - time.length;
    if (at > from && _sameWords(words.sublist(at), time)) {
      to = at;
      break;
    }
  }
  for (final (a, b) in [(from, words.length), (0, to), (from, to)]) {
    if (a == 0 && b == words.length) continue;
    if (b <= a) continue;
    final trimmed = resolveName(words.sublist(a, b).join(' '), products);
    if (trimmed.state == ResolutionState.resolved) return trimmed;
  }
  return full;
}

bool _sameWords(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
