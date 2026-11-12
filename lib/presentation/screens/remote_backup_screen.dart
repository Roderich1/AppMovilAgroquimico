import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app.dart' show backupServiceProvider;
import '../../data/backup_encryption.dart';
import '../../data/restore_safety_copies.dart';
import '../../guarded_restore.dart' show GuardedRestoreOutcome;
import '../../services/backup/backup_keyring.dart';
import '../../services/backup/remote_backup_api.dart';
import '../../services/backup/remote_backup_providers.dart';
import '../../services/backup/remote_backup_service.dart';
import '../../services/sync/sync_providers.dart';
import '../theme/agro_theme.dart';
import '../widgets/agro_ui.dart';
import '../widgets/common.dart';
import '../widgets/identification_texts.dart' show labelPhotosNotInBackups;
import '../widgets/local_backup_actions.dart';
import '../widgets/rdm_c_page.dart';
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
    // Restos de una subida o preparación que no terminó (la app se cerró).
    ref.read(remoteBackupServiceProvider).cleanupLeftovers();
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

  Future<bool> _openKeyScreen({BackupRecoveryKey? rotationKey}) async {
    final confirmed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BackupRecoveryKeyScreen(rotationKey: rotationKey),
      ),
    );
    await _loadKeyring();
    return confirmed ?? false;
  }

  Future<void> _rotate() async {
    final active = await ref.read(backupKeyringProvider).activeKey();
    if (active == null || !mounted) return;
    final authorization = await ref.read(backupKeyAuthorizerProvider)(
      context,
      ref,
      BackupKeyAction.rotate,
      active.keyId,
    );
    final BackupRecoveryKey next;
    try {
      next = await ref
          .read(backupKeyringProvider)
          .startRotation(authorization: authorization);
    } on BackupKeyAuthorizationRequired catch (error) {
      if (mounted) showError(context, error.message);
      return;
    }
    if (!mounted) return;
    await _openKeyScreen(rotationKey: next);
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
          'Se genera un respaldo de todos los datos y de las fotografías de '
          'factura de este teléfono, se cifra aquí con su clave de '
          'recuperación y se guarda como copia privada de su cuenta en el '
          'servidor del sindicato. El servidor sólo recibe la copia cifrada: '
          'nadie más puede leerla, tampoco la Directiva. No se publica ningún '
          'dato al sindicato.\n\n$labelPhotosNotInBackups',
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
          '${prepared.validation.attachmentCount} fotografía(s) de factura. '
          '$labelPhotosNotInBackups\n'
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
    final errorColor = Theme.of(context).colorScheme.error;
    final GuardedRestoreOutcome outcome;
    try {
      outcome = await service.restorePrepared(prepared);
    } on Object catch (error) {
      // El aviso se muestra aunque la pantalla se haya desmontado, y la
      // sección de copias previas se recarga: puede haber una copia sin
      // resolver sobre la que decidir (F08-PREV-01).
      showErrorOn(messenger, errorColor, error);
      if (mounted) await _loadPrevio();
      return;
    }
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

  /// Copia de una restauración sin resolver: seguir con los datos actuales
  /// y confirmar la recuperación son dos decisiones distintas (F08-PREV-01).
  Future<void> _decideUnresolved(SafetyCopyEntry entry) async {
    final bool hasCopy;
    try {
      hasCopy = await ref
          .read(backupServiceProvider)
          .safetyCopies
          .hasFiles(entry);
    } on Object catch (error) {
      if (mounted) showError(context, error);
      return;
    }
    if (!mounted) return;
    final choice = await showDialog<_UnresolvedChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.shield_outlined),
        title: const Text('Restauración sin resolver'),
        content: Text(
          'Una restauración del ${_date(entry.createdAt)} no terminó o no '
          'pudimos confirmar que sus datos anteriores se recuperaron '
          'correctamente. '
          '${hasCopy ? 'Conservamos la copia de seguridad de los datos que había entonces.' : 'En este teléfono no quedó ninguna copia de los datos de entonces.'}'
          '\n\n'
          '· «Seguir con los actuales»: podrá restaurar otro respaldo; la '
          'entrada sigue protegida y no se borra.\n'
          '· «Mis datos están bien»: revíselos antes. La entrada deja de '
          'estar protegida y puede retirarse en la próxima limpieza (se '
          'conservan como máximo dos, durante siete días).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _UnresolvedChoice.continueAsIs),
            child: const Text('Seguir con los actuales'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _UnresolvedChoice.confirm),
            child: const Text('Mis datos están bien'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == _UnresolvedChoice.confirm) {
      await _confirmRecovery(entry, hasCopy: hasCopy);
      return;
    }
    await _run(() async {
      await ref
          .read(backupServiceProvider)
          .safetyCopies
          .continueWithCurrentData(entry.id);
      await _loadPrevio();
    });
  }

  Future<void> _confirmRecovery(SafetyCopyEntry entry, {bool? hasCopy}) async {
    final bool copy;
    try {
      copy =
          hasCopy ??
          await ref.read(backupServiceProvider).safetyCopies.hasFiles(entry);
    } on Object catch (error) {
      if (mounted) showError(context, error);
      return;
    }
    if (!mounted) return;
    final restoreDate = _date(entry.createdAt);
    final confirmed = await confirmDestructiveAction(
      context,
      title: '¿Sus datos actuales están bien?',
      detail:
          'Hágalo sólo después de revisarlos. '
          '${copy ? 'La copia de los datos de antes de la restauración del $restoreDate' : 'La entrada de la restauración del $restoreDate, sin copia en este teléfono,'}'
          ' dejará de estar protegida y puede retirarse en la próxima limpieza '
          '(se conservan como máximo dos, durante siete días).',
      confirmLabel: 'Mis datos están bien',
    );
    if (!confirmed || !mounted) return;
    await _run(() async {
      await ref
          .read(backupServiceProvider)
          .safetyCopies
          .confirmRecovery(entry.id);
      await _loadPrevio();
    });
  }

  Future<void> _replaceKeyring() async {
    final confirmed = await confirmDestructiveAction(
      context,
      title: '¿Empezar un llavero nuevo?',
      detail:
          'El llavero de claves de este teléfono no se puede leer. Si empieza '
          'uno nuevo, las claves que tenía se pierden: para restaurar copias '
          'antiguas tendrá que escribir su clave de recuperación anotada. Sus '
          'copias del servidor no cambian.',
      confirmLabel: 'Empezar uno nuevo',
    );
    if (!confirmed) return;
    await _run(() async {
      await ref.read(backupKeyringProvider).replaceUnreadable();
      await _loadKeyring();
    });
  }

  Future<void> _deleteUnregistered(FileSystemEntity entity) async {
    final confirmed = await confirmDestructiveAction(
      context,
      title: '¿Borrar esta copia sin registro?',
      detail:
          '${p.basename(entity.path)}\n\nEs una copia de sus datos anteriores '
          'a alguna restauración que no figura en el registro: de una versión '
          'previa de la aplicación o de un registro que se apartó por estar '
          'dañado. No se sabe si todavía la necesita; sólo se borra porque '
          'usted lo pide.',
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

  /// Tarjeta oscura de la clave de recuperación (lámina «Respaldos»): el
  /// estado, qué significa y la acción que corresponde. Mismos textos y
  /// acciones que antes.
  Widget _keyCard() {
    final readiness = _readiness;
    final (badge, text) = switch (readiness) {
      _ when _keyringProblem != null => (
        'Clave con problemas',
        _keyringProblem!,
      ),
      KeyringReadiness.ready => (
        'Clave creada',
        'Sus respaldos se cifran en este teléfono con su clave de '
            'recuperación. Guárdela fuera del teléfono.',
      ),
      KeyringReadiness.pendingConfirmation => (
        'Falta confirmar la clave',
        'Falta confirmar la clave de recuperación que se le mostró. Hasta '
            'entonces no se sube nada.',
      ),
      KeyringReadiness.noKey || null => (
        'Falta la clave de recuperación',
        'Antes de subir un respaldo hay que crear su clave de recuperación '
            'y anotarla fuera del teléfono.',
      ),
    };
    final ok = readiness == KeyringReadiness.ready && _keyringProblem == null;
    final onInk = OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      side: const BorderSide(color: AgroColors.onInkMuted),
      minimumSize: const Size(0, 48),
    );
    return Material(
      key: const Key('backup-key-card'),
      color: AgroColors.ink,
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StatusBadge(
              label: badge,
              tone: ok ? BadgeTone.ok : BadgeTone.review,
            ),
            const SizedBox(height: 10),
            Semantics(
              header: true,
              child: Text(
                'Clave de recuperación',
                style: AgroText.h2.copyWith(color: Colors.white),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              text,
              style: AgroText.detail.copyWith(color: AgroColors.onInkMuted),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (readiness == KeyringReadiness.ready) ...[
                  OutlinedButton(
                    style: onInk,
                    onPressed: _busy
                        ? null
                        : () => revealActiveRecoveryKey(context, ref),
                    child: const Text('Ver la clave'),
                  ),
                  OutlinedButton(
                    style: onInk,
                    onPressed: _busy ? null : _rotate,
                    child: const Text('Cambiar la clave'),
                  ),
                ] else if (_keyringProblem != null)
                  OutlinedButton(
                    style: onInk,
                    onPressed: _busy ? null : _replaceKeyring,
                    child: const Text('Empezar un llavero nuevo'),
                  )
                else
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AgroColors.lime,
                      foregroundColor: AgroColors.ink,
                      minimumSize: const Size(0, 52),
                    ),
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
        'RESTAURACIÓN SIN RESOLVER: copia protegida; bloquea otra '
            'restauración',
      SafetyCopyState.retained => 'Recuperación sin confirmar: copia protegida',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        const SectionHeader(title: 'Copias previas a restauraciones'),
        const SizedBox(height: 4),
        const Text(
          'Se guardan en este teléfono. Se conservan hasta dos, siete días, '
          'cuando se abre esta sección o se restaura otra copia; no hay '
          'limpieza con la aplicación cerrada. La de una restauración sin '
          'resolver, o cuya recuperación no se confirmó, no se borra.',
          style: AgroText.detail,
        ),
        const SizedBox(height: 8),
        if (!_previoReadable)
          _Tile(
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
          _Tile(
            child: ListTile(
              leading: Icon(
                entry.isProtected
                    ? Icons.shield_outlined
                    : Icons.history_outlined,
              ),
              title: Text('Del ${_date(entry.createdAt)}'),
              subtitle: Text(state(entry.state)),
              trailing: switch (entry.state) {
                SafetyCopyState.interrupted => TextButton(
                  onPressed: _busy ? null : () => _decideUnresolved(entry),
                  child: const Text('Decidir'),
                ),
                SafetyCopyState.retained => TextButton(
                  onPressed: _busy ? null : () => _confirmRecovery(entry),
                  child: const Text('Mis datos están bien'),
                ),
                _ => null,
              },
            ),
          ),
        for (final entity in _unregistered)
          _Tile(
            child: ListTile(
              leading: const Icon(Icons.inventory_outlined),
              title: Text(p.basename(entity.path)),
              subtitle: const Text('Copia sin registro'),
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
    return RdmCPage(
      title: 'Respaldos',
      subtitle:
          'Copias privadas de sus datos. No se comparten con el sindicato.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const RdmCOverline('En la nube'),
          _keyCard(),
          const SizedBox(height: 12),
          AgroGroup(
            children: [
              RdmCRow(
                key: const Key('backup-upload'),
                title: 'Subir respaldo',
                detail: 'Copia cifrada en el servidor',
                onTap: _busy ? null : _upload,
              ),
              RdmCRow(
                key: const Key('backup-list-remote'),
                title: 'Ver copias en el servidor',
                detail: 'Necesita conexión',
                trailing: _busy
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
                onTap: _busy ? null : _refresh,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_problem != null)
            EmptyState(icon: Icons.cloud_off_outlined, message: _problem!)
          else if (entries == null)
            const SizedBox.shrink()
          else if (entries.isEmpty)
            const EmptyState(
              icon: Icons.cloud_queue_outlined,
              message: 'Todavía no tiene copias en el servidor.',
            )
          else
            AgroGroup(
              children: [
                for (final entry in entries)
                  ListTile(
                    leading: Icon(
                      entry.formatVersion == 1
                          ? Icons.lock_open_outlined
                          : Icons.lock_outline,
                    ),
                    title: Text(
                      'Copia del ${_date(entry.createdAt)}',
                      style: AgroText.value,
                    ),
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
              ],
            ),
          const SizedBox(height: 8),
          // Rediseño (lámina «Respaldos»): el respaldo en un archivo de este
          // teléfono, el mismo que el menú de la carpeta de Cuentas.
          const RdmCOverline('En este teléfono'),
          AgroGroup(
            children: [
              RdmCRow(
                key: const Key('backup-local-export'),
                title: 'Exportar respaldo',
                detail: 'Archivo con sus datos y las fotos de factura',
                onTap: _busy ? null : () => exportLocalBackup(context, ref),
              ),
              RdmCRow(
                key: const Key('backup-local-restore'),
                title: 'Restaurar respaldo',
                detail: 'Reemplaza los datos actuales; antes guarda una copia',
                onTap: _busy
                    ? null
                    : () => restoreLocalBackup(
                        context,
                        ref,
                        onRestored: () {
                          if (mounted) _loadPrevio();
                        },
                      ),
              ),
            ],
          ),
          _previoSection(),
        ],
      ),
    );
  }
}

/// Una fila sobre fondo blanco (las copias previas), con la respuesta al
/// toque visible.
class _Tile extends StatelessWidget {
  const _Tile({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: AgroGroup(children: [child]),
  );
}

enum _UnresolvedChoice { continueAsIs, confirm }
