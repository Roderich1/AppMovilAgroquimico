import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/installation_access.dart';
import '../../installation_access.dart';
import '../../services/auth/first_activation_providers.dart';
import '../../services/auth/local_owner_credential.dart';
import '../../services/auth/local_owner_credential_providers.dart';
import '../widgets/common.dart';

/// Textos del enrolamiento dentro de la activación (F03 §4 bis.2).
abstract final class ActivationPinTexts {
  static const offer =
      'Le recomendamos crear ahora el PIN del titular. Con él, el titular '
      'autoriza en este teléfono, incluso sin conexión, las acciones que sólo '
      'él puede aprobar: revertir una operación o revisar una operación '
      'tardía.';
  static const whyNow =
      'Acaba de confirmar su cuenta en línea, así que ahora no hace falta '
      'volver a escribir la contraseña. Si lo deja para después, tendrá que '
      'confirmar la cuenta en línea con su correo y su contraseña.';
  static const separation =
      'El PIN no se guarda en el respaldo y no sirve para descifrar copias: la '
      'clave de recuperación del respaldo es otra. Tampoco reemplaza la '
      'contraseña de su cuenta.';
  static const form = 'Elija un PIN de 6 dígitos que no sea una secuencia.';
  static const done = 'PIN del titular creado. Funciona sin conexión.';
  static const skipped =
      'Puede crear el PIN más tarde en Operaciones › Más › PIN del titular. '
      'Entonces se le pedirá confirmar su cuenta en línea.';
  static const expired =
      'Ya no se puede crear el PIN con la confirmación de la activación: pasó '
      'el tiempo, salió de la aplicación o cambió la cuenta, la instalación o '
      'el titular. Puede crearlo más tarde en Operaciones › Más › PIN del '
      'titular, confirmando su cuenta en línea.';
  static const saveFailed =
      'No se pudo guardar el PIN. Puede crearlo más tarde en Operaciones › Más '
      '› PIN del titular, confirmando su cuenta en línea.';
}

/// Textos del retorno a una operación pendiente (F03 §4 bis.6).
abstract final class OwnerPinReturnTexts {
  static const header =
      'PIN del titular configurado. Revise la operación y autorícela con su '
      'PIN.';
  static const notConfigured =
      'No se configuró el PIN. La operación no cambió.';
  static const checkFailed =
      'No se pudo comprobar la operación. No se hizo ningún cambio.';
  static const ownerChanged =
      'El titular de estos datos cambió. No se hizo ningún cambio.';
  static String stale(String why) =>
      'Esta operación ya no está pendiente: $why. No se hizo ningún cambio.';
  static const noOwner =
      'Esta acción la autoriza sólo el titular con su PIN. Para habilitarla, '
      'active la aplicación, elija el titular y configure el PIN.';
}

/// Configurar o restablecer el PIN del titular (F03 §4). Por la vía (a) exige
/// acreditar en línea al mismo titular con su contraseña; con
/// [fromActivation] (vía (b), §4 bis) crea el primer PIN con la acreditación
/// de activación, sin contraseña. Restablecer el PIN no recupera ni descifra
/// copias de respaldo (la clave del respaldo es otra cosa). Al salir devuelve
/// `true` sólo si guardó un PIN en esta visita.
class OwnerCredentialScreen extends ConsumerStatefulWidget {
  const OwnerCredentialScreen({
    super.key,
    this.fromActivation = false,
    this.activationNotice,
  });

  final bool fromActivation;

  /// Aviso de la confirmación del titular (modalidad) que se muestra arriba.
  final String? activationNotice;

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

  // Modo de activación: el controlador se guarda aquí para anular la
  // acreditación al salir sin usar `ref` en dispose (H9).
  FirstActivationController? _activation;
  bool _activationEnded = false;
  String? _activationResult;

  @override
  void initState() {
    super.initState();
    if (!widget.fromActivation) return;
    try {
      if (ref.exists(firstActivationProvider)) {
        _activation = ref.read(firstActivationProvider.notifier);
      }
    } on Object {
      _activation = null;
    }
    if (!(_activation?.hasActivationEvidence ?? false)) {
      _activationEnded = true;
      _activationResult = ActivationPinTexts.expired;
    }
  }

  @override
  void dispose() {
    // Salir de la oferta por cualquier vía la anula (F03 §4 bis.3).
    _activation?.discardActivationEvidence();
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
                  'contraseña y la conexión, o espere un momento si el teléfono '
                  'se está sincronizando, y vuelva a intentarlo.'
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

  /// Vía (b): la forma y la igualdad del PIN se comprueban antes de tocar la
  /// acreditación, para que un error de tecleo no la gaste.
  Future<void> _createFromActivation() async {
    if (_busy || _activationEnded) return;
    final pin = _pin.text;
    final confirmation = _pinConfirmation.text;
    final problem =
        pinProblem(pin) ??
        (pin != confirmation ? 'Los dos PIN no coinciden.' : null);
    if (problem != null) {
      _pin.clear();
      _pinConfirmation.clear();
      setState(() => _message = problem);
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    String? result;
    var done = false;
    try {
      final binding = await ref.read(ownerBindingContextReaderProvider)();
      final proof = binding == null
          ? null
          : await ref
                .read(ownerOnlineVerificationProvider)
                .fromActivation(binding: binding);
      if (proof == null || binding == null) {
        result = ActivationPinTexts.expired;
      } else {
        await ref
            .read(localOwnerCredentialProvider)
            .enroll(
              pin: pin,
              pinConfirmation: confirmation,
              proof: proof,
              binding: binding,
            );
        done = true;
        result = ActivationPinTexts.done;
      }
    } on CredentialException catch (error) {
      result = error.message == activationExistingPinMessage
          ? activationExistingPinMessage
          : ActivationPinTexts.saveFailed;
    } on Object {
      result = ActivationPinTexts.saveFailed;
    } finally {
      _pin.clear();
      _pinConfirmation.clear();
      _activation?.discardActivationEvidence();
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _done = done;
      _activationEnded = true;
      _activationResult = result;
    });
  }

  void _skip() {
    _activation?.discardActivationEvidence();
    showSuccess(context, ActivationPinTexts.skipped);
    context.go('/');
  }

  void _leaveActivation() {
    if (_busy) return;
    if (_activationEnded) {
      context.go('/');
    } else {
      _skip();
    }
  }

  /// Vía (a): vuelve con el resultado (true sólo si se guardó un PIN).
  void _leave() {
    if (_busy) return;
    if (context.canPop()) {
      context.pop(_done);
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
    if (widget.fromActivation) return _buildActivation(context, activated);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
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
                const Text(ActivationPinTexts.form),
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

  Widget _buildActivation(BuildContext context, bool activated) {
    final notice = widget.activationNotice;
    final ended = _activationEnded || !activated;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leaveActivation();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('PIN del titular')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                notice == null
                    ? 'Titular vinculado.'
                    : 'Titular vinculado. $notice',
                key: const Key('pin-activation-notice'),
              ),
              const SizedBox(height: 16),
              if (ended) ...[
                Text(
                  _activationResult ?? ActivationPinTexts.expired,
                  key: Key(
                    _done ? 'pin-activation-done' : 'pin-activation-ended',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  key: const Key('pin-activation-continue'),
                  onPressed: _busy ? null : () => context.go('/'),
                  child: const Text('Continuar'),
                ),
              ] else ...[
                const Text(
                  ActivationPinTexts.offer,
                  key: Key('pin-activation-offer'),
                ),
                const SizedBox(height: 12),
                const Text(ActivationPinTexts.whyNow),
                const SizedBox(height: 12),
                const Text(ActivationPinTexts.separation),
                const SizedBox(height: 16),
                const Text(ActivationPinTexts.form),
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
                  key: const Key('pin-activation-create'),
                  onPressed: _busy ? null : _createFromActivation,
                  child: const Text('Crear PIN'),
                ),
                TextButton(
                  key: const Key('pin-activation-skip'),
                  onPressed: _busy ? null : _skip,
                  child: const Text('Ahora no'),
                ),
                if (_busy) const LinearProgressIndicator(),
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Text(_message!, key: const Key('pin-message')),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Un PIN utilizable para autorizar: el vínculo con el que se verifica y si
/// se acaba de configurar en esta misma acción (F03 §4 bis.6).
class OwnerPinGate {
  const OwnerPinGate(this.binding, {required this.configuredNow});

  final OwnerBindingContext binding;
  final bool configuredNow;
}

/// Comprueba que hay un PIN del titular utilizable. Si no lo hay, ofrece
/// configurarlo, espera a que se vuelva de `/titular/pin` y revalida: el
/// mismo vínculo, un PIN vigente y, con [revalidate], que la operación siga
/// aplicando (devuelve null si aplica o el motivo si ya no). Nunca autoriza
/// ni ejecuta nada: null si no se puede seguir. [announceReturn] muestra los
/// avisos del retorno (F08 los omite porque ya informa por su cuenta).
Future<OwnerPinGate?> ensureOwnerPin(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  Future<String?> Function()? revalidate,
  bool announceReturn = true,
}) async {
  final reader = ref.read(ownerBindingContextReaderProvider);
  final binding = await reader();
  if (!context.mounted) return null;
  if (binding == null) {
    await _showPinUnavailable(
      context,
      title,
      OwnerPinReturnTexts.noOwner,
      configure: false,
    );
    return null;
  }
  final credential = ref.read(localOwnerCredentialProvider);
  final status = await credential.status(binding);
  if (!context.mounted) return null;
  if (status.canVerify) return OwnerPinGate(binding, configuredNow: false);
  final message = switch (status.state) {
    CredentialState.locked =>
      'Demasiados intentos. Espere antes de volver a intentarlo.',
    CredentialState.requiresOnlineReset =>
      'El PIN quedó bloqueado. Restablézcalo acreditando al titular en línea.',
    _ =>
      'Esta acción la autoriza sólo el titular con su PIN. Configure el PIN '
          'del titular primero.',
  };
  final open = await _showPinUnavailable(
    context,
    title,
    message,
    configure: status.state != CredentialState.locked,
  );
  if (open != true || !context.mounted) return null;
  final created = await context.push<bool>('/titular/pin');
  if (!context.mounted) return null;
  void announce(String text) {
    if (announceReturn && context.mounted) showError(context, text);
  }

  if (created != true) {
    announce(OwnerPinReturnTexts.notConfigured);
    return null;
  }
  // REVALIDAR: mismo vínculo, PIN vigente y la operación todavía aplicable.
  final again = await reader();
  if (!context.mounted) return null;
  if (again == null ||
      again.bindingId != binding.bindingId ||
      again.personId != binding.personId ||
      again.scope != binding.scope) {
    announce(OwnerPinReturnTexts.ownerChanged);
    return null;
  }
  final after = await credential.status(again);
  if (!context.mounted) return null;
  if (!after.canVerify) {
    announce(OwnerPinReturnTexts.notConfigured);
    return null;
  }
  if (revalidate != null) {
    final String? stale;
    try {
      stale = await revalidate();
    } on Object {
      announce(OwnerPinReturnTexts.checkFailed);
      return null;
    }
    if (!context.mounted) return null;
    if (stale != null) {
      announce(OwnerPinReturnTexts.stale(stale));
      return null;
    }
  }
  return OwnerPinGate(again, configuredNow: true);
}

Future<bool?> _showPinUnavailable(
  BuildContext context,
  String title,
  String message, {
  required bool configure,
}) => showDialog<bool>(
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

/// El diálogo del PIN para una acción concreta, con el vínculo de [gate].
/// Devuelve la autorización de un solo uso o null si se cancela.
Future<OwnerAuthorization?> showOwnerPinDialog(
  BuildContext context,
  WidgetRef ref, {
  required OwnerPinGate gate,
  required AuthorizationPurpose purpose,
  required String subjectRef,
  required String title,
  required String effects,
}) {
  final credential = ref.read(localOwnerCredentialProvider);
  return showDialog<OwnerAuthorization>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _OwnerPinDialog(
      title: title,
      effects: effects,
      header: gate.configuredNow ? OwnerPinReturnTexts.header : null,
      onVerify: (pin) => credential.verify(
        pin: pin,
        purpose: purpose,
        subjectRef: subjectRef,
        binding: gate.binding,
      ),
    ),
  );
}

/// Pide el PIN del titular para una acción concreta y devuelve la autorización
/// de un solo uso, o null si se cancela. [effects] describe lo que hará la
/// acción. Si el PIN no está configurado, ofrece configurarlo y, al volver con
/// un PIN creado, revalida y vuelve a mostrar la acción: nunca la autoriza ni
/// la ejecuta sola (F03 §4 bis.6).
Future<OwnerAuthorization?> requestOwnerAuthorization(
  BuildContext context,
  WidgetRef ref, {
  required AuthorizationPurpose purpose,
  required String subjectRef,
  required String title,
  required String effects,
  Future<String?> Function()? revalidate,
  bool announceReturn = true,
}) async {
  final gate = await ensureOwnerPin(
    context,
    ref,
    title: title,
    revalidate: revalidate,
    announceReturn: announceReturn,
  );
  if (gate == null || !context.mounted) return null;
  return showOwnerPinDialog(
    context,
    ref,
    gate: gate,
    purpose: purpose,
    subjectRef: subjectRef,
    title: title,
    effects: effects,
  );
}

class _OwnerPinDialog extends StatefulWidget {
  const _OwnerPinDialog({
    required this.title,
    required this.effects,
    required this.onVerify,
    this.header,
  });

  final String title;
  final String effects;
  final String? header;
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
        if (widget.header != null) ...[
          Text(widget.header!, key: const Key('owner-pin-return-header')),
          const SizedBox(height: 8),
        ],
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
