import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../data/agro_repository.dart' show AgroRepository;
import '../../data/app_database.dart';
import '../../domain/campaign_calendar.dart';
import '../../domain/inventory_alerts.dart';
import '../../domain/money.dart';
import '../../domain/operation_mode.dart';
import '../../operation_mode_controller.dart';
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
  List<Map<String, Object?>> lots,
  ProductAlertSettings alertSettings,
});

/// Movimientos más recientes que se ven en el detalle; el resto, en el
/// historial completo.
const _recentMovements = 5;

/// Cuántos movimientos muestra el historial de entrada y cuántos más por
/// «Ver más».
const _movementsPage = 20;

/// Detalle de un producto (ronda 2 del rediseño, 2026-11-12), en el orden que
/// pidió el autor:
///
/// 1. cuánto hay ahora y qué parte vence (con su cantidad);
/// 2. quién lo tiene;
/// 3. lo previsto en planes, sólo si hay planes pendientes que lo piden;
/// 4. los movimientos recientes y el acceso al historial completo (que
///    explica el saldo: tarea T3 del piloto, E-10);
/// 5. «Más datos»: lotes, cifras netas y valor, y avisos del producto.
///
/// Las cifras y cálculos son los de antes (`inventoryProductHeader`,
/// `inventoryProductDistribution`, `inventoryProductLots`); sólo cambia la
/// presentación. Las lecturas se hacen una vez al abrir (B-15).
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
      alertSettings: await repo.productAlertSettings(widget.productId),
    );
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
        ? '${AppDatabase.defaultAlertLeadDays} días (valor inicial)'
        : (v == 1 ? '1 día' : '$v días');
    final authorization = await requestOwnerAuthorization(
      context,
      ref,
      purpose: AuthorizationPurpose.configureProductAlerts,
      subjectRef: AgroRepository.productAlertsSubjectRef(widget.productId),
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

  /// Se pide una fila más que las que se muestran para saber si hay más.
  Future<List<Map<String, Object?>>> _loadMovements() => ref
      .read(repositoryProvider)
      .productMovements(widget.productId, limit: _recentMovements + 1);

  /// El historial completo, en su propia vista (el detalle sólo muestra los
  /// más recientes).
  Future<void> _openHistory(String productName, String unit) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => _MovementsHistoryPage(
            productId: widget.productId,
            productName: productName,
            unit: unit,
          ),
        ),
      );

  /// Lo que significan las cifras: se abre con «i» en la cabecera, sin
  /// párrafos permanentes. Los términos técnicos («neto», «asignación neta»)
  /// se explican aquí.
  Future<void> _showInfo() => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('inventory-info-dialog'),
      title: const Text('Qué significan estas cifras'),
      content: const SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cuánto hay, de qué compras viene y en qué se usó. El '
              'inventario continúa entre campañas.',
            ),
            SizedBox(height: 10),
            Text(
              'Hay ahora: lo que queda entre todas las personas (en el '
              'cálculo, el físico). Los vencimientos dicen qué cantidad '
              'vence y cuándo, según la fecha de cada lote.',
            ),
            SizedBox(height: 10),
            Text(
              'Neto: no cuenta lo revertido. Comprado neto menos consumido '
              'neto es lo que hay ahora.',
            ),
            SizedBox(height: 10),
            Text(
              'Previsto en planes: lo que piden los planes pendientes de la '
              'campaña activa. No aparta producto: «Quedarían» es lo que hay '
              'ahora menos lo previsto, una proyección por si se aplican los '
              'planes. Si es negativo, faltaría producto.',
            ),
            SizedBox(height: 10),
            Text(
              'Asignación neta: lo comprado para esta persona, más lo que '
              'recibió y menos lo que entregó por transferencias. No cuenta lo '
              'revertido. Restando lo consumido queda lo que tiene. En «Quién '
              'lo tiene», «Usó 1 L de 3 L» es su consumido neto de su '
              'asignación neta.',
            ),
            SizedBox(height: 10),
            Text(
              'Valor a costo de compra: lo que hay ahora, valorado al costo '
              'de cada lote. No es una deuda ni un saldo.',
            ),
            SizedBox(height: 10),
            Text(
              'Lo que explica el saldo: compras, aplicaciones, pases '
              '(entregas sin deuda) y reversiones, del más reciente al más '
              'antiguo.',
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
      final productName = h['product_name'] as String;
      final unit = h['unit'] as String;
      final physical = h['physical_base'] as int;
      final committed = h['committed_base'] as int;
      // Vencimiento de los lotes con existencia, con el plazo del producto
      // (RN-31), agrupado por fecha con su cantidad.
      final today = localDay(DateTime.now());
      final lead =
          data.alertSettings.leadDays ?? AppDatabase.defaultAlertLeadDays;
      final portions = expiryPortions(
        lots: [
          for (final lot in data.lots)
            (
              availableBase: lot['available_base'] as int,
              expiryDay: lot['expiry_date'] as String?,
            ),
        ],
        today: today,
        leadDays: lead,
      );
      return RdmScrollPage(
        header: _Header(
          productName: productName,
          physical: physical,
          unit: unit,
          portions: portions,
          leadDays: lead,
          onInfo: _showInfo,
        ),
        children: [
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
                    // Consumido neto de su asignación neta (los términos, en
                    // «i»).
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
          // Sólo cuando hay planes pendientes que piden este producto.
          if (committed != 0) ...[
            const SizedBox(height: 18),
            _PlansCard(physical: physical, committed: committed, unit: unit),
          ],
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Semantics(
              header: true,
              child: const Text(
                'Movimientos recientes',
                key: Key('inventory-movements-title'),
                style: AgroText.h2,
              ),
            ),
          ),
          FutureBuilder<List<Map<String, Object?>>>(
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
                return const EmptyState(
                  icon: Icons.history_outlined,
                  message: 'Todavía no hay movimientos de este producto.',
                );
              }
              final hasMore = rows.length > _recentMovements;
              return AgroGroup(
                key: const Key('inventory-movements'),
                children: [
                  for (final row in rows.take(_recentMovements))
                    _MovementTile(row: row, unit: unit),
                  if (hasMore)
                    _onWhite(
                      TextButton.icon(
                        key: const Key('inventory-movements-all'),
                        onPressed: () => _openHistory(productName, unit),
                        icon: const Icon(Icons.history),
                        label: const Text('Ver todo el historial'),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 22),
          const GroupLabel('Más datos'),
          _LotsPanel(lots: data.lots, unit: unit, today: today, lead: lead),
          const SizedBox(height: 12),
          AgroGroup(
            key: const Key('inventory-totals'),
            children: [
              _FigureRow(
                label: 'Comprado neto',
                hint: 'Sin compras revertidas',
                value: formatQuantity(h['purchased_base'] as int, unit),
              ),
              _FigureRow(
                label: 'Consumido neto',
                hint: 'En aplicaciones, sin las revertidas',
                value: formatQuantity(h['consumed_base'] as int, unit),
              ),
              _FigureRow(
                label: 'Valor a costo de compra',
                hint: 'De lo que hay ahora. No es una deuda.',
                value: formatBob(h['value_bob_minor'] as int),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _AlertSettingsCard(
            settings: data.alertSettings,
            onConfigure: () => _configureAlerts(data.alertSettings),
            // Sin modalidad conocida se presenta la compartida, la de
            // defecto (operation_mode_controller.dart).
            shared: ref.watch(operationModeProvider) != OperationMode.personal,
          ),
        ],
      );
    },
  );
}

String _leadText(int? leadDays) =>
    '${leadDaysText(leadDays ?? AppDatabase.defaultAlertLeadDays)}'
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
  });

  final String productName;
  final int physical;
  final String unit;
  final List<ExpiryPortion> portions;
  final int leadDays;
  final VoidCallback onInfo;

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
              'ver Lotes, en «Más datos»',
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
                  label: 'Hay ahora: ${formatQuantity(physical, unit)}',
                  excludeSemantics: true,
                  child: Column(
                    key: const Key('metric-Hay ahora'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Hay ahora',
                        style: TextStyle(
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

/// Lotes con existencia, plegados: cada uno como tarjeta legible, sin el
/// identificador interno; el número del fabricante sólo si existe.
class _LotsPanel extends StatelessWidget {
  const _LotsPanel({
    required this.lots,
    required this.unit,
    required this.today,
    required this.lead,
  });

  final List<Map<String, Object?>> lots;
  final String unit;
  final String today;
  final int lead;

  String _expiryText(ExpiryStatus status, String? day) => switch (status) {
    ExpiryStatus.expired => 'Venció el ${displayDay(day!)}',
    ExpiryStatus.today => 'Vence hoy',
    ExpiryStatus.near => 'Vence el ${displayDay(day!)} · por vencer',
    ExpiryStatus.later => 'Vence el ${displayDay(day!)}',
    ExpiryStatus.unknown => 'Sin fecha de vencimiento registrada',
  };

  @override
  Widget build(BuildContext context) {
    final references = lotReferences([
      for (final lot in lots)
        (
          person: lot['owner_name'] as String,
          acquiredDay: storedLocalDay(lot['acquired_date'] as String),
        ),
    ]);
    final count = lots.length;
    return Container(
      decoration: BoxDecoration(
        color: AgroColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: _onWhite(
          ExpansionTile(
            key: const Key('inventory-lots'),
            title: const Text(
              'Lotes',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AgroColors.ink,
              ),
            ),
            subtitle: Text(
              count == 1
                  ? '1 lote con existencia'
                  : '$count lotes con existencia',
              style: AgroText.detail,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [
              for (final (i, lot) in lots.indexed) ...[
                if (i > 0) const SizedBox(height: 8),
                Builder(
                  builder: (context) {
                    final expiry = lot['expiry_date'] as String?;
                    final status = classifyExpiry(
                      expiryDay: expiry,
                      today: today,
                      leadDays: lead,
                    );
                    return LotCard(
                      key: Key('inventory-lot-$i'),
                      person: lot['owner_name'] as String,
                      quantity: formatQuantity(
                        lot['available_base'] as int,
                        unit,
                      ),
                      purchaseDay: formatDate(lot['acquired_date']),
                      expiryStatus: status,
                      expiryText: _expiryText(status, expiry),
                      details: [
                        'Costo ${lotCostText(lot['unit_cost'] as int, unit)}',
                        '${lot['supplier_name']} · ${lot['campaign_name']}',
                      ],
                      manufacturerLot: lot['lot_number'] as String?,
                      reference: references[i],
                      fromTransfer: lot['parent_lot_id'] != null,
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Historial completo de movimientos del producto, del más reciente al más
/// antiguo, por páginas («Ver más»). Sólo lee.
class _MovementsHistoryPage extends ConsumerStatefulWidget {
  const _MovementsHistoryPage({
    required this.productId,
    required this.productName,
    required this.unit,
  });

  final int productId;
  final String productName;
  final String unit;

  @override
  ConsumerState<_MovementsHistoryPage> createState() =>
      _MovementsHistoryPageState();
}

class _MovementsHistoryPageState extends ConsumerState<_MovementsHistoryPage> {
  int limit = _movementsPage;
  late Future<List<Map<String, Object?>>> movements = _load();

  /// Se pide una fila más que el límite para saber si queda algo por ver.
  Future<List<Map<String, Object?>>> _load() => ref
      .read(repositoryProvider)
      .productMovements(widget.productId, limit: limit + 1);

  void _showMore() => setState(() {
    limit += _movementsPage;
    movements = _load();
  });

  @override
  Widget build(BuildContext context) => Material(
    color: AgroColors.canvas,
    child: SafeArea(
      bottom: false,
      child: FutureBuilder<List<Map<String, Object?>>>(
        future: movements,
        builder: (context, snapshot) => RdmScrollPage(
          children: [
            ScreenTitleBar(
              title: 'Movimientos',
              subtitle: widget.productName,
              compact: true,
              leading: const RdmBackButton(),
            ),
            const SizedBox(height: 8),
            if (snapshot.hasError)
              EmptyState(
                icon: Icons.error_outline,
                message: friendlyError(snapshot.error!),
              )
            else if (!snapshot.hasData)
              const Center(child: CircularProgressIndicator())
            else
              AgroGroup(
                key: const Key('inventory-history'),
                children: [
                  for (final row in snapshot.data!.take(limit))
                    _MovementTile(row: row, unit: widget.unit),
                  if (snapshot.data!.length > limit)
                    _onWhite(
                      TextButton.icon(
                        key: const Key('inventory-history-more'),
                        onPressed: _showMore,
                        icon: const Icon(Icons.expand_more),
                        label: const Text('Ver más'),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    ),
  );
}

/// Configuración de avisos del producto (RF-44), visible para el titular.
class _AlertSettingsCard extends StatelessWidget {
  const _AlertSettingsCard({
    required this.settings,
    required this.onConfigure,
    required this.shared,
  });
  final ProductAlertSettings settings;
  final VoidCallback onConfigure;

  /// Modalidad compartida: el nivel se compara con el total y con cada
  /// responsable.
  final bool shared;

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
                        : 'Nivel mínimo: ${formatQuantity(min, settings.unit)}. '
                              '${shared ? 'Se avisa cuando el total de la '
                                        'instalación, o lo de un responsable, '
                                        'queda en esa cantidad o menos.' : 'Se avisa cuando queda esa cantidad o menos.'}',
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
      if (parsed == null ||
          parsed < 0 ||
          parsed > AgroRepository.maxAlertLeadDays) {
        dayError =
            'Escriba un número entero de días, de 0 a '
            '${AgroRepository.maxAlertLeadDays}.';
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
                    'De 0 a ${AgroRepository.maxAlertLeadDays} días. Vacío: '
                    '${AppDatabase.defaultAlertLeadDays} días (valor inicial).',
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
    return _onWhite(
      ListTile(
        leading: IconCircle(icon: _icon),
        title: Text(_label),
        subtitle: Text(
          '${formatDate(row['movement_date'])} · ${row['owner_name']}'
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
