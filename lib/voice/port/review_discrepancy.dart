/// Qué tipo de diferencia hay entre las cifras de los dos reconocedores
/// (diagnóstico F09, POCO 2026-11-09).
///
/// [chooseReviewedText] compara las listas de hechos ([ReviewFacts]) elemento a
/// elemento: si Vosk no oyó «bolivianos el litro» y la revisión sí, las listas
/// tienen distinta longitud y la frase cuenta como desacuerdo numérico. Esa
/// regla **no cambia aquí**. Este módulo sólo explica la diferencia, para el
/// diagnóstico, sin texto ni cifras:
///
/// * agrupa los hechos en **datos** con su papel —cantidad (cifra + unidad),
///   precio (cifra + moneda, con o sin «el litro»), área (cifra + hectáreas),
///   cifra suelta, unidad suelta, moneda suelta—, porque una misma cifra puede
///   ser cantidad, precio o área;
/// * alinea los datos de las dos propuestas por su valor, en orden;
/// * clasifica cada diferencia: valor distinto, dato ausente en uno de los
///   dos, unidad distinta, moneda distinta, formato equivalente, extracción
///   fallida o correspondencia ambigua.
///
/// Una cifra que el lector no entiende (`n?`) es **extracción fallida**, no
/// un valor distinto. Un dato que sólo uno de los dos trae es **ausente**, no
/// una contradicción. Si los datos no se pueden alinear sin adivinar, es
/// **correspondencia ambigua**.
library;

/// Papel del dato afectado.
enum ReviewField {
  /// Cifra con unidad de medida («cinco litros»).
  quantity,

  /// Cifra con moneda («ciento veinte bolivianos»).
  price,

  /// Cifra con hectáreas.
  area,

  /// Cifra sin unidad ni moneda.
  number,

  /// Unidad sin cifra, o la unidad de un precio («el litro»).
  unit,

  /// Moneda sin cifra, o la moneda de un dato que en el otro es precio.
  currency,
}

/// Tipo de diferencia.
enum DiscrepancyKind {
  /// Los dos tienen el dato con valores distintos.
  differentValue,

  /// Sólo uno de los dos tiene el dato (ver [FactDiscrepancy.onlyIn]).
  missing,

  /// La misma cifra con otra unidad.
  differentUnit,

  /// La misma cifra con otra moneda.
  differentCurrency,

  /// El mismo valor escrito de otra forma («1.5» frente a «1,5»).
  equivalentFormat,

  /// Uno de los dos tiene una cifra que el lector de la app no entiende.
  extractionFailed,

  /// No se puede decidir qué dato de uno corresponde a cuál del otro.
  ambiguousAlignment,
}

/// Quién trae un dato que el otro no tiene.
enum ReviewSide { first, review }

/// Una diferencia, sólo con códigos.
final class FactDiscrepancy {
  const FactDiscrepancy(this.field, this.kind, {this.onlyIn});

  final ReviewField field;
  final DiscrepancyKind kind;

  /// Con [DiscrepancyKind.missing]: el reconocedor que sí lo trae.
  final ReviewSide? onlyIn;

  /// Código para el diagnóstico: `campo:tipo` o `campo:missing@lado`.
  String get code => onlyIn == null
      ? '${field.name}:${kind.name}'
      : '${field.name}:${kind.name}@${onlyIn == ReviewSide.first ? 'vosk' : 'revision'}';

  @override
  bool operator ==(Object other) =>
      other is FactDiscrepancy &&
      other.field == field &&
      other.kind == kind &&
      other.onlyIn == onlyIn;

  @override
  int get hashCode => Object.hash(field, kind, onlyIn);

  @override
  String toString() => code;
}

/// Diferencias entre los hechos de [first] (Vosk) y los de [review]. Vacía si
/// dicen lo mismo.
List<FactDiscrepancy> classifyFactDifferences(
  List<String> first,
  List<String> review,
) {
  final a = _claims(first);
  final b = _claims(review);
  final pairs = _align(a, b);
  final out = <FactDiscrepancy>[];
  var i = 0;
  var j = 0;
  for (final (pi, pj) in [...pairs, (a.length, b.length)]) {
    out.addAll(_gap(a.sublist(i, pi), b.sublist(j, pj)));
    if (pi < a.length && pj < b.length) out.addAll(_pair(a[pi], b[pj]));
    i = pi + 1;
    j = pj + 1;
  }
  // Los mismos datos con otros hechos (la moneda antes de la cifra, «Bs
  // 120»): la regla actual lo cuenta como distinto, pero es la misma cosa.
  if (out.isEmpty && !_sameFacts(first, review)) {
    final hasPrice = a.any((c) => c.field == ReviewField.price);
    out.add(
      FactDiscrepancy(
        hasPrice
            ? ReviewField.price
            : (a.isEmpty ? ReviewField.number : a.first.field),
        DiscrepancyKind.equivalentFormat,
      ),
    );
  }
  return out;
}

bool _sameFacts(List<String> x, List<String> y) {
  if (x.length != y.length) return false;
  for (var k = 0; k < x.length; k++) {
    if (x[k] != y[k]) return false;
  }
  return true;
}

/// Un dato: su papel, su valor (`null` si la cifra no se entiende) y lo que
/// lo acompaña.
final class _Claim {
  _Claim(
    this.field, {
    this.value,
    this.tolerant = false,
    this.unreadable = false,
    this.unit,
    this.currency,
    this.priceUnit,
  });

  final ReviewField field;

  /// Milésimas (cifras), o la unidad / moneda en los datos sin cifra.
  final String? value;

  /// La cifra sólo se entiende con la lectura tolerante («1.5»).
  final bool tolerant;

  /// La cifra no se entiende (`n?` sin valor).
  final bool unreadable;
  final String? unit;
  final String? currency;
  final String? priceUnit;

  bool get numeric =>
      field != ReviewField.unit && field != ReviewField.currency;
}

List<_Claim> _claims(List<String> facts) {
  final out = <_Claim>[];
  var i = 0;
  String? at(int k) => k < facts.length ? facts[k] : null;
  bool isNumber(String? f) => f != null && f.startsWith('n');
  bool isUnit(String? f) => f != null && f.startsWith('u') && f != 'uha';
  bool isCurrency(String? f) => f != null && f.startsWith('c');

  while (i < facts.length) {
    final f = facts[i];
    if (isNumber(f)) {
      final (value, tolerant, unreadable) = _number(f);
      final next = at(i + 1);
      if (next == 'uha') {
        out.add(
          _Claim(
            ReviewField.area,
            value: value,
            tolerant: tolerant,
            unreadable: unreadable,
            unit: 'ha',
          ),
        );
        i += 2;
      } else if (isUnit(next)) {
        out.add(
          _Claim(
            ReviewField.quantity,
            value: value,
            tolerant: tolerant,
            unreadable: unreadable,
            unit: next!.substring(1),
          ),
        );
        i += 2;
      } else if (isCurrency(next)) {
        final per = at(i + 2);
        out.add(
          _Claim(
            ReviewField.price,
            value: value,
            tolerant: tolerant,
            unreadable: unreadable,
            currency: next!.substring(1),
            priceUnit: isUnit(per) ? per!.substring(1) : null,
          ),
        );
        i += isUnit(per) ? 3 : 2;
      } else {
        out.add(
          _Claim(
            ReviewField.number,
            value: value,
            tolerant: tolerant,
            unreadable: unreadable,
          ),
        );
        i += 1;
      }
      continue;
    }
    // Moneda delante de la cifra («Bs 120 el litro»): también es un precio.
    if (isCurrency(f) && isNumber(at(i + 1))) {
      final (value, tolerant, unreadable) = _number(at(i + 1)!);
      final per = at(i + 2);
      out.add(
        _Claim(
          ReviewField.price,
          value: value,
          tolerant: tolerant,
          unreadable: unreadable,
          currency: f.substring(1),
          priceUnit: isUnit(per) ? per!.substring(1) : null,
        ),
      );
      i += isUnit(per) ? 3 : 2;
      continue;
    }
    if (isCurrency(f)) {
      out.add(_Claim(ReviewField.currency, value: f.substring(1)));
    } else {
      out.add(_Claim(ReviewField.unit, value: f.substring(1)));
    }
    i++;
  }
  return out;
}

(String?, bool, bool) _number(String fact) {
  if (!fact.startsWith('n?')) return (fact.substring(1), false, false);
  if (fact.length > 2) return (fact.substring(2), true, false);
  return (null, false, true);
}

/// ¿Pueden ser el mismo dato? Mismo valor conocido; o, sin cifra, lo mismo.
bool _sameKey(_Claim x, _Claim y) {
  if (x.numeric != y.numeric) return false;
  if (x.unreadable || y.unreadable) return false;
  if (!x.numeric && x.field != y.field) return false;
  return x.value == y.value;
}

/// Pares alineados (subsecuencia común más larga por valor). Con varias
/// alineaciones posibles de la misma longitud se queda la primera en orden:
/// las que no alinean se tratan en los huecos.
List<(int, int)> _align(List<_Claim> a, List<_Claim> b) {
  final n = a.length;
  final m = b.length;
  final lcs = List.generate(n + 1, (_) => List.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      lcs[i][j] = _sameKey(a[i], b[j])
          ? lcs[i + 1][j + 1] + 1
          : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
    }
  }
  final out = <(int, int)>[];
  var i = 0;
  var j = 0;
  while (i < n && j < m) {
    if (_sameKey(a[i], b[j]) && lcs[i][j] == lcs[i + 1][j + 1] + 1) {
      out.add((i, j));
      i++;
      j++;
    } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  return out;
}

/// Datos que no alinearon por valor entre dos pares alineados.
List<FactDiscrepancy> _gap(List<_Claim> a, List<_Claim> b) {
  if (a.isEmpty && b.isEmpty) return const [];
  FactDiscrepancy only(_Claim c, ReviewSide side) => c.unreadable
      ? FactDiscrepancy(c.field, DiscrepancyKind.extractionFailed)
      : FactDiscrepancy(c.field, DiscrepancyKind.missing, onlyIn: side);
  if (a.isEmpty) return [for (final c in b) only(c, ReviewSide.review)];
  if (b.isEmpty) return [for (final c in a) only(c, ReviewSide.first)];
  // Mismo número de datos a los dos lados: se corresponden en orden. Una
  // cifra frente a una unidad o moneda suelta no es la misma cosa: cada una
  // falta en el otro.
  if (a.length == b.length) {
    return [
      for (var k = 0; k < a.length; k++)
        if (a[k].numeric != b[k].numeric) ...[
          only(a[k], ReviewSide.first),
          only(b[k], ReviewSide.review),
        ] else if (a[k].unreadable || b[k].unreadable)
          FactDiscrepancy(a[k].field, DiscrepancyKind.extractionFailed)
        else
          FactDiscrepancy(
            a[k].field == b[k].field ? a[k].field : _wider(a[k], b[k]),
            DiscrepancyKind.differentValue,
          ),
    ];
  }
  // Distinto número de datos con valores distintos: no se adivina cuál es
  // cuál.
  final unreadable = [...a, ...b].any((c) => c.unreadable);
  return [
    FactDiscrepancy(
      a.first.field,
      unreadable
          ? DiscrepancyKind.extractionFailed
          : DiscrepancyKind.ambiguousAlignment,
    ),
  ];
}

/// Mismo valor en los dos: ¿con el mismo papel, unidad y moneda?
List<FactDiscrepancy> _pair(_Claim x, _Claim y) {
  final out = <FactDiscrepancy>[];
  if (x.tolerant != y.tolerant) {
    out.add(FactDiscrepancy(_wider(x, y), DiscrepancyKind.equivalentFormat));
  }
  if (!x.numeric) return out;
  final fx = x.field;
  final fy = y.field;
  if (fx == fy) {
    switch (fx) {
      case ReviewField.quantity:
        if (x.unit != y.unit) {
          out.add(
            const FactDiscrepancy(
              ReviewField.quantity,
              DiscrepancyKind.differentUnit,
            ),
          );
        }
      case ReviewField.price:
        if (x.currency != y.currency) {
          out.add(
            const FactDiscrepancy(
              ReviewField.price,
              DiscrepancyKind.differentCurrency,
            ),
          );
        }
        out.addAll(_priceUnit(x, y));
      default:
        break;
    }
    return out;
  }
  // Mismo valor con otro papel: lo que distingue un papel del otro (unidad,
  // moneda) falta en uno, o es otra unidad.
  final xp = fx == ReviewField.price;
  final yp = fy == ReviewField.price;
  if (xp || yp) {
    final side = xp ? ReviewSide.first : ReviewSide.review;
    out.add(
      FactDiscrepancy(
        ReviewField.currency,
        DiscrepancyKind.missing,
        onlyIn: side,
      ),
    );
    final price = xp ? x : y;
    final other = xp ? y : x;
    // «ciento veinte litro» frente a «120 bolivianos el litro»: la unidad
    // del precio está en los dos.
    if (price.priceUnit != null && other.unit == null) {
      out.add(
        FactDiscrepancy(
          ReviewField.unit,
          DiscrepancyKind.missing,
          onlyIn: side,
        ),
      );
    } else if (price.priceUnit == null && other.unit != null) {
      out.add(
        FactDiscrepancy(
          ReviewField.unit,
          DiscrepancyKind.missing,
          onlyIn: xp ? ReviewSide.review : ReviewSide.first,
        ),
      );
    } else if (price.priceUnit != other.unit) {
      out.add(
        const FactDiscrepancy(ReviewField.price, DiscrepancyKind.differentUnit),
      );
    }
    return out;
  }
  if (fx == ReviewField.number || fy == ReviewField.number) {
    final with_ = fx == ReviewField.number ? y : x;
    out.add(
      FactDiscrepancy(
        with_.field,
        DiscrepancyKind.missing,
        onlyIn: fx == ReviewField.number ? ReviewSide.review : ReviewSide.first,
      ),
    );
    return out;
  }
  // Cantidad frente a área: otra unidad.
  out.add(FactDiscrepancy(fx, DiscrepancyKind.differentUnit));
  return out;
}

List<FactDiscrepancy> _priceUnit(_Claim x, _Claim y) {
  if (x.priceUnit == y.priceUnit) return const [];
  if (x.priceUnit == null || y.priceUnit == null) {
    return [
      FactDiscrepancy(
        ReviewField.unit,
        DiscrepancyKind.missing,
        onlyIn: x.priceUnit == null ? ReviewSide.review : ReviewSide.first,
      ),
    ];
  }
  return const [
    FactDiscrepancy(ReviewField.price, DiscrepancyKind.differentUnit),
  ];
}

/// El papel más informativo de dos con el mismo valor.
ReviewField _wider(_Claim x, _Claim y) =>
    x.field == ReviewField.number ? y.field : x.field;
