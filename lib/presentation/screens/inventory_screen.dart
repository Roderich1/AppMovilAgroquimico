import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../data/typed_reads.dart';
import '../../domain/inventory_alerts.dart';
import '../../domain/money.dart';
import '../../domain/read_models.dart';
import '../../operation_mode_controller.dart' show personalModeProvider;
import '../theme/agro_theme.dart';
import '../widgets/agro_ui.dart';
import '../widgets/common.dart';
import '../widgets/rdm2_b_lotes.dart';
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
/// - **Quedarían**: `projectedBase` = existencia − previsto; si es negativo,
///   «faltarían». Es una proyección por si se aplican los planes (ronda 2
///   del rediseño, 2026-11-12), no lo que hay ahora.
/// Los avisos cuentan **lotes** (vencimientos) y **productos** (existencia
/// baja), como dice cada rótulo.
///
/// **Modo individual** (láminas I-30, I-32 e I-33, 2026-11-13): las mismas
/// cifras y avisos, con el buscador siempre visible, filtros «Todos», «Por
/// vencer» y «Con planes», los avisos en una píldora de la cabecera y un
/// estado vacío que lleva a registrar una compra. Sin «Poco por
/// responsable»: el titular es el único responsable. El modo con varias
/// personas no cambia.
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

  /// Filtro del modo individual (lámina I-30).
  _PersonalFilter personalFilter = _PersonalFilter.all;
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
    return ref.watch(personalModeProvider)
        ? _personalPage(context)
        : _page(context);
  }

  Future<void> _newPurchase() async {
    await context.push('/compras/nueva');
    if (mounted) refresh();
  }

  Future<void> _newApplication() async {
    await context.push('/aplicaciones/nueva');
    if (mounted) refresh();
  }

  /// Almacén del modo individual (láminas I-30, I-32, I-33).
  Widget _personalPage(BuildContext context) => FutureBuilder<InventoryAlerts>(
    future: alerts,
    builder: (context, alertSnap) => FutureBuilder<List<InventoryLineRead>>(
      future: future,
      builder: (context, snapshot) {
        // Sólo productos con algo que contar: comprados, usados, en
        // existencia o previstos en planes. Un producto del catálogo que
        // nunca entró no es parte de su almacén (sigue en Ajustes ›
        // productos); así «todavía no tiene productos» es cierto.
        final all = snapshot.data?.where(inPersonalStore).toList();
        final alertData = alertSnap.data;
        final title = ScreenTitleBar(
          title: 'Almacén',
          actions: [
            if (all != null && all.isNotEmpty && alertData != null)
              _AlertsPill(
                count: personalAlertCount(alertData),
                onTap: _openAlerts,
              ),
          ],
        );
        if (snapshot.hasError) {
          return RdmScrollPage(
            children: [
              title,
              EmptyState(
                icon: Icons.error_outline,
                message: friendlyError(snapshot.error!),
              ),
            ],
          );
        }
        if (all == null) {
          return RdmScrollPage(
            children: [
              title,
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
          );
        }
        if (all.isEmpty) {
          return RdmScrollPage(
            children: [
              title,
              _PersonalEmpty(onPurchase: _newPurchase),
            ],
          );
        }
        bool inFilter(InventoryLineRead row) => switch (personalFilter) {
          _PersonalFilter.all => true,
          _PersonalFilter.expiring =>
            alertData != null &&
                [
                  ...alertData.dueToday,
                  ...alertData.near,
                ].any((a) => a.lot.productId == row.productId),
          _PersonalFilter.withPlans => row.committedBase != 0,
        };
        final rows = all
            .where((r) => matchesSearch(r.productName, query) && inFilter(r))
            .toList();
        return RdmScrollPage(
          children: [
            title,
            const SizedBox(height: 8),
            TextField(
              key: const Key('inventory-search'),
              controller: _search,
              onChanged: (value) =>
                  setState(() => query = value.trim().toLowerCase()),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar producto',
              ),
            ),
            const SizedBox(height: 10),
            FilterPillBar(
              children: [
                for (final (value, label) in const [
                  (_PersonalFilter.all, 'Todos'),
                  (_PersonalFilter.expiring, 'Por vencer'),
                  (_PersonalFilter.withPlans, 'Con planes'),
                ])
                  FilterPill(
                    key: Key('inventory-filter-${value.name}'),
                    label: label,
                    selected: personalFilter == value,
                    onSelected: () => setState(() => personalFilter = value),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              EmptyState(
                icon: Icons.search_off_outlined,
                message: query.isNotEmpty
                    ? 'Ningún producto coincide con "${_search.text.trim()}".'
                    : personalFilter == _PersonalFilter.expiring
                    ? 'Ningún producto vence pronto.'
                    : 'Ningún producto está previsto en planes.',
              )
            else
              _ProductGrid(
                rows: rows,
                cardOf: (row) => _ProductCard(
                  row: row,
                  alerts: alertData,
                  personal: true,
                  onTap: () => _openProduct(row.productId),
                ),
              ),
            const SizedBox(height: 6),
            AgroGroup(
              children: [
                LinkRow(
                  key: const Key('inventory-alerts-entry'),
                  icon: Icons.warning_amber_outlined,
                  title: 'Todos los avisos',
                  subtitle: alertSnap.hasError
                      ? 'No se pudieron calcular. Ábralos para ver el motivo.'
                      : alertData != null
                      ? inventoryAlertsSummary(alertData)
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
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                key: const Key('inventory-new-application'),
                onPressed: _newApplication,
                child: const Text('Registrar una aplicación'),
              ),
            ),
          ],
        );
      },
    ),
  );

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
                  _ProductGrid(
                    rows: rows,
                    cardOf: (row) => _ProductCard(
                      row: row,
                      alerts: alertSnap.data,
                      onTap: () => _openProduct(row.productId),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );
}

enum _PersonalFilter { all, expiring, withPlans }

/// Si un producto se muestra en el Almacén del modo individual: tiene
/// compras o consumos netos, existencia o lo piden planes pendientes.
@visibleForTesting
bool inPersonalStore(InventoryLineRead row) =>
    row.purchasedBase != 0 ||
    row.consumedBase != 0 ||
    row.availableBase != 0 ||
    row.committedBase != 0;

/// Avisos de inventario que cuenta la píldora del modo individual: lotes
/// vencidos, que vencen hoy o pronto, y productos con poca existencia en el
/// total (las mismas listas que «Avisos de inventario»).
@visibleForTesting
int personalAlertCount(InventoryAlerts alerts) =>
    alerts.expired.length +
    alerts.dueToday.length +
    alerts.near.length +
    alerts.lowStock.where((a) => a.line.isTotal).length;

/// Tarjetas de producto: de una en una o, en pantalla ancha (desde 640 de
/// lista: el Pixel 8 en horizontal da ~700), de dos en dos, cada una de al
/// menos 315, tan ancha como en un teléfono: a todo el ancho la existencia
/// quedaba lejos del nombre (revisión del autor, 2026-11-12). No es una
/// tabla: cada tarjeta conserva su lectura, sus avisos y su toque; el orden
/// sigue siendo por filas. Con letra grande la tarjeta crece en alto: en
/// horizontal dejaría de caber entera en la vista, así que el umbral crece
/// con la escala de la letra (640 × escala).
class _ProductGrid extends StatelessWidget {
  const _ProductGrid({required this.rows, required this.cardOf});

  final List<InventoryLineRead> rows;
  final Widget Function(InventoryLineRead row) cardOf;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns =
          constraints.maxWidth >= MediaQuery.textScalerOf(context).scale(640)
          ? 2
          : 1;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i += columns) ...[
            if (columns == 1)
              cardOf(rows[i])
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cardOf(rows[i])),
                  const SizedBox(width: 10),
                  Expanded(
                    child: i + 1 < rows.length
                        ? cardOf(rows[i + 1])
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            const SizedBox(height: 10),
          ],
        ],
      );
    },
  );
}

/// Píldora de avisos de la cabecera del modo individual (lámina I-30), con
/// texto además del color. Abre «Avisos de inventario».
class _AlertsPill extends StatelessWidget {
  const _AlertsPill({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  static const _warnInk = Color(0xFF5A3A00);

  @override
  Widget build(BuildContext context) {
    final label = switch (count) {
      0 => 'Sin avisos',
      1 => '1 aviso',
      _ => '$count avisos',
    };
    final ink = count == 0 ? AgroColors.ink : _warnInk;
    return Material(
      color: count == 0 ? AgroColors.surface : AgroColors.warnBg,
      shape: const StadiumBorder(),
      child: InkWell(
        key: const Key('inventory-alerts-pill'),
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (count > 0) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: _warnInk,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Almacén sin productos en el modo individual (lámina I-32). Sin
/// cantidades en cero: no hay nada que mostrar.
class _PersonalEmpty extends StatelessWidget {
  const _PersonalEmpty({required this.onPurchase});

  final VoidCallback onPurchase;

  @override
  Widget build(BuildContext context) => Padding(
    key: const Key('inventory-empty'),
    padding: const EdgeInsets.fromLTRB(8, 64, 8, 24),
    child: Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AgroColors.ink,
            borderRadius: BorderRadius.circular(22),
          ),
          child: const Icon(
            Icons.inventory_2_outlined,
            size: 34,
            color: AgroColors.lime,
          ),
        ),
        const SizedBox(height: 18),
        Semantics(
          header: true,
          child: const Text(
            'Su almacén todavía no tiene productos',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AgroFonts.display,
              fontSize: 22,
              height: 28 / 22,
              fontWeight: FontWeight.w800,
              color: AgroColors.ink,
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Los productos entran al registrar una compra. No hay cantidades '
          'que mostrar.',
          textAlign: TextAlign.center,
          style: AgroText.detail,
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('inventory-empty-purchase'),
          style: FilledButton.styleFrom(
            backgroundColor: AgroColors.lime,
            foregroundColor: AgroColors.ink,
            minimumSize: const Size(0, 52),
            padding: const EdgeInsets.symmetric(horizontal: 28),
            shape: const StadiumBorder(),
          ),
          onPressed: onPurchase,
          child: const Text(
            'Registrar una compra',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
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
    this.personal = false,
  });

  final InventoryLineRead row;
  final InventoryAlerts? alerts;
  final VoidCallback onTap;

  /// Modo individual: el titular es el único responsable; no hay «Poco por
  /// responsable» (la existencia baja es la del total).
  final bool personal;

  @override
  Widget build(BuildContext context) {
    final id = row.productId;
    final alerts = this.alerts;
    final expired = alerts?.expired.where((a) => a.lot.productId == id) ?? [];
    final today = alerts?.dueToday.where((a) => a.lot.productId == id) ?? [];
    final near = alerts?.near.where((a) => a.lot.productId == id) ?? [];
    final low = alerts?.lowStock.where((a) => a.line.productId == id) ?? [];
    final expiredBase = expired.fold(0, (sum, a) => sum + a.lot.remainingBase);
    final badges = <Widget>[
      if (expired.isNotEmpty)
        StatusBadge(
          label: expired.length == 1
              ? 'Lote vencido'
              : '${expired.length} lotes vencidos',
          tone: BadgeTone.missing,
        ),
      // Ronda 2: con la cantidad afectada, para que no se lea como si
      // venciera todo el producto.
      if (today.isNotEmpty)
        StatusBadge(
          label: todayExpiryBadge(today, row.unit),
          tone: BadgeTone.review,
        ),
      if (near.isNotEmpty)
        StatusBadge(
          label: nearExpiryBadge(near, row.unit),
          tone: BadgeTone.review,
        ),
      if (low.any((a) => a.line.isTotal))
        const StatusBadge(label: 'Queda poco', tone: BadgeTone.neutral)
      else if (low.isNotEmpty && !personal)
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
            '${projected < 0 ? 'faltarían ${formatQuantity(-projected, row.unit)}' : 'quedarían ${formatQuantity(projected, row.unit)}'}',
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
