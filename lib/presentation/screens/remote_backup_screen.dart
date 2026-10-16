import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/backup/remote_backup_api.dart';
import '../../services/backup/remote_backup_providers.dart';
import '../../services/sync/sync_providers.dart';
import '../widgets/common.dart';

/// «Respaldo en la nube» (F08, MOB #35/#36): copia privada del agricultor en
/// el servidor del sindicato. Cada acción es explícita: subir, actualizar la
/// lista, restaurar (con descarga, verificación SHA-256 y confirmación) y
/// eliminar. Nada de esto publica datos al sindicato: un respaldo no es una
/// sincronización.
class RemoteBackupScreen extends ConsumerStatefulWidget {
  const RemoteBackupScreen({super.key});

  @override
  ConsumerState<RemoteBackupScreen> createState() => _RemoteBackupScreenState();
}

class _RemoteBackupScreenState extends ConsumerState<RemoteBackupScreen> {
  List<RemoteBackupEntry>? _entries;
  String? _problem;
  bool _busy = false;

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

  Future<void> _refresh() => _run(() async {
    try {
      final entries = await ref.read(remoteBackupServiceProvider).list();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _problem = null;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _problem = friendlyError(error));
      rethrow;
    }
  });

  Future<void> _upload() async {
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Subir un respaldo nuevo',
      detail:
          'Se genera un respaldo de todos los datos y fotografías de este '
          'teléfono y se guarda como copia privada de su cuenta en el servidor '
          'del sindicato. Nadie más puede verla, tampoco la Directiva. No se '
          'publica ningún dato al sindicato.',
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
            : 'Respaldo subido y confirmado por el servidor '
                  '(${_size(result.entry.sizeBytes)}).',
      );
      // Una foto que ya no está en el teléfono no se oculta (#55).
      await _showNotices('Respaldo', result.export.warnings);
      final entries = await ref.read(remoteBackupServiceProvider).list();
      if (mounted) setState(() => _entries = entries);
    });
  }

  Future<void> _restore(RemoteBackupEntry entry) => _run(() async {
    final service = ref.read(remoteBackupServiceProvider);
    // Descarga y verifica antes de pedir confirmación: si la copia no está
    // íntegra o no es de este titular, no se llega a ofrecer.
    final prepared = await service.prepareRestore(entry);
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
          'verificada con SHA-256.\n'
          'Contiene la base de datos y '
          '${prepared.validation.attachmentCount} fotografía(s).\n'
          '${prepared.ownership.message}\n\n'
          'TODOS los datos actuales se reemplazarán. Se guarda una copia de '
          'los datos actuales. Los envíos al sindicato que traiga la copia '
          'quedarán pausados hasta que usted los libere en Sincronización.',
      confirmLabel: 'Restaurar',
    );
    if (!confirmed || !mounted) {
      await service.discard(prepared);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await service.restorePrepared(prepared);
    await ref.read(syncControllerProvider.notifier).refreshSummary();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Copia restaurada (${outcome.result.restoredAttachments} '
          'fotografía(s)). Copia de los datos anteriores: '
          '${outcome.result.safetyCopyPath}',
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
      final service = ref.read(remoteBackupServiceProvider);
      await service.delete(entry);
      final entries = await service.list();
      if (!mounted) return;
      setState(() => _entries = entries);
      showSuccess(context, 'Copia eliminada del servidor.');
    });
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  static String _date(DateTime value) {
    final local = value.toLocal();
    return '${_two(local.day)}/${_two(local.month)}/${local.year} '
        '${_two(local.hour)}:${_two(local.minute)}';
  }

  static String _size(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).ceil()} KB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return PageFrame(
      title: 'Respaldo en la nube',
      subtitle: 'Copia privada de sus datos. No se comparte con el sindicato.',
      action: FilledButton.icon(
        onPressed: _busy ? null : _upload,
        icon: const Icon(Icons.cloud_upload_outlined),
        label: const Text('Subir respaldo'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text('Copia del ${_date(entry.createdAt)}'),
                  subtitle: Text(
                    '${_size(entry.sizeBytes)} · esquema '
                    '${entry.schemaVersion} · SHA-256 '
                    '${entry.sha256.substring(0, 12)}…',
                  ),
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
        ],
      ),
    );
  }
}
