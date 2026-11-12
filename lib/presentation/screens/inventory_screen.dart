import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../data/typed_reads.dart';
import '../../domain/inventory_alerts.dart';
import '../../domain/money.dart';
import '../../domain/read_models.dart';
import '../theme/agro_theme.dart';
import '../widgets/agro_ui.dart';
import '../widgets/common.dart';
import '../widgets/rdm_b_ui.dart';
import '../widgets/register_sheet.dart' show registerRevisionProvider;
import 'inventory_alerts_screen.dart';

/// Almacén (antes «Inventario», lámina 1.4).
///
/// Cifras, todas de `inventorySummaryTyped()` sin recalcular:
/// - **Existencia**: el stock físico (`availableBase`), lotes vencidos
///   incluidos; si hay vencidos se dice cuánto, para no confundir la
///   existencia total con la que se puede usar.
/// - **Previsto en planes**: `committedBase`, lo que piden los planes
///   pendientes de la campaña activa. No es una reserva: no aparta nada.
/// - **Quedarán**: `projectedBase` = existencia − previsto; si es negativo,
///   «faltarán».
/// Los avisos cuentan **lotes** (vencimientos) y **productos** (existencia
/// baja), como dice cada rótulo.
class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});
  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  late Future<List<InventoryLineRead>> future;

  /// Avisos de existencias y vencimiento (F04-AV): una consulta aparte, que
  /// puede fallar sin ocultar la lista.
  late Future<InventoryAlerts> alerts;
  String query = '';
  bool searching = false;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    future = ref.read(repositoryProvider).inventorySummaryTyped();
    alerts = ref.read(repositoryProvider).inventoryAlerts();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void refresh() {
    final next = ref.read(repositoryProvider).inventorySummaryTyped();
    final nextAlerts = ref.read(repositoryProvider).inventoryAlerts();
    setState(() {
      future = next;
      alerts = nextAlerts;
    });
  }

  Future<void> _openEstimation() async {
    await context.push('/inventario/estimacion');
    if (mounted) refresh();
  }

  Future<void> _openAlerts() async {
    await context.push('/inventario/avisos');
    if (mounted) refresh();
  }

  Future<void> _openProduct(int id) async {
    await context.push('/inventario/$id');
    if (mounted) refresh();
  }

  void _toggleSearch() {
    setState(() {
      if (searching) {
        searching = false;
        query = '';
        _search.clear();
      } else {
        searching = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Lo registrado desde la hoja «+ Registrar» del shell (una compra, una
    // transferencia o una aplicación cambian las existencias).
    ref.listen(registerRevisionProvider, (_, _) => refresh());
    return _page(context);
  }

  Widget _page(BuildContext context) => FutureBuilder<InventoryAlerts>(
    future: alerts,
    builder: (context, alertSnap) => RdmScrollPage(
      children: [
        ScreenTitleBar(
          title: 'Almacén',
          actions: [
            CircleIconButton(
              key: const Key('inventory-search-toggle'),
              icon: searching ? Icons.close : Icons.search,
              tooltip: searching ? 'Cerrar búsqueda' : 'Buscar producto',
              onPressed: _toggleSearch,
            ),
            CircleIconButton(
              icon: Icons.refresh,
              tooltip: 'Actualizar',
              onPressed: refresh,
            ),
          ],
        ),
        if (searching) ...[
          const SizedBox(height: 8),
          TextField(
            key: const Key('inventory-search'),
            controller: _search,
            autofocus: true,
            onChanged: (value) =>
                setState(() => query = value.trim().toLowerCase()),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Buscar producto',
            ),
          ),
        ],
        const SizedBox(height: 12),
        _AlertTiles(snapshot: alertSnap, onOpen: _openAlerts),
        const SizedBox(height: 10),
        AgroGroup(
          children: [
            LinkRow(
              key: const Key('inventory-alerts-entry'),
              icon: Icons.warning_amber_outlined,
              title: 'Todos los avisos',
              subtitle: alertSnap.hasError
                  ? 'No se pudieron calcular. Ábralos para ver el motivo.'
                  : alertSnap.hasData
                  ? inventoryAlertsSummary(alertSnap.data!)
                  : 'Calculando…',
              onTap: _openAlerts,
            ),
            LinkRow(
              key: const Key('inventory-estimation-entry'),
              icon: Icons.insights_outlined,
              title: 'Estimación del consumo',
              subtitle: 'Referencia; no cambia el inventario.',
              onTap: _openEstimation,
            ),
          ],
        ),
        FutureBuilder<List<InventoryLineRead>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.only(top: 16),
                child: EmptyState(
                  icon: Icons.error_outline,
                  message: friendlyError(snapshot.error!),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final all = snapshot.data!;
            final rows = all
                .where((r) => matchesSearch(r.productName, query))
                .toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                SectionHeader(
                  title: query.isEmpty
                      ? alertCount(all.length, 'producto', 'productos')
                      : alertCount(rows.length, 'resultado', 'resultados'),
                ),
                const SizedBox(height: 8),
                if (rows.isEmpty)
                  // No es lo mismo no tener productos que no encontrar el
                  // buscado (UIBUG-007).
                  EmptyState(
                    icon: query.isEmpty
                        ? Icons.inventory_2_outlined
                        : Icons.search_off_outlined,
                    message: query.isEmpty
                        ? 'No hay productos para mostrar.'
                        : 'Ningún producto coincide con "${_search.text.trim()}".',
                  )
                else
                  for (final row in rows) ...[
                    _ProductCard(
                      row: row,
                      alerts: alertSnap.data,
                      onTap: () => _openProduct(row.productId),
                    ),
                    const SizedBox(height: 10),
                  ],
              ],
            );
          },
        ),
      ],
    ),
  );
}

/// Tres cifras de avisos arriba del Almacén. Cada una dice qué cuenta.
class _AlertTiles extends StatelessWidget {
  const _AlertTiles({required this.snapshot, required this.onOpen});

  final AsyncSnapshot<InventoryAlerts> snapshot;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final alerts = snapshot.data;
    if (alerts == null) return const SizedBox.shrink();
    // Productos bajos en el total de la instalación; los de cada
    // responsable van en el resumen de «Todos los avisos».
    final lowProducts = alerts.lowStock.where((a) => a.line.isTotal).length;
    final tiles = [
      (
        key: 'inventory-tile-expired',
        count: alerts.expired.length,
        label: alerts.expired.length == 1 ? 'Lote vencido' : 'Lotes vencidos',
        bg: const Color(0xFFFFDAD6),
        fg: const Color(0xFF8C1D18),
      ),
      (
        key: 'inventory-tile-today',
        count: alerts.dueToday.length,
        label: alerts.dueToday.length == 1
            ? 'Lote vence hoy'
            : 'Lotes vencen hoy',
        bg: AgroColors.warnBg,
        fg: const Color(0xFF5A3A00),
      ),
      (
        key: 'inventory-tile-low',
        count: lowProducts,
        label: lowProducts == 1 ? 'Producto bajo' : 'Productos bajos',
        bg: AgroColors.surface,
        fg: AgroColors.ink,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final labelStyle = const TextStyle(
          fontFamily: AgroFonts.body,
          fontSize: 13,
          height: 18 / 13,
          fontWeight: FontWeight.w700,
        );
        final widest = tiles
            .expand((t) => t.label.split(' '))
            .map((w) => measureText(context, w, labelStyle))
            .fold(0.0, (a, b) => a > b ? a : b);
        var columns = 3;
        double widthFor(int n) => (constraints.maxWidth - (n - 1) * 8) / n;
        while (columns > 1 && widthFor(columns) < widest + 28 + 4) {
          columns--;
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tile in tiles)
              SizedBox(
                width: widthFor(columns),
                child: Material(
                  color: tile.bg,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    key: Key(tile.key),
                    borderRadius: BorderRadius.circular(20),
                    onTap: onOpen,
                    child: Semantics(
                      label: '${tile.count} ${tile.label.toLowerCase()}',
                      button: true,
                      excludeSemantics: true,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${tile.count}',
                              style: TextStyle(
                                fontFamily: AgroFonts.display,
                                fontSize: 30,
                                height: 34 / 30,
                                fontWeight: FontWeight.w800,
                                color: tile.fg,
                              ),
                            ),
                            Text(
                              tile.label,
                              style: labelStyle.copyWith(color: tile.fg),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Un producto del Almacén: nombre, existencia grande con su unidad, lo
/// previsto en planes y lo que quedará, el valor y los avisos del producto.
class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.row,
    required this.alerts,
    required this.onTap,
  });

  final InventoryLineRead row;
  final InventoryAlerts? alerts;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final id = row.productId;
    final alerts = this.alerts;
    final expired = alerts?.expired.where((a) => a.lot.productId == id) ?? [];
    final today = alerts?.dueToday.where((a) => a.lot.productId == id) ?? [];
    final near = alerts?.near.where((a) => a.lot.productId == id) ?? [];
    final low = alerts?.lowStock.where((a) => a.line.productId == id) ?? [];
    final expiredBase = expired.fold(0, (sum, a) => sum + a.lot.remainingBase);
    final nearestDays = near
        .map((a) => a.days)
        .whereType<int>()
        .fold<int?>(null, (m, d) => m == null || d < m ? d : m);
    final badges = <Widget>[
      if (expired.isNotEmpty)
        StatusBadge(
          label: expired.length == 1
              ? 'Lote vencido'
              : '${expired.length} lotes vencidos',
          tone: BadgeTone.missing,
        ),
      if (today.isNotEmpty)
        StatusBadge(
          label: today.length == 1
              ? 'Lote vence hoy'
              : '${today.length} lotes vencen hoy',
          tone: BadgeTone.review,
        ),
      if (near.isNotEmpty)
        StatusBadge(
          label: nearestDays == null
              ? 'Por vencer'
              : 'Vence en ${alertCount(nearestDays, 'día', 'días')}',
          tone: BadgeTone.review,
        ),
      if (low.any((a) => a.line.isTotal))
        const StatusBadge(label: 'Queda poco', tone: BadgeTone.neutral)
      else if (low.isNotEmpty)
        const StatusBadge(
          label: 'Poco por responsable',
          tone: BadgeTone.neutral,
        ),
    ];
    final stock = splitQuantity(row.availableBase, row.unit);
    final projected = row.projectedBase;
    final details = <String>[
      if (row.committedBase != 0)
        'Previsto en planes ${formatQuantity(row.committedBase, row.unit)} · '
            '${projected < 0 ? 'faltarán ${formatQuantity(-projected, row.unit)}' : 'quedarán ${formatQuantity(projected, row.unit)}'}',
      if (expiredBase > 0)
        'Incluye ${formatQuantity(expiredBase, row.unit)} vencidos',
      'Valor ${formatBob(row.availableValueBobMinor)}',
    ];
    return Material(
      color: AgroColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        key: Key('inventory-product-$id'),
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final color = row.availableBase < 0
                  ? AgroColors.danger
                  : AgroColors.ink;
              final info = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.productName,
                    style: const TextStyle(
                      fontSize: 17,
                      height: 22 / 17,
                      fontWeight: FontWeight.w700,
                      color: AgroColors.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final line in details)
                    Text(
                      line,
                      style: AgroText.detail.copyWith(
                        color: line.startsWith('Previsto') && projected < 0
                            ? AgroColors.danger
                            : null,
                      ),
                    ),
                  if (badges.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 6, children: badges),
                  ],
                ],
              );
              // La existencia va a la derecha si cabe entera en un tercio
              // largo de la fila; si no (letra grande, cifras largas), baja
              // debajo del nombre. Nunca se parte el rótulo.
              final figureWidth = [
                measureText(context, 'Existencia', AgroText.label),
                measureText(
                  context,
                  '${stock.number} ${stock.unit}',
                  const TextStyle(
                    fontFamily: AgroFonts.display,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ].reduce((a, b) => a > b ? a : b);
              if (figureWidth + 12 <= constraints.maxWidth * 0.38) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: info),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('Existencia', style: AgroText.label),
                        BigFigure(
                          number: stock.number,
                          unit: stock.unit,
                          alignment: Alignment.centerRight,
                          color: color,
                        ),
                      ],
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  info,
                  const SizedBox(height: 8),
                  const Text('Existencia', style: AgroText.label),
                  BigFigure(
                    number: stock.number,
                    unit: stock.unit,
                    color: color,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
