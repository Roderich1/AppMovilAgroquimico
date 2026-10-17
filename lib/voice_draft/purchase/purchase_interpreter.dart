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
/// - el proveedor: «el proveedor es Agro Norte»;
/// - la persona: «todo para José» o «todo queda asignado al administrador»;
/// - el tipo de cambio: «tipo de cambio seis coma noventa y seis».
///
/// Volver a nombrar un producto ya presente **corrige esa línea** sólo en los
/// campos que se dicen. Nada de lo dictado sobrescribe un campo editado a mano.
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
  });

  final VoicePurchaseDraft draft;
  final VoicePatchOutcome outcome;

  /// En inventario propio la compra es del titular, sin elegir persona (como
  /// en el formulario): una persona dictada se ignora y se informa.
  final String? ignoredRecipient;

  /// Si el dictado parece otra operación (aplicación, plan, pago o
  /// consulta), no se aplicó nada y esto lo dice.
  final VoiceIntent? otherIntent;
}

const _stop = {
  ',',
  'a',
  'al',
  'por',
  'precio',
  'proveedor',
  'proveedora',
  'todo',
  'tipo',
  'en',
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

  final supplier = _nameAfter(words, const {'proveedor', 'proveedora'});
  if (supplier != null) {
    final (field, o) = mergeField(
      draft.supplier,
      entryField(resolveName(supplier, catalog.suppliers), 'proveedor'),
    );
    draft = draft.copyWith(supplier: field);
    outcome += o;
  }

  final recipient = _recipient(words);
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

  for (final line in _lines(words)) {
    final product = entryField(
      resolveName(line.productHeard, catalog.products),
      'producto',
    );
    final existing = product.isResolved
        ? draft.lines.where((l) => l.product.value?.id == product.value!.id)
        : const <VoicePurchaseLine>[];
    if (existing.isNotEmpty) {
      final target = existing.first;
      var updated = target;
      var o = const VoicePatchOutcome();
      final (q, oq) = mergeField(updated.quantity, line.quantity);
      final (p, op) = mergeField(updated.price, line.price);
      final (c, oc) = mergeField(updated.currency, line.currency);
      updated = updated.copyWith(quantity: q, price: p, currency: c);
      o = oq + op + oc;
      draft = draft.updateLine(target.key, (_) => updated);
      outcome += o;
    } else {
      final added = VoicePurchaseLine(
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
      draft = draft.copyWith(
        lines: [...draft.lines, added],
        nextLineKey: draft.nextLineKey + 1,
      );
      outcome += const VoicePatchOutcome(applied: 1);
    }
  }

  return PurchaseInterpretation(
    draft: draft,
    outcome: outcome,
    ignoredRecipient: ignoredRecipient,
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

/// «todo para José», «todo queda asignado al administrador».
String? _recipient(List<String> words) {
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

String _takeName(List<String> words, int from) {
  final out = <String>[];
  for (var j = from; j < words.length; j++) {
    final w = words[j];
    if (w == ',' || w == 'y' || w == 'todo' || w == 'proveedor') break;
    out.add(w);
  }
  return out.join(' ');
}

DraftField<int>? _exchangeRate(List<String> words) {
  for (var i = 0; i + 2 < words.length; i++) {
    if (words[i] != 'tipo' ||
        words[i + 1] != 'de' ||
        words[i + 2] != 'cambio') {
      continue;
    }
    var j = i + 3;
    while (j < words.length && const {'de', 'es', 'a'}.contains(words[j])) {
      j++;
    }
    final n = readNumberAt(words, j);
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

final class _HeardLine {
  _HeardLine(this.productHeard);
  final String productHeard;
  DraftField<SpokenQuantity>? quantity;
  DraftField<SpokenPrice>? price;
  DraftField<CurrencyCode>? currency;
}

/// Encuentra `cantidad unidad de producto [a precio [moneda] [el litro]]`.
List<_HeardLine> _lines(List<String> words) {
  final out = <_HeardLine>[];
  var i = 0;
  while (i < words.length) {
    final n = readNumberAt(words, i);
    if (n == null || n.end >= words.length) {
      i++;
      continue;
    }
    final unit = unitWord(words[n.end]);
    if (unit == null) {
      i = n.end;
      continue;
    }
    var j = n.end + 1;
    if (j < words.length && (words[j] == 'de' || words[j] == 'del')) j++;
    final productWords = <String>[];
    while (j < words.length && !_stop.contains(words[j])) {
      if (words[j] == 'y' &&
          j + 1 < words.length &&
          isNumberWord(words[j + 1])) {
        // «… Bellator y cincuenta litros de …» empieza otra línea, salvo que
        // lo que sigue sea parte del nombre: se decide por la unidad.
        final next = readNumberAt(words, j + 1);
        if (next != null &&
            next.end < words.length &&
            unitWord(words[next.end]) != null) {
          break;
        }
      }
      productWords.add(words[j]);
      j++;
    }
    if (productWords.isEmpty) {
      i = j;
      continue;
    }
    final line = _HeardLine(productWords.join(' '));
    line.quantity =
        consecutiveNumbers<SpokenQuantity>(words, n, words[n.end]) ??
        (!n.isValid
            ? DraftField.invalid(message: n.invalidMessage!, heard: n.heard)
            : n.thousandths <= 0
            ? DraftField.invalid(
                message: 'La cantidad debe ser mayor a cero.',
                heard: n.heard,
              )
            : DraftField.resolved(
                SpokenQuantity(n.thousandths, unit),
                origin: FieldOrigin.voice,
                heard: '${n.heard} ${words[n.end]}',
              ));

    // Precio.
    if (j < words.length && const {'a', 'al', 'por'}.contains(words[j])) {
      var k = j + 1;
      if (k < words.length && words[k] == 'precio') k++;
      if (k < words.length && words[k] == 'de') k++;
      final price = readNumberAt(words, k);
      if (price != null) {
        k = price.end;
        final currency = k < words.length ? currencyWord(words[k]) : null;
        if (currency != null) {
          line.currency = DraftField.resolved(
            currency,
            origin: FieldOrigin.voice,
            heard: words[k],
          );
          k++;
        }
        CatalogUnit? perUnit;
        var perUnitSaid = false;
        var total = false;
        if (k + 1 < words.length &&
            const {'el', 'la', 'por', 'cada'}.contains(words[k]) &&
            unitWord(words[k + 1]) != null) {
          perUnit = unitWord(words[k + 1])!.family;
          perUnitSaid = true;
          k += 2;
        } else if (k + 1 < words.length &&
            words[k] == 'cada' &&
            const {'uno', 'una'}.contains(words[k + 1])) {
          perUnitSaid = true;
          k += 2;
        } else if (k < words.length && words[k] == 'total' ||
            (k + 1 < words.length &&
                words[k] == 'en' &&
                words[k + 1] == 'total')) {
          total = true;
        }
        final heard = words.sublist(price.start, k).join(' ');
        if (!price.isValid) {
          line.price = DraftField.invalid(
            message: price.invalidMessage!,
            heard: heard,
          );
        } else if (total) {
          line.price = DraftField.invalid(
            message:
                'Se dijo un total. La compra se registra con precio por litro '
                'o kilo: dígalo así o escríbalo.',
            heard: heard,
          );
        } else if (price.thousandths % 10 != 0 || price.thousandths <= 0) {
          line.price = DraftField.invalid(
            message: 'El precio debe ser mayor a cero y en centavos enteros.',
            heard: heard,
          );
        } else {
          final value = SpokenPrice(price.thousandths ~/ 10, perUnit: perUnit);
          line.price = perUnitSaid
              ? DraftField.resolved(
                  value,
                  origin: FieldOrigin.voice,
                  heard: heard,
                )
              : DraftField.ambiguous(
                  candidates: const [],
                  heard: heard,
                  value: value,
                  message:
                      '¿Es el precio por litro o kilo? Confírmelo o corríjalo.',
                );
        }
        j = k;
      }
    }
    out.add(line);
    i = j > i ? j : i + 1;
  }
  return out;
}
