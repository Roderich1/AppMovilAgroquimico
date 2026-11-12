import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../data/sync/sync_outbox_store.dart' show SyncQueueSummary;
import '../../domain/money.dart';
import '../../domain/sync/sync_types.dart';
import '../../services/sync/sync_providers.dart';
import '../theme/agro_theme.dart';
import '../widgets/agro_ui.dart';
import '../widgets/common.dart';
import '../widgets/rdm_c_page.dart';
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

  /// 422 CONTRACT_VERSION_MISMATCH (F05 matriz C25): la reanudación es una
  /// decisión del titular, nunca automática. Se reenvía el mismo contenido.
  Future<void> _resumeVersionMismatch() async {
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Reintentar con esta versión',
      detail:
          'El sindicato no aceptó estos envíos porque la aplicación tenía '
          'una versión distinta. Si ya actualizó la aplicación, se volverán '
          'a enviar con su mismo contenido. Si el sindicato los sigue '
          'rechazando, quedarán pausados otra vez; nada se borra.',
      confirmLabel: 'Reintentar',
    );
    if (!confirmed || !mounted) return;
    final resumed = await ref
        .read(syncControllerProvider.notifier)
        .resumeVersionMismatch();
    if (!mounted) return;
    _reload();
    if (resumed > 0) showSuccess(context, 'Reanudados: $resumed.');
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
    return RdmCPage(
      title: 'Sincronización',
      subtitle: 'Lo que se envía al sindicato: sólo totales propios.',
      action: FilledButton.icon(
        onPressed: sync.busy ? null : _syncNow,
        style: FilledButton.styleFrom(
          backgroundColor: AgroColors.lime,
          foregroundColor: AgroColors.ink,
          minimumSize: const Size(0, 44),
        ),
        icon: const Icon(Icons.sync),
        label: const Text('Sincronizar ahora'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sin botón propio: «Sincronizar ahora» ya es la acción de la
          // página.
          if (sync.message != null) ...[
            SyncNoticeCard(message: sync.message!),
            const SizedBox(height: 8),
          ],
          if (summary != null) ...[
            _SummaryCard(summary: summary),
            // C40/C22 (#18): tras un 403, verificar el acceso no reanuda nada
            // por sí solo; la acción explícita es «Sincronizar ahora».
            if (summary.count(OutboxStatus.authPaused) > 0)
              const _SyncNotice(
                icon: Icons.lock_outline,
                title: 'Envíos pausados por autorización',
                body:
                    'El sindicato no autorizó esta cuenta o este '
                    'dispositivo. No se reanudan solos: con el acceso '
                    'verificado de la cuenta del titular, pulse '
                    '«Sincronizar ahora».',
              ),
            // D-F04-C2: intenciones que nunca salieron y no se envían porque
            // el período local de su campaña no cabe en el central (o no se
            // comprobó). Se resuelven en «Vincular con el sindicato».
            if (summary.heldForPeriod > 0)
              _SyncNotice(
                key: const Key('held-for-period'),
                icon: Icons.event_busy_outlined,
                title:
                    'Envíos retenidos por el período de la campaña: '
                    '${summary.heldForPeriod}',
                body:
                    'El período de la campaña local no cabe en el de la '
                    'campaña del sindicato, o no se ha comprobado. No se '
                    'envían ni se borran: fije el fin previsto o actualice '
                    'las referencias en «Vincular con el sindicato».',
                action: TextButton(
                  onPressed: () => context.push('/sindicato/vinculos'),
                  child: const Text('Revisar'),
                ),
              ),
            if (summary.count(OutboxStatus.restorePaused) > 0)
              _SyncNotice(
                icon: Icons.restore,
                title: 'Envíos pausados por una restauración',
                body:
                    'No se publican solos. Revíselos y libérelos si son '
                    'suyos.',
                action: TextButton(
                  onPressed: _releaseRestored,
                  child: const Text('Liberar'),
                ),
              ),
            // 422 CONTRACT_VERSION_MISMATCH: pausado por versión; sólo el
            // titular lo reanuda, normalmente tras actualizar la aplicación.
            // Sin consultas nuevas: el contador ya está en el resumen.
            if (summary.count(OutboxStatus.versionMismatch) > 0)
              _SyncNotice(
                key: const Key('version-mismatch'),
                icon: Icons.system_update_alt,
                title:
                    'Envíos pausados por una versión distinta de la '
                    'aplicación',
                body:
                    'El sindicato no los aceptó con la versión anterior. '
                    'No se reanudan solos ni se borran: actualice la '
                    'aplicación y vuelva a intentarlo.',
                // La etiqueta es larga: debajo del texto, nunca al lado,
                // para que quepa con fuente ampliada en 360 px.
                action: TextButton(
                  onPressed: _resumeVersionMismatch,
                  child: const Text('Reintentar con esta versión'),
                ),
              ),
          ],
          const SizedBox(height: 16),
          AgroGroup(
            children: [
              RdmCRow(
                title: 'Productos y campañas',
                detail: 'Vincular con el sindicato',
                onTap: () => context.push('/sindicato/vinculos'),
              ),
              RdmCRow(
                title: 'Necesidad declarada',
                detail: 'Lo que solicita para la campaña',
                onTap: () => context.push('/planificacion/necesidades'),
              ),
              RdmCRow(
                key: const Key('open-consumption-publish'),
                title: 'Consumo para el sindicato',
                detail: 'Totales de lo que usted aplicó',
                onTap: () => context.push('/sincronizacion/consumo'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const SectionHeader(title: 'Envíos'),
          const SizedBox(height: 10),
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
                return const RdmCEmpty(
                  icon: Icons.cloud_done_outlined,
                  message: 'Todavía no hay nada que enviar al sindicato.',
                );
              }
              return AgroGroup(
                children: [
                  for (final entry in list)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        RdmCRow(
                          title: rowTitle(entry),
                          detail: rowSubtitle(entry),
                          // C-05: el conflicto se decide y el rechazo se
                          // revisa donde vive la proyección, no aquí.
                          actions: [
                            if (needsDecision(entry))
                              TextButton(
                                key: Key('decide-${entry.operationId}'),
                                onPressed: () =>
                                    context.push(decisionRoute(entry)),
                                child: Text(decisionLabel(entry)),
                              ),
                          ],
                        ),
                        // El código técnico y los intentos quedan para el
                        // diagnóstico, plegados; nunca en el texto
                        // principal.
                        if (hasTechnicalDetail(entry))
                          Material(
                            type: MaterialType.transparency,
                            child: ExpansionTile(
                              key: Key('detail-${entry.operationId}'),
                              dense: true,
                              shape: const Border(),
                              collapsedShape: const Border(),
                              tilePadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              title: Text(
                                'Detalle técnico',
                                style: AgroText.detail,
                              ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    12,
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      technicalDetail(entry),
                                      style: AgroText.detail,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Resumen de la cola: cuántos envíos hay en cada estado (palabra y número)
/// y la última confirmación del sindicato.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});
  final SyncQueueSummary summary;

  @override
  Widget build(BuildContext context) {
    final counts = [
      for (final status in OutboxStatus.values)
        if (summary.count(status) > 0)
          StatusBadge(
            label: '${outboxStatusLabel(status)}: ${summary.count(status)}',
            tone: rdmCOutboxTone(status),
          ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (counts.isNotEmpty)
          AgroGroup(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(spacing: 6, runSpacing: 6, children: counts),
              ),
            ],
          ),
        // A todo el ancho y fuera de la tarjeta: con 360 dp y la letra al
        // 130 % la fecha cabe entera en dos líneas como máximo.
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text(
            // Lenguaje del agricultor (bloque X01): «confirmación» en vez de
            // «ACK». Es el mismo estado real (`lastAcceptedAt`): que no haya
            // confirmación no dice que Central no recibiera el envío.
            summary.lastAcceptedAt == null
                ? 'Todavía sin confirmación'
                : 'Última confirmación: ${formatDate(summary.lastAcceptedAt)}',
            // 12 px que siguen la escala del teléfono (el chip anterior no la
            // seguía): con 360 dp y 130 % la fecha cabe en dos líneas.
            style: AgroText.detail.copyWith(
              color: AgroColors.ink,
              fontSize: 12,
              height: 18 / 12,
            ),
          ),
        ),
      ],
    );
  }
}

/// Aviso con título, explicación y, si hay, la acción debajo (nunca al
/// lado: con la letra ampliada no cabría).
class _SyncNotice extends StatelessWidget {
  const _SyncNotice({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: AgroColors.warnBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AgroColors.warnInk, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AgroText.question.copyWith(color: AgroColors.warnInk),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: AgroText.detail.copyWith(color: AgroColors.warnInk),
                ),
                if (action != null)
                  Align(alignment: Alignment.centerRight, child: action),
              ],
            ),
          ),
        ],
      ),
    ),
  );
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
  final explanation = rowExplanation(entry);
  return [what, state, if (explanation != null) explanation].join('\n');
}

/// Explicación por familia del código, salvo cuando no añade nada: aceptado
/// (`OK`), pausado por autorización (la frase de estado ya lo dice) o una
/// frase idéntica a la del estado.
String? rowExplanation(OutboxEntry entry) {
  if (entry.status == OutboxStatus.acked ||
      entry.status == OutboxStatus.authPaused) {
    return null;
  }
  final explanation = syncCodeExplanation(entry.lastCode);
  final phrase = outboxStatusPhrase(
    entry.status,
    attempts: entry.attempts,
    conflictResolved: entry.resolvedAt != null,
  );
  return explanation == phrase ? null : explanation;
}

bool needsDecision(OutboxEntry entry) =>
    (entry.status == OutboxStatus.conflict && entry.resolvedAt == null) ||
    entry.status == OutboxStatus.rejected ||
    entry.status == OutboxStatus.failed;

/// «Decidir…» sólo donde hay una decisión (conflicto); un rechazo se revisa.
String decisionLabel(OutboxEntry entry) =>
    entry.status == OutboxStatus.conflict ? 'Decidir…' : 'Revisar…';

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
