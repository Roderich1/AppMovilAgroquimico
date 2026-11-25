import '../core/draft_field.dart';
import '../interpretation/voice_intent.dart';
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
    this.trace = const PurchaseTrace(),
  });

  final VoicePurchaseDraft draft;
  final VoicePatchOutcome outcome;

  /// Recorrido del dictado **sin texto**: sólo cuentas y códigos, para el
  /// registro técnico de diagnóstico.
  final PurchaseTrace trace;

  /// En inventario propio la compra es del titular, sin elegir persona (como
  /// en el formulario): una persona dictada se ignora y se informa.
  final String? ignoredRecipient;

  /// Si el dictado parece otra operación (aplicación, plan, pago o
  /// consulta), no se aplicó nada y esto lo dice.
  final VoiceIntent? otherIntent;

  /// Un precio dicho aparte que **no se puso en ninguna línea**: no había una
  /// sola línea que pudiera recibirlo o el precio no estaba claro.
  final UnplacedPrice? unplacedPrice;

  /// Lo oído que no se aplicó a ninguna línea porque no estaba claro a cuál
  /// iba (o un producto fuera del catálogo dicho sin cantidad).
  final String? lineNotice;
}

/// Recorrido de un dictado por el intérprete, **sin texto ni nombres**.
final class PurchaseTrace {
  const PurchaseTrace({
    this.words = 0,
    this.intent = 'none',
    this.measures = 0,
    this.loosePrices = 0,
    this.lines = const [],
    this.mention = 'no-aplica',
    this.reason = 'ok',
  });

  final int words;
  final String intent;
  final int measures;
  final int loosePrices;
  final List<String> lines;
  final String mention;
  final String reason;

  String logLine({required int applied, required int keptManual}) =>
      'voz compra: palabras=$words intencion=$intent medidas=$measures '
      'precios-sueltos=$loosePrices lineas=[${lines.join(',')}] '
      'mencion=$mention aplicados=$applied conservados=$keptManual '
      'motivo=$reason';
}

/// Por qué un precio dicho aparte no se puso en ninguna línea.
enum UnplacedPriceReason {
  noLine,
  severalLines,
  unitMismatch,
  unitNotSaid,
  total,
  unclear,
  notAlone,
}

/// Un precio oído que no se aplicó. Sólo informa; no es un valor aceptado.
final class UnplacedPrice {
  const UnplacedPrice({
    required this.heard,
    required this.reason,
    required this.message,
  });

  final String heard;
  final UnplacedPriceReason reason;
  final String message;
}
