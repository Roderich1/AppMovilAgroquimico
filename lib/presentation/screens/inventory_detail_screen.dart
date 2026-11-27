import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../domain/agro_gateway.dart';
import '../../domain/campaign_calendar.dart';
import '../../domain/inventory_alerts.dart';
import '../../domain/money.dart';
import '../../domain/person_roles.dart' show PersonPurpose;
import '../../domain/repository_types.dart'
    show ProductMovementFilter, repositoryMaxAlertLeadDays;
import '../../operation_mode_controller.dart' show personalModeProvider;
import '../../services/auth/local_owner_credential.dart'
    show AuthorizationPurpose;
import '../theme/agro_theme.dart';
import '../widgets/agro_ui.dart';
import '../widgets/rdm2_b_lotes.dart';
import '../widgets/rdm_b_ui.dart';
import '../widgets/common.dart';
import 'owner_credential_screen.dart' show requestOwnerAuthorization;

typedef _InventoryDetail = ({
  Map<String, Object?> header,
  List<Map<String, Object?>> distribution,
  List<({int availableBase, String? expiryDay})> expiryTotals,
  ProductAlertSettings alertSettings,
  String? titularName,
});

/// Cuántos movimientos o lotes muestra cada página inicial y cuántos añade
/// «Ver más».
const _movementsPage = 20;
const _lotsPage = 20;

enum _ProductDetailTab { summary, movements, lots }

enum _LotFilter { inStock, expiring, all }

/// Detalle de un producto dividido en tres subvistas («Resumen»,
/// «Movimientos» y «Lotes») bajo la cabecera de existencias y
/// vencimientos:
///
/// - **Cabecera:** cuánto hay ahora y qué parte vence (calculado siempre sobre
///   todos los lotes con existencia, sin verse afectado por filtros ni
///   paginación de las pestañas).
/// - **Resumen** (vista inicial): quién lo tiene (en modo compartido), lo
///   previsto en planes (si hay comprometido), cifras clave («Comprado neto»,
///   «Consumido neto» y «Valor a costo de compra» con «No es una deuda») y
///   avisos del producto.
/// - **Movimientos:** filtros por categoría aplicados en la consulta antes de
///   paginar («Todo», «Compras», «Aplicaciones» y, en compartido, «Pases»; las
///   reversiones permanecen en su categoría y los pases históricos siguen en
///   «Todo» también en modo individual).
/// - **Lotes:** «Con stock» como vista inicial, «Por vencer» y «Todos» (que
///   incluye los lotes agotados identificados con la etiqueta «Agotado»; los
///   de compras revertidas se consultan en Movimientos).
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

  _ProductDetailTab _tab = _ProductDetailTab.summary;
  ProductMovementFilter _movementFilter = ProductMovementFilter.all;
  int _movementLimit = _movementsPage;

  _LotFilter _lotFilter = _LotFilter.inStock;

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
      expiryTotals: await repo.inventoryProductExpiryTotals(widget.productId),
      alertSettings: await repo.productAlertSettings(widget.productId),
      // Sólo en propio (una consulta más): el nombre del titular, para no
      // repetirlo en cada movimiento y lote y conservar el de otra persona
      // en la historia anterior al cambio de modo.
      titularName: ref.read(personalModeProvider)
          ? await _titularName(repo)
          : null,
    );
  }

  static Future<String?> _titularName(AgroGateway repo) async {
    final read = await repo.peopleAndContextFor(PersonPurpose.providerPayer);
    final owner = read.context.ownerPersonId;
    for (final person in read.people) {
      if (person['id'] == owner) return person['name'] as String?;
    }
    return null;
  }

  /// Configura el nivel mínimo y el plazo de aviso (RF-44). Corresponde al
  /// titular: primero los dos valores y, al guardar, su PIN una sola vez
  /// (decisión del autor del 2026-11-01). Cancelar en cualquier paso no
  /// cambia nada. Sólo cambia esa configuración; no toca existencias ni
  /// operaciones.
  Future<void> _configureAlerts(ProductAlertSettings current) async {
    final result = await showDialog<({int? minStockBase, int? leadDays})>(
      context: context,
      builder: (_) => AlertSettingsDialog(current: current),
    );
    if (result == null || !mounted) return;
    final repo = ref.read(repositoryProvider);
    String min(int? v) =>
        v == null ? 'sin nivel mínimo' : formatQuantity(v, current.unit);
    String lead(int? v) => v == null
        ? '$defaultAlertLeadDays días (valor inicial)'
        : (v == 1 ? '1 día' : '$v días');
    final authorization = await requestOwnerAuthorization(
      context,
      ref,
      purpose: AuthorizationPurpose.configureProductAlerts,
      subjectRef: productAlertsSubjectRef(widget.productId),
      title: 'Avisos de ${current.productName}',
      effects:
          'Nivel mínimo: ${min(current.minStockBase)} → '
          '${min(result.minStockBase)}. Aviso de vencimiento: '
          '${lead(current.leadDays)} → ${lead(result.leadDays)}. Sólo cambia '
          'cuándo se avisa: las existencias no cambian.',
    );
    if (authorization == null || !mounted) return;
    try {
      await repo.setProductAlertSettings(
        widget.productId,
        minStockBase: result.minStockBase,
        leadDays: result.leadDays,
        authorization: authorization,
      );
      if (!mounted) return;
      showSuccess(context, 'Se guardaron los avisos de este producto.');
      final next = _load();
      setState(() {
        detail = next;
      });
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  /// Se pide una fila más que las que se muestran para saber si hay más, con
  /// el filtro aplicado antes del límite en la consulta SQL.
  Future<List<Map<String, Object?>>> _loadMovements({
    ProductMovementFilter? filter,
    int? limit,
  }) => ref
      .read(repositoryProvider)
      .productMovements(
        widget.productId,
        limit: (limit ?? _movementLimit) + 1,
        filter: filter ?? _movementFilter,
      );

  void _selectMovementFilter(ProductMovementFilter next) {
    if (_movementFilter == next) return;
    setState(() {
      _movementFilter = next;
      _movementLimit = _movementsPage;
      movements = _loadMovements(filter: next, limit: _movementsPage);
    });
  }

  void _showMoreMovements() {
    final nextLimit = _movementLimit + _movementsPage;
    setState(() {
      _movementLimit = nextLimit;
      movements = _loadMovements(limit: nextLimit);
    });
  }

  void _selectLotFilter(_LotFilter next) => setState(() => _lotFilter = next);

  /// Lo que significan las cifras: se abre con «i» en la cabecera, sin
  /// párrafos permanentes. Los términos técnicos («neto», «asignación neta»)
  /// se explican aquí.
  Future<void> _showInfo(bool personal) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('inventory-info-dialog'),
      title: const Text('Qué significan estas cifras'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cuánto hay, de qué compras viene y en qué se usó. El '
              'inventario continúa entre campañas.',
            ),
            const SizedBox(height: 10),
            Text(
              personal
                  ? 'Tiene ahora: lo que queda en su almacén (en el cálculo, '
                        'el físico). Los vencimientos dicen qué cantidad vence '
                        'y cuándo, según la fecha de cada lote.'
                  : 'Hay ahora: lo que queda entre todas las personas (en el '
                        'cálculo, el físico). Los vencimientos dicen qué '
                        'cantidad vence y cuándo, según la fecha de cada lote.',
            ),
            const SizedBox(height: 10),
            const Text(
              'Neto: no cuenta lo revertido. Comprado neto menos consumido '
              'neto es lo que hay ahora.',
            ),
            const SizedBox(height: 10),
            const Text(
              'Previsto en planes: lo que piden los planes pendientes de la '
              'campaña activa. No aparta producto: «Quedarían» es lo que hay '
              'ahora menos lo previsto, una proyección por si se aplican los '
              'planes. Si es negativo, faltaría producto.',
            ),
            // En propio no hay asignaciones a otras personas ni pases.
            if (!personal) ...[
              const SizedBox(height: 10),
              const Text(
                'Asignación neta: lo comprado para esta persona, más lo que '
                'recibió y menos lo que entregó por transferencias. No cuenta '
                'lo revertido. Restando lo consumido queda lo que tiene. En '
                '«Quién lo tiene», «Usó 1 L de 3 L» es su consumido neto de '
                'su asignación neta.',
              ),
            ],
            const SizedBox(height: 10),
            const Text(
              'Valor a costo de compra: lo que hay ahora, valorado al costo '
              'de cada lote. No es una deuda ni un saldo.',
            ),
            const SizedBox(height: 10),
            Text(
              personal
                  ? 'Lo que explica el saldo: compras, aplicaciones y '
                        'reversiones, del más reciente al más antiguo.'
                  : 'Lo que explica el saldo: compras, aplicaciones, pases '
                        '(entregas sin deuda) y reversiones, del más reciente '
                        'al más antiguo.',
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<_InventoryDetail>(
    future: detail,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return RdmScrollPage(
          children: [
            const ScreenTitleBar(title: 'Producto', leading: RdmBackButton()),
            EmptyState(
              icon: Icons.error_outline,
              message: friendlyError(snapshot.error!),
            ),
          ],
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final data = snapshot.data!;
      final h = data.header;
      // Sin modalidad conocida se presenta la compartida, la de defecto
      // (operation_mode_controller.dart).
      final personal = ref.watch(personalModeProvider);
      final productName = h['product_name'] as String;
      final unit = h['unit'] as String;
      final physical = h['physical_base'] as int;
      final committed = h['committed_base'] as int;
      // Vencimiento de los lotes con existencia, con el plazo del producto
      // (RN-31), agrupado por fecha con su cantidad.
      final now = DateTime.now();
      final today = localDay(now);
      final lead = data.alertSettings.leadDays ?? defaultAlertLeadDays;
      final expiryThrough = _lotFilter == _LotFilter.expiring
          ? localDay(DateTime(now.year, now.month, now.day + lead))
          : null;
      final portions = expiryPortions(
        lots: data.expiryTotals,
        today: today,
        leadDays: lead,
      );
      // En modo individual no se muestra la pastilla «Pases»; si estaba
      // elegida antes de cambiar de modo, vuelve a «Todo» (donde los pases
      // históricos siguen visibles).
      if (personal && _movementFilter == ProductMovementFilter.transfers) {
        _movementFilter = ProductMovementFilter.all;
        _movementLimit = _movementsPage;
        movements = _loadMovements(
          filter: ProductMovementFilter.all,
          limit: _movementsPage,
        );
      }
      return RdmScrollPage(
        header: _Header(
          productName: productName,
          physical: physical,
          unit: unit,
          portions: portions,
          leadDays: lead,
          personal: personal,
          onInfo: () => _showInfo(personal),
        ),
        children: [
          SegmentToggle<_ProductDetailTab>(
            key: const Key('inventory-detail-tabs'),
            selected: _tab,
            onChanged: (next) => setState(() => _tab = next),
            options: const [
              ToggleOption(
                _ProductDetailTab.summary,
                'Resumen',
                key: Key('inventory-tab-summary'),
              ),
              ToggleOption(
                _ProductDetailTab.movements,
                'Movimientos',
                key: Key('inventory-tab-movements'),
              ),
              ToggleOption(
                _ProductDetailTab.lots,
                'Lotes',
                key: Key('inventory-tab-lots'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_tab == _ProductDetailTab.summary) ...[
            // En propio todo es del titular: «Quién lo tiene» repetiría su
            // nombre con la misma cifra de la cabecera (lámina I-31).
            if (!personal) ...[
              const _SectionTitle('Quién lo tiene'),
              AgroGroup(
                key: const Key('inventory-distribution'),
                children: [
                  for (final row in data.distribution)
                    // Material propio: el grupo blanco tiene color de fondo.
                    _onWhite(
                      ListTile(
                        title: Text(
                          row['person_name'] as String,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AgroColors.ink,
                          ),
                        ),
                        // Consumido neto de su asignación neta (los términos,
                        // en «i»).
                        subtitle: Text(
                          'Usó ${formatQuantity(row['consumed_base'] as int, unit)} '
                          'de ${formatQuantity(row['assigned_base'] as int, unit)}',
                          style: AgroText.detail,
                        ),
                        trailing: Text(
                          formatQuantity(row['available_base'] as int, unit),
                          style: AgroText.amount,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            // Sólo cuando hay planes pendientes que piden este producto.
            if (committed != 0) ...[
              if (!personal) const SizedBox(height: 18),
              if (personal)
                _PersonalPlansCard(
                  physical: physical,
                  committed: committed,
                  unit: unit,
                )
              else
                _PlansCard(
                  physical: physical,
                  committed: committed,
                  unit: unit,
                ),
            ],
            if (!personal || committed != 0) const SizedBox(height: 18),
            const _SectionTitle('Cifras clave'),
            AgroGroup(
              key: const Key('inventory-totals'),
              children: [
                _FigureRow(
                  label: 'Comprado neto',
                  value: formatQuantity(h['purchased_base'] as int, unit),
                ),
                _FigureRow(
                  label: 'Consumido neto',
                  value: formatQuantity(h['consumed_base'] as int, unit),
                ),
                _FigureRow(
                  label: 'Valor a costo de compra',
                  hint: 'De lo que hay ahora. No es una deuda.',
                  value: formatBob(h['value_bob_minor'] as int),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: Text(
                    'Neto: sin operaciones revertidas.',
                    key: Key('inventory-net-note'),
                    style: AgroText.detail,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _AlertSettingsCard(
              settings: data.alertSettings,
              onConfigure: () => _configureAlerts(data.alertSettings),
            ),
          ] else if (_tab == _ProductDetailTab.movements) ...[
            FilterPillBar(
              children: [
                FilterPill(
                  key: const Key('inventory-movements-filter-all'),
                  label: 'Todo',
                  selected: _movementFilter == ProductMovementFilter.all,
                  onSelected: () =>
                      _selectMovementFilter(ProductMovementFilter.all),
                ),
                FilterPill(
                  key: const Key('inventory-movements-filter-purchases'),
                  label: 'Compras',
                  selected: _movementFilter == ProductMovementFilter.purchases,
                  onSelected: () =>
                      _selectMovementFilter(ProductMovementFilter.purchases),
                ),
                FilterPill(
                  key: const Key('inventory-movements-filter-applications'),
                  label: 'Aplicaciones',
                  selected:
                      _movementFilter == ProductMovementFilter.applications,
                  onSelected: () =>
                      _selectMovementFilter(ProductMovementFilter.applications),
                ),
                if (!personal)
                  FilterPill(
                    key: const Key('inventory-movements-filter-transfers'),
                    label: 'Pases',
                    selected:
                        _movementFilter == ProductMovementFilter.transfers,
                    onSelected: () =>
                        _selectMovementFilter(ProductMovementFilter.transfers),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<Map<String, Object?>>>(
              key: ValueKey(('movements', _movementFilter, _movementLimit)),
              future: movements,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return EmptyState(
                    icon: Icons.error_outline,
                    message: friendlyError(snapshot.error!),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                final rows = snapshot.data!;
                if (rows.isEmpty) {
                  return EmptyState(
                    icon: Icons.history_outlined,
                    message: _movementFilter == ProductMovementFilter.all
                        ? 'Todavía no hay movimientos de este producto.'
                        : 'No hay movimientos en esta categoría.',
                  );
                }
                final hasMore = rows.length > _movementLimit;
                return AgroGroup(
                  key: const Key('inventory-movements'),
                  children: [
                    for (final row in rows.take(_movementLimit))
                      _MovementTile(
                        row: row,
                        unit: unit,
                        personal: personal,
                        titularName: data.titularName,
                      ),
                    if (hasMore)
                      _onWhite(
                        TextButton.icon(
                          key: const Key('inventory-history-more'),
                          onPressed: _showMoreMovements,
                          icon: const Icon(Icons.expand_more),
                          label: const Text('Ver más'),
                        ),
                      ),
                  ],
                );
              },
            ),
          ] else ...[
            FilterPillBar(
              children: [
                FilterPill(
                  key: const Key('inventory-lots-filter-inStock'),
                  label: 'Con stock',
                  selected: _lotFilter == _LotFilter.inStock,
                  onSelected: () => _selectLotFilter(_LotFilter.inStock),
                ),
                FilterPill(
                  key: const Key('inventory-lots-filter-expiring'),
                  label: 'Por vencer',
                  selected: _lotFilter == _LotFilter.expiring,
                  onSelected: () => _selectLotFilter(_LotFilter.expiring),
                ),
                FilterPill(
                  key: const Key('inventory-lots-filter-all'),
                  label: 'Todos',
                  selected: _lotFilter == _LotFilter.all,
                  onSelected: () => _selectLotFilter(_LotFilter.all),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _LotsSection(
              key: ValueKey((widget.productId, _lotFilter, expiryThrough)),
              productId: widget.productId,
              filter: _lotFilter,
              expiryThrough: expiryThrough,
              unit: unit,
              today: today,
              lead: lead,
              personal: personal,
              titularName: data.titularName,
            ),
          ],
        ],
      );
    },
  );
}

String _leadText(int? leadDays) =>
    '${leadDaysText(leadDays ?? defaultAlertLeadDays)}'
    '${leadDays == null ? ' (valor inicial)' : ''}';

/// Título de sección del detalle.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Semantics(header: true, child: Text(text, style: AgroText.h2)),
  );
}

/// Cabecera oscura: nombre, cuánto hay ahora en grande y qué parte vence.
class _Header extends StatelessWidget {
  const _Header({
    required this.productName,
    required this.physical,
    required this.unit,
    required this.portions,
    required this.leadDays,
    required this.onInfo,
    this.personal = false,
  });

  final String productName;
  final int physical;
  final String unit;
  final List<ExpiryPortion> portions;
  final int leadDays;
  final VoidCallback onInfo;

  /// Modo individual: «Tiene ahora» (todo es del titular) en vez de «Hay
  /// ahora» (entre todas las personas). La cifra es la misma.
  final bool personal;

  /// Como mucho tres líneas de vencimiento; el resto se ve en los lotes.
  static const _maxLines = 3;

  @override
  Widget build(BuildContext context) {
    final warns = portions.where((p) => p.warns).toList();
    final later = portions.any((p) => p.status == ExpiryStatus.later);
    final unknown = portions.where((p) => p.status == ExpiryStatus.unknown);
    final lines = <Widget>[
      for (final p in warns.take(_maxLines))
        ExpiryLine(
          status: p.status,
          text: expiryPortionText(p, unit),
          onDark: true,
        ),
      if (warns.length > _maxLines)
        ExpiryLine(
          status: ExpiryStatus.near,
          text:
              '${warns.length - _maxLines} '
              '${warns.length - _maxLines == 1 ? 'fecha más' : 'fechas más'}: '
              'ver pestaña Lotes',
          onDark: true,
        ),
      if (warns.isEmpty && later)
        ExpiryLine(
          status: ExpiryStatus.later,
          text: leadDays == 0
              ? 'Nada vence hoy'
              : 'Nada vence en los próximos '
                    '${leadDays == 1 ? '1 día' : '$leadDays días'}',
          onDark: true,
        ),
      for (final p in unknown)
        ExpiryLine(
          status: p.status,
          text: expiryPortionText(p, unit),
          onDark: true,
        ),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: AgroColors.ink,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const RdmBackButton(
                background: AgroColors.inkSoft,
                foreground: AgroColors.onInk,
              ),
              const Spacer(),
              CircleIconButton(
                key: const Key('inventory-info'),
                icon: Icons.info_outline,
                tooltip: 'Qué significan estas cifras',
                onPressed: onInfo,
                background: AgroColors.inkSoft,
                foreground: AgroColors.onInk,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    productName,
                    style: const TextStyle(
                      fontFamily: AgroFonts.display,
                      fontSize: 20,
                      height: 26 / 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Semantics(
                  label:
                      '${personal ? 'Tiene ahora' : 'Hay ahora'}: '
                      '${formatQuantity(physical, unit)}',
                  excludeSemantics: true,
                  child: Column(
                    key: const Key('metric-Hay ahora'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        personal ? 'Tiene ahora' : 'Hay ahora',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AgroColors.onInkMuted,
                        ),
                      ),
                      BigFigure(
                        number: splitQuantity(physical, unit).number,
                        unit: splitQuantity(physical, unit).unit,
                        size: 64,
                        color: AgroColors.lime,
                      ),
                    ],
                  ),
                ),
                if (lines.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Column(
                    key: const Key('inventory-expiry'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < lines.length; i++) ...[
                        if (i > 0) const SizedBox(height: 4),
                        lines[i],
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lo previsto en planes pendientes y lo que quedaría si se aplican: una
/// proyección, no una reserva ni lo que hay ahora (`committed_base`).
class _PlansCard extends StatelessWidget {
  const _PlansCard({
    required this.physical,
    required this.committed,
    required this.unit,
  });

  final int physical;
  final int committed;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final projected = physical - committed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle('Planes pendientes'),
        AgroGroup(
          key: const Key('inventory-plans'),
          children: [
            _FigureRow(
              label: 'Previsto en planes',
              value: formatQuantity(committed, unit),
            ),
            _FigureRow(
              label: projected < 0
                  ? 'Faltarían si se aplican los planes'
                  : 'Quedarían si se aplican los planes',
              value: formatQuantity(projected.abs(), unit),
              warn: projected < 0,
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Text(
                'Es una proyección: los planes no apartan producto y lo que '
                'hay ahora no cambia.',
                style: AgroText.detail,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Lo previsto en planes en el modo individual (lámina I-31): la cifra, una
/// barra con la parte de lo que tiene ahora que piden los planes y la
/// proyección en una frase. Mismas cifras que [_PlansCard]; un plan no
/// aparta ni descuenta producto.
class _PersonalPlansCard extends StatelessWidget {
  const _PersonalPlansCard({
    required this.physical,
    required this.committed,
    required this.unit,
  });

  final int physical;
  final int committed;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final projected = physical - committed;
    final short = projected < 0;
    // Parte de lo que hay que piden los planes; llena si piden más de lo
    // que hay (o si no hay nada).
    final share = physical <= 0 ? 1.0 : (committed / physical).clamp(0.0, 1.0);
    final barColor = short ? AgroColors.danger : const Color(0xFFC77700);
    final text = short
        ? 'Proyección: si ejecuta sus planes faltarían '
              '${formatQuantity(-projected, unit)}. Un plan no descuenta '
              'existencias.'
        : 'Proyección: si ejecuta sus planes quedarán '
              '${formatQuantity(projected, unit)}. Un plan no descuenta '
              'existencias.';
    return Container(
      key: const Key('inventory-plans'),
      decoration: BoxDecoration(
        color: AgroColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Semantics(
        label: 'Previsto en planes: ${formatQuantity(committed, unit)}. $text',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AmountAside(
              amount: formatQuantity(committed, unit),
              minTextWidth: 140,
              child: const Text(
                'Previsto en planes',
                style: TextStyle(
                  fontSize: 17,
                  height: 22 / 17,
                  fontWeight: FontWeight.w700,
                  color: AgroColors.ink,
                ),
              ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                key: const Key('inventory-plans-bar'),
                value: share,
                minHeight: 10,
                color: barColor,
                backgroundColor: AgroColors.canvas,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              text,
              key: const Key('inventory-plans-projection'),
              style: AgroText.detail.copyWith(
                color: short ? AgroColors.danger : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cifra con su rótulo en una fila blanca («Comprado neto 9 L»). La clave
/// `metric-<rótulo>` la usan las pruebas.
class _FigureRow extends StatelessWidget {
  const _FigureRow({
    required this.label,
    required this.value,
    this.hint,
    this.warn = false,
  });

  final String label;
  final String value;
  final String? hint;

  /// Proyección negativa: icono y color de advertencia.
  final bool warn;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label: $value${hint == null ? '' : '. $hint'}',
    excludeSemantics: true,
    child: Padding(
      key: Key('metric-$label'),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      // Con letra grande la cifra baja debajo del rótulo, sin desbordar.
      child: AmountAside(
        amount: value,
        amountStyle: AgroText.amount.copyWith(
          color: warn ? AgroColors.danger : null,
        ),
        minTextWidth: 140,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (warn) ...[
              const Icon(
                Icons.warning_amber_rounded,
                size: 20,
                color: AgroColors.danger,
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      height: 20 / 15,
                      fontWeight: FontWeight.w500,
                      color: warn ? AgroColors.danger : AgroColors.ink,
                    ),
                  ),
                  if (hint != null) Text(hint!, style: AgroText.detail),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Lista paginada de lotes en la subvista «Lotes»: cada uno como tarjeta
/// legible, sin identificador interno; el número del fabricante sólo si
/// existe, y los agotados con la etiqueta «Agotado».
class _LotsSection extends ConsumerStatefulWidget {
  const _LotsSection({
    super.key,
    required this.productId,
    required this.filter,
    required this.expiryThrough,
    required this.unit,
    required this.today,
    required this.lead,
    this.personal = false,
    this.titularName,
  });

  final int productId;
  final _LotFilter filter;
  final String? expiryThrough;
  final String unit;
  final String today;
  final int lead;

  /// Modo individual: los lotes del titular sin su nombre; los de otra
  /// persona (si quedaran) con el suyo.
  final bool personal;
  final String? titularName;

  @override
  ConsumerState<_LotsSection> createState() => _LotsSectionState();
}

class _LotsSectionState extends ConsumerState<_LotsSection> {
  final _lots = <Map<String, Object?>>[];
  bool _loading = false;
  bool _hasMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadNext());
  }

  Future<void> _loadNext() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await ref
          .read(repositoryProvider)
          .inventoryProductLots(
            widget.productId,
            includeExhausted: widget.filter == _LotFilter.all,
            expiryThrough: widget.expiryThrough,
            limit: _lotsPage + 1,
            offset: _lots.length,
          );
      if (!mounted) return;
      setState(() {
        _lots.addAll(rows.take(_lotsPage));
        _hasMore = rows.length > _lotsPage;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(error);
        _loading = false;
      });
    }
  }

  String _expiryText(ExpiryStatus status, String? day) => switch (status) {
    ExpiryStatus.expired => 'Venció el ${displayDay(day!)}',
    ExpiryStatus.today => 'Vence hoy',
    ExpiryStatus.near => 'Vence el ${displayDay(day!)} · por vencer',
    ExpiryStatus.later => 'Vence el ${displayDay(day!)}',
    ExpiryStatus.unknown => 'Sin fecha de vencimiento registrada',
  };

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (_lots.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_lots.isEmpty && error == null) {
      return EmptyState(
        key: const Key('inventory-lots'),
        icon: Icons.inventory_2_outlined,
        message: switch (widget.filter) {
          _LotFilter.inStock => 'No hay lotes con existencia.',
          _LotFilter.expiring => 'No hay lotes vencidos ni próximos a vencer.',
          _LotFilter.all => 'Todavía no hay lotes de este producto.',
        },
      );
    }
    final references = lotReferences([
      for (final lot in _lots)
        (
          person: lot['owner_name'] as String,
          acquiredDay: storedLocalDay(lot['acquired_date'] as String),
        ),
    ]);
    return Container(
      key: const Key('inventory-lots'),
      decoration: BoxDecoration(
        color: AgroColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, lot) in _lots.indexed) ...[
            if (i > 0) const SizedBox(height: 8),
            Builder(
              builder: (context) {
                final expiry = lot['expiry_date'] as String?;
                final available = lot['available_base'] as int;
                final exhausted = available == 0;
                final status = classifyExpiry(
                  expiryDay: expiry,
                  today: widget.today,
                  leadDays: widget.lead,
                );
                return LotCard(
                  key: Key('inventory-lot-$i'),
                  person:
                      widget.personal &&
                          widget.titularName != null &&
                          lot['owner_name'] == widget.titularName
                      ? null
                      : lot['owner_name'] as String,
                  quantity: formatQuantity(available, widget.unit),
                  purchaseDay: formatDate(lot['acquired_date']),
                  expiryStatus: status,
                  expiryText: _expiryText(status, expiry),
                  details: [
                    'Costo ${lotCostText(lot['unit_cost'] as int, widget.unit)}',
                    '${lot['supplier_name']} · ${lot['campaign_name']}',
                  ],
                  manufacturerLot: lot['lot_number'] as String?,
                  reference: references[i],
                  fromTransfer: lot['parent_lot_id'] != null,
                  exhausted: exhausted,
                );
              },
            ),
          ],
          if (error != null) Text(error, style: AgroText.detail),
          if (_loading)
            const LinearProgressIndicator()
          else if (_hasMore || error != null) ...[
            const SizedBox(height: 8),
            _onWhite(
              TextButton.icon(
                key: const Key('inventory-lots-more'),
                onPressed: _loadNext,
                icon: const Icon(Icons.expand_more),
                label: Text(error == null ? 'Ver más' : 'Reintentar'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Configuración de avisos del producto (RF-44), visible para el titular.
class _AlertSettingsCard extends StatelessWidget {
  const _AlertSettingsCard({required this.settings, required this.onConfigure});
  final ProductAlertSettings settings;
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    final min = settings.minStockBase;
    return Container(
      key: const Key('inventory-alert-settings'),
      decoration: BoxDecoration(
        color: AgroColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.notifications_outlined, color: AgroColors.ink),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Avisos de este producto',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AgroColors.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    min == null
                        ? 'Sin nivel mínimo: no se avisa cuando queda poco.'
                        : 'Nivel mínimo: ${formatQuantity(min, settings.unit)}.',
                    style: AgroText.detail.copyWith(color: AgroColors.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Aviso de vencimiento: ${_leadText(settings.leadDays)}.',
                    style: AgroText.detail.copyWith(color: AgroColors.ink),
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const Key('inventory-alert-settings-edit'),
                onPressed: onConfigure,
                icon: const Icon(Icons.tune),
                label: const Text('Configurar avisos'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Diálogo del nivel mínimo y el plazo de aviso. Un campo vacío es «sin
/// nivel» o «valor inicial», nunca cero. Con el lenguaje de los formularios
/// del rediseño (rótulo fijo, unidad al lado, aviso del PIN en un recuadro);
/// la validación, el PIN y lo que se guarda no cambian.
class AlertSettingsDialog extends StatefulWidget {
  const AlertSettingsDialog({super.key, required this.current});
  final ProductAlertSettings current;

  @override
  State<AlertSettingsDialog> createState() => _AlertSettingsDialogState();
}

class _AlertSettingsDialogState extends State<AlertSettingsDialog> {
  late final TextEditingController minimum;
  late final TextEditingController days;
  String? minimumError;
  String? daysError;

  /// Se escribió algo distinto, pero con el mismo valor («2,5» y «2,50»).
  bool sameValues = false;

  @override
  void initState() {
    super.initState();
    final min = widget.current.minStockBase;
    minimum = TextEditingController(
      text: min == null ? '' : formatForInput(min / baseUnitsPerMajor),
    );
    days = TextEditingController(
      text: widget.current.leadDays?.toString() ?? '',
    );
    _initialMinimum = minimum.text;
    _initialDays = days.text;
  }

  @override
  void dispose() {
    minimum.dispose();
    days.dispose();
    super.dispose();
  }

  /// Algo distinto de lo guardado. Sin cambios no se pide el PIN.
  bool get _changed =>
      minimum.text.trim() != _initialMinimum ||
      days.text.trim() != _initialDays;

  late final String _initialMinimum;
  late final String _initialDays;

  void _save() {
    int? minBase;
    int? leadDays;
    String? minError;
    String? dayError;
    if (minimum.text.trim().isNotEmpty) {
      final parsed = parseNumericInput(minimum.text);
      if (!parsed.isValid || parsed.value! < 0) {
        minError = parsed.message ?? 'Escriba una cantidad de 0 o más.';
      } else {
        minBase = (parsed.value! * baseUnitsPerMajor).round();
      }
    }
    if (days.text.trim().isNotEmpty) {
      // Sólo dígitos: int.tryParse aceptaría «0x10» o «+5».
      final text = days.text.trim();
      final parsed = RegExp(r'^\d{1,3}$').hasMatch(text)
          ? int.parse(text)
          : null;
      if (parsed == null || parsed < 0 || parsed > repositoryMaxAlertLeadDays) {
        dayError =
            'Escriba un número entero de días, de 0 a '
            '$repositoryMaxAlertLeadDays.';
      } else {
        leadDays = parsed;
      }
    }
    if (minError != null || dayError != null) {
      setState(() {
        minimumError = minError;
        daysError = dayError;
      });
      return;
    }
    // «2» y «2,0» son el mismo nivel: sin cambio real no se pide el PIN.
    if (minBase == widget.current.minStockBase &&
        leadDays == widget.current.leadDays) {
      setState(() => sameValues = true);
      return;
    }
    Navigator.pop(context, (minStockBase: minBase, leadDays: leadDays));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Avisos de ${widget.current.productName}'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Rótulo como pregunta encima del campo (como «¿Para quién es?»
          // de Compra): con letra grande no se corta, como pasaba con el
          // rótulo flotante.
          _DialogField(
            label: 'Nivel mínimo',
            field: TextField(
              key: const Key('alert-settings-minimum'),
              controller: minimum,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: AgroText.value,
              onChanged: (_) => setState(() {
                minimumError = null;
                sameValues = false;
              }),
              decoration: InputDecoration(
                // Siempre visible (suffixText sólo se ve con foco o texto).
                suffixIcon: _UnitSuffix(widget.current.unit),
                helperText:
                    'Vacío: sin aviso de existencia baja. 0: avisa sólo '
                    'cuando se acaba.',
                helperMaxLines: 6,
                errorText: minimumError,
                errorMaxLines: 6,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _DialogField(
            label: 'Avisar antes del vencimiento',
            field: TextField(
              key: const Key('alert-settings-days'),
              controller: days,
              keyboardType: TextInputType.number,
              style: AgroText.value,
              onChanged: (_) => setState(() {
                daysError = null;
                sameValues = false;
              }),
              decoration: InputDecoration(
                // Siempre visible (suffixText sólo se ve con foco o texto).
                suffixIcon: _UnitSuffix('días'),
                helperText:
                    'De 0 a $repositoryMaxAlertLeadDays días. Vacío: '
                    '$defaultAlertLeadDays días (valor inicial).',
                helperMaxLines: 6,
                errorText: daysError,
                errorMaxLines: 6,
              ),
            ),
          ),
          if (sameValues)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 18,
                    color: AgroColors.danger,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'No hay cambios que guardar: los valores son los mismos.',
                      key: const Key('alert-settings-same'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          const NoticeBox(
            icon: Icons.lock_outline,
            text:
                'Al guardar se pide el PIN del titular, una vez para los dos '
                'datos. Los avisos no cambian sus existencias ni impiden '
                'registrar operaciones.',
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const Key('alert-settings-save'),
        onPressed: _changed ? _save : null,
        child: const Text('Guardar'),
      ),
    ],
  );
}

/// Una fila de `inventory_movements` en palabras: tipo con su contraparte,
/// fecha local, persona y cantidad con signo en la unidad mayor.
class _MovementTile extends StatelessWidget {
  const _MovementTile({
    required this.row,
    required this.unit,
    this.personal = false,
    this.titularName,
  });
  final Map<String, Object?> row;
  final String unit;
  final String? titularName;

  /// Modo individual (lámina I-31): «Compra · proveedor» y sin el nombre del
  /// titular en cada fila. Un movimiento de otra persona (historia anterior
  /// al cambio de modo) conserva su nombre.
  final bool personal;

  String get _label {
    final farm = row['farm_name'] ?? 'chaco';
    final other = row['counterpart_name'] ?? 'otra persona';
    final supplier = row['supplier_name'];
    return switch (row['type']) {
      'PURCHASE_IN' when personal && supplier != null => 'Compra · $supplier',
      'PURCHASE_REVERSAL' when personal && supplier != null =>
        'Compra revertida · $supplier',
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

  /// D-07 (RN-35): un pase es una entrega de producto, no una venta ni una
  /// deuda; la fila lo dice para que «Pase a X» no se lea como venta. Su
  /// reversión tampoco toca cuentas.
  String? get _accountNote => switch (row['type']) {
    'TRANSFER_OUT' || 'TRANSFER_IN' => transferNoDebtLabel.toLowerCase(),
    'TRANSFER_REVERSAL_IN' || 'TRANSFER_REVERSAL_OUT' => 'sin deuda',
    _ => null,
  };

  IconData get _icon => switch (row['type']) {
    'PURCHASE_IN' || 'PURCHASE_REVERSAL' => Icons.shopping_cart_outlined,
    'APPLICATION_OUT' || 'APPLICATION_REVERSAL' => Icons.agriculture_outlined,
    _ => Icons.swap_horiz,
  };

  @override
  Widget build(BuildContext context) {
    final quantity = row['quantity_signed'] as int;
    final supplier = row['supplier_name'];
    final note = _accountNote;
    // En propio el proveedor ya va en el título de la compra, y el titular
    // no se repite; el nombre de otra persona (historia) sí se conserva.
    final isPurchase =
        row['type'] == 'PURCHASE_IN' || row['type'] == 'PURCHASE_REVERSAL';
    final ownerIsOther =
        titularName == null || row['owner_name'] != titularName;
    return _onWhite(
      ListTile(
        leading: IconCircle(icon: _icon),
        title: Text(_label),
        subtitle: Text(
          personal
              ? [
                  formatDate(row['movement_date']),
                  if (ownerIsOther) '${row['owner_name']}',
                  if (supplier != null && !isPurchase) '$supplier',
                  ?note,
                ].join(' · ')
              : '${formatDate(row['movement_date'])} · ${row['owner_name']}'
                    '${supplier == null ? '' : ' · $supplier'}'
                    '${note == null ? '' : ' · $note'}',
        ),
        trailing: Text(
          '${quantity < 0 ? '-' : '+'}${formatQuantity(quantity.abs(), unit)}',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: quantity < 0 ? Theme.of(context).colorScheme.error : null,
          ),
        ),
      ),
    );
  }
}

/// Una fila con tinta propia dentro de un grupo blanco (el contenedor con
/// color taparía la tinta del ListTile).
Widget _onWhite(Widget child) =>
    Material(type: MaterialType.transparency, child: child);

/// Campo del diálogo de avisos con su rótulo encima (el lector de pantalla
/// lee el rótulo y después el campo con su ayuda, como las preguntas de
/// Compra).
class _DialogField extends StatelessWidget {
  const _DialogField({required this.label, required this.field});
  final String label;
  final Widget field;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: AgroText.question),
      const SizedBox(height: 6),
      field,
    ],
  );
}

/// Unidad a la derecha del campo, visible también con el campo vacío.
class _UnitSuffix extends StatelessWidget {
  const _UnitSuffix(this.unit);
  final String unit;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 8, right: 14),
    child: Align(
      alignment: Alignment.centerRight,
      widthFactor: 1,
      child: Text(
        unit,
        style: AgroText.value.copyWith(color: AgroColors.muted),
      ),
    ),
  );
}
