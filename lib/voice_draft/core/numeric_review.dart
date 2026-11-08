/// Cifras por revisar cuando los dos reconocedores oyeron valores distintos
/// (F09, hallazgos POCO 2026-11-08).
///
/// La captura entrega una sola transcripción por frase —la de Vosk cuando la
/// revisión lee otras cifras— y una marca aparte de desacuerdo numérico. Una
/// discrepancia no demuestra que Vosk tenga razón: en el POCO, una de esas
/// frases dejó un precio equivocado. Por eso lo que ese dictado puso en los
/// campos **numéricos** no se da por bueno: queda por revisar
/// ([DraftField.markForReview]) y bloquea la confirmación hasta que la persona
/// lo confirme o lo corrija.
///
/// Funciones puras: comparan el borrador de antes del dictado con el que
/// devolvió el intérprete y marcan **sólo** los campos numéricos que ese
/// dictado cambió. Lo que la persona puso o confirmó, lo propuesto (área del
/// chaco o del plan) y lo que ya no está resuelto quedan como estaban
/// (`markForReview` no los toca).
///
/// ## Qué campos
///
/// * Compra: cantidad, precio y moneda de cada línea, y el tipo de cambio.
/// * Aplicación: área tratada y cantidad real de cada línea. La dosis y lo
///   planeado de una línea de plan no se dictan: vienen del plan.
/// * Planificación: área y dosis de cada línea.
///
/// Productos, personas, proveedores, chacos, campaña y plan no son cifras y
/// no se marcan. La **moneda** sí: el lector que compara los dos
/// reconocedores también compara monedas, y un desacuerdo puede ser sólo
/// «bolivianos» frente a «dólares» con el mismo número. Si el precio de esa
/// línea quedó ambiguo (precio por litro o total), el aviso del precio no
/// habla de la moneda, y sin marcarla un cambio de moneda pasaría sin mirar.
///
/// ## Qué es «cambió»
///
/// El valor, el estado o el origen del campo son otros que antes del dictado
/// (o la línea es nueva). Un dictado que repite el mismo valor ya presente no
/// lo cambia y no lo marca: ese valor llegó antes, por otra frase.
library;

import '../application/voice_application_draft.dart';
import '../plan/voice_plan_draft.dart';
import '../purchase/voice_purchase_draft.dart';
import 'draft_field.dart';

/// Mensaje propuesto para los campos por revisar.
const numericDisagreementMessage =
    'Los dos reconocedores oyeron cifras distintas. Revise este valor y '
    'confírmelo o corríjalo.';

/// Compra: marca la cantidad, el precio y la moneda de las líneas, y el tipo
/// de cambio, que el dictado cambió entre [before] y [after].
VoicePurchaseDraft reviewPurchaseNumbers(
  VoicePurchaseDraft before,
  VoicePurchaseDraft after,
  String message,
) {
  final old = {for (final l in before.lines) l.key: l};
  return after.copyWith(
    exchangeRate: _review(before.exchangeRate, after.exchangeRate, message),
    lines: [
      for (final l in after.lines)
        l.copyWith(
          quantity: _review(old[l.key]?.quantity, l.quantity, message),
          price: _review(old[l.key]?.price, l.price, message),
          currency: _review(old[l.key]?.currency, l.currency, message),
        ),
    ],
  );
}

/// Aplicación: marca el área tratada y la cantidad real de las líneas que el
/// dictado cambió entre [before] y [after].
VoiceApplicationDraft reviewApplicationNumbers(
  VoiceApplicationDraft before,
  VoiceApplicationDraft after,
  String message,
) {
  final old = {for (final l in before.lines) l.key: l};
  return after.copyWith(
    area: _review(before.area, after.area, message),
    lines: [
      for (final l in after.lines)
        l.copyWith(
          quantity: _review(old[l.key]?.quantity, l.quantity, message),
        ),
    ],
  );
}

/// Planificación: marca el área y la dosis de las líneas que el dictado
/// cambió entre [before] y [after].
VoicePlanDraft reviewPlanNumbers(
  VoicePlanDraft before,
  VoicePlanDraft after,
  String message,
) {
  final old = {for (final l in before.lines) l.key: l};
  return after.copyWith(
    area: _review(before.area, after.area, message),
    lines: [
      for (final l in after.lines)
        l.copyWith(dose: _review(old[l.key]?.dose, l.dose, message)),
    ],
  );
}

DraftField<T> _review<T>(
  DraftField<T>? before,
  DraftField<T> after,
  String message,
) => _changed(before, after) ? after.markForReview(message) : after;

bool _changed<T>(DraftField<T>? before, DraftField<T> after) =>
    before == null ||
    before.value != after.value ||
    before.status != after.status ||
    before.origin != after.origin;
