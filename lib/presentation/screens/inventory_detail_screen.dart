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

/// Cuántos movimientos se muestran de entrada y cuántos más por «Ver más».
const _movementsPage = 20;

/// Detalle de un producto: cuánto hay, para quién, y los movimientos que lo
/// explican (compras, aplicaciones, pases y reversiones con su fecha), que es
/// lo que la tarea T3 del piloto pide leer (E-10). Lotes y valor físico quedan
/// plegados debajo. Las lecturas se hacen una vez al abrir (B-15).
class InventoryDetailScreen extends ConsumerStatefulWidget {
  const InventoryDetailScreen({super.key, required this.productId});
  final int productId;

  @override
  ConsumerState<InventoryDetailScreen> createState() =>
      _InventoryDetailScreenState();
}

class _InventoryDetailScreenState extends ConsumerState<InventoryDetailScreen> {
  late Future<_InventoryDetail> detail;
  late Future<List<Map<String, Object?>>> movements;
  int movementsLimit = _movementsPage;

  @override
  void initState() {
    super.initState();
    detail = _load();
    movements = _loadMovements();
  }

  Future<_InventoryDetail> _load() async {
    final repo = ref.read(repositoryProvider);
    return (
      header: await repo.inventoryProductHeader(widget.productId),
      distribution: await repo.inventoryProductDistribution(widget.productId),
      lots: await repo.inventoryProductLots(widget.productId),
    );
  }

  /// Se pide una fila más que el límite para saber si queda algo por ver.
  Future<List<Map<String, Object?>>> _loadMovements() => ref
      .read(repositoryProvider)
      .productMovements(widget.productId, limit: movementsLimit + 1);

  void _showMore() => setState(() {
    movementsLimit += _movementsPage;
    movements = _loadMovements();
  });

  @override
  Widget build(BuildContext context) => FutureBuilder<_InventoryDetail>(
    future: detail,
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
      final theme = Theme.of(context);
      return PageFrame(
        title: h['product_name'] as String,
        subtitle: 'Cuánto hay, de qué compras viene y en qué se usó. El inventario continúa entre campañas.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth >= 700
                    ? (constraints.maxWidth - 16) / 3
                    : (constraints.maxWidth - 8) / 2;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Metric(
                      width: width,
                      label: 'Comprado neto',
                      value: formatQuantity(h['purchased_base'] as int, unit),
                    ),
                    _Metric(
                      width: width,
                      label: 'Consumido neto',
                      value: formatQuantity(h['consumed_base'] as int, unit),
                    ),
                    _Metric(
                      width: width,
                      label: 'Físico',
                      value: formatQuantity(physical, unit),
                    ),
                    _Metric(
                      width: width,
                      label: 'Reservado por planes',
                      value: formatQuantity(committed, unit),
                    ),
                    _Metric(
                      width: width,
                      label: 'Quedará libre',
                      value: formatQuantity(physical - committed, unit),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            Text(
              'Neto: no cuenta lo revertido. Comprado neto menos consumido '
              'neto es el físico.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            Text(
              'Distribución por persona',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Asignación neta: lo comprado para esta persona, más lo que '
              'recibió y menos lo que entregó por transferencias. No cuenta lo '
              'revertido. Restando lo consumido queda su físico.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  for (final row in data.distribution)
                    ListTile(
                      title: Text(row['person_name'] as String),
                      subtitle: Text(
                        'Asignación neta ${formatQuantity(row['assigned_base'] as int, unit)} · consumido neto ${formatQuantity(row['consumed_base'] as int, unit)}',
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
              'Movimientos',
              key: const Key('inventory-movements-title'),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Lo que explica el saldo: compras, aplicaciones, pases y '
              'reversiones, del más reciente al más antiguo.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<Map<String, Object?>>>(
              future: movements,
              builder: (context, snapshot) {
                if (snapshot.hasError)
                  return EmptyState(
                    icon: Icons.error_outline,
                    message: friendlyError(snapshot.error!),
                  );
                if (!snapshot.hasData)
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    ),
                  );
                final rows = snapshot.data!;
                if (rows.isEmpty)
                  return const EmptyState(
                    icon: Icons.history_outlined,
                    message: 'Todavía no hay movimientos de este producto.',
                  );
                final hasMore = rows.length > movementsLimit;
                return Card(
                  key: const Key('inventory-movements'),
                  child: Column(
                    children: [
                      for (final row in rows.take(movementsLimit))
                        _MovementTile(row: row, unit: unit),
                      if (hasMore)
                        TextButton.icon(
                          key: const Key('inventory-movements-more'),
                          onPressed: _showMore,
                          icon: const Icon(Icons.expand_more),
                          label: const Text('Ver más'),
                        ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            // Detalle técnico, plegado: lotes vigentes y valor físico.
            Card(
              child: ExpansionTile(
                key: const Key('inventory-lots'),
                title: const Text('Lotes disponibles y valor físico'),
                subtitle: Text(
                  'Valor físico: ${formatBob(h['value_bob_minor'] as int)}',
                ),
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

/// Una fila de `inventory_movements` en palabras: tipo con su contraparte,
/// fecha local, persona y cantidad con signo en la unidad mayor.
class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.row, required this.unit});
  final Map<String, Object?> row;
  final String unit;

  String get _label {
    final farm = row['farm_name'] ?? 'chaco';
    final other = row['counterpart_name'] ?? 'otra persona';
    return switch (row['type']) {
      'PURCHASE_IN' => 'Compra',
      'PURCHASE_REVERSAL' => 'Compra revertida',
      'APPLICATION_OUT' => 'Aplicación en $farm',
      'APPLICATION_REVERSAL' => 'Aplicación revertida en $farm',
      'TRANSFER_OUT' => 'Pase a $other',
      'TRANSFER_IN' => 'Recibido de $other',
      'TRANSFER_REVERSAL_IN' => 'Pase revertido: vuelve de $other',
      'TRANSFER_REVERSAL_OUT' => 'Pase revertido: devuelto a $other',
      _ => '${row['type']}',
    };
  }

  IconData get _icon => switch (row['type']) {
    'PURCHASE_IN' || 'PURCHASE_REVERSAL' => Icons.shopping_cart_outlined,
    'APPLICATION_OUT' || 'APPLICATION_REVERSAL' => Icons.agriculture_outlined,
    _ => Icons.swap_horiz,
  };

  @override
  Widget build(BuildContext context) {
    final quantity = row['quantity_signed'] as int;
    final supplier = row['supplier_name'];
    return ListTile(
      leading: Icon(_icon),
      title: Text(_label),
      subtitle: Text(
        '${formatDate(row['movement_date'])} · ${row['owner_name']}'
        '${supplier == null ? '' : ' · $supplier'}',
      ),
      trailing: Text(
        '${quantity < 0 ? '-' : '+'}${formatQuantity(quantity.abs(), unit)}',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: quantity < 0 ? Theme.of(context).colorScheme.error : null,
        ),
      ),
    );
  }
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
