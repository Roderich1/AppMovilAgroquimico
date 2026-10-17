import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/money.dart';
import '../../domain/sync/sync_types.dart';
import '../../services/sync/sync_providers.dart';
import '../widgets/common.dart';
import '../widgets/sync_status_banner.dart';

String projectionLabel(ProjectionType type) => switch (type) {
  ProjectionType.declaredNeed => 'Necesidad declarada',
  ProjectionType.consumptionTotal => 'Consumo total',
};

String actionLabel(SyncAction action) => switch (action) {
  SyncAction.publish => 'Publicar',
  SyncAction.supersede => 'Sustituir',
  SyncAction.cancel => 'Retirar',
};

/// Estado de lo que se envía al sindicato (RF-18): pendiente, enviando,
/// sincronizado, conflicto, rechazado o pausado, con la fecha del último ACK.
/// No muestra nada de otras personas: la outbox sólo tiene totales propios.
class SyncStatusScreen extends ConsumerStatefulWidget {
  const SyncStatusScreen({super.key});
  @override
  ConsumerState<SyncStatusScreen> createState() => _SyncStatusScreenState();
}

class _SyncStatusScreenState extends ConsumerState<SyncStatusScreen> {
  late Future<List<OutboxEntry>> entries;

  @override
  void initState() {
    super.initState();
    entries = ref.read(syncOutboxStoreProvider).entries();
    ref.read(syncControllerProvider.notifier).refreshSummary();
  }

  void _reload() {
    final next = ref.read(syncOutboxStoreProvider).entries();
    setState(() {
      entries = next;
    });
    ref.invalidate(syncSummaryProvider);
  }

  Future<void> _syncNow() async {
    final report = await ref.read(syncControllerProvider.notifier).syncNow();
    if (!mounted) return;
    _reload();
    final message = ref.read(syncControllerProvider).message;
    if (report != null && message == null) {
      showSuccess(
        context,
        report.sent == 0
            ? 'No hay envíos pendientes.'
            : 'Aceptados: ${report.accepted}. Conflictos: ${report.conflicts}. '
                  'Rechazados: ${report.rejected}.',
      );
    }
  }

  Future<void> _releaseRestored() async {
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Liberar envíos restaurados',
      detail:
          'Estos envíos llegaron con un respaldo restaurado. Se enviarán con '
          'su mismo contenido, sólo si la cuenta en sesión es la del titular.',
      confirmLabel: 'Liberar',
    );
    if (!confirmed || !mounted) return;
    final released = await ref
        .read(syncControllerProvider.notifier)
        .releaseRestored();
    if (!mounted) return;
    _reload();
    if (released > 0) showSuccess(context, 'Liberados: $released.');
  }

  @override
  Widget build(BuildContext context) {
    // Un ciclo del worker que no se esperó aquí (el que lanza «Liberar», el
    // temporizador o una reconexión) cambia el estado de las filas. Lo último
    // de cada ciclo es publicar el resumen nuevo: entonces se relee la lista,
    // como en Necesidades declaradas. Visto en el POCO: tras «Liberar», el
    // resumen decía «Sincronizado» y la fila seguía «Pendiente (sin
    // confirmar)» hasta volver a entrar.
    ref.listen<SyncState>(syncControllerProvider, (previous, next) {
      if (previous != null && !identical(previous.summary, next.summary)) {
        _reload();
      }
    });
    final sync = ref.watch(syncControllerProvider);
    final summary = sync.summary;
    return PageFrame(
      title: 'Sincronización',
      subtitle: 'Lo que se envía al sindicato: sólo totales propios.',
      action: FilledButton.icon(
        onPressed: sync.busy ? null : _syncNow,
        icon: const Icon(Icons.sync),
        label: const Text('Sincronizar ahora'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (sync.message != null)
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(sync.message!),
              ),
            ),
          if (summary != null) ...[
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final status in OutboxStatus.values)
                      if (summary.count(status) > 0)
                        Chip(
                          label: Text(
                            '${outboxStatusLabel(status)}: ${summary.count(status)}',
                          ),
                        ),
                    Chip(
                      avatar: const Icon(Icons.schedule, size: 16),
                      label: Text(
                        summary.lastAcceptedAt == null
                            ? 'Sin ACK todavía'
                            : 'Último ACK: ${formatDate(summary.lastAcceptedAt)}',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // C40/C22 (#18): tras un 403, verificar el acceso no reanuda nada
            // por sí solo; la acción explícita es «Sincronizar ahora».
            if (summary.count(OutboxStatus.authPaused) > 0) ...[
              const SizedBox(height: 8),
              const Card(
                child: ListTile(
                  leading: Icon(Icons.lock_outline),
                  title: Text('Envíos pausados por autorización'),
                  subtitle: Text(
                    'El sindicato rechazó un envío (403). No se reanudan '
                    'solos: con el acceso verificado de la cuenta del '
                    'titular, pulse «Sincronizar ahora».',
                  ),
                ),
              ),
            ],
            // D-F04-C2: intenciones que nunca salieron y no se envían porque
            // el período local de su campaña no cabe en el central (o no se
            // comprobó). Se resuelven en «Vincular con el sindicato».
            if (summary.heldForPeriod > 0) ...[
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  key: const Key('held-for-period'),
                  leading: const Icon(Icons.event_busy_outlined),
                  title: Text(
                    'Envíos retenidos por el período de la campaña: '
                    '${summary.heldForPeriod}',
                  ),
                  subtitle: const Text(
                    'El período de la campaña local no cabe en el de la '
                    'campaña del sindicato, o no se ha comprobado. No se '
                    'envían ni se borran: fije el fin previsto o actualice '
                    'las referencias en «Vincular con el sindicato».',
                  ),
                  trailing: TextButton(
                    onPressed: () => context.push('/sindicato/vinculos'),
                    child: const Text('Revisar'),
                  ),
                ),
              ),
            ],
            if (summary.count(OutboxStatus.restorePaused) > 0) ...[
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.restore),
                  title: const Text('Envíos pausados por una restauración'),
                  subtitle: const Text(
                    'No se publican solos. Revíselos y libérelos si son suyos.',
                  ),
                  trailing: TextButton(
                    onPressed: _releaseRestored,
                    child: const Text('Liberar'),
                  ),
                ),
              ),
            ],
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => context.push('/sindicato/vinculos'),
                icon: const Icon(Icons.link),
                label: const Text('Vincular con el sindicato'),
              ),
              OutlinedButton.icon(
                onPressed: () => context.push('/planificacion/necesidades'),
                icon: const Icon(Icons.playlist_add_check),
                label: const Text('Necesidades declaradas'),
              ),
              OutlinedButton.icon(
                key: const Key('open-consumption-publish'),
                onPressed: () => context.push('/sincronizacion/consumo'),
                icon: const Icon(Icons.water_drop_outlined),
                label: const Text('Consumo para el sindicato'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<OutboxEntry>>(
            future: entries,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return EmptyState(
                  icon: Icons.error_outline,
                  message: friendlyError(snapshot.error!),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final list = snapshot.data!;
              if (list.isEmpty) {
                return const EmptyState(
                  icon: Icons.cloud_done_outlined,
                  message: 'Todavía no hay nada que enviar al sindicato.',
                );
              }
              return Card(
                child: Column(
                  children: [
                    for (final entry in list)
                      ListTile(
                        title: Text(
                          '${projectionLabel(entry.projectionType)} · '
                          '${actionLabel(entry.action)}'
                          '${entry.quantityBase == null ? '' : ' · ${formatQuantity(int.parse(entry.quantityBase!), entry.baseUnit.majorUnit)}'}',
                        ),
                        subtitle: Text(
                          [
                            outboxStatusLabel(entry.status),
                            if (entry.lastCode != null &&
                                entry.status != OutboxStatus.acked)
                              entry.lastCode!,
                            'creada ${formatDate(entry.createdAt)}',
                            if (entry.ackedAt != null)
                              'ACK ${formatDate(entry.ackedAt)}',
                          ].join(' · '),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
