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
    return v is String && RegExp(r'^[a-zA-Z-]+$').hasMatch(v) ? v : '-';
  }

  final diffs = discrepancies.isEmpty
      ? 'ninguna'
      : discrepancies.map((d) => d.code).join(',');
  final took = reviewMs is num ? '${reviewMs}ms' : '-';
  return 'voz diag: turno=$turn frase=${seq ?? '-'} '
      'audio=${n('audioMs', 'ms')} cierre=${code('closedBy')} '
      'nivel=${n('rmsDbfs', 'dBFS')} pico=${n('peakDbfs', 'dBFS')} '
      'suelo=${n('floorDbfs', 'dBFS')} max=${n('loudestDbfs', 'dBFS')} '
      'sat=${n('clipPermille', 'permil')} voz=${n('voiceDetected')} '
      'silencioInicial=${n('leadingQuietMs', 'ms')} '
      'silencioFinal=${n('trailingQuietMs', 'ms')} '
      'descartado=${n('droppedMs', 'ms')} '
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
  });

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
