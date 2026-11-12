import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app.dart';
import '../../domain/restore_ownership.dart';
import '../../guarded_restore.dart';
import 'common.dart';
import 'identification_texts.dart' show labelPhotosNotInBackups;

/// Respaldo LOCAL (archivo en este teléfono): exportar y restaurar.
///
/// Rediseño (2026-11-12, lámina «Respaldos»): las mismas acciones que el menú
/// de la carpeta de Cuentas, sacadas a funciones para que también las ofrezca
/// la pantalla «Respaldos». El procedimiento, los textos y las guardas son
/// los de `settlements_screen.dart` en la base `01b2576`: valida el archivo,
/// comprueba de quién es, avisa de que reemplaza todo y sólo entonces
/// sustituye la base, en exclusiva (`GuardedRestore`). La copia previa se
/// conserva siempre.

/// Exporta un respaldo local y avisa del resultado (y de sus discrepancias).
Future<void> exportLocalBackup(BuildContext context, WidgetRef ref) async {
  try {
    final result = await ref.read(backupServiceProvider).export();
    if (!context.mounted) return;
    final photos = result.attachmentCount == 1
        ? '1 fotografía de factura'
        : '${result.attachmentCount} fotografías de factura';
    showSuccess(
      context,
      'Respaldo guardado en ${result.path} (base de datos y $photos). '
      '$labelPhotosNotInBackups',
    );
    // Una discrepancia no puede quedarse en silencio: si una factura ya no
    // tiene su foto en el teléfono, el usuario tiene que enterarse ahora y no
    // el día que necesite restaurar.
    if (result.hasWarnings) {
      await _showNotices(context, 'Respaldo', result.warnings);
    }
  } catch (error) {
    if (context.mounted) showError(context, error);
  }
}

/// Restaura un respaldo local elegido de la lista. [onRestored] se llama al
/// terminar bien (p. ej. para recargar la pantalla).
Future<void> restoreLocalBackup(
  BuildContext context,
  WidgetRef ref, {
  VoidCallback? onRestored,
}) async {
  final service = ref.read(backupServiceProvider);
  final guarded = ref.read(guardedRestoreProvider);
  final List<File> backups;
  try {
    backups = await service.listAvailableBackups();
  } catch (error) {
    if (context.mounted) showError(context, error);
    return;
  }
  if (!context.mounted) return;
  if (backups.isEmpty) {
    // No es un error: es una indicación normal la primera vez (UIBUG-050).
    showSuccess(
      context,
      'Todavía no hay ningún respaldo. Use "Exportar respaldo" para crear el '
      'primero.',
    );
    return;
  }

  final chosen = await showDialog<File>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Restaurar respaldo'),
      content: SizedBox(
        width: 520,
        height: 320,
        child: ListView(
          children: [
            for (final file in backups)
              ListTile(
                leading: const Icon(Icons.restore_page_outlined),
                title: Text(p.basename(file.path)),
                subtitle: Text(
                  '${file.statSync().modified.toString().substring(0, 16)} · '
                  '${(file.statSync().size / 1024).round()} KB',
                ),
                onTap: () => Navigator.pop(dialogContext, file),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancelar'),
        ),
      ],
    ),
  );
  if (chosen == null || !context.mounted) return;

  final validation = await service.validate(chosen.path);
  if (!context.mounted) return;
  if (!validation.isValid) {
    showError(context, validation.problem!);
    return;
  }

  // De quién es la copia, antes de pedir confirmación. Una copia ajena o
  // ilegible no llega a ofrecerse (y la restauración lo vuelve a comprobar).
  final RestoreOwnershipVerdict ownership;
  try {
    ownership = await guarded.preview(chosen.path);
  } on Object catch (error) {
    if (context.mounted) showError(context, error);
    return;
  }
  if (!context.mounted) return;
  if (!ownership.accepted) {
    showError(context, ownership.message);
    return;
  }

  // Qué trae exactamente el archivo, antes de reemplazar nada. El formato
  // histórico sólo guarda la base: conviene saberlo ANTES de aceptar.
  final contents = validation.isLegacyWithoutPhotos
      ? 'Formato histórico: contiene la base de datos, pero NO las '
            'fotografías de factura. Las fotografías actuales del teléfono '
            'se conservan.'
      : 'Contiene la base de datos y ${validation.attachmentCount} '
            'fotografía(s) de factura. $labelPhotosNotInBackups';

  final confirmed = await confirmDestructiveAction(
    context,
    title: '¿Restaurar este respaldo?',
    detail:
        '${p.basename(chosen.path)}\n'
        'Esquema versión ${validation.schemaVersion}\n'
        '$contents\n'
        '${ownership.message}\n\n'
        'TODOS los datos actuales se reemplazarán por los del respaldo. '
        'Se guardará automáticamente una copia de los datos actuales por si '
        'necesita volver atrás.',
    confirmLabel: 'Restaurar',
  );
  if (!confirmed || !context.mounted) return;

  // El aviso sobrevive a la navegación: si la base restaurada no habilita
  // operaciones, el router lleva a la pantalla de acceso.
  final messenger = ScaffoldMessenger.of(context);
  final errorColor = Theme.of(context).colorScheme.error;
  try {
    final result = (await guarded.restore(chosen.path)).result;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Respaldo restaurado (${result.restoredAttachments} '
          'fotografía(s)). Copia de los datos anteriores: '
          '${result.safetyCopyPath}',
        ),
      ),
    );
    onRestored?.call();
    if (result.warnings.isNotEmpty && context.mounted) {
      await _showNotices(context, 'Restauración', result.warnings);
    }
  } catch (error) {
    // También si la pantalla ya no está: un «No pudimos confirmar…» no puede
    // perderse (F08-PREV-01).
    showErrorOn(messenger, errorColor, error);
  }
}

/// Avisos que acompañan a una operación que sí terminó.
Future<void> _showNotices(
  BuildContext context,
  String title,
  List<String> notices,
) async {
  if (!context.mounted || notices.isEmpty) return;
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
