import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/installation_access.dart';
import '../../installation_access.dart';
import '../../services/auth/local_owner_credential.dart';
import '../../services/auth/local_owner_credential_providers.dart';

/// Configurar o restablecer el PIN del titular (F03 §4). Exige acreditar en
/// línea al mismo titular; restablecer el PIN no recupera ni descifra copias
/// de respaldo (la clave del respaldo es otra cosa).
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
                  'contraseña y la conexión.'
            : null;
      });
    } finally {
      _password.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enroll() async {
    if (_busy || _proof == null || _binding == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref
          .read(localOwnerCredentialProvider)
          .enroll(
            pin: _pin.text,
            pinConfirmation: _pinConfirmation.text,
            proof: _proof,
            binding: _binding!,
          );
      if (!mounted) return;
      setState(() {
        _done = true;
        _message = 'PIN del titular configurado. Funciona sin conexión.';
      });
    } on CredentialException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } finally {
      _pin.clear();
      _pinConfirmation.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activated =
        ref.watch(installationAccessProvider) ==
        InstallationAccessState.activated;
    Widget pinField(TextEditingController c, String label, Key key) =>
        TextField(
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
    return Scaffold(
      appBar: AppBar(title: const Text('PIN del titular')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'El PIN autoriza en este teléfono, incluso sin conexión, las '
              'acciones que sólo puede aprobar el titular: revertir una '
              'operación o revisar una operación tardía. No se guarda en el '
              'respaldo y no sirve para descifrar copias: la clave de '
              'recuperación del respaldo es otra.',
            ),
            const SizedBox(height: 16),
            if (!activated)
              const Text(
                'Para configurar o restablecer el PIN, la instalación debe '
                'estar activada con la sesión del titular disponible.',
                key: Key('pin-requires-activated'),
              )
            else if (_done)
              Text(_message ?? '', key: const Key('pin-done'))
            else if (_proof == null) ...[
              const Text('Primero confirme la cuenta del titular en línea.'),
              const SizedBox(height: 12),
              TextField(
                key: const Key('pin-email'),
                controller: _email,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                textCapitalization: TextCapitalization.none,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: 'Correo'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('pin-password'),
                controller: _password,
                enabled: !_busy,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Contraseña'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('pin-verify-online'),
                onPressed: _busy ? null : _verifyOnline,
                child: const Text('Confirmar en línea'),
              ),
            ] else ...[
              const Text('Elija un PIN de 6 dígitos que no sea una secuencia.'),
              const SizedBox(height: 12),
              pinField(_pin, 'PIN', const Key('pin-new')),
              const SizedBox(height: 12),
              pinField(
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
            TextButton(
              onPressed: _busy ? null : () => context.pop(),
              child: const Text('Volver'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pide el PIN del titular para una acción concreta y devuelve la autorización
/// de un solo uso, o null si se cancela. [effects] describe lo que hará la
/// acción; [reasonHint] no se usa aquí (el motivo lo pide la pantalla de la
/// acción). Si el PIN no está configurado, ofrece configurarlo.
Future<OwnerAuthorization?> requestOwnerAuthorization(
  BuildContext context,
  WidgetRef ref, {
  required AuthorizationPurpose purpose,
  required String subjectRef,
  required String title,
  required String effects,
}) async {
  final binding = await ref.read(ownerBindingContextReaderProvider)();
  if (!context.mounted) return null;
  final credential = ref.read(localOwnerCredentialProvider);
  final status = await credential.status(binding);
  if (!context.mounted) return null;
  if (binding == null || !status.canVerify) {
    final message = switch (status.state) {
      CredentialState.locked =>
        'Demasiados intentos. Espere antes de volver a intentarlo.',
      CredentialState.requiresOnlineReset => 'El PIN quedó bloqueado. Restablézcalo acreditando al titular en línea.',
      _ =>
        'Esta acción la autoriza sólo el titular con su PIN. Configure el PIN '
            'del titular primero.',
    };
    final configure = status.state != CredentialState.locked;
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message, key: const Key('owner-pin-unavailable')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cerrar'),
          ),
          if (configure)
            FilledButton(
              key: const Key('owner-pin-configure'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Configurar PIN'),
            ),
        ],
      ),
    );
    if (open == true && context.mounted) context.push('/titular/pin');
    return null;
  }
  return showDialog<OwnerAuthorization>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _OwnerPinDialog(
      title: title,
      effects: effects,
      onVerify: (pin) => credential.verify(
        pin: pin,
        purpose: purpose,
        subjectRef: subjectRef,
        binding: binding,
      ),
    ),
  );
}

class _OwnerPinDialog extends StatefulWidget {
  const _OwnerPinDialog({
    required this.title,
    required this.effects,
    required this.onVerify,
  });

  final String title;
  final String effects;
  final Future<OwnerAuthorization> Function(String pin) onVerify;

  @override
  State<_OwnerPinDialog> createState() => _OwnerPinDialogState();
}

class _OwnerPinDialogState extends State<_OwnerPinDialog> {
  final _pin = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final authorization = await widget.onVerify(_pin.text);
      if (mounted) Navigator.pop(context, authorization);
    } on CredentialException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      _pin.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.effects, key: const Key('owner-pin-effects')),
        const SizedBox(height: 12),
        TextField(
          key: const Key('owner-pin-input'),
          controller: _pin,
          enabled: !_busy,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          enableSuggestions: false,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'PIN del titular',
            counterText: '',
          ),
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null) Text(_error!, key: const Key('owner-pin-error')),
        if (_busy) const LinearProgressIndicator(),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const Key('owner-pin-submit'),
        onPressed: _busy ? null : _submit,
        child: const Text('Autorizar'),
      ),
    ],
  );
}
