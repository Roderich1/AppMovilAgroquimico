import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/sync/consumption_publisher.dart';
import '../../domain/money.dart';
import '../../domain/sync/consumption_projection.dart';
import '../../domain/sync/sync_types.dart' show OutboxStatus;
import '../../services/sync/sync_providers.dart';
import '../widgets/common.dart';
import '../widgets/sync_status_banner.dart';

/// Publicación explícita del consumo al sindicato (MOB #33): la vista previa
/// no escribe nada; sólo «Publicar» encola, y sólo los totales que cambiaron.
class ConsumptionPublishScreen extends ConsumerStatefulWidget {
  const ConsumptionPublishScreen({super.key});

  @override
  ConsumerState<ConsumptionPublishScreen> createState() =>
      _ConsumptionPublishScreenState();
}

class _ConsumptionPublishScreenState
    extends ConsumerState<ConsumptionPublishScreen> {
  late Future<ConsumptionPreview> preview;

  ConsumptionPublisher get _publisher => ref.read(consumptionPublisherProvider);

  @override
  void initState() {
    super.initState();
    preview = _publisher.preview();
  }

  void _reload() {
    final next = _publisher.preview();
    setState(() {
      preview = next;
    });
    ref.invalidate(syncSummaryProvider);
  }

  String _total(ConsumptionPreviewRow row) =>
      formatQuantity(row.quantityBase, row.baseUnit.majorUnit);

  Future<void> _publish(ConsumptionPreview shown) async {
    final changes = shown.rows.where((row) => row.sends).toList();
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Publicar consumo'),
            content: Text(
              'Publicar al sindicato el consumo total de sus aplicaciones '
              'confirmadas:\n'
              '${changes.map((row) => '• ${row.productName} (${row.campaignName}): ${_total(row)}').join('\n')}\n'
              'Cada total sustituye al anterior; no se suma.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Publicar'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    try {
      final enqueued = await _publisher.publish(shown);
      if (!mounted) return;
      // C-01: guardado en el teléfono; la aceptación se ve en la fila.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Consumo guardado en el teléfono: $enqueued total(es). Se '
            'enviará al sindicato; aquí verá cuándo lo acepta.',
          ),
        ),
      );
      unawaited(ref.read(syncControllerProvider.notifier).kick());
    } catch (error) {
      if (mounted) showError(context, error);
    }
    if (mounted) _reload();
  }

  /// D-F04-C2: retirar del sindicato un total bloqueado, con confirmación.
  Future<void> _withdraw(ConsumptionPreviewRow row) async {
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Retirar del sindicato',
      detail:
          'Se retira del sindicato el total de ${row.productName} '
          '(${row.campaignName}) que ya tiene aceptado. Sus aplicaciones '
          'locales no cambian. Cuando el período sea compatible, podrá '
          'publicar el total vigente otra vez.',
      confirmLabel: 'Retirar',
    );
    if (!confirmed || !mounted) return;
    try {
      await _publisher.withdraw(row);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Retirada guardada en el teléfono. Se enviará al sindicato; aquí '
            'verá cuándo la acepta.',
          ),
        ),
      );
      unawaited(ref.read(syncControllerProvider.notifier).kick());
    } catch (error) {
      if (mounted) showError(context, error);
    }
    if (mounted) _reload();
  }

  Future<void> _resolve(ConsumptionPreviewRow row) async {
    try {
      final view = await ref
          .read(syncControllerProvider.notifier)
          .operationView(row.prior!.operationId);
      await _publisher.resolveConflict(row: row, view: view);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Decisión guardada en el teléfono: se enviará su total actual al '
            'sindicato; aquí verá cuándo lo acepta.',
          ),
        ),
      );
      unawaited(ref.read(syncControllerProvider.notifier).kick());
    } catch (error) {
      if (mounted) showError(context, error);
    }
    if (mounted) _reload();
  }

  /// Misma acción explícita que en Sincronización (C-02).
  Future<void> _syncNow() async {
    await ref.read(syncControllerProvider.notifier).syncNow();
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    // Un ciclo del worker cambia el estado de lo enviado: se relee al final.
    ref.listen<SyncState>(syncControllerProvider, (previous, next) {
      if (previous != null && !identical(previous.summary, next.summary)) {
        _reload();
      }
    });
    final sync = ref.watch(syncControllerProvider);
    return PageFrame(
      title: 'Consumo para el sindicato',
      subtitle:
          'Totales de sus aplicaciones confirmadas y no revertidas, por campaña '
          'y producto vinculados. Sólo se envía si usted lo confirma.',
      child: FutureBuilder<ConsumptionPreview>(
        future: preview,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Text(
              snapshot.error is ConsumptionPublishException
                  ? (snapshot.error! as ConsumptionPublishException).message
                  : 'No se pudo preparar la vista previa.',
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // C-02: por qué el worker no envía, con la acción pertinente.
              if (sync.message != null) ...[
                SyncNoticeCard(
                  message: sync.message!,
                  busy: sync.busy,
                  onSyncNow: _syncNow,
                ),
                const SizedBox(height: 8),
              ],
              FilledButton.icon(
                key: const Key('publish-consumption'),
                onPressed: data.hasChanges ? () => _publish(data) : null,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Publicar consumo al sindicato'),
              ),
              const SizedBox(height: 12),
              if (data.rows.isEmpty)
                const Text(
                  'No hay consumo propio en campañas y productos vinculados.',
                ),
              for (final row in data.rows)
                Card(
                  child: ListTile(
                    title: Text('${row.productName} · ${row.campaignName}'),
                    subtitle: Text(
                      '${_total(row)} · ${_changeLabel(row)}'
                      '${row.blockedDetail == null ? '' : '\n${row.blockedDetail}'}',
                    ),
                    isThreeLine: row.blockedDetail != null,
                    trailing: row.change == ConsumptionChange.conflict
                        ? TextButton(
                            onPressed: () => _resolve(row),
                            child: const Text('Enviar mi total actual'),
                          )
                        : row.canWithdraw
                        ? TextButton(
                            key: Key('withdraw-${row.target.productRef}'),
                            onPressed: () => _withdraw(row),
                            child: const Text('Retirar del sindicato'),
                          )
                        : null,
                  ),
                ),
              ..._exclusions(data),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => context.push('/sindicato/vinculos'),
                icon: const Icon(Icons.link),
                label: const Text('Vincular con el sindicato'),
              ),
            ],
          );
        },
      ),
    );
  }

  String _changeLabel(ConsumptionPreviewRow row) {
    final before = row.prior?.quantityBase;
    final previous = before == null
        ? ''
        : ' (antes ${formatQuantity(int.parse(before), row.baseUnit.majorUnit)})';
    return switch (row.change) {
      ConsumptionChange.publish => 'Nuevo: se publicará',
      ConsumptionChange.supersede => 'Cambió: se sustituirá$previous',
      // C-12: el estado en palabras, sin dos puntos dobles.
      ConsumptionChange.unchanged =>
        'Sin cambios · ${outboxStatusPhrase(row.prior!.status, attempts: row.prior!.attempts, conflictResolved: row.prior!.resolvedAt != null)}',
      ConsumptionChange.conflict => 'Conflicto con el sindicato: decida usted',
      ConsumptionChange.blocked =>
        row.prior != null && row.prior!.status == OutboxStatus.acked
            ? 'Vínculo no vigente: el total aceptado requiere revisión; no se '
                  'publica otro'
            : 'Vínculo no vigente: no se publica',
    };
  }

  List<Widget> _exclusions(ConsumptionPreview data) {
    final lines = data.excludedLines;
    final notes = <String>[
      if ((lines[ConsumptionExclusion.notOwner] ?? 0) > 0)
        'No se incluyen ${lines[ConsumptionExclusion.notOwner]} línea(s) de '
            'familiares o terceros: sólo se publica el consumo del titular.',
      if ((lines[ConsumptionExclusion.reversed] ?? 0) > 0)
        'No se incluyen ${lines[ConsumptionExclusion.reversed]} línea(s) de '
            'aplicaciones revertidas.',
      for (final pair in data.excludedPairs)
        // Un par bloqueado por período ya aparece arriba con su total real y
        // el detalle; aquí sólo los demás motivos.
        if (pair.detail == null)
          '${pair.product} (${pair.campaign}): ${_reason(pair.reason)}',
    ];
    if (notes.isEmpty) return const [];
    return [
      const SizedBox(height: 8),
      Text('No se publica', style: Theme.of(context).textTheme.titleSmall),
      for (final note in notes) Text('• $note'),
    ];
  }

  String _reason(ConsumptionExclusion reason) => switch (reason) {
    ConsumptionExclusion.campaignNotBound => 'la campaña no está vinculada',
    ConsumptionExclusion.campaignBindingInvalid =>
      'el vínculo de la campaña no está vigente',
    ConsumptionExclusion.productNotBound => 'el producto no está vinculado',
    ConsumptionExclusion.productBindingInvalid =>
      'el vínculo del producto no está vigente',
    ConsumptionExclusion.overflow => 'el total supera el máximo admitido',
    ConsumptionExclusion.notOwner || ConsumptionExclusion.reversed => '',
  };
}
