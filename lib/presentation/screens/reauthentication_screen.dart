import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/auth/existing_session_providers.dart';
import '../../services/auth/existing_session_startup.dart';
import '../../services/auth/remote_session_coordinator.dart';
import '../../services/auth/remote_session_providers.dart';

/// Explicit reauthentication of the existing local binding, never activation.
class ReauthenticationScreen extends ConsumerStatefulWidget {
  const ReauthenticationScreen({super.key});

  @override
  ConsumerState<ReauthenticationScreen> createState() =>
      _ReauthenticationScreenState();
}

class _ReauthenticationScreenState
    extends ConsumerState<ReauthenticationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final result = await ref
          .read(remoteSessionProvider.notifier)
          .reauthenticate(email: _email.text.trim(), password: _password.text);
      if (!mounted) return;
      _password.clear();
      if (result.phase == RemoteSessionPhase.remoteAvailable) {
        context.go('/');
      }
    } finally {
      if (mounted) {
        _password.clear();
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = ref.watch(effectiveLocalSessionProvider);
    final canReauthenticate =
        local == ExistingSessionStartupState.localSessionAvailable ||
        local == ExistingSessionStartupState.localSessionExpired;
    final remote = ref.watch(remoteSessionProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Volver a autenticar')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Icon(Icons.lock_reset_outlined, size: 54),
                const SizedBox(height: 16),
                Text(
                  canReauthenticate
                      ? 'Verifique la misma cuenta para recuperar funciones en línea. Sus datos locales no cambian.'
                      : 'No hay una vinculación local legible para reautenticar. Sus datos locales siguen disponibles.',
                  textAlign: TextAlign.center,
                ),
                if (canReauthenticate) ...[
                  const SizedBox(height: 20),
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          key: const Key('reauth-email'),
                          controller: _email,
                          enabled: !_submitting,
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
                          key: const Key('reauth-password'),
                          controller: _password,
                          enabled: !_submitting,
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
                  const SizedBox(height: 16),
                  if (_submitting) const LinearProgressIndicator(),
                  Text(remote.safeMessage, key: const Key('reauth-status')),
                  if (remote.cleanupUnconfirmed)
                    const Text(
                      'La limpieza de la sesión remota nueva no pudo confirmarse.',
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('reauth-submit'),
                    onPressed:
                        _submitting ||
                            remote.phase == RemoteSessionPhase.outcomeUnknown
                        ? null
                        : _submit,
                    child: const Text('Volver a autenticar'),
                  ),
                ],
                TextButton(
                  onPressed: () => context.go('/'),
                  child: const Text('Continuar con datos locales'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
