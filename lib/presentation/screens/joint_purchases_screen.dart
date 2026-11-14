import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/sync/joint_purchase_store.dart';
import '../../domain/sync/joint_purchase_call_view.dart'
    show jointPurchaseRecentFinishedDays;
import '../../services/sync/joint_purchase_sender.dart';
import '../../services/sync/sync_providers.dart';
import '../theme/agro_theme.dart';
import '../widgets/agro_ui.dart';
import '../widgets/common.dart';
import '../widgets/joint_purchase_texts.dart';
import '../widgets/rdm_c_joint.dart';
import '../widgets/rdm_c_page.dart';

/// «Compras conjuntas» (contrato E2 §5 y §10.1): las convocatorias que el
/// sindicato sirvió a este titular, guardadas en el teléfono. Se descubren
/// al pulsar «Actualizar» o tras un ciclo de sincronización (sin
/// notificaciones push).
///
/// La lista principal muestra las abiertas y las terminadas recientes; las
/// terminadas antes van en «Historial», en esta misma pantalla. «Consultar
/// historial» trae del sindicato, con conexión, las anteriores que no están
/// en el teléfono. Las operaciones propias (pendientes, rechazadas, fuera de
/// plazo) se ven siempre con su convocatoria, en una sección o en la otra.
class JointPurchasesScreen extends ConsumerStatefulWidget {
  const JointPurchasesScreen({super.key});

  @override
  ConsumerState<JointPurchasesScreen> createState() =>
      _JointPurchasesScreenState();
}

class _JointPurchasesScreenState extends ConsumerState<JointPurchasesScreen> {
  late Future<JointPurchaseOverview> overview;
  bool loading = false;
  String? problem;

  /// «Historial» del sindicato en esta visita: si ya se consultó, el cursor
  /// para «Ver más» y el último aviso.
  bool historyQueried = false;
  bool historyLoading = false;
  String? historyCursor;
  String? historyProblem;

  @override
  void initState() {
    super.initState();
    overview = _read();
  }

  Future<JointPurchaseOverview> _read() =>
      ref.read(jointPurchaseStoreProvider).overviewForActiveOwner();

  void _reload() {
    final next = _read();
    setState(() {
      overview = next;
    });
  }

  Future<void> _refresh() async {
    setState(() {
      loading = true;
      problem = null;
    });
    try {
      final report = await ref
          .read(syncControllerProvider.notifier)
          .refreshJointPurchases();
      if (mounted) setState(() => problem = refreshProblem(report));
    } on SyncAccessUnavailable catch (error) {
      if (mounted) setState(() => problem = error.message);
    } on Object catch (error) {
      if (mounted) setState(() => problem = friendlyError(error));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  /// «Consultar historial» (sin [more]) o «Ver más».
  Future<void> _queryHistory({bool more = false}) async {
    setState(() {
      historyLoading = true;
      historyProblem = null;
    });
    try {
      final result = await ref
          .read(syncControllerProvider.notifier)
          .jointPurchaseHistory(before: more ? historyCursor : null);
      if (!mounted) return;
      setState(() {
        historyProblem = historyProblemText(result);
        if (result.outcome == JointPurchaseHistoryOutcome.saved) {
          historyQueried = true;
          historyCursor = result.nextCursor;
        } else if (result.outcome ==
            JointPurchaseHistoryOutcome.invalidCursor) {
          historyQueried = false;
          historyCursor = null;
        }
      });
    } on SyncAccessUnavailable catch (error) {
      if (mounted) {
        setState(
          () => historyProblem =
              '$jointPurchaseHistoryOfflineText\n${error.message}',
        );
      }
    } on Object catch (error) {
      if (mounted) setState(() => historyProblem = friendlyError(error));
    } finally {
      if (mounted) setState(() => historyLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(jointPurchaseRevisionProvider, (_, _) => _reload());
    return RdmCPage(
      title: 'Compras conjuntas',
      subtitle: 'Convocatorias del sindicato y su participación.',
      action: RdmCHeaderAction(
        icon: Icons.sync,
        label: 'Actualizar',
        onPressed: loading ? null : _refresh,
      ),
      child: FutureBuilder<JointPurchaseOverview>(
        future: overview,
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
          final data = snapshot.data!;
          final open = [
            for (final call in data.recent)
              if (call.isOpen) call,
          ];
          final finished = [
            for (final call in data.recent)
              if (!call.isOpen) call,
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (loading) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
              ],
              if (problem != null) ...[
                _Problem(text: problem!, textKey: 'joint-purchases-problem'),
                const SizedBox(height: 12),
              ],
              if (data.isEmpty)
                const RdmCEmpty(
                  icon: Icons.groups_outlined,
                  message:
                      'No hay convocatorias en este teléfono. Pulse '
                      '«Actualizar» para consultar al sindicato.',
                )
              else if (data.recent.isEmpty)
                const RdmCEmpty(
                  icon: Icons.groups_outlined,
                  message: jointPurchaseRecentEmpty,
                ),
              if (open.isNotEmpty) ...[
                const RdmCOverline('Abiertas'),
                for (final call in open) ...[
                  _OpenCallCard(call: call, onOpen: () => _open(call)),
                  const SizedBox(height: 10),
                ],
              ],
              if (finished.isNotEmpty) ...[
                // «Terminadas hace menos de 180 días»: el filtro de la vista,
                // no un borrado (E2 §10.1 a); las anteriores siguen abajo.
                RdmCOverline(
                  'Terminadas hace menos de $jointPurchaseRecentFinishedDays '
                  'días',
                ),
                AgroGroup(
                  children: [
                    for (final call in finished)
                      _callRow(call, onOpen: () => _open(call)),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              _history(context, data),
            ],
          );
        },
      ),
    );
  }

  Future<void> _open(JointPurchaseCall call) async {
    await context.push('/compras-conjuntas/${call.callId}');
    if (mounted) _reload();
  }

  Widget _history(BuildContext context, JointPurchaseOverview data) => Column(
    key: const Key('joint-history-section'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SectionHeader(title: jointPurchaseHistoryTitle),
      const SizedBox(height: 4),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(jointPurchaseHistoryIntro, style: AgroText.detail),
      ),
      const SizedBox(height: 10),
      if (data.older.isEmpty)
        RdmCEmpty(
          key: const Key('joint-history-empty'),
          icon: Icons.history,
          message: jointPurchaseHistoryEmpty,
        )
      else
        AgroGroup(
          children: [
            for (final call in data.older)
              _callRow(call, onOpen: () => _open(call)),
          ],
        ),
      if (data.missingOlder > 0)
        _HistoryNote(
          text: jointPurchaseMissingOlderText(data.missingOlder),
          textKey: 'joint-history-missing',
        ),
      if (historyLoading)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: LinearProgressIndicator(),
        ),
      if (historyProblem != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _Problem(
            text: historyProblem!,
            textKey: 'joint-history-problem',
          ),
        ),
      if (historyQueried && historyCursor == null && historyProblem == null)
        const _HistoryNote(
          text: jointPurchaseHistoryEnd,
          textKey: 'joint-history-end',
        ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            key: const Key('joint-history-query'),
            onPressed: historyLoading ? null : () => _queryHistory(),
            icon: const Icon(Icons.history),
            label: const Text('Consultar historial'),
          ),
          if (historyCursor != null)
            OutlinedButton(
              key: const Key('joint-history-more'),
              onPressed: historyLoading
                  ? null
                  : () => _queryHistory(more: true),
              child: const Text('Ver más'),
            ),
        ],
      ),
    ],
  );

  /// Fila de una convocatoria terminada o anterior: nombre, campaña, fecha
  /// límite y las etiquetas de su estado y de la participación propia.
  Widget _callRow(JointPurchaseCall call, {required VoidCallback onOpen}) =>
      RdmCRow(
        key: Key('joint-call-${call.callId}'),
        title: call.name,
        detail: [
          if (call.campaignName != null) 'Campaña: ${call.campaignName}',
          callDeadlineText(call),
        ].join('\n'),
        badges: [JointBadges(jointPurchaseChips(call))],
        onTap: onOpen,
      );
}

/// Convocatoria abierta, destacada como en la lámina: etiquetas, nombre,
/// campaña, fecha límite según el sindicato y «Ver y participar».
class _OpenCallCard extends StatelessWidget {
  const _OpenCallCard({required this.call, required this.onOpen});
  final JointPurchaseCall call;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    child: Material(
      key: Key('joint-call-${call.callId}'),
      color: AgroColors.ink,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              JointBadges(jointPurchaseChips(call)),
              const SizedBox(height: 10),
              Text(
                call.name,
                style: AgroText.sheetTitle.copyWith(color: Colors.white),
              ),
              if (call.campaignName != null)
                Text(
                  'Campaña: ${call.campaignName}',
                  style: AgroText.detail.copyWith(color: AgroColors.onInk),
                ),
              const SizedBox(height: 6),
              Text(
                callDeadlineText(call),
                style: AgroText.detail.copyWith(color: AgroColors.onInkMuted),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: onOpen,
                style: FilledButton.styleFrom(
                  backgroundColor: AgroColors.lime,
                  foregroundColor: AgroColors.ink,
                  minimumSize: const Size(0, 48),
                ),
                child: Text(
                  call.acceptedActive != null || call.pendingOp != null
                      ? 'Ver su participación'
                      : 'Ver y participar',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Aviso de un problema al consultar, con su clave en el texto.
class _Problem extends StatelessWidget {
  const _Problem({required this.text, required this.textKey});
  final String text;
  final String textKey;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: AgroColors.warnBg,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.cloud_off_outlined, color: AgroColors.warnInk),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            key: Key(textKey),
            style: AgroText.detail.copyWith(color: AgroColors.warnInk),
          ),
        ),
      ],
    ),
  );
}

class _HistoryNote extends StatelessWidget {
  const _HistoryNote({required this.text, required this.textKey});
  final String text;
  final String textKey;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
    child: Text(
      text,
      key: Key(textKey),
      style: AgroText.detail.copyWith(color: AgroColors.ink),
    ),
  );
}

/// Aviso tras «Actualizar» o «Enviar ahora», o null si todo fue bien.
String? refreshProblem(JointPurchaseRunReport report) {
  if (report.ownerMismatch) {
    return 'La cuenta en sesión no es la del titular: no se envió ni se '
        'consultó nada.';
  }
  if (report.authFailed) {
    return 'El sindicato pidió verificar el acceso otra vez. Lo preparado '
        'sigue guardado en el teléfono.';
  }
  if (report.apiUnavailable) {
    return 'Este teléfono no tiene configurado el servidor del sindicato.';
  }
  if (report.listUnavailable) {
    // N7: incompatibilidad de versión, falta de conexión y fallo temporal
    // se dicen distinto.
    return switch (report.listProblem) {
      JointPurchaseListProblem.incompatibleVersion =>
        jointPurchaseIncompatibleText,
      JointPurchaseListProblem.offline => jointPurchaseListOfflineText,
      _ => jointPurchaseListTemporaryText,
    };
  }
  if (report.retried > 0) {
    return 'No se pudo confirmar un envío. Se reintentará con el mismo '
        'contenido.';
  }
  return null;
}
