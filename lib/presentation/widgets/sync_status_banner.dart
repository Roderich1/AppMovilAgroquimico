import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/sync/sync_outbox_store.dart';
import '../../domain/sync/sync_types.dart';
import '../../services/sync/sync_providers.dart';

/// Resumen de la outbox para el indicador. Nunca falla: sin base legible
/// devuelve null y el indicador no se muestra (Riverpod reintentaría un
/// error con temporizadores).
final syncSummaryProvider = FutureProvider.autoDispose<SyncQueueSummary?>((
  ref,
) async {
  ref.watch(syncControllerProvider.select((state) => state.summary));
  try {
    return await ref.read(syncOutboxStoreProvider).summary();
  } on Object {
    return null;
  }
});

/// Nombre visible de cada estado local (RF-18).
String outboxStatusLabel(OutboxStatus status) => switch (status) {
  OutboxStatus.pending => 'Pendiente',
  OutboxStatus.sending => 'Enviando',
  OutboxStatus.outcomeUnknown => 'Pendiente (sin confirmar)',
  OutboxStatus.acked => 'Sincronizado',
  OutboxStatus.conflict => 'Conflicto',
  OutboxStatus.rejected => 'Rechazado',
  OutboxStatus.failed => 'Rechazado (no admitido)',
  OutboxStatus.authPaused => 'Pausado: autorización',
  OutboxStatus.ownerPaused => 'Pausado: otro titular',
  OutboxStatus.restorePaused => 'Pausado: restauración',
  OutboxStatus.versionMismatch => 'Pausado: versión',
  OutboxStatus.discarded => 'Descartado (no enviado)',
};

/// El estado de **un** envío en palabras del agricultor, para la fila (los
/// chips y el indicador siguen con [outboxStatusLabel]). [attempts] separa
/// «guardado, todavía no salió» de «salió y no hay confirmación»; con
/// [feminine] habla de «la necesidad» en vez de «el envío». Un conflicto ya
/// decidido ([conflictResolved]) no vuelve a pedir decisión.
String outboxStatusPhrase(
  OutboxStatus status, {
  required int attempts,
  bool feminine = false,
  bool conflictResolved = false,
}) {
  final a = feminine ? 'a' : 'o';
  return switch (status) {
    OutboxStatus.pending =>
      attempts == 0
          ? 'Guardad$a, pendiente de envío'
          : 'Enviad$a, sin confirmación',
    OutboxStatus.sending => 'Enviando al sindicato',
    OutboxStatus.outcomeUnknown => 'Enviad$a, sin confirmación',
    OutboxStatus.acked => 'Aceptad$a por el sindicato',
    OutboxStatus.conflict =>
      conflictResolved
          ? 'Conflicto resuelto por usted; se enviará su decisión'
          : 'En conflicto: decida usted',
    OutboxStatus.rejected => 'Rechazad$a por el sindicato',
    OutboxStatus.failed => 'No admitid$a por el sindicato',
    OutboxStatus.authPaused => 'Pausad$a: falta verificar el acceso',
    OutboxStatus.ownerPaused => 'Pausad$a: otro titular en sesión',
    OutboxStatus.restorePaused => 'Pausad$a: llegó con un respaldo restaurado',
    OutboxStatus.versionMismatch => 'Pausad$a: actualice la aplicación',
    OutboxStatus.discarded => 'Descartad$a (no enviad$a)',
  };
}

/// Aviso del worker (`SyncState.message`): por qué no pudo enviar y, si se
/// le pasa [onSyncNow], la acción pertinente («Sincronizar ahora», que
/// verifica el acceso de forma explícita). La misma tarjeta en
/// Sincronización, Necesidad declarada y Consumo.
class SyncNoticeCard extends StatelessWidget {
  const SyncNoticeCard({
    super.key,
    required this.message,
    this.onSyncNow,
    this.busy = false,
  });

  final String message;
  final VoidCallback? onSyncNow;
  final bool busy;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(leading: const Icon(Icons.info_outline), title: Text(message)),
        if (onSyncNow != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const Key('sync-now-notice'),
                onPressed: busy ? null : onSyncNow,
                icon: const Icon(Icons.sync),
                label: const Text('Sincronizar ahora'),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Texto corto para el indicador; null si no hay nada que mostrar.
String? syncHeadline(SyncQueueSummary summary) {
  final conflicts = summary.count(OutboxStatus.conflict);
  final rejected =
      summary.count(OutboxStatus.rejected) + summary.count(OutboxStatus.failed);
  final paused =
      summary.count(OutboxStatus.authPaused) +
      summary.count(OutboxStatus.ownerPaused) +
      summary.count(OutboxStatus.restorePaused) +
      summary.count(OutboxStatus.versionMismatch);
  final parts = <String>[
    if (summary.waiting > 0) 'Pendiente: ${summary.waiting}',
    if (conflicts > 0) 'Conflicto: $conflicts',
    if (rejected > 0) 'Rechazado: $rejected',
    if (paused > 0) 'Pausado: $paused',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Indicador del shell: aparece sólo si hay algo pendiente o que atender, y
/// lleva a la pantalla de sincronización. Sin nada que mostrar devuelve el
/// contenido tal cual.
class SyncAwareBody extends ConsumerWidget {
  const SyncAwareBody({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(syncSummaryProvider).value;
    final headline = summary == null ? null : syncHeadline(summary);
    if (headline == null) return child;
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: InkWell(
            onTap: () => context.push('/sincronizacion'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.sync, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Sindicato · $headline')),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
