import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../data/operation_mode_store.dart';
import '../../domain/operation_mode.dart';
import '../widgets/common.dart';

/// Modo de uso (MODE-04, CU-05): consulta, consecuencias y confirmación.
/// Las reglas viven en [OperationModeStore]; esta pantalla sólo las muestra.
class OperationModeScreen extends ConsumerStatefulWidget {
  const OperationModeScreen({super.key});

  @override
  ConsumerState<OperationModeScreen> createState() =>
      _OperationModeScreenState();
}

class _OperationModeScreenState extends ConsumerState<OperationModeScreen> {
  late Future<OperationMode> _current = _store.current();
  ModeTransitionDecision? _blocked;
  bool _saving = false;

  OperationModeStore get _store =>
      OperationModeStore(ref.read(repositoryProvider).appDatabase);

  Future<void> _change(OperationMode target) async {
    final decision = await _store.evaluate(target);
    if (!mounted) return;
    if (!decision.allowed) {
      setState(() => _blocked = decision);
      return;
    }
    final consequence = target == OperationMode.personal
        ? 'Sólo el titular registrará compras y aplicaciones, y no habrá '
              'transferencias. Los registros de otras personas se conservan.'
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
    setState(() => _saving = true);
    try {
      await _store.apply(target, confirmed: true);
      if (!mounted) return;
      showSuccess(context, 'Modalidad actualizada.');
      setState(() {
        _saving = false;
        _blocked = null;
        _current = _store.current();
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Modo de uso')),
    body: SafeArea(
      child: FutureBuilder<OperationMode>(
        future: _current,
        builder: (context, snapshot) {
          final mode = snapshot.data;
          if (mode == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final target = mode == OperationMode.shared
              ? OperationMode.personal
              : OperationMode.shared;
          final blocked = _blocked;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                mode == OperationMode.shared
                    ? 'Modalidad actual: inventario compartido'
                    : 'Modalidad actual: inventario propio',
                key: const Key('mode-current'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              if (blocked != null)
                Card(
                  key: const Key('mode-blocked'),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(_blockedText(blocked)),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('mode-change'),
                onPressed: _saving ? null : () => _change(target),
                child: Text(
                  target == OperationMode.personal
                      ? 'Cambiar a inventario propio'
                      : 'Cambiar a inventario compartido',
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

String _blockedText(ModeTransitionDecision decision) {
  if (decision.blocks.contains(ModeTransitionBlock.ownerRequired)) {
    return 'El inventario propio necesita un titular vinculado.';
  }
  final activity = decision.activity;
  return [
    'No se puede pasar a inventario propio todavía. Resuelva en modo '
        'compartido:',
    if (activity.personsWithStock.isNotEmpty)
      '• ${activity.personsWithStock.length} persona(s) con existencias',
    if (activity.openPlanIds.isNotEmpty)
      '• ${activity.openPlanIds.length} plan(es) abierto(s) en chacos de otras personas',
    if (activity.personsWithAccountBalance.isNotEmpty)
      '• ${activity.personsWithAccountBalance.length} persona(s) con saldo de cuenta',
    'No se borra ni se reasigna nada.',
  ].join('\n');
}
