import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app.dart' show backupServiceProvider;
import '../../data/backup_encryption.dart';
import '../../data/restore_safety_copies.dart';
import '../../services/backup/backup_keyring.dart';
import '../../services/backup/remote_backup_api.dart';
import '../../services/backup/remote_backup_providers.dart';
import '../../services/backup/remote_backup_service.dart';
import '../../services/sync/sync_providers.dart';
import '../widgets/common.dart';
import 'backup_recovery_key_screen.dart';

/// «Respaldo en la nube» (F08, MOB #35/#36): copia privada del agricultor en
/// el servidor del sindicato. Cada acción es explícita: subir, actualizar la
/// lista, restaurar (con descarga, verificación SHA-256, descifrado y
/// confirmación) y eliminar. Nada de esto publica datos al sindicato: un
/// respaldo no es una sincronización.
///
/// Desde F08-ADR-003 la copia se cifra en el teléfono con la clave de
/// recuperación del titular, que se crea, se anota fuera del teléfono y se
/// confirma antes de subir nada.
class RemoteBackupScreen extends ConsumerStatefulWidget {
  const RemoteBackupScreen({super.key});

  @override
  ConsumerState<RemoteBackupScreen> createState() => _RemoteBackupScreenState();
}

class _RemoteBackupScreenState extends ConsumerState<RemoteBackupScreen> {
  List<RemoteBackupEntry>? _entries;
  Map<String, RemoteCopyKey> _keys = const {};
  String? _problem;
  bool _busy = false;
  KeyringReadiness? _readiness;
  String? _keyringProblem;
  List<SafetyCopyEntry> _previo = const [];
  List<FileSystemEntity> _unregistered = const [];
  bool _previoReadable = true;

  @override
  void initState() {
    super.initState();
    _loadKeyring();
    // Abrir la sección de respaldos es una oportunidad de mantenimiento de
    // las copias previas (F08-ADR-003 §7.2).
    _loadPrevio(maintain: true);
  }

  Future<void> _loadKeyring() async {
    try {
      final readiness = await ref.read(backupKeyringProvider).readiness();
      if (mounted) {
        setState(() {
          _readiness = readiness;
          _keyringProblem = null;
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _keyringProblem = friendlyError(error));
    }
  }

  Future<void> _loadPrevio({bool maintain = false}) async {
    final copies = ref.read(backupServiceProvider).safetyCopies;
    try {
      if (maintain) await copies.maintain();
      final readable = await copies.registryReadable();
      final entries = readable ? await copies.entries() : <SafetyCopyEntry>[];
      final unregistered = await copies.unregistered();
      if (!mounted) return;
      setState(() {
        _previoReadable = readable;
        _previo = entries;
        _unregistered = unregistered;
      });
    } on Object {
      // Sin acceso a la carpeta: la sección no se muestra; no cambia nada.
    }
  }

  /// La lista sólo se pide al servidor cuando el agricultor lo solicita.
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on Object catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reload() async {
    final service = ref.read(remoteBackupServiceProvider);
    final entries = await service.list();
    final keys = await service.keysFor(entries);
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _keys = keys;
      _problem = null;
    });
  }

  Future<void> _refresh() => _run(() async {
    try {
      await _reload();
    } on Object catch (error) {
      if (mounted) setState(() => _problem = friendlyError(error));
      rethrow;
    }
  });

  Future<bool> _openKeyScreen({bool rotation = false}) async {
    final confirmed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BackupRecoveryKeyScreen(rotation: rotation),
      ),
    );
    await _loadKeyring();
    return confirmed ?? false;
  }

  Future<void> _rotate() async {
    final active = await ref.read(backupKeyringProvider).activeKey();
    if (active == null || !mounted) return;
    final authorized = await ref.read(backupKeyAuthorizerProvider)(
      context,
      BackupKeyAction.rotate,
      active.keyId,
    );
    if (!mounted) return;
    if (!authorized) {
      showError(
        context,
        'Cambiar la clave requiere la autorización del titular en este '
        'teléfono. No se cambió nada.',
      );
      return;
    }
    await _openKeyScreen(rotation: true);
  }

  Future<void> _upload() async {
    if (_readiness != KeyringReadiness.ready) {
      final ready = await _openKeyScreen();
      if (!ready || !mounted) return;
    }
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Subir un respaldo nuevo',
      detail:
          'Se genera un respaldo de todos los datos y fotografías de este '
          'teléfono, se cifra aquí con su clave de recuperación y se guarda '
          'como copia privada de su cuenta en el servidor del sindicato. El '
          'servidor sólo recibe la copia cifrada: nadie más puede leerla, '
          'tampoco la Directiva. No se publica ningún dato al sindicato.',
      confirmLabel: 'Subir',
    );
    if (!confirmed || !mounted) return;
    await _run(() async {
      final result = await ref.read(remoteBackupServiceProvider).uploadNew();
      if (!mounted) return;
      showSuccess(
        context,
        result.confirmedByListing
            ? 'La respuesta no llegó, pero el servidor ya tiene esta copia '
                  '(mismo SHA-256): no hace falta volver a subirla.'
            : 'Respaldo cifrado subido y confirmado por el servidor '
                  '(${_size(result.entry.sizeBytes)}).',
      );
      // Una foto que ya no está en el teléfono no se oculta (#55).
      await _showNotices('Respaldo', result.export.warnings);
      await _reload();
    });
  }

  /// Descarga y descifra; si hace falta la clave escrita, la pide hasta que
  /// la persona cancele. Null si se canceló.
  Future<PreparedRemoteRestore?> _prepare(RemoteBackupEntry entry) async {
    final service = ref.read(remoteBackupServiceProvider);
    try {
      return await service.prepareRestore(entry);
    } on RecoveryKeyRequired catch (required) {
      String? problem;
      while (true) {
        if (!mounted) break;
        final typed = await askRecoveryKey(context, problem: problem);
        if (typed == null) {
          await service.discardPending(required.pending);
          return null;
        }
        try {
          return await service.prepareWithRecoveryKey(required.pending, typed);
        } on RecoveryKeyFormatException catch (error) {
          problem = error.message;
        } on BackupEnvelopeException catch (error) {
          if (error.problem != BackupEnvelopeProblem.wrongKey) rethrow;
          problem = error.message;
        }
      }
      await service.discardPending(required.pending);
      return null;
    }
  }

  Future<void> _restore(RemoteBackupEntry entry) => _run(() async {
    final service = ref.read(remoteBackupServiceProvider);
    // Descarga, descifra y verifica antes de pedir confirmación: si la copia
    // no está íntegra o no es de este titular, no se llega a ofrecer.
    final prepared = await _prepare(entry);
    if (prepared == null) return;
    if (!mounted) {
      await service.discard(prepared);
      return;
    }
    if (!prepared.ownership.accepted) {
      await service.discard(prepared);
      if (mounted) showError(context, prepared.ownership.message);
      return;
    }
    final confirmed = await confirmDestructiveAction(
      context,
      title: '¿Restaurar esta copia?',
      detail:
          'Copia del ${_date(entry.createdAt)} (${_size(entry.sizeBytes)}), '
          '${prepared.unencrypted ? 'guardada SIN CIFRAR (formato anterior)' : 'descifrada y verificada'}.\n'
          'Contiene la base de datos y '
          '${prepared.validation.attachmentCount} fotografía(s).\n'
          '${prepared.ownership.message}\n\n'
          'TODOS los datos actuales se reemplazarán. Se guarda una copia de '
          'los datos actuales en este teléfono. Los envíos al sindicato que '
          'traiga la copia quedarán pausados hasta que usted los libere en '
          'Sincronización.',
      confirmLabel: 'Restaurar',
    );
    if (!confirmed || !mounted) {
      await service.discard(prepared);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await service.restorePrepared(prepared);
    await ref.read(syncControllerProvider.notifier).refreshSummary();
    await _loadKeyring();
    await _loadPrevio();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Copia restaurada (${outcome.result.restoredAttachments} '
          'fotografía(s)). Se guardó una copia de los datos anteriores en '
          'este teléfono.',
        ),
      ),
    );
    await _showNotices('Restauración', outcome.result.warnings);
  });

  /// Avisos de una operación que sí terminó: nunca se ocultan.
  Future<void> _showNotices(String title, List<String> notices) async {
    if (!mounted || notices.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.warning_amber_outlined),
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final notice in notices) Text('· $notice')],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(RemoteBackupEntry entry) async {
    final confirmed = await confirmDestructiveAction(
      context,
      title: '¿Eliminar esta copia del servidor?',
      detail:
          'Copia del ${_date(entry.createdAt)} (${_size(entry.sizeBytes)}). '
          'Se elimina sólo del servidor; los respaldos guardados en este '
          'teléfono no cambian.',
      confirmLabel: 'Eliminar',
    );
    if (!confirmed || !mounted) return;
    await _run(() async {
      await ref.read(remoteBackupServiceProvider).delete(entry);
      await _reload();
      if (mounted) showSuccess(context, 'Copia eliminada del servidor.');
    });
  }

  Future<void> _keepCurrent(SafetyCopyEntry entry) async {
    final confirmed = await confirmDestructiveAction(
      context,
      title: '¿Mantener los datos actuales?',
      detail:
          'Una restauración del ${_date(entry.createdAt)} no terminó y se '
          'conserva la copia de los datos que había entonces. Si los datos '
          'actuales son correctos, márquela como resuelta: la copia se '
          'conservará siete días más y después se retirará en la limpieza '
          'normal.',
      confirmLabel: 'Mantener los actuales',
    );
    if (!confirmed) return;
    await _run(() async {
      await ref
          .read(backupServiceProvider)
          .safetyCopies
          .keepCurrentData(entry.id);
      await _loadPrevio();
    });
  }

  Future<void> _deleteUnregistered(FileSystemEntity entity) async {
    final confirmed = await confirmDestructiveAction(
      context,
      title: '¿Borrar esta copia antigua?',
      detail:
          '${p.basename(entity.path)}\n\nEs una copia de los datos anteriores '
          'a una restauración, de una versión previa de la aplicación. No se '
          'sabe si todavía la necesita; sólo se borra porque usted lo pide.',
      confirmLabel: 'Borrar',
    );
    if (!confirmed) return;
    await _run(() async {
      await ref
          .read(backupServiceProvider)
          .safetyCopies
          .deleteUnregistered(entity);
      await _loadPrevio();
    });
  }

  Future<void> _setAsideRegistry() => _run(() async {
    await ref
        .read(backupServiceProvider)
        .safetyCopies
        .setAsideUnreadableRegistry();
    await _loadPrevio();
  });

  static String _two(int value) => value.toString().padLeft(2, '0');

  static String _date(DateTime value) {
    final local = value.toLocal();
    return '${_two(local.day)}/${_two(local.month)}/${local.year} '
        '${_two(local.hour)}:${_two(local.minute)}';
  }

  static String _size(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).ceil()} KB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  Widget _keyCard() {
    final readiness = _readiness;
    final (icon, text) = switch (readiness) {
      _ when _keyringProblem != null => (
        Icons.key_off_outlined,
        _keyringProblem!,
      ),
      KeyringReadiness.ready => (
        Icons.key_outlined,
        'Sus respaldos se cifran en este teléfono con su clave de '
            'recuperación. Guárdela fuera del teléfono.',
      ),
      KeyringReadiness.pendingConfirmation => (
        Icons.key_outlined,
        'Falta confirmar la clave de recuperación que se le mostró. Hasta '
            'entonces no se sube nada.',
      ),
      KeyringReadiness.noKey || null => (
        Icons.key_off_outlined,
        'Antes de subir un respaldo hay que crear su clave de recuperación '
            'y anotarla fuera del teléfono.',
      ),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(icon),
              title: const Text('Clave de recuperación'),
              subtitle: Text(text),
            ),
            Wrap(
              spacing: 8,
              children: [
                if (readiness == KeyringReadiness.ready) ...[
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => revealActiveRecoveryKey(context, ref),
                    child: const Text('Ver la clave'),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : _rotate,
                    child: const Text('Cambiar la clave'),
                  ),
                ] else if (_keyringProblem == null)
                  FilledButton(
                    onPressed: _busy ? null : _openKeyScreen,
                    child: Text(
                      readiness == KeyringReadiness.pendingConfirmation
                          ? 'Confirmar la clave'
                          : 'Crear la clave',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _entryDetail(RemoteBackupEntry entry) {
    final protection = switch (entry.formatVersion) {
      1 => 'SIN CIFRAR (formato anterior)',
      RemoteBackupService.uploadFormatVersion => remoteCopyKeyLabel(
        _keys[entry.id],
      ),
      _ => 'formato desconocido',
    };
    return '${_size(entry.sizeBytes)} · esquema ${entry.schemaVersion} · '
        '$protection';
  }

  Widget _previoSection() {
    if (_previoReadable && _previo.isEmpty && _unregistered.isEmpty) {
      return const SizedBox.shrink();
    }
    String state(SafetyCopyState value) => switch (value) {
      SafetyCopyState.preparing => 'en uso por una restauración',
      SafetyCopyState.finalized => 'restauración terminada',
      SafetyCopyState.rolledBack => 'restauración deshecha',
      SafetyCopyState.interrupted =>
        'RESTAURACIÓN SIN TERMINAR: copia protegida',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text(
          'Copias previas a restauraciones',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const Text(
          'Se guardan en este teléfono. Se conservan hasta dos, siete días, '
          'cuando se abre esta sección o se restaura otra copia; no hay '
          'limpieza con la aplicación cerrada. La de una restauración sin '
          'terminar no se borra.',
        ),
        if (!_previoReadable)
          Card(
            child: ListTile(
              leading: const Icon(Icons.error_outline),
              title: const Text('El registro de copias no se puede leer'),
              subtitle: const Text(
                'No se borrará ninguna copia y no se podrá restaurar hasta '
                'apartarlo. Apartarlo no borra copias: quedan como «antiguas» '
                'y sólo se borran una a una si usted lo pide.',
              ),
              trailing: TextButton(
                onPressed: _busy ? null : _setAsideRegistry,
                child: const Text('Apartar'),
              ),
            ),
          ),
        for (final entry in _previo)
          Card(
            child: ListTile(
              leading: Icon(
                entry.isProtected
                    ? Icons.shield_outlined
                    : Icons.history_outlined,
              ),
              title: Text('Del ${_date(entry.createdAt)}'),
              subtitle: Text(state(entry.state)),
              trailing: entry.state == SafetyCopyState.interrupted
                  ? TextButton(
                      onPressed: _busy ? null : () => _keepCurrent(entry),
                      child: const Text('Mantener los actuales'),
                    )
                  : null,
            ),
          ),
        for (final entity in _unregistered)
          Card(
            child: ListTile(
              leading: const Icon(Icons.inventory_outlined),
              title: Text(p.basename(entity.path)),
              subtitle: const Text('Copia antigua sin registro'),
              trailing: IconButton(
                tooltip: 'Borrar',
                onPressed: _busy ? null : () => _deleteUnregistered(entity),
                icon: const Icon(Icons.delete_outline),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return PageFrame(
      title: 'Respaldo en la nube',
      subtitle:
          'Copia privada y cifrada de sus datos. No se comparte con el '
          'sindicato.',
      action: FilledButton.icon(
        onPressed: _busy ? null : _upload,
        icon: const Icon(Icons.cloud_upload_outlined),
        label: const Text('Subir respaldo'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _keyCard(),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Ver copias en el servidor'),
              ),
              const SizedBox(width: 12),
              if (_busy)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_problem != null)
            EmptyState(icon: Icons.cloud_off_outlined, message: _problem!)
          else if (entries == null)
            const EmptyState(
              icon: Icons.cloud_outlined,
              message:
                  'Pulse «Ver copias en el servidor» para consultar sus '
                  'copias. La consulta requiere conexión.',
            )
          else if (entries.isEmpty)
            const EmptyState(
              icon: Icons.cloud_queue_outlined,
              message: 'Todavía no tiene copias en el servidor.',
            )
          else
            for (final entry in entries)
              Card(
                child: ListTile(
                  leading: Icon(
                    entry.formatVersion == 1
                        ? Icons.lock_open_outlined
                        : Icons.lock_outline,
                  ),
                  title: Text('Copia del ${_date(entry.createdAt)}'),
                  subtitle: Text(_entryDetail(entry)),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        tooltip: 'Restaurar',
                        onPressed: _busy ? null : () => _restore(entry),
                        icon: const Icon(Icons.restore_outlined),
                      ),
                      IconButton(
                        tooltip: 'Eliminar del servidor',
                        onPressed: _busy ? null : () => _delete(entry),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              ),
          _previoSection(),
        ],
      ),
    );
  }
}
