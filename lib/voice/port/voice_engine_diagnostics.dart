/// Diagnóstico de la selección entre Vosk y la revisión (F09, POCO
/// 2026-11-09).
///
/// Dos piezas separadas:
///
/// * [phraseDiagnosticLine]: una línea **sólo con códigos y números** por
///   frase —duración y nivel del audio, cómo se cerró, qué pasó con la
///   revisión, qué motor se eligió, por qué regla y qué tipo de diferencia
///   hubo—. Va al registro de la app. Nunca lleva texto, cifras dictadas,
///   nombres ni huellas del contenido.
/// * [VoiceProposalsInspector]: lo que propuso cada motor, **con texto**,
///   sólo en la compilación de diagnóstico ([voiceDiagnosticsBuild]) y sólo
///   en memoria, para que la persona que dicta lo revise en pantalla. No va
///   al registro, ni a archivos, ni a la evidencia; se borra al cerrar la
///   vista, al descartar o registrar el borrador y al salir de la pantalla.
library;

import 'package:flutter/foundation.dart';

import 'review_discrepancy.dart';
import 'review_selection.dart';

/// Compilación de diagnóstico: `--dart-define=AGRO_VOICE_DIAG=true`. En
/// cualquier otra compilación el inspector no guarda nada y la vista no
/// existe.
const voiceDiagnosticsBuild = bool.fromEnvironment('AGRO_VOICE_DIAG');

/// Diagnóstico activo: la compilación de diagnóstico o, sólo en pruebas, la
/// habilitación explícita de [VoiceExperiment.debugAllowOutsideDiagnostics].
bool get voiceDiagnosticsActive =>
    voiceDiagnosticsBuild ||
    VoiceExperiment.instance.debugAllowOutsideDiagnostics;

/// Línea de diagnóstico de una frase. [info] es lo que mandó el lado nativo
/// (`phraseInfo`): sólo números y códigos. Las claves desconocidas no se
/// copian, para que nada más pueda colarse.
String phraseDiagnosticLine({
  required int turn,
  required int? seq,
  required Map<Object?, Object?> info,
  required Object? reviewMs,
  required ReviewVerdict verdict,
  required bool revised,
  required List<FactDiscrepancy> discrepancies,
  bool late = false,
}) {
  String n(String key, [String unit = '']) {
    final v = info[key];
    return v is num || v is bool ? '$v$unit' : '-';
  }

  String code(String key) {
    final v = info[key];
    return v is String && RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(v) ? v : '-';
  }

  final diffs = discrepancies.isEmpty
      ? 'ninguna'
      : discrepancies.map((d) => d.code).join(',');
  final took = reviewMs is num ? '${reviewMs}ms' : '-';
  return 'voz diag: turno=$turn frase=${seq ?? '-'} '
      'audio=${n('audioMs', 'ms')} cierre=${code('closedBy')} '
      'nivelTotal=${n('rmsDbfs', 'dBFS')} '
      'nivelHabla=${n('speechRmsDbfs', 'dBFS')} '
      'nivelSilencio=${n('silenceRmsDbfs', 'dBFS')} '
      'habla=${n('speechMs', 'ms')} metodo=${code('levelMethod')} '
      'pico=${n('peakDbfs', 'dBFS')} '
      'suelo=${n('floorDbfs', 'dBFS')} max=${n('loudestDbfs', 'dBFS')} '
      'sat=${n('clipPermille', 'permil')} voz=${n('voiceDetected')} '
      'silencioInicial=${n('leadingQuietMs', 'ms')} '
      'silencioFinal=${n('trailingQuietMs', 'ms')} '
      'descartado=${n('droppedMs', 'ms')} '
      'turnoCapturado=${n('turnCapturedMs', 'ms')} '
      'audioRevision=${n('reviewAudioMs', 'ms')} '
      'entrega=${n('closeToDeliverMs', 'ms')} '
      'revision=${code('reviewOutcome')} carga=${n('loadMs', 'ms')} '
      'cola=${n('queuedMs', 'ms')} inferencia=$took '
      'elegido=${late ? 'vosk(tardio)' : (revised ? 'revision' : 'vosk')} '
      'motivo=${late ? 'timedOut' : verdict.name} diferencias=$diffs';
}

/// Lo que propuso cada motor para una frase. Sólo vive en memoria.
@immutable
final class EngineProposal {
  const EngineProposal({
    required this.turn,
    required this.seq,
    required this.vosk,
    required this.review,
    required this.reviewOutcome,
    required this.verdict,
    required this.revised,
    required this.discrepancies,
    this.late = false,
    this.alternatives = const [],
    this.policyBUsedReview,
  });

  /// La misma propuesta, entregada con la política B.
  EngineProposal withPolicyB({required bool usedReview}) => EngineProposal(
    turn: turn,
    seq: seq,
    vosk: vosk,
    review: review,
    reviewOutcome: reviewOutcome,
    verdict: verdict,
    revised: revised,
    discrepancies: discrepancies,
    late: late,
    alternatives: alternatives,
    policyBUsedReview: usedReview,
  );

  /// La misma propuesta con una transcripción alternativa más.
  EngineProposal withAlternative(ReviewAlternative alternative) =>
      EngineProposal(
        turn: turn,
        seq: seq,
        vosk: vosk,
        review: review,
        reviewOutcome: reviewOutcome,
        verdict: verdict,
        revised: revised,
        discrepancies: discrepancies,
        late: late,
        alternatives: [...alternatives, alternative],
        policyBUsedReview: policyBUsedReview,
      );

  final int turn;
  final int? seq;
  final String vosk;

  /// Texto de la revisión, o `null` si no lo hubo.
  final String? review;

  /// Código del lado nativo (`ok`, `aborted`, `off`, `queue-full`…).
  final String reviewOutcome;
  final ReviewVerdict verdict;

  /// Se entregó el texto de la revisión.
  final bool revised;
  final List<FactDiscrepancy> discrepancies;

  /// La revisión llegó después del tope: se entregó Vosk.
  final bool late;

  /// Sólo diagnóstico: otras transcripciones de Whisper del mismo audio con
  /// otra pista. No llegan al formulario.
  final List<ReviewAlternative> alternatives;

  /// Con la política B activa: si se entregó la revisión (`true`) o Vosk
  /// (`false`). `null`: se entregó con la regla A.
  final bool? policyBUsedReview;
}

/// Otra transcripción de Whisper del mismo audio de la frase, con otra pista
/// (comparación de contextos, sólo diagnóstico).
@immutable
final class ReviewAlternative {
  const ReviewAlternative({
    required this.label,
    required this.text,
    required this.ms,
    required this.outcome,
    required this.discrepancies,
  });

  /// Qué pista se usó (`sin-pista`, `dominio`…).
  final String label;
  final String? text;
  final int ms;

  /// `ok`, `aborted`, `cancelled` o `error`.
  final String outcome;

  /// Diferencias de cifras frente a Vosk.
  final List<FactDiscrepancy> discrepancies;
}

/// Experimento de diagnóstico activo. Sólo tiene efecto en la compilación de
/// diagnóstico, sólo vive en memoria y vuelve a apagado al salir de la
/// pantalla.
final class VoiceExperiment {
  VoiceExperiment._();

  static final VoiceExperiment instance = VoiceExperiment._();

  /// Volver a transcribir cada frase con otras pistas, sobre el mismo audio
  /// en memoria, después de entregarla.
  bool compareContexts = false;

  /// Política experimental B: si la revisión es válida, se entrega su texto
  /// entero y sólo los campos afectados quedan por revisar. Apagada, la regla
  /// A de siempre. Sólo en la compilación de diagnóstico.
  bool policyB = false;

  bool get policyBActive =>
      (voiceDiagnosticsBuild || debugAllowOutsideDiagnostics) && policyB;

  /// Sólo pruebas: permite la política B fuera de la compilación de
  /// diagnóstico.
  @visibleForTesting
  bool debugAllowOutsideDiagnostics = false;

  /// Pistas alternativas por etiqueta (lista de nombres o términos; vacía =
  /// sin pista). La pista principal sigue siendo la del catálogo.
  Map<String, List<String>> comparisonHints = const {};

  /// Lo que se manda al motor al abrir un turno: vacío salvo en la
  /// compilación de diagnóstico con la comparación encendida.
  Map<String, List<String>> get activeComparisons =>
      voiceDiagnosticsBuild && compareContexts ? comparisonHints : const {};

  /// Experimento F09 (2026-11-09): **compra por voz con un solo transcriptor
  /// por turno**. Vosk no segmenta ni decide; al terminar, el modelo de
  /// revisión transcribe todo el audio del turno de una vez. Se elige antes de
  /// abrir «Compra por voz»; aplicación y planificación no lo usan. [reset]
  /// no lo toca: es una elección deliberada para la sesión de la app (se
  /// pierde al cerrarla; nunca se guarda en disco).
  bool singleTranscriberTurn = false;

  bool get singleTranscriberTurnActive =>
      (voiceDiagnosticsBuild || debugAllowOutsideDiagnostics) &&
      singleTranscriberTurn;

  /// Variante del modelo de revisión del próximo turno entero (`base` o
  /// `small`). Un solo modelo por turno; nunca se combinan resultados.
  String turnVariant = singleTranscriberVariants.first;

  /// Variantes que se pueden elegir (las que empaqueta
  /// `fetch_voice_models.sh both`).
  static const singleTranscriberVariants = ['base', 'small'];

  /// Métricas de los turnos enteros de esta sesión de la app: sólo números y
  /// códigos, nunca texto. En memoria, con tope; se borran a mano o al cerrar.
  final List<SingleTranscriberTurnMetric> turnMetrics = [];

  static const maxTurnMetrics = 50;

  void noteTurn(SingleTranscriberTurnMetric metric) {
    turnMetrics.add(metric);
    while (turnMetrics.length > maxTurnMetrics) {
      turnMetrics.removeAt(0);
    }
  }

  void clearTurnMetrics() => turnMetrics.clear();

  void reset() {
    compareContexts = false;
    policyB = false;
    debugAllowOutsideDiagnostics = false;
    comparisonHints = const {};
  }
}

/// Métrica de un turno entero (experimento de un solo transcriptor): qué
/// modelo corrió, cómo terminó y cuánto tardó. Sin texto ni audio.
final class SingleTranscriberTurnMetric {
  const SingleTranscriberTurnMetric({
    required this.turn,
    required this.variant,
    required this.model,
    required this.outcome,
    required this.hadText,
    required this.audioMs,
    required this.speechMs,
    required this.speechDbfs,
    required this.loadMs,
    required this.inferenceMs,
    required this.closedBy,
  });

  final int turn;

  /// `base`, `small` o `-` si el motor no la informó.
  final String variant;

  /// Nombre del modelo que realmente cargó el motor (`whisper-small-q5_1`…).
  final String model;

  /// `ok`, `aborted`, `error`, `unavailable`.
  final String outcome;

  /// Hubo texto (no vacío). No dice si fue correcto.
  final bool hadText;
  final int audioMs;
  final int speechMs;
  final int? speechDbfs;
  final int loadMs;
  final int inferenceMs;

  /// `stoppedByUser`, `maxDuration`, `error`.
  final String closedBy;

  /// Línea de registro con códigos y números; ningún dato dictado.
  String get logLine =>
      'voz turno: turno=$turn variante=${_safe(variant)} modelo=${_safe(model)} '
      'resultado=${_safe(outcome)} texto=${hadText ? 'si' : 'no'} '
      'audio=${audioMs}ms habla=${speechMs}ms '
      'nivelHabla=${speechDbfs == null ? '-' : '${speechDbfs}dBFS'} '
      'carga=${loadMs}ms inferencia=${inferenceMs}ms cierre=${_safe(closedBy)}';

  static String _safe(String value) =>
      RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(value) ? value : '-';
}

/// Línea de diagnóstico de una transcripción alternativa: sólo códigos.
String comparisonDiagnosticLine({
  required int turn,
  required int? seq,
  required String label,
  required int ms,
  required String outcome,
  required List<FactDiscrepancy> discrepancies,
}) {
  final safeLabel = RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(label) ? label : '-';
  final safeOutcome = RegExp(r'^[a-zA-Z-]+$').hasMatch(outcome) ? outcome : '-';
  final diffs = discrepancies.isEmpty
      ? 'ninguna'
      : discrepancies.map((d) => d.code).join(',');
  return 'voz diag comparar: turno=$turn frase=${seq ?? '-'} '
      'pista=$safeLabel resultado=$safeOutcome inferencia=${ms}ms '
      'diferenciasConVosk=$diffs';
}

/// Propuestas de los motores, en memoria, para la vista de diagnóstico.
///
/// Fuera de la compilación de diagnóstico [add] no guarda nada.
final class VoiceProposalsInspector extends ChangeNotifier {
  VoiceProposalsInspector._();

  static final VoiceProposalsInspector instance = VoiceProposalsInspector._();

  /// Tope: las frases más viejas salen primero.
  static const maxItems = 20;

  final List<EngineProposal> _items = <EngineProposal>[];

  List<EngineProposal> get items => List.unmodifiable(_items);

  void add(EngineProposal proposal) {
    if (!voiceDiagnosticsBuild) return;
    _items.add(proposal);
    while (_items.length > maxItems) {
      _items.removeAt(0);
    }
    notifyListeners();
  }

  /// Añade una transcripción alternativa a la propuesta de esa frase.
  void attach(int turn, int? seq, ReviewAlternative alternative) {
    final i = _items.indexWhere((p) => p.turn == turn && p.seq == seq);
    if (i < 0) return;
    _items[i] = _items[i].withAlternative(alternative);
    notifyListeners();
  }

  /// Anota qué entregó la política B para esa frase.
  void notePolicyB(int turn, int? seq, {required bool usedReview}) {
    final i = _items.indexWhere((p) => p.turn == turn && p.seq == seq);
    if (i < 0) return;
    _items[i] = _items[i].withPolicyB(usedReview: usedReview);
    notifyListeners();
  }

  /// Borra todo lo guardado.
  void clear() {
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
  }

  /// Sólo para pruebas: guarda aunque no sea la compilación de diagnóstico.
  @visibleForTesting
  void addForTest(EngineProposal proposal) {
    _items.add(proposal);
    notifyListeners();
  }
}
