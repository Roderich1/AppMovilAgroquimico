/// Enganche de la evidencia de dictado (#167) en las pantallas de borrador.
///
/// - Durante el borrador sólo se **anota** en memoria lo que propuso cada
///   dictado aplicado ([noteVoiceApplied]).
/// - Al cerrarse la pantalla (registrar, cancelar, Atrás, abrir el
///   formulario manual o cambiar de pestaña: todas las salidas pasan por
///   `dispose`) se entrega **una sola** entrada al sumidero
///   ([finishVoiceEvidence]), con el resultado que dice la fase del borrador.
/// - El sumidero por defecto es nulo. Sólo una compilación con
///   `--dart-define=AGRO_VOICE_EVIDENCE=true` usa el almacén, y aun así el
///   almacén no guarda nada sin un consentimiento vigente.
/// - No hay audio en ningún punto: sólo texto ya reconocido y campos.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../../voice/session/voice_session_state.dart';
import '../../voice/voice_providers.dart';
import '../../voice_draft/core/voice_draft_controller.dart';
import '../../voice_evidence/draft_snapshot.dart';
import '../../voice_evidence/voice_evidence.dart';
import '../../voice_evidence/voice_evidence_providers.dart';

/// Compilación de evaluación: activa el almacén de evidencia y la pantalla
/// de consentimiento. Por defecto, apagado.
const voiceEvidenceEnabled = bool.fromEnvironment('AGRO_VOICE_EVIDENCE');

/// Commit de la compilación, si quien compila lo pasa
/// (`--dart-define=AGRO_APP_COMMIT=<sha>`). Vacío = desconocido.
const voiceAppCommit = String.fromEnvironment('AGRO_APP_COMMIT');

mixin VoiceEvidenceRecording<W extends ConsumerStatefulWidget>
    on ConsumerState<W> {
  final VoiceEvidenceTrace _evidence = VoiceEvidenceTrace();
  late final VoiceEvidenceSink _evidenceSink;
  bool _evidenceDone = false;

  /// Llamar en `initState`: el sumidero se lee aquí porque en `dispose` ya
  /// no se puede usar `ref`.
  void initVoiceEvidence() {
    _evidenceSink = ref.read(voiceEvidenceSinkProvider);
  }

  // Tiempos observados DESDE LA INTERFAZ (incluyen la entrega del evento a la
  // pantalla), del primer dictado del borrador:
  // - primer parcial: de «escuchando» al primer texto provisional;
  // - final: de «Detener» al último tramo aplicado al borrador después.
  final Stopwatch _clock = Stopwatch()..start();
  Duration? _listeningAt;
  int? _firstPartialMs;
  Duration? _stoppingAt;
  int? _finalMs;
  String? _model;

  /// En cada cambio de la sesión de voz (antes de interpretar).
  void observeVoiceSession(VoiceSessionSnapshot s) {
    if (_evidenceDone) return;
    final now = _clock.elapsed;
    if (s.status == VoiceSessionStatus.listening) _listeningAt ??= now;
    if (_firstPartialMs == null &&
        _listeningAt != null &&
        s.partialText.isNotEmpty) {
      _firstPartialMs = (now - _listeningAt!).inMilliseconds;
    }
    if (s.status == VoiceSessionStatus.stopping) _stoppingAt ??= now;
    final a = s.availability;
    if (a != null && a.engineName.isNotEmpty) {
      _model = [
        '${a.engineName} ${a.engineVersion}'.trim(),
        if (a.reviewModel != null) a.reviewModel!,
      ].join(' + ');
    }
  }

  /// Tras cada `applyVoice` aceptado: el borrador resultante y el texto
  /// cerrado que lo produjo. En el formulario único, [lineIds] lleva cada
  /// línea de la sombra a la línea del formulario a la que fue.
  void noteVoiceApplied(
    Object draftAfterVoice,
    String transcript, {
    Map<int, int>? lineIds,
  }) {
    if (_evidenceDone) return;
    _evidence.voiceApplied(
      draftAfterVoice,
      transcript: transcript,
      lineKeys: lineIds,
    );
    final stoppedAt = _stoppingAt;
    if (stoppedAt != null) {
      _finalMs = (_clock.elapsed - stoppedAt).inMilliseconds;
    }
  }

  /// Llamar en `dispose`, **antes** de liberar el controlador del borrador.
  /// Sin ningún dictado aplicado no hay evidencia que entregar.
  void finishVoiceEvidence(VoiceDraftController<dynamic, dynamic>? draft) {
    if (draft == null) return;
    _finishEvidence(() => draft.draft as Object, switch (draft.phase) {
      DraftPhase.confirmed => VoiceEvidenceOutcome.confirmed,
      _ when draft.error != null => VoiceEvidenceOutcome.failed,
      _ => VoiceEvidenceOutcome.discarded,
    }, fromForm: false);
  }

  /// Formulario único (F09), en `dispose` y antes de liberar los campos: el
  /// borrador final es el que arma [formDraft] con **lo que tiene el
  /// formulario** (lo registrado, si se registró, con las correcciones hechas
  /// a mano), no la sombra del último dictado (RF-41, DAT-21; 2026-11-13).
  /// Sólo se arma si hubo algún dictado aplicado. El resultado es el del
  /// guardado del formulario.
  void finishFormVoiceEvidence({
    required Object Function() formDraft,
    required VoiceEvidenceOutcome outcome,
  }) => _finishEvidence(formDraft, outcome, fromForm: true);

  void _finishEvidence(
    Object Function() finalDraft,
    VoiceEvidenceOutcome outcome, {
    required bool fromForm,
  }) {
    if (_evidenceDone || !_evidence.hasVoice) return;
    _evidenceDone = true;
    final entry = _evidence.finish(
      finalDraft: finalDraft(),
      outcome: outcome,
      fromForm: fromForm,
      engine: voiceEngine,
      model: _model,
      appCommit: voiceAppCommit.isEmpty ? null : voiceAppCommit,
      firstPartialMs: _firstPartialMs,
      finalMs: _finalMs,
    );
    // El almacén nunca lanza; la pantalla ya se está cerrando.
    unawaited(_evidenceSink.record(entry));
  }
}

/// Sobrescrituras de `ProviderScope` que activan el almacén, sólo en una
/// compilación de evaluación; en otra, ninguna.
List<Override> voiceEvidenceOverrides() =>
    voiceEvidenceEnabled ? [recordVoiceEvidenceOverride] : const [];
