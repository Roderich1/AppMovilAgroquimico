import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../domain/money.dart';
import '../theme/agro_theme.dart';
import '../widgets/agro_ui.dart';
import '../widgets/common.dart';
import '../widgets/owner_reversal_flow.dart';
import '../widgets/rdm_b_purchase_actions.dart';
import '../widgets/rdm_b_ui.dart';
import 'purchase_detail_screen.dart' show showInvoiceImage;

/// Lista de compras (se abre desde Actividad › Compras › «Lista de compras»
/// y desde Inicio › «compras con saldo por pagar»). Conserva el filtro por
/// campaña, la búsqueda por proveedor o factura y, por compra, «Ver
/// factura», «Registrar pago» al proveedor y «Revertir compra». Tocar la
/// compra abre su detalle (A2), también la revertida.
class PurchasesScreen extends ConsumerStatefulWidget {
  const PurchasesScreen({super.key});
  @override
  ConsumerState<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends ConsumerState<PurchasesScreen> {
  late Future<List<Map<String, Object?>>> data;
  String query = '';
  int? campaignFilter;
  @override
  void initState() {
    super.initState();
    data = ref.read(repositoryProvider).purchases();
  }

  void _refresh() {
    final next = ref.read(repositoryProvider).purchases();
    setState(() {
      data = next;
    });
  }

  Future<void> _newPurchase() async {
    final created = await context.push<bool>('/compras/nueva');
    if (!mounted) return;
    if (created == true) {
      _refresh();
      showSuccess(
        context,
        'Compra multiproducto confirmada; lotes e inventario creados.',
      );
    }
  }

  Future<void> _pay(Map<String, Object?> purchase) async {
    if (await payPurchaseProvider(
          context,
          ref,
          purchaseTargetFromRow(purchase),
        ) &&
        mounted) {
      _refresh();
    }
  }

  Future<void> _reverse(Map<String, Object?> purchase) async {
    if (await reversePurchaseWithApproval(
          context,
          ref,
          purchaseTargetFromRow(purchase),
        ) &&
        mounted) {
      _refresh();
    }
  }

  Future<void> _openDetail(int id) async {
    await context.push('/compras/detalle/$id');
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) => RdmScrollPage(
    children: [
      ScreenTitleBar(
        title: 'Compras',
        leading: const RdmBackButton(),
        actions: [
          FilledButton.icon(
            onPressed: _newPurchase,
            style: FilledButton.styleFrom(
              backgroundColor: AgroColors.lime,
              foregroundColor: AgroColors.ink,
              minimumSize: const Size(0, 44),
              shape: const StadiumBorder(),
            ),
            icon: const Icon(Icons.add),
            label: const Text(
              'Nueva compra',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      FutureBuilder<List<Map<String, Object?>>>(
        future: data,
        builder: (context, snapshot) {
          // El error se comprueba ANTES que los datos: al revés, `hasData` es
          // falso durante un fallo y esta rama nunca se alcanzaba.
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
              icon: Icons.shopping_bag_outlined,
              message: 'No hay compras confirmadas.',
            );
          }
          final rows = snapshot.data!.where((row) {
            if (campaignFilter != null &&
                row['campaign_id'] != campaignFilter) {
              return false;
            }
            if (query.isEmpty) return true;
            return '${row['supplier_name']} ${row['invoice_number'] ?? ''}'
                .toLowerCase()
                .contains(query);
          }).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<int?>(
                initialValue: campaignFilter,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Campaña',
                  prefixIcon: Icon(Icons.calendar_month_outlined),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todas')),
                  for (final row in {
                    for (final row in snapshot.data!)
                      row['campaign_id'] as int: row,
                  }.values)
                    DropdownMenuItem(
                      value: row['campaign_id'] as int,
                      child: Text(row['campaign_name'] as String),
                    ),
                ],
                onChanged: (value) => setState(() => campaignFilter = value),
              ),
              const SizedBox(height: 8),
              TextField(
                onChanged: (value) => setState(() {
                  query = value.trim().toLowerCase();
                }),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Buscar proveedor o factura',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              if (rows.isEmpty)
                const EmptyState(
                  icon: Icons.search_off_outlined,
                  message: 'Ninguna compra coincide con el filtro.',
                )
              else
                AgroGroup(
                  children: [
                    for (final row in rows)
                      _PurchaseRow(
                        row: row,
                        onOpen: () => _openDetail(row['id']! as int),
                        onPay: () => _pay(row),
                        onReverse: () => _reverse(row),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    ],
  );
}

/// Una compra: proveedor y factura, fecha, campaña y productos, total y
/// estado del pago al proveedor (con texto, no sólo color), y su menú.
class _PurchaseRow extends StatelessWidget {
  const _PurchaseRow({
    required this.row,
    required this.onOpen,
    required this.onPay,
    required this.onReverse,
  });

  final Map<String, Object?> row;
  final VoidCallback onOpen;
  final VoidCallback onPay;
  final VoidCallback onReverse;

  @override
  Widget build(BuildContext context) {
    final reversed = row['status'] == 'REVERSED';
    final total = row['total_bob_minor']! as int;
    final paid = row['paid_bob_minor']! as int;
    final items = row['item_count'] as int? ?? 0;
    final badge = reversed
        ? const StatusBadge(label: 'Revertida', tone: BadgeTone.neutral)
        : paid <= 0
        ? const StatusBadge(label: 'Sin pagar', tone: BadgeTone.review)
        : paid < total
        ? StatusBadge(
            label:
                'Pagó ${splitBob(paid).number} · falta '
                '${splitBob(total - paid).number}',
            tone: BadgeTone.review,
          )
        : const StatusBadge(label: 'Pagada', tone: BadgeTone.ok);
    return InkWell(
      // A2: toda la fila abre el detalle de sólo lectura, también de una
      // compra revertida. El menú conserva las acciones.
      key: Key('purchase-card-${row['id']}'),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconCircle(
              icon: reversed ? Icons.undo : Icons.shopping_bag_outlined,
              background: reversed ? AgroColors.chip : AgroColors.lime,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${row['supplier_name']} · '
                    '${row['invoice_number'] ?? 'Sin factura'}',
                    style: const TextStyle(
                      fontSize: 16,
                      height: 21 / 16,
                      fontWeight: FontWeight.w700,
                      color: AgroColors.ink,
                    ),
                  ),
                  Text(
                    '${formatDate(row['purchase_date'])} · '
                    '${row['campaign_name']} · '
                    '$items producto${items == 1 ? '' : 's'}',
                    style: AgroText.detail,
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        formatBob(total),
                        style: AgroText.amount.copyWith(
                          decoration: reversed
                              ? TextDecoration.lineThrough
                              : null,
                          color: reversed ? AgroColors.muted : null,
                        ),
                      ),
                      badge,
                    ],
                  ),
                  if (reversed)
                    ReversalActorText(
                      operationType: 'PURCHASE',
                      operationId: row['id']! as int,
                    ),
                ],
              ),
            ),
            if (!reversed)
              PopupMenuButton<String>(
                tooltip: 'Acciones de la compra',
                onSelected: (value) {
                  if (value == 'pay') {
                    onPay();
                  } else if (value == 'invoice') {
                    showInvoiceImage(
                      context,
                      row['invoice_image_path']! as String,
                    );
                  } else {
                    onReverse();
                  }
                },
                itemBuilder: (_) => [
                  if (row['invoice_image_path'] != null)
                    const PopupMenuItem(
                      value: 'invoice',
                      child: ListTile(
                        leading: Icon(Icons.image_outlined),
                        title: Text('Ver factura'),
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'pay',
                    child: ListTile(
                      leading: Icon(Icons.payments_outlined),
                      title: Text('Registrar pago'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'reverse',
                    child: ListTile(
                      leading: Icon(Icons.undo),
                      title: Text('Revertir compra'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
