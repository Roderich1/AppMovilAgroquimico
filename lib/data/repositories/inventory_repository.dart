import 'package:sqflite/sqflite.dart' show Sqflite, Transaction;

import '../../domain/inventory_alerts.dart';
import '../../services/auth/local_owner_credential.dart';
import 'inventory_queries.dart';
import 'repository_exceptions.dart';
import 'repository_session.dart';
import 'repository_types.dart';

/// Sub-repositorio de existencias, lotes, corrección auditada de vencimiento/lote
/// y configuración de avisos F04-AV.
class InventoryRepository {
  InventoryRepository(this._session) : _queries = InventoryQueries(_session);

  final RepositorySession _session;
  final InventoryQueries _queries;

  /// Referencia que firma la autorización de una corrección.
  static String lotDataSubjectRef(int purchaseItemId) =>
      'purchase_item:$purchaseItemId';

  /// Referencia que firma la autorización de la configuración de avisos.
  static String productAlertsSubjectRef(int productId) =>
      'product_alerts:$productId';

  static const String _provenLotsSql = '''WITH RECURSIVE proven(id) AS (
      SELECT l.id FROM inventory_lots l
      WHERE l.purchase_item_id=?1 AND l.parent_lot_id IS NULL
        AND EXISTS (SELECT 1 FROM inventory_movements m
          JOIN purchase_allocations a ON a.id=m.reference_id
          WHERE m.lot_id=l.id AND m.type='PURCHASE_IN'
            AND m.reference_type='PURCHASE_ALLOCATION' AND a.purchase_item_id=?1)
      UNION
      SELECT l.id FROM inventory_lots l JOIN proven p ON l.parent_lot_id=p.id
      WHERE l.purchase_item_id=?1
        AND EXISTS (SELECT 1 FROM transfer_lot_items t
          WHERE t.source_lot_id=p.id AND t.destination_lot_id=l.id))
    SELECT id FROM proven ORDER BY id''';

  Future<List<Map<String, Object?>>> stock() => _queries.stock();

  Future<List<Map<String, Object?>>> inventorySummary({int? limit}) =>
      _queries.inventorySummary(limit: limit);

  Future<List<Map<String, Object?>>> personStockSummary(int personId) =>
      _queries.personStockSummary(personId);

  Future<Map<String, Object?>> inventoryProductHeader(int productId) =>
      _queries.inventoryProductHeader(productId);

  Future<List<Map<String, Object?>>> inventoryProductDistribution(
    int productId,
  ) => _queries.inventoryProductDistribution(productId);

  Future<InventoryAlerts> inventoryAlerts({DateTime? now}) =>
      _queries.inventoryAlerts(now: now);

  Future<List<Map<String, Object?>>> inventoryProductLots(
    int productId, {
    int? personId,
    int? supplierId,
    int? campaignId,
  }) => _queries.inventoryProductLots(
    productId,
    personId: personId,
    supplierId: supplierId,
    campaignId: campaignId,
  );

  Future<List<Map<String, Object?>>> productMovements(
    int productId, {
    int limit = 20,
  }) => _queries.productMovements(productId, limit: limit);

  /// Si se puede corregir la línea: existe y su compra no está revertida.
  Future<bool> canCorrectLotData(int purchaseItemId) async {
    final rows = await (await _session.db).rawQuery(
      '''SELECT p.status, p.reversed_at FROM purchase_items i
      JOIN purchases p ON p.id=i.purchase_id WHERE i.id=?''',
      [purchaseItemId],
    );
    return rows.isNotEmpty &&
        rows.single['status'] != 'REVERSED' &&
        rows.single['reversed_at'] == null;
  }

  /// Corrige el vencimiento y el número de lote de una línea de compra (RF-42).
  Future<LotDataCorrectionResult> correctLotData(
    int purchaseItemId, {
    required String? expiryDay,
    required String? lotNumber,
    required String reason,
    required OwnerAuthorization authorization,
  }) async {
    checkRepositoryExpiryDay(expiryDay);
    final number = normalizeRepositoryLotNumber(lotNumber);
    final note = reason.trim();
    if (note.isEmpty) {
      throw BusinessRuleException('Indique el motivo de la corrección.');
    }
    return _session.writeAuthorized((txn, consume) async {
      await _ensureCorrectablePurchaseItem(txn, purchaseItemId);
      final proven = [
        for (final row in await txn.rawQuery(_provenLotsSql, [purchaseItemId]))
          row['id']! as int,
      ];
      if (proven.isEmpty) {
        throw BusinessRuleException(
          'No se pudo demostrar la procedencia de ningún lote de esta línea: '
          'no se corrige nada.',
        );
      }
      final first = (await txn.query(
        'inventory_lots',
        columns: ['expiry_date', 'lot_number'],
        where: 'id=?',
        whereArgs: [proven.first],
      )).single;
      final previousExpiry = first['expiry_date'] as String?;
      final previousNumber = first['lot_number'] as String?;
      if (previousExpiry == expiryDay && previousNumber == number) {
        throw BusinessRuleException('No hay cambios que guardar.');
      }
      await consume(
        authorization,
        AuthorizationPurpose.correctLotData,
        lotDataSubjectRef(purchaseItemId),
      );
      return _applyLotDataCorrection(
        txn,
        purchaseItemId: purchaseItemId,
        proven: proven,
        previousExpiry: previousExpiry,
        previousNumber: previousNumber,
        expiryDay: expiryDay,
        number: number,
        note: note,
        authorization: authorization,
      );
    });
  }

  Future<void> _ensureCorrectablePurchaseItem(
    Transaction txn,
    int purchaseItemId,
  ) async {
    final purchase = await txn.rawQuery(
      '''SELECT p.status, p.reversed_at FROM purchase_items i
      JOIN purchases p ON p.id=i.purchase_id WHERE i.id=?''',
      [purchaseItemId],
    );
    if (purchase.isEmpty) {
      throw BusinessRuleException('La línea de compra no existe.');
    }
    if (purchase.single['status'] == 'REVERSED' ||
        purchase.single['reversed_at'] != null) {
      throw BusinessRuleException(
        'La compra está revertida: se puede consultar, pero no corregir.',
      );
    }
  }

  Future<LotDataCorrectionResult> _applyLotDataCorrection(
    Transaction txn, {
    required int purchaseItemId,
    required List<int> proven,
    required String? previousExpiry,
    required String? previousNumber,
    required String? expiryDay,
    required String? number,
    required String note,
    required OwnerAuthorization authorization,
  }) async {
    final allLots =
        Sqflite.firstIntValue(
          await txn.rawQuery(
            'SELECT COUNT(*) FROM inventory_lots WHERE purchase_item_id=?',
            [purchaseItemId],
          ),
        ) ??
        0;
    final correctionId = await txn.insert('lot_data_corrections', {
      'purchase_item_id': purchaseItemId,
      'previous_expiry_date': previousExpiry,
      'previous_lot_number': previousNumber,
      'new_expiry_date': expiryDay,
      'new_lot_number': number,
      'reason': note,
      'actor_person_id': authorization.personId,
      'actor_binding_id': authorization.bindingId,
      'actor_member_id': authorization.scope.memberId,
      'actor_tenant_id': authorization.scope.tenantId,
      'actor_method': authorization.method,
      'credential_enrolment_ref': authorization.enrolmentId,
      'unproven_lot_count': allLots - proven.length,
      'recorded_at': _session.date(DateTime.now()),
    });
    for (final lotId in proven) {
      await txn.update(
        'inventory_lots',
        {'expiry_date': expiryDay, 'lot_number': number},
        where: 'id=?',
        whereArgs: [lotId],
      );
      await txn.insert('lot_data_correction_lots', {
        'correction_id': correctionId,
        'lot_id': lotId,
      });
    }
    return LotDataCorrectionResult(
      correctionId: correctionId,
      correctedLots: proven.length,
      unprovenLots: allLots - proven.length,
    );
  }

  /// Sólo pruebas: la corrección sin autorización, para preparar datos.
  Future<void> setLotDataUnauditedForTesting(
    int lotId, {
    String? expiryDay,
    String? lotNumber,
  }) => _session.write(
    (txn, _) => txn.update(
      'inventory_lots',
      {'expiry_date': expiryDay, 'lot_number': lotNumber},
      where: 'id=?',
      whereArgs: [lotId],
    ),
  );

  /// Correcciones de una línea de compra, de la más reciente a la más antigua.
  Future<List<Map<String, Object?>>> lotDataCorrections(
    int purchaseItemId,
  ) async => (await _session.db).rawQuery(
    '''SELECT c.*, pe.name actor_name,
    (SELECT COUNT(*) FROM lot_data_correction_lots x WHERE x.correction_id=c.id) lot_count
    FROM lot_data_corrections c JOIN persons pe ON pe.id=c.actor_person_id
    WHERE c.purchase_item_id=? ORDER BY c.id DESC''',
    [purchaseItemId],
  );

  void _checkAlertSettings(int? minStockBase, int? leadDays) {
    if (minStockBase != null && minStockBase < 0) {
      throw BusinessRuleException('El nivel mínimo no puede ser negativo.');
    }
    if (leadDays != null &&
        (leadDays < 0 || leadDays > repositoryMaxAlertLeadDays)) {
      throw BusinessRuleException(
        'El plazo de aviso debe ser un número entero de días, de 0 a '
        '$repositoryMaxAlertLeadDays.',
      );
    }
  }

  /// Nivel mínimo (unidad base) y plazo de aviso (días) de un producto (RF-44).
  Future<void> setProductAlertSettings(
    int productId, {
    required int? minStockBase,
    required int? leadDays,
    required OwnerAuthorization authorization,
  }) async {
    _checkAlertSettings(minStockBase, leadDays);
    await _session.writeAuthorized((txn, consume) async {
      final rows = await txn.query(
        'products',
        columns: ['min_stock_base', 'alert_lead_days'],
        where: 'id=?',
        whereArgs: [productId],
      );
      if (rows.isEmpty) throw BusinessRuleException('El producto no existe.');
      if (rows.single['min_stock_base'] == minStockBase &&
          rows.single['alert_lead_days'] == leadDays) {
        throw BusinessRuleException('No hay cambios que guardar.');
      }
      await consume(
        authorization,
        AuthorizationPurpose.configureProductAlerts,
        productAlertsSubjectRef(productId),
      );
      await txn.update(
        'products',
        {'min_stock_base': minStockBase, 'alert_lead_days': leadDays},
        where: 'id=?',
        whereArgs: [productId],
      );
    });
  }

  /// Sólo pruebas y siembras sintéticas: la configuración sin PIN.
  Future<void> setProductAlertSettingsWithoutPinForTesting(
    int productId, {
    required int? minStockBase,
    required int? leadDays,
  }) async {
    _checkAlertSettings(minStockBase, leadDays);
    await _session.write((txn, _) async {
      final changed = await txn.update(
        'products',
        {'min_stock_base': minStockBase, 'alert_lead_days': leadDays},
        where: 'id=?',
        whereArgs: [productId],
      );
      if (changed == 0) {
        throw BusinessRuleException('El producto no existe.');
      }
    });
  }

  /// Configuración de avisos de un producto.
  Future<ProductAlertSettings> productAlertSettings(int productId) async {
    final rows = await (await _session.db).query(
      'products',
      columns: InventoryQueries.alertSettingsColumns,
      where: 'id=?',
      whereArgs: [productId],
    );
    if (rows.isEmpty) throw BusinessRuleException('El producto no existe.');
    return InventoryQueries.alertSettingsOf(rows.single);
  }
}
