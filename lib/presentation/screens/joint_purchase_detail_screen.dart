import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sync/joint_purchase_store.dart';
import '../../domain/money.dart' show baseUnitsPerMajor, formatQuantity;
import '../../domain/numeric_input.dart' show formatForInput, parseBaseQuantity;
import '../../domain/sync/joint_purchase_call_view.dart';
import '../../services/sync/sync_providers.dart';
import '../widgets/common.dart';
import '../widgets/joint_purchase_texts.dart';
import 'joint_purchases_screen.dart' show refreshProblem;

typedef _Detail = ({JointPurchaseCall? call, Map<String, int> declared});

/// Detalle de una convocatoria (E2 §5.2–§5.4). Abrirla la marca como vista
/// (sólo en el teléfono). Participar, modificar o retirar se guarda en el
/// teléfono como «Pendiente de envío»; el sindicato decide al recibirlo.
class JointPurchaseDetailScreen extends ConsumerStatefulWidget {
  const JointPurchaseDetailScreen({super.key, required this.callId});

  final String callId;

  @override
  ConsumerState<JointPurchaseDetailScreen> createState() =>
      _JointPurchaseDetailScreenState();
}

class _JointPurchaseDetailScreenState
    extends ConsumerState<JointPurchaseDetailScreen> {
  late Future<_Detail> detail;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    detail = _read(markSeen: true);
  }

  Future<_Detail> _read({bool markSeen = false}) async {
    final store = ref.read(jointPurchaseStoreProvider);
    if (markSeen && await store.markSeen(widget.callId) && mounted) {
      ref.read(jointPurchaseRevisionProvider.notifier).bump();
    }
    final call = await store.call(widget.callId);
    return (
      call: call,
      declared: call == null
          ? const <String, int>{}
          : await store.declaredNeedsFor(call.campaignRef),
    );
  }

  void _reload() {
    final next = _read();
    setState(() {
      detail = next;
    });
  }

  Future<void> _participate(JointPurchaseCall call) async {
    final initial = call.pendingOp?.isWithdraw == false
        ? call.pendingOp!.lines
        : call.acceptedActive?.lines ?? const <String, int>{};
    final lines = await showDialog<Map<String, int>>(
      context: context,
      builder: (_) =>
          ParticipationQuantitiesDialog(call: call, initial: initial),
    );
    if (lines == null || !mounted) return;
    final acceptedAt = await showDialog<DateTime>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const JointPurchaseConsentDialog(),
    );
    if (acceptedAt == null || !mounted) return;
    await _save(
      () => ref
          .read(jointPurchaseStoreProvider)
          .confirm(
            callId: call.callId,
            lines: lines,
            consentVersion: jointPurchaseConsentVersion,
            consentAcceptedAt: acceptedAt,
          ),
      'Guardada en el teléfono: pendiente de envío al sindicato.',
    );
  }

  Future<void> _withdraw(JointPurchaseCall call) async {
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Retirar participación',
      detail:
          'Se avisará al sindicato que retira su participación en '
          '«${call.name}». Podrá volver a participar mientras la convocatoria '
          'siga abierta.',
      confirmLabel: 'Retirar',
    );
    if (!confirmed || !mounted) return;
    await _save(
      () => ref.read(jointPurchaseStoreProvider).withdraw(call.callId),
      'Retiro guardado en el teléfono: pendiente de envío al sindicato.',
    );
  }

  Future<void> _save(Future<Object?> Function() action, String done) async {
    setState(() => busy = true);
    try {
      await action();
      if (!mounted) return;
      showSuccess(context, done);
      ref.read(syncControllerProvider.notifier).jointPurchaseQueued();
    } on Object catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted) _reload();
  }

  Future<void> _sendNow(JointPurchaseCall call) async {
    setState(() => busy = true);
    try {
      final report = await ref
          .read(syncControllerProvider.notifier)
          .sendJointPurchaseNow(call.callId);
      final problem = refreshProblem(report);
      if (problem != null && mounted) showError(context, problem);
    } on SyncAccessUnavailable catch (error) {
      if (mounted) showError(context, error.message);
    } on Object catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(jointPurchaseRevisionProvider, (_, _) => _reload());
    return FutureBuilder<_Detail>(
      future: detail,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return PageFrame(
            title: 'Compra conjunta',
            child: EmptyState(
              icon: Icons.error_outline,
              message: friendlyError(snapshot.error!),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const PageFrame(
            title: 'Compra conjunta',
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final call = snapshot.data!.call;
        if (call == null) {
          return const PageFrame(
            title: 'Compra conjunta',
            child: EmptyState(
              icon: Icons.search_off_outlined,
              message:
                  'Esta convocatoria no está en el teléfono para el titular '
                  'actual.',
            ),
          );
        }
        return PageFrame(
          title: call.name,
          child: _body(context, call, snapshot.data!.declared),
        );
      },
    );
  }

  Widget _body(
    BuildContext context,
    JointPurchaseCall call,
    Map<String, int> declared,
  ) {
    final hasParticipation =
        call.acceptedActive != null ||
        (call.pendingOp != null && !call.pendingOp!.isWithdraw);
    final opText = jointPurchaseOpText(call.latestOp);
    final accepted = acceptedText(call);
    final pending = pendingText(call);
    final bold = const TextStyle(fontWeight: FontWeight.w700);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Chip(
                  label: Text(callStatusText(call)),
                  visualDensity: VisualDensity.compact,
                ),
                if (call.campaignName != null)
                  Text('Campaña: ${call.campaignName}'),
                Text(callDeadlineText(call)),
                if (call.responsibleName != null)
                  Text('Responsable: ${call.responsibleName}'),
              ],
            ),
          ),
        ),
        const SectionHeading(title: 'Productos'),
        for (final product in call.products)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('${product.name} (${product.unit})'),
            subtitle: declared[product.productRef] == null
                ? null
                : Text(
                    'Su necesidad declarada para esta campaña: '
                    '${formatQuantity(declared[product.productRef]!, product.unit)}',
                  ),
          ),
        if (declared.isNotEmpty)
          const Text(
            'La necesidad declarada es sólo una referencia: no se suma a su '
            'participación.',
          ),
        const SizedBox(height: 8),
        const SectionHeading(title: 'Su participación'),
        if (opText != null)
          Chip(
            key: const Key('joint-op-status'),
            label: Text(opText),
            visualDensity: VisualDensity.compact,
          ),
        if (accepted != null)
          Text(accepted, key: const Key('joint-accepted'), style: bold),
        if (pending != null) Text(pending, key: const Key('joint-pending')),
        if (accepted == null && pending == null)
          const Text('Todavía no participa en esta convocatoria.'),
        const SizedBox(height: 4),
        const Text(
          'Participar no es una compra ni genera una deuda: la persona '
          'responsable y quienes ella autorice coordinan la compra y la '
          'entrega.',
          key: Key('joint-not-a-debt'),
        ),
        if (!call.isOpen)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${callStatusText(call)}: ya no admite cambios.',
              key: const Key('joint-not-open'),
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              key: const Key('joint-participate'),
              onPressed: busy || !call.isOpen ? null : () => _participate(call),
              icon: const Icon(Icons.how_to_reg_outlined),
              label: Text(hasParticipation ? 'Modificar' : 'Participar'),
            ),
            if (hasParticipation)
              OutlinedButton.icon(
                key: const Key('joint-withdraw'),
                onPressed: busy || !call.isOpen ? null : () => _withdraw(call),
                icon: const Icon(Icons.person_remove_outlined),
                label: const Text('Retirar participación'),
              ),
            if (call.pendingOp != null)
              TextButton.icon(
                key: const Key('joint-send-now'),
                onPressed: busy ? null : () => _sendNow(call),
                icon: const Icon(Icons.send_outlined),
                label: const Text('Enviar ahora'),
              ),
          ],
        ),
      ],
    );
  }
}

/// Cantidades por producto en L o KG (convertidas a ML/G como la necesidad
/// declarada, con `parseBaseQuantity`). Vacío = no pide ese producto.
class ParticipationQuantitiesDialog extends StatefulWidget {
  const ParticipationQuantitiesDialog({
    super.key,
    required this.call,
    required this.initial,
  });

  final JointPurchaseCall call;
  final Map<String, int> initial;

  @override
  State<ParticipationQuantitiesDialog> createState() =>
      _ParticipationQuantitiesDialogState();
}

class _ParticipationQuantitiesDialogState
    extends State<ParticipationQuantitiesDialog> {
  late final Map<String, TextEditingController> controllers = {
    for (final product in widget.call.products)
      product.productRef: TextEditingController(
        text: widget.initial[product.productRef] == null
            ? ''
            : formatForInput(
                widget.initial[product.productRef]! / baseUnitsPerMajor,
              ),
      ),
  };
  final Map<String, String?> errors = {};
  String? general;

  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final lines = <String, int>{};
    final nextErrors = <String, String?>{};
    for (final product in widget.call.products) {
      final text = controllers[product.productRef]!.text.trim();
      if (text.isEmpty) continue;
      final parsed = parseBaseQuantity(text);
      if (!parsed.isValid) {
        nextErrors[product.productRef] = parsed.message;
      } else if (parsed.base! <= 0) {
        nextErrors[product.productRef] =
            'Debe ser mayor que cero. Deje el campo vacío si no pide este '
            'producto.';
      } else {
        lines[product.productRef] = parsed.base!;
      }
    }
    setState(() {
      errors
        ..clear()
        ..addAll(nextErrors);
      general = nextErrors.isEmpty && lines.isEmpty
          ? 'Indique la cantidad de al menos un producto.'
          : null;
    });
    if (nextErrors.isEmpty && lines.isNotEmpty) Navigator.pop(context, lines);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Cantidades que solicita'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final product in widget.call.products)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                key: Key('joint-quantity-${product.productRef}'),
                controller: controllers[product.productRef],
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: product.name,
                  suffixText: product.unit,
                  errorText: errors[product.productRef],
                  errorMaxLines: 3,
                ),
                onChanged: (_) => setState(() {
                  errors.remove(product.productRef);
                  general = null;
                }),
              ),
            ),
          const Text('Deje vacío lo que no pide.'),
          if (general != null)
            Text(
              general!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Continuar')),
    ],
  );
}

/// Consentimiento vigente `CONV-2` (E2 §10.2) con casilla obligatoria. Devuelve la
/// fecha de aceptación (del teléfono) o null si se cancela.
class JointPurchaseConsentDialog extends StatefulWidget {
  const JointPurchaseConsentDialog({super.key});

  @override
  State<JointPurchaseConsentDialog> createState() =>
      _JointPurchaseConsentDialogState();
}

class _JointPurchaseConsentDialogState
    extends State<JointPurchaseConsentDialog> {
  bool accepted = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Antes de confirmar'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(jointPurchaseConsentText),
          CheckboxListTile(
            key: const Key('joint-consent-check'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: accepted,
            onChanged: (value) => setState(() => accepted = value ?? false),
            title: const Text('Entiendo y acepto'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const Key('joint-consent-confirm'),
        onPressed: accepted
            ? () => Navigator.pop(context, DateTime.now())
            : null,
        child: const Text('Confirmar participación'),
      ),
    ],
  );
}
