import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/sync/consumption_publisher.dart';
import '../../domain/money.dart';
import '../../domain/sync/consumption_projection.dart';
import '../../domain/sync/sync_types.dart'
    show
        OutboxStatus,
        SyncAction,
        SyncCodeFamily,
        syncCodeExplanation,
        syncCodeFamily;
import '../../services/sync/sync_providers.dart';
import '../theme/agro_theme.dart';
import '../widgets/agro_ui.dart';
import '../widgets/common.dart';
import '../widgets/rdm_c_page.dart';
import '../widgets/sync_status_banner.dart';

/// Publicación explícita del consumo al sindicato (MOB #33): la vista previa
/// no escribe nada; sólo «Publicar» encola, y sólo los totales que cambiaron.
///
/// Cada fila dice su estado en tres palabras («Pendiente», «Enviado»,
/// «Requiere atención»), derivado de la outbox. No hay envío automático: la
/// publicación sigue siendo una acción expresa del agricultor (F04 §2.4; la
/// propuesta de envío automático está en `docs/adr/F06-ADR-006-*`, Proposed).
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
    return RdmCPage(
      title: 'Consumo para el sindicato',
      subtitle:
          'Totales de sus aplicaciones confirmadas y no revertidas, por campaña '
          'y producto vinculados. Sólo se envía si usted lo confirma.',
      child: FutureBuilder<ConsumptionPreview>(
        future: preview,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return NoticeBox(
              tone: NoticeTone.warning,
              text: snapshot.error is ConsumptionPublishException
                  ? (snapshot.error! as ConsumptionPublishException).message
                  : 'No se pudo preparar la vista previa.',
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // C-02: por qué el worker no envía, con la acción pertinente.
              if (sync.message != null) ...[
                SyncNoticeCard(
                  message: sync.message!,
                  busy: sync.busy,
                  onSyncNow: _syncNow,
                ),
                const SizedBox(height: 12),
              ],
              if (data.rows.isEmpty)
                const RdmCEmpty(
                  icon: Icons.water_drop_outlined,
                  message:
                      'No hay consumo propio en campañas y productos '
                      'vinculados.',
                ),
              for (final row in data.rows) ...[
                _ConsumptionCard(
                  key: Key(
                    'consumption-${row.target.campaignRef}-${row.target.productRef}',
                  ),
                  title: row.productName,
                  campaign: row.campaignName,
                  amount: _total(row),
                  state: _stateWord(row.sendState),
                  tone: _stateTone(row.sendState),
                  detail:
                      '${_changeLabel(row)}'
                      '${row.blockedDetail == null ? '' : '\n${row.blockedDetail}'}',
                  action: row.change == ConsumptionChange.conflict
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
                const SizedBox(height: 10),
              ],
              ..._exclusions(data),
              const SizedBox(height: 12),
              // Publicar es siempre una acción expresa (F04 §2.4); sólo se
              // habilita si algún total cambió.
              PrimaryActionButton(
                key: const Key('publish-consumption'),
                label: 'Publicar consumo al sindicato',
                icon: Icons.arrow_upward,
                iconFirst: true,
                onPressed: data.hasChanges ? () => _publish(data) : null,
              ),
              const SizedBox(height: 12),
              RdmCLinkRow(
                text: 'Vincular con el sindicato',
                semanticsHint: 'Abre Productos y campañas',
                onTap: () => context.push('/sindicato/vinculos'),
              ),
            ],
          );
        },
      ),
    );
  }

  static BadgeTone _stateTone(ConsumptionSendState state) => switch (state) {
    ConsumptionSendState.pending => BadgeTone.review,
    ConsumptionSendState.sent => BadgeTone.voice,
    ConsumptionSendState.attention => BadgeTone.missing,
  };

  /// Las tres palabras de estado (pedido del autor del 2026-11-05). La
  /// publicación sigue siendo expresa: «Pendiente» incluye lo que espera a
  /// que usted pulse «Publicar».
  static String _stateWord(ConsumptionSendState state) => switch (state) {
    ConsumptionSendState.pending => 'Pendiente',
    ConsumptionSendState.sent => 'Enviado',
    ConsumptionSendState.attention => 'Requiere atención',
  };

  /// Frase con punto final (las explicaciones por familia no lo llevan).
  static String _sentence(String text) => text.endsWith('.') ? text : '$text.';

  String _changeLabel(ConsumptionPreviewRow row) {
    final prior = row.prior;
    final before = prior?.quantityBase;
    final previous = before == null
        ? ''
        : ' (antes ${formatQuantity(int.parse(before), row.baseUnit.majorUnit)})';
    // Estado de la última intención vigente, si dice algo más que «aceptado»
    // (pausas, acceso sin verificar, en camino).
    final priorPhrase = prior == null || prior.action == SyncAction.cancel
        ? null
        : outboxStatusPhrase(
            prior.status,
            attempts: prior.attempts,
            conflictResolved: prior.resolvedAt != null,
          );
    final access =
        prior != null &&
            prior.status.isSendable &&
            syncCodeFamily(prior.lastCode) == SyncCodeFamily.authorization
        ? ' ${_sentence(syncCodeExplanation(prior.lastCode)!)}'
        : '';
    final rejection = row.lastRejection;
    final rejected = rejection == null
        ? ''
        : ' El sindicato rechazó el último envío: '
              '${_sentence(rejection.interventionMessage ?? syncCodeExplanation(rejection.lastCode) ?? 'sin motivo informado')}';
    final label = switch (row.change) {
      ConsumptionChange.publish =>
        prior != null && prior.action == SyncAction.cancel
            ? 'Retirado del sindicato: se publicará otra vez si pulsa '
                  '«Publicar».'
            : 'Nuevo: se publicará si pulsa «Publicar».',
      ConsumptionChange.supersede =>
        'Cambió$previous: sustituirá al anterior si pulsa «Publicar».'
            '${priorPhrase == null || prior!.status == OutboxStatus.acked ? '' : ' Último envío: ${_sentence(priorPhrase)}'}',
      // C-12: el estado en palabras, sin dos puntos dobles.
      ConsumptionChange.unchanged => 'Sin cambios · ${priorPhrase!}.',
      ConsumptionChange.conflict =>
        'En conflicto con el sindicato: decida usted.',
      ConsumptionChange.blocked =>
        prior != null && prior.status == OutboxStatus.acked
            ? 'Vínculo no vigente: el total aceptado requiere revisión; no se '
                  'publica otro.'
            : 'Vínculo no vigente: no se publica.',
      // F04 §2.4: terminal; el mensaje vigente, sin reintento ni otra campaña.
      ConsumptionChange.rejected => _sentence(
        rejection?.interventionMessage ??
            syncCodeExplanation(rejection?.lastCode) ??
            'El sindicato rechazó el último envío.',
      ),
    };
    return row.change == ConsumptionChange.rejected
        ? label
        : '$label$rejected$access';
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
      Container(
        key: const Key('consumption-exclusions'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: AgroColors.track,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: const Text('No se publica', style: AgroText.question),
            ),
            for (final note in notes)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '• $note',
                  style: AgroText.detail.copyWith(color: AgroColors.ink),
                ),
              ),
          ],
        ),
      ),
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

/// Un total por campaña y producto: nombre, campaña, cantidad grande, la
/// palabra del estado y, debajo, qué pasaría al publicar.
class _ConsumptionCard extends StatelessWidget {
  const _ConsumptionCard({
    super.key,
    required this.title,
    required this.campaign,
    required this.amount,
    required this.state,
    required this.tone,
    required this.detail,
    required this.action,
  });

  final String title;
  final String campaign;
  final String amount;
  final String state;
  final BadgeTone tone;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Material(
    color: AgroColors.surface,
    borderRadius: BorderRadius.circular(20),
    child: Padding(
      padding: EdgeInsets.fromLTRB(16, 14, 16, action == null ? 14 : 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AmountAside(
            amount: amount,
            amountStyle: AgroText.total,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AgroText.value),
                Text(campaign, style: AgroText.detail),
                const SizedBox(height: 8),
                StatusBadge(label: state, tone: tone),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(detail, style: AgroText.detail.copyWith(color: AgroColors.ink)),
          if (action != null)
            Align(alignment: Alignment.centerLeft, child: action),
        ],
      ),
    ),
  );
}
