import 'package:flutter/material.dart';

import '../../data/agro_repository.dart';
import '../../data/typed_reads.dart';
import '../../domain/campaign_calendar.dart';
import '../../domain/money.dart';
import 'catalog_dialogs.dart';
import 'common.dart';

/// Reglas de campaña en la interfaz (RN-15, RN-16, UIBUG-059, #110, #122,
/// #125), compartidas por la pantalla Campañas y la sección Campañas de
/// Catálogos: activar (con «Cerrar y activar» si hay otra activa), cerrar
/// con su resumen y fin efectivo, y el alta con su día de inicio. Cada
/// función devuelve si algo cambió; los errores del repositorio se propagan
/// para que la pantalla los muestre.

/// Activa [row]. Si otra está activa, ofrece cerrarla y activar ésta.
Future<bool> activateCampaignFlow(
  BuildContext context,
  AgroRepository repo,
  Map<String, Object?> row,
) async {
  try {
    await repo.activateCampaign(row['id'] as int);
    return true;
  } on CampaignConflictException catch (conflict) {
    if (!context.mounted) return false;
    final replace = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cambiar campaña activa'),
        content: Text(
          'Está activa ${conflict.activeCampaignName}. ¿Desea cerrarla y activar ${row['name']}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cerrar y activar'),
          ),
        ],
      ),
    );
    if (replace != true) return false;
    await repo.activateCampaign(row['id'] as int, closeCurrent: true);
    return true;
  }
}

/// Cierra [row] después de mostrar su resumen y elegir el fin efectivo.
Future<bool> closeCampaignFlow(
  BuildContext context,
  AgroRepository repo,
  Map<String, Object?> row,
) async {
  final summary = await repo.campaignCloseSummaryTyped(row['id'] as int);
  if (!context.mounted) return false;
  // Fin del período (RN-16; «las fechas concretas son configuración»):
  // el fin **efectivo** se elige siempre, hoy por defecto, también si
  // el alta de la siguiente o «Fijar fin previsto…» ya fijaron un fin
  // (#122). Ese fin previsto se muestra aparte y no se conserva en
  // silencio; el repositorio vuelve a validar.
  final plannedEnd = row['end_date'] as String?;
  // El fin más tardío admitido es hoy, o el inicio si la campaña todavía
  // no empezó (revisión de B sobre #110); es también el que se propone.
  final start = DateTime.parse(row['start_date']! as String).toLocal();
  final now = DateTime.now();
  final latestEnd = start.isAfter(now) ? start : now;
  var end = latestEnd;
  final confirm = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text('¿Cerrar ${row['name']}?'),
        // Cerrar dejó de ser reversible desde la aplicación (UIBUG-059),
        // así que la confirmación tiene que decirlo antes, no después:
        // qué campaña, desde cuándo, qué deja de admitir y que no podrá
        // reactivarse.
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (plannedEnd != null)
              ListTile(
                key: const Key('campaign-close-planned-end'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_note_outlined),
                title: const Text('Fin previsto'),
                subtitle: Text(
                  '${formatDate(plannedEnd)}. El fin efectivo que '
                  'confirme abajo lo sustituye.',
                ),
              ),
            ListTile(
              key: const Key('campaign-close-end'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: const Text('Termina el'),
              subtitle: Text(formatDate(end.toIso8601String())),
              trailing: const Text('Cambiar'),
              onTap: () async {
                final picked = await showDatePicker(
                  context: dialogContext,
                  initialDate: end,
                  firstDate: DateTime(2000),
                  // Un fin futuro no se admite (el repositorio lo
                  // rechaza también).
                  lastDate: latestEnd,
                );
                if (picked != null) setDialogState(() => end = picked);
              },
            ),
            Text(
              'Periodo: desde ${formatDate(row['start_date'])}.\n\n'
              'Compras: ${summary.purchasesCount} · aplicaciones: ${summary.applicationsCount}\n'
              'Planes pendientes: ${summary.pendingPlans}\n'
              'Deuda pendiente por origen: ${formatBob(summary.receivableBobMinor)}\n\n'
              'La campaña dejará de admitir nuevas compras, aplicaciones, '
              'transferencias y planes.\n\n'
              'Una campaña cerrada NO se puede volver a activar desde la '
              'aplicación. Si necesita seguir operando, cree una campaña '
              'nueva.\n\n'
              'El inventario físico no se elimina y seguirá disponible en la próxima campaña.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            // Mismo criterio visual de acción irreversible que las
            // reversiones (UIBUG-033).
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cerrar definitivamente'),
          ),
        ],
      ),
    ),
  );
  if (confirm != true) return false;
  await repo.closeCampaign(row['id'] as int, end: end);
  return true;
}

/// Alta de campaña: nombre y día de inicio, sugerido por el repositorio.
Future<bool> addCampaignFlow(BuildContext context, AgroRepository repo) async {
  // RN-16: el inicio se elige (antes era siempre el día de alta) y el
  // repositorio comprueba que no solape ni deje operaciones fuera.
  final suggested = await repo.suggestedCampaignStart();
  if (!context.mounted) return false;
  final result = await showDialog<(String, DateTime)?>(
    context: context,
    builder: (_) => CampaignDialog(suggestedStart: suggested),
  );
  if (result == null) return false;
  await repo.addCampaign(name: result.$1, start: result.$2);
  return true;
}

/// Estado y período de la campaña. Una planificada cuyo inicio aún no llegó,
/// mientras otra está activa, dice desde cuándo se podrá activar (#125): el
/// camino válido es esperar a ese día; «Cerrar y activar» no se ofrece
/// antes, y el repositorio lo rechaza igual si se llega por otra vía.
String campaignSubtitle(
  Map<String, Object?> row,
  List<Map<String, Object?>> all,
) {
  final start = row['start_date']! as String;
  final end = row['end_date'] as String?;
  var text =
      '${campaignStatusLabel(row['status'])} · ${formatDate(start)}'
      '${end == null ? '' : ' – ${formatDate(end)}'}';
  if (row['status'] == 'PLANNED' &&
      storedLocalDay(start).compareTo(localDay(DateTime.now())) > 0 &&
      all.any((r) => r['status'] == 'ACTIVE')) {
    text += ' · Se podrá activar desde el ${formatDate(start)}';
  }
  return text;
}
