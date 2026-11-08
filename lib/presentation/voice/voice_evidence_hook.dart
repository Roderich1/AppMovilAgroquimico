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

  /// Tras cada `applyVoice` aceptado: el borrador resultante y el texto
  /// cerrado que lo produjo.
  void noteVoiceApplied(Object draftAfterVoice, String transcript) {
    if (_evidenceDone) return;
    _evidence.voiceApplied(draftAfterVoice, transcript: transcript);
  }

  /// Llamar en `dispose`, **antes** de liberar el controlador del borrador.
  /// Sin ningún dictado aplicado no hay evidencia que entregar.
  void finishVoiceEvidence(VoiceDraftController<dynamic, dynamic>? draft) {
    if (_evidenceDone || draft == null || !_evidence.hasVoice) return;
    _evidenceDone = true;
    final outcome = switch (draft.phase) {
      DraftPhase.confirmed => VoiceEvidenceOutcome.confirmed,
      _ when draft.error != null => VoiceEvidenceOutcome.failed,
      _ => VoiceEvidenceOutcome.discarded,
    };
    final entry = _evidence.finish(
      finalDraft: draft.draft as Object,
      outcome: outcome,
      engine: voiceEngine,
      appCommit: voiceAppCommit.isEmpty ? null : voiceAppCommit,
    );
    // El almacén nunca lanza; la pantalla ya se está cerrando.
    unawaited(_evidenceSink.record(entry));
  }
}

/// Sobrescrituras de `ProviderScope` que activan el almacén, sólo en una
/// compilación de evaluación; en otra, ninguna.
List<Override> voiceEvidenceOverrides() =>
    voiceEvidenceEnabled ? [recordVoiceEvidenceOverride] : const [];
