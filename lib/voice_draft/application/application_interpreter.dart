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
/// sobrescribe un campo corregido a mano. «Aplicar la planificación…» no se
/// atiende aquí (decisión pendiente D-F09-4): se avisa y no se cambia nada.
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

  /// Se pidió aplicar una planificación: no se aplicó nada.
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
  if (words.any(
    (w) => const {
      'plan',
      'planificacion',
      'planificado',
      'planificada',
    }.contains(w),
  )) {
    return ApplicationInterpretation(
      draft: current,
      outcome: const VoicePatchOutcome(),
      planRequested: true,
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
  return ApplicationInterpretation(draft: draft, outcome: outcome);
}

/// Tras cambiar el chaco: su dueño pasa a ser quien aplica (o nadie, si no
/// puede aplicar), el stock leído deja de valer y se propone el área del
/// chaco si nadie la dijo ni la corrigió. Lo usa también la edición manual.
VoiceApplicationDraft selectFarm(
  VoiceApplicationDraft draft,
  VoiceCatalog catalog,
) {
  final farm = draft.farm.isResolved ? draft.farm.value : null;
  final owner = farm == null ? null : catalog.farmOwners[farm.id];
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

/// `cantidad unidad de producto`.
List<_HeardLine> _lines(List<String> words) {
  final out = <_HeardLine>[];
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
    if (product.isNotEmpty) {
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
