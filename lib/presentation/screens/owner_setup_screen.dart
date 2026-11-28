import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../domain/operation_mode.dart';
import '../../domain/owner_binding_models.dart';
import '../../domain/person_roles.dart';
import '../../installation_access.dart';
import '../../operation_mode_controller.dart';
import '../widgets/agro_ui.dart';
import '../widgets/common.dart';
import 'operation_mode_screen.dart'
    show operationModeExplanation, operationModeTitle;

/// Elección explícita del titular tras activar (criterio C, CU-01, CU-05).
///
/// El titular es la persona local que representa al agricultor dueño del
/// ámbito. No se deduce por nombre ni teléfono, no se cambia el rol de nadie y
/// nunca se elige solo. El agricultor histórico registrado como administrador
/// de pagos (rol privado ADMIN, no el ADMINISTRADOR del sindicato) se ofrece
/// con una confirmación explícita: conserva su rol y sus movimientos.
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
        (rows) => [
          for (final row in rows)
            if (_eligibility(row) != OwnerEligibility.notEligible) row,
        ],
      );
  final _newName = TextEditingController();
  int? _selected;
  bool _selectedIsAdministrator = false;
  bool _administratorConfirmed = false;
  bool _createNew = false;

  static OwnerEligibility _eligibility(Map<String, Object?> person) {
    final role = personRoleFromCode(person['role']);
    return role == null ? OwnerEligibility.notEligible : ownerEligibility(role);
  }

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
    if (!_createNew && _selectedIsAdministrator && !_administratorConfirmed) {
      showError(context, OwnerAdministratorConfirmationRequired().message);
      return;
    }
    setState(() => _saving = true);
    final store = ref.read(ownerBindingGatewayProvider);
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
          confirmAdministrator:
              _selectedIsAdministrator && _administratorConfirmed,
        );
      }
      String? modeNotice;
      if (_mode == OperationMode.personal) {
        try {
          await ref
              .read(operationModeGatewayProvider)
              .apply(OperationMode.personal, confirmed: true);
        } on ModeTransitionException catch (error) {
          modeNotice = '${error.message} Queda en el modo con varias personas.';
        }
      }
      await controller.refresh();
      await ref.read(operationModeProvider.notifier).reload();
      if (!mounted) return;
      showSuccess(
        context,
        modeNotice ??
            (_mode == OperationMode.personal
                ? 'Titular vinculado. Usa el modo individual; puede cambiarlo '
                      'en Ajustes y datos › Modo de uso.'
                : 'Titular vinculado. Usa el modo con varias personas; puede '
                      'cambiarlo en Ajustes y datos › Modo de uso.'),
      );
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
    appBar: const AgroAppBar(title: 'Titular de los datos'),
    body: SafeArea(
      child: FutureBuilder<List<Map<String, Object?>>>(
        future: _candidates,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final candidates = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            children: [
              const Text(
                'Elija la persona que es el agricultor dueño de estos '
                'registros. Sólo se vincula con su cuenta del sindicato; no se '
                'cambia el rol de ninguna persona.',
              ),
              const SizedBox(height: 8),
              AgroGroup(
                children: [
                  RadioGroup<int>(
                    groupValue: _createNew ? -1 : _selected,
                    onChanged: (value) => setState(() {
                      _createNew = value == -1;
                      _selected = value == -1 ? null : value;
                      _selectedIsAdministrator = candidates.any(
                        (person) =>
                            person['id'] == _selected &&
                            _eligibility(person) ==
                                OwnerEligibility
                                    .requiresAdministratorConfirmation,
                      );
                      _administratorConfirmed = false;
                    }),
                    child: Column(
                      children: [
                        for (final person in candidates)
                          RadioListTile<int>(
                            key: Key('owner-candidate-${person['id']}'),
                            value: person['id']! as int,
                            title: Text(person['name']! as String),
                            subtitle:
                                _eligibility(person) ==
                                    OwnerEligibility
                                        .requiresAdministratorConfirmation
                                ? const Text(
                                    'Administrador · registro anterior',
                                  )
                                : null,
                          ),
                        const RadioListTile<int>(
                          key: Key('owner-create-new'),
                          value: -1,
                          title: Text('Crear el titular'),
                        ),
                      ],
                    ),
                  ),
                  if (!_createNew && _selectedIsAdministrator)
                    CheckboxListTile(
                      key: const Key('owner-confirm-administrator'),
                      value: _administratorConfirmed,
                      onChanged: (value) => setState(
                        () => _administratorConfirmed = value ?? false,
                      ),
                      title: const Text(
                        'Confirmo que esta persona es el agricultor titular',
                      ),
                      subtitle: const Text(
                        'Al vincularla, se mostrará como «Titular» y registrará los '
                        'pagos al proveedor. Se conservan sus movimientos y su '
                        'regla de liquidación.',
                      ),
                    ),
                  if (_createNew)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: TextField(
                        key: const Key('owner-new-name'),
                        controller: _newName,
                        decoration: const InputDecoration(labelText: 'Nombre'),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Modo de uso',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Text(
                'Elija cómo se registra el inventario en este teléfono. Podrá '
                'cambiarlo después en Ajustes y datos › Modo de uso, sin perder '
                'registros y sin conexión.',
                key: Key('owner-mode-help'),
              ),
              const SizedBox(height: 6),
              AgroGroup(
                children: [
                  RadioGroup<OperationMode>(
                    groupValue: _mode,
                    onChanged: (value) =>
                        setState(() => _mode = value ?? OperationMode.shared),
                    child: Column(
                      children: [
                        RadioListTile<OperationMode>(
                          key: const Key('owner-mode-shared'),
                          value: OperationMode.shared,
                          title: Text(operationModeTitle(OperationMode.shared)),
                          subtitle: Text(
                            operationModeExplanation(OperationMode.shared),
                          ),
                        ),
                        RadioListTile<OperationMode>(
                          key: const Key('owner-mode-personal'),
                          value: OperationMode.personal,
                          title: Text(
                            operationModeTitle(OperationMode.personal),
                          ),
                          subtitle: Text(
                            operationModeExplanation(OperationMode.personal),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
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
