import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/installation_access.dart';
import '../../installation_access.dart';
import '../../services/auth/local_owner_credential.dart';
import '../../services/auth/local_owner_credential_providers.dart';
import '../widgets/agro_ui.dart';

/// Configuración opcional del PIN desde Ajustes y datos.
class OwnerCredentialScreen extends ConsumerStatefulWidget {
  const OwnerCredentialScreen({super.key});

  @override
  ConsumerState<OwnerCredentialScreen> createState() =>
      _OwnerCredentialScreenState();
}

class _OwnerCredentialScreenState extends ConsumerState<OwnerCredentialScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _pin = TextEditingController();
  final _pinConfirmation = TextEditingController();
  OnlineOwnerProof? _proof;
  OwnerBindingContext? _binding;
  bool _busy = false;
  String? _message;
  bool _done = false;

  @override
  void dispose() {
    for (final c in [_email, _password, _pin, _pinConfirmation]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _verifyOnline() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final binding = await ref.read(ownerBindingContextReaderProvider)();
      if (!mounted) return;
      if (binding == null) {
        setState(
          () => _message = 'No hay un titular vinculado en este teléfono.',
        );
        return;
      }
      final proof = await ref
          .read(ownerOnlineVerificationProvider)
          .verify(
            email: _email.text.trim(),
            password: _password.text,
            binding: binding,
          );
      if (!mounted) return;
      setState(() {
        _binding = binding;
        _proof = proof;
        _message = proof == null
            ? 'No se pudo acreditar al titular en línea. Revise la cuenta, la '
                  'contraseña y la conexión, o espere un momento si el teléfono '
                  'se está sincronizando, y vuelva a intentarlo.'
            : null;
      });
    } finally {
      if (mounted) {
        _password.clear();
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _enroll() async {
    final binding = _binding;
    if (_busy || _proof == null || binding == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final current = await ref.read(ownerBindingContextReaderProvider)();
      if (!mounted) return;
      if (!_sameOwner(binding, current)) {
        setState(() {
          _proof = null;
          _binding = null;
          _message = 'Cambió el titular. Confirme la cuenta nuevamente.';
        });
        return;
      }
      await ref
          .read(localOwnerCredentialProvider)
          .enroll(
            pin: _pin.text,
            pinConfirmation: _pinConfirmation.text,
            proof: _proof,
            binding: binding,
          );
      if (!mounted) return;
      setState(() {
        _done = true;
        _message = 'PIN del titular configurado. Funciona sin conexión.';
      });
    } on CredentialException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } finally {
      if (mounted) {
        _pin.clear();
        _pinConfirmation.clear();
        setState(() => _busy = false);
      }
    }
  }

  /// Vía (b): la forma y la igualdad del PIN se comprueban antes de tocar la
  /// acreditación, para que un error de tecleo no la gaste.
  void _leave() {
    if (_busy) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  Widget _pinField(TextEditingController c, String label, Key key) => TextField(
    key: key,
    controller: c,
    enabled: !_busy,
    obscureText: true,
    keyboardType: TextInputType.number,
    maxLength: 6,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    enableSuggestions: false,
    autocorrect: false,
    decoration: InputDecoration(labelText: label, counterText: ''),
  );

  @override
  Widget build(BuildContext context) {
    final activated =
        ref.watch(installationAccessProvider) ==
        InstallationAccessState.activated;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: const AgroAppBar(title: 'PIN del titular'),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              AgroGroup(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Configurar un PIN es opcional. Le permite autorizar sin conexión las '
                      'acciones que sólo la persona titular puede aprobar: revertir una '
                      'operación o revisar una operación tardía. Si no configura un PIN, puede '
                      'usar la contraseña de su cuenta con conexión. El PIN no se guarda en el '
                      'respaldo y no sirve para descifrar copias: la clave de '
                      'recuperación del respaldo es otra.',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              AgroGroup(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!activated)
                          const Text(
                            'Para configurar o restablecer el PIN, la instalación debe '
                            'estar activada con la sesión del titular disponible.',
                            key: Key('pin-requires-activated'),
                          )
                        else if (_done)
                          Text(_message ?? '', key: const Key('pin-done'))
                        else if (_proof == null) ...[
                          const Text(
                            'Primero confirme la cuenta del titular en línea.',
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            key: const Key('pin-email'),
                            controller: _email,
                            enabled: !_busy,
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: const InputDecoration(
                              labelText: 'Correo',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            key: const Key('pin-password'),
                            controller: _password,
                            enabled: !_busy,
                            obscureText: true,
                            enableSuggestions: false,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              labelText: 'Contraseña',
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            key: const Key('pin-verify-online'),
                            onPressed: _busy ? null : _verifyOnline,
                            child: const Text('Confirmar en línea'),
                          ),
                        ] else ...[
                          const Text(
                            'Elija un PIN de 6 dígitos que no sea una secuencia.',
                          ),
                          const SizedBox(height: 12),
                          _pinField(_pin, 'PIN', const Key('pin-new')),
                          const SizedBox(height: 12),
                          _pinField(
                            _pinConfirmation,
                            'Repita el PIN',
                            const Key('pin-confirm'),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            key: const Key('pin-save'),
                            onPressed: _busy ? null : _enroll,
                            child: const Text('Guardar PIN'),
                          ),
                        ],
                        if (_busy) const LinearProgressIndicator(),
                        if (_message != null && !_done) ...[
                          const SizedBox(height: 12),
                          Text(_message!, key: const Key('pin-message')),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextButton(
                key: const Key('pin-back'),
                onPressed: _busy ? null : _leave,
                child: const Text('Volver'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _sameOwner(OwnerBindingContext binding, OwnerBindingContext? current) =>
    current?.bindingId == binding.bindingId &&
    current?.personId == binding.personId &&
    current?.scope == binding.scope;

/// Solicita una autorización para la operación con el método de este titular.
Future<OwnerAuthorization?> requestOwnerAuthorization(
  BuildContext context,
  WidgetRef ref, {
  required AuthorizationPurpose purpose,
  required String subjectRef,
  required String title,
  required String effects,
  Future<String?> Function()? revalidate,
}) async {
  final readBinding = ref.read(ownerBindingContextReaderProvider);
  final binding = await readBinding();
  if (!context.mounted) return null;
  if (binding == null) {
    await _showAuthorizationUnavailable(
      context,
      title,
      'Para autorizar esta acción, active la aplicación y elija al titular.',
    );
    return null;
  }
  final credential = ref.read(localOwnerCredentialProvider);
  final status = await credential.status(binding);
  if (!context.mounted) return null;
  final blocked = switch (status.state) {
    CredentialState.locked =>
      'Demasiados intentos. Espere antes de volver a intentarlo.',
    CredentialState.requiresOnlineReset => 'El PIN quedó bloqueado. Restablézcalo en Ajustes y datos › PIN del titular.',
    CredentialState.unreadable => 'No se pudo leer el PIN. Restablézcalo en Ajustes y datos › PIN del titular.',
    _ => null,
  };
  if (blocked != null) {
    await _showAuthorizationUnavailable(context, title, blocked);
    return null;
  }
  final usePin = status.canVerify;
  return showDialog<OwnerAuthorization>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _OwnerAuthorizationDialog(
      title: title,
      effects: effects,
      usePin: usePin,
      onVerify: (email, secret) async {
        if (usePin) {
          return credential.verify(
            pin: secret,
            purpose: purpose,
            subjectRef: subjectRef,
            binding: binding,
          );
        }

        final authorization = await credential.authorizeWithPassword(
          email: email,
          password: secret,
          purpose: purpose,
          subjectRef: subjectRef,
          binding: binding,
        );
        final current = await readBinding();
        if (!_sameOwner(binding, current)) {
          throw const CredentialException(
            'Cambió el titular. Abra la operación de nuevo.',
          );
        }
        final String? stale;
        try {
          stale = await revalidate?.call();
        } on Object {
          throw const CredentialException(
            'No se pudo comprobar el estado de la operación. Vuelva a intentarlo.',
          );
        }
        if (stale != null) {
          throw CredentialException('No se puede continuar: $stale.');
        }
        return authorization;
      },
    ),
  );
}

Future<void> _showAuthorizationUnavailable(
  BuildContext context,
  String title,
  String message,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(title),
    content: Text(message),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Volver'),
      ),
    ],
  ),
);

class _OwnerAuthorizationDialog extends StatefulWidget {
  const _OwnerAuthorizationDialog({
    required this.title,
    required this.effects,
    required this.onVerify,
    required this.usePin,
  });

  final String title;
  final String effects;
  final bool usePin;
  final Future<OwnerAuthorization> Function(String email, String secret)
  onVerify;

  @override
  State<_OwnerAuthorizationDialog> createState() =>
      _OwnerAuthorizationDialogState();
}

class _OwnerAuthorizationDialogState extends State<_OwnerAuthorizationDialog> {
  final _email = TextEditingController();
  final _secret = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _secret.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!widget.usePin &&
        (_email.text.trim().isEmpty || _secret.text.isEmpty)) {
      setState(() => _error = 'Ingrese el correo y la contraseña del titular.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final authorization = await widget.onVerify(
        _email.text.trim(),
        _secret.text,
      );
      if (mounted) Navigator.pop(context, authorization);
    } on CredentialException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) {
        setState(() => _error = 'No se pudo autorizar. Vuelva a intentarlo.');
      }
    } finally {
      if (mounted) _secret.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.effects, key: const Key('owner-pin-effects')),
          const SizedBox(height: 12),
          if (!widget.usePin) ...[
            const Text(
              'Para autorizar con su cuenta necesita conexión a internet.',
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('owner-account-email'),
              controller: _email,
              enabled: !_busy,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Correo del titular',
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            key: Key(
              widget.usePin ? 'owner-pin-input' : 'owner-account-password',
            ),
            controller: _secret,
            enabled: !_busy,
            autofocus: widget.usePin,
            obscureText: true,
            keyboardType: widget.usePin
                ? TextInputType.number
                : TextInputType.visiblePassword,
            maxLength: widget.usePin ? 6 : null,
            inputFormatters: widget.usePin
                ? [FilteringTextInputFormatter.digitsOnly]
                : null,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: widget.usePin
                  ? 'PIN del titular'
                  : 'Contraseña de la cuenta',
              counterText: '',
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null)
            Text(_error!, key: const Key('owner-authorization-error')),
          if (_busy) const LinearProgressIndicator(),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: Key(widget.usePin ? 'owner-pin-submit' : 'owner-account-submit'),
        onPressed: _busy ? null : _submit,
        child: const Text('Autorizar'),
      ),
    ],
  );
}
