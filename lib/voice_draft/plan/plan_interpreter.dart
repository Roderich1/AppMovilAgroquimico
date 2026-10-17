/// Del texto dictado a un parche del borrador de planificación (#14).
///
/// Reglas deterministas, sin modelo ni red. Forma que reconoce, en cualquier
/// orden y repartida en varios dictados:
///
/// - el chaco: «planificar el chaco Norte»;
/// - el área: «en cinco hectáreas» (si no se dice, se propone la del chaco,
///   como en el formulario);
/// - cada producto con su dosis: «dos litros por hectárea de Bellator» o
///   «Bellator a dos litros por hectárea».
///
/// Volver a nombrar un producto corrige su dosis. Nada de lo dictado
/// sobrescribe un campo corregido a mano.
library;

import '../catalog/voice_catalog.dart';
import '../core/draft_field.dart';
import '../interpretation/phrases.dart';
import '../interpretation/voice_intent.dart';
import '../text/normalize.dart';
import '../text/spanish_numbers.dart';
import '../text/units.dart';
import 'voice_plan_draft.dart';

final class PlanInterpretation {
  const PlanInterpretation({
    required this.draft,
    required this.outcome,
    this.otherIntent,
  });

  final VoicePlanDraft draft;
  final VoicePatchOutcome outcome;
  final VoiceIntent? otherIntent;
}

const _boundary = {
  ',',
  'y',
  'con',
  'en',
  'para',
  'a',
  'al',
  'de',
  'del',
  'el',
  'la',
  'chaco',
  'parcela',
  'plan',
  'planificar',
  'planificacion',
  'quiero',
  'producto',
  'productos',
};

PlanInterpretation interpretPlan(
  String text,
  VoicePlanDraft current,
  VoiceCatalog catalog,
) {
  final words = tokenize(text);
  final intent = classifyIntent(words);
  if (intent != VoiceIntent.plan && intent != VoiceIntent.none) {
    return PlanInterpretation(
      draft: current,
      outcome: const VoicePatchOutcome(),
      otherIntent: intent,
    );
  }

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
    final resolution = resolveFarm(farm, catalog.farms);
    final (field, o) = mergeField(draft.farm, entryField(resolution, 'chaco'));
    draft = draft.copyWith(farm: field);
    outcome += o;
    draft = proposeFarmArea(draft);
  }

  for (final line in _doses(words)) {
    final product = entryField(
      resolveName(line.productHeard, catalog.products),
      'producto',
    );
    final existing = product.isResolved
        ? draft.lines.where((l) => l.product.value?.id == product.value!.id)
        : const <VoicePlanLine>[];
    if (existing.isNotEmpty) {
      final target = existing.first;
      final (dose, o) = mergeField(target.dose, line.dose);
      draft = draft.updateLine(target.key, (l) => l.copyWith(dose: dose));
      outcome += o;
    } else {
      draft = draft.copyWith(
        lines: [
          ...draft.lines,
          VoicePlanLine(
            key: draft.nextLineKey,
            product: product,
            dose: line.dose,
          ),
        ],
        nextLineKey: draft.nextLineKey + 1,
      );
      outcome += const VoicePatchOutcome(applied: 1);
    }
  }
  return PlanInterpretation(draft: draft, outcome: outcome);
}

/// Si el chaco está resuelto y el área no la dijo ni la corrigió nadie, se
/// propone la del chaco, visible, como hace el formulario.
VoicePlanDraft proposeFarmArea(VoicePlanDraft draft) {
  final farmArea = draft.farm.value?.areaM2;
  if (!draft.farm.isResolved || farmArea == null || farmArea <= 0) {
    return draft;
  }
  final area = draft.area;
  if (area.isManual || (area.isResolved && area.origin == FieldOrigin.voice)) {
    return draft;
  }
  return draft.copyWith(
    area: DraftField.resolved(farmArea, origin: FieldOrigin.preset),
  );
}

final class _HeardDose {
  _HeardDose(this.productHeard, this.dose);
  final String productHeard;
  final DraftField<SpokenDose> dose;
}

/// `cantidad unidad por hectárea [de producto]` o `producto [a] cantidad
/// unidad por hectárea`.
List<_HeardDose> _doses(List<String> words) {
  final out = <_HeardDose>[];
  var lastEnd = 0;
  var i = 0;
  while (i < words.length) {
    final n = readNumberAt(words, i);
    if (n == null) {
      i++;
      continue;
    }
    final unit = n.end < words.length ? unitWord(words[n.end]) : null;
    final perHa =
        unit != null &&
        n.end + 2 < words.length &&
        const {'por', 'x', 'cada'}.contains(words[n.end + 1]) &&
        hectareWords.contains(words[n.end + 2]);
    if (!perHa) {
      i = n.end > i ? n.end : i + 1;
      continue;
    }
    var j = n.end + 3;
    String product;
    if (j < words.length && (words[j] == 'de' || words[j] == 'del')) {
      j++;
      final after = <String>[];
      while (j < words.length &&
          !const {',', 'y', 'con', 'en', 'para'}.contains(words[j]) &&
          !startsQuantity(words, j)) {
        after.add(words[j]);
        j++;
      }
      product = after.join(' ');
    } else {
      // El producto va antes: «Bellator a dos litros por hectárea».
      final before = <String>[];
      var k = n.start - 1;
      // «Bellator a dos litros…», «con Bellator, dos litros…»: los conectores
      // entre el producto y la dosis no son parte del nombre.
      while (k >= lastEnd && const {'a', 'al', 'con', ','}.contains(words[k])) {
        k--;
      }
      while (k >= lastEnd && !_boundary.contains(words[k])) {
        before.insert(0, words[k]);
        k--;
      }
      product = before.join(' ');
    }
    final heard = '${n.heard} ${words[n.end]} por ${words[n.end + 2]}';
    final dose = !n.isValid
        ? DraftField<SpokenDose>.invalid(
            message: n.invalidMessage!,
            heard: heard,
          )
        : n.thousandths <= 0
        ? DraftField<SpokenDose>.invalid(
            message: 'La dosis debe ser mayor a cero.',
            heard: heard,
          )
        : DraftField.resolved(
            SpokenDose(n.thousandths, unit),
            origin: FieldOrigin.voice,
            heard: heard,
          );
    if (product.isNotEmpty) out.add(_HeardDose(product, dose));
    lastEnd = j;
    i = j > i ? j : i + 1;
  }
  return out;
}
