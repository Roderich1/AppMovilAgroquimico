import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../data/typed_reads.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../../domain/read_models.dart';
import '../widgets/common.dart';

typedef _DashboardData = ({
  DashboardSummary summary,
  List<InventoryLineRead> inventory,
  // `applications` no es fuente de ningun reporte de EVOLUTION-2: sigue en el
  // camino legacy, como el resto de consumidores no migrados.
  List<Map<String, Object?>> applications,
  List<TopSettlementRead> debts,
  List<CampaignRead> campaigns,
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
      // Sin `limit`: el buscador filtra en cliente y con solo 5 filas
      // precargadas afirmaba que no habia inventario aunque el producto
      // existiera (UIBUG-007). La tabla sigue mostrando 5 cuando no se busca.
      inventory: await repo.inventorySummaryTyped(),
      applications: await repo.applications(limit: 5),
      debts: await repo.topSettlementsTyped(limit: 5),
      campaigns: await repo.campaignsTyped(),
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
        final searching = inventoryQuery.isNotEmpty;
        final matchingInventory = data.inventory
            .where(
              (row) =>
                  !searching || matchesSearch(row.productName, inventoryQuery),
            )
            .toList();
        // Sin busqueda se mantiene el resumen corto de siempre; al buscar se
        // recorre todo el inventario.
        final visibleInventory = searching
            ? matchingInventory
            : matchingInventory.take(5).toList();
        final activeCampaign = data.campaigns
            .where((campaign) => campaign.isActive)
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
                  // Sin `Expanded` el texto reclamaba su ancho natural y la
                  // fila desbordaba con un nombre de campaña largo o con la
                  // fuente ampliada: `RenderFlex overflowed` y la cinta
                  // recortada en la primera pantalla de la aplicación
                  // (UIBUG-067). Ahora se reparte en varias líneas.
                  Expanded(
                    child: Text(
                      'Campaña activa: ${activeCampaign?.name ?? 'Sin campaña activa'}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
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
                inventoryQuery = value.trim();
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
                  // No es lo mismo no tener inventario que no encontrar nada:
                  // el mensaje unico hacia creer que el almacen estaba vacio
                  // (UIBUG-007).
                  ? EmptyState(
                      icon: searching
                          ? Icons.search_off_outlined
                          : Icons.inventory_2_outlined,
                      message: searching
                          ? 'Ningún producto coincide con "$inventoryQuery".'
                          : 'Aún no hay inventario.',
                    )
                  // En ancho de móvil la tabla no cabía y había que
                  // desplazarla en horizontal: al hacerlo la columna
                  // "Producto" salía de la pantalla y quedaban cifras sin
                  // dueño visible (UIBUG-023). En vez de fijar la primera
                  // columna, el ancho estrecho usa una lista donde el nombre
                  // encabeza cada fila y las cifras van etiquetadas: no hay
                  // desplazamiento horizontal que perder.
                  : LayoutBuilder(
                      builder: (context, constraints) =>
                          constraints.maxWidth < _tableMinWidth
                          ? _InventoryCards(rows: visibleInventory)
                          : SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: _inventoryTable(context, visibleInventory),
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
                      subtitle: Text(
                        '${row['campaign_name']}'
                        '${row['status'] == 'REVERSED' ? ' · ${operationStatusLabel(row['status'])}' : ''}',
                      ),
                      // El inicio mostraba el importe de una aplicación anulada
                      // como si siguiera vigente, mientras el reporte de costos
                      // sí la excluía: dos cifras para el mismo hecho
                      // (UIBUG-010).
                      trailing: Text(
                        formatBob(row['total_cost_bob_minor']! as int),
                        style: TextStyle(
                          decoration: row['status'] == 'REVERSED'
                              ? TextDecoration.lineThrough
                              : null,
                          color: row['status'] == 'REVERSED'
                              ? Theme.of(context).colorScheme.outline
                              : null,
                        ),
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
                            (a, b) => b.balanceMinor.compareTo(a.balanceMinor),
                          ))
                          .take(5))
                    ListTile(
                      dense: true,
                      title: Text(row.name),
                      subtitle: Text(
                        row.role == 'FAMILY' ? 'Familiar' : 'Tercero',
                      ),
                      trailing: Text(
                        formatBob(row.balanceMinor),
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

  /// Ancho por debajo del cual la tabla de inventario obligaría a desplazarse
  /// en horizontal. Las seis columnas no caben en el ancho útil de un móvil
  /// (UIBUG-023).
  static const double _tableMinWidth = 560;

  Widget _inventoryTable(BuildContext context, List<InventoryLineRead> rows) =>
      DataTable(
        headingRowHeight: 40,
        dataRowMinHeight: 40,
        dataRowMaxHeight: 48,
        columns: const [
          DataColumn(label: Text('Producto')),
          DataColumn(label: Text('Unidad')),
          DataColumn(label: Text('Físico'), numeric: true),
          DataColumn(label: Text('Comprometido'), numeric: true),
          DataColumn(label: Text('Proyección'), numeric: true),
          DataColumn(label: Text('Valor'), numeric: true),
        ],
        // Sin `onSelectChanged` no aparece la columna de
        // casillas, que no tenia ninguna accion masiva detras y
        // robaba ancho a una tabla que ya no cabia (UIBUG-022).
        showCheckboxColumn: false,
        rows: [
          for (final row in rows)
            DataRow(
              onSelectChanged: (_) =>
                  context.push('/inventario/${row.productId}'),
              cells: [
                DataCell(Text(row.productName)),
                DataCell(Text(row.unit)),
                DataCell(Text(formatQuantity(row.availableBase, row.unit))),
                DataCell(Text(formatQuantity(row.committedBase, row.unit))),
                DataCell(
                  Text(
                    formatQuantity(row.projectedBase, row.unit),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                DataCell(Text(formatBob(row.availableValueBobMinor))),
              ],
            ),
        ],
      );

  Widget _title(BuildContext context, String text) => Text(
    text,
    style: Theme.of(context).textTheme.titleLarge
        ?.copyWith(fontWeight: FontWeight.w700),
  );
}

/// Inventario en ancho de móvil: una fila por producto, con el **nombre como
/// encabezado** y cada cifra junto a su etiqueta (UIBUG-023).
///
/// Sustituye a la tabla desplazable en horizontal, donde al arrastrar hacia la
/// derecha el nombre del producto salía de la pantalla y las cantidades
/// quedaban sin dueño visible. Aquí no hay desplazamiento horizontal que
/// perder: cada fila se lee entera.
class _InventoryCards extends StatelessWidget {
  const _InventoryCards({required this.rows});

  final List<InventoryLineRead> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        for (final (index, row) in rows.indexed) ...[
          if (index > 0) const Divider(height: 1),
          InkWell(
            onTap: () => context.push('/inventario/${row.productId}'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.productName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      _figure(
                        theme,
                        'Físico',
                        formatQuantity(row.availableBase, row.unit),
                      ),
                      _figure(
                        theme,
                        'Comprometido',
                        formatQuantity(row.committedBase, row.unit),
                      ),
                      _figure(
                        theme,
                        'Proyección',
                        formatQuantity(row.projectedBase, row.unit),
                        strong: true,
                      ),
                      _figure(
                        theme,
                        'Valor',
                        formatBob(row.availableValueBobMinor),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _figure(
    ThemeData theme,
    String label,
    String value, {
    bool strong = false,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      ),
      Text(
        value,
        style: TextStyle(
          fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
    ],
  );
}
