// Consulta única del libro de cuentas (D-04 y E-15, decisiones del autor del
// 2026-10-27; docs/architecture/D04_E15_CUENTAS_IMPUTACION_Y_COSTO_PROPIO.md).
// La usan el repositorio y `OperationModeStore` (paso a modo propio), que
// trabaja dentro de su propia transacción.

import 'package:sqflite/sqflite.dart' show DatabaseExecutor;

import '../domain/account_ledger.dart';

const _conceptSql = '''COALESCE(
      (SELECT GROUP_CONCAT(p.name, ', ') FROM application_items i JOIN products p ON p.id=i.product_id
       WHERE i.application_id=t.reference_id AND t.reference_type='APPLICATION'),
      (SELECT p.name FROM purchase_allocations a JOIN purchase_items i ON i.id=a.purchase_item_id
       JOIN products p ON p.id=i.product_id WHERE a.id=t.reference_id AND t.reference_type='PURCHASE_ALLOCATION'),
      t.notes, t.type)''';

const _farmSql =
    '''(SELECT f.name FROM applications a JOIN farms f ON f.id=a.farm_id
     WHERE a.id=t.reference_id AND t.reference_type='APPLICATION')''';

/// Libro de cuentas en **una** consulta: campañas (K), personas (P),
/// asientos (T), imputaciones (L), vínculos de titular (B) y aplicaciones de
/// quien ha sido titular (A, para el consumo propio de E-15). Con
/// [personId], sólo esa persona (los vínculos se leen siempre todos).
/// La clasificación y los cálculos son Dart puro (`AccountLedger`).
///
/// Con [withDetails] en `false` no se resuelven concepto ni chaco (sin
/// `GROUP_CONCAT`): basta para cifras (lista, Inicio, resumen).
Future<AccountLedger> readAccountLedger(
  DatabaseExecutor db, {
  int? personId,
  bool withDetails = true,
}) async {
  final one = personId != null;
  final concept = withDetails ? _conceptSql : 'NULL';
  final farm = withDetails ? _farmSql : 'NULL';
  final rows = await db.rawQuery(
    '''SELECT 'K' kind, c.id id, NULL person_id, c.name name, c.start_date d1,
        c.end_date d2, c.status code, NULL amount, NULL ref1, NULL ref2,
        NULL concept, NULL farm_name, NULL notes FROM campaigns c
      UNION ALL
      SELECT 'P', p.id, p.id, p.name, NULL, NULL, p.role, NULL, NULL, NULL,
        NULL, NULL, NULL FROM persons p ${one ? 'WHERE p.id=?' : ''}
      UNION ALL
      SELECT 'T', t.id, t.person_id, NULL, t.transaction_date, NULL, t.type,
        t.amount_bob_minor_signed, t.campaign_id, t.reversal_of_id,
        $concept, $farm, t.notes
        FROM account_transactions t ${one ? 'WHERE t.person_id=?' : ''}
      UNION ALL
      SELECT 'L', a.id, NULL, NULL, NULL, NULL, NULL, a.amount_bob_minor,
        a.payment_transaction_id, a.charge_transaction_id, NULL, NULL, NULL
        FROM payment_allocations a
        ${one ? 'WHERE a.payment_transaction_id IN (SELECT id FROM account_transactions WHERE person_id=?)' : ''}
      UNION ALL
      SELECT 'B', b.id, b.person_id, NULL, b.bound_at, b.ended_at, NULL, NULL,
        NULL, NULL, NULL, NULL, NULL FROM owner_bindings b
      UNION ALL
      SELECT 'A', a.id, a.person_id, NULL, a.applied_at, a.reversed_at, a.status,
        a.total_cost_bob_minor, a.campaign_id, NULL, NULL, NULL, NULL
        FROM applications a
        WHERE a.person_id IN (SELECT person_id FROM owner_bindings)
        ${one ? 'AND a.person_id=?' : ''}''',
    [
      if (one) ...[personId, personId, personId, personId],
    ],
  );
  return AccountLedger.fromRows(rows);
}
