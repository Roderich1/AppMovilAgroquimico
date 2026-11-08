/// Consentimiento para la evidencia de dictado de la evaluación (#167).
///
/// Sólo existe en una compilación de evaluación (`AGRO_VOICE_EVIDENCE=true`).
/// Muestra el texto, permite aceptarlo o retirarlo (retirar borra todo) y
/// borrar lo guardado sin retirar el permiso. No muestra lo dictado: la
/// lectura para la evaluación la hace el evaluador con su procedimiento.
///
/// El texto es la **propuesta** de `docs/f09/evaluacion/README.md`, pendiente
/// de aprobación del autor; la versión guardada lo dice.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../voice_evidence/voice_evidence_providers.dart';
import '../../voice_evidence/voice_evidence_store.dart';
import '../widgets/common.dart';

const voiceEvidenceConsentPath = '/voz/evidencia';

/// Identificador del texto aceptado. Cambia si cambia el texto.
const voiceEvidenceConsentTextVersion = 'F09-CONSENT-PROPUESTA-2026-11-08';

const voiceEvidenceConsentText =
    'Para evaluar la voz de Agrocuentas, ¿permite que este teléfono guarde, '
    'por cada dictado, el texto reconocido, lo que la app propuso, lo que '
    'usted corrigió y lo que confirmó? No se graba su voz. Estos datos se '
    'quedan sólo en este teléfono: no se envían al sindicato, no entran en el '
    'respaldo y se usan sólo para la evaluación. Puede retirar el permiso '
    'cuando quiera y se borrará todo lo guardado.';

class VoiceEvidenceConsentScreen extends ConsumerStatefulWidget {
  const VoiceEvidenceConsentScreen({super.key});

  @override
  ConsumerState<VoiceEvidenceConsentScreen> createState() =>
      _VoiceEvidenceConsentScreenState();
}

class _VoiceEvidenceConsentScreenState
    extends ConsumerState<VoiceEvidenceConsentScreen> {
  late final VoiceEvidenceStore _store;
  VoiceEvidenceConsent? _consent;
  int _count = 0;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _store = ref.read(voiceEvidenceStoreProvider);
    _reload();
  }

  Future<void> _reload() async {
    final consent = await _store.consent();
    final count = await _store.count();
    if (!mounted) return;
    setState(() {
      _consent = consent;
      _count = count;
      _loading = false;
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
      await _reload();
    }
  }

  Future<void> _grant() => _run(
    () => _store.grantConsent(
      consentTextVersion: voiceEvidenceConsentTextVersion,
    ),
  );

  Future<void> _revoke() async {
    final ok = await confirmDestructiveAction(
      context,
      title: '¿Retirar el permiso?',
      detail: 'Se borrará todo lo guardado para la evaluación.',
      confirmLabel: 'Retirar y borrar',
    );
    if (ok) await _run(() => _store.revokeConsent());
  }

  Future<void> _eraseAll() async {
    final ok = await confirmDestructiveAction(
      context,
      title: '¿Borrar lo guardado?',
      detail: 'El permiso sigue vigente para los próximos dictados.',
      confirmLabel: 'Borrar todo',
    );
    if (ok) await _run(() => _store.eraseAll());
  }

  @override
  Widget build(BuildContext context) {
    final consent = _consent;
    return PageFrame(
      title: 'Evaluación de la voz',
      subtitle: 'Permiso para guardar lo dictado en este teléfono',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(voiceEvidenceConsentText),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  consent == null
                      ? 'Permiso: no dado. No se guarda nada.'
                      : 'Permiso: dado. Dictados guardados: $_count.',
                  key: const Key('voz-evidencia-estado'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                if (consent == null)
                  FilledButton(
                    key: const Key('voz-evidencia-aceptar'),
                    onPressed: _busy ? null : _grant,
                    child: const Text('Acepto'),
                  )
                else ...[
                  OutlinedButton(
                    key: const Key('voz-evidencia-borrar'),
                    onPressed: _busy || _count == 0 ? null : _eraseAll,
                    child: const Text('Borrar lo guardado'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    key: const Key('voz-evidencia-retirar'),
                    onPressed: _busy ? null : _revoke,
                    child: const Text('Retirar el permiso'),
                  ),
                ],
              ],
            ),
    );
  }
}
