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
import '../theme/agro_theme.dart';
import '../widgets/agro_ui.dart';
import '../widgets/common.dart';
import '../widgets/rdm_b_ui.dart';
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
      revalidate: reversalStillPending(ref, 'transfers', id),
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

  Future<void> _new() async {
    final saved = await context.push<bool>('/transferencias/nueva');
    if (saved == true && mounted) refresh();
  }

  Widget _list(BuildContext context) => RdmScrollPage(
    children: [
      ScreenTitleBar(
        title: 'Transferencias',
        leading: const RdmBackButton(),
        actions: [
          FilledButton.icon(
            onPressed: _new,
            style: FilledButton.styleFrom(
              backgroundColor: AgroColors.lime,
              foregroundColor: AgroColors.ink,
              minimumSize: const Size(0, 44),
              shape: const StadiumBorder(),
            ),
            icon: const Icon(Icons.add),
            label: const Text(
              'Nueva',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      // D-07: lo que es (y no es) una transferencia, con el texto vigente.
      const NoticeBox(
        icon: Icons.info_outline,
        text:
            'Entregas de producto de una persona a otra. No generan deuda; el '
            'costo es sólo de referencia.',
      ),
      const SizedBox(height: 12),
      FutureBuilder<List<Map<String, Object?>>>(
        future: future,
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
          if (snapshot.data!.isEmpty) {
            return const EmptyState(
              icon: Icons.swap_horiz,
              message: 'No hay transferencias.',
            );
          }
          return AgroGroup(
            key: const Key('transfers-group'),
            children: [
              for (final row in snapshot.data!)
                _TransferRow(row: row, onReverse: () => reverse(row)),
            ],
          );
        },
      ),
    ],
  );
}

/// Una transferencia: de quién a quién, fecha y productos, «Entrega sin
/// deuda»; al desplegar, productos, lotes y el costo de referencia. Las
/// revertidas dicen su estado con texto y su auditoría.
class _TransferRow extends StatelessWidget {
  const _TransferRow({required this.row, required this.onReverse});

  final Map<String, Object?> row;
  final VoidCallback onReverse;

  @override
  Widget build(BuildContext context) {
    final confirmed = row['status'] == 'CONFIRMED';
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: Key('transfer-row-${row['id']}'),
        tilePadding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
        childrenPadding: const EdgeInsets.fromLTRB(68, 0, 16, 12),
        leading: const IconCircle(icon: Icons.swap_horiz),
        title: Text(
          '${row['from_person_name']} → ${row['to_person_name']}',
          style: const TextStyle(
            fontSize: 16,
            height: 21 / 16,
            fontWeight: FontWeight.w700,
            color: AgroColors.ink,
          ),
        ),
        subtitle: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!confirmed) ...[
              const SizedBox(height: 4),
              StatusBadge(
                label: operationStatusLabel(row['status']),
                tone: BadgeTone.neutral,
              ),
              const SizedBox(height: 4),
            ],
            Text(
              '${formatDate(row['transfer_date'])} · '
              '${formatItemsSummary(row['products_summary'])}\n'
              '$transferNoDebtLabel',
              style: AgroText.detail,
            ),
            if (!confirmed)
              ReversalActorText(
                operationType: 'TRANSFER',
                operationId: row['id']! as int,
              ),
          ],
        ),
        trailing: confirmed
            ? IconButton(
                tooltip: 'Revertir',
                onPressed: onReverse,
                icon: const Icon(Icons.undo),
              )
            : null,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${row['item_count']} producto(s) · ${row['lot_count']} lote(s) · costo de referencia ${formatBob(row['total_cost_bob_minor'] as int)}\n'
              'Es el costo de compra del producto entregado, no un '
              'precio de venta. La entrega no genera deuda.',
              style: AgroText.detail,
            ),
          ),
        ],
      ),
    );
  }
}
