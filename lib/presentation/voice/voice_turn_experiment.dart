/// Experimento F09 (2026-11-09): compra por voz con **un solo transcriptor
/// por turno** (Whisper base o small, sin Vosk).
///
/// Sólo en la compilación de diagnóstico. El interruptor vive en la entrada
/// «Registrar por voz» y se lee al abrir «Compra por voz»; aplicación y
/// planificación no cambian. Las métricas son números y códigos: nunca texto
/// dictado ni audio.
library;

import 'package:flutter/material.dart';

import '../../voice/port/voice_engine_diagnostics.dart';
import '../../voice/session/voice_session_controller.dart';
import '../../voice/session/voice_session_state.dart';

/// Interruptor del experimento, en la entrada a la voz.
class VoiceSingleTranscriberSwitch extends StatefulWidget {
  const VoiceSingleTranscriberSwitch({
    super.key,
    this.enabled = voiceDiagnosticsBuild,
  });

  final bool enabled;

  @override
  State<VoiceSingleTranscriberSwitch> createState() =>
      _VoiceSingleTranscriberSwitchState();
}

class _VoiceSingleTranscriberSwitchState
    extends State<VoiceSingleTranscriberSwitch> {
  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();
    final experiment = VoiceExperiment.instance;
    return Card(
      child: SwitchListTile(
        key: const Key('voz-experimento-turno-entero'),
        title: const Text(
          'Experimento: compra con un solo transcriptor (Whisper) por turno',
        ),
        subtitle: const Text(
          'Sólo en «Compra por voz». Vosk no segmenta ni decide: al pulsar '
          '«Terminar», Whisper transcribe todo el turno de una vez (máximo '
          '30 s). El modelo (base o small) se elige en la pantalla de compra. '
          'Aplicación y planificación no cambian. Se apaga al cerrar la app.',
        ),
        value: experiment.singleTranscriberTurn,
        onChanged: (on) =>
            setState(() => experiment.singleTranscriberTurn = on),
      ),
    );
  }
}

/// Tarjeta del experimento en «Compra por voz»: modelo del próximo turno y
/// métricas de los turnos de esta sesión de la app.
class VoiceSingleTranscriberPanel extends StatefulWidget {
  const VoiceSingleTranscriberPanel({super.key, required this.session});

  final VoiceSessionController session;

  @override
  State<VoiceSingleTranscriberPanel> createState() =>
      _VoiceSingleTranscriberPanelState();
}

class _VoiceSingleTranscriberPanelState
    extends State<VoiceSingleTranscriberPanel> {
  @override
  Widget build(BuildContext context) {
    final experiment = VoiceExperiment.instance;
    if (!experiment.singleTranscriberTurnActive) return const SizedBox.shrink();
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
              'Experimento activo: un solo transcriptor por turno',
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
