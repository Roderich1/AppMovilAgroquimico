import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../widgets/common.dart';

typedef _DashboardData = ({
  DashboardSummary summary,
  List<Map<String, Object?>> inventory,
  List<Map<String, Object?>> applications,
  List<Map<String, Object?>> debts,
  List<Map<String, Object?>> campaigns,
});

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  late Future<_DashboardData> future;
  String inventoryQuery = '';

  @override
  void initState() {
    super.initState();
    future = _load();
  }

  Future<_DashboardData> _load() async {
    final repo = ref.read(repositoryProvider);
    return (
      summary: await repo.dashboard(),
      inventory: await repo.inventorySummary(limit: 5),
      applications: await repo.applications(limit: 5),
      debts: await repo.topSettlements(limit: 5),
      campaigns: await repo.campaigns(),
    );
  }

  void _refresh() {
    final next = _load();
    setState(() {
      future = next;
    });
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Inicio',
    subtitle: 'Almacén y cuentas de un vistazo.',
    action: IconButton.filledTonal(
      onPressed: _refresh,
      icon: const Icon(Icons.refresh),
    ),
    child: FutureBuilder<_DashboardData>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return EmptyState(
            icon: Icons.error_outline,
            message: friendlyError(snapshot.error!),
          );
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final data = snapshot.data!;
        final visibleInventory = data.inventory.where((row) {
          return inventoryQuery.isEmpty ||
              (row['product_name']! as String).toLowerCase().contains(
                inventoryQuery,
              );
        }).toList();
        final activeCampaign = data.campaigns
            .where((campaign) => campaign['status'] == 'ACTIVE')
            .firstOrNull;
        final cards = [
          (
            'Compras',
            formatBob(data.summary.purchasesBobMinor),
            Icons.shopping_bag_outlined,
          ),
          (
            'Pagado proveedores',
            formatBob(data.summary.providerPaidMinor),
            Icons.storefront_outlined,
          ),
          (
            'Familias por cobrar',
            formatBob(data.summary.familyReceivableMinor),
            Icons.family_restroom_outlined,
          ),
          (
            'Terceros por cobrar',
            formatBob(data.summary.thirdPartyReceivableMinor),
            Icons.person_outline,
          ),
          (
            'Pagos recibidos',
            formatBob(data.summary.receivedMinor),
            Icons.payments_outlined,
          ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month_outlined),
                  const SizedBox(width: 8),
                  Text(
                    'Campaña activa: ${activeCampaign?['name'] ?? 'Sin campaña activa'}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth > 1000
                    ? 5
                    : constraints.maxWidth > 600
                    ? 3
                    : 2;
                final width =
                    (constraints.maxWidth - (columns - 1) * 8) / columns;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final card in cards)
                      SizedBox(
                        width: width,
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Icon(
                                  card.$3,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(card.$1),
                                      const SizedBox(height: 3),
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          card.$2,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: _title(context, 'Inventario proyectado')),
                TextButton(
                  onPressed: () => context.go('/inventario'),
                  child: const Text('Ver todos'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              onChanged: (value) => setState(() {
                inventoryQuery = value.trim().toLowerCase();
              }),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Buscar producto',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: visibleInventory.isEmpty
                  ? const EmptyState(
                      icon: Icons.inventory_2_outlined,
                      message: 'Aún no hay inventario.',
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowHeight: 40,
                        dataRowMinHeight: 40,
                        dataRowMaxHeight: 48,
                        columns: const [
                          DataColumn(label: Text('Producto')),
                          DataColumn(label: Text('Unidad')),
                          DataColumn(label: Text('Físico'), numeric: true),
                          DataColumn(
                            label: Text('Comprometido'),
                            numeric: true,
                          ),
                          DataColumn(label: Text('Proyección'), numeric: true),
                          DataColumn(label: Text('Valor'), numeric: true),
                        ],
                        rows: [
                          for (final row in visibleInventory)
                            DataRow(
                              onSelectChanged: (_) => context.go(
                                '/inventario/${row['product_id']}',
                              ),
                              cells: [
                                DataCell(Text(row['product_name']! as String)),
                                DataCell(Text(row['unit']! as String)),
                                DataCell(
                                  Text(
                                    formatQuantity(
                                      row['available_base']! as int,
                                      row['unit']! as String,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    formatQuantity(
                                      row['committed_base']! as int,
                                      row['unit']! as String,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    formatQuantity(
                                      row['projected_base']! as int,
                                      row['unit']! as String,
                                    ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    formatBob(
                                      row['available_value_bob_minor']! as int,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: _title(context, 'Aplicaciones recientes')),
                TextButton(
                  onPressed: () => context.go('/aplicaciones'),
                  child: const Text('Ver todas'),
                ),
              ],
            ),
            Card(
              child: Column(
                children: [
                  for (final row in data.applications.take(5))
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.agriculture_outlined),
                      title: Text(
                        '${row['person_name']} · ${row['farm_name']}',
                      ),
                      subtitle: Text(row['campaign_name'] as String),
                      trailing: Text(
                        formatBob(row['total_cost_bob_minor']! as int),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: _title(context, 'Principales saldos')),
                TextButton(
                  onPressed: () => context.go('/liquidacion'),
                  child: const Text('Ver todos'),
                ),
              ],
            ),
            Card(
              child: Column(
                children: [
                  for (final row
                      in (data.debts.toList()..sort(
                            (a, b) => (b['balance']! as int).compareTo(
                              a['balance']! as int,
                            ),
                          ))
                          .take(5))
                    ListTile(
                      dense: true,
                      title: Text(row['name']! as String),
                      subtitle: Text(
                        row['role'] == 'FAMILY' ? 'Familiar' : 'Tercero',
                      ),
                      trailing: Text(
                        formatBob(row['balance']! as int),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _title(BuildContext context, String text) => Text(
    text,
    style: Theme.of(context).textTheme.titleLarge
        ?.copyWith(fontWeight: FontWeight.w700),
  );
}
