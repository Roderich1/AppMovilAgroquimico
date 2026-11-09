/// Del texto dictado a un parche del borrador de compra (EVO-010 / EVO-017).
///
/// Reglas deterministas, sin modelo ni red. Se ajustaron sólo con frases de la
/// partición `ajuste` del corpus del banco y con frases propias de las pruebas;
/// la partición `aceptacion` no se usó.
///
/// Forma que reconoce, en cualquier orden y repartida en varios dictados:
///
/// - una línea: «cincuenta litros de Bellator a ciento ochenta y seis
///   bolivianos el litro»;
/// - el proveedor: «el proveedor es Agro Norte» (también «provedor», como lo
///   entrega a veces el reconocedor);
/// - la persona: «todo para José», «todo queda asignado al administrador»,
///   «esta compra va para Ana» o «es para Ana» si Ana es una persona elegible;
/// - el tipo de cambio: «tipo de cambio seis coma noventa y seis»;
/// - un precio dicho aparte («a cincuenta bolivianos el litro»), que sólo se
///   pone en una línea si hay exactamente una que pueda recibirlo.
///
/// Volver a nombrar un producto ya presente **corrige esa línea** sólo en los
/// campos que se dicen. Nada de lo dictado sobrescribe un campo editado a mano.
///
/// POCO 2026-11-08 (datos sintéticos): «… cinco litros de herbicida demo a
/// ciento veinte bolivianos el litro» llegó como «… herbicidas demo haciendo
/// veinte bolivianas litro». Sin la «a», todo acababa en el nombre del
/// producto y el precio quedaba vacío. Ahora el nombre se corta donde empieza
/// una cifra seguida de moneda, y un precio sin conector nunca queda resuelto:
/// como mucho queda **por revisar** y, si hay señales de mala transcripción,
/// sin valor y pidiendo que se diga de nuevo. Nunca se reconstruye una cifra
/// («haciendo» no se convierte en «a ciento»).
library;

import '../../domain/models.dart';
import '../catalog/voice_catalog.dart';
import '../core/draft_field.dart';
import '../interpretation/phrases.dart';
import '../interpretation/voice_intent.dart';
import '../text/normalize.dart';
import '../text/spanish_numbers.dart';
import '../text/units.dart';
import 'voice_purchase_draft.dart';

/// Resultado de interpretar un dictado.
final class PurchaseInterpretation {
  const PurchaseInterpretation({
    required this.draft,
    required this.outcome,
    this.otherIntent,
    this.ignoredRecipient,
    this.unplacedPrice,
    this.lineNotice,
  });

  final VoicePurchaseDraft draft;
  final VoicePatchOutcome outcome;

  /// En inventario propio la compra es del titular, sin elegir persona (como
  /// en el formulario): una persona dictada se ignora y se informa.
  final String? ignoredRecipient;

  /// Si el dictado parece otra operación (aplicación, plan, pago o
  /// consulta), no se aplicó nada y esto lo dice.
  final VoiceIntent? otherIntent;

  /// Un precio dicho aparte que **no se puso en ninguna línea**: no había una
  /// sola línea que pudiera recibirlo o el precio no estaba claro. La
  /// pantalla debe decirlo ([UnplacedPrice.message]); el borrador no cambió
  /// por ese precio.
  final UnplacedPrice? unplacedPrice;

  /// Lo oído que no se aplicó a ninguna línea porque no estaba claro a cuál
  /// iba (o un producto fuera del catálogo dicho sin cantidad). La pantalla
  /// lo muestra; el borrador no cambió por eso.
  final String? lineNotice;
}

/// Por qué un precio dicho aparte no se puso en ninguna línea.
enum UnplacedPriceReason {
  /// Ninguna línea puede recibirlo: no hay líneas, todas tienen precio, o la
  /// única sin precio aún no tiene un producto elegido.
  noLine,

  /// Varias líneas sin precio: no se sabe a cuál va.
  severalLines,

  /// Se dijo «el litro» y la única línea sin precio se mide en kilos, o al
  /// revés.
  unitMismatch,

  /// No quedó claro si es por litro o por kilo («cincuenta bolivianos»,
  /// «cincuenta bolivianos de litro»).
  unitNotSaid,

  /// Se dijo un total; la compra se registra con precio por litro o kilo.
  total,

  /// El precio no se entendió bien (moneda mal transcrita, palabra extraña
  /// antes de la cifra, cifra que no se puede leer).
  unclear,

  /// El mismo dictado traía cantidades u otros precios: el precio suelto no
  /// se reparte por adivinación.
  notAlone,
}

/// Un precio oído que no se aplicó. Sólo informa; no es un valor aceptado.
final class UnplacedPrice {
  const UnplacedPrice({
    required this.heard,
    required this.reason,
    required this.message,
  });

  /// Lo oído, tal cual («cincuenta bolivianos de litro»).
  final String heard;
  final UnplacedPriceReason reason;

  /// Texto para la persona, listo para mostrar.
  final String message;
}

/// Palabra clave del proveedor. «provedor» es como el reconocedor entrega a
/// veces «proveedor» (POCO 2026-11-08); sólo cuenta como palabra clave, nunca
/// como parte de un nombre. No hay alias de nombres (ver `normalize.dart`).
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

/// Conectores que anuncian el precio: «a», «al», «por» (y «precio», aparte).
const _priceConnectors = {'a', 'al', 'por'};

/// Variantes de moneda que el reconocedor entrega en lugar de «bolivianos».
/// **Sólo cortan el nombre del producto**: nunca dan la moneda ni el precio
/// por buenos.
const _currencyVariants = {'boliviana', 'bolivianas'};

bool _currencyLike(String w) =>
    currencyWord(w) != null || _currencyVariants.contains(w);

/// ¿Empieza en [i] una cifra seguida de una palabra de moneda («ciento veinte
/// bolivianos»)? Un número **sin** moneda detrás es parte del nombre («Germi
/// cien», «glifosato 480», «2,4-D amina 720»).
bool _numberThenCurrency(List<String> words, int i) {
  final n = readNumberAt(words, i);
  return n != null &&
      n.end > i &&
      n.end < words.length &&
      _currencyLike(words[n.end]);
}

/// Palabras que unen el nombre con la cifra sin ser parte de ninguno («de
/// ciento veinte bolivianos»). Se quitan del nombre sin sospechar de ellas.
const _glue = {'de', 'del', 'y'};

/// Lo que puede preceder a una cifra suelta sin hacer sospechar de la
/// transcripción («y ciento veinte…», «son ciento veinte…»).
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

PurchaseInterpretation interpretPurchase(
  String text,
  VoicePurchaseDraft current,
  VoiceCatalog catalog,
) {
  final words = tokenize(text);
  final intent = classifyIntent(words);
  if (intent != VoiceIntent.purchase && intent != VoiceIntent.none) {
    return PurchaseInterpretation(
      draft: current,
      outcome: const VoicePatchOutcome(),
      otherIntent: intent,
    );
  }

  var draft = current;
  var outcome = const VoicePatchOutcome();

  // POCO §2.2: «compré cinco kilos de» [pausa] «Mancozeb».
  final waiting = draft.lines.lastOrNull;
  final name = intent == VoiceIntent.none ? bareName(words) : null;
  if (name != null && waiting != null && isAwaitingProduct(waiting.product)) {
    final (field, o) = mergeField(
      waiting.product,
      entryField(resolveName(name, catalog.products), 'producto'),
    );
    return PurchaseInterpretation(
      draft: draft.updateLine(waiting.key, (l) => l.copyWith(product: field)),
      outcome: o,
    );
  }

  final supplier = _nameAfter(words, _supplierKeys);
  if (supplier != null) {
    final (field, o) = mergeField(
      draft.supplier,
      entryField(resolveName(supplier, catalog.suppliers), 'proveedor'),
    );
    draft = draft.copyWith(supplier: field);
    outcome += o;
  }

  final recipient = _recipient(words, catalog.people);
  String? ignoredRecipient;
  if (recipient != null && catalog.personalOwner != null) {
    ignoredRecipient = recipient;
  } else if (recipient != null) {
    final (field, o) = mergeField(
      draft.recipient,
      entryField(resolveName(recipient, catalog.people), 'persona'),
    );
    draft = draft.copyWith(recipient: field);
    outcome += o;
  }

  final fx = _exchangeRate(words);
  if (fx != null) {
    final (field, o) = mergeField(draft.exchangeRate, fx);
    draft = draft.copyWith(exchangeRate: field);
    outcome += o;
  }

  final heard = _scan(words, catalog.products);
  // Líneas creadas por este mismo dictado: un segundo producto igual en la
  // misma frase es otra línea, no una corrección de la primera.
  final added = <int>{};
  final notices = <String>[];
  for (final line in heard.lines) {
    // Una cantidad que cerró el tramo espera su producto en el siguiente.
    final product = line.productHeard.isEmpty
        ? awaitingProduct
        : entryField(
            resolveName(line.productHeard, catalog.products),
            'producto',
          );
    final placed = _placeLine(draft, line, product, added);
    if (placed.notice != null) {
      notices.add(placed.notice!);
      continue;
    }
    final target = placed.target;
    if (target != null) {
      // El producto sólo se vuelve a leer en una línea cuyo producto no se
      // había resuelto (lo mismo oído otra vez); el de una línea ya resuelta
      // es el mismo y no se toca.
      final (pr, opr) = line.productHeard.isEmpty || target.product.isResolved
          ? (target.product, const VoicePatchOutcome())
          : mergeField(target.product, product);
      final (q, oq) = mergeField(target.quantity, line.quantity);
      final (p, op) = mergeField(target.price, line.price);
      final (c, oc) = mergeField(target.currency, line.currency);
      draft = draft.updateLine(
        target.key,
        (l) => l.copyWith(product: pr, quantity: q, price: p, currency: c),
      );
      outcome += opr + oq + op + oc;
    } else {
      final created = VoicePurchaseLine(
        key: draft.nextLineKey,
        product: product,
        quantity: line.quantity ?? const DraftField.missing(),
        price:
            line.price ??
            const DraftField.missing(message: 'Diga o escriba el precio.'),
        currency:
            line.currency ??
            const DraftField.missing(message: 'Diga o elija la moneda.'),
      );
      added.add(created.key);
      draft = draft.copyWith(
        lines: [...draft.lines, created],
        nextLineKey: draft.nextLineKey + 1,
      );
      outcome += const VoicePatchOutcome(applied: 1);
    }
  }

  // «compré herbicida demo»: un producto sin cantidad. Completa la línea que
  // espera producto, o abre una línea que espera la cantidad. Un nombre que
  // no está en el catálogo no abre nada: se avisa.
  if (heard.lines.isEmpty &&
      !heard.sawMeasure &&
      heard.loose.isEmpty &&
      intent == VoiceIntent.purchase &&
      supplier == null &&
      recipient == null &&
      fx == null) {
    final alone = _productAlone(words);
    if (alone != null) {
      final field = entryField(
        resolveName(alone, catalog.products),
        'producto',
      );
      final (d, o, notice) = _productWithoutQuantity(draft, field, alone);
      draft = d;
      outcome += o;
      if (notice != null) notices.add(notice);
    }
  }

  UnplacedPrice? unplaced;
  if (heard.loose.length > 1) {
    unplaced = _unplaced(
      heard.loose.map((c) => c.heard).join(' · '),
      UnplacedPriceReason.notAlone,
    );
  } else if (heard.loose.length == 1) {
    final clause = heard.loose.single;
    if (heard.lines.isNotEmpty || heard.sawMeasure) {
      unplaced = _unplaced(clause.heard, UnplacedPriceReason.notAlone);
    } else {
      final (placed, o, why) = _placePrice(draft, clause);
      draft = placed;
      outcome += o;
      unplaced = why;
    }
  }

  return PurchaseInterpretation(
    draft: draft,
    outcome: outcome,
    ignoredRecipient: ignoredRecipient,
    unplacedPrice: unplaced,
    lineNotice: notices.isEmpty ? null : notices.join(' '),
  );
}

/// A qué línea va lo oído ([_HeardLine]): `target` nula = línea nueva;
/// `notice` = no está claro y no se aplica nada.
///
/// - Producto del catálogo: la línea de ese producto (corrige los campos
///   dichos), salvo «otros …» o que la haya creado este mismo dictado (dos
///   líneas del mismo producto en una frase no se funden en silencio). Con
///   varias líneas de ese producto se pide corregir a mano.
/// - Cantidad sin producto: la línea que espera producto (repetir la frase
///   no añade otra); si no hay, la **única** línea con producto y sin
///   cantidad; con varias, se pide elegir. Con «tres litros de» (el producto
///   viene después) o sin ninguna, una línea nueva que espera producto.
/// - Producto oído que no se resuelve: la línea con lo mismo oído y sin
///   resolver, si hay una sola (repetir la frase no la duplica).
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

/// Verbo y enlaces que pueden preceder a un producto dicho solo («compré
/// herbicida demo», «también compré …»).
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

/// El producto de «compré herbicida demo», o `null` si el dictado dice algo
/// más que un nombre.
String? _productAlone(List<String> words) {
  var i = 0;
  while (i < words.length && _purchaseLead.contains(words[i])) {
    i++;
  }
  if (i == 0 || i >= words.length) return null;
  return bareName(words.sublist(i));
}

/// Un producto dicho sin cantidad: completa la línea que espera producto;
/// si ya hay una línea de ese producto, no cambia nada; si no, abre una
/// línea que espera la cantidad. Fuera del catálogo no abre nada y avisa.
(VoicePurchaseDraft, VoicePatchOutcome, String?) _productWithoutQuantity(
  VoicePurchaseDraft draft,
  DraftField<CatalogEntry> product,
  String heard,
) {
  if (product.status == FieldStatus.missing) {
    return (
      draft,
      const VoicePatchOutcome(),
      'Se oyó «$heard», que no está en el catálogo: dígalo de nuevo o '
          'elíjalo en la línea.',
    );
  }
  final waiting = [
    for (final l in draft.lines)
      if (isAwaitingProduct(l.product)) l,
  ];
  if (waiting.length == 1) {
    final (field, o) = mergeField(waiting.single.product, product);
    return (
      draft.updateLine(waiting.single.key, (l) => l.copyWith(product: field)),
      o,
      null,
    );
  }
  if (product.isResolved &&
      draft.lines.any((l) => l.product.value?.id == product.value!.id)) {
    return (draft, const VoicePatchOutcome(), null);
  }
  final line = VoicePurchaseLine(
    key: draft.nextLineKey,
    product: product,
    price: const DraftField.missing(message: 'Diga o escriba el precio.'),
    currency: const DraftField.missing(message: 'Diga o elija la moneda.'),
  );
  return (
    draft.copyWith(
      lines: [...draft.lines, line],
      nextLineKey: draft.nextLineKey + 1,
    ),
    const VoicePatchOutcome(applied: 1),
    null,
  );
}

/// Nombre que sigue a una palabra clave («proveedor es Agro Norte»).
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

/// Persona que recibe la compra.
String? _recipient(List<String> words, List<CatalogEntry> people) =>
    _allFor(words) ?? _goesFor(words, people);

/// «todo para José», «todo queda asignado al administrador».
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

/// «(esta|la) compra va para X», «es para X», «va para X».
///
/// «para» también dice el **uso** del producto («es para el maíz», «va para
/// la plaga», «es para fumigar», «va para el chaco Norte»), así que sólo se
/// toma como persona cuando el contexto no deja dudas:
///
/// - el sujeto es la compra («esta compra va para …»): se toma lo que sigue
///   (si no está entre las personas elegibles queda faltante, sin crear),
///   salvo que sea claramente un uso: un chaco o parcela, un infinitivo, un
///   determinante («mi», «los», …) o un artículo seguido de algo que no es
///   una persona elegible;
/// - sin la compra como sujeto, X debe **empezar** por el nombre de una
///   persona elegible y resolverse en [people] (exacto, o aproximado, que
///   queda ambiguo para elegir). «el maíz» no empieza por ninguna persona.
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

/// ¿Dice [first] un uso y no una persona? Un determinante o un infinitivo
/// («fumigar», «aplicar», «controlar»). Un infinitivo aparente que es parte
/// del nombre de una persona elegible («Javier», «Omar») no cuenta.
bool _isUse(String first, List<CatalogEntry> people) {
  if (_determiners.contains(first)) return true;
  if (isNumberWord(first)) return true;
  final infinitive =
      first.length > 4 &&
      (first.endsWith('ar') || first.endsWith('er') || first.endsWith('ir'));
  if (!infinitive) return false;
  return !people.any((p) => canonicalTokens(p.name).contains(first));
}

/// Un chaco o una parcela en lo que sigue a «para» es un uso.
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

/// Primera palabra de la cifra del tipo de cambio que empieza en [i].
int _exchangeRateNumber(List<String> words, int i) {
  var j = i + 3;
  while (j < words.length && const {'de', 'es', 'a'}.contains(words[j])) {
    j++;
  }
  return j;
}

// ------------------------------------------------------------------ precios

/// Cómo se dijo a qué unidad corresponde el precio.
enum _PerUnit {
  /// No se dijo.
  none,

  /// «el litro», «la unidad»… con artículo o «por»/«cada»: forma clara.
  clean,

  /// «cada uno»: precio por unidad, sin decir cuál.
  eachOne,

  /// «de litro», «bolivianas litro»: se nombra la unidad, pero no es una
  /// forma clara de precio unitario (puede ser «un bidón de litro», o una
  /// «a»/«el» que se perdió). Nunca da el precio por bueno.
  unclear,
}

/// Una cláusula de precio oída: «a ciento veinte bolivianos el litro».
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
  });

  final List<String> words;

  /// Una sola palabra desconocida entre la cifra y «el/por/cada» + unidad,
  /// sin moneda («a 120 volviendo el litro», POCO 2026-11-09). No se
  /// sustituye por ninguna moneda: el precio queda por elegir y la moneda
  /// pendiente.
  final String? unknownBeforeUnit;

  /// Primera palabra de lo oído que se muestra: la cifra, o la palabra
  /// extraña que la precedía.
  final int heardFrom;

  /// Primera palabra después de la cláusula.
  final int end;

  /// Se dijo con «a», «al», «por» o «precio» antes de la cifra.
  final bool connector;
  final SpokenNumber number;
  final int? currencyIndex;
  final CatalogUnit? perUnit;
  final _PerUnit form;
  final bool total;

  /// Palabra que no es de ningún producto justo antes de la cifra, sin
  /// conector («haciendo veinte…»): señal de que el reconocedor entendió mal.
  final String? stray;

  String get heard => words.sublist(heardFrom, end).join(' ');

  String? get currencyHeard =>
      currencyIndex == null ? null : words[currencyIndex!];

  /// Sólo una moneda dicha en su forma canónica.
  CurrencyCode? get currency =>
      currencyHeard == null ? null : currencyWord(currencyHeard!);

  bool get currencyVariant => currencyHeard != null && currency == null;

  bool get perUnitSaid => form == _PerUnit.clean || form == _PerUnit.eachOne;

  /// Sin conector, la cláusula sólo vale para revisar si está completa y
  /// limpia: cifra + moneda canónica + «el/por/cada» + unidad, sin palabra
  /// extraña delante.
  bool get cleanWithoutConnector =>
      currency != null && form == _PerUnit.clean && stray == null;
}

/// Lee la cláusula de precio que empieza en [at]: con conector («a …», «al
/// …», «por …», «a un precio de …», «precio de …», «el precio es …») o sin
/// él, si en [at] hay una cifra seguida de moneda.
///
/// [loose]: la cláusula va sola, sin producto delante; entonces sólo cuenta
/// si trae moneda o una unidad clara («el litro»).
_PriceClause? _readClause(
  List<String> words,
  int at, {
  bool loose = false,
  String? stray,
  int? heardFrom,
}) {
  var k = at;
  var connector = false;
  if (k < words.length && _priceConnectors.contains(words[k])) {
    connector = true;
    k++;
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
  // «a cinco litros»: una cantidad, no un precio.
  if (k < words.length && unitWord(words[k]) != null) return null;
  int? currencyIndex;
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
  if (currencyIndex == null &&
      connector &&
      k + 2 < words.length &&
      _unknownPriceWord(words[k]) &&
      const {'el', 'la', 'por', 'cada'}.contains(words[k + 1]) &&
      unitWord(words[k + 2]) != null) {
    // «a 120 volviendo el litro»: la unidad del precio se dijo, pero entre
    // ella y la cifra hay una palabra que no es moneda. No se adivina cuál
    // era: se pregunta.
    unknownBeforeUnit = words[k];
    perUnit = unitWord(words[k + 2])!.family;
    form = _PerUnit.unclear;
    k += 3;
  } else if (k + 2 < words.length &&
      words[k] == 'por' &&
      const {'cada', 'el', 'la'}.contains(words[k + 1]) &&
      unitWord(words[k + 2]) != null) {
    // «por cada litro», «por el kilo»: tan claros como «el litro».
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
  if (loose && currencyIndex == null && form != _PerUnit.clean) return null;
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
  );
}

/// ¿Puede [w] ser una palabra que no se entendió entre la cifra y la unidad
/// del precio? No si es una cifra, unidad, moneda o palabra de enlace.
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

/// Precio y moneda de una cláusula (la moneda, `null` si no se da por
/// buena).
///
/// Frontera (POCO 2026-11-08):
///
/// - **Con conector** se mantiene lo de siempre: resuelto si se dijo la
///   unidad («el litro»), ambiguo «¿por litro o kilo?» si no, y no válido si
///   se dijo un total. Si la moneda llegó deformada («bolivianas») la cifra
///   tras la «a» sigue siendo legible, pero queda **por revisar** y la moneda
///   sin elegir.
/// - **Sin conector** la cifra no es fiable: la «a» perdida puede haberse
///   comido parte del número («a ciento» → «haciendo»). Nunca queda resuelta.
///   Si la cláusula está completa y limpia queda **por revisar** con el valor
///   a la vista; si no (moneda deformada, falta «el» antes de la unidad, «de
///   litro», sin unidad, palabra extraña delante), queda **no válida, sin
///   valor**, con lo oído y pidiendo que se diga de nuevo o se escriba.
(DraftField<SpokenPrice>, DraftField<CurrencyCode>?) _priceFields(
  _PriceClause c,
) {
  final heard = c.heard;
  DraftField<CurrencyCode>? currency(bool trusted) =>
      trusted && c.currency != null
      ? DraftField.resolved(
          c.currency!,
          origin: FieldOrigin.voice,
          heard: c.currencyHeard,
        )
      : null;
  if (!c.number.isValid) {
    return (
      DraftField.invalid(message: c.number.invalidMessage!, heard: heard),
      currency(c.connector),
    );
  }
  if (c.total) {
    // Se dijo un importe total («seiscientos bolivianos en total»): la
    // compra se registra con precio por unidad. No se divide por su cuenta:
    // la persona elige «Total de la línea» y entonces se reparte entre la
    // cantidad, si da centavos exactos.
    if (c.number.thousandths % 10 != 0 || c.number.thousandths <= 0) {
      return (
        DraftField.invalid(
          message: 'El importe debe ser mayor a cero y en centavos enteros.',
          heard: heard,
        ),
        currency(c.connector),
      );
    }
    return (
      DraftField.ambiguous(
        candidates: const [],
        heard: heard,
        value: SpokenPrice(c.number.thousandths ~/ 10, total: true),
        message: totalSaidMessage,
      ),
      currency(c.connector),
    );
  }
  if (!c.connector && !c.cleanWithoutConnector) {
    return (
      DraftField.invalid(
        message:
            'Se oyó «$heard», pero el precio no se entendió bien. Dígalo de '
            'nuevo («a … bolivianos el litro») o escríbalo.',
        heard: heard,
      ),
      null,
    );
  }
  if (c.number.thousandths % 10 != 0 || c.number.thousandths <= 0) {
    return (
      DraftField.invalid(
        message: 'El precio debe ser mayor a cero y en centavos enteros.',
        heard: heard,
      ),
      currency(c.connector),
    );
  }
  final value = SpokenPrice(
    c.number.thousandths ~/ 10,
    perUnit: c.form == _PerUnit.clean ? c.perUnit : null,
  );
  if (!c.connector) {
    return (
      DraftField.toReview(
        value,
        message:
            'Se entendió «$heard» sin «a» antes de la cifra: confirme el '
            'precio o corríjalo.',
        heard: heard,
      ),
      currency(true),
    );
  }
  if (c.unknownBeforeUnit != null) {
    final unit = c.perUnit == CatalogUnit.kilogram ? 'kg' : 'L';
    return (
      DraftField.ambiguous(
        candidates: const [],
        heard: heard,
        value: value,
        message: unknownWordBeforeUnitMessage(
          c.unknownBeforeUnit!,
          value.minorPerUnit,
          unit,
        ),
      ),
      currency(true),
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
      currency(true),
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
    currency(true),
  );
}

// ------------------------------------------------------------ precio aparte

/// Pone un precio dicho aparte en **la** línea que puede recibirlo, o dice
/// por qué no. Nunca se elige por defecto la última línea.
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
  // Sin conector, una palabra extraña delante o la moneda deformada dicen
  // que la transcripción falló: ni siquiera se busca la línea.
  if (!c.connector && (c.stray != null || c.currencyVariant)) {
    return (draft, none, why(UnplacedPriceReason.unclear));
  }
  // «cincuenta bolivianos de litro» o sin unidad: no se sabe si es por
  // litro, por kilo o un total. Conservador: no se aplica.
  if (c.form != _PerUnit.clean || c.perUnit == null) {
    return (draft, none, why(UnplacedPriceReason.unitNotSaid));
  }
  if (!c.connector && !c.cleanWithoutConnector) {
    return (draft, none, why(UnplacedPriceReason.unclear));
  }
  // Líneas que podrían recibirlo: precio sin resolver y no puesto a mano.
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

// ------------------------------------------------------------------ líneas

final class _HeardLine {
  _HeardLine(this.productHeard, {this.explicitNew = false, this.open = false});
  final String productHeard;

  /// «otros dos litros de …»: se pidió una línea nueva.
  final bool explicitNew;

  /// Cantidad sin producto que termina en «de» («tres litros de»): el
  /// producto viene en el tramo siguiente; no completa otra línea.
  final bool open;
  DraftField<SpokenQuantity>? quantity;
  DraftField<SpokenPrice>? price;
  DraftField<CurrencyCode>? currency;
}

final class _Heard {
  final lines = <_HeardLine>[];

  /// Cláusulas de precio que no siguen a ningún producto.
  final loose = <_PriceClause>[];

  /// Se dijo alguna cantidad, aunque no formara línea.
  var sawMeasure = false;
}

/// «otro», «otros dos litros…»: pide una línea nueva aunque el producto ya
/// esté en el borrador.
const _another = {'otro', 'otra', 'otros', 'otras'};

/// Precio suelto que empieza en [i], o `null`.
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

/// Encuentra `cantidad unidad de producto [a precio [moneda] [el litro]]` y
/// los precios sueltos.
_Heard _scan(List<String> words, List<CatalogEntry> products) {
  final out = _Heard();
  var i = 0;
  while (i < words.length) {
    // La cifra del tipo de cambio la lee [_exchangeRate]; no es un precio.
    if (_exchangeRateAt(words, i)) {
      final k = _exchangeRateNumber(words, i);
      final n = readNumberAt(words, k);
      i = n != null && n.end > k ? n.end : k;
      continue;
    }
    // «cincuenta litros», «un litro y medio», «litro y medio» (POCO §2.1).
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
      // «… Bellator y cincuenta litros de …» empieza otra línea, salvo que
      // lo que sigue sea parte del nombre: se decide por la unidad.
      if (words[j] == 'y' && readMeasureAt(words, j + 1) != null) break;
      // Una cifra seguida de moneda empieza el precio, aunque no se haya
      // oído la «a» (POCO 2026-11-08). Una cifra sin moneda es del nombre.
      if (_numberThenCurrency(words, j)) break;
      j++;
    }
    var nameEnd = j;

    // Precio.
    _PriceClause? clause;
    final pause = j < words.length && words[j] == ',' ? j + 1 : j;
    if (pause < words.length &&
        (_priceConnectors.contains(words[pause]) || words[pause] == 'precio')) {
      if (pause == j && words[j] == 'precio') {
        // «… Bellator con el precio de …»: el artículo no es del nombre.
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
        // Pegada al nombre: lo que une se quita sin sospechar; una palabra
        // que no es de ningún producto del catálogo, justo antes de la
        // cifra, se separa del nombre y marca el precio como mal oído. Sólo
        // si el nombre conserva al menos una palabra.
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

    // Sin producto y al final del tramo: el producto puede llegar en el
    // siguiente, tras una pausa (POCO §2.2). En medio del tramo, no.
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
      // Como antes: una cantidad que no vale muestra sólo el número oído.
      invalidHeard: m.numberHeard.isEmpty ? m.heard : m.numberHeard,
    );
    if (clause != null) {
      final (price, currency) = _priceFields(clause);
      line.price = price;
      line.currency = currency;
      j = clause.end;
    }
    out.lines.add(line);
    i = j > i ? j : i + 1;
  }
  return out;
}
