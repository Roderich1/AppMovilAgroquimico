import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../data/operation_mode_store.dart';
import '../../data/owner_binding_store.dart';
import '../../domain/installation_access.dart' show InstallationAccessState;
import '../../domain/operation_mode.dart';
import '../../domain/person_roles.dart';
import '../../installation_access.dart';
import '../../operation_mode_controller.dart';
import '../../services/auth/first_activation_providers.dart';
import '../../services/auth/local_owner_credential.dart';
import '../../services/auth/local_owner_credential_providers.dart';
import '../widgets/common.dart';
import 'operation_mode_screen.dart' show operationModeExplanation;

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

  // F03 §4 bis: el controlador se guarda al entrar para anular la acreditación
  // de activación si se sale sin vincular, sin usar `ref` en dispose (H9).
  FirstActivationController? _activation;
  bool _bound = false;

  FirstActivationController? _activationController() {
    try {
      return ref.exists(firstActivationProvider)
          ? ref.read(firstActivationProvider.notifier)
          : null;
    } on Object {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _activation = _activationController();
  }

  @override
  void dispose() {
    if (!_bound) _activation?.discardActivationEvidence();
    _newName.dispose();
    super.dispose();
  }

  /// F03 §4 bis.2, paso 2: ata la acreditación al vínculo recién creado, sólo
  /// en la secuencia activationPendingOwner → activated. Debe llamarse antes
  /// de recalcular el acceso.
  bool _attachActivation(
    InstallationAccessState accessBefore,
    OwnerBinding binding,
  ) {
    final activation = _activationController();
    if (activation == null) return false;
    if (accessBefore != InstallationAccessState.activationPendingOwner) {
      activation.discardActivationEvidence();
      return false;
    }
    return activation.attachOwnerBinding(activationBindingRefOf(binding));
  }

  /// La oferta del PIN: acceso `activated` y un titular sin PIN propio en el
  /// teléfono (notEnrolled o scopeMismatch). Si `status()` lanza, no hay
  /// oferta (H8). Si no hay oferta, la acreditación se anula.
  Future<bool> _pinOffer(OwnerBinding binding) async {
    final activation = _activationController();
    if (activation == null || !activation.hasActivationEvidence) return false;
    try {
      if (ref.read(installationAccessProvider) ==
          InstallationAccessState.activated) {
        final status = await ref
            .read(localOwnerCredentialProvider)
            .status(
              OwnerBindingContext(
                bindingId: binding.id,
                personId: binding.personId,
                scope: binding.scope,
              ),
            );
        if ((status.state == CredentialState.notEnrolled ||
                status.state == CredentialState.scopeMismatch) &&
            activation.hasActivationEvidence) {
          return true;
        }
      }
    } on Object {
      // Sin estado legible no se ofrece nada.
    }
    activation.discardActivationEvidence();
    return false;
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
    final database = ref.read(repositoryProvider).appDatabase;
    final store = OwnerBindingStore(database);
    try {
      final OwnerBinding binding;
      if (_createNew) {
        binding = await store.bindNewPerson(
          name: _newName.text,
          scope: scope,
          installationRef: installationRef,
        );
      } else {
        binding = await store.bindExistingPerson(
          personId: _selected!,
          scope: scope,
          installationRef: installationRef,
          confirmAdministrator:
              _selectedIsAdministrator && _administratorConfirmed,
        );
      }
      _bound = true;
      final attached = _attachActivation(access, binding);
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
      await ref.read(operationModeProvider.notifier).reload();
      if (!mounted) return;
      final offer = attached && await _pinOffer(binding);
      if (!mounted) return;
      if (offer) {
        // F03 §4 bis.2, paso 3: el aviso de modalidad va en la oferta.
        context.go(
          '/titular/pin/activacion',
          extra:
              modeNotice ??
              (_mode == OperationMode.personal
                  ? 'Usa inventario propio; puede cambiarlo en Operaciones › '
                        'Más › Modo de uso.'
                  : 'Usa inventario compartido; puede cambiarlo en '
                        'Operaciones › Más › Modo de uso.'),
        );
        return;
      }
      showSuccess(
        context,
        modeNotice ??
            (_mode == OperationMode.personal
                ? 'Titular vinculado. Usa inventario propio; puede cambiarlo '
                      'en Operaciones › Más › Modo de uso.'
                : 'Titular vinculado. Usa inventario compartido; puede '
                      'cambiarlo en Operaciones › Más › Modo de uso.'),
      );
      context.go('/');
    } on Object catch (error) {
      // Un error en el paso 2 anula la acreditación de activación.
      _activationController()?.discardActivationEvidence();
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
                'Elija la persona que es el agricultor dueño de estos '
                'registros. Sólo se vincula con su cuenta del sindicato; no se '
                'cambia el rol de ninguna persona.',
              ),
              const SizedBox(height: 16),
              RadioGroup<int>(
                groupValue: _createNew ? -1 : _selected,
                onChanged: (value) => setState(() {
                  _createNew = value == -1;
                  _selected = value == -1 ? null : value;
                  _selectedIsAdministrator = candidates.any(
                    (person) =>
                        person['id'] == _selected &&
                        _eligibility(person) ==
                            OwnerEligibility.requiresAdministratorConfirmation,
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
                                'Administrador de pagos (rol de estos '
                                'registros, no del sindicato)',
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
                  onChanged: (value) =>
                      setState(() => _administratorConfirmed = value ?? false),
                  title: const Text(
                    'Confirmo que esta persona es el agricultor titular',
                  ),
                  subtitle: const Text(
                    'Conserva su rol de administrador de pagos: sigue pagando a '
                    'los proveedores, no se le cargan consumos y no entra en la '
                    'liquidación. No se crea otra persona ni se mueve ningún '
                    'registro.',
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
              const Text(
                'Elija cómo se registra el inventario en este teléfono. Podrá '
                'cambiarlo después en Operaciones › Más › Modo de uso, sin perder '
                'registros y sin conexión.',
                key: Key('owner-mode-help'),
              ),
              RadioGroup<OperationMode>(
                groupValue: _mode,
                onChanged: (value) =>
                    setState(() => _mode = value ?? OperationMode.shared),
                child: Column(
                  children: [
                    RadioListTile<OperationMode>(
                      key: const Key('owner-mode-shared'),
                      value: OperationMode.shared,
                      title: const Text('Compartido'),
                      subtitle: Text(
                        operationModeExplanation(OperationMode.shared),
                      ),
                    ),
                    RadioListTile<OperationMode>(
                      key: const Key('owner-mode-personal'),
                      value: OperationMode.personal,
                      title: const Text('Propio'),
                      subtitle: Text(
                        operationModeExplanation(OperationMode.personal),
                      ),
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
