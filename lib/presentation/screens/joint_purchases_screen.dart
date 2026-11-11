import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/sync/joint_purchase_store.dart';
import '../../services/sync/joint_purchase_sender.dart';
import '../../services/sync/sync_providers.dart';
import '../widgets/common.dart';
import '../widgets/joint_purchase_texts.dart';

/// «Compras conjuntas» (contrato E2 §5): las convocatorias que el sindicato
/// sirvió a este titular, guardadas en el teléfono. Se descubren al pulsar
/// «Actualizar» o tras un ciclo de sincronización (sin notificaciones push).
class JointPurchasesScreen extends ConsumerStatefulWidget {
  const JointPurchasesScreen({super.key});

  @override
  ConsumerState<JointPurchasesScreen> createState() =>
      _JointPurchasesScreenState();
}

class _JointPurchasesScreenState extends ConsumerState<JointPurchasesScreen> {
  late Future<List<JointPurchaseCall>> calls;
  bool loading = false;
  String? problem;

  @override
  void initState() {
    super.initState();
    calls = _read();
  }

  Future<List<JointPurchaseCall>> _read() =>
      ref.read(jointPurchaseStoreProvider).callsForActiveOwner();

  void _reload() {
    final next = _read();
    setState(() {
      calls = next;
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
      child: FutureBuilder<List<JointPurchaseCall>>(
        future: calls,
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
          final items = snapshot.data!;
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
              if (items.isEmpty)
                const EmptyState(
                  icon: Icons.groups_outlined,
                  message:
                      'No hay convocatorias en este teléfono. Pulse '
                      '«Actualizar» para consultar al sindicato.',
                )
              else
                for (final call in items)
                  Card(
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
                          if (call.campaignName != null)
                            Text('Campaña: ${call.campaignName}'),
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
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
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
                  ),
            ],
          );
        },
      ),
    );
  }
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
    return 'No se pudo leer la lista del sindicato. Lo guardado en el '
        'teléfono se conserva; inténtelo más tarde.';
  }
  if (report.retried > 0) {
    return 'No se pudo confirmar un envío. Se reintentará con el mismo '
        'contenido.';
  }
  return null;
}
