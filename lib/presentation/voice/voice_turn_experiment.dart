/// Diagnóstico de la compra por voz en turno entero (F09): modelo del
/// próximo turno, decodificación y métricas de los turnos.
///
/// La compra usa siempre el turno entero con Whisper small y haz de 5
/// ([purchaseVoiceWholeTurn]); esta tarjeta sólo aparece en la compilación de
/// diagnóstico. Las métricas son números y códigos: nunca texto dictado ni
/// audio.
library;

import 'package:flutter/material.dart';

import '../../voice/port/voice_engine_diagnostics.dart';
import '../../voice/session/voice_session_controller.dart';
import '../../voice/session/voice_session_state.dart';
import 'voice_purchase_port.dart';

/// Tarjeta de diagnóstico en «Compra por voz»: modelo del próximo turno y
/// métricas de los turnos de esta sesión de la app. Sólo en la compilación de
/// diagnóstico ([enabled]).
class VoiceSingleTranscriberPanel extends StatefulWidget {
  const VoiceSingleTranscriberPanel({
    super.key,
    required this.session,
    this.enabled = voiceDiagnosticsBuild,
  });

  final VoiceSessionController session;
  final bool enabled;

  @override
  State<VoiceSingleTranscriberPanel> createState() =>
      _VoiceSingleTranscriberPanelState();
}

class _VoiceSingleTranscriberPanelState
    extends State<VoiceSingleTranscriberPanel> {
  @override
  Widget build(BuildContext context) {
    final experiment = VoiceExperiment.instance;
    if (!widget.enabled || !purchaseVoiceWholeTurn) {
      return const SizedBox.shrink();
    }
    final snapshot = widget.session.snapshot;
    final idle =
        !snapshot.status.microphoneMayBeOpen &&
        !snapshot.status.isTransition &&
        snapshot.status != VoiceSessionStatus.processing;
    final theme = Theme.of(context);
    final metrics = experiment.turnMetrics.reversed.take(6).toList();
    return Card(
      key: const Key('voz-experimento-panel'),
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Diagnóstico: un solo transcriptor por turno',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Hablar → Terminar → transcribir todo el turno → revisar y '
              'corregir → registrar. Un solo modelo por turno; cambie el '
              'modelo sólo con el micrófono cerrado.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text('Modelo del próximo turno', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            SegmentedButton<String>(
              key: const Key('voz-experimento-variante'),
              segments: const [
                ButtonSegment(value: 'base', label: Text('Whisper base')),
                ButtonSegment(value: 'small', label: Text('Whisper small')),
              ],
              selected: {experiment.turnVariant},
              onSelectionChanged: idle
                  ? (selected) =>
                        setState(() => experiment.turnVariant = selected.first)
                  : null,
            ),
            const SizedBox(height: 4),
            Text(
              experiment.turnDecoding == WholeTurnDecoding.greedy
                  ? 'Decodificación: voraz (temperatura 0, sin reintentos).'
                  : 'Decodificación: haz de '
                        '${experiment.turnDecoding.beamSize} (temperatura 0, '
                        'sin reintentos).',
              key: const Key('voz-experimento-decodificacion'),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    metrics.isEmpty
                        ? 'Todavía sin turnos en esta sesión.'
                        : 'Últimos turnos (sólo tiempos y códigos):',
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                if (experiment.turnMetrics.isNotEmpty)
                  TextButton(
                    key: const Key('voz-experimento-borrar-metricas'),
                    onPressed: () => setState(experiment.clearTurnMetrics),
                    child: const Text('Borrar'),
                  ),
              ],
            ),
            for (final m in metrics)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  describeTurnMetric(m),
                  key: Key('voz-experimento-turno-${m.turn}'),
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Una línea legible por turno. Sin texto dictado.
String describeTurnMetric(SingleTranscriberTurnMetric m) {
  String s(int ms) => (ms / 1000).toStringAsFixed(1).replaceAll('.', ',');
  final result = switch (m.outcome) {
    'ok' => m.hadText ? 'texto' : 'sin texto',
    'aborted' => 'tope agotado',
    'unavailable' => 'modelo no disponible',
    _ => 'error',
  };
  final close = switch (m.closedBy) {
    'maxDuration' => ' · cortado a los 30 s',
    'error' => ' · micrófono con error',
    _ => '',
  };
  return 'Turno ${m.turn} · ${m.variant} · $result · audio ${s(m.audioMs)} s '
      '(habla ${s(m.speechMs)} s) · carga ${m.loadMs} ms · '
      'transcripción ${m.inferenceMs} ms$close';
}
