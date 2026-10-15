import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../data/operation_mode_store.dart';
import '../../data/owner_binding_store.dart';
import '../../domain/models.dart';
import '../../domain/operation_mode.dart';
import '../../installation_access.dart';
import '../widgets/common.dart';

/// Elección explícita del titular tras activar (criterio C, CU-01, CU-05).
///
/// El titular es la persona de la familia que representa al agricultor dueño
/// del ámbito local. No se deduce por nombre ni teléfono, no se cambia el rol
/// de nadie y nunca se elige solo.
class OwnerSetupScreen extends ConsumerStatefulWidget {
  const OwnerSetupScreen({super.key});

  @override
  ConsumerState<OwnerSetupScreen> createState() => _OwnerSetupScreenState();
}

class _OwnerSetupScreenState extends ConsumerState<OwnerSetupScreen> {
  late final Future<List<Map<String, Object?>>> _candidates = ref
      .read(repositoryProvider)
      .people()
      .then(
        (rows) =>
            rows.where((row) => row['role'] == PersonRole.family.code).toList(),
      );
  final _newName = TextEditingController();
  int? _selected;
  bool _createNew = false;
  OperationMode _mode = OperationMode.shared;
  bool _saving = false;

  @override
  void dispose() {
    _newName.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final access = ref.read(installationAccessProvider);
    final controller = ref.read(installationAccessProvider.notifier);
    final scope = controller.sessionScope;
    final installationRef = ref.read(installationRefProvider);
    if (access == null ||
        !access.allowsOwnerBinding ||
        scope == null ||
        installationRef == null) {
      showError(
        context,
        'Para elegir el titular hace falta una cuenta activada y legible.',
      );
      return;
    }
    if (!_createNew && _selected == null) {
      showError(context, 'Elija el titular o cree uno nuevo.');
      return;
    }
    setState(() => _saving = true);
    final database = ref.read(repositoryProvider).appDatabase;
    final store = OwnerBindingStore(database);
    try {
      if (_createNew) {
        await store.bindNewPerson(
          name: _newName.text,
          scope: scope,
          installationRef: installationRef,
        );
      } else {
        await store.bindExistingPerson(
          personId: _selected!,
          scope: scope,
          installationRef: installationRef,
        );
      }
      String? modeNotice;
      if (_mode == OperationMode.personal) {
        try {
          await OperationModeStore(database)
              .apply(OperationMode.personal, confirmed: true);
        } on ModeTransitionException catch (error) {
          modeNotice = '${error.message} Queda en inventario compartido.';
        }
      }
      await controller.refresh();
      if (!mounted) return;
      showSuccess(context, modeNotice ?? 'Titular vinculado.');
      context.go('/');
    } on Object catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        showError(context, error);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Titular de los datos')),
    body: SafeArea(
      child: FutureBuilder<List<Map<String, Object?>>>(
        future: _candidates,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final candidates = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Elija la persona de la familia que es el agricultor dueño de '
                'estos registros. Sólo se vincula con su cuenta del sindicato; '
                'no se cambia el rol de ninguna persona.',
              ),
              const SizedBox(height: 16),
              RadioGroup<int>(
                groupValue: _createNew ? -1 : _selected,
                onChanged: (value) => setState(() {
                  _createNew = value == -1;
                  _selected = value == -1 ? null : value;
                }),
                child: Column(
                  children: [
                    for (final person in candidates)
                      RadioListTile<int>(
                        key: Key('owner-candidate-${person['id']}'),
                        value: person['id']! as int,
                        title: Text(person['name']! as String),
                      ),
                    const RadioListTile<int>(
                      key: Key('owner-create-new'),
                      value: -1,
                      title: Text('Crear el titular'),
                    ),
                  ],
                ),
              ),
              if (_createNew)
                TextField(
                  key: const Key('owner-new-name'),
                  controller: _newName,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                ),
              const SizedBox(height: 20),
              Text(
                'Modalidad de inventario',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              RadioGroup<OperationMode>(
                groupValue: _mode,
                onChanged: (value) =>
                    setState(() => _mode = value ?? OperationMode.shared),
                child: const Column(
                  children: [
                    RadioListTile<OperationMode>(
                      key: Key('owner-mode-shared'),
                      value: OperationMode.shared,
                      title: Text('Compartido'),
                      subtitle: Text('Varios responsables y transferencias'),
                    ),
                    RadioListTile<OperationMode>(
                      key: Key('owner-mode-personal'),
                      value: OperationMode.personal,
                      title: Text('Propio'),
                      subtitle: Text('Sólo el titular registra'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('owner-confirm'),
                onPressed: _saving ? null : _confirm,
                child: const Text('Confirmar titular'),
              ),
            ],
          );
        },
      ),
    ),
  );
}
