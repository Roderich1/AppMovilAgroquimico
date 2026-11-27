import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/sync/joint_purchase_call_view.dart';
import '../../domain/sync/joint_purchase_models.dart';
import '../../services/sync/sync_providers.dart';
import '../theme/agro_theme.dart';
import 'common.dart';
import 'joint_purchase_texts.dart';

/// Permite autorizar a Administración sobre una participación anterior,
/// incluso en el histórico de una convocatoria cerrada.
class JointPurchaseAccessActions extends ConsumerStatefulWidget {
  const JointPurchaseAccessActions({
    super.key,
    required this.call,
    required this.onChanged,
  });

  final JointPurchaseCall call;

  /// Se llama después de guardar una decisión (para volver a leer el detalle).
  final VoidCallback onChanged;

  @override
  ConsumerState<JointPurchaseAccessActions> createState() =>
      _JointPurchaseAccessActionsState();
}

class _JointPurchaseAccessActionsState
    extends ConsumerState<JointPurchaseAccessActions> {
  bool busy = false;

  Future<void> _authorize() async {
    final decidedAt = await showDialog<DateTime>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const JointPurchaseAccessReviewDialog(),
    );
    if (decidedAt == null || !mounted) return;
    setState(() => busy = true);
    try {
      final op = await ref
          .read(jointPurchaseGatewayProvider)
          .decideAccess(
            callId: widget.call.callId,
            scope: JointPurchaseConsentScope.administration,
            decidedAt: decidedAt,
          );
      if (!mounted) return;
      showSuccess(
        context,
        op == null
            ? 'Eso ya rige en el sindicato: no hay nada que enviar.'
            : 'Autorización guardada en el teléfono: pendiente de envío. '
                  'Hasta que el sindicato la reciba, no está aplicada.',
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
    if (!call.canReviewAccess) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (call.needsAccessReview)
            FilledButton.icon(
              key: const Key('joint-access-review'),
              onPressed: busy ? null : _authorize,
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text(jointPurchaseAccessReviewLabel),
            )
          else
            OutlinedButton.icon(
              key: const Key('joint-access-review'),
              onPressed: busy ? null : _authorize,
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text(jointPurchaseAccessReviewLabel),
            ),
        ],
      ),
    );
  }
}

/// Ayuda de `CONV-4` con su icono, legible por el lector de pantalla como un
/// solo texto.
class JointPurchaseConsentHelp extends StatelessWidget {
  const JointPurchaseConsentHelp({super.key, required this.textKey});

  final Key textKey;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(Icons.help_outline, size: 20, color: AgroColors.muted),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            jointPurchaseConsentHelp,
            key: textKey,
            style: AgroText.detail,
          ),
        ),
      ],
    ),
  );
}

/// «Revisar quién puede ver mi participación»: el texto `CONV-4` exacto, su
/// ayuda, una casilla **sin marcar** y «Sus cantidades no cambian.».
/// Devuelve la fecha de la decisión (del teléfono) o null.
class JointPurchaseAccessReviewDialog extends StatefulWidget {
  const JointPurchaseAccessReviewDialog({super.key});

  @override
  State<JointPurchaseAccessReviewDialog> createState() =>
      _JointPurchaseAccessReviewDialogState();
}

class _JointPurchaseAccessReviewDialogState
    extends State<JointPurchaseAccessReviewDialog> {
  bool accepted = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text(jointPurchaseAccessReviewLabel),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            jointPurchaseConsentText,
            key: Key('joint-access-review-text'),
          ),
          const SizedBox(height: 8),
          const JointPurchaseConsentHelp(
            textKey: Key('joint-access-review-help'),
          ),
          const SizedBox(height: 8),
          const Text(jointPurchaseAuthorizationLockNotice),
          CheckboxListTile(
            key: const Key('joint-access-review-check'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: accepted,
            onChanged: (value) => setState(() => accepted = value ?? false),
            title: const Text(jointPurchaseAccessReviewCheck),
          ),
          const Text(jointPurchaseQuantitiesUnchanged),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const Key('joint-access-review-confirm'),
        onPressed: accepted
            ? () => Navigator.pop(context, DateTime.now())
            : null,
        child: const Text('Autorizar'),
      ),
    ],
  );
}
