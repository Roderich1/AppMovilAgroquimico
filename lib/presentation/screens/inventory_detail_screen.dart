import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../domain/money.dart';
import '../widgets/common.dart';

typedef _InventoryDetail = ({
  Map<String, Object?> header,
  List<Map<String, Object?>> distribution,
  List<Map<String, Object?>> lots,
});

class InventoryDetailScreen extends ConsumerWidget {
  const InventoryDetailScreen({super.key, required this.productId});
  final int productId;

  Future<_InventoryDetail> _load(WidgetRef ref) async {
    final repo = ref.read(repositoryProvider);
    return (
      header: await repo.inventoryProductHeader(productId),
      distribution: await repo.inventoryProductDistribution(productId),
      lots: await repo.inventoryProductLots(productId),
    );
  }

  @override
  Widget build(
    BuildContext context,
    WidgetRef ref,
  ) => FutureBuilder<_InventoryDetail>(
    future: _load(ref),
    builder: (context, snapshot) {
      if (snapshot.hasError)
        return PageFrame(
          title: 'Inventario',
          child: EmptyState(
            icon: Icons.error_outline,
            message: friendlyError(snapshot.error!),
          ),
        );
      if (!snapshot.hasData)
        return const Center(child: CircularProgressIndicator());
      final data = snapshot.data!;
      final h = data.header;
      final unit = h['unit'] as String;
      final physical = h['physical_base'] as int;
      final committed = h['committed_base'] as int;
      return PageFrame(
        title: h['product_name'] as String,
        subtitle: 'Detalle físico y trazabilidad FIFO. El inventario continúa entre campañas.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Metric(
                    width: constraints.maxWidth >= 700
                        ? (constraints.maxWidth - 16) / 3
                        : (constraints.maxWidth - 8) / 2,
                    label: 'Comprado',
                    value: formatQuantity(h['purchased_base'] as int, unit),
                  ),
                  _Metric(
                    width: constraints.maxWidth >= 700
                        ? (constraints.maxWidth - 16) / 3
                        : (constraints.maxWidth - 8) / 2,
                    label: 'Consumido',
                    value: formatQuantity(h['consumed_base'] as int, unit),
                  ),
                  _Metric(
                    width: constraints.maxWidth >= 700
                        ? (constraints.maxWidth - 16) / 3
                        : (constraints.maxWidth - 8) / 2,
                    label: 'Físico',
                    value: formatQuantity(physical, unit),
                  ),
                  _Metric(
                    width: constraints.maxWidth >= 700
                        ? (constraints.maxWidth - 16) / 3
                        : (constraints.maxWidth - 8) / 2,
                    label: 'Comprometido',
                    value: formatQuantity(committed, unit),
                  ),
                  _Metric(
                    width: constraints.maxWidth >= 700
                        ? (constraints.maxWidth - 16) / 3
                        : (constraints.maxWidth - 8) / 2,
                    label: 'Libre proyectado',
                    value: formatQuantity(physical - committed, unit),
                  ),
                  _Metric(
                    width: constraints.maxWidth >= 700
                        ? (constraints.maxWidth - 16) / 3
                        : (constraints.maxWidth - 8) / 2,
                    label: 'Valor físico',
                    value: formatBob(h['value_bob_minor'] as int),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Distribución por persona',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  for (final row in data.distribution)
                    ListTile(
                      title: Text(row['person_name'] as String),
                      subtitle: Text(
                        'Asignado ${formatQuantity(row['assigned_base'] as int, unit)} · consumido ${formatQuantity(row['consumed_base'] as int, unit)}',
                      ),
                      trailing: Text(
                        formatQuantity(row['available_base'] as int, unit),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Lotes disponibles',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  for (final lot in data.lots)
                    ExpansionTile(
                      title: Text(
                        '${lot['owner_name']} · ${formatQuantity(lot['available_base'] as int, unit)}',
                      ),
                      subtitle: Text(
                        '${lot['supplier_name']} · ${lot['campaign_name']}',
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Lote #${lot['lot_id']} · costo ${formatBob(lot['unit_cost'] as int)}/$unit · origen ${lot['parent_lot_id'] == null ? 'compra' : 'transferencia del lote #${lot['parent_lot_id']}'}',
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.width,
    required this.label,
    required this.value,
  });
  final double width;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    ),
  );
}
