import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/auth/local_owner_credential.dart'
    show AuthorizationPurpose;
import '../widgets/owner_reversal_flow.dart';

import '../../app.dart';
import '../../domain/money.dart';
import '../../domain/operation_mode.dart';
import '../../operation_mode_controller.dart';
import '../widgets/common.dart';
import '../widgets/mode_notice.dart';

class TransfersScreen extends ConsumerStatefulWidget {
  const TransfersScreen({super.key});
  @override
  ConsumerState<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends ConsumerState<TransfersScreen> {
  late Future<List<Map<String, Object?>>> future;
  @override
  void initState() {
    super.initState();
    future = ref.read(repositoryProvider).transfers();
  }

  void refresh() {
    final next = ref.read(repositoryProvider).transfers();
    setState(() {
      future = next;
    });
  }

  Future<void> reverse(Map<String, Object?> row) async {
    final id = row['id']! as int;
    // RF-13: motivo y PIN del titular; el actor sale de la autorización.
    final approval = await requestOwnerApproval(
      context,
      ref,
      purpose: AuthorizationPurpose.reverseTransfer,
      subjectRef: 'transfer:$id',
      title: '¿Revertir esta transferencia?',
      confirmLabel: 'Revertir transferencia',
      effects:
          '${row['from_person_name']} → ${row['to_person_name']}\n'
          '${formatItemsSummary(row['products_summary'])}\n'
          'Costo ${formatBob(row['total_cost_bob_minor']! as int)}, sólo de '
          'referencia: la transferencia no generó deuda.\n\n'
          'El stock volverá a la persona de origen y ninguna cuenta cambia. '
          'Esta acción no se puede deshacer.',
    );
    if (approval == null || !mounted) return;
    try {
      await ref
          .read(repositoryProvider)
          .reverseTransfer(
            id,
            reason: approval.reason,
            authorization: approval.authorization,
          );
      if (mounted) refresh();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) =>
      // La ruta ya no se abre en inventario propio; si la pantalla quedó
      // abierta debajo de otra al cambiar de modalidad, deja de ofrecer
      // acciones (#26).
      ref.watch(operationModeProvider) == OperationMode.personal
      ? SharedOnlyNotice(onBack: () => context.go('/operaciones'))
      : _list(context);

  Widget _list(BuildContext context) => PageFrame(
    title: 'Transferencias',
    // D-07 (RN-35): una transferencia es una entrega de producto, no una
    // venta ni un cargo; el costo que se muestra es sólo de referencia.
    subtitle:
        'Entregas de producto de una persona a otra. No generan deuda; el '
        'costo es sólo de referencia.',
    action: FilledButton.icon(
      onPressed: () async {
        final saved = await context.push<bool>('/transferencias/nueva');
        if (saved == true && mounted) refresh();
      },
      icon: const Icon(Icons.add),
      label: const Text('Nueva'),
    ),
    child: FutureBuilder<List<Map<String, Object?>>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return EmptyState(
            icon: Icons.error_outline,
            message: friendlyError(snapshot.error!),
          );
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.data!.isEmpty)
          return const EmptyState(
            icon: Icons.swap_horiz,
            message: 'No hay transferencias.',
          );
        return Card(
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: snapshot.data!.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final row = snapshot.data![index];
              return ExpansionTile(
                leading: const Icon(Icons.swap_horiz),
                title: Text(
                  '${row['from_person_name']} → ${row['to_person_name']}',
                ),
                subtitle: Text(
                  '${formatDate(row['transfer_date'])} · '
                  '${formatItemsSummary(row['products_summary'])}\n'
                  '$transferNoDebtLabel',
                ),
                trailing: row['status'] == 'CONFIRMED'
                    ? IconButton(
                        tooltip: 'Revertir',
                        onPressed: () => reverse(row),
                        icon: const Icon(Icons.undo),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('Revertida'),
                          ReversalActorText(
                            operationType: 'TRANSFER',
                            operationId: row['id']! as int,
                          ),
                        ],
                      ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${row['item_count']} producto(s) · ${row['lot_count']} lote(s) · costo de referencia ${formatBob(row['total_cost_bob_minor'] as int)}\n'
                        'Es el costo de compra del producto entregado, no un '
                        'precio de venta. La entrega no genera deuda.',
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    ),
  );
}
