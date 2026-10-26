import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/auth/local_owner_credential.dart'
    show AuthorizationPurpose;
import '../widgets/owner_reversal_flow.dart';

import '../../app.dart';
import '../../domain/campaign_calendar.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../../domain/person_roles.dart';
import '../widgets/common.dart';
import '../widgets/provider_payment_fields.dart';

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
    // Regla del pagador (piloto X01): paga el titular vigente, en las dos
    // modalidades. La lista sólo trae al titular; si está vacía es que no hay
    // titular vinculado, y registrar otra persona no lo arreglaría.
    final payers = await repo.peopleFor(PersonPurpose.providerPayer);
    if (!mounted) return;
    if (payers.isEmpty) {
      showError(
        context,
        'No hay un titular vinculado: el pago al proveedor lo registra el '
        'titular.',
      );
      return;
    }
    final remaining =
        (purchase['total_bob_minor']! as int) -
        (purchase['paid_bob_minor']! as int);
    final result = await showDialog<_PaymentInput?>(
      context: context,
      builder: (_) => _PaymentDialog(
        people: payers,
        maxMinor: remaining,
        title: 'Pago al proveedor',
        purchaseDay: storedLocalDay(purchase['purchase_date']! as String),
        // El pagador no se elige: es el titular (en propio y en compartido).
        fixedPayer: payers.length == 1,
      ),
    );
    if (result == null) return;
    try {
      // Medio y fecha: los que la persona vio y pudo corregir en el diálogo.
      await repo.addProviderPayment(
        purchaseId: purchase['id']! as int,
        payerPersonId: result.$1,
        amountBobMinor: result.$2,
        method: result.$3,
        date: result.$4,
      );
      _refresh();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _reverse(Map<String, Object?> purchase) async {
    final paid = purchase['paid_bob_minor']! as int;
    final id = purchase['id']! as int;
    // RF-13: motivo y PIN del titular; el actor sale de la autorización.
    final approval = await requestOwnerApproval(
      context,
      ref,
      purpose: AuthorizationPurpose.reversePurchase,
      subjectRef: 'purchase:$id',
      title: '¿Revertir esta compra?',
      effects:
          '${purchase['supplier_name']} · '
          '${purchase['invoice_number'] ?? 'Sin factura'}\n'
          'Total ${formatBob(purchase['total_bob_minor']! as int)}\n\n'
          'Se anularán los lotes creados y los cargos generados'
          '${paid > 0 ? ', y se revertirán los pagos al proveedor por ${formatBob(paid)}' : ''}. '
          'Esta acción no se puede deshacer.',
      confirmLabel: 'Revertir compra',
    );
    if (approval == null || !mounted) return;
    try {
      await ref
          .read(repositoryProvider)
          .reversePurchase(
            id,
            reason: approval.reason,
            authorization: approval.authorization,
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
                              if (row['status'] == 'REVERSED')
                                ReversalActorText(
                                  operationType: 'PURCHASE',
                                  operationId: row['id']! as int,
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
    required this.purchaseDay,
    this.fixedPayer = false,
  });
  final List<Map<String, Object?>> people;
  final int maxMinor;
  final String title;

  /// Día local de la compra: el pago no puede ser anterior.
  final String purchaseDay;

  /// Paga el titular: no se elige pagador (#26 y regla del piloto X01).
  final bool fixedPayer;
  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

/// Lo que devuelve el diálogo: pagador, importe, medio y fecha del pago.
typedef _PaymentInput = (int, int, PaymentMethod, DateTime);

class _PaymentDialogState extends State<_PaymentDialog> {
  late int? person = widget.fixedPayer
      ? widget.people.single['id']! as int
      : null;
  // Se precarga con el convenio es-BO que la propia aplicacion acepta.
  // `toStringAsFixed` producia "20000.00", que con la regla de entrada
  // centralizada (UIBUG-003) es un formato invalido: el punto es separador de
  // miles, no decimal.
  late final amount = TextEditingController(
    text: formatForInput(widget.maxMinor / 100, maxDecimals: 2),
  );

  /// Medio y día del pago: visibles y corregibles, sin valores supuestos.
  /// El medio empieza en «Sin indicar»; el día, en hoy (se registra ahora).
  PaymentMethod method = PaymentMethod.unspecified;
  late String day = localDay(DateTime.now());

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  void _submit() {
    final payer = person;
    if (payer == null) return;
    Navigator.pop<_PaymentInput>(context, (
      payer,
      parseMinor(amount.text),
      method,
      effectiveInstantForDay(day, DateTime.now()),
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.fixedPayer)
            Text(
              'Paga el titular: ${widget.people.single['name']}',
              key: const Key('payment-personal-payer'),
            )
          else
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
          const SizedBox(height: 12),
          ProviderPaymentFields(
            method: method,
            onMethodChanged: (value) => setState(() => method = value),
            day: day,
            dayHint: day == localDay(DateTime.now()) ? ' (hoy)' : '',
            firstDay: widget.purchaseDay,
            onDayChanged: (value) => setState(() => day = value),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Registrar')),
    ],
  );
}
