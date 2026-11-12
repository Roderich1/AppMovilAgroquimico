import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../data/operation_mode_store.dart';
import '../../domain/operation_mode.dart';
import '../../operation_mode_controller.dart';
import '../theme/agro_theme.dart';
import '../widgets/agro_ui.dart';
import '../widgets/common.dart';

/// Qué significa cada modalidad, con las mismas palabras en la elección
/// inicial del titular y aquí (MODE-02, #25).
String operationModeTitle(OperationMode mode) => switch (mode) {
  OperationMode.shared => 'Inventario compartido',
  OperationMode.personal => 'Inventario propio',
};

String operationModeExplanation(OperationMode mode) => switch (mode) {
  OperationMode.shared =>
    'Varias personas (familiares o terceros) compran, aplican y transfieren '
        'productos; cada una tiene su inventario y su cuenta.',
  OperationMode.personal =>
    'Sólo el titular compra, aplica y paga. No hay transferencias ni hay que '
        'elegir persona en los formularios.',
};

/// Modo de uso (MODE-02/MODE-04, CU-05): consulta, consecuencias y
/// confirmación. Las reglas viven en [OperationModeStore]; esta pantalla sólo
/// las muestra. Todo es local: funciona sin conexión.
class OperationModeScreen extends ConsumerStatefulWidget {
  const OperationModeScreen({super.key});

  @override
  ConsumerState<OperationModeScreen> createState() =>
      _OperationModeScreenState();
}

class _OperationModeScreenState extends ConsumerState<OperationModeScreen> {
  late Future<OperationMode> _current = _store.current();
  String? _blocked;
  bool _saving = false;

  OperationModeStore get _store =>
      OperationModeStore(ref.read(repositoryProvider).appDatabase);

  Future<void> _change(OperationMode target) async {
    final decision = await _store.evaluate(target);
    if (!mounted) return;
    if (!decision.allowed) {
      final text = await _blockedText(decision);
      if (mounted) setState(() => _blocked = text);
      return;
    }
    final consequence = target == OperationMode.personal
        ? 'Sólo el titular registrará compras, aplicaciones y pagos. Se '
              'ocultan las transferencias y la elección de persona en los '
              'formularios. Los registros de otras personas se conservan.'
        : 'Se habilitan responsables y transferencias. Todo el historial '
              'sigue asociado al titular.';
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              target == OperationMode.personal
                  ? 'Pasar a inventario propio'
                  : 'Pasar a inventario compartido',
            ),
            content: Text(consequence, key: const Key('mode-consequence')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                key: const Key('mode-confirm'),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Confirmar'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    // La modalidad global vive en el contenedor raíz, no en esta pantalla: se
    // toma antes de guardar para recargarla aunque el usuario salga mientras
    // tanto (como en la restauración). Sólo el aviso y el estado de la
    // pantalla dependen de que siga montada.
    final modes = ref.read(operationModeProvider.notifier);
    setState(() => _saving = true);
    try {
      await _store.apply(target, confirmed: true);
      // Navegación, atajos y formularios abiertos leen la modalidad nueva.
      await modes.reload();
      if (!mounted) return;
      showSuccess(
        context,
        target == OperationMode.personal
            ? 'Ahora usa inventario propio. Se ocultaron las transferencias '
                  'y la elección de persona; el historial se conserva.'
            : 'Ahora usa inventario compartido. Ya puede registrar '
                  'responsables y transferencias; el historial sigue '
                  'asociado al titular.',
      );
      setState(() {
        _saving = false;
        _blocked = null;
        _current = _store.current();
      });
    } on ModeTransitionException catch (error) {
      // Algo cambió entre la evaluación y la escritura: se muestra la causa.
      if (!mounted) return;
      final decision = error.decision;
      final text = decision == null
          ? error.message
          : await _blockedText(decision);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _blocked = text;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showError(context, error);
    }
  }

  Future<String> _blockedText(ModeTransitionDecision decision) async {
    if (decision.blocks.contains(ModeTransitionBlock.ownerRequired)) {
      return 'El inventario propio necesita un titular vinculado. Active la '
          'cuenta y elija el titular primero.';
    }
    final names = await _store.describe(decision.activity);
    return [
      'Todavía no se puede pasar a inventario propio. Resuélvalo en modo '
          'compartido:',
      if (names.withStock.isNotEmpty)
        '• Existencias de ${names.withStock.join(', ')}: regístrelas en una '
            'aplicación o transfiéralas al titular.',
      if (names.planFarmOwners.isNotEmpty)
        '• Planes abiertos en chacos de ${names.planFarmOwners.join(', ')}: '
            'aplíquelos o cancélelos en Planificación.',
      if (names.withBalance.isNotEmpty)
        '• Saldo de cuenta de ${names.withBalance.join(', ')}: registre el '
            'pago en Personas › Cuentas.',
      'No se borra ni se reasigna nada.',
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: FutureBuilder<OperationMode>(
        future: _current,
        builder: (context, snapshot) {
          final mode = snapshot.data;
          final header = Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                CircleIconButton(
                  icon: Icons.arrow_back,
                  tooltip: 'Volver',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text('Modo de uso', style: AgroText.h1),
                  ),
                ),
              ],
            ),
          );
          if (mode == null) {
            return Column(
              children: [
                header,
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
            );
          }
          final target = mode == OperationMode.shared
              ? OperationMode.personal
              : OperationMode.shared;
          final blocked = _blocked;
          return Column(
            children: [
              header,
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    // Rediseño (lámina «Modo de uso»): la modalidad en uso en
                    // una tarjeta oscura y la otra en blanco, con lo que hace.
                    Material(
                      color: AgroColors.ink,
                      borderRadius: BorderRadius.circular(28),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const StatusBadge(
                              label: 'En uso',
                              tone: BadgeTone.ok,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              mode == OperationMode.shared
                                  ? 'Modalidad actual: inventario compartido'
                                  : 'Modalidad actual: inventario propio',
                              key: const Key('mode-current'),
                              style: AgroText.h2.copyWith(color: Colors.white),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              operationModeExplanation(mode),
                              key: const Key('mode-current-explanation'),
                              style: AgroText.detail.copyWith(
                                color: AgroColors.onInkMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Material(
                      color: AgroColors.surface,
                      borderRadius: BorderRadius.circular(28),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Si cambia a '
                              '${operationModeTitle(target).toLowerCase()}',
                              style: AgroText.h2,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              operationModeExplanation(target),
                              key: const Key('mode-target-explanation'),
                              style: AgroText.detail,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const NoticeBox(
                      icon: Icons.check,
                      text:
                          'Cambiar no borra ni reasigna registros y no '
                          'necesita conexión.',
                    ),
                    if (blocked != null) ...[
                      const SizedBox(height: 12),
                      NoticeBox(
                        key: const Key('mode-blocked'),
                        tone: NoticeTone.danger,
                        text: blocked,
                      ),
                    ],
                  ],
                ),
              ),
              BottomPanel(
                children: [
                  FilledButton(
                    key: const Key('mode-change'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                    ),
                    onPressed: _saving ? null : () => _change(target),
                    child: Text(
                      target == OperationMode.personal
                          ? 'Cambiar a inventario propio'
                          : 'Cambiar a inventario compartido',
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    ),
  );
}
