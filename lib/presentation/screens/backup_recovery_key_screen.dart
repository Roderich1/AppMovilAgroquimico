import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/backup_models.dart';
import '../../services/backup/backup_keyring.dart';
import '../../services/backup/remote_backup_providers.dart';
import '../../services/backup/screen_secure.dart';
import '../theme/agro_theme.dart';
import '../widgets/agro_ui.dart';
import '../widgets/common.dart';

/// Entrada manual y pegado explícito en la pantalla protegida.
class _RecoveryKeyInput extends StatefulWidget {
  const _RecoveryKeyInput(this.controller, {this.errorText});

  final TextEditingController controller;
  final String? errorText;

  @override
  State<_RecoveryKeyInput> createState() => _RecoveryKeyInputState();
}

class _RecoveryKeyInputState extends State<_RecoveryKeyInput> {
  String? _pasteError;

  Future<void> _paste() async {
    final previous = widget.controller.value;
    String? canonicalKey;
    String? error;
    try {
      final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      canonicalKey = BackupRecoveryKey.parse(text ?? '').displayText;
    } on RecoveryKeyFormatException {
      error = 'El portapapeles no contiene una clave de recuperación válida.';
    } on Exception {
      error = 'No se pudo leer el portapapeles.';
    }
    if (!mounted ||
        ModalRoute.isCurrentOf(context) == false ||
        widget.controller.value != previous) {
      return;
    }
    if (canonicalKey != null) {
      widget.controller.value = TextEditingValue(
        text: canonicalKey,
        selection: TextSelection.collapsed(offset: canonicalKey.length),
      );
    }
    setState(() => _pasteError = error);
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextField(
        controller: widget.controller,
        autofocus: true,
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
        contextMenuBuilder: (_, _) => const SizedBox.shrink(),
        keyboardType: TextInputType.visiblePassword,
        textCapitalization: TextCapitalization.characters,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z\- ]')),
        ],
        maxLines: 2,
        minLines: 1,
        style: const TextStyle(fontFamily: 'monospace', letterSpacing: 1.5),
        decoration: InputDecoration(
          labelText: 'Clave de recuperación',
          hintText: 'XXXX-XXXX-XXXX-…',
          errorText: _pasteError ?? widget.errorText,
          errorMaxLines: 3,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) {
          if (_pasteError != null) setState(() => _pasteError = null);
        },
      ),
      TextButton.icon(
        onPressed: _paste,
        icon: const Icon(Icons.content_paste),
        label: const Text('Pegar clave'),
      ),
    ],
  );
}

/// Muestra [child] sólo con la pantalla protegida contra capturas
/// (FLAG_SECURE, [ScreenSecure]). Mientras Android no lo confirma se ve un
/// indicador, nunca lo sensible; si no lo confirma, un aviso para reintentar.
/// La protección se devuelve al desmontarse, es decir, cuando la pantalla o el
/// diálogo ya terminó de cerrarse.
class ScreenSecureScope extends ConsumerStatefulWidget {
  const ScreenSecureScope({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<ScreenSecureScope> createState() => _ScreenSecureScopeState();
}

class _ScreenSecureScopeState extends ConsumerState<ScreenSecureScope> {
  ScreenSecureLease? _lease;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _acquire();
  }

  @override
  void dispose() {
    _lease?.release();
    super.dispose();
  }

  Future<void> _acquire() async {
    try {
      final lease = await ref.read(screenSecureProvider).acquire();
      if (!mounted) {
        await lease.release();
        return;
      }
      setState(() => _lease = lease);
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_lease != null) return widget.child;
    if (!_failed) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(const ScreenSecureUnavailable().message),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () {
            setState(() => _failed = false);
            _acquire();
          },
          child: const Text('Reintentar'),
        ),
      ],
    );
  }
}

/// La clave en grupos, para leerla y copiarla a mano.
class RecoveryKeyDisplay extends StatelessWidget {
  const RecoveryKeyDisplay(this.recoveryKey, {super.key});
  final BackupRecoveryKey recoveryKey;

  @override
  Widget build(BuildContext context) {
    final groups = recoveryKey.displayText.split('-');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            for (var i = 0; i < groups.length; i++)
              Text(
                '${i + 1}. ${groups[i]}',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Crear (o cambiar) la clave de recuperación: la persona la guarda y la
/// introduce completa para activarla (F08-ADR-003 §3.4).
class BackupRecoveryKeyScreen extends ConsumerStatefulWidget {
  const BackupRecoveryKeyScreen({super.key, this.rotationKey});

  /// Cambio de una clave ya activa: la pendiente que devolvió
  /// `startRotation`, con la autorización del titular. La anterior se
  /// conserva para las copias ya subidas.
  final BackupRecoveryKey? rotationKey;

  bool get rotation => rotationKey != null;

  @override
  ConsumerState<BackupRecoveryKeyScreen> createState() =>
      _BackupRecoveryKeyScreenState();
}

class _BackupRecoveryKeyScreenState
    extends ConsumerState<BackupRecoveryKeyScreen> {
  BackupRecoveryKey? _key;
  bool _saved = false;
  bool _confirming = false;
  String? _error;
  final _typed = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final key =
          widget.rotationKey ??
          await ref.read(backupKeyringProvider).pendingKey();
      if (mounted) setState(() => _key = key);
    } on Object catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    }
  }

  Future<void> _confirm() async {
    try {
      await ref.read(backupKeyringProvider).confirmPending(_typed.text);
      if (!mounted) return;
      showSuccess(
        context,
        'Clave de recuperación confirmada. Ya puede subir respaldos cifrados.',
      );
      Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    }
  }

  Future<void> _discard() async {
    await ref.read(backupKeyringProvider).discardPending();
    if (mounted) Navigator.of(context).pop(false);
  }

  Future<void> _copy(BackupRecoveryKey key) async {
    try {
      final systemShowsConfirmation = await ref
          .read(screenSecureProvider)
          .copyRecoveryKey(key.displayText);
      if (mounted && !systemShowsConfirmation) {
        showSuccess(context, 'Clave copiada al portapapeles.');
      }
    } on Exception {
      if (mounted) showError(context, 'No se pudo copiar la clave.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final key = _key;
    return Scaffold(
      appBar: AgroAppBar(
        title: widget.rotation
            ? 'Cambiar la clave de recuperación'
            : 'Clave de recuperación',
      ),
      body: SafeArea(
        child: ScreenSecureScope(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AgroGroup(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Esta clave descifra sus respaldos en la nube. El servidor del '
                            'sindicato y el proveedor sólo guardan la copia cifrada: nadie, '
                            'tampoco la Directiva ni el administrador del servidor, puede '
                            'leerla ni recuperar esta clave por usted.',
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Es distinta de su contraseña y de su PIN. Recuperar la cuenta o '
                            'el PIN no recupera esta clave. Si pierde el teléfono y también '
                            'la clave, sus copias cifradas no se podrán recuperar.',
                            style: AgroText.detail,
                          ),
                          if (widget.rotation) ...[
                            const SizedBox(height: 8),
                            const Text(
                              'Conserve también la clave anterior: las copias que ya subió '
                              'siguen necesitándola hasta que el servidor las sustituya por '
                              'copias nuevas.',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AgroColors.ink,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (key == null && _error == null)
                  const Center(child: CircularProgressIndicator())
                else if (key != null && !_confirming) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'Guarde la clave fuera de Agrocuentas. Puede anotarla '
                      'o copiarla tal como aparece.',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AgroColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  RecoveryKeyDisplay(key),
                  TextButton.icon(
                    onPressed: () => _copy(key),
                    icon: const Icon(Icons.content_copy),
                    label: const Text('Copiar clave'),
                  ),
                  const SizedBox(height: 12),
                  AgroGroup(
                    children: [
                      CheckboxListTile(
                        value: _saved,
                        onChanged: (value) =>
                            setState(() => _saved = value ?? false),
                        title: const Text(
                          'Ya guardé la clave fuera de Agrocuentas.',
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _saved
                        ? () => setState(() {
                            _confirming = true;
                            _error = null;
                          })
                        : null,
                    child: const Text('Continuar'),
                  ),
                ] else if (key != null) ...[
                  AgroGroup(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Escriba o pegue la clave completa para confirmarla.',
                            ),
                            const SizedBox(height: 12),
                            _RecoveryKeyInput(_typed, errorText: _error),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _confirm,
                    child: const Text('Confirmar la clave'),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _confirming = false;
                      _error = null;
                    }),
                    child: const Text('Volver a ver la clave'),
                  ),
                ],
                if (key == null && _error != null)
                  EmptyState(icon: Icons.key_off_outlined, message: _error!),
                const SizedBox(height: 24),
                if (key != null)
                  TextButton(
                    onPressed: _discard,
                    child: Text(
                      widget.rotation
                          ? 'Cancelar el cambio (se mantiene la clave actual)'
                          : 'Descartar esta clave y no subir respaldos',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Muestra otra vez la clave activa, sólo con la autorización del titular.
Future<void> revealActiveRecoveryKey(
  BuildContext context,
  WidgetRef ref,
) async {
  final keyring = ref.read(backupKeyringProvider);
  final active = await keyring.activeKey();
  if (active == null || !context.mounted) return;
  final authorization = await ref.read(backupKeyAuthorizerProvider)(
    context,
    ref,
    BackupKeyAction.show,
    active.keyId,
  );
  final BackupRecoveryKey? key;
  try {
    key = await keyring.revealActive(authorization: authorization);
  } on BackupKeyAuthorizationRequired catch (error) {
    if (context.mounted) showError(context, error.message);
    return;
  }
  if (key == null || !context.mounted) return;
  final BackupRecoveryKey revealed = key;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Clave de recuperación'),
      content: ScreenSecureScope(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Compruebe que coincide con la clave que guardó.'),
            const SizedBox(height: 8),
            RecoveryKeyDisplay(revealed),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );
}

/// Pide la clave de recuperación de una copia. Null si se cancela.
Future<String?> askRecoveryKey(BuildContext context, {String? problem}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _RestoreRecoveryKeyDialog(problem: problem),
    );

class _RestoreRecoveryKeyDialog extends StatefulWidget {
  const _RestoreRecoveryKeyDialog({this.problem});

  final String? problem;

  @override
  State<_RestoreRecoveryKeyDialog> createState() =>
      _RestoreRecoveryKeyDialogState();
}

class _RestoreRecoveryKeyDialogState extends State<_RestoreRecoveryKeyDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Clave de recuperación'),
    content: ScreenSecureScope(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Esta copia está cifrada con una clave que este teléfono no '
            'tiene. Escriba o pegue la clave de recuperación que guardó. Sus datos '
            'actuales no cambian hasta que confirme la restauración.',
          ),
          const SizedBox(height: 12),
          _RecoveryKeyInput(_controller, errorText: widget.problem),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: const Text('Descifrar'),
      ),
    ],
  );
}

/// Etiqueta de qué clave necesita una copia cifrada.
String remoteCopyKeyLabel(RemoteCopyKey? key) => switch (key) {
  RemoteCopyKey.current => 'cifrada con su clave actual',
  RemoteCopyKey.retired => 'cifrada con una clave anterior (consérvela)',
  RemoteCopyKey.unknown ||
  null => 'cifrada; pedirá la clave de recuperación con que se subió',
};
