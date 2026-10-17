/// Del texto dictado a un parche del borrador de aplicación (#15).
///
/// Forma que reconoce, en cualquier orden y repartida en varios dictados:
///
/// - las líneas: «apliqué dos litros de Bellator y un kilo de Expansive»;
/// - el chaco: «en el chaco Sur»; fija quién aplica (su dueño) y propone su
///   área, como el formulario;
/// - el área tratada: «en dos hectáreas».
///
/// Volver a nombrar un producto corrige su cantidad. Nada de lo dictado
/// sobrescribe un campo corregido a mano.
///
/// «Aplicar la planificación del chaco Sur» (D-F09-4) resuelve el chaco y
/// **ofrece** sus planes pendientes de la campaña activa; no elige ninguno,
/// aunque haya uno solo. El plan se elige en la pantalla ([selectPlan]).
library;

import '../catalog/voice_catalog.dart';
import '../core/draft_field.dart';
import '../interpretation/phrases.dart';
import '../interpretation/voice_intent.dart';
import '../text/normalize.dart';
import '../text/spanish_numbers.dart';
import '../text/units.dart';
import 'voice_application_draft.dart';

final class ApplicationInterpretation {
  const ApplicationInterpretation({
    required this.draft,
    required this.outcome,
    this.otherIntent,
    this.planRequested = false,
  });

  final VoiceApplicationDraft draft;
  final VoicePatchOutcome outcome;
  final VoiceIntent? otherIntent;

  /// Se pidió aplicar una planificación: se ofrecieron sus planes, sin elegir.
  final bool planRequested;
}

ApplicationInterpretation interpretApplication(
  String text,
  VoiceApplicationDraft current,
  VoiceCatalog catalog,
) {
  final words = tokenize(text);
  final intent = classifyIntent(words);
  if (intent != VoiceIntent.application && intent != VoiceIntent.none) {
    return ApplicationInterpretation(
      draft: current,
      outcome: const VoicePatchOutcome(),
      otherIntent: intent,
    );
  }
  final planRequested = words.any(
    (w) => const {
      'plan',
      'planificacion',
      'planificado',
      'planificada',
    }.contains(w),
  );

  var draft = current;
  var outcome = const VoicePatchOutcome();

  final area = findArea(words);
  if (area != null) {
    final (field, o) = mergeField(draft.area, area);
    draft = draft.copyWith(area: field);
    outcome += o;
  }

  final farm = findFarm(words);
  if (farm != null) {
    final before = draft.farm;
    final (field, o) = mergeField(
      draft.farm,
      entryField(resolveFarm(farm, catalog.farms), 'chaco'),
    );
    outcome += o;
    if (!identical(field, before)) {
      draft = selectFarm(draft.copyWith(farm: field), catalog);
    }
  }

  for (final line in _lines(words)) {
    final product = entryField(
      resolveName(line.productHeard, catalog.products),
      'producto',
    );
    final existing = product.isResolved
        ? draft.lines.where((l) => l.product.value?.id == product.value!.id)
        : const <VoiceApplicationLine>[];
    if (existing.isNotEmpty) {
      final target = existing.first;
      final (q, o) = mergeField(target.quantity, line.quantity);
      draft = draft.updateLine(target.key, (l) => l.copyWith(quantity: q));
      outcome += o;
    } else {
      draft = draft.copyWith(
        lines: [
          ...draft.lines,
          VoiceApplicationLine(
            key: draft.nextLineKey,
            product: product,
            quantity: line.quantity,
          ),
        ],
        nextLineKey: draft.nextLineKey + 1,
      );
      outcome += const VoicePatchOutcome(applied: 1);
    }
  }
  if (planRequested) draft = offerPlans(draft, catalog);
  return ApplicationInterpretation(
    draft: draft,
    outcome: outcome,
    planRequested: planRequested,
  );
}

/// Ofrece los planes pendientes del chaco elegido, **sin elegir ninguno**:
/// el campo queda ambiguo con las opciones (aunque sea una) o faltante si no
/// hay. Si ya hay un plan elegido para este chaco, no se toca.
VoiceApplicationDraft offerPlans(
  VoiceApplicationDraft draft,
  VoiceCatalog catalog,
) {
  final farm = draft.farm.isResolved ? draft.farm.value : null;
  if (farm == null) {
    return draft.copyWith(
      plan: const DraftField.missing(
        message: 'Diga o elija el chaco del plan que se aplica.',
      ),
    );
  }
  if (draft.planData != null && draft.planData!.farmId == farm.id) {
    return draft;
  }
  final options = catalog.plansFor(farm.id, draft.campaign.value?.id);
  return draft.copyWith(
    plan: options.isEmpty
        ? DraftField.missing(
            message:
                'No hay planes pendientes de la campaña activa para '
                '${farm.name}.',
          )
        : DraftField.ambiguous(
            candidates: [for (final o in options) o.entry],
            heard: 'planificación de ${farm.name}',
            message: 'Elija el plan que se aplica.',
          ),
  );
}

/// Selección **explícita** del plan (toque del usuario). Sólo acepta un plan
/// pendiente del chaco elegido; si no, no cambia nada. Las líneas pasan a ser
/// las del plan: la cantidad real se propone igual a la planeada, salvo que
/// ya se hubiera dicho o escrito para ese producto.
VoiceApplicationDraft selectPlan(
  VoiceApplicationDraft draft,
  int planId,
  VoiceCatalog catalog,
) {
  final farm = draft.farm.isResolved ? draft.farm.value : null;
  final plan = farm == null
      ? null
      : catalog
            .plansFor(farm.id, draft.campaign.value?.id)
            .where((p) => p.id == planId)
            .firstOrNull;
  if (plan == null) return draft;
  var next = draft;
  var key = next.nextLineKey;
  final lines = <VoiceApplicationLine>[];
  for (final item in plan.items) {
    final said = next.lines
        .where((l) => l.product.value?.id == item.product.id && !l.fromPlan)
        .firstOrNull;
    final unit = item.product.unit == CatalogUnit.kilogram
        ? SpokenUnit.kilogram
        : SpokenUnit.liter;
    lines.add(
      VoiceApplicationLine(
        key: said?.key ?? key++,
        product: DraftField.resolved(item.product, origin: FieldOrigin.preset),
        quantity: said != null && said.quantity.isResolved
            ? said.quantity
            : DraftField.resolved(
                SpokenAmount(item.requiredBase, unit),
                origin: FieldOrigin.preset,
              ),
        plannedBase: item.requiredBase,
        doseBasePerHa: item.doseBasePerHa,
      ),
    );
  }
  // Lo dicho que no está en el plan se conserva visible y bloquea.
  for (final l in next.lines) {
    if (plan.items.every((i) => i.product.id != l.product.value?.id)) {
      lines.add(l.copyWith(clearPlan: true));
    }
  }
  next = next.copyWith(
    plan: DraftField.resolved(plan.entry, origin: FieldOrigin.manual),
    planData: plan,
    lines: lines,
    nextLineKey: key,
  );
  if (!next.area.isManual) {
    next = next.copyWith(
      area: DraftField.resolved(plan.areaM2, origin: FieldOrigin.preset),
    );
  }
  return next;
}

/// Quitar el plan: se vuelve a una aplicación libre; las líneas se conservan
/// sin planeado ni dosis.
VoiceApplicationDraft clearPlan(VoiceApplicationDraft draft) => draft.copyWith(
  clearPlan: true,
  lines: [for (final l in draft.lines) l.copyWith(clearPlan: true)],
);

/// Tras cambiar el chaco: su dueño pasa a ser quien aplica (o nadie, si no
/// puede aplicar), el stock leído deja de valer y se propone el área del
/// chaco si nadie la dijo ni la corrigió. Lo usa también la edición manual.
VoiceApplicationDraft selectFarm(
  VoiceApplicationDraft draft,
  VoiceCatalog catalog,
) {
  final farm = draft.farm.isResolved ? draft.farm.value : null;
  final owner = farm == null ? null : catalog.farmOwners[farm.id];
  // Un plan es de un chaco: al cambiar de chaco, el plan elegido se quita
  // (y se vuelven a ofrecer los del chaco nuevo si se había pedido uno).
  if (draft.planData != null && draft.planData!.farmId != farm?.id) {
    draft = offerPlans(clearPlan(draft).copyWith(plan: draft.plan), catalog);
  }
  var next = draft.copyWith(
    person: owner,
    clearPerson: owner == null,
    clearStock: true,
  );
  final farmArea = farm?.areaM2;
  final area = next.area;
  if (farmArea != null &&
      farmArea > 0 &&
      !area.isManual &&
      !(area.isResolved && area.origin == FieldOrigin.voice)) {
    next = next.copyWith(
      area: DraftField.resolved(farmArea, origin: FieldOrigin.preset),
    );
  }
  return next;
}

final class _HeardLine {
  _HeardLine(this.productHeard, this.quantity);
  final String productHeard;
  final DraftField<SpokenAmount> quantity;
}

/// Palabras de relleno entre el producto y la cantidad en una corrección
/// («de Bellator **en realidad usamos** diez litros», EVO-018).
const _correctionFillers = {
  'en',
  'realidad',
  'verdad',
  'solo',
  'nomas',
  'al',
  'final',
  'se',
  'uso',
  'usamos',
  'use',
  'usaron',
  'usado',
  'fue',
  'fueron',
  'puse',
  'pusimos',
  'gastamos',
  'aplicamos',
  'aplique',
  'aplico',
};

/// El producto de «de Bellator en realidad usamos diez litros»: `de`
/// seguido del producto, sólo relleno hasta la cantidad y nada de una línea
/// anterior en medio. Si no, null.
String? _productBefore(List<String> words, int quantityStart, int from) {
  const stops = {',', 'y', 'a', 'por', 'con', 'chaco', 'parcela'};
  for (var k = quantityStart - 1; k >= from; k--) {
    final w = words[k];
    if (stops.contains(w)) return null;
    if (w != 'de' && w != 'del') continue;
    final product = <String>[];
    var m = k + 1;
    while (m < quantityStart &&
        !_correctionFillers.contains(words[m]) &&
        !stops.contains(words[m])) {
      product.add(words[m]);
      m++;
    }
    for (; m < quantityStart; m++) {
      if (!_correctionFillers.contains(words[m])) return null;
    }
    return product.isEmpty ? null : product.join(' ');
  }
  return null;
}

/// `cantidad unidad de producto`, o `de producto … cantidad unidad` para
/// corregir una línea (EVO-018).
List<_HeardLine> _lines(List<String> words) {
  final out = <_HeardLine>[];
  var consumed = 0;
  var i = 0;
  while (i < words.length) {
    final n = readNumberAt(words, i);
    if (n == null) {
      i++;
      continue;
    }
    final unit = n.end < words.length ? unitWord(words[n.end]) : null;
    if (unit == null) {
      i = n.end > i ? n.end : i + 1;
      continue;
    }
    // «dos litros por hectárea» es una dosis, no una cantidad aplicada.
    if (n.end + 2 < words.length &&
        words[n.end + 1] == 'por' &&
        hectareWords.contains(words[n.end + 2])) {
      i = n.end + 3;
      continue;
    }
    var j = n.end + 1;
    if (j < words.length && (words[j] == 'de' || words[j] == 'del')) j++;
    final product = <String>[];
    while (j < words.length &&
        !const {
          ',',
          'y',
          'en',
          'a',
          'al',
          'por',
          'con',
          'chaco',
          'parcela',
        }.contains(words[j]) &&
        !startsQuantity(words, j)) {
      product.add(words[j]);
      j++;
    }
    if (product.isEmpty) {
      final before = _productBefore(words, i, consumed);
      if (before != null) product.add(before);
    }
    if (product.isNotEmpty) {
      consumed = j;
      final heard = '${n.heard} ${words[n.end]}';
      out.add(
        _HeardLine(
          product.join(' '),
          consecutiveNumbers<SpokenAmount>(words, n, words[n.end]) ??
              (!n.isValid
                  ? DraftField.invalid(message: n.invalidMessage!, heard: heard)
                  : n.thousandths <= 0
                  ? DraftField.invalid(
                      message: 'La cantidad debe ser mayor a cero.',
                      heard: heard,
                    )
                  : DraftField.resolved(
                      SpokenAmount(n.thousandths, unit),
                      origin: FieldOrigin.voice,
                      heard: heard,
                    )),
        ),
      );
    }
    i = j > i ? j : i + 1;
  }
  return out;
}
