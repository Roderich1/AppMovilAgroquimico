import 'package:sqflite/sqflite.dart' show Transaction;

import '../../domain/models.dart';
import '../../domain/money.dart';
import 'repository_exceptions.dart';
import 'repository_session.dart';

/// Sub-repositorio de transferencias entre responsables (FIFO) y consulta de
/// existencias transferibles.
class TransferRepository {
  TransferRepository(this._session);

  final RepositorySession _session;

  Future<int> transferStock({
    required int sourceLotId,
    required int destinationPersonId,
    required int quantityBase,
    DateTime? date,
    String? notes,
  }) async {
    final source = await (await _session.db).query(
      'inventory_lots',
      columns: ['product_id', 'owner_person_id'],
      where: 'id=? AND reversed_at IS NULL',
      whereArgs: [sourceLotId],
    );
    if (source.isEmpty) {
      throw BusinessRuleException('El lote de origen no está activo.');
    }
    final transferId = await transferProductFifo(
      fromPersonId: source.single['owner_person_id']! as int,
      toPersonId: destinationPersonId,
      productId: source.single['product_id']! as int,
      quantityBase: quantityBase,
      date: date,
      notes: notes,
    );
    final item = await (await _session.db).query(
      'transfer_lot_items',
      columns: ['destination_lot_id'],
      where: 'transfer_id=?',
      whereArgs: [transferId],
      orderBy: 'id',
      limit: 1,
    );
    return item.single['destination_lot_id']! as int;
  }

  Future<int> transferProductFifo({
    required int fromPersonId,
    required int toPersonId,
    required int productId,
    required int quantityBase,
    DateTime? date,
    String? notes,
  }) => transferProductsFifo(
    fromPersonId: fromPersonId,
    toPersonId: toPersonId,
    items: [
      TransferItemDraft(productId: productId, quantityBase: quantityBase),
    ],
    date: date,
    notes: notes,
  );

  Future<int> transferProductsFifo({
    required int fromPersonId,
    required int toPersonId,
    required List<TransferItemDraft> items,
    DateTime? date,
    String? notes,
  }) async {
    if (fromPersonId == toPersonId) {
      throw BusinessRuleException(
        'El origen y el destino deben ser diferentes.',
      );
    }
    final validItems = items.where((item) => item.quantityBase > 0).toList();
    if (validItems.isEmpty) {
      throw BusinessRuleException(
        'Seleccione al menos un producto para transferir.',
      );
    }
    if (validItems.map((item) => item.productId).toSet().length !=
        validItems.length) {
      throw BusinessRuleException(
        'No repita productos dentro de la transferencia.',
      );
    }
    return _session.write((txn, context) async {
      _session.rejectTransferInPersonal(context);
      final movementDate = _session.date(date ?? DateTime.now());
      final transferId = await txn.insert('transfers', {
        'product_id': validItems.first.productId,
        'from_person_id': fromPersonId,
        'to_person_id': toPersonId,
        'transfer_date': movementDate,
        'quantity_base': validItems.first.quantityBase,
        'total_cost_bob_minor': 0,
        'notes': notes,
      });
      var transferCost = 0;
      for (final item in validItems) {
        transferCost += await _transferItemFifo(
          txn,
          transferId: transferId,
          fromPersonId: fromPersonId,
          toPersonId: toPersonId,
          item: item,
          movementDate: movementDate,
          notes: notes,
        );
      }
      await txn.update(
        'transfers',
        {'total_cost_bob_minor': transferCost},
        where: 'id=?',
        whereArgs: [transferId],
      );
      return transferId;
    });
  }

  Future<int> _transferItemFifo(
    Transaction txn, {
    required int transferId,
    required int fromPersonId,
    required int toPersonId,
    required TransferItemDraft item,
    required String movementDate,
    required String? notes,
  }) async {
    final lots = await txn.rawQuery(
      '''SELECT l.*, COALESCE(SUM(m.quantity_signed),0) available
      FROM inventory_lots l LEFT JOIN inventory_movements m ON m.lot_id=l.id
      WHERE l.owner_person_id=? AND l.product_id=? AND l.reversed_at IS NULL
      GROUP BY l.id HAVING available>0 ORDER BY l.acquired_date,l.id''',
      [fromPersonId, item.productId],
    );
    final available = lots.fold<int>(
      0,
      (sum, lot) => sum + (lot['available']! as int),
    );
    if (available < item.quantityBase) {
      throw BusinessRuleException(
        'Stock insuficiente en uno de los productos. No se transfirió ningún item.',
      );
    }
    final transferItemId = await txn.insert('transfer_items', {
      'transfer_id': transferId,
      'product_id': item.productId,
      'quantity_base': item.quantityBase,
      'total_cost_bob_minor': 0,
    });
    var remaining = item.quantityBase;
    var itemCost = 0;
    for (final source in lots) {
      if (remaining == 0) break;
      final lotAvailable = source['available']! as int;
      final take = remaining < lotAvailable ? remaining : lotAvailable;
      itemCost += await _recordLotTransfer(
        txn,
        transferId: transferId,
        transferItemId: transferItemId,
        fromPersonId: fromPersonId,
        toPersonId: toPersonId,
        productId: item.productId,
        source: source,
        take: take,
        movementDate: movementDate,
        notes: notes,
      );
      remaining -= take;
    }
    await txn.update(
      'transfer_items',
      {'total_cost_bob_minor': itemCost},
      where: 'id=?',
      whereArgs: [transferItemId],
    );
    return itemCost;
  }

  Future<int> _recordLotTransfer(
    Transaction txn, {
    required int transferId,
    required int transferItemId,
    required int fromPersonId,
    required int toPersonId,
    required int productId,
    required Map<String, Object?> source,
    required int take,
    required String movementDate,
    required String? notes,
  }) async {
    final cost = costForBaseQuantity(
      take,
      source['unit_cost_bob_minor_per_major_unit']! as int,
    );
    final destinationLotId = await txn.insert('inventory_lots', {
      'purchase_item_id': source['purchase_item_id'],
      'product_id': productId,
      'owner_person_id': toPersonId,
      'acquired_date': source['acquired_date'],
      'initial_quantity_base': take,
      'unit_cost_bob_minor_per_major_unit':
          source['unit_cost_bob_minor_per_major_unit'],
      'currency_code': source['currency_code'],
      'original_unit_price_minor': source['original_unit_price_minor'],
      'exchange_rate_scaled': source['exchange_rate_scaled'],
      'parent_lot_id': source['id'],
      'notes': notes,
      'expiry_date': source['expiry_date'],
      'lot_number': source['lot_number'],
    });
    for (final movement in <Map<String, Object?>>[
      {
        'lot_id': source['id'],
        'owner_person_id': fromPersonId,
        'quantity_signed': -take,
        'type': 'TRANSFER_OUT',
      },
      {
        'lot_id': destinationLotId,
        'owner_person_id': toPersonId,
        'quantity_signed': take,
        'type': 'TRANSFER_IN',
      },
    ]) {
      await txn.insert('inventory_movements', {
        ...movement,
        'product_id': productId,
        'movement_date': movementDate,
        'reference_type': 'TRANSFER',
        'reference_id': transferId,
        'notes': notes,
      });
    }
    await txn.insert('transfer_lot_items', {
      'transfer_id': transferId,
      'transfer_item_id': transferItemId,
      'source_lot_id': source['id'],
      'destination_lot_id': destinationLotId,
      'quantity_base': take,
      'cost_bob_minor': cost,
    });
    return cost;
  }

  Future<List<Map<String, Object?>>> transfers({int limit = 50}) async =>
      (await _session.db).rawQuery(
        '''SELECT t.*, pr.name product_name, pr.unit,
        source.name from_person_name, destination.name to_person_name,
        (SELECT COUNT(*) FROM transfer_lot_items i WHERE i.transfer_id=t.id) lot_count,
        COALESCE((SELECT COUNT(*) FROM transfer_items ti WHERE ti.transfer_id=t.id),1) item_count,
        COALESCE((SELECT GROUP_CONCAT(p.name || '|' || ti.quantity_base || '|' || p.unit, ';')
          FROM transfer_items ti JOIN products p ON p.id=ti.product_id WHERE ti.transfer_id=t.id),
          pr.name || '|' || t.quantity_base || '|' || pr.unit) products_summary
        FROM transfers t JOIN products pr ON pr.id=t.product_id
        JOIN persons source ON source.id=t.from_person_id
        JOIN persons destination ON destination.id=t.to_person_id
        ORDER BY t.transfer_date DESC, t.id DESC LIMIT ?''',
        [limit],
      );

  Future<List<Map<String, Object?>>> availableProductsForOwner(
    int personId, {
    String query = '',
    int limit = 100,
  }) async => (await _session.db).rawQuery(
    '''SELECT p.id product_id, p.name product_name, p.unit,
        SUM(m.quantity_signed) available_base, COUNT(DISTINCT l.id) lot_count,
        (SELECT fl.unit_cost_bob_minor_per_major_unit FROM inventory_lots fl
          JOIN inventory_movements fm ON fm.lot_id=fl.id
          WHERE fl.owner_person_id=? AND fl.product_id=p.id AND fl.reversed_at IS NULL
          GROUP BY fl.id HAVING SUM(fm.quantity_signed)>0 ORDER BY fl.acquired_date,fl.id LIMIT 1) next_fifo_cost_minor
        FROM products p JOIN inventory_movements m ON m.product_id=p.id AND m.owner_person_id=?
        JOIN inventory_lots l ON l.id=m.lot_id
        WHERE p.name LIKE ? GROUP BY p.id HAVING available_base>0
        ORDER BY p.name LIMIT ?''',
    [personId, personId, '%${query.trim()}%', limit],
  );
}
