// Hoja «Envíos al sindicato» del modo individual (lámina I-53, 2026-11-13).
//
// Sólo presentación de la cola de envíos que ya existe: lee el resumen y las
// entradas de la outbox y ofrece «Enviar ahora», la misma acción que
// «Enviar pendientes» de Sincronización (que verifica el acceso de forma
// explícita). Abrir la hoja no envía nada. Las decisiones (conflictos,
// rechazos, pausas por versión o por restauración) siguen en
// `/sincronizacion`, que conserva sus guardas.
//
// Respecto de la lámina: la app no sondea la red, así que no afirma «Sin
// conexión» por su cuenta; muestra el último aviso del envío (que sí dice si
// no hubo conexión) y deja «Enviar ahora» disponible para intentarlo.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/sync/sync_types.dart';
import '../../services/sync/sync_providers.dart';
import '../screens/sync_status_screen.dart'
    show decisionRoute, needsDecision, projectionLabel;
import '../theme/agro_theme.dart';
import 'agro_ui.dart';
import 'sync_status_banner.dart';

Future<void> showIndConnectionSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _IndConnectionSheet(),
    );

bool _waiting(OutboxStatus status) =>
    status == OutboxStatus.pending ||
    status == OutboxStatus.sending ||
    status == OutboxStatus.outcomeUnknown;

bool _shown(OutboxStatus status) =>
    status != OutboxStatus.acked && status != OutboxStatus.discarded;

class _IndConnectionSheet extends ConsumerStatefulWidget {
  const _IndConnectionSheet();

  @override
  ConsumerState<_IndConnectionSheet> createState() =>
      _IndConnectionSheetState();
}

class _IndConnectionSheetState extends ConsumerState<_IndConnectionSheet> {
  late Future<List<OutboxEntry>> _entries = _load();

  Future<List<OutboxEntry>> _load() async => [
    for (final entry in await ref.read(syncOutboxStoreProvider).entries())
      if (_shown(entry.status)) entry,
  ];

  Future<void> _sendNow() async {
    await ref.read(syncControllerProvider.notifier).syncNow();
    if (mounted) {
      setState(() {
        _entries = _load();
      });
    }
  }

  void _open(String route) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push(route);
  }

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(syncControllerProvider);
    final message = sync.message;
    return SafeArea(
      child: SingleChildScrollView(
        key: const Key('ind-connection-sheet'),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: FutureBuilder<List<OutboxEntry>>(
          future: _entries,
          builder: (context, snapshot) {
            final entries = snapshot.data ?? const <OutboxEntry>[];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: StatusBadge(
                    label: entries.isEmpty
                        ? 'Sin pendientes'
                        : entries.any((e) => !_waiting(e.status))
                        ? 'Envíos por revisar'
                        : 'Pendientes de envío',
                    tone: entries.isEmpty ? BadgeTone.ok : BadgeTone.review,
                  ),
                ),
                const SizedBox(height: 12),
                Semantics(
                  header: true,
                  child: const Text(
                    'Sus registros están guardados en este teléfono',
                    style: AgroText.sheetTitle,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Compras, aplicaciones y planes funcionan sin conexión. Lo '
                  'del sindicato se envía cuando usted lo indique y haya '
                  'señal.',
                  style: AgroText.detail,
                ),
                if (message != null) ...[
                  const SizedBox(height: 12),
                  NoticeBox(
                    key: const Key('ind-connection-message'),
                    tone: NoticeTone.warning,
                    text: message,
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  'PENDIENTES DE ENVÍO · ${entries.length}',
                  style: const TextStyle(
                    fontSize: 13,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w700,
                    color: AgroColors.muted,
                  ),
                ),
                const SizedBox(height: 8),
                if (!snapshot.hasData)
                  const Center(child: CircularProgressIndicator())
                else if (entries.isEmpty)
                  const Text(
                    'No hay nada pendiente de envío.',
                    key: Key('ind-connection-empty'),
                    style: AgroText.detail,
                  )
                else
                  AgroGroup(
                    children: [
                      for (final entry in entries)
                        _EntryRow(
                          entry: entry,
                          onReview: needsDecision(entry)
                              ? () => _open(decisionRoute(entry))
                              : !_waiting(entry.status)
                              ? () => _open('/sincronizacion')
                              : null,
                        ),
                    ],
                  ),
                const SizedBox(height: 10),
                const Text(
                  'Nada se envía por abrir una pantalla. Un envío pendiente no '
                  'cambia su almacén ni sus saldos.',
                  style: AgroText.detail,
                ),
                const SizedBox(height: 14),
                FilledButton(
                  key: const Key('ind-connection-send'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                  onPressed: sync.busy || entries.isEmpty ? null : _sendNow,
                  child: Text(sync.busy ? 'Enviando…' : 'Enviar ahora'),
                ),
                TextButton(
                  key: const Key('ind-connection-all'),
                  onPressed: () => _open('/sincronizacion'),
                  child: const Text('Ver todos los envíos'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, required this.onReview});

  final OutboxEntry entry;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final waiting = _waiting(entry.status);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    projectionLabel(entry.projectionType),
                    ?entry.productName,
                  ].join(' · '),
                  style: const TextStyle(
                    fontSize: 16,
                    height: 21 / 16,
                    fontWeight: FontWeight.w700,
                    color: AgroColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                StatusBadge(
                  label: outboxStatusPhrase(
                    entry.status,
                    attempts: entry.attempts,
                    conflictResolved: entry.resolvedAt != null,
                  ),
                  tone: waiting ? BadgeTone.review : BadgeTone.missing,
                ),
              ],
            ),
          ),
          if (onReview != null) ...[
            const SizedBox(width: 8),
            OutlinedButton(onPressed: onReview, child: const Text('Revisar')),
          ],
        ],
      ),
    );
  }
}
