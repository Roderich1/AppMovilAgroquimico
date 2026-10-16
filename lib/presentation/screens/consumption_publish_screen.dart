import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/sync/consumption_publisher.dart';
import '../../domain/money.dart';
import '../../domain/sync/consumption_projection.dart';
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Consumo listo para enviar: $enqueued total(es).'),
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
          content: Text('Decisión registrada: se enviará su total actual.'),
        ),
      );
      unawaited(ref.read(syncControllerProvider.notifier).kick());
    } catch (error) {
      if (mounted) showError(context, error);
    }
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
                    subtitle: Text('${_total(row)} · ${_changeLabel(row)}'),
                    trailing: row.change == ConsumptionChange.conflict
                        ? TextButton(
                            onPressed: () => _resolve(row),
                            child: const Text('Enviar mi total actual'),
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
      ConsumptionChange.unchanged =>
        'Sin cambios: ${outboxStatusLabel(row.prior!.status)}',
      ConsumptionChange.conflict => 'Conflicto con el sindicato: decida usted',
      ConsumptionChange.blocked => 'Vínculo no vigente: no se publica',
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
