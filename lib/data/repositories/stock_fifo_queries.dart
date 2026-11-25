import 'package:sqflite/sqflite.dart' show DatabaseExecutor;

import '../../domain/campaign_calendar.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import 'repository_exceptions.dart';

/// Consultas de elegibilidad de lotes presentes e históricas (D-03, RF-03 §2.3
/// y §2.6), compartidas entre aplicaciones ordinarias y operaciones tardías.
class StockFifoQueries {
  const StockFifoQueries();

  /// Rechazo de una aplicación con fecha pasada cuyo cupo histórico no
  /// alcanza (D-03), también cuando tampoco alcanza el saldo de hoy. Nombra
  /// el producto, el día y la existencia elegible, y distingue si ese día la
  /// persona no tenía el producto o si lo tenía y queda menos sin usar en
  /// operaciones posteriores. Sólo se lee en el camino del rechazo.
  Future<HistoricalStockException> historicalShortfall(
    DatabaseExecutor txn,
    ApplicationLineDraft line,
    int personId,
    int available,
    String day,
  ) async {
    final history = await lotHistoryAt(txn, line.productId, personId, day);
    // Lo que tenía al final de ese día, por lote; un saldo histórico
    // negativo (registros anteriores inconsistentes) cuenta como nada.
    final held = history.fold<int>(0, (sum, lot) {
      final atDay = lot['held']! as int;
      return sum + (atDay > 0 ? atDay : 0);
    });
    final product = (await txn.query(
      'products',
      columns: ['name', 'unit'],
      where: 'id=?',
      whereArgs: [line.productId],
      limit: 1,
    )).single;
    final unit = product['unit']! as String;
    final name = product['name']! as String;
    final when = displayDay(day);
    final asked = formatQuantity(line.quantityBase, unit);
    final String what;
    if (held <= 0) {
      what =
          '$name: el $when esa persona no tenía este producto; pidió $asked.';
    } else if (available == held) {
      what =
          '$name: el $when esa persona tenía ${formatQuantity(held, unit)}; '
          'pidió $asked.';
    } else {
      what =
          '$name: el $when esa persona tenía ${formatQuantity(held, unit)}; '
          'de eso quedan ${formatQuantity(available, unit)} sin usar en '
          'operaciones posteriores; pidió $asked.';
    }
    return HistoricalStockException(
      productId: line.productId,
      day: day,
      heldBase: held,
      availableBase: available,
      requestedBase: line.quantityBase,
      message:
          '$what Una aplicación con fecha pasada sólo puede usar lo que esa '
          'persona ya tenía ese día y no se usó después: no cuenta el producto '
          'comprado o recibido más tarde. Revise la fecha o la cantidad. No se '
          'registró nada.',
    );
  }

  /// Lotes con saldo hoy, en orden FIFO (registro ordinario).
  Future<List<Map<String, Object?>>> lotsAvailableNow(
    DatabaseExecutor txn,
    int productId,
    int personId,
  ) => txn.rawQuery(
    '''
          SELECT l.*, COALESCE(SUM(m.quantity_signed), 0) AS available
          FROM inventory_lots l JOIN inventory_movements m ON m.lot_id = l.id
          WHERE l.product_id = ? AND l.owner_person_id = ? AND l.reversed_at IS NULL
          GROUP BY l.id HAVING available > 0 ORDER BY l.acquired_date, l.id
        ''',
    [productId, personId],
  );

  /// Lotes elegibles para una aplicación del día [day] y su cupo temporal
  /// (§2.3, I1 de B; §2.6 para D-03): adquiridos ese día o antes, no
  /// anulados; el cupo es el mínimo del saldo al final del día efectivo y al
  /// final de cada día posterior con movimientos, ordenando por día efectivo
  /// y después por id. La aplicación va al final de su día. Lo usan la
  /// operación tardía (`confirmLateOperation`) y la aplicación ordinaria con
  /// fecha pasada (`confirmApplication`, D-03), sobre la misma proyección
  /// corregida por anulaciones demostradas. Sólo lotes con cupo positivo.
  Future<List<Map<String, Object?>>> lotsAvailableAt(
    DatabaseExecutor txn,
    int productId,
    int personId,
    String day,
  ) async => [
    for (final lot in await lotHistoryAt(txn, productId, personId, day))
      if ((lot['available']! as int) > 0) lot,
  ];

  /// Cada lote adquirido el día [day] o antes, con `held` (saldo al final de
  /// ese día) y `available` (su cupo, que puede ser cero o negativo), sobre
  /// la proyección histórica corregida (§2.6): los pares de anulación
  /// demostrados ([_demonstratedAnnulments]) no cuentan, y el cupo nunca
  /// supera el saldo actual del lote. La base no cambia.
  Future<List<Map<String, Object?>>> lotHistoryAt(
    DatabaseExecutor txn,
    int productId,
    int personId,
    String day,
  ) async {
    final lots = await txn.query(
      'inventory_lots',
      where: 'product_id=? AND owner_person_id=? AND reversed_at IS NULL',
      whereArgs: [productId, personId],
      orderBy: 'acquired_date, id',
    );
    final eligible = <Map<String, Object?>>[];
    for (final lot in lots) {
      if (storedLocalDay(lot['acquired_date']! as String).compareTo(day) > 0) {
        continue;
      }
      final movements = await txn.query(
        'inventory_movements',
        columns: [
          'id',
          'movement_date',
          'quantity_signed',
          'type',
          'reference_type',
          'reference_id',
        ],
        where: 'lot_id=?',
        whereArgs: [lot['id']],
      );
      final current = movements.fold<int>(
        0,
        (sum, m) => sum + (m['quantity_signed']! as int),
      );
      final neutral = await _demonstratedAnnulments(
        txn,
        lot['id']! as int,
        movements,
      );
      final ordered =
          movements
              .where((m) => !neutral.contains(m['id']))
              .map(
                (m) => (
                  day: storedLocalDay(m['movement_date']! as String),
                  id: m['id']! as int,
                  quantity: m['quantity_signed']! as int,
                ),
              )
              .toList()
            ..sort((a, b) {
              final byDay = a.day.compareTo(b.day);
              return byDay != 0 ? byDay : a.id.compareTo(b.id);
            });
      // Saldo acumulado al final del día efectivo (todo lo de días ≤ day) y
      // mínimo del saldo al final de cada día posterior con movimientos.
      var balance = 0;
      var atDay = 0;
      int? laterMin;
      for (var i = 0; i < ordered.length; i++) {
        balance += ordered[i].quantity;
        final endOfDay =
            i == ordered.length - 1 || ordered[i + 1].day != ordered[i].day;
        if (!endOfDay) continue;
        if (ordered[i].day.compareTo(day) <= 0) {
          atDay = balance;
        } else {
          laterMin = laterMin == null || balance < laterMin
              ? balance
              : laterMin;
        }
      }
      var cap = laterMin == null || atDay < laterMin ? atDay : laterMin;
      // Tope del saldo de hoy, defensivo e inalcanzable con datos válidos: un
      // par neutralizado suma cero, así que el saldo corregido al final del
      // último día coincide con el actual y el mínimo de los saldos
      // posteriores ya lo acota. Se deja por si un dato inconsistente rompe
      // esa igualdad.
      if (cap > current) cap = current;
      eligible.add({...lot, 'held': atDay, 'available': cap});
    }
    return eligible;
  }

  /// Pares de anulación **demostrados** del lote [lotId] (D-03, decisión del
  /// autor del 2026-10-28; contrato §2.6): ids de los movimientos que la
  /// proyección histórica trata como si no hubieran existido. La bitácora
  /// conserva la operación, la reversión y sus fechas reales; aquí sólo se
  /// leen.
  Future<Set<int>> _demonstratedAnnulments(
    DatabaseExecutor txn,
    int lotId,
    List<Map<String, Object?>> movements,
  ) async {
    const kinds = [
      (
        out: 'APPLICATION_OUT',
        outRef: 'APPLICATION',
        back: 'APPLICATION_REVERSAL',
        backRef: 'APPLICATION_REVERSAL',
        operation: 'APPLICATION',
      ),
      (
        out: 'TRANSFER_OUT',
        outRef: 'TRANSFER',
        back: 'TRANSFER_REVERSAL_IN',
        backRef: 'TRANSFER_REVERSAL',
        operation: 'TRANSFER',
      ),
    ];
    final neutral = <int>{};
    for (final kind in kinds) {
      bool isBack(Map<String, Object?> m) =>
          m['type'] == kind.back && m['reference_type'] == kind.backRef;
      final operations = {
        for (final m in movements)
          if (isBack(m) && m['reference_id'] is int) m['reference_id']! as int,
      };
      for (final operation in operations) {
        final outs = [
          for (final m in movements)
            if (m['type'] == kind.out &&
                m['reference_type'] == kind.outRef &&
                m['reference_id'] == operation)
              m,
        ];
        final backs = [
          for (final m in movements)
            if (isBack(m) && m['reference_id'] == operation) m,
        ];
        if (outs.length != 1 || backs.length != 1) continue;
        final quantity = backs.single['quantity_signed']! as int;
        if (quantity <= 0 || outs.single['quantity_signed'] != -quantity) {
          continue;
        }
        final backId = backs.single['id']! as int;
        if (!await _annulmentRecorded(
          txn,
          kind.operation,
          operation,
          lotId,
          quantity,
          backId,
        )) {
          continue;
        }
        neutral
          ..add(outs.single['id']! as int)
          ..add(backId);
      }
    }
    return neutral;
  }

  /// La operación consta como revertida en este lote por [quantity], y la
  /// auditoría de RF-13, si existe, nombra el movimiento [reversalMovementId].
  Future<bool> _annulmentRecorded(
    DatabaseExecutor txn,
    String operationType,
    int operationId,
    int lotId,
    int quantity,
    int reversalMovementId,
  ) async {
    if (operationType == 'APPLICATION') {
      final application = await txn.query(
        'applications',
        columns: ['status', 'reversed_at'],
        where: 'id=?',
        whereArgs: [operationId],
      );
      if (application.length != 1 ||
          application.single['reversed_at'] == null ||
          application.single['status'] != 'REVERSED') {
        return false;
      }
      final consumptions = await txn.rawQuery(
        '''SELECT c.quantity_consumed_base q, c.reversed_at r
        FROM application_consumptions c
        JOIN application_items i ON i.id=c.application_item_id
        WHERE i.application_id=? AND c.inventory_lot_id=?''',
        [operationId, lotId],
      );
      if (consumptions.length != 1 ||
          consumptions.single['r'] == null ||
          consumptions.single['q'] != quantity) {
        return false;
      }
    } else {
      final transfer = await txn.query(
        'transfers',
        columns: ['status', 'reversed_at'],
        where: 'id=?',
        whereArgs: [operationId],
      );
      if (transfer.length != 1 ||
          transfer.single['reversed_at'] == null ||
          transfer.single['status'] != 'REVERSED') {
        return false;
      }
      final items = await txn.rawQuery(
        '''SELECT i.quantity_base q, d.reversed_at r FROM transfer_lot_items i
        JOIN inventory_lots d ON d.id=i.destination_lot_id
        WHERE i.transfer_id=? AND i.source_lot_id=?''',
        [operationId, lotId],
      );
      if (items.length != 1 ||
          items.single['r'] == null ||
          items.single['q'] != quantity) {
        return false;
      }
    }
    final audit = await txn.query(
      'reversal_audit',
      columns: ['id'],
      where: 'operation_type=? AND operation_id=?',
      whereArgs: [operationType, operationId],
    );
    if (audit.isEmpty) return true;
    final named = await txn.query(
      'reversal_audit_effects',
      columns: ['id'],
      where: "audit_id=? AND table_name='inventory_movements' AND row_id=?",
      whereArgs: [audit.single['id'], reversalMovementId],
    );
    return named.length == 1;
  }
}
