import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app.dart';
import '../../data/agro_repository.dart'
    show AgroRepository, PurchaseDetailRead;
import '../../domain/campaign_calendar.dart';
import '../../domain/inventory_alerts.dart' show expiryPickerRange;
import '../../domain/labels.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../theme/agro_theme.dart';
import '../widgets/agro_ui.dart';
import '../widgets/common.dart';
import '../widgets/rdm_b_purchase_actions.dart';
import '../widgets/rdm_b_ui.dart';
import '../widgets/owner_reversal_flow.dart';
import 'purchase_form_screen.dart' show lotNumberCounter;
import '../../services/auth/local_owner_credential.dart'
    show AuthorizationPurpose;

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

  /// Corregir después del registro (decisión del autor del 2026-11-01):
  /// primero los datos nuevos, después el motivo y el PIN del titular. El
  /// repositorio vuelve a comprobar todo en su transacción.
  Future<void> _correctLotData(Map<String, Object?> item) async {
    final itemId = item['id']! as int;
    final result = await showDialog<_LotDataCorrection>(
      context: context,
      builder: (_) => _LotDataDialog(item: item),
    );
    if (result == null || !mounted) return;
    final repo = ref.read(repositoryProvider);
    String day(String? v) => v == null ? 'sin fecha' : displayDay(v);
    String lot(String? v) => v ?? 'sin número';
    final approval = await requestOwnerApproval(
      context,
      ref,
      purpose: AuthorizationPurpose.correctLotData,
      subjectRef: AgroRepository.lotDataSubjectRef(itemId),
      title: 'Corregir vencimiento o lote',
      effects:
          'Vencimiento: ${day(item['expiry_date'] as String?)} → '
          '${day(result.expiryDay)}. Número de lote: '
          '${lot(item['lot_number'] as String?)} → ${lot(result.lotNumber)}. '
          'Cambia en los lotes de esta compra y en los entregados desde '
          'ellos cuando su procedencia está demostrada. Las cantidades y los '
          'movimientos no cambian.',
      revalidate: () async => await repo.canCorrectLotData(itemId)
          ? null
          : 'ya no se puede corregir',
    );
    if (approval == null || !mounted) return;
    try {
      final done = await repo.correctLotData(
        itemId,
        expiryDay: result.expiryDay,
        lotNumber: result.lotNumber,
        reason: approval.reason,
        authorization: approval.authorization,
      );
      if (!mounted) return;
      showSuccess(
        context,
        'Se guardó la corrección en '
        '${done.correctedLots == 1 ? '1 lote' : '${done.correctedLots} lotes'}. '
        'Las cantidades no cambiaron.'
        '${done.unprovenLots == 0 ? '' : ' ${done.unprovenLots == 1 ? '1 lote' : '${done.unprovenLots} lotes'} de esta línea no se '
                  'cambiaron porque no se pudo demostrar su procedencia.'}',
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
                    '${value(row['new_lot_number'], 'sin número')}. '
                    'Motivo: ${row['reason']}. Autorizó ${row['actor_name']} '
                    'con PIN; ${row['lot_count']} '
                    '${row['lot_count'] == 1 ? 'lote cambiado' : 'lotes cambiados'}'
                    '${(row['unproven_lot_count'] as int? ?? 0) == 0 ? '' : ', ${row['unproven_lot_count']} sin procedencia demostrada'}.',
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

  void _reload() {
    setState(() {
      data = ref.read(repositoryProvider).purchaseDetail(widget.purchaseId);
    });
  }

  /// Pagado al proveedor y no revertido (lo mismo que se mostraba antes).
  static int _paid(PurchaseDetailRead detail) => [
    for (final row in detail.payments)
      if (row['reversed_at'] == null) row['amount_bob_minor']! as int,
  ].fold<int>(0, (sum, amount) => sum + amount);

  PurchaseActionTarget _target(PurchaseDetailRead detail) => (
    id: detail.purchase['id']! as int,
    supplierName: '${detail.purchase['supplier_name']}',
    invoiceNumber: detail.purchase['invoice_number'] as String?,
    totalMinor: detail.purchase['total_bob_minor']! as int,
    paidMinor: _paid(detail),
  );

  Future<void> _pay(PurchaseDetailRead detail) async {
    if (await payPurchaseProvider(context, ref, _target(detail)) && mounted) {
      _reload();
      showSuccess(context, 'Pago al proveedor registrado.');
    }
  }

  Future<void> _reverse(PurchaseDetailRead detail) async {
    if (await reversePurchaseWithApproval(context, ref, _target(detail)) &&
        mounted) {
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<PurchaseDetailRead?>(
    future: data,
    builder: (context, snapshot) {
      Widget plain(Widget child) => RdmScrollPage(
        children: [
          const ScreenTitleBar(
            title: 'Detalle de compra',
            leading: RdmBackButton(),
          ),
          const SizedBox(height: 12),
          child,
        ],
      );
      if (snapshot.hasError) {
        return plain(
          EmptyState(
            icon: Icons.error_outline,
            message: friendlyError(snapshot.error!),
          ),
        );
      }
      if (snapshot.connectionState != ConnectionState.done) {
        return plain(const Center(child: CircularProgressIndicator()));
      }
      final detail = snapshot.data;
      if (detail == null) {
        return plain(
          const EmptyState(
            icon: Icons.receipt_long_outlined,
            message: 'Esta compra ya no está en el teléfono.',
          ),
        );
      }
      return RdmScrollPage(
        header: _DetailHero(
          detail: detail,
          paid: _paid(detail),
          onPay: () => _pay(detail),
          onReverse: () => _reverse(detail),
        ),
        children: [
          _ItemsCard(
            detail: detail,
            onCorrectLotData: _correctLotData,
            onShowCorrections: _showCorrections,
          ),
          const SizedBox(height: 16),
          _PaymentsCard(payments: detail.payments),
          const SizedBox(height: 16),
          _HeaderCard(detail: detail),
        ],
      );
    },
  );
}

/// Cabecera oscura del detalle (lámina 2.8): proveedor, fecha y factura,
/// total, lo pagado y lo que falta, el estado y «Registrar pago al
/// proveedor» mientras quede saldo. El menú ofrece «Revertir compra».
///
/// Sin `FittedBox` (UX-C1): el total no se encoge; si no cabe, baja de
/// línea.
class _DetailHero extends StatelessWidget {
  const _DetailHero({
    required this.detail,
    required this.paid,
    required this.onPay,
    required this.onReverse,
  });

  final PurchaseDetailRead detail;
  final int paid;
  final VoidCallback onPay;
  final VoidCallback onReverse;

  @override
  Widget build(BuildContext context) {
    final p = detail.purchase;
    final reversed = p['status'] == 'REVERSED';
    final total = p['total_bob_minor']! as int;
    final remaining = total - paid;
    final invoice = p['invoice_number'] as String?;
    final split = splitBob(total);
    const muted = TextStyle(
      fontSize: 14,
      height: 20 / 14,
      color: AgroColors.onInkMuted,
    );
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
              if (!reversed)
                PopupMenuButton<String>(
                  key: const Key('purchase-detail-menu'),
                  tooltip: 'Más acciones',
                  iconColor: AgroColors.onInk,
                  style: IconButton.styleFrom(
                    backgroundColor: AgroColors.inkSoft,
                    fixedSize: const Size.square(44),
                  ),
                  onSelected: (_) => onReverse(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'reverse',
                      child: ListTile(
                        leading: Icon(Icons.undo),
                        title: Text('Revertir compra'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    'Compra',
                    formatDate(p['purchase_date']),
                    if (invoice != null && invoice.isNotEmpty)
                      'factura $invoice',
                  ].join(' · '),
                  style: muted,
                ),
                Semantics(
                  header: true,
                  child: Text(
                    p['supplier_name']! as String,
                    style: const TextStyle(
                      fontFamily: AgroFonts.display,
                      fontSize: 20,
                      height: 26 / 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: split.number,
                        style: TextStyle(
                          fontFamily: AgroFonts.display,
                          fontSize: 44,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          color: reversed
                              ? AgroColors.onInkMuted
                              : AgroColors.lime,
                          decoration: reversed
                              ? TextDecoration.lineThrough
                              : null,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      TextSpan(
                        text: ' ${split.unit}',
                        style: TextStyle(
                          fontFamily: AgroFonts.display,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: reversed
                              ? AgroColors.onInkMuted
                              : AgroColors.lime,
                        ),
                      ),
                    ],
                  ),
                  key: const Key('purchase-detail-total'),
                ),
                const SizedBox(height: 10),
                StatusBadge(
                  key: const Key('purchase-detail-status'),
                  label: operationStatusLabel(p['status']),
                  tone: reversed ? BadgeTone.neutral : BadgeTone.ok,
                ),
                if (!reversed) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      key: const Key('purchase-detail-progress'),
                      value: total <= 0 ? 0 : (paid / total).clamp(0.0, 1.0),
                      minHeight: 8,
                      color: AgroColors.lime,
                      backgroundColor: AgroColors.inkSoft,
                      semanticsLabel: 'Pagado al proveedor',
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        Text(
                          'Pagado ${formatBob(paid).trim()}',
                          style: const TextStyle(
                            fontSize: 15,
                            color: AgroColors.onInk,
                          ),
                        ),
                        Text(
                          remaining > 0
                              ? 'Falta ${formatBob(remaining).trim()}'
                              : 'Pagada',
                          key: const Key('purchase-detail-remaining'),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (remaining > 0) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        key: const Key('purchase-detail-pay'),
                        onPressed: onPay,
                        style: FilledButton.styleFrom(
                          backgroundColor: AgroColors.lime,
                          foregroundColor: AgroColors.ink,
                          minimumSize: const Size(0, 52),
                          shape: const StadiumBorder(),
                        ),
                        child: const Text(
                          'Registrar pago al proveedor',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(title, style: AgroText.h2),
      ),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AgroColors.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    ],
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
    return _Section(
      title: 'Datos de la compra',
      children: [
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
          _Field('Nota del tipo de cambio', p['exchange_rate_note']! as String),
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
              // Una compra revertida se consulta, con su historial, pero no
              // admite correcciones nuevas.
              if (detail.purchase['status'] != 'REVERSED')
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

typedef _LotDataCorrection = ({String? expiryDay, String? lotNumber});

/// Datos nuevos de vencimiento y número de lote de una línea (RF-42). El
/// motivo y el PIN se piden después, en la aprobación del titular.
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

  String? get _lengthError =>
      AgroRepository.lotNumberLengthError(lotNumber.text);

  bool get _changed {
    final number = lotNumber.text.trim();
    return expiryDay != widget.item['expiry_date'] ||
        (number.isEmpty ? null : number) != widget.item['lot_number'];
  }

  @override
  void dispose() {
    lotNumber.dispose();
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
          // Sin maxLength: lo pegado no se recorta; el exceso se señala.
          TextField(
            key: const Key('lot-data-number'),
            controller: lotNumber,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Número de lote (opcional)',
              counterText: lotNumberCounter(lotNumber.text),
              errorText: _lengthError,
              errorMaxLines: 3,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Después se pide el motivo y el PIN del titular. Se corrige en '
            'los lotes de esta compra y en los entregados desde ellos cuando '
            'su procedencia está demostrada. Las cantidades y los '
            'movimientos no cambian, y la corrección queda registrada.',
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
        // Sin cambios, o con un número demasiado largo, no se sigue: no se
        // pide motivo ni PIN para nada.
        onPressed: !_changed || _lengthError != null
            ? null
            : () {
                final number = lotNumber.text.trim();
                Navigator.pop<_LotDataCorrection>(context, (
                  expiryDay: expiryDay,
                  lotNumber: number.isEmpty ? null : number,
                ));
              },
        child: const Text('Continuar'),
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
