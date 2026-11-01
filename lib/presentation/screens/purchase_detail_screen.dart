import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app.dart';
import '../../data/agro_repository.dart' show PurchaseDetailRead;
import '../../domain/campaign_calendar.dart';
import '../../domain/inventory_alerts.dart' show expiryPickerRange;
import '../../domain/labels.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../widgets/common.dart';
import '../widgets/owner_reversal_flow.dart';

/// Detalle de una compra, de sólo lectura (bloque de experiencia 2026-10-30,
/// A2). Se llega tocando la tarjeta en Compras, también si está revertida.
///
/// Muestra únicamente lo guardado: cabecera, líneas con su precio original,
/// a quién se asignó cada cantidad, pagos al proveedor (con los revertidos) y,
/// si se revirtió, quién lo autorizó y por qué. Un campo vacío no se rellena
/// con un valor supuesto: se omite. Consultar no escribe nada; las acciones
/// (pagar, revertir) siguen en el menú de la tarjeta. La única acción aquí
/// es corregir el vencimiento o el número de lote de una línea (F04-AV,
/// RF-42), que no toca cantidades ni movimientos.
class PurchaseDetailScreen extends ConsumerStatefulWidget {
  const PurchaseDetailScreen({super.key, required this.purchaseId});

  final int purchaseId;

  @override
  ConsumerState<PurchaseDetailScreen> createState() =>
      _PurchaseDetailScreenState();
}

class _PurchaseDetailScreenState extends ConsumerState<PurchaseDetailScreen> {
  // Una lectura al abrir (y otra sólo si cambia la compra): reconstruir la
  // pantalla no vuelve a consultar.
  late Future<PurchaseDetailRead?> data;

  @override
  void initState() {
    super.initState();
    data = ref.read(repositoryProvider).purchaseDetail(widget.purchaseId);
  }

  @override
  void didUpdateWidget(PurchaseDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.purchaseId != widget.purchaseId) {
      data = ref.read(repositoryProvider).purchaseDetail(widget.purchaseId);
    }
  }

  Future<void> _correctLotData(Map<String, Object?> item) async {
    final result = await showDialog<_LotDataCorrection>(
      context: context,
      builder: (_) => _LotDataDialog(item: item),
    );
    if (result == null || !mounted) return;
    try {
      await ref
          .read(repositoryProvider)
          .correctLotData(
            item['id']! as int,
            expiryDay: result.expiryDay,
            lotNumber: result.lotNumber,
            reason: result.reason,
          );
      if (!mounted) return;
      showSuccess(
        context,
        'Se guardó la corrección. Las cantidades no cambiaron.',
      );
      setState(() {
        data = ref.read(repositoryProvider).purchaseDetail(widget.purchaseId);
      });
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  /// Historial de correcciones de una línea: se lee sólo al pedirlo.
  Future<void> _showCorrections(Map<String, Object?> item) async {
    final List<Map<String, Object?>> rows;
    try {
      rows = await ref
          .read(repositoryProvider)
          .lotDataCorrections(item['id']! as int);
    } catch (error) {
      if (mounted) showError(context, error);
      return;
    }
    if (!mounted) return;
    String value(Object? v, String empty) => v == null ? empty : v.toString();
    String day(Object? v) => v == null ? 'sin fecha' : displayDay(v as String);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Correcciones de ${item['product_name']}'),
        content: SingleChildScrollView(
          child: Column(
            key: const Key('lot-data-corrections'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    '${formatDate(row['recorded_at'])}: vencimiento '
                    '${day(row['previous_expiry_date'])} → '
                    '${day(row['new_expiry_date'])}; lote '
                    '${value(row['previous_lot_number'], 'sin número')} → '
                    '${value(row['new_lot_number'], 'sin número')}'
                    '${row['reason'] == null ? '' : '. Motivo: ${row['reason']}'}',
                  ),
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
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Detalle de compra',
    child: FutureBuilder<PurchaseDetailRead?>(
      future: data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            message: friendlyError(snapshot.error!),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final detail = snapshot.data;
        if (detail == null) {
          return const Card(
            child: EmptyState(
              icon: Icons.receipt_long_outlined,
              message: 'Esta compra ya no está en el teléfono.',
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HeaderCard(detail: detail),
            const SizedBox(height: 12),
            _ItemsCard(
              detail: detail,
              onCorrectLotData: _correctLotData,
              onShowCorrections: _showCorrections,
            ),
            const SizedBox(height: 12),
            _PaymentsCard(payments: detail.payments),
          ],
        );
      },
    ),
  );
}

/// Ver la foto de la factura guardada con la compra (sólo lectura).
Future<void> showInvoiceImage(BuildContext context, String path) async {
  final file = File(path);
  if (!await file.exists()) {
    if (context.mounted) {
      showError(
        context,
        'La imagen de factura ya no está disponible en este dispositivo.',
      );
    }
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Factura'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 700),
        child: InteractiveViewer(child: Image.file(file, fit: BoxFit.contain)),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );
}

/// Fila «etiqueta: valor» que parte la línea cuando no cabe, sin recortar.
class _Field extends StatelessWidget {
  const _Field(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    ),
  );
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.detail});

  final PurchaseDetailRead detail;

  @override
  Widget build(BuildContext context) {
    final p = detail.purchase;
    final reversed = p['status'] == 'REVERSED';
    final paid = [
      for (final row in detail.payments)
        if (row['reversed_at'] == null) row['amount_bob_minor']! as int,
    ].fold<int>(0, (sum, amount) => sum + amount);
    final invoice = p['invoice_number'] as String?;
    final notes = p['notes'] as String?;
    final image = p['invoice_image_path'] as String?;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              p['supplier_name']! as String,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Chip(
              key: const Key('purchase-detail-status'),
              avatar: Icon(
                reversed ? Icons.undo : Icons.check_circle_outline,
                size: 18,
              ),
              label: Text(operationStatusLabel(p['status'])),
            ),
            const SizedBox(height: 8),
            _Field(
              'Factura',
              invoice == null || invoice.isEmpty ? 'Sin número' : invoice,
            ),
            _Field('Fecha de compra', formatDate(p['purchase_date'])),
            _Field('Campaña', p['campaign_name']! as String),
            _Field('Total', formatBob(p['total_bob_minor']! as int)),
            _Field(
              reversed ? 'Pagado y no revertido' : 'Pagado al proveedor',
              formatBob(paid),
            ),
            if (p['exchange_rate_source'] != null)
              _Field(
                'Origen del tipo de cambio',
                exchangeRateSourceLabel(p['exchange_rate_source']),
              ),
            if ((p['exchange_rate_note'] as String?)?.isNotEmpty ?? false)
              _Field(
                'Nota del tipo de cambio',
                p['exchange_rate_note']! as String,
              ),
            if (notes != null && notes.isNotEmpty) _Field('Notas', notes),
            if (reversed) ...[
              if (p['reversed_at'] != null)
                _Field('Revertida el', formatDate(p['reversed_at'])),
              // Auditoría completa (RF-13): quién autorizó, cómo y el motivo.
              ReversalActorText(
                operationType: 'PURCHASE',
                operationId: p['id']! as int,
              ),
            ],
            if (image != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => showInvoiceImage(context, image),
                icon: const Icon(Icons.image_outlined),
                label: const Text('Ver foto de la factura'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ItemsCard extends StatelessWidget {
  const _ItemsCard({
    required this.detail,
    required this.onCorrectLotData,
    required this.onShowCorrections,
  });

  final PurchaseDetailRead detail;
  final void Function(Map<String, Object?> item) onCorrectLotData;
  final void Function(Map<String, Object?> item) onShowCorrections;

  @override
  Widget build(BuildContext context) {
    final items = detail.items;
    return _Section(
      title: items.length == 1 ? '1 producto' : '${items.length} productos',
      children: [
        for (final (index, item) in items.indexed) ...[
          if (index > 0) const Divider(height: 24),
          Text(
            '${item['product_name']} · '
            '${formatQuantity(item['quantity_base']! as int, item['unit']! as String)}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          _Field('Precio', unitPriceText(item)),
          _Field('Subtotal', formatBob(item['subtotal_bob_minor']! as int)),
          for (final allocation in detail.allocations)
            if (allocation['purchase_item_id'] == item['id'])
              _Field(
                'Para ${allocation['person_name']}',
                allocationText(allocation, item['unit']! as String),
              ),
          // F04-AV: datos opcionales del lote; sin dato no se supone nada.
          _Field(
            'Vencimiento',
            item['expiry_date'] == null
                ? 'sin fecha registrada'
                : displayDay(item['expiry_date']! as String),
          ),
          _Field(
            'Número de lote',
            (item['lot_number'] as String?) ?? 'sin registrar',
          ),
          if (((item['lot_data_corrections'] as int?) ?? 0) > 0)
            _Field(
              'Correcciones',
              '${item['lot_data_corrections']} (las cantidades no cambiaron)',
            ),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                key: Key('purchase-lot-data-correct-${item['id']}'),
                onPressed: () => onCorrectLotData(item),
                icon: const Icon(Icons.edit_calendar_outlined),
                label: const Text('Corregir vencimiento o lote'),
              ),
              if (((item['lot_data_corrections'] as int?) ?? 0) > 0)
                TextButton.icon(
                  key: Key('purchase-lot-data-history-${item['id']}'),
                  onPressed: () => onShowCorrections(item),
                  icon: const Icon(Icons.history),
                  label: const Text('Ver correcciones'),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

typedef _LotDataCorrection = ({
  String? expiryDay,
  String? lotNumber,
  String? reason,
});

/// Corregir el vencimiento y el número de lote de una línea (RF-42). Cambia
/// esos datos en todos sus lotes, también los transferidos, y queda
/// registrado con los valores anteriores.
class _LotDataDialog extends StatefulWidget {
  const _LotDataDialog({required this.item});
  final Map<String, Object?> item;

  @override
  State<_LotDataDialog> createState() => _LotDataDialogState();
}

class _LotDataDialogState extends State<_LotDataDialog> {
  late String? expiryDay = widget.item['expiry_date'] as String?;
  late final lotNumber = TextEditingController(
    text: (widget.item['lot_number'] as String?) ?? '',
  );
  final reason = TextEditingController();

  @override
  void dispose() {
    lotNumber.dispose();
    reason.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final range = expiryPickerRange(
      expiryDay == null ? null : startOfLocalDay(expiryDay!),
      now,
    );
    final picked = await showDatePicker(
      context: context,
      initialDate: range.initial,
      firstDate: range.first,
      lastDate: range.last,
      helpText: 'Fecha de vencimiento',
    );
    if (picked != null && mounted) {
      setState(() => expiryDay = localDay(picked));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Vencimiento y lote de ${widget.item['product_name']}'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('lot-data-expiry'),
                  onPressed: _pick,
                  icon: const Icon(Icons.event_outlined),
                  label: Text(
                    expiryDay == null
                        ? 'Sin fecha registrada'
                        : 'Vence el ${displayDay(expiryDay!)}',
                  ),
                ),
              ),
              if (expiryDay != null)
                IconButton(
                  key: const Key('lot-data-expiry-clear'),
                  tooltip: 'Dejar sin fecha',
                  onPressed: () => setState(() => expiryDay = null),
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('lot-data-number'),
            controller: lotNumber,
            maxLength: 40,
            decoration: const InputDecoration(
              labelText: 'Número de lote (opcional)',
            ),
          ),
          TextField(
            key: const Key('lot-data-reason'),
            controller: reason,
            decoration: const InputDecoration(labelText: 'Motivo (opcional)'),
          ),
          const SizedBox(height: 12),
          Text(
            'Se corrige en todos los lotes de esta línea, también los '
            'entregados a otras personas. Las cantidades y los movimientos '
            'no cambian, y la corrección queda registrada.',
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
        key: const Key('lot-data-save'),
        onPressed: () {
          final number = lotNumber.text.trim();
          final why = reason.text.trim();
          Navigator.pop<_LotDataCorrection>(context, (
            expiryDay: expiryDay,
            lotNumber: number.isEmpty ? null : number,
            reason: why.isEmpty ? null : why,
          ));
        },
        child: const Text('Guardar corrección'),
      ),
    ],
  );
}

class _PaymentsCard extends StatelessWidget {
  const _PaymentsCard({required this.payments});

  final List<Map<String, Object?>> payments;

  @override
  Widget build(BuildContext context) => _Section(
    title: 'Pagos al proveedor',
    children: [
      if (payments.isEmpty) const Text('No hay pagos registrados.'),
      for (final payment in payments)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            paymentText(payment),
            style: payment['reversed_at'] == null
                ? null
                : TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ),
    ],
  );
}

/// «45,00 Bs por L», o en dólares «6,50 US$ por L · tipo de cambio 6,96 =
/// 45,24 Bs por L». Son los valores guardados en la línea, no recalculados.
String unitPriceText(Map<String, Object?> item) {
  final unit = item['unit']! as String;
  final bob =
      '${formatBob(item['converted_unit_price_bob_minor']! as int).trim()} '
      'por $unit';
  if (item['currency_code'] != CurrencyCode.usd.code) return bob;
  final original = formatUsd(item['original_unit_price_minor']! as int);
  final rate = item['exchange_rate_scaled'] as int?;
  final rateText = rate == null
      ? ''
      : ' · tipo de cambio '
            '${NumberFormat('#,##0.####', 'es_BO').format(rate / fxScale)}';
  return '$original por $unit$rateText = $bob';
}

/// Cantidad asignada y cómo se cobra, según la política que quedó guardada
/// con la asignación (`charge_policy_snapshot`).
String allocationText(Map<String, Object?> allocation, String unit) {
  final quantity = formatQuantity(allocation['quantity_base']! as int, unit);
  final charge = allocation['amount_bob_minor_if_allocation_charge'] as int?;
  final how = charge != null
      ? 'cargo por compra ${formatBob(charge)}'
      : switch (allocation['charge_policy_snapshot']) {
          'BY_ACTUAL_USAGE' => 'se cobra al aplicar',
          'MANUAL' => 'sin cobro automático',
          'BY_PURCHASE_ALLOCATION' => 'cobro por compra',
          final other => '$other',
        };
  return '$quantity · $how';
}

/// «05/01/2026 · Efectivo · pagó Titular · 180,00 Bs», y si se revirtió,
/// «(revertido el …)».
String paymentText(Map<String, Object?> payment) {
  final method =
      PaymentMethod.fromCode('${payment['method']}')?.label ??
      '${payment['method']}';
  final reversedAt = payment['reversed_at'];
  return '${formatDate(payment['payment_date'])} · $method · '
      'pagó ${payment['payer_name']} · '
      '${formatBob(payment['amount_bob_minor']! as int).trim()}'
      '${reversedAt == null ? '' : ' (revertido el ${formatDate(reversedAt)})'}';
}
