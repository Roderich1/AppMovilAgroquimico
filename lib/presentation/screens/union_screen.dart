import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/sync/sync_outbox_store.dart' show SyncQueueSummary;
import '../../domain/money.dart' show formatDate;
import '../../services/sync/sync_providers.dart';
import '../theme/agro_theme.dart';
import '../widgets/agro_ui.dart';
import '../widgets/common.dart';
import '../widgets/joint_purchase_texts.dart' show jointPurchaseNoticeText;
import '../widgets/rdm_c_page.dart';
import '../widgets/sync_status_banner.dart'
    show SyncNoticeCard, syncSummaryProvider;

/// «Sindicato» (rediseño, lámina «Sindicato»): punto de entrada a lo que se
/// comparte con el sindicato. Esqueleto creado por el orquestador; contenido
/// de la sesión C (`docs/rediseno/COORDINACION.md`).
///
/// Sólo muestra lo que ya exponen los proveedores sin consultas nuevas: el
/// resumen de la cola de envíos (totales propios) y el aviso de convocatoria
/// nueva. Cada pantalla conserva sus guardas y sus reglas; «Enviar» es la
/// misma acción expresa que «Sincronizar ahora».
class UnionScreen extends ConsumerStatefulWidget {
  const UnionScreen({super.key});

  /// Lo que se comparte con el sindicato, en el orden de la lámina.
  static const shared =
      <({String key, String title, String subtitle, String path})>[
        (
          key: 'union-needs',
          title: 'Necesidad declarada',
          subtitle: 'Lo que solicita para la campaña',
          path: '/planificacion/necesidades',
        ),
        (
          key: 'union-consumption',
          title: 'Consumo',
          subtitle: 'Totales de lo que usted aplicó',
          path: '/sincronizacion/consumo',
        ),
        (
          key: 'union-links',
          title: 'Productos y campañas',
          subtitle: 'Sus equivalentes en el sindicato',
          path: '/sindicato/vinculos',
        ),
      ];

  @override
  ConsumerState<UnionScreen> createState() => _UnionScreenState();
}

class _UnionScreenState extends ConsumerState<UnionScreen> {
  /// Misma acción expresa que «Sincronizar ahora» (C-02): verifica el acceso
  /// si hace falta y lanza un ciclo; el motivo de no enviar se muestra aquí.
  Future<void> _send() async {
    final report = await ref.read(syncControllerProvider.notifier).syncNow();
    if (!mounted) return;
    ref.invalidate(syncSummaryProvider);
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

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(syncControllerProvider);
    final summary = ref.watch(syncSummaryProvider).value;
    final notice = ref.watch(jointPurchaseNoticeProvider).value;
    return RdmCPage(
      title: 'Sindicato',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SendCard(
            summary: summary,
            busy: sync.busy,
            onOpen: () => context.push('/sincronizacion'),
            onSend: _send,
          ),
          if (sync.message != null) ...[
            const SizedBox(height: 10),
            SyncNoticeCard(message: sync.message!),
          ],
          const SizedBox(height: 16),
          const SectionHeader(title: 'Compras conjuntas'),
          const SizedBox(height: 10),
          AgroGroup(
            children: [
              RdmCRow(
                key: const Key('union-joint-purchases'),
                title: 'Convocatorias',
                detail: notice == null
                    ? 'Convocatorias del sindicato y su participación'
                    : jointPurchaseNoticeText(notice),
                badges: [
                  if (notice != null)
                    const StatusBadge(label: 'Nueva', tone: BadgeTone.voice),
                ],
                onTap: () => context.push('/compras-conjuntas'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const SectionHeader(title: 'Lo que comparte'),
          const SizedBox(height: 10),
          AgroGroup(
            children: [
              for (final entry in UnionScreen.shared)
                RdmCRow(
                  key: Key(entry.key),
                  title: entry.title,
                  detail: entry.subtitle,
                  onTap: () => context.push(entry.path),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Tarjeta oscura de la lámina: cuántos envíos de totales propios esperan,
/// la última confirmación del sindicato y «Enviar». Tocarla abre
/// Sincronización con el detalle.
class _SendCard extends StatelessWidget {
  const _SendCard({
    required this.summary,
    required this.busy,
    required this.onOpen,
    required this.onSend,
  });

  final SyncQueueSummary? summary;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onSend;

  String get _headline {
    final waiting = summary?.waiting ?? 0;
    if (summary == null) return 'Envíos al sindicato';
    if (waiting == 0) return 'Nada pendiente de envío';
    return waiting == 1 ? '1 envío pendiente' : '$waiting envíos pendientes';
  }

  @override
  Widget build(BuildContext context) {
    final current = summary;
    final attention = current?.needsAttention ?? 0;
    final lines = <String>[
      if (current != null)
        // «Confirmación» y no «envío»: es el estado real (`lastAcceptedAt`).
        current.lastAcceptedAt == null
            ? 'Todavía sin confirmación'
            : 'Última confirmación: ${formatDate(current.lastAcceptedAt)}',
      if (attention > 0)
        attention == 1
            ? '1 requiere atención'
            : '$attention requieren atención',
    ];
    return Semantics(
      container: true,
      child: Material(
        key: const Key('union-sync'),
        color: AgroColors.ink,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _headline,
                      style: AgroText.h2.copyWith(color: Colors.white),
                    ),
                    for (final line in lines)
                      Text(
                        line,
                        style: AgroText.detail.copyWith(
                          color: AgroColors.onInkMuted,
                        ),
                      ),
                  ],
                ),
                FilledButton.icon(
                  key: const Key('union-send'),
                  onPressed: busy ? null : onSend,
                  style: FilledButton.styleFrom(
                    backgroundColor: AgroColors.lime,
                    foregroundColor: AgroColors.ink,
                    minimumSize: const Size(0, 52),
                  ),
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: const Text('Enviar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
