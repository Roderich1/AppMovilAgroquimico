import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
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

  Future<void> _reverse(Map<String, Object?> purchase) async {
    final paid = purchase['paid_bob_minor']! as int;
    final confirmed = await confirmDestructiveAction(
      context,
      title: '¿Revertir esta compra?',
      detail:
          '${purchase['supplier_name']} · '
          '${purchase['invoice_number'] ?? 'Sin factura'}\n'
          'Total ${formatBob(purchase['total_bob_minor']! as int)}\n\n'
          'Se anularán los lotes creados y los cargos generados'
          '${paid > 0 ? ', y se revertirán los pagos al proveedor por ${formatBob(paid)}' : ''}. '
          'Esta acción no se puede deshacer.',
      confirmLabel: 'Revertir compra',
    );
    if (!confirmed || !mounted) return;
    try {
      await ref
          .read(repositoryProvider)
          .reversePurchase(
            purchase['id']! as int,
            reason: 'Reversión solicitada por usuario',
          );
      if (mounted) _refresh();
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
        // El error se comprueba ANTES que los datos: al revés, `hasData` es
        // falso durante un fallo y esta rama nunca se alcanzaba.
        if (snapshot.hasError)
          return EmptyState(
            icon: Icons.error_outline,
            message: friendlyError(snapshot.error!),
          );
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
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
                                _reverse(row);
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
  // Se precarga con el convenio es-BO que la propia aplicacion acepta.
  // `toStringAsFixed` producia "20000.00", que con la regla de entrada
  // centralizada (UIBUG-003) es un formato invalido: el punto es separador de
  // miles, no decimal.
  late final amount = TextEditingController(
    text: formatForInput(widget.maxMinor / 100, maxDecimals: 2),
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
