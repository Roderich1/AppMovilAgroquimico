import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/app_log.dart';
import '../../data/sync/joint_purchase_store.dart';
import '../../domain/money.dart' show baseUnitsPerMajor, formatQuantity;
import '../../domain/numeric_input.dart' show formatForInput, parseBaseQuantity;
import '../../domain/sync/joint_purchase_call_view.dart';
import '../../services/auth/remote_session_coordinator.dart';
import '../../services/auth/remote_session_providers.dart';
import '../../services/sync/sync_providers.dart';
import '../theme/agro_theme.dart';
import '../widgets/agro_ui.dart';
import '../widgets/common.dart';
import '../widgets/joint_purchase_access_review.dart';
import '../widgets/joint_purchase_texts.dart';
import '../widgets/rdm_c_joint.dart';
import '../widgets/rdm_c_page.dart';
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

  Future<void> _participate(
    JointPurchaseCall call,
    Map<String, int> declared,
  ) async {
    final initial = call.pendingOp?.isWithdraw == false
        ? call.pendingOp!.lines
        : call.acceptedActive?.lines ?? const <String, int>{};
    final lines = await showRdmCSheet<Map<String, int>>(
      context,
      builder: (_) => ParticipationQuantitiesDialog(
        call: call,
        initial: initial,
        declared: declared,
      ),
    );
    if (lines == null || !mounted) return;
    // E2 §10.6 y E4 §4: el consentimiento (`CONV-4`) se pide sólo para
    // participar por primera vez; modificar cantidades conserva lo aceptado
    // y nunca cambia quién ve los datos.
    DateTime? acceptedAt;
    if (call.serverParticipation == null) {
      acceptedAt = await showDialog<DateTime>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const JointPurchaseConsentDialog(),
      );
      if (acceptedAt == null || !mounted) return;
    }
    await _save(
      () => ref
          .read(jointPurchaseStoreProvider)
          .confirm(
            callId: call.callId,
            lines: lines,
            consentVersion: acceptedAt == null
                ? null
                : jointPurchaseConsentVersion,
            consentAcceptedAt: acceptedAt,
          ),
      acceptedAt == null
          ? 'Guardada en el teléfono: pendiente de envío al sindicato. Su '
                'autorización no cambia.'
          : 'Guardada en el teléfono: pendiente de envío al sindicato.',
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
      if (mounted) _showAccessProblem(error);
    } on Object catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted) _reload();
  }

  /// Decisión E del autor (2026-11-13): sin acceso en línea no se envió
  /// nada. El aviso lo dice y, si hay que volver a autenticar, lleva a la
  /// pantalla existente (`/reauth`); después, «Enviar ahora» lo envía.
  void _showAccessProblem(SyncAccessUnavailable error) {
    AppLog.error('Error mostrado al usuario', error: error);
    final phase = ref.read(remoteSessionProvider).phase;
    final router = GoRouter.maybeOf(context);
    final reauth =
        router != null &&
        (phase == RemoteSessionPhase.requiresReauthentication ||
            phase == RemoteSessionPhase.outcomeUnknown);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${error.message} Lo pendiente no se envió y sigue guardado en el '
          'teléfono.',
        ),
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 10),
        action: reauth
            ? SnackBarAction(
                label: 'Volver a autenticar',
                onPressed: () => router.push('/reauth'),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(jointPurchaseRevisionProvider, (_, _) => _reload());
    return FutureBuilder<_Detail>(
      future: detail,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return RdmCPage(
            title: 'Compra conjunta',
            child: EmptyState(
              icon: Icons.error_outline,
              message: friendlyError(snapshot.error!),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const RdmCPage(
            title: 'Compra conjunta',
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final call = snapshot.data!.call;
        if (call == null) {
          return const RdmCPage(
            title: 'Compra conjunta',
            child: RdmCEmpty(
              icon: Icons.search_off_outlined,
              message:
                  'Esta convocatoria no está en el teléfono para el titular '
                  'actual.',
            ),
          );
        }
        return RdmCPage(
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
    final consentResult = jointPurchaseConsentResultText(call);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CallSummary(call: call),
        const SizedBox(height: 16),
        // --- Cantidades: participar, modificar, retirar ---------------------
        const SectionHeader(title: 'Su participación'),
        const SizedBox(height: 10),
        AgroGroup(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (opText != null) ...[
                    StatusBadge(
                      key: const Key('joint-op-status'),
                      label: opText,
                      tone: jointPurchaseChipTone(opText),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (accepted != null)
                    Text(
                      accepted,
                      key: const Key('joint-accepted'),
                      style: AgroText.question,
                    ),
                  if (pending != null)
                    Padding(
                      padding: EdgeInsets.only(top: accepted == null ? 0 : 6),
                      child: Text(
                        pending,
                        key: const Key('joint-pending'),
                        style: AgroText.detail.copyWith(
                          color: AgroColors.warnInk,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  if (accepted == null && pending == null)
                    const Text(
                      'Todavía no participa en esta convocatoria.',
                      style: AgroText.detail,
                    ),
                ],
              ),
            ),
          ],
        ),
        if (!call.isOpen)
          JointInfoLine(
            text: '${callStatusText(call)}: ya no admite cambios.',
            textKey: const Key('joint-not-open'),
            icon: Icons.lock_clock_outlined,
            strong: true,
          ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(1);
            final side =
                hasParticipation && constraints.maxWidth / 2 >= 160 * scale;
            final participate = PrimaryActionButton(
              key: const Key('joint-participate'),
              label: hasParticipation ? 'Modificar' : 'Participar',
              icon: Icons.how_to_reg_outlined,
              iconFirst: true,
              onPressed: busy || !call.isOpen
                  ? null
                  : () => _participate(call, declared),
            );
            final withdraw = SecondaryActionButton(
              key: const Key('joint-withdraw'),
              label: 'Retirar participación',
              icon: Icons.person_remove_outlined,
              onPressed: busy || !call.isOpen ? null : () => _withdraw(call),
            );
            if (!hasParticipation) return participate;
            return side
                ? Row(
                    children: [
                      Expanded(child: participate),
                      const SizedBox(width: 10),
                      Expanded(child: withdraw),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      participate,
                      const SizedBox(height: 10),
                      withdraw,
                    ],
                  );
          },
        ),
        if (call.pendingOp != null || call.pendingConsentOp != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('joint-send-now'),
              onPressed: busy ? null : () => _sendNow(call),
              icon: const Icon(Icons.send_outlined),
              label: const Text('Enviar ahora'),
            ),
          ),
        const JointInfoLine(
          text:
              'Participar no es una compra ni genera una deuda: la persona '
              'responsable coordina la compra y la entrega.',
          textKey: Key('joint-not-a-debt'),
        ),
        const SizedBox(height: 16),
        // --- Productos de la convocatoria ----------------------------------
        const SectionHeader(title: 'Productos'),
        const SizedBox(height: 10),
        AgroGroup(
          children: [
            for (final product in call.products)
              RdmCRow(
                title: '${product.name} (${product.unit})',
                detail: declared[product.productRef] == null
                    ? null
                    : 'Su necesidad declarada para esta campaña: '
                          '${formatQuantity(declared[product.productRef]!, product.unit)}',
              ),
          ],
        ),
        if (declared.isNotEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              'La necesidad declarada es sólo una referencia: no se suma a su '
              'participación.',
              style: AgroText.detail,
            ),
          ),
        const SizedBox(height: 16),
        // --- Quién ve sus datos (E4 §4: aparte de las cantidades) -----------
        const SectionHeader(title: 'Quién ve sus datos'),
        JointInfoLine(
          text: jointPurchaseWhoCanSeeText(call),
          textKey: const Key('joint-who-can-see'),
          icon: Icons.visibility_outlined,
        ),
        // Con pocas participaciones, un total sin nombres puede permitir
        // deducir una cantidad: se dice siempre (ayuda de `CONV-4`).
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: JointPurchaseConsentHelp(textKey: Key('joint-consent-help')),
        ),
        if (call.pendingConsentOp != null)
          JointInfoLine(
            text: jointPurchaseConsentPendingText(call.pendingConsentOp!),
            textKey: const Key('joint-consent-pending'),
            icon: Icons.schedule,
            strong: true,
          ),
        if (consentResult != null)
          JointInfoLine(
            text: consentResult,
            textKey: const Key('joint-consent-result'),
            icon: Icons.fact_check_outlined,
          ),
        // E4 §4.2: revisar (también en una cerrada) o retirar la
        // autorización; acciones propias, aparte de las cantidades (se
        // muestran solas si aplican; nunca en una cancelada).
        JointPurchaseAccessActions(call: call, onChanged: _reload),
      ],
    );
  }
}

/// Resumen oscuro de la convocatoria (lámina «Convocatoria»): estado,
/// campaña agrícola, fecha límite según el sindicato y persona responsable.
class _CallSummary extends StatelessWidget {
  const _CallSummary({required this.call});
  final JointPurchaseCall call;

  @override
  Widget build(BuildContext context) {
    final light = AgroText.detail.copyWith(color: AgroColors.onInk);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: AgroColors.ink,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Compra conjunta',
                style: AgroText.detail.copyWith(color: AgroColors.onInkMuted),
              ),
              StatusBadge(
                label: callStatusText(call),
                tone: jointPurchaseChipTone(callStatusText(call)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Campaña agrícola ≠ convocatoria: la campaña es el período; la
          // convocatoria es esta compra conjunta.
          if (call.campaignName != null)
            Text('Campaña: ${call.campaignName}', style: light),
          Text(
            callDeadlineText(call),
            style: AgroText.question.copyWith(color: AgroColors.lime),
          ),
          if (call.responsibleName != null)
            Text('Responsable: ${call.responsibleName}', style: light),
        ],
      ),
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
    this.declared = const {},
  });

  final JointPurchaseCall call;
  final Map<String, int> initial;

  /// Necesidad declarada por producto, sólo como referencia (no se suma).
  final Map<String, int> declared;

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
  Widget build(BuildContext context) => RdmCSheetBody(
    title: 'Cantidades que solicita',
    subtitle: '${widget.call.name} · ${callDeadlineText(widget.call)}',
    actions: [
      PrimaryActionButton(
        key: const Key('joint-quantities-continue'),
        label: 'Continuar',
        onPressed: _submit,
      ),
    ],
    children: [
      AgroGroup(
        children: [
          for (final product in widget.call.products)
            _QuantityRow(
              product: product,
              declared: widget.declared[product.productRef],
              controller: controllers[product.productRef]!,
              error: errors[product.productRef],
              onChanged: () => setState(() {
                errors.remove(product.productRef);
                general = null;
              }),
            ),
        ],
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(4, 10, 4, 0),
        child: Text('Deje vacío lo que no pide.', style: AgroText.detail),
      ),
      if (general != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
          child: Row(
            children: [
              const Icon(
                Icons.error_outline,
                size: 18,
                color: AgroColors.danger,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  general!,
                  style: const TextStyle(color: AgroColors.danger),
                ),
              ),
            ],
          ),
        ),
      // Las cantidades no cambian quién ve sus datos (E2 §10.6): eso se
      // decide aparte, en «Quién ve sus datos».
    ],
  );
}

/// Un producto: nombre, la necesidad declarada como referencia y el campo
/// de la cantidad con su unidad. Con la letra ampliada el campo baja debajo
/// del nombre.
class _QuantityRow extends StatelessWidget {
  const _QuantityRow({
    required this.product,
    required this.declared,
    required this.controller,
    required this.error,
    required this.onChanged,
  });

  final JointPurchaseProduct product;
  final int? declared;
  final TextEditingController controller;
  final String? error;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(product.name, style: AgroText.value),
        if (declared != null)
          Text(
            'Su necesidad declarada: '
            '${formatQuantity(declared!, product.unit)}',
            style: AgroText.detail,
          ),
      ],
    );
    final field = Semantics(
      label: '${product.name}, cantidad en ${product.unit}',
      child: TextField(
        key: Key('joint-quantity-${product.productRef}'),
        controller: controller,
        textAlign: TextAlign.end,
        style: AgroText.input,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          // La unidad siempre a la vista (`suffixText` sólo aparece al
          // escribir).
          suffixIcon: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(product.unit, style: AgroText.value),
          ),
          suffixIconConstraints: const BoxConstraints(minWidth: 0),
          errorText: error,
          errorMaxLines: 4,
        ),
        onChanged: (_) => onChanged(),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(1);
          if (constraints.maxWidth >= 300 * scale) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: label,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(width: 140 * scale.clamp(1, 1.3), child: field),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [label, const SizedBox(height: 8), field],
          );
        },
      ),
    );
  }
}

/// Consentimiento vigente (`CONV-4`, E4 §4.1) con su ayuda y una casilla
/// obligatoria sin marcar, sólo al participar por primera vez: aceptarlo da
/// el alcance `ADMINISTRATION` (la Administración habilitada ve el nombre y
/// las cantidades; la Directiva, sólo los totales). Devuelve la fecha de
/// aceptación (del teléfono) o null si se cancela.
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
          const SizedBox(height: 8),
          const JointPurchaseConsentHelp(
            textKey: Key('joint-consent-dialog-help'),
          ),
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
