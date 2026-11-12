import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sync/joint_purchase_store.dart';
import '../../domain/sync/joint_purchase_call_view.dart';
import '../../services/sync/sync_providers.dart';
import 'common.dart';
import 'joint_purchase_texts.dart';

/// P-A C1 (E2 §12): la persona responsable de la convocatoria cambió y el
/// sindicato dice que este agricultor todavía no la autorizó. Muestra quién
/// es ahora, lo que eso significa y una acción **propia** para autorizarla,
/// separada de las cantidades (también en una convocatoria cerrada, sin
/// editar el pedido; nunca en una cancelada). No se muestra si no aplica.
///
/// Estados:
/// - `joint-responsible-changed`: falta autorizarla;
/// - `joint-responsible-pending`: la autorización está guardada en el
///   teléfono y todavía no llegó (nunca se anuncia como aplicada);
/// - `joint-responsible-outdated`: la responsable volvió a cambiar antes de
///   que llegara: hay que revisar de nuevo.
///
/// La lógica (qué se guarda y qué se envía) está en
/// `JointPurchaseStore.decideConsent(authorizeResponsible: true)`; este
/// widget sólo la presenta, para que la pantalla de detalle la pueda
/// colocar con su propio estilo.
class JointPurchaseResponsibleReview extends ConsumerStatefulWidget {
  const JointPurchaseResponsibleReview({
    super.key,
    required this.call,
    required this.onChanged,
  });

  final JointPurchaseCall call;

  /// Se llama después de guardar una decisión (para volver a leer el detalle).
  final VoidCallback onChanged;

  @override
  ConsumerState<JointPurchaseResponsibleReview> createState() =>
      _JointPurchaseResponsibleReviewState();
}

class _JointPurchaseResponsibleReviewState
    extends ConsumerState<JointPurchaseResponsibleReview> {
  bool busy = false;

  Future<void> _review() async {
    final call = widget.call;
    final decision = await showDialog<JointPurchaseResponsibleDecision>(
      context: context,
      barrierDismissible: false,
      builder: (_) => JointPurchaseResponsibleDialog(call: call),
    );
    if (decision == null || !mounted) return;
    setState(() => busy = true);
    try {
      await ref
          .read(jointPurchaseStoreProvider)
          .decideConsent(
            callId: call.callId,
            scope: decision.scope,
            decidedAt: decision.decidedAt,
            authorizeResponsible: true,
          );
      if (!mounted) return;
      showSuccess(
        context,
        'Autorización guardada en el teléfono: pendiente de envío. Hasta que '
        'el sindicato la reciba, la nueva persona responsable sigue sin ver '
        'sus datos.',
      );
      ref.read(syncControllerProvider.notifier).jointPurchaseQueued();
    } on Object catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final call = widget.call;
    final outdated = call.authorizationOutdated;
    final pending =
        !outdated && call.pendingConsentOp?.authorizeResponsible == true;
    if (!call.needsResponsibleReview && !outdated && !pending) {
      return const SizedBox.shrink();
    }
    return Card(
      key: const Key('joint-responsible-review'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              jointPurchaseResponsibleChangedText(call),
              key: const Key('joint-responsible-changed'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (pending)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  jointPurchaseResponsiblePendingText(call),
                  key: const Key('joint-responsible-pending'),
                ),
              ),
            if (outdated)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  jointPurchaseResponsibleOutdatedText,
                  key: Key('joint-responsible-outdated'),
                ),
              ),
            if (!pending)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  key: const Key('joint-responsible-authorize'),
                  onPressed: busy ? null : _review,
                  icon: const Icon(Icons.verified_user_outlined),
                  label: const Text(jointPurchaseResponsibleReviewLabel),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Lo que eligió el agricultor en [JointPurchaseResponsibleDialog].
typedef JointPurchaseResponsibleDecision = ({String scope, DateTime decidedAt});

/// Autorizar a la persona responsable actual: el texto vigente (`CONV-3`),
/// quién es ahora y dos casillas **sin marcar**: la primera la autoriza a
/// ella; la segunda, aparte, amplía también a quienes ella autorice. Sólo la
/// primera habilita confirmar; la segunda sólo se puede marcar con la
/// primera. Devuelve el alcance elegido y la fecha (del teléfono), o null.
class JointPurchaseResponsibleDialog extends StatefulWidget {
  const JointPurchaseResponsibleDialog({super.key, required this.call});

  final JointPurchaseCall call;

  @override
  State<JointPurchaseResponsibleDialog> createState() =>
      _JointPurchaseResponsibleDialogState();
}

class _JointPurchaseResponsibleDialogState
    extends State<JointPurchaseResponsibleDialog> {
  bool responsible = false;
  bool collaborators = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Autorizar a la nueva persona responsable'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Persona responsable actual: '
            '${widget.call.responsibleName ?? '(sin nombre)'}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(jointPurchaseConsentText),
          CheckboxListTile(
            key: const Key('joint-responsible-check'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: responsible,
            onChanged: (value) => setState(() {
              responsible = value ?? false;
              if (!responsible) collaborators = false;
            }),
            title: Text(jointPurchaseResponsibleCheck(widget.call)),
          ),
          CheckboxListTile(
            key: const Key('joint-responsible-collaborators'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: collaborators,
            onChanged: responsible
                ? (value) => setState(() => collaborators = value ?? false)
                : null,
            title: const Text(jointPurchaseResponsibleCollaboratorsCheck),
          ),
          const Text('Sus cantidades no cambian.'),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const Key('joint-responsible-confirm'),
        onPressed: responsible
            ? () => Navigator.pop<JointPurchaseResponsibleDecision>(context, (
                scope: collaborators
                    ? JointPurchaseConsentScope.collaborators
                    : JointPurchaseConsentScope.responsibleOnly,
                decidedAt: DateTime.now(),
              ))
            : null,
        child: const Text('Autorizar'),
      ),
    ],
  );
}
