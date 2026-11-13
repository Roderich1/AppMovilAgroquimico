// Proveedores y saldos (lámina I-05, modo individual, 2026-11-13).
//
// Lo que se debe a cada proveedor por compras a crédito y el acceso a
// pagarlas. No calcula nada nuevo: el saldo de una compra es el mismo que
// «Registrar pago al proveedor» propone en Compras y que Inicio cuenta como
// «compras pendientes de pago» (`purchases()`: total de una compra
// confirmada menos sus pagos no revertidos). Pagar usa el mismo flujo
// (`payPurchaseProvider`: paga el titular vigente, en las dos modalidades).
// Un pago a un proveedor no es un cobro al titular ni a otra persona.
//
// La pantalla sirve igual en las dos modalidades (no depende de personas);
// sólo el texto final menciona «Chacos › Costos», que existe en el modo
// individual.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../domain/money.dart';
import '../../operation_mode_controller.dart' show personalModeProvider;
import '../theme/agro_theme.dart';
import '../widgets/agro_ui.dart';
import '../widgets/common.dart';
import '../widgets/rdm_b_purchase_actions.dart';
import '../widgets/rdm_b_ui.dart';
import '../widgets/register_sheet.dart' show registerRevisionProvider;

/// Ruta propuesta al orquestador (dentro del shell, sección Actividad).
const indProvidersPath = '/proveedores';

/// Compras pagadas que se muestran por proveedor; las demás, en la lista de
/// compras.
const _paidShown = 3;

/// Saldo pendiente de una fila de `purchases()`: total menos lo pagado, sólo
/// de una compra confirmada y sólo si es positivo. Es el criterio de Inicio
/// y de «Registrar pago al proveedor».
int purchaseBalanceMinor(Map<String, Object?> row) {
  if (row['status'] != 'CONFIRMED') return 0;
  final balance =
      (row['total_bob_minor']! as int) - (row['paid_bob_minor']! as int);
  return balance > 0 ? balance : 0;
}

/// Resumen de lo que se debe a proveedores, de todas las campañas.
typedef SupplierDebt = ({int totalMinor, int purchases, int suppliers});

/// Suma los saldos de [rows] (todas las compras, sin límite de filas).
SupplierDebt supplierDebt(Iterable<Map<String, Object?>> rows) {
  var total = 0;
  var purchases = 0;
  final suppliers = <Object?>{};
  for (final row in rows) {
    final balance = purchaseBalanceMinor(row);
    if (balance == 0) continue;
    total += balance;
    purchases++;
    suppliers.add(row['supplier_id'] ?? row['supplier_name']);
  }
  return (totalMinor: total, purchases: purchases, suppliers: suppliers.length);
}

/// Importe en Bs sin el espacio final que deja `formatBob` («Bs »), para
/// que no quede un hueco doble antes de « · ».
String _bob(int minor) => formatBob(minor).trim();

String _plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';

/// «Debe 1.885,00 Bs · todas las campañas» o «Sin saldo con proveedores».
String supplierDebtLine(SupplierDebt debt) => debt.totalMinor == 0
    ? 'Sin saldo pendiente · todas las campañas'
    : 'Debe ${_bob(debt.totalMinor)} · todas las campañas';

class SuppliersBalanceScreen extends ConsumerStatefulWidget {
  const SuppliersBalanceScreen({super.key});

  @override
  ConsumerState<SuppliersBalanceScreen> createState() =>
      _SuppliersBalanceScreenState();
}

class _SuppliersBalanceScreenState
    extends ConsumerState<SuppliersBalanceScreen> {
  // Sin límite de filas: con el de 200 se contarían de menos (como Inicio).
  late Future<List<Map<String, Object?>>> future = _load();

  Future<List<Map<String, Object?>>> _load() =>
      ref.read(repositoryProvider).purchases(limit: 1 << 30);

  void _refresh() {
    final next = _load();
    setState(() {
      future = next;
    });
  }

  Future<void> _pay(Map<String, Object?> row) async {
    if (await payPurchaseProvider(context, ref, purchaseTargetFromRow(row)) &&
        mounted) {
      _refresh();
      showSuccess(context, 'Pago al proveedor registrado.');
    }
  }

  Future<void> _openDetail(int id) async {
    await context.push('/compras/detalle/$id');
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(registerRevisionProvider, (_, _) => _refresh());
    final personal = ref.watch(personalModeProvider);
    return FutureBuilder<List<Map<String, Object?>>>(
      future: future,
      builder: (context, snapshot) {
        const title = ScreenTitleBar(
          title: 'Proveedores',
          leading: RdmBackButton(),
          compact: true,
        );
        if (snapshot.hasError) {
          return RdmScrollPage(
            children: [
              title,
              EmptyState(
                icon: Icons.error_outline,
                message: friendlyError(snapshot.error!),
              ),
            ],
          );
        }
        if (!snapshot.hasData) {
          return const RdmScrollPage(
            children: [
              title,
              Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
          );
        }
        // Las revertidas no son deuda ni pago: su historia está en Actividad.
        final rows = snapshot.data!
            .where((r) => r['status'] == 'CONFIRMED')
            .toList();
        if (rows.isEmpty) {
          return const RdmScrollPage(
            children: [
              title,
              EmptyState(
                icon: Icons.storefront_outlined,
                message:
                    'Todavía no hay compras a proveedores. Al registrar una '
                    'compra a crédito, su saldo aparece aquí.',
              ),
            ],
          );
        }
        final debt = supplierDebt(rows);
        final bySupplier = <String, List<Map<String, Object?>>>{};
        for (final row in rows) {
          bySupplier.putIfAbsent('${row['supplier_name']}', () => []).add(row);
        }
        int owed(List<Map<String, Object?>> list) =>
            list.fold(0, (sum, r) => sum + purchaseBalanceMinor(r));
        // Primero a quien más se debe; después, por nombre.
        final suppliers = bySupplier.keys.toList()
          ..sort((a, b) {
            final byDebt = owed(bySupplier[b]!).compareTo(owed(bySupplier[a]!));
            return byDebt != 0 ? byDebt : a.compareTo(b);
          });
        return RdmScrollPage(
          children: [
            title,
            const SizedBox(height: 8),
            _DebtHeader(debt: debt),
            for (final name in suppliers) ...[
              const SizedBox(height: 20),
              _SupplierSection(
                name: name,
                rows: bySupplier[name]!,
                owedMinor: owed(bySupplier[name]!),
                onPay: _pay,
                onOpen: _openDetail,
                onAll: () => context.push('/compras'),
              ),
            ],
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                personal
                    ? 'Aquí paga compras a crédito. Sus costos propios se '
                          'consultan en Chacos › Costos.'
                    : 'Aquí paga compras a crédito. Pagar a un proveedor no '
                          'es un cobro a una persona.',
                key: const Key('suppliers-footer'),
                style: AgroText.detail,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Cabecera oscura: lo que se debe a proveedores, de todas las campañas.
class _DebtHeader extends StatelessWidget {
  const _DebtHeader({required this.debt});
  final SupplierDebt debt;

  @override
  Widget build(BuildContext context) {
    final amount = splitBob(debt.totalMinor);
    return Container(
      key: const Key('suppliers-debt'),
      decoration: BoxDecoration(
        color: AgroColors.ink,
        borderRadius: BorderRadius.circular(28),
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Semantics(
        label:
            'Debe a proveedores, todas las campañas: '
            '${_bob(debt.totalMinor)}',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Debe a proveedores · todas las campañas',
              style: TextStyle(fontSize: 15, color: AgroColors.onInkMuted),
            ),
            const SizedBox(height: 4),
            BigFigure(
              number: amount.number,
              unit: amount.unit,
              size: 48,
              color: Colors.white,
              unitColor: AgroColors.lime,
            ),
            const SizedBox(height: 6),
            Text(
              debt.totalMinor == 0
                  ? 'Ninguna compra con saldo'
                  : '${_plural(debt.purchases, 'compra con saldo', 'compras con saldo')}'
                        ' · ${_plural(debt.suppliers, 'proveedor', 'proveedores')}',
              style: const TextStyle(
                fontSize: 15,
                color: AgroColors.onInkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Un proveedor: lo que se le debe, sus compras con saldo (con «Pagar») y
/// las últimas pagadas.
class _SupplierSection extends StatelessWidget {
  const _SupplierSection({
    required this.name,
    required this.rows,
    required this.owedMinor,
    required this.onPay,
    required this.onOpen,
    required this.onAll,
  });

  final String name;
  final List<Map<String, Object?>> rows;
  final int owedMinor;
  final void Function(Map<String, Object?> row) onPay;
  final void Function(int id) onOpen;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) {
    final withBalance = rows.where((r) => purchaseBalanceMinor(r) > 0).toList();
    final paid = rows.where((r) => purchaseBalanceMinor(r) == 0).toList();
    final hiddenPaid = paid.length - _paidShown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 2,
            children: [
              Semantics(header: true, child: Text(name, style: AgroText.h2)),
              Text(
                owedMinor == 0 ? 'Sin saldo' : 'Debe ${_bob(owedMinor)}',
                style: AgroText.detail,
              ),
            ],
          ),
        ),
        AgroGroup(
          children: [
            for (final row in withBalance)
              _PurchaseRow(row: row, onPay: onPay, onOpen: onOpen),
            for (final row in paid.take(_paidShown))
              _PurchaseRow(row: row, onPay: onPay, onOpen: onOpen),
            if (hiddenPaid > 0)
              LinkRow(
                title: hiddenPaid == 1
                    ? '1 compra pagada más'
                    : '$hiddenPaid compras pagadas más',
                subtitle: 'En la lista de compras',
                onTap: onAll,
              ),
          ],
        ),
      ],
    );
  }
}

class _PurchaseRow extends StatelessWidget {
  const _PurchaseRow({
    required this.row,
    required this.onPay,
    required this.onOpen,
  });

  final Map<String, Object?> row;
  final void Function(Map<String, Object?> row) onPay;
  final void Function(int id) onOpen;

  @override
  Widget build(BuildContext context) {
    final id = row['id']! as int;
    final total = row['total_bob_minor']! as int;
    final paid = row['paid_bob_minor']! as int;
    final balance = purchaseBalanceMinor(row);
    final day = formatDate(row['purchase_date']);
    final title = balance > 0
        ? 'Debe ${_bob(balance)}'
        : 'Compra de ${_bob(total)}';
    final detail = balance > 0
        ? 'Compra del $day · total ${splitBob(total).number} · '
              '${paid <= 0 ? 'sin pagos' : 'pagó ${splitBob(paid).number}'}'
        : 'Compra del $day';
    final trailing = balance > 0
        ? FilledButton(
            key: Key('suppliers-pay-$id'),
            style: FilledButton.styleFrom(
              backgroundColor: AgroColors.ink,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              shape: const StadiumBorder(),
            ),
            onPressed: () => onPay(row),
            child: const Text(
              'Pagar',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          )
        : const StatusBadge(label: 'Pagada', tone: BadgeTone.ok);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: Key('suppliers-purchase-$id'),
        onTap: () => onOpen(id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final text = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      height: 22 / 17,
                      fontWeight: FontWeight.w700,
                      color: AgroColors.ink,
                    ),
                  ),
                  Text(detail, style: AgroText.detail),
                ],
              );
              // Con letra grande el botón baja debajo del texto, a la
              // derecha: el importe no se aprieta en una columna estrecha.
              final narrow =
                  constraints.maxWidth <
                  MediaQuery.textScalerOf(context).scale(300);
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    text,
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerRight, child: trailing),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: text),
                  const SizedBox(width: 12),
                  trailing,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
