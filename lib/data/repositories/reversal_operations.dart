import 'package:sqflite/sqflite.dart' show Sqflite, Transaction;

import 'repository_exceptions.dart';
import 'repository_session.dart';
import 'repository_types.dart';

/// Ejecución transaccional de los efectos compensatorios de reversión
/// (RF-13) para aplicaciones, compras y transferencias.
class ReversalOperations {
  ReversalOperations(this._session);

  final RepositorySession _session;

  Future<OriginalOperation> reverseApplicationIn(
    Transaction txn,
    WriteContext context,
    int applicationId,
    String? reason,
    ReversalEffects effects,
  ) async {
    final rows = await txn.query(
      'applications',
      where: 'id = ? AND reversed_at IS NULL',
      whereArgs: [applicationId],
    );
    if (rows.isEmpty) {
      throw BusinessRuleException(
        'La aplicación ya fue revertida o no existe.',
      );
    }
    final application = rows.single;
    _session.requireOwnerInPersonal(
      context,
      [application['person_id']! as int],
      'En el modo individual sólo se revierten aplicaciones del titular. '
      'Para revertir la de otra persona, cambie al modo con varias personas.',
    );
    final consumptions = await txn.rawQuery(
      '''SELECT c.*, i.product_id FROM application_consumptions c
      JOIN application_items i ON i.id = c.application_item_id
      WHERE i.application_id = ? AND c.reversed_at IS NULL''',
      [applicationId],
    );
    final now = _session.date(DateTime.now());
    for (final consumption in consumptions) {
      effects.add(
        'inventory_movements',
        await txn.insert('inventory_movements', {
          'lot_id': consumption['inventory_lot_id'],
          'product_id': consumption['product_id'],
          'owner_person_id': application['person_id'],
          'movement_date': now,
          'type': 'APPLICATION_REVERSAL',
          'quantity_signed': consumption['quantity_consumed_base'],
          'reference_type': 'APPLICATION_REVERSAL',
          'reference_id': applicationId,
          'notes': reason,
        }),
      );
      effects.add('application_consumptions', consumption['id']! as int);
    }
    await txn.update(
      'application_consumptions',
      {'reversed_at': now},
      where: 'application_item_id IN (SELECT id FROM application_items WHERE application_id = ?)',
      whereArgs: [applicationId],
    );
    final charges = await txn.query(
      'account_transactions',
      where: "reference_type = 'APPLICATION' AND reference_id = ? AND type = 'USAGE_CHARGE'",
      whereArgs: [applicationId],
    );
    for (final charge in charges) {
      effects.add(
        'account_transactions',
        await txn.insert('account_transactions', {
          'person_id': charge['person_id'],
          'campaign_id': charge['campaign_id'],
          'transaction_date': now,
          'type': 'CREDIT_ADJUSTMENT',
          'amount_bob_minor_signed':
              -(charge['amount_bob_minor_signed']! as int),
          'reference_type': 'APPLICATION_REVERSAL',
          'reference_id': applicationId,
          'notes': reason,
          'reversal_of_id': charge['id'],
        }),
      );
    }
    await txn.update(
      'applications',
      {'status': 'REVERSED', 'reversed_at': now},
      where: 'id = ?',
      whereArgs: [applicationId],
    );
    return (
      personId: application['person_id'] as int?,
      effectiveDate: application['applied_at'] as String?,
    );
  }

  Future<OriginalOperation> reversePurchaseIn(
    Transaction txn,
    WriteContext context,
    int purchaseId,
    String? reason,
    ReversalEffects effects,
  ) async {
    final consumed =
        Sqflite.firstIntValue(
          await txn.rawQuery(
            '''SELECT COUNT(*) FROM application_consumptions c
            JOIN inventory_lots l ON l.id = c.inventory_lot_id
            JOIN purchase_items i ON i.id = l.purchase_item_id
            WHERE i.purchase_id = ? AND c.reversed_at IS NULL''',
            [purchaseId],
          ),
        ) ??
        0;
    if (consumed > 0) {
      throw BusinessRuleException(
        'La compra tiene lotes consumidos. Revierta primero las aplicaciones relacionadas.',
      );
    }
    final purchase = await txn.query(
      'purchases',
      where: 'id = ? AND reversed_at IS NULL',
      whereArgs: [purchaseId],
    );
    if (purchase.isEmpty) {
      throw BusinessRuleException('La compra ya fue revertida o no existe.');
    }
    final lots = await txn.rawQuery(
      'SELECT l.* FROM inventory_lots l JOIN purchase_items i ON i.id=l.purchase_item_id WHERE i.purchase_id=?',
      [purchaseId],
    );
    final allocationCharges = await txn.rawQuery(
      '''SELECT t.* FROM account_transactions t JOIN purchase_allocations a ON
      t.reference_type='PURCHASE_ALLOCATION' AND t.reference_id=a.id
      JOIN purchase_items i ON i.id=a.purchase_item_id
      WHERE i.purchase_id=?''',
      [purchaseId],
    );
    _session.requireOwnerInPersonal(
      context,
      [
        for (final lot in lots)
          if (lot['reversed_at'] == null) lot['owner_person_id']! as int,
        for (final charge in allocationCharges) charge['person_id']! as int,
      ],
      'En el modo individual sólo se revierten compras asignadas al titular. '
      'Para revertir una compra con asignaciones a otras personas, cambie '
      'al modo con varias personas.',
    );
    final now = _session.date(DateTime.now());
    for (final lot in lots) {
      await _reversePurchaseLot(txn, purchaseId, lot, now, reason, effects);
    }
    await _reversePurchaseChargesAndPayments(
      txn,
      purchaseId,
      allocationCharges,
      now,
      reason,
      effects,
    );
    await txn.update(
      'purchases',
      {'status': 'REVERSED', 'reversed_at': now},
      where: 'id=?',
      whereArgs: [purchaseId],
    );
    return (
      personId: null,
      effectiveDate: purchase.single['purchase_date'] as String?,
    );
  }

  Future<void> _reversePurchaseLot(
    Transaction txn,
    int purchaseId,
    Map<String, Object?> lot,
    String now,
    String? reason,
    ReversalEffects effects,
  ) async {
    final available =
        Sqflite.firstIntValue(
          await txn.rawQuery(
            'SELECT COALESCE(SUM(quantity_signed),0) FROM inventory_movements WHERE lot_id=?',
            [lot['id']],
          ),
        ) ??
        0;
    if (lot['reversed_at'] != null) {
      if (available != 0) {
        throw BusinessRuleException(
          'Un lote anulado de esta compra conserva saldo; revise sus '
          'movimientos antes de revertir.',
        );
      }
      return;
    }
    if (available != lot['initial_quantity_base']) {
      throw BusinessRuleException(
        'El lote fue transferido o ajustado; requiere reversión consistente previa.',
      );
    }
    effects.add(
      'inventory_movements',
      await txn.insert('inventory_movements', {
        'lot_id': lot['id'],
        'product_id': lot['product_id'],
        'owner_person_id': lot['owner_person_id'],
        'movement_date': now,
        'type': 'PURCHASE_REVERSAL',
        'quantity_signed': -available,
        'reference_type': 'PURCHASE_REVERSAL',
        'reference_id': purchaseId,
        'notes': reason,
      }),
    );
    await txn.update(
      'inventory_lots',
      {'reversed_at': now},
      where: 'id=?',
      whereArgs: [lot['id']],
    );
    effects.add('inventory_lots', lot['id']! as int);
  }

  Future<void> _reversePurchaseChargesAndPayments(
    Transaction txn,
    int purchaseId,
    List<Map<String, Object?>> allocationCharges,
    String now,
    String? reason,
    ReversalEffects effects,
  ) async {
    for (final charge in allocationCharges) {
      effects.add(
        'account_transactions',
        await txn.insert('account_transactions', {
          'person_id': charge['person_id'],
          'campaign_id': charge['campaign_id'],
          'transaction_date': now,
          'type': 'CREDIT_ADJUSTMENT',
          'amount_bob_minor_signed':
              -(charge['amount_bob_minor_signed']! as int),
          'reference_type': 'PURCHASE_REVERSAL',
          'reference_id': purchaseId,
          'notes': reason,
          'reversal_of_id': charge['id'],
        }),
      );
    }
    for (final payment in await txn.query(
      'provider_payments',
      columns: ['id'],
      where: 'purchase_id=? AND reversed_at IS NULL',
      whereArgs: [purchaseId],
    )) {
      effects.add('provider_payments', payment['id']! as int);
    }
    await txn.update(
      'provider_payments',
      {'reversed_at': now},
      where: 'purchase_id=? AND reversed_at IS NULL',
      whereArgs: [purchaseId],
    );
  }

  Future<OriginalOperation> reverseTransferIn(
    Transaction txn,
    WriteContext context,
    int transferId,
    String? reason,
    ReversalEffects effects,
  ) async {
    _session.rejectTransferInPersonal(context);
    final transfers = await txn.query(
      'transfers',
      where: "id=? AND status='CONFIRMED' AND reversed_at IS NULL",
      whereArgs: [transferId],
    );
    if (transfers.isEmpty) {
      throw BusinessRuleException(
        'La transferencia ya fue revertida o no existe.',
      );
    }
    final transfer = transfers.single;
    final items = await txn.rawQuery(
      '''SELECT i.*, source.product_id source_product_id,
      destination.product_id destination_product_id
      FROM transfer_lot_items i
      JOIN inventory_lots source ON source.id=i.source_lot_id
      JOIN inventory_lots destination ON destination.id=i.destination_lot_id
      WHERE i.transfer_id=? ORDER BY i.id''',
      [transferId],
    );
    await _ensureTransferDestinationsUntouched(txn, items);
    final reversedAt = _session.date(DateTime.now());
    for (final item in items) {
      await _reverseTransferItem(
        txn,
        transferId: transferId,
        transfer: transfer,
        item: item,
        reversedAt: reversedAt,
        reason: reason,
        effects: effects,
      );
    }
    await txn.update(
      'transfers',
      {'status': 'REVERSED', 'reversed_at': reversedAt},
      where: 'id=?',
      whereArgs: [transferId],
    );
    return (
      personId: transfer['from_person_id'] as int?,
      effectiveDate: transfer['transfer_date'] as String?,
    );
  }

  Future<void> _ensureTransferDestinationsUntouched(
    Transaction txn,
    List<Map<String, Object?>> items,
  ) async {
    for (final item in items) {
      final available =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COALESCE(SUM(quantity_signed),0) FROM inventory_movements WHERE lot_id=?',
              [item['destination_lot_id']],
            ),
          ) ??
          0;
      if (available != item['quantity_base']) {
        throw BusinessRuleException(
          'El stock transferido ya tuvo movimientos. Reviértalos antes de continuar.',
        );
      }
    }
  }

  Future<void> _reverseTransferItem(
    Transaction txn, {
    required int transferId,
    required Map<String, Object?> transfer,
    required Map<String, Object?> item,
    required String reversedAt,
    required String? reason,
    required ReversalEffects effects,
  }) async {
    final quantity = item['quantity_base']! as int;
    for (final movement in <Map<String, Object?>>[
      {
        'lot_id': item['source_lot_id'],
        'product_id': item['source_product_id'],
        'owner_person_id': transfer['from_person_id'],
        'quantity_signed': quantity,
        'type': 'TRANSFER_REVERSAL_IN',
      },
      {
        'lot_id': item['destination_lot_id'],
        'product_id': item['destination_product_id'],
        'owner_person_id': transfer['to_person_id'],
        'quantity_signed': -quantity,
        'type': 'TRANSFER_REVERSAL_OUT',
      },
    ]) {
      effects.add(
        'inventory_movements',
        await txn.insert('inventory_movements', {
          ...movement,
          'movement_date': reversedAt,
          'reference_type': 'TRANSFER_REVERSAL',
          'reference_id': transferId,
          'notes': reason,
        }),
      );
    }
    await txn.update(
      'inventory_lots',
      {'reversed_at': reversedAt},
      where: 'id=?',
      whereArgs: [item['destination_lot_id']],
    );
    effects.add('inventory_lots', item['destination_lot_id']! as int);
  }
}
