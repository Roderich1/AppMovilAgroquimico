/// Acciones sobre una compra confirmada: pagar al proveedor y revertir.
///
/// Rediseño B (2026-11-12): se trasladaron sin cambios desde
/// `purchases_screen.dart` para usarlas también en el detalle de la compra
/// (lámina 2.8, «Registrar pago al proveedor» y menú). La regla del pagador,
/// el diálogo, los límites, la aprobación del titular (RF-13) y las llamadas
/// al repositorio son los mismos.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../domain/campaign_calendar.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../../domain/person_roles.dart';
import '../../services/auth/local_owner_credential.dart'
    show AuthorizationPurpose;
import 'common.dart';
import 'owner_reversal_flow.dart';
import 'provider_payment_fields.dart';

/// Lo mínimo de una compra para pagarla o revertirla.
typedef PurchaseActionTarget = ({
  int id,
  String supplierName,
  String? invoiceNumber,
  int totalMinor,
  int paidMinor,
});

/// Fila de `purchases()` como destino de una acción.
PurchaseActionTarget purchaseTargetFromRow(Map<String, Object?> row) => (
  id: row['id']! as int,
  supplierName: '${row['supplier_name']}',
  invoiceNumber: row['invoice_number'] as String?,
  totalMinor: row['total_bob_minor']! as int,
  paidMinor: row['paid_bob_minor']! as int,
);

/// Registra un pago al proveedor de [purchase]. Devuelve `true` si se guardó.
Future<bool> payPurchaseProvider(
  BuildContext context,
  WidgetRef ref,
  PurchaseActionTarget purchase,
) async {
  final repo = ref.read(repositoryProvider);
  // Regla del pagador (piloto X01): paga el titular vigente, en las dos
  // modalidades. La lista sólo trae al titular; si está vacía es que no hay
  // titular vinculado, y registrar otra persona no lo arreglaría.
  final payers = await repo.peopleFor(PersonPurpose.providerPayer);
  if (!context.mounted) return false;
  if (payers.isEmpty) {
    showError(
      context,
      'No hay un titular vinculado: el pago al proveedor lo registra el '
      'titular.',
    );
    return false;
  }
  final remaining = purchase.totalMinor - purchase.paidMinor;
  final result = await showDialog<_PaymentInput?>(
    context: context,
    builder: (_) => _PaymentDialog(
      people: payers,
      maxMinor: remaining,
      title: 'Pago al proveedor',
      // El pagador no se elige: es el titular (en propio y en compartido).
      fixedPayer: payers.length == 1,
    ),
  );
  if (result == null) return false;
  try {
    // Medio y fecha: los que la persona vio y pudo corregir en el diálogo.
    await repo.addProviderPayment(
      purchaseId: purchase.id,
      payerPersonId: result.$1,
      amountBobMinor: result.$2,
      method: result.$3,
      date: result.$4,
    );
    return true;
  } catch (error) {
    if (context.mounted) showError(context, error);
    return false;
  }
}

/// Revierte [purchase] con motivo y PIN del titular (RF-13). Devuelve `true`
/// si se revirtió.
Future<bool> reversePurchaseWithApproval(
  BuildContext context,
  WidgetRef ref,
  PurchaseActionTarget purchase,
) async {
  final paid = purchase.paidMinor;
  final id = purchase.id;
  final approval = await requestOwnerApproval(
    context,
    ref,
    purpose: AuthorizationPurpose.reversePurchase,
    subjectRef: 'purchase:$id',
    title: '¿Revertir esta compra?',
    effects:
        '${purchase.supplierName} · '
        '${purchase.invoiceNumber ?? 'Sin factura'}\n'
        'Total ${formatBob(purchase.totalMinor)}\n\n'
        'Se anularán los lotes creados y los cargos generados'
        '${paid > 0 ? ', y se revertirán los pagos al proveedor por ${formatBob(paid)}' : ''}. '
        'Esta acción no se puede deshacer.',
    confirmLabel: 'Revertir compra',
    revalidate: reversalStillPending(ref, 'purchases', id),
  );
  if (approval == null || !context.mounted) return false;
  try {
    await ref
        .read(repositoryProvider)
        .reversePurchase(
          id,
          reason: approval.reason,
          authorization: approval.authorization,
        );
    return true;
  } catch (error) {
    if (context.mounted) showError(context, error);
    return false;
  }
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({
    required this.people,
    required this.maxMinor,
    required this.title,
    this.fixedPayer = false,
  });
  final List<Map<String, Object?>> people;
  final int maxMinor;
  final String title;

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
