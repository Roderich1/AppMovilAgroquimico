import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app.dart';
import '../../data/agro_repository.dart' show PurchaseDetailRead;
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
/// (pagar, revertir) siguen en el menú de la tarjeta.
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
            _ItemsCard(detail: detail),
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
  const _ItemsCard({required this.detail});

  final PurchaseDetailRead detail;

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
        ],
      ],
    );
  }
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
