/// Del texto dictado a un parche del borrador de compra (EVO-010 / EVO-017).
library;

import '../../domain/models.dart';
import '../catalog/voice_catalog.dart';
import '../core/draft_field.dart';
import '../interpretation/phrases.dart';
import '../interpretation/voice_intent.dart';
import '../text/normalize.dart';
import '../text/spanish_numbers.dart';
import '../text/units.dart';
import 'purchase_interpretation_models.dart';
import 'voice_purchase_draft.dart';

export 'purchase_interpretation_models.dart';

part 'purchase_header_parser.dart';
part 'purchase_line_scanner.dart';
part 'purchase_price_parser.dart';
part 'purchase_tokenizer.dart';

PurchaseInterpretation interpretPurchase(
  String text,
  VoicePurchaseDraft current,
  VoiceCatalog catalog,
) {
  final words = _purchaseWords(text, catalog.products);
  final intent = classifyIntent(words);
  if (intent != VoiceIntent.purchase && intent != VoiceIntent.none) {
    return PurchaseInterpretation(
      draft: current,
      outcome: const VoicePatchOutcome(),
      otherIntent: intent,
      trace: PurchaseTrace(
        words: words.length,
        intent: intent.name,
        reason: 'otra-operacion',
      ),
    );
  }

  final mood = _purchaseMood(words);
  if (mood != null) {
    return PurchaseInterpretation(
      draft: current,
      outcome: const VoicePatchOutcome(),
      lineNotice: mood == _negated
          ? 'Se oyó una compra negada («no compré …»): no se añadió nada al '
                'borrador.'
          : 'Se oyó una compra por hacer («quiero comprar …», «voy a comprar '
                '…»): no se añadió nada. Dicte la compra cuando esté hecha.',
      trace: PurchaseTrace(
        words: words.length,
        intent: intent.name,
        reason: mood,
      ),
    );
  }

  var draft = current;
  var outcome = const VoicePatchOutcome();

  final waiting = draft.lines.lastOrNull;
  final name = intent == VoiceIntent.none ? bareName(words) : null;
  if (name != null && waiting != null && isAwaitingProduct(waiting.product)) {
    final (field, o) = mergeField(
      waiting.product,
      entryField(_resolveProduct(name, catalog.products), 'producto'),
    );
    return PurchaseInterpretation(
      draft: draft.updateLine(waiting.key, (l) => l.copyWith(product: field)),
      outcome: o,
      trace: PurchaseTrace(
        words: words.length,
        intent: intent.name,
        mention: 'completa-linea-en-espera',
        reason: o.applied > 0 ? 'ok' : 'sin-cambios',
      ),
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
  final added = <int>{};
  final notices = <String>[];
  final traced = <String>[];
  for (final line in heard.lines) {
    final product = line.productHeard.isEmpty
        ? awaitingProduct
        : entryField(
            _resolveProduct(line.productHeard, catalog.products),
            'producto',
          );
    final heardUnit = line.priceUnitHeard;
    final productUnit = product.value?.unit;
    if (heardUnit != null &&
        product.isResolved &&
        productUnit != null &&
        heardUnit != productUnit &&
        line.price != null) {
      line.price = DraftField.ambiguous(
        candidates: const [],
        heard: line.price!.heard ?? '',
        value: line.price!.value,
        message:
            'La unidad oída en el precio no es la del producto '
            '(${productUnit == CatalogUnit.kilogram ? 'kg' : 'L'}): escriba '
            'el precio por unidad o elija «Total de la línea».',
      );
    }
    final placed = _placeLine(draft, line, product, added);
    final match = line.productHeard.isEmpty
        ? 'sin-nombre'
        : _matchCode(product.status);
    if (placed.notice != null) {
      notices.add(placed.notice!);
      traced.add('$match/aviso');
      continue;
    }
    final target = placed.target;
    traced.add('$match/${target == null ? 'nueva' : 'existente'}');
    if (target != null) {
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

  var mentioned = false;
  var mention = 'no-aplica';
  if (heard.lines.isEmpty &&
      !heard.sawMeasure &&
      heard.loose.length <= 1 &&
      (intent == VoiceIntent.purchase || intent == VoiceIntent.none) &&
      supplier == null &&
      recipient == null &&
      fx == null) {
    final m = _productMention(draft, words, catalog);
    if (m != null) {
      mentioned = true;
      draft = m.draft;
      outcome += m.outcome;
      if (m.notice != null) notices.add(m.notice!);
      mention = m.code;
    } else {
      mention = 'descartado';
    }
  }

  UnplacedPrice? unplaced;
  if (mentioned) {
    // El precio de la frase ya se trató junto a su producto.
  } else if (heard.loose.length > 1) {
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

  final changed = outcome.applied > 0;
  return PurchaseInterpretation(
    draft: draft,
    outcome: outcome,
    ignoredRecipient: ignoredRecipient,
    unplacedPrice: unplaced,
    lineNotice: notices.isEmpty ? null : notices.join(' '),
    trace: PurchaseTrace(
      words: words.length,
      intent: intent.name,
      measures: heard.lines.length,
      loosePrices: heard.loose.length,
      lines: traced,
      mention: mention,
      reason: changed
          ? 'ok'
          : words.isEmpty
          ? 'vacio'
          : notices.isNotEmpty
          ? 'aviso'
          : unplaced != null
          ? 'precio-no-colocado'
          : heard.lines.isEmpty && !mentioned
          ? 'sin-linea'
          : 'sin-cambios',
    ),
  );
}
