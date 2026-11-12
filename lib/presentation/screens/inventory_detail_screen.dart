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
import '../widgets/rdm_b_ui.dart';
import '../widgets/common.dart';
import 'owner_credential_screen.dart' show requestOwnerAuthorization;

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

  /// Se pide una fila más que el límite para saber si queda algo por ver.
  Future<List<Map<String, Object?>>> _loadMovements() => ref
      .read(repositoryProvider)
      .productMovements(widget.productId, limit: movementsLimit + 1);

  void _showMore() => setState(() {
    movementsLimit += _movementsPage;
    movements = _loadMovements();
  });

  /// Lo que antes eran párrafos permanentes: se abren con «i» en la
  /// cabecera, con los mismos textos.
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
              'Neto: no cuenta lo revertido. Comprado neto menos consumido '
              'neto es el físico.',
            ),
            SizedBox(height: 10),
            Text(
              'Previsto en planes: lo que piden los planes pendientes de la '
              'campaña activa. No aparta producto; «Quedarán» es el físico '
              'menos lo previsto y puede ser negativo.',
            ),
            SizedBox(height: 10),
            Text(
              'Asignación neta: lo comprado para esta persona, más lo que '
              'recibió y menos lo que entregó por transferencias. No cuenta lo '
              'revertido. Restando lo consumido queda su físico.',
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
      final unit = h['unit'] as String;
      final physical = h['physical_base'] as int;
      final committed = h['committed_base'] as int;
      // Vencimiento de los lotes con existencia, con el plazo del producto
      // (RN-31): sólo para las etiquetas de la cabecera.
      final today = localDay(DateTime.now());
      final lead =
          data.alertSettings.leadDays ?? AppDatabase.defaultAlertLeadDays;
      final statuses = [
        for (final lot in data.lots)
          if ((lot['available_base'] as int) > 0)
            classifyExpiry(
              expiryDay: lot['expiry_date'] as String?,
              today: today,
              leadDays: lead,
            ),
      ];
      final stock = splitQuantity(physical, unit);
      return RdmScrollPage(
        header: Container(
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
                  Expanded(
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (statuses.contains(ExpiryStatus.expired))
                          const StatusBadge(
                            label: 'Lote vencido',
                            tone: BadgeTone.missing,
                          ),
                        if (statuses.contains(ExpiryStatus.today))
                          const StatusBadge(
                            label: 'Vence hoy',
                            tone: BadgeTone.review,
                          ),
                        if (statuses.contains(ExpiryStatus.near))
                          const StatusBadge(
                            label: 'Por vencer',
                            tone: BadgeTone.review,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleIconButton(
                    key: const Key('inventory-info'),
                    icon: Icons.info_outline,
                    tooltip: 'Qué significan estas cifras',
                    onPressed: _showInfo,
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
                        h['product_name'] as String,
                        style: const TextStyle(
                          fontFamily: AgroFonts.display,
                          fontSize: 20,
                          height: 26 / 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    _Metric(
                      label: 'Físico',
                      value: formatQuantity(physical, unit),
                      big: stock,
                    ),
                    const SizedBox(height: 14),
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: AgroColors.inkSoft,
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 18,
                      runSpacing: 12,
                      children: [
                        _Metric(
                          label: 'Comprado neto',
                          value: formatQuantity(
                            h['purchased_base'] as int,
                            unit,
                          ),
                        ),
                        _Metric(
                          label: 'Consumido neto',
                          value: formatQuantity(
                            h['consumed_base'] as int,
                            unit,
                          ),
                        ),
                        _Metric(
                          label: 'Previsto en planes',
                          value: formatQuantity(committed, unit),
                        ),
                        _Metric(
                          label: 'Quedarán',
                          value: formatQuantity(physical - committed, unit),
                          warn: physical - committed < 0,
                        ),
                        _Metric(
                          label: 'Valor',
                          value: formatBob(h['value_bob_minor'] as int),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text('Quién lo tiene', style: AgroText.h2),
          ),
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
                    subtitle: Text(
                      'Asignación neta ${formatQuantity(row['assigned_base'] as int, unit)} · consumido neto ${formatQuantity(row['consumed_base'] as int, unit)}',
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
          const SizedBox(height: 12),
          _AlertSettingsCard(
            settings: data.alertSettings,
            onConfigure: () => _configureAlerts(data.alertSettings),
            // Sin modalidad conocida se presenta la compartida, la de
            // defecto (operation_mode_controller.dart).
            shared: ref.watch(operationModeProvider) != OperationMode.personal,
          ),
          const SizedBox(height: 18),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              'Movimientos',
              key: Key('inventory-movements-title'),
              style: AgroText.h2,
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
              final hasMore = rows.length > movementsLimit;
              return AgroGroup(
                key: const Key('inventory-movements'),
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
              );
            },
          ),
          const SizedBox(height: 18),
          // Detalle técnico, plegado: lotes vigentes y valor físico.
          Container(
            decoration: BoxDecoration(
              color: AgroColors.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            clipBehavior: Clip.antiAlias,
            child: Theme(
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: _onWhite(
                ExpansionTile(
                  key: const Key('inventory-lots'),
                  title: const Text(
                    'Lotes disponibles y valor físico',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
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
            ),
          ),
        ],
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
    return Container(
      key: const Key('inventory-alert-settings'),
      decoration: BoxDecoration(
        color: AgroColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
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
        children: [
          TextField(
            key: const Key('alert-settings-minimum'),
            controller: minimum,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {
              minimumError = null;
              sameValues = false;
            }),
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
            onChanged: (_) => setState(() {
              daysError = null;
              sameValues = false;
            }),
            decoration: InputDecoration(
              labelText: 'Avisar días antes del vencimiento',
              helperText:
                  'De 0 a ${AgroRepository.maxAlertLeadDays} días. Vacío: '
                  '${AppDatabase.defaultAlertLeadDays} días (valor inicial).',
              helperMaxLines: 3,
              errorText: daysError,
              errorMaxLines: 3,
            ),
          ),
          if (sameValues)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'No hay cambios que guardar: los valores son los mismos.',
                key: const Key('alert-settings-same'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            'Al guardar se pide el PIN del titular, una vez para los dos '
            'datos. Los avisos no cambian sus existencias ni impiden '
            'registrar operaciones.',
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

/// Una cifra de la cabecera del producto con su rótulo. [big] dibuja la
/// existencia grande («10 L»).
class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.big,
    this.warn = false,
  });
  final String label;
  final String value;
  final ({String number, String unit})? big;
  final bool warn;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label: $value',
    excludeSemantics: true,
    child: Column(
      key: Key('metric-$label'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AgroColors.onInkMuted),
        ),
        if (big != null)
          BigFigure(
            number: big!.number,
            unit: big!.unit,
            size: 64,
            color: AgroColors.lime,
          )
        else
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              height: 22 / 15,
              fontWeight: FontWeight.w700,
              color: warn ? const Color(0xFFFFB4AB) : Colors.white,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
      ],
    ),
  );
}

/// Una fila con tinta propia dentro de un grupo blanco (el contenedor con
/// color taparía la tinta del ListTile).
Widget _onWhite(Widget child) =>
    Material(type: MaterialType.transparency, child: child);
