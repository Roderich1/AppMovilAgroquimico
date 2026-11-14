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
import 'joint_purchases_screen.dart' show refreshProblem;

/// «Sindicato»: la única pantalla principal de lo que se comparte con el
/// sindicato. Llegan aquí la pestaña y el acceso «Sindicato» de Inicio
/// (revisión del autor del 2026-11-12). Entrar no envía ni consulta nada.
///
/// Tres operaciones distintas, con su nombre real:
/// - «Enviar pendientes»: la acción expresa de siempre (C-02, `syncNow`):
///   verifica el acceso si hace falta, reanuda lo pausado por autorización
///   del titular y envía lo que espera (necesidad y consumo; en el mismo
///   ciclo, participaciones y solicitudes de identificación pendientes).
///   Sólo aparece si hay totales por enviar o que requieren atención.
/// - «Actualizar»: consulta las convocatorias del sindicato
///   (`refreshJointPurchases`, el mismo «Actualizar» de Convocatorias, que
///   también envía las participaciones pendientes). Siempre disponible: no
///   depende de que haya envíos pendientes.
/// - «Ver estado de los envíos»: la pantalla secundaria con cada envío, su
///   último intento y el detalle técnico.
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
  /// Aviso de la última consulta de convocatorias, o null.
  String? refreshNotice;
  bool refreshing = false;

  /// «Enviar pendientes»: misma acción expresa que en Estado de los envíos.
  Future<void> _send() async {
    final report = await ref.read(syncControllerProvider.notifier).syncNow();
    if (!mounted) return;
    ref.invalidate(syncSummaryProvider);
    final message = ref.read(syncControllerProvider).message;
    if (report != null && message == null) {
      showSuccess(
        context,
        report.sent == 0
            ? 'No había envíos pendientes.'
            : 'Aceptados: ${report.accepted}. Conflictos: ${report.conflicts}. '
                  'Rechazados: ${report.rejected}.',
      );
    }
  }

  /// «Actualizar»: consulta las convocatorias del sindicato.
  Future<void> _refresh() async {
    setState(() {
      refreshing = true;
      refreshNotice = null;
    });
    String? problem;
    try {
      final report = await ref
          .read(syncControllerProvider.notifier)
          .refreshJointPurchases();
      problem = refreshProblem(report);
    } on SyncAccessUnavailable catch (error) {
      problem = error.message;
    } on Object catch (error) {
      problem = friendlyError(error);
    }
    if (!mounted) return;
    ref.invalidate(syncSummaryProvider);
    setState(() {
      refreshing = false;
      refreshNotice = problem;
    });
    if (problem == null) showSuccess(context, 'Convocatorias consultadas.');
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
            sending: sync.busy,
            refreshing: refreshing,
            onSend: _send,
            onRefresh: _refresh,
            onStatus: () => context.push('/sincronizacion'),
          ),
          if (sync.message != null) ...[
            const SizedBox(height: 10),
            SyncNoticeCard(message: sync.message!),
          ],
          if (refreshNotice != null) ...[
            const SizedBox(height: 10),
            SyncNoticeCard(
              key: const Key('union-refresh-notice'),
              message: refreshNotice!,
            ),
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
                    const StatusBadge(label: 'Nueva', tone: BadgeTone.ok),
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

/// Tarjeta oscura: qué espera envío (necesidad declarada y consumo), la
/// última confirmación del sindicato y las tres operaciones. «Enviar
/// pendientes» sólo aparece si hay algo que enviar o que atender;
/// «Actualizar» y «Ver estado de los envíos», siempre.
class _SendCard extends StatelessWidget {
  const _SendCard({
    required this.summary,
    required this.sending,
    required this.refreshing,
    required this.onSend,
    required this.onRefresh,
    required this.onStatus,
  });

  final SyncQueueSummary? summary;
  final bool sending;
  final bool refreshing;
  final VoidCallback onSend;
  final VoidCallback onRefresh;
  final VoidCallback onStatus;

  String get _headline {
    final waiting = summary?.waiting ?? 0;
    if (summary == null) return 'Envíos al sindicato';
    if (waiting == 0) return 'Nada por enviar';
    return waiting == 1 ? '1 envío pendiente' : '$waiting envíos pendientes';
  }

  @override
  Widget build(BuildContext context) {
    final current = summary;
    final attention = current?.needsAttention ?? 0;
    final canSend = (current?.waiting ?? 0) > 0 || attention > 0;
    final lines = <String>[
      if (current != null) 'Necesidad declarada y consumo',
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
    final busy = sending || refreshing;
    Widget spinner() => const SizedBox.square(
      dimension: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
    final limeStyle = FilledButton.styleFrom(
      backgroundColor: AgroColors.lime,
      foregroundColor: AgroColors.ink,
      minimumSize: const Size(0, 52),
    );
    final refreshIcon = refreshing ? spinner() : const Icon(Icons.refresh);
    return Semantics(
      container: true,
      child: Material(
        key: const Key('union-sync'),
        color: AgroColors.ink,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_headline, style: AgroText.h2.copyWith(color: Colors.white)),
              for (final line in lines)
                Text(
                  line,
                  style: AgroText.detail.copyWith(color: AgroColors.onInkMuted),
                ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (canSend) ...[
                    FilledButton.icon(
                      key: const Key('union-send'),
                      onPressed: busy ? null : onSend,
                      style: limeStyle,
                      icon: sending ? spinner() : const Icon(Icons.upload),
                      label: const Text('Enviar pendientes'),
                    ),
                    OutlinedButton.icon(
                      key: const Key('union-refresh'),
                      onPressed: busy ? null : onRefresh,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: AgroColors.onInkMuted),
                        minimumSize: const Size(0, 52),
                      ),
                      icon: refreshIcon,
                      label: const Text('Actualizar'),
                    ),
                  ] else
                    FilledButton.icon(
                      key: const Key('union-refresh'),
                      onPressed: busy ? null : onRefresh,
                      style: limeStyle,
                      icon: refreshIcon,
                      label: const Text('Actualizar'),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              TextButton.icon(
                key: const Key('union-status'),
                onPressed: onStatus,
                style: TextButton.styleFrom(
                  foregroundColor: AgroColors.onInk,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 48),
                ),
                icon: const Icon(Icons.chevron_right),
                label: const Text('Ver estado de los envíos'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
