import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

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
/// sincronizado, conflicto, rechazado o pausado, con la fecha de la última
/// confirmación de Central.
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
          // Sin botón propio: «Sincronizar ahora» ya es la acción de la
          // página.
          if (sync.message != null) SyncNoticeCard(message: sync.message!),
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
                        // Lenguaje del agricultor (bloque X01): «confirmación»
                        // en vez de «ACK». Es el mismo estado real
                        // (`lastAcceptedAt`): que no haya confirmación no
                        // dice que Central no recibiera el envío.
                        summary.lastAcceptedAt == null
                            ? 'Todavía sin confirmación'
                            : 'Última confirmación: ${formatDate(summary.lastAcceptedAt)}',
                        // El `Chip` desvanece en silencio lo que no cabe en
                        // una línea; con fuente ampliada en 360 px la fecha
                        // no cabía. Dos líneas, nunca truncado.
                        softWrap: true,
                        maxLines: 2,
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
                    'El sindicato no autorizó esta cuenta o este '
                    'dispositivo. No se reanudan solos: con el acceso '
                    'verificado de la cuenta del titular, pulse '
                    '«Sincronizar ahora».',
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
                    for (final entry in list) ...[
                      ListTile(
                        title: Text(rowTitle(entry)),
                        subtitle: Text(rowSubtitle(entry)),
                        isThreeLine: true,
                        // C-05: el conflicto o el rechazo se decide donde
                        // vive la proyección, no aquí.
                        trailing: needsDecision(entry)
                            ? TextButton(
                                key: Key('decide-${entry.operationId}'),
                                onPressed: () =>
                                    context.push(decisionRoute(entry)),
                                child: const Text('Decidir…'),
                              )
                            : null,
                      ),
                      // El código técnico y los intentos quedan para el
                      // diagnóstico, plegados; nunca en el texto principal.
                      if (hasTechnicalDetail(entry))
                        ExpansionTile(
                          key: Key('detail-${entry.operationId}'),
                          dense: true,
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                          ),
                          title: Text(
                            'Detalle técnico',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  technicalDetail(entry),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
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

/// Nombre local del producto y de la campaña; «sin vínculo» si el vínculo ya
/// no existe (la referencia central sigue en la outbox).
String rowTitle(OutboxEntry entry) =>
    '${entry.productName ?? 'producto sin vínculo'} · '
    '${entry.campaignName ?? 'campaña sin vínculo'}';

/// Qué es el envío, en qué estado está (en palabras), cuándo se creó y, si
/// aplica, cuándo lo confirmó el sindicato; una última línea explica el
/// código técnico por familia (no el código).
String rowSubtitle(OutboxEntry entry) {
  final what =
      '${projectionLabel(entry.projectionType)} · '
      '${actionLabel(entry.action)}'
      '${entry.quantityBase == null ? '' : ' · ${formatQuantity(int.parse(entry.quantityBase!), entry.baseUnit.majorUnit)}'}';
  final state = [
    outboxStatusPhrase(
      entry.status,
      attempts: entry.attempts,
      conflictResolved: entry.resolvedAt != null,
    ),
    'creada ${formatDate(entry.createdAt)}',
    if (entry.ackedAt != null) 'Confirmado: ${formatDate(entry.ackedAt)}',
  ].join(' · ');
  final explanation = entry.status == OutboxStatus.acked
      ? null
      : syncCodeExplanation(entry.lastCode);
  return [what, state, if (explanation != null) explanation].join('\n');
}

bool needsDecision(OutboxEntry entry) =>
    (entry.status == OutboxStatus.conflict && entry.resolvedAt == null) ||
    entry.status == OutboxStatus.rejected ||
    entry.status == OutboxStatus.failed;

String decisionRoute(OutboxEntry entry) => switch (entry.projectionType) {
  ProjectionType.declaredNeed => '/planificacion/necesidades',
  ProjectionType.consumptionTotal => '/sincronizacion/consumo',
};

bool hasTechnicalDetail(OutboxEntry entry) =>
    entry.attempts > 0 || entry.lastCode != null || entry.nextAttemptAt != null;

/// Código, intentos, próximo intento (hora local del teléfono, como todos
/// los instantes) y la referencia del envío, para soporte.
String technicalDetail(OutboxEntry entry) => [
  'Código: ${entry.lastCode ?? '—'}',
  'Intentos: ${entry.attempts}',
  if (entry.nextAttemptAt != null)
    'Próximo intento: ${formatInstant(entry.nextAttemptAt!)}',
  'Envío: ${entry.operationId}',
].join(' · ');

/// `dd/mm/aaaa hh:mm` en hora local; mismo criterio que [formatDate] para
/// los instantes (`Z` → día y hora del teléfono). Patrón numérico, sin
/// locale.
String formatInstant(String iso) {
  final parsed = DateTime.tryParse(iso)?.toLocal();
  if (parsed == null) return iso;
  return DateFormat('dd/MM/yyyy HH:mm').format(parsed);
}
