import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/sync/joint_purchase_store.dart';
import '../../services/sync/joint_purchase_sender.dart';
import '../../services/sync/sync_providers.dart';
import '../widgets/common.dart';
import '../widgets/joint_purchase_texts.dart';

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
    return PageFrame(
      title: 'Compras conjuntas',
      subtitle: 'Convocatorias del sindicato y su participación.',
      action: FilledButton.tonalIcon(
        onPressed: loading ? null : _refresh,
        icon: const Icon(Icons.cloud_download_outlined),
        label: const Text('Actualizar'),
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
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (loading) const LinearProgressIndicator(),
              if (problem != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    problem!,
                    key: const Key('joint-purchases-problem'),
                  ),
                ),
              if (data.isEmpty)
                const EmptyState(
                  icon: Icons.groups_outlined,
                  message:
                      'No hay convocatorias en este teléfono. Pulse '
                      '«Actualizar» para consultar al sindicato.',
                )
              else if (data.recent.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(jointPurchaseRecentEmpty),
                )
              else
                for (final call in data.recent) _callCard(call),
              const SizedBox(height: 16),
              _history(context, data),
            ],
          );
        },
      ),
    );
  }

  Widget _history(BuildContext context, JointPurchaseOverview data) => Column(
    key: const Key('joint-history-section'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        jointPurchaseHistoryTitle,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 4),
      const Text(jointPurchaseHistoryIntro),
      const SizedBox(height: 8),
      if (data.older.isEmpty)
        const Text(jointPurchaseHistoryEmpty, key: Key('joint-history-empty'))
      else
        for (final call in data.older) _callCard(call),
      if (data.missingOlder > 0)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            jointPurchaseMissingOlderText(data.missingOlder),
            key: const Key('joint-history-missing'),
          ),
        ),
      if (historyLoading)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: LinearProgressIndicator(),
        ),
      if (historyProblem != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(historyProblem!, key: const Key('joint-history-problem')),
        ),
      if (historyQueried && historyCursor == null && historyProblem == null)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(jointPurchaseHistoryEnd, key: Key('joint-history-end')),
        ),
      const SizedBox(height: 8),
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

  Widget _callCard(JointPurchaseCall call) => Card(
    child: ListTile(
      key: Key('joint-call-${call.callId}'),
      contentPadding: const EdgeInsets.all(12),
      title: Text(
        call.name,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (call.campaignName != null) Text('Campaña: ${call.campaignName}'),
          Text(callDeadlineText(call)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final text in jointPurchaseChips(call))
                Chip(
                  label: Text(text),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ],
          ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        await context.push('/compras-conjuntas/${call.callId}');
        if (mounted) _reload();
      },
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
