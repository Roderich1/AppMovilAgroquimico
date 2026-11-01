import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../data/app_database.dart';
import '../../domain/campaign_calendar.dart';
import '../../domain/inventory_alerts.dart';
import '../../domain/money.dart';
import '../../domain/operation_mode.dart';
import '../../operation_mode_controller.dart';
import '../widgets/common.dart';

typedef _InventoryDetail = ({
  Map<String, Object?> header,
  List<Map<String, Object?>> distribution,
  List<Map<String, Object?>> lots,
  ProductAlertSettings alertSettings,
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
      alertSettings: await repo.productAlertSettings(widget.productId),
    );
  }

  /// Configura el nivel mínimo y el plazo de aviso (RF-44). Sólo cambia esa
  /// configuración; no toca existencias ni operaciones.
  Future<void> _configureAlerts(ProductAlertSettings current) async {
    final result = await showDialog<({int? minStockBase, int? leadDays})>(
      context: context,
      builder: (_) => AlertSettingsDialog(current: current),
    );
    if (result == null || !mounted) return;
    try {
      await ref
          .read(repositoryProvider)
          .setProductAlertSettings(
            widget.productId,
            minStockBase: result.minStockBase,
            leadDays: result.leadDays,
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
            const SizedBox(height: 12),
            _AlertSettingsCard(
              settings: data.alertSettings,
              onConfigure: () => _configureAlerts(data.alertSettings),
              // Sin modalidad conocida se presenta la compartida, la de
              // defecto (operation_mode_controller.dart).
              shared:
                  ref.watch(operationModeProvider) != OperationMode.personal,
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
              'Lo que explica el saldo: compras, aplicaciones, pases '
              '(entregas sin deuda) y reversiones, del más reciente al más '
              'antiguo.',
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
                        '${lot['supplier_name']} · ${lot['campaign_name']} · '
                        '${lotExpiryText(lot['expiry_date'] as String?)}',
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Lote #${lot['lot_id']} · '
                              '${lot['lot_number'] == null ? 'sin número de lote' : 'número de lote ${lot['lot_number']}'} · '
                              'costo ${formatBob(lot['unit_cost'] as int)}/$unit · origen ${lot['parent_lot_id'] == null ? 'compra' : 'transferencia del lote #${lot['parent_lot_id']}'}',
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

/// Vencimiento de un lote en palabras; sin fecha no se supone ninguna.
String lotExpiryText(String? expiryDay) => expiryDay == null
    ? 'sin fecha de vencimiento registrada'
    : 'vence el ${displayDay(expiryDay)}';

String _leadText(int? leadDays) =>
    '${leadDaysText(leadDays ?? AppDatabase.defaultAlertLeadDays)}'
    '${leadDays == null ? ' (valor inicial)' : ''}';

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
    return Card(
      key: const Key('inventory-alert-settings'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Avisos de este producto',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              min == null
                  ? 'Sin nivel mínimo: no se avisa cuando queda poco.'
                  : 'Nivel mínimo: ${formatQuantity(min, settings.unit)}. '
                        '${shared ? 'Se avisa cuando el total de la '
                                  'instalación, o lo de un responsable, '
                                  'queda en esa cantidad o menos.' : 'Se avisa cuando queda esa cantidad o menos.'}',
            ),
            Text('Aviso de vencimiento: ${_leadText(settings.leadDays)}.'),
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
/// nivel» o «valor inicial», nunca cero.
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
  }

  @override
  void dispose() {
    minimum.dispose();
    days.dispose();
    super.dispose();
  }

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
      final parsed = int.tryParse(days.text.trim());
      if (parsed == null || parsed < 0 || parsed > 365) {
        dayError = 'Escriba un número entero de días, de 0 a 365.';
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
    Navigator.pop(context, (minStockBase: minBase, leadDays: leadDays));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Avisos de ${widget.current.productName}'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('alert-settings-minimum'),
            controller: minimum,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() => minimumError = null),
            decoration: InputDecoration(
              labelText: 'Nivel mínimo (${widget.current.unit})',
              helperText:
                  'Vacío: sin aviso de existencia baja. 0: avisa sólo '
                  'cuando se acaba.',
              helperMaxLines: 3,
              errorText: minimumError,
              errorMaxLines: 4,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('alert-settings-days'),
            controller: days,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() => daysError = null),
            decoration: InputDecoration(
              labelText: 'Avisar días antes del vencimiento',
              helperText:
                  'Vacío: ${AppDatabase.defaultAlertLeadDays} días (valor '
                  'inicial).',
              helperMaxLines: 3,
              errorText: daysError,
              errorMaxLines: 3,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Los avisos no cambian sus existencias ni impiden registrar '
            'operaciones.',
            style: Theme.of(context).textTheme.bodySmall,
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
        onPressed: _save,
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
    return ListTile(
      leading: Icon(_icon),
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
