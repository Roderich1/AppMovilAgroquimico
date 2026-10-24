import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/backup_encryption.dart';
import '../../services/backup/backup_keyring.dart';
import '../../services/backup/remote_backup_providers.dart';
import '../widgets/common.dart';

/// Campo para escribir una clave de recuperación: sin sugerencias, sin
/// autocorrección y sin aprendizaje del teclado (teclados como SwiftKey
/// guardan lo escrito), en mayúsculas.
TextField recoveryKeyField(
  TextEditingController controller, {
  String label = 'Clave de recuperación',
  String? errorText,
  bool autofocus = false,
}) => TextField(
  controller: controller,
  autofocus: autofocus,
  autocorrect: false,
  enableSuggestions: false,
  enableIMEPersonalizedLearning: false,
  keyboardType: TextInputType.visiblePassword,
  textCapitalization: TextCapitalization.characters,
  inputFormatters: [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z\- ]')),
  ],
  maxLines: 2,
  minLines: 1,
  style: const TextStyle(fontFamily: 'monospace', letterSpacing: 1.5),
  decoration: InputDecoration(
    labelText: label,
    hintText: 'XXXX-XXXX-XXXX-…',
    errorText: errorText,
    border: const OutlineInputBorder(),
  ),
);

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

/// Crear (o cambiar) la clave de recuperación: se muestra una vez, la persona
/// la anota fuera del teléfono y la vuelve a escribir completa. Sólo entonces
/// se activa (F08-ADR-003 §3.4). Devuelve true si quedó confirmada.
class BackupRecoveryKeyScreen extends ConsumerStatefulWidget {
  const BackupRecoveryKeyScreen({super.key, this.rotation = false});

  /// Cambio de una clave ya activa: la anterior se conserva para las copias
  /// ya subidas.
  final bool rotation;

  @override
  ConsumerState<BackupRecoveryKeyScreen> createState() =>
      _BackupRecoveryKeyScreenState();
}

class _BackupRecoveryKeyScreenState
    extends ConsumerState<BackupRecoveryKeyScreen> {
  BackupRecoveryKey? _key;
  bool _written = false;
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
      final key = await ref.read(backupKeyringProvider).pendingKey();
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

  @override
  Widget build(BuildContext context) {
    final key = _key;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.rotation
              ? 'Cambiar la clave de recuperación'
              : 'Clave de recuperación',
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
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
            ),
            if (widget.rotation) ...[
              const SizedBox(height: 8),
              const Text(
                'Conserve también la clave anterior: las copias que ya subió '
                'siguen necesitándola hasta que el servidor las sustituya por '
                'copias nuevas.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 16),
            if (key == null && _error == null)
              const Center(child: CircularProgressIndicator())
            else if (key != null && !_confirming) ...[
              const Text(
                'Anótela en papel, tal como aparece, y guárdela fuera del '
                'teléfono. No le haga una foto ni la copie en mensajes.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              RecoveryKeyDisplay(key),
              CheckboxListTile(
                value: _written,
                onChanged: (value) => setState(() => _written = value ?? false),
                title: const Text(
                  'La anoté en papel y la guardo fuera del teléfono.',
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              FilledButton(
                onPressed: _written
                    ? () => setState(() {
                        _confirming = true;
                        _error = null;
                      })
                    : null,
                child: const Text('Continuar'),
              ),
            ] else if (key != null) ...[
              const Text(
                'Escriba la clave completa tal como la anotó. Así se comprueba '
                'que la tiene fuera del teléfono antes de depender de ella.',
              ),
              const SizedBox(height: 12),
              recoveryKeyField(_typed, errorText: _error, autofocus: true),
              const SizedBox(height: 12),
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
  final authorized = await ref.read(backupKeyAuthorizerProvider)(
    context,
    BackupKeyAction.show,
    active.keyId,
  );
  if (!context.mounted) return;
  if (!authorized) {
    showError(
      context,
      'Para volver a ver la clave hace falta la autorización del titular en '
      'este teléfono. La clave no se mostró.',
    );
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Clave de recuperación'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Compruebe que coincide con la que tiene anotada.'),
          const SizedBox(height: 8),
          RecoveryKeyDisplay(active.key),
        ],
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
Future<String?> askRecoveryKey(BuildContext context, {String? problem}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Clave de recuperación'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Esta copia está cifrada con una clave que este teléfono no tiene. '
            'Escriba la clave de recuperación que anotó. Sus datos actuales '
            'no cambian hasta que confirme la restauración.',
          ),
          const SizedBox(height: 12),
          recoveryKeyField(controller, errorText: problem, autofocus: true),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text),
          child: const Text('Descifrar'),
        ),
      ],
    ),
  );
}

/// Etiqueta de qué clave necesita una copia cifrada.
String remoteCopyKeyLabel(RemoteCopyKey? key) => switch (key) {
  RemoteCopyKey.current => 'cifrada con su clave actual',
  RemoteCopyKey.retired => 'cifrada con una clave anterior (consérvela)',
  RemoteCopyKey.unknown ||
  null => 'cifrada; pedirá la clave de recuperación con que se subió',
};
