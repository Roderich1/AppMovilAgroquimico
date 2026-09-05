import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../widgets/common.dart';

class PurchasesScreen extends ConsumerStatefulWidget {
  const PurchasesScreen({super.key});
  @override
  ConsumerState<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends ConsumerState<PurchasesScreen> {
  late Future<List<Map<String, Object?>>> data;
  String query = '';
  int? campaignFilter;
  @override
  void initState() {
    super.initState();
    data = ref.read(repositoryProvider).purchases();
  }

  void _refresh() {
    final next = ref.read(repositoryProvider).purchases();
    setState(() {
      data = next;
    });
  }

  Future<void> _newPurchase() async {
    final created = await context.push<bool>('/compras/nueva');
    if (!mounted) return;
    if (created == true) {
      _refresh();
      showSuccess(
        context,
        'Compra multiproducto confirmada; lotes e inventario creados.',
      );
    }
  }

  Future<void> _viewInvoice(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      if (mounted) {
        showError(
          context,
          'La imagen de factura ya no está disponible en este dispositivo.',
        );
      }
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Factura'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700, maxHeight: 700),
          child: InteractiveViewer(
            child: Image.file(file, fit: BoxFit.contain),
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

  Future<void> _pay(Map<String, Object?> purchase) async {
    final repo = ref.read(repositoryProvider);
    final admins = (await repo.people())
        .where((p) => p['role'] == 'ADMIN')
        .toList();
    if (!mounted) return;
    if (admins.isEmpty) {
      showError(
        context,
        'Registra una persona administradora para pagar al proveedor.',
      );
      return;
    }
    final remaining =
        (purchase['total_bob_minor']! as int) -
        (purchase['paid_bob_minor']! as int);
    final result = await showDialog<(int, int)?>(
      context: context,
      builder: (_) => _PaymentDialog(
        people: admins,
        maxMinor: remaining,
        title: 'Pago al proveedor',
      ),
    );
    if (result == null) return;
    try {
      await repo.addProviderPayment(
        purchaseId: purchase['id']! as int,
        payerPersonId: result.$1,
        amountBobMinor: result.$2,
        method: 'TRANSFER',
      );
      _refresh();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _reverse(int id) async {
    try {
      await ref
          .read(repositoryProvider)
          .reversePurchase(id, reason: 'Reversión solicitada por usuario');
      _refresh();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Compras',
    subtitle: 'Precio original, FX histórico, pago al proveedor y lotes.',
    action: FilledButton.icon(
      onPressed: _newPurchase,
      icon: const Icon(Icons.add),
      label: const Text('Nueva compra'),
    ),
    child: FutureBuilder(
      future: data,
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError)
          return EmptyState(
            icon: Icons.error_outline,
            message: snapshot.error.toString(),
          );
        if (snapshot.data!.isEmpty)
          return const Card(
            child: EmptyState(
              icon: Icons.shopping_bag_outlined,
              message: 'No hay compras confirmadas.',
            ),
          );
        final rows = snapshot.data!.where((row) {
          if (campaignFilter != null && row['campaign_id'] != campaignFilter) {
            return false;
          }
          if (query.isEmpty) return true;
          return '${row['supplier_name']} ${row['invoice_number'] ?? ''}'
              .toLowerCase()
              .contains(query);
        }).toList();
        return Column(
          children: [
            DropdownButtonFormField<int?>(
              initialValue: campaignFilter,
              decoration: const InputDecoration(
                labelText: 'Campaña',
                prefixIcon: Icon(Icons.calendar_month_outlined),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todas')),
                for (final row in {
                  for (final row in snapshot.data!)
                    row['campaign_id'] as int: row,
                }.values)
                  DropdownMenuItem(
                    value: row['campaign_id'] as int,
                    child: Text(row['campaign_name'] as String),
                  ),
              ],
              onChanged: (value) => setState(() => campaignFilter = value),
            ),
            const SizedBox(height: 8),
            TextField(
              onChanged: (value) => setState(() {
                query = value.trim().toLowerCase();
              }),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Buscar proveedor o factura',
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        CircleAvatar(
                          child: Icon(
                            row['status'] == 'REVERSED'
                                ? Icons.undo
                                : Icons.receipt_long_outlined,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${row['supplier_name']} · ${row['invoice_number'] ?? 'Sin factura'}',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                '${row['campaign_name']} · ${row['item_count']} producto${row['item_count'] == 1 ? '' : 's'} · Total ${formatBob(row['total_bob_minor']! as int)} · pagado ${formatBob(row['paid_bob_minor']! as int)} · ${row['status'] == 'CONFIRMED' ? 'Confirmada' : 'Revertida'}',
                              ),
                            ],
                          ),
                        ),
                        if (row['status'] != 'REVERSED')
                          PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'pay') {
                                _pay(row);
                              } else if (value == 'invoice') {
                                _viewInvoice(
                                  row['invoice_image_path']! as String,
                                );
                              } else {
                                _reverse(row['id']! as int);
                              }
                            },
                            itemBuilder: (_) => [
                              if (row['invoice_image_path'] != null)
                                const PopupMenuItem(
                                  value: 'invoice',
                                  child: ListTile(
                                    leading: Icon(Icons.image_outlined),
                                    title: Text('Ver factura'),
                                  ),
                                ),
                              const PopupMenuItem(
                                value: 'pay',
                                child: ListTile(
                                  leading: Icon(Icons.payments_outlined),
                                  title: Text('Registrar pago'),
                                ),
                              ),
                              const PopupMenuItem(
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
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _AllocationInput {
  int? personId;
  final quantity = TextEditingController();
  void dispose() => quantity.dispose();
}

class _PurchaseDialog extends StatefulWidget {
  const _PurchaseDialog({
    required this.suppliers,
    required this.campaigns,
    required this.products,
    required this.people,
  });
  final List<Map<String, Object?>> suppliers, campaigns, products, people;
  @override
  State<_PurchaseDialog> createState() => _PurchaseDialogState();
}

class _PurchaseDialogState extends State<_PurchaseDialog> {
  int? supplier, campaign, product;
  CurrencyCode currency = CurrencyCode.usd;
  final quantity = TextEditingController(text: '420');
  final price = TextEditingController(text: '16');
  final fx = TextEditingController(text: '7');
  final invoice = TextEditingController();
  final allocations = <_AllocationInput>[_AllocationInput()];

  @override
  void dispose() {
    quantity.dispose();
    price.dispose();
    fx.dispose();
    invoice.dispose();
    for (final allocation in allocations) {
      allocation.dispose();
    }
    super.dispose();
  }

  int get quantityBase => parseBase(quantity.text);
  int get priceMinor => parseMinor(price.text);
  int? get fxScaled => currency == CurrencyCode.usd
      ? ((tryParseDecimal(fx.text) ?? 0) * fxScale).round()
      : null;
  int get unitBob => convertedUnitPriceBobMinor(priceMinor, fxScaled);
  int get totalBob => subtotalMinor(
    quantityBase: quantityBase,
    unitPriceMinor: priceMinor,
    fxScaled: fxScaled,
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Confirmar compra'),
    content: SizedBox(
      width: 620,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: _select(
                    'Proveedor',
                    widget.suppliers,
                    supplier,
                    (v) => setState(() => supplier = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _select(
                    'Campaña',
                    widget.campaigns,
                    campaign,
                    (v) => setState(() => campaign = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _select(
              'Producto',
              widget.products,
              product,
              (v) => setState(() => product = v),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: quantity,
                    onChanged: (_) => setState(() {}),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Cantidad (L/kg)',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField(
                    initialValue: currency,
                    decoration: const InputDecoration(labelText: 'Moneda'),
                    items: const [
                      DropdownMenuItem(
                        value: CurrencyCode.bob,
                        child: Text('BOB'),
                      ),
                      DropdownMenuItem(
                        value: CurrencyCode.usd,
                        child: Text('USD'),
                      ),
                    ],
                    onChanged: (value) => setState(() => currency = value!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: price,
                    onChanged: (_) => setState(() {}),
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: currency == CurrencyCode.usd
                          ? 'Precio unitario USD'
                          : 'Precio unitario Bs',
                    ),
                  ),
                ),
                if (currency == CurrencyCode.usd) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: fx,
                      onChanged: (_) => setState(() {}),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Tipo de cambio Bs/USD',
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: invoice,
              decoration: const InputDecoration(
                labelText: 'N.º de factura (opcional)',
              ),
            ),
            const SizedBox(height: 16),
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${quantity.text} L/kg · ${currency == CurrencyCode.usd ? '\$' : 'Bs '}${price.text}/unidad',
                    ),
                    if (currency == CurrencyCode.usd)
                      Text('FX ${fx.text} · ${formatBob(unitBob)}/unidad'),
                    const SizedBox(height: 6),
                    Text(
                      formatBob(totalBob),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Asignación de stock',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton.icon(
                  onPressed: () =>
                      setState(() => allocations.add(_AllocationInput())),
                  icon: const Icon(Icons.add),
                  label: const Text('Persona'),
                ),
              ],
            ),
            for (var i = 0; i < allocations.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _select(
                        'Propietario',
                        widget.people,
                        allocations[i].personId,
                        (v) => setState(() => allocations[i].personId = v),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: allocations[i].quantity,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Cantidad',
                        ),
                      ),
                    ),
                    if (allocations.length > 1)
                      IconButton(
                        onPressed: () =>
                            setState(() => allocations.removeAt(i)),
                        icon: const Icon(Icons.close),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Familia: la asignación no crea deuda. Tercero: genera cargo al confirmar.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton.icon(
        onPressed: _submit,
        icon: const Icon(Icons.check),
        label: const Text('Confirmar y crear lotes'),
      ),
    ],
  );

  void _submit() {
    try {
      if (supplier == null ||
          campaign == null ||
          product == null ||
          allocations.any((a) => a.personId == null))
        return;
      Navigator.pop(
        context,
        PurchaseDraft(
          supplierId: supplier!,
          campaignId: campaign!,
          purchaseDate: DateTime.now(),
          invoiceNumber: invoice.text.trim(),
          exchangeRateSource: currency == CurrencyCode.usd
              ? ExchangeRateSource.agreedWithSupplier
              : null,
          items: [
            PurchaseItemDraft(
              productId: product!,
              quantityBase: quantityBase,
              currency: currency,
              originalUnitPriceMinor: priceMinor,
              exchangeRateScaled: fxScaled,
              allocations: [
                for (final allocation in allocations)
                  AllocationDraft(
                    personId: allocation.personId!,
                    quantityBase: parseBase(allocation.quantity.text),
                  ),
              ],
            ),
          ],
        ),
      );
    } catch (_) {}
  }

  Widget _select(
    String label,
    List<Map<String, Object?>> rows,
    int? value,
    ValueChanged<int?> changed,
  ) => DropdownButtonFormField<int>(
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    isExpanded: true,
    items: [
      for (final row in rows)
        DropdownMenuItem(
          value: row['id']! as int,
          child: Text(row['name']! as String),
        ),
    ],
    onChanged: changed,
  );
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({
    required this.people,
    required this.maxMinor,
    required this.title,
  });
  final List<Map<String, Object?>> people;
  final int maxMinor;
  final String title;
  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  int? person;
  late final amount = TextEditingController(
    text: (widget.maxMinor / 100).toStringAsFixed(2),
  );
  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<int>(
          initialValue: person,
          decoration: const InputDecoration(labelText: 'Pagador'),
          items: [
            for (final p in widget.people)
              DropdownMenuItem(
                value: p['id']! as int,
                child: Text(p['name']! as String),
              ),
          ],
          onChanged: (value) => setState(() => person = value),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: amount,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Importe BOB',
            helperText: 'Máximo ${formatBob(widget.maxMinor)}',
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (person != null)
            Navigator.pop(context, (person!, parseMinor(amount.text)));
        },
        child: const Text('Registrar'),
      ),
    ],
  );
}
