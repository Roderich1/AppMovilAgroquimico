import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../data/operation_mode_store.dart';
import '../../domain/operation_mode.dart';
import '../../operation_mode_controller.dart';
import '../theme/agro_theme.dart';
import '../widgets/agro_ui.dart';
import '../widgets/common.dart';

/// Qué significa cada modalidad, con las mismas palabras en la elección
/// inicial del titular y aquí (MODE-02, #25). Nombres de las láminas del
/// modo individual (I-50 a I-52, 2026-11-13); los códigos internos siguen
/// siendo PERSONAL y SHARED.
String operationModeTitle(OperationMode mode) => switch (mode) {
  OperationMode.shared => 'Modo con varias personas',
  OperationMode.personal => 'Modo individual',
};

String operationModeExplanation(OperationMode mode) => switch (mode) {
  OperationMode.shared =>
    'Familiares o terceros compran, aplican y transfieren. Cada persona '
        'tiene su inventario y su cuenta.',
  OperationMode.personal =>
    'Solo el titular compra, aplica y paga. No hay transferencias ni hay que '
        'elegir persona en los formularios. El sindicato y los proveedores '
        'funcionan igual.',
};

/// Lo que cambia al pasar a [target] (lámina I-51, «Si cambia:»).
String operationModeConsequence(OperationMode target) => switch (target) {
  OperationMode.shared =>
    'Se habilitan responsables y transferencias. Todo el historial sigue '
        'asociado al titular.',
  OperationMode.personal =>
    'Solo el titular registrará compras, aplicaciones y pagos. Se ocultan '
        'las transferencias y la elección de persona en los formularios. Los '
        'registros de otras personas se conservan.',
};

/// Un pendiente que impide pasar a modo individual (lámina I-52), con el
/// lugar donde se resuelve.
typedef ModePending = ({String title, String detail, String route});

/// «Beto Mamani», «Beto Mamani y Carmen Choque», «A, B y C».
String _names(List<String> names) => names.length <= 1
    ? names.join()
    : '${names.sublist(0, names.length - 1).join(', ')} y ${names.last}';

/// Pendientes reales de [decision] (`evaluateModeTransition`), sin inventar
/// requisitos: titular vinculado y ninguna existencia, plan abierto ni saldo
/// de otras personas (v1.5 CU-05 A2/E1).
Future<List<ModePending>> modePendings(
  OperationModeStore store,
  ModeTransitionDecision decision,
) async {
  final pendings = <ModePending>[];
  if (decision.blocks.contains(ModeTransitionBlock.ownerRequired)) {
    pendings.add((
      title: 'Falta el titular',
      detail: 'Active la cuenta y elija el titular primero.',
      route: '/acceso',
    ));
  }
  if (decision.blocks.contains(ModeTransitionBlock.thirdPartyActivity)) {
    final names = await store.describe(decision.activity);
    if (names.withStock.isNotEmpty) {
      final many = names.withStock.length > 1;
      pendings.add((
        title:
            '${_names(names.withStock)} ${many ? 'tienen' : 'tiene'} '
            'productos',
        detail: 'Regístrelos en una aplicación o transfiéralos al titular.',
        route: '/inventario',
      ));
    }
    if (names.planFarmOwners.isNotEmpty) {
      pendings.add((
        title:
            'Hay planes abiertos en chacos de '
            '${_names(names.planFarmOwners)}',
        detail: 'Aplíquelos o cancélelos.',
        route: '/planificacion',
      ));
    }
    if (names.withBalance.isNotEmpty) {
      final many = names.withBalance.length > 1;
      pendings.add((
        title:
            '${_names(names.withBalance)} ${many ? 'tienen' : 'tiene'} '
            'saldo',
        detail: 'Registre el pago en su cuenta.',
        route: '/personas',
      ));
    }
  }
  return pendings;
}

typedef _ModeView = ({OperationMode mode, List<ModePending> pendings});

/// Modo de uso (MODE-02/MODE-04, CU-05; láminas I-51 e I-52): la modalidad
/// en uso, la otra y, antes de tocar nada, si el cambio está disponible o
/// qué lo impide. Las reglas viven en [OperationModeStore]; esta pantalla
/// sólo las muestra y vuelve a evaluarlas al confirmar. Todo es local:
/// funciona sin conexión.
class OperationModeScreen extends ConsumerStatefulWidget {
  const OperationModeScreen({super.key});

  @override
  ConsumerState<OperationModeScreen> createState() =>
      _OperationModeScreenState();
}

class _OperationModeScreenState extends ConsumerState<OperationModeScreen> {
  late Future<_ModeView> _view = _load();
  bool _saving = false;

  OperationModeStore get _store =>
      OperationModeStore(ref.read(repositoryProvider).appDatabase);

  static OperationMode _other(OperationMode mode) =>
      mode == OperationMode.shared
      ? OperationMode.personal
      : OperationMode.shared;

  Future<_ModeView> _load() async {
    final store = _store;
    final mode = await store.current();
    final decision = await store.evaluate(_other(mode));
    return (
      mode: mode,
      pendings: decision.allowed
          ? const <ModePending>[]
          : await modePendings(store, decision),
    );
  }

  void _reload() => setState(() {
    _view = _load();
  });

  Future<void> _change(OperationMode target) async {
    // Se evalúa otra vez: algo pudo cambiar desde que se abrió la pantalla.
    final decision = await _store.evaluate(target);
    if (!mounted) return;
    if (!decision.allowed) {
      _reload();
      return;
    }
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              target == OperationMode.personal
                  ? 'Pasar a modo individual'
                  : 'Pasar a varias personas',
            ),
            content: Text(
              operationModeConsequence(target),
              key: const Key('mode-consequence'),
            ),
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
            ? 'Ahora usa el modo individual. Se ocultaron las transferencias '
                  'y la elección de persona; el historial se conserva.'
            : 'Ahora usa el modo con varias personas. Ya puede registrar '
                  'responsables y transferencias; el historial sigue '
                  'asociado al titular.',
      );
      setState(() {
        _saving = false;
        _view = _load();
      });
    } on ModeTransitionException {
      // Algo cambió entre la evaluación y la escritura: se muestran los
      // pendientes que lo impiden.
      if (!mounted) return;
      setState(() {
        _saving = false;
        _view = _load();
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showError(context, error);
    }
  }

  Future<void> _resolve(ModePending pending) async {
    await context.push(pending.route);
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: FutureBuilder<_ModeView>(
        future: _view,
        builder: (context, snapshot) {
          final view = snapshot.data;
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
          if (view == null) {
            return Column(
              children: [
                header,
                Expanded(
                  child: Center(
                    child: snapshot.hasError
                        ? Padding(
                            padding: const EdgeInsets.all(16),
                            child: NoticeBox(
                              tone: NoticeTone.danger,
                              text: friendlyError(snapshot.error!),
                            ),
                          )
                        : const CircularProgressIndicator(),
                  ),
                ),
              ],
            );
          }
          final mode = view.mode;
          final target = _other(mode);
          final blocked = view.pendings.isNotEmpty;
          return Column(
            children: [
              header,
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    _CurrentCard(mode: mode, explain: !blocked),
                    const SizedBox(height: 12),
                    if (blocked)
                      _PendingList(
                        key: const Key('mode-blocked'),
                        pendings: view.pendings,
                        onOpen: _resolve,
                      )
                    else ...[
                      _TargetCard(target: target),
                      const SizedBox(height: 12),
                      Container(
                        key: const Key('mode-available'),
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE3F6A8),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.check, color: AgroColors.ink),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'El cambio está disponible. No borra ni '
                                'reasigna registros y no necesita conexión.',
                                style: TextStyle(
                                  fontSize: 16,
                                  height: 22 / 16,
                                  color: AgroColors.ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              BottomPanel(
                children: [
                  OutlinedButton(
                    key: const Key('mode-change'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                    ),
                    onPressed: _saving || blocked
                        ? null
                        : () => _change(target),
                    // Mientras guarda, el botón lo dice (y las pruebas lo
                    // distinguen de «bloqueado», que también lo inactiva).
                    child: _saving
                        ? const Text('Cambiando…', key: Key('mode-saving'))
                        : Text(
                            target == OperationMode.personal
                                ? 'Pasar a modo individual'
                                : 'Pasar a varias personas',
                          ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    blocked
                        ? 'Se activará cuando no queden pendientes.'
                        : 'Antes de cambiar se le pedirá confirmar.',
                    key: const Key('mode-change-hint'),
                    textAlign: TextAlign.center,
                    style: AgroText.detail,
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

class _CurrentCard extends StatelessWidget {
  const _CurrentCard({required this.mode, required this.explain});

  final OperationMode mode;
  final bool explain;

  @override
  Widget build(BuildContext context) => Material(
    color: AgroColors.ink,
    borderRadius: BorderRadius.circular(28),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StatusBadge(label: 'En uso', tone: BadgeTone.ok),
          const SizedBox(height: 10),
          Text(
            operationModeTitle(mode),
            key: const Key('mode-current'),
            style: AgroText.h1.copyWith(color: Colors.white),
          ),
          if (explain) ...[
            const SizedBox(height: 8),
            Text(
              operationModeExplanation(mode),
              key: const Key('mode-current-explanation'),
              style: const TextStyle(
                fontSize: 16,
                height: 22 / 16,
                color: AgroColors.onInkMuted,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _TargetCard extends StatelessWidget {
  const _TargetCard({required this.target});

  final OperationMode target;

  @override
  Widget build(BuildContext context) => Material(
    color: AgroColors.surface,
    borderRadius: BorderRadius.circular(28),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(operationModeTitle(target), style: AgroText.h2),
          const SizedBox(height: 8),
          Text(
            operationModeExplanation(target),
            key: const Key('mode-target-explanation'),
            style: AgroText.detail,
          ),
          const SizedBox(height: 12),
          const Text(
            'Si cambia:',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AgroColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            operationModeConsequence(target),
            key: const Key('mode-target-consequence'),
            style: AgroText.detail,
          ),
        ],
      ),
    ),
  );
}

class _PendingList extends StatelessWidget {
  const _PendingList({super.key, required this.pendings, required this.onOpen});

  final List<ModePending> pendings;
  final void Function(ModePending pending) onOpen;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(4, 8, 4, 6),
        child: Text(
          'Todavía no se puede pasar a modo individual',
          style: AgroText.h2,
        ),
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
        child: Text(
          'Primero resuelva estos pendientes. No se borra ni se reasigna '
          'nada.',
          style: AgroText.detail,
        ),
      ),
      AgroGroup(
        children: [
          for (final pending in pendings)
            InkWell(
              onTap: () => onOpen(pending),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: AgroColors.caution,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pending.title,
                            style: const TextStyle(
                              fontSize: 16,
                              height: 21 / 16,
                              fontWeight: FontWeight.w700,
                              color: AgroColors.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(pending.detail, style: AgroText.detail),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: AgroColors.muted),
                  ],
                ),
              ),
            ),
        ],
      ),
    ],
  );
}
