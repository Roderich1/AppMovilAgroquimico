import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/installation_identity_initializer.dart';
import '../../services/auth/existing_session_providers.dart';
import '../../services/auth/first_activation_coordinator.dart';
import '../../services/auth/first_activation_providers.dart';

/// An explicit first-activation entry point. Existing-session startup belongs
/// to #21 and is intentionally not inferred from a stored credential here.
class FirstActivationScreen extends ConsumerStatefulWidget {
  const FirstActivationScreen({super.key});

  @override
  ConsumerState<FirstActivationScreen> createState() =>
      _FirstActivationScreenState();
}

class _FirstActivationScreenState extends ConsumerState<FirstActivationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;
  bool _navigated = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting ||
        _navigated ||
        !ref.read(existingSessionStartupProvider).allowsFirstActivation ||
        ref.read(firstActivationProvider).isCompleted ||
        !_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _submitting = true);
    final result = await ref
        .read(firstActivationProvider.notifier)
        .activate(email: _email.text.trim(), password: _password.text);
    if (!mounted) return;
    _password.clear();
    if (result.isCompleted && !_navigated) {
      _navigated = true;
      context.go('/');
      return;
    }
    setState(() => _submitting = false);
  }

  void _cancel() {
    ref.read(firstActivationProvider.notifier).requestCancel();
  }

  @override
  Widget build(BuildContext context) {
    final existingSession = ref.watch(existingSessionStartupProvider);
    if (!existingSession.allowsFirstActivation) {
      return Scaffold(
        appBar: AppBar(title: const Text('Activar cuenta')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.shield_outlined, size: 54),
                    const SizedBox(height: 16),
                    Text(
                      existingSession.safeMessage!,
                      key: const Key('existing-session-blocks-activation'),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () => context.go('/'),
                      child: const Text('Continuar con datos locales'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    final state = ref.watch(firstActivationProvider);
    if (state.isCompleted) {
      return Scaffold(
        appBar: AppBar(title: const Text('Activar cuenta')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.verified_user_outlined, size: 54),
                    const SizedBox(height: 16),
                    const Text(
                      'La activación de esta instalación ya se completó '
                      'durante esta ejecución. Puede continuar con sus datos locales.',
                      key: Key('activation-already-completed'),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () => context.go('/'),
                      child: const Text('Continuar con datos locales'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    final identity = ref.watch(installationIdentityProvider);
    final blockedByIdentity =
        identity.status != InstallationIdentityStatus.ready;
    final needsReconciliation =
        state.localCommitUnknown || state.remoteOutcomeUnknown;
    final busy = _submitting || _isBusy(state.phase);
    final canCancel =
        busy &&
        state.phase != FirstActivationPhase.cancelling &&
        state.phase != FirstActivationPhase.committingSession;
    final problem = blockedByIdentity
        ? (identity.status == InstallationIdentityStatus.corrupt
              ? FirstActivationProblem.identityCorrupt
              : FirstActivationProblem.identityUnavailable)
        : state.problem;

    return PopScope(
      canPop: !busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && canCancel) _cancel();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Activar cuenta')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const Icon(Icons.verified_user_outlined, size: 54),
                  const SizedBox(height: 16),
                  Text(
                    'Primera activación',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Vincule esta instalación con su cuenta. Sus datos locales '
                    'permanecen disponibles aunque la activación no finalice.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          key: const Key('activation-email'),
                          controller: _email,
                          enabled:
                              !busy &&
                              !blockedByIdentity &&
                              !needsReconciliation,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(
                            labelText: 'Correo',
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Ingrese su correo.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: const Key('activation-password'),
                          controller: _password,
                          enabled:
                              !busy &&
                              !blockedByIdentity &&
                              !needsReconciliation,
                          obscureText: true,
                          enableSuggestions: false,
                          autocorrect: false,
                          autofillHints: const [AutofillHints.password],
                          decoration: const InputDecoration(
                            labelText: 'Contraseña',
                          ),
                          validator: (value) => value == null || value.isEmpty
                              ? 'Ingrese su contraseña.'
                              : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (busy) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                    Text(_phaseLabel(state.phase), textAlign: TextAlign.center),
                  ],
                  if (problem != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      problem.safeMessage,
                      key: const Key('activation-error'),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (needsReconciliation) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'El resultado necesita revisión. No vuelva a activar '
                      'esta instalación hasta verificar el estado de la sesión.',
                      key: Key('activation-reconcile'),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    key: const Key('activation-submit'),
                    onPressed:
                        busy ||
                            blockedByIdentity ||
                            needsReconciliation ||
                            _navigated
                        ? null
                        : _submit,
                    child: const Text('Activar'),
                  ),
                  if (canCancel)
                    TextButton(
                      key: const Key('activation-cancel'),
                      onPressed: _cancel,
                      child: const Text('Cancelar activación'),
                    ),
                  if (!busy)
                    TextButton(
                      onPressed: () => context.go('/'),
                      child: const Text('Continuar con datos locales'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

bool _isBusy(FirstActivationPhase phase) => switch (phase) {
  FirstActivationPhase.checkingIdentity ||
  FirstActivationPhase.preparingClient ||
  FirstActivationPhase.loggingIn ||
  FirstActivationPhase.registeringClient ||
  FirstActivationPhase.bindingSession ||
  FirstActivationPhase.verifyingContext ||
  FirstActivationPhase.committingSession ||
  FirstActivationPhase.cancelling => true,
  _ => false,
};

String _phaseLabel(FirstActivationPhase phase) => switch (phase) {
  FirstActivationPhase.checkingIdentity => 'Verificando instalación…',
  FirstActivationPhase.preparingClient => 'Preparando conexión segura…',
  FirstActivationPhase.loggingIn => 'Verificando credenciales…',
  FirstActivationPhase.registeringClient => 'Registrando instalación…',
  FirstActivationPhase.bindingSession => 'Vinculando sesión…',
  FirstActivationPhase.verifyingContext => 'Verificando cuenta…',
  FirstActivationPhase.committingSession => 'Guardando sesión de forma segura…',
  FirstActivationPhase.cancelling => 'Cancelando activación…',
  _ => '',
};
