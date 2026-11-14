/// Política experimental B (F09, 2026-11-09): Vosk en vivo y Whisper como
/// propuesta final cuando termina válidamente.
///
/// **Sólo se calcula y se muestra** en la vista de diagnóstico, junto a la
/// regla actual (A, [chooseReviewedText]), que es la que sigue entregando el
/// texto al formulario. Así A se mantiene reproducible y B se puede comparar
/// sobre el mismo dictado sin cambiar nada.
///
/// Reglas de B:
///
/// * Si la salida de Whisper no es válida (no llegó, vacía, no-habla,
///   degenerada o fuera de tiempo), se usa Vosk y se dice por qué.
/// * Si es válida, se usa **el texto de Whisper entero**, sin mezclar
///   palabras de los dos.
/// * No se vuelve a Vosk por una diferencia de cifras: cada diferencia
///   relevante deja **su campo** por revisar (valor, unidad o moneda
///   distintos; cifra ilegible; dato que sólo oyó uno de los dos;
///   correspondencia ambigua). El formato equivalente no se marca.
/// * Ningún número en conflicto se acepta sin aviso.
library;

import 'review_discrepancy.dart';
import 'review_selection.dart';

/// Lo que haría B con una frase.
final class PolicyBChoice {
  const PolicyBChoice({
    required this.useReview,
    required this.reason,
    this.reviewFields = const {},
  });

  /// `true`: el texto de Whisper; `false`: el de Vosk.
  final bool useReview;

  /// Por qué, en código: `whisper-valido`, o el veredicto que lo invalida.
  final String reason;

  /// Campos que quedarían «Revisar».
  final Set<ReviewField> reviewFields;
}

/// Decide con B a partir del veredicto de la regla actual (que ya dice si la
/// salida de Whisper es válida) y de las diferencias clasificadas.
PolicyBChoice choosePolicyB({
  required ReviewVerdict verdict,
  required bool late,
  required List<FactDiscrepancy> discrepancies,
}) {
  if (late) return const PolicyBChoice(useReview: false, reason: 'timedOut');
  switch (verdict) {
    case ReviewVerdict.notRun:
    case ReviewVerdict.empty:
    case ReviewVerdict.nonSpeech:
    case ReviewVerdict.degenerate:
    case ReviewVerdict.unchecked:
    case ReviewVerdict.timedOut:
      return PolicyBChoice(useReview: false, reason: verdict.name);
    case ReviewVerdict.accepted:
    case ReviewVerdict.quantities:
    case ReviewVerdict.format:
      break;
  }
  return PolicyBChoice(
    useReview: true,
    reason: 'revision-valida',
    reviewFields: {
      for (final d in discrepancies)
        if (d.kind != DiscrepancyKind.equivalentFormat) d.field,
    },
  );
}
