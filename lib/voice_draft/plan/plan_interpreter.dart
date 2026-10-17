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

const _hectare = {'hectarea', 'hectareas', 'ha'};
const _farmWords = {'chaco', 'parcela'};
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

  final area = _area(words);
  if (area != null) {
    final (field, o) = mergeField(draft.area, area);
    draft = draft.copyWith(area: field);
    outcome += o;
  }

  final farm = _farm(words);
  if (farm != null) {
    // «el chaco Titular» puede referirse a «Titular» o a «Chaco titular»: se
    // prueba sin y con la palabra, y sólo vale una coincidencia exacta única.
    var resolution = resolveName(farm.$2, catalog.farms);
    if (resolution.state != ResolutionState.resolved) {
      final withKeyword = resolveName('${farm.$1} ${farm.$2}', catalog.farms);
      if (withKeyword.state == ResolutionState.resolved) {
        resolution = withKeyword;
      }
    }
    final (field, o) = mergeField(draft.farm, _entryField(resolution, 'chaco'));
    draft = draft.copyWith(farm: field);
    outcome += o;
    draft = proposeFarmArea(draft);
  }

  for (final line in _doses(words)) {
    final product = _entryField(
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

DraftField<CatalogEntry> _entryField(Resolution r, String what) =>
    switch (r.state) {
      ResolutionState.resolved => DraftField.resolved(
        r.entry!,
        origin: FieldOrigin.voice,
        heard: r.heard,
      ),
      ResolutionState.ambiguous => DraftField.ambiguous(
        candidates: r.candidates,
        heard: r.heard,
        message: 'Elija el $what entre las opciones.',
      ),
      ResolutionState.missing => DraftField.missing(
        heard: r.heard,
        message:
            '«${r.heard}» no está en el catálogo. Elija uno existente; si es '
            'nuevo, créelo primero en Catálogos.',
      ),
    };

/// «el chaco Norte», «la parcela Los Limoncitos»: la palabra clave y el
/// nombre que la sigue.
(String, String)? _farm(List<String> words) {
  for (var i = 0; i < words.length; i++) {
    if (!_farmWords.contains(words[i])) continue;
    final out = <String>[];
    for (var j = i + 1; j < words.length; j++) {
      final w = words[j];
      if (const {',', 'y', 'con', 'en', 'para', 'a', 'al'}.contains(w)) break;
      if (_startsQuantity(words, j)) break;
      out.add(w);
    }
    if (out.isNotEmpty) return (words[i], out.join(' '));
  }
  return null;
}

/// «en cinco hectáreas»: un número seguido directamente de «hectáreas».
DraftField<int>? _area(List<String> words) {
  for (var i = 0; i < words.length; i++) {
    final n = readNumberAt(words, i);
    if (n == null ||
        n.end >= words.length ||
        !_hectare.contains(words[n.end])) {
      continue;
    }
    // «por hectárea» es una dosis, no un área.
    if (i > 0 && words[i - 1] == 'por') continue;
    final heard = '${n.heard} ${words[n.end]}';
    if (!n.isValid || n.thousandths <= 0) {
      return DraftField.invalid(
        message: n.invalidMessage ?? 'El área debe ser mayor a cero.',
        heard: heard,
      );
    }
    // 1 ha = 10 000 m²; las milésimas de hectárea son 10 m².
    return DraftField.resolved(
      n.thousandths * 10,
      origin: FieldOrigin.voice,
      heard: heard,
    );
  }
  return null;
}

bool _startsQuantity(List<String> words, int i) {
  final n = readNumberAt(words, i);
  return n != null &&
      n.end < words.length &&
      (unitWord(words[n.end]) != null || _hectare.contains(words[n.end]));
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
        _hectare.contains(words[n.end + 2]);
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
          !_startsQuantity(words, j)) {
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
