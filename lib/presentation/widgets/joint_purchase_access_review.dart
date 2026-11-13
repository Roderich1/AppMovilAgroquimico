import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sync/joint_purchase_store.dart';
import '../../domain/sync/joint_purchase_call_view.dart';
import '../../services/sync/sync_providers.dart';
import '../theme/agro_theme.dart';
import 'common.dart';
import 'joint_purchase_texts.dart';

/// E4 §4.2 (sustituye a la revisión de la persona responsable de P-A C1, que
/// ya no decide quién ve nada): las dos acciones sobre quién ve el nombre y
/// las cantidades, separadas de las cantidades.
///
/// - `joint-access-review` — «Revisar quién puede ver mi participación»:
///   para una participación con consentimiento anterior (también en una
///   convocatoria cerrada, sin reabrirla ni cambiar el consolidado) o con la
///   autorización retirada. Muestra el texto `CONV-4` y su ayuda con una
///   casilla sin marcar.
/// - `joint-access-retract` — «Retirar la autorización» (D-05): la
///   Administración deja de ver el detalle y la participación sigue.
///
/// Nunca en una convocatoria cancelada. La lógica (qué se guarda y qué se
/// envía) está en `JointPurchaseStore.decideAccess`; este widget sólo la
/// presenta. No se muestra si no aplica.
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

  Future<void> _decide(String scope) async {
    final review = scope == JointPurchaseConsentScope.administration;
    final decidedAt = await showDialog<DateTime>(
      context: context,
      barrierDismissible: false,
      builder: (_) => review
          ? const JointPurchaseAccessReviewDialog()
          : const JointPurchaseAccessRetractDialog(),
    );
    if (decidedAt == null || !mounted) return;
    setState(() => busy = true);
    try {
      final op = await ref
          .read(jointPurchaseStoreProvider)
          .decideAccess(
            callId: widget.call.callId,
            scope: scope,
            decidedAt: decidedAt,
          );
      if (!mounted) return;
      showSuccess(context, switch ((review, op == null)) {
        (true, true) => 'Eso ya rige en el sindicato: no hay nada que enviar.',
        (true, false) =>
          'Autorización guardada en el teléfono: pendiente de envío. Hasta que '
              'el sindicato la reciba, no está aplicada.',
        (false, true) =>
          'Se dejó sin efecto la autorización que todavía no se había '
              'enviado. Rige lo anterior.',
        (false, false) =>
          'Retirada guardada en el teléfono: pendiente de envío. Hasta que el '
              'sindicato la reciba, no está aplicada.',
      });
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
    if (!call.canReviewAccess && !call.canRetractAccess) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (call.canReviewAccess)
            // Una participación anterior que falta revisar se destaca; volver
            // a autorizar tras retirarla, no.
            call.needsAccessReview
                ? FilledButton.icon(
                    key: const Key('joint-access-review'),
                    onPressed: busy
                        ? null
                        : () =>
                              _decide(JointPurchaseConsentScope.administration),
                    icon: const Icon(Icons.verified_user_outlined),
                    label: const Text(jointPurchaseAccessReviewLabel),
                  )
                : OutlinedButton.icon(
                    key: const Key('joint-access-review'),
                    onPressed: busy
                        ? null
                        : () =>
                              _decide(JointPurchaseConsentScope.administration),
                    icon: const Icon(Icons.verified_user_outlined),
                    label: const Text(jointPurchaseAccessReviewLabel),
                  ),
          if (call.canRetractAccess)
            OutlinedButton.icon(
              key: const Key('joint-access-retract'),
              onPressed: busy
                  ? null
                  : () => _decide(JointPurchaseConsentScope.totalsOnly),
              icon: const Icon(Icons.lock_person_outlined),
              label: const Text(jointPurchaseAccessRetractLabel),
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

/// «Retirar la autorización» (D-05): qué cambia, una casilla **sin marcar**
/// y «Sus cantidades no cambian.». Devuelve la fecha de la decisión (del
/// teléfono) o null.
class JointPurchaseAccessRetractDialog extends StatefulWidget {
  const JointPurchaseAccessRetractDialog({super.key});

  @override
  State<JointPurchaseAccessRetractDialog> createState() =>
      _JointPurchaseAccessRetractDialogState();
}

class _JointPurchaseAccessRetractDialogState
    extends State<JointPurchaseAccessRetractDialog> {
  bool confirmed = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text(jointPurchaseAccessRetractLabel),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            jointPurchaseAccessRetractDetail,
            key: Key('joint-access-retract-detail'),
          ),
          CheckboxListTile(
            key: const Key('joint-access-retract-check'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: confirmed,
            onChanged: (value) => setState(() => confirmed = value ?? false),
            title: const Text(jointPurchaseAccessRetractCheck),
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
        key: const Key('joint-access-retract-confirm'),
        onPressed: confirmed
            ? () => Navigator.pop(context, DateTime.now())
            : null,
        child: const Text('Retirar'),
      ),
    ],
  );
}
