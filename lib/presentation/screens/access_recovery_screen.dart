import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../installation_access.dart';
import '../../services/auth/access_recovery.dart';
import '../../services/auth/existing_session_providers.dart';
import '../../services/auth/first_activation_coordinator.dart';

/// F03 «Recuperar acceso» (docs/architecture/F03_RECUPERACION_IDENTIDAD_LOCAL.md
/// §2). La acción depende del estado: entrar como el titular, rehacer sólo la
/// sesión o salir de una sesión ajena. Ningún camino borra datos locales.
class AccessRecoveryScreen extends ConsumerStatefulWidget {
  const AccessRecoveryScreen({super.key});

  @override
  ConsumerState<AccessRecoveryScreen> createState() =>
      _AccessRecoveryScreenState();
}

class _AccessRecoveryScreenState extends ConsumerState<AccessRecoveryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;
  String? _message;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _leave() {
    final canOperate =
        ref.read(installationAccessProvider)?.allowsFarmerOperations ?? false;
    context.go(canOperate ? '/' : '/acceso');
  }

  Future<void> _recover() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _message = null;
    });
    try {
      final result = await ref
          .read(accessRecoveryProvider.notifier)
          .recover(email: _email.text.trim(), password: _password.text);
      if (!mounted) return;
      if (result.isCompleted) {
        _leave();
        return;
      }
      setState(() => _message = result.safeMessage);
    } finally {
      _password.clear();
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _signOut() async {
    if (_submitting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Salir de esta sesión'),
        content: const Text(
          'Se cierra la sesión de la cuenta que no es la del titular. Los datos '
          'de este teléfono no cambian y no se habilitan para esa cuenta. '
          'Después podrá entrar con la cuenta del titular.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('recovery-signout-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Salir de la sesión'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _submitting = true;
      _message = null;
    });
    try {
      final result = await signOutForeignSession(ref);
      if (!mounted) return;
      setState(
        () => _message = switch (result.outcome) {
          ForeignSignOutOutcome.signedOut =>
            result.remoteConfirmed
                ? 'Sesión cerrada. Ahora puede entrar con la cuenta del titular.'
                : 'Sesión cerrada en este teléfono. El servidor no confirmó el '
                      'cierre; caducará sola. Ahora puede entrar con la cuenta '
                      'del titular.',
          ForeignSignOutOutcome.nothingToSignOut =>
            'No hay una sesión legible que cerrar. No se cambió nada.',
          ForeignSignOutOutcome.deletionUncertain =>
            'No se pudo confirmar el cierre en este teléfono. No se cambió '
                'ningún dato; reintente.',
        },
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = accessRecoveryModeFor(
      ref.watch(installationAccessProvider),
      ref.watch(effectiveLocalSessionProvider),
    );
    final activation = ref.watch(accessRecoveryProvider);
    final cancellable =
        _submitting &&
        activation.phase != FirstActivationPhase.committingSession &&
        activation.phase != FirstActivationPhase.cancelling;
    final intro = switch (mode) {
      AccessRecoveryMode.signInAsOwner =>
        'Entre con la cuenta del titular de estos datos. Sus datos locales, '
            'titulares y pendientes se conservan. Si entra con otra cuenta no '
            'se guarda nada.',
      AccessRecoveryMode.rebuildSessionOnly =>
        'La sesión guardada no se puede leer y la activación no terminó. Entre '
            'con su cuenta para rehacer sólo la sesión; después deberá elegir el '
            'titular. No se borra ningún dato.',
      AccessRecoveryMode.signOutForeignSession =>
        'La sesión de este teléfono es de otra cuenta. Salga de ella para entrar '
            'con la del titular. Los datos no cambian.',
      AccessRecoveryMode.storageUnavailable =>
        'El almacenamiento seguro no está disponible ahora. No se cambió nada; '
            'reintente más tarde.',
      AccessRecoveryMode.none =>
        'En este estado no hace falta recuperar el acceso desde aquí.',
    };
    final signIn =
        mode == AccessRecoveryMode.signInAsOwner ||
        mode == AccessRecoveryMode.rebuildSessionOnly;
    return Scaffold(
      appBar: AppBar(title: const Text('Recuperar acceso')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Icon(Icons.key_outlined, size: 54),
                const SizedBox(height: 16),
                Text(
                  intro,
                  key: const Key('recovery-intro'),
                  textAlign: TextAlign.center,
                ),
                if (signIn) ...[
                  const SizedBox(height: 20),
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          key: const Key('recovery-email'),
                          controller: _email,
                          enabled: !_submitting,
                          keyboardType: TextInputType.emailAddress,
                          textCapitalization: TextCapitalization.none,
                          autocorrect: false,
                          enableSuggestions: false,
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
                          key: const Key('recovery-password'),
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
                  FilledButton(
                    key: const Key('recovery-submit'),
                    onPressed: _submitting ? null : _recover,
                    child: const Text('Recuperar acceso'),
                  ),
                  if (cancellable)
                    TextButton(
                      key: const Key('recovery-cancel'),
                      onPressed: () => ref
                          .read(accessRecoveryProvider.notifier)
                          .requestCancel(),
                      child: const Text('Cancelar'),
                    ),
                ],
                if (mode == AccessRecoveryMode.signOutForeignSession) ...[
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    key: const Key('recovery-signout'),
                    onPressed: _submitting ? null : _signOut,
                    icon: const Icon(Icons.logout),
                    label: const Text('Salir de esta sesión'),
                  ),
                ],
                if (mode == AccessRecoveryMode.storageUnavailable)
                  TextButton(
                    key: const Key('recovery-retry'),
                    onPressed: () =>
                        ref.read(installationAccessProvider.notifier).refresh(),
                    child: const Text('Reintentar'),
                  ),
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _message!,
                    key: const Key('recovery-message'),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('recovery-leave'),
                  onPressed: _submitting ? null : _leave,
                  child: const Text('Volver'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
