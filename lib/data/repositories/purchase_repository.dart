import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' show Sqflite, Transaction;

import '../../domain/campaign_calendar.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../invoice_storage.dart';
import 'campaign_repository.dart';
import 'repository_exceptions.dart';
import 'repository_session.dart';
import 'repository_types.dart';

/// Sub-repositorio de compras, asignaciones iniciales por lote, pagos a
/// proveedores y respaldo de fotografías de factura.
class PurchaseRepository {
  PurchaseRepository(this._session, this._campaigns);

  final RepositorySession _session;
  final CampaignRepository _campaigns;

  /// Confirma la compra y, con [paidInFull], registra en la **misma
  /// transacción** el pago del total al proveedor a nombre del titular vigente.
  Future<int> confirmPurchase(
    PurchaseDraft draft, {
    ProviderPaymentDetails? paidInFull,
  }) async {
    final purchaseTotal = validatePurchaseDraft(draft);
    final payment = paidInFull;
    return _session.write((txn, context) async {
      _session.requireOwnerInPersonal(context, [
        for (final item in draft.items)
          for (final allocation in item.allocations) allocation.personId,
      ], 'En el modo individual la compra se asigna sólo al titular.');
      final payer = payment == null ? null : _requireOwnerPayer(context);
      await _campaigns.ensureCampaignActive(txn, draft.campaignId);
      await _campaigns.ensureEffectiveDateInCampaign(
        txn,
        draft.campaignId,
        draft.purchaseDate,
      );
      final purchaseId = await insertPurchase(txn, draft, purchaseTotal);
      if (payer != null && payment != null) {
        await _insertProviderPayment(
          txn,
          purchaseId: purchaseId,
          payerPersonId: payer,
          amountBobMinor: purchaseTotal,
          method: payment.method,
          date: payment.date,
        );
      }
      return purchaseId;
    });
  }

  /// El pago al proveedor lo registra el **titular vigente** de la instalación.
  int _requireOwnerPayer(WriteContext context, {int? payerPersonId}) {
    final owner = context.ownerPersonId;
    if (owner == null) {
      throw BusinessRuleException(
        'Para registrar el pago al proveedor, la instalación necesita un '
        'titular vinculado.',
      );
    }
    if (payerPersonId != null && payerPersonId != owner) {
      throw BusinessRuleException(
        'El pago al proveedor lo registra el titular vigente, no otra persona.',
      );
    }
    return owner;
  }

  /// Validaciones de una compra que no dependen de la base. Devuelve el total.
  int validatePurchaseDraft(PurchaseDraft draft) {
    if (draft.items.isEmpty) {
      throw BusinessRuleException('La compra necesita al menos un producto.');
    }
    if (draft.items.map((item) => item.productId).toSet().length !=
        draft.items.length) {
      throw BusinessRuleException('No repita productos dentro de la compra.');
    }
    var purchaseTotal = 0;
    for (final item in draft.items) {
      _validatePurchaseItem(item);
      purchaseTotal += subtotalMinor(
        quantityBase: item.quantityBase,
        unitPriceMinor: item.originalUnitPriceMinor,
        fxScaled: item.exchangeRateScaled,
      );
    }
    return purchaseTotal;
  }

  void _validatePurchaseItem(PurchaseItemDraft item) {
    if (item.quantityBase <= 0 || item.originalUnitPriceMinor <= 0) {
      throw BusinessRuleException(
        'Cantidad y precio deben ser mayores a cero.',
      );
    }
    if (item.currency == CurrencyCode.usd &&
        (item.exchangeRateScaled ?? 0) <= 0) {
      throw BusinessRuleException('Una compra en USD requiere tipo de cambio.');
    }
    if (item.currency == CurrencyCode.bob && item.exchangeRateScaled != null) {
      throw BusinessRuleException(
        'Una compra en BOB no debe guardar tipo de cambio.',
      );
    }
    final allocated = item.allocations.fold<int>(
      0,
      (sum, value) => sum + value.quantityBase,
    );
    if (allocated != item.quantityBase) {
      throw BusinessRuleException(
        'La cantidad asignada debe coincidir con la cantidad comprada.',
      );
    }
    checkRepositoryExpiryDay(item.expiryDay);
    if (item.lotNumber != null &&
        normalizeRepositoryLotNumber(item.lotNumber) != item.lotNumber) {
      throw BusinessRuleException(
        'El número de lote no puede quedar vacío ni empezar o terminar con '
        'espacios.',
      );
    }
  }

  /// Escribe una compra ya validada en [draft.campaignId].
  Future<int> insertPurchase(
    Transaction txn,
    PurchaseDraft draft,
    int purchaseTotal,
  ) async {
    final purchaseId = await txn.insert('purchases', {
      'supplier_id': draft.supplierId,
      'campaign_id': draft.campaignId,
      'purchase_date': _session.date(draft.purchaseDate),
      'invoice_number': draft.invoiceNumber,
      'default_currency_code': draft.items.first.currency.code,
      'default_exchange_rate_scaled': draft.items.first.exchangeRateScaled,
      'exchange_rate_source': draft.exchangeRateSource?.code,
      'exchange_rate_note': draft.exchangeRateNote,
      'total_bob_minor': purchaseTotal,
      'status': 'CONFIRMED',
      'notes': draft.notes,
      'invoice_image_path': draft.invoiceImagePath,
    });
    for (final item in draft.items) {
      await _insertPurchaseItem(txn, purchaseId, draft, item);
    }
    return purchaseId;
  }

  Future<void> _insertPurchaseItem(
    Transaction txn,
    int purchaseId,
    PurchaseDraft draft,
    PurchaseItemDraft item,
  ) async {
    final unitBob = convertedUnitPriceBobMinor(
      item.originalUnitPriceMinor,
      item.exchangeRateScaled,
    );
    final originalSubtotal = divideRoundedHalfUp(
      item.quantityBase * item.originalUnitPriceMinor,
      baseUnitsPerMajor,
    );
    final bobSubtotal = subtotalMinor(
      quantityBase: item.quantityBase,
      unitPriceMinor: item.originalUnitPriceMinor,
      fxScaled: item.exchangeRateScaled,
    );
    final purchaseItemId = await txn.insert('purchase_items', {
      'purchase_id': purchaseId,
      'product_id': item.productId,
      'quantity_base': item.quantityBase,
      'currency_code': item.currency.code,
      'original_unit_price_minor': item.originalUnitPriceMinor,
      'exchange_rate_scaled': item.exchangeRateScaled,
      'converted_unit_price_bob_minor': unitBob,
      'original_subtotal_minor': originalSubtotal,
      'subtotal_bob_minor': bobSubtotal,
    });
    for (final allocation in item.allocations) {
      await _insertAllocationLot(
        txn,
        purchaseItemId,
        draft,
        item,
        allocation,
        unitBob,
      );
    }
  }

  Future<void> _insertAllocationLot(
    Transaction txn,
    int purchaseItemId,
    PurchaseDraft draft,
    PurchaseItemDraft item,
    AllocationDraft allocation,
    int unitBob,
  ) async {
    final person = (await txn.query(
      'persons',
      where: 'id = ?',
      whereArgs: [allocation.personId],
      limit: 1,
    )).single;
    final policy = person['settlement_policy']! as String;
    final allocationCost = costForBaseQuantity(
      allocation.quantityBase,
      unitBob,
    );
    final allocationId = await txn.insert('purchase_allocations', {
      'purchase_item_id': purchaseItemId,
      'person_id': allocation.personId,
      'quantity_base': allocation.quantityBase,
      'charge_policy_snapshot': policy,
      'amount_bob_minor_if_allocation_charge':
          policy == 'BY_PURCHASE_ALLOCATION' ? allocationCost : null,
    });
    final lotId = await txn.insert('inventory_lots', {
      'purchase_item_id': purchaseItemId,
      'product_id': item.productId,
      'owner_person_id': allocation.personId,
      'acquired_date': _session.date(draft.purchaseDate),
      'initial_quantity_base': allocation.quantityBase,
      'unit_cost_bob_minor_per_major_unit': unitBob,
      'currency_code': item.currency.code,
      'original_unit_price_minor': item.originalUnitPriceMinor,
      'exchange_rate_scaled': item.exchangeRateScaled,
      'expiry_date': item.expiryDay,
      'lot_number': item.lotNumber,
    });
    await txn.insert('inventory_movements', {
      'lot_id': lotId,
      'product_id': item.productId,
      'owner_person_id': allocation.personId,
      'movement_date': _session.date(draft.purchaseDate),
      'type': 'PURCHASE_IN',
      'quantity_signed': allocation.quantityBase,
      'reference_type': 'PURCHASE_ALLOCATION',
      'reference_id': allocationId,
    });
    if (policy == 'BY_PURCHASE_ALLOCATION') {
      await txn.insert('account_transactions', {
        'person_id': allocation.personId,
        'campaign_id': draft.campaignId,
        'transaction_date': _session.date(draft.purchaseDate),
        'type': 'PURCHASE_ALLOCATION_CHARGE',
        'amount_bob_minor_signed': allocationCost,
        'reference_type': 'PURCHASE_ALLOCATION',
        'reference_id': allocationId,
      });
    }
  }

  /// Pago posterior al proveedor.
  Future<int> addProviderPayment({
    required int purchaseId,
    required int payerPersonId,
    required int amountBobMinor,
    required PaymentMethod method,
    DateTime? date,
  }) async {
    if (amountBobMinor <= 0) {
      throw BusinessRuleException('El pago debe ser mayor a cero.');
    }
    return _session.write((txn, context) async {
      _session.requireOwnerInPersonal(context, [
        payerPersonId,
      ], 'En el modo individual el pago al proveedor lo registra el titular.');
      _requireOwnerPayer(context, payerPersonId: payerPersonId);
      return _insertProviderPayment(
        txn,
        purchaseId: purchaseId,
        payerPersonId: payerPersonId,
        amountBobMinor: amountBobMinor,
        method: method,
        date: date ?? DateTime.now(),
      );
    });
  }

  Future<int> _insertProviderPayment(
    Transaction txn, {
    required int purchaseId,
    required int payerPersonId,
    required int amountBobMinor,
    required PaymentMethod method,
    required DateTime date,
  }) async {
    final purchase = await txn.query(
      'purchases',
      where: 'id = ? AND reversed_at IS NULL',
      whereArgs: [purchaseId],
      limit: 1,
    );
    if (purchase.isEmpty) {
      throw BusinessRuleException('La compra no está activa.');
    }
    final day = localDay(date);
    final today = localDay(DateTime.now());
    if (day.compareTo(today) > 0) {
      throw BusinessRuleException(
        'La fecha del pago (${displayDay(day)}) es posterior a hoy '
        '(${displayDay(today)}). Un pago ya hecho no puede tener una fecha '
        'futura. No se registró nada.',
      );
    }
    final paid =
        Sqflite.firstIntValue(
          await txn.rawQuery(
            'SELECT COALESCE(SUM(amount_bob_minor),0) FROM provider_payments WHERE purchase_id = ? AND reversed_at IS NULL',
            [purchaseId],
          ),
        ) ??
        0;
    final total = purchase.single['total_bob_minor']! as int;
    if (paid + amountBobMinor > total) {
      throw BusinessRuleException('El pago supera el saldo de la compra.');
    }
    return txn.insert('provider_payments', {
      'purchase_id': purchaseId,
      'payer_person_id': payerPersonId,
      'payment_date': _session.date(date),
      'amount_bob_minor': amountBobMinor,
      'method': method.code,
    });
  }

  Future<List<Map<String, Object?>>> purchases({int limit = 200}) async =>
      (await _session.db).rawQuery(
        '''SELECT p.*, s.name supplier_name, c.name campaign_name,
    COALESCE((SELECT SUM(amount_bob_minor) FROM provider_payments pp WHERE pp.purchase_id=p.id AND pp.reversed_at IS NULL),0) paid_bob_minor,
    (SELECT COUNT(*) FROM purchase_items i WHERE i.purchase_id=p.id) item_count
    FROM purchases p JOIN suppliers s ON s.id=p.supplier_id
    JOIN campaigns c ON c.id=p.campaign_id ORDER BY purchase_date DESC LIMIT ?''',
        [limit],
      );

  /// Detalle de una compra tal como está guardada (A2).
  Future<PurchaseDetailRead?> purchaseDetail(int purchaseId) async {
    final db = await _session.db;
    final header = await db.rawQuery(
      '''SELECT p.*, s.name supplier_name, c.name campaign_name
      FROM purchases p JOIN suppliers s ON s.id=p.supplier_id
      JOIN campaigns c ON c.id=p.campaign_id WHERE p.id=?''',
      [purchaseId],
    );
    if (header.isEmpty) return null;
    return (
      purchase: header.single,
      items: await db.rawQuery(
        '''SELECT i.*, pr.name product_name, pr.unit,
        (SELECT l.expiry_date FROM inventory_lots l WHERE l.purchase_item_id=i.id
          AND l.parent_lot_id IS NULL AND EXISTS (SELECT 1 FROM inventory_movements m
          JOIN purchase_allocations a ON a.id=m.reference_id WHERE m.lot_id=l.id
          AND m.type='PURCHASE_IN' AND m.reference_type='PURCHASE_ALLOCATION'
          AND a.purchase_item_id=i.id) ORDER BY l.id LIMIT 1) expiry_date,
        (SELECT l.lot_number FROM inventory_lots l WHERE l.purchase_item_id=i.id
          AND l.parent_lot_id IS NULL AND EXISTS (SELECT 1 FROM inventory_movements m
          JOIN purchase_allocations a ON a.id=m.reference_id WHERE m.lot_id=l.id
          AND m.type='PURCHASE_IN' AND m.reference_type='PURCHASE_ALLOCATION'
          AND a.purchase_item_id=i.id) ORDER BY l.id LIMIT 1) lot_number,
        (SELECT COUNT(*) FROM lot_data_corrections c
          WHERE c.purchase_item_id=i.id) lot_data_corrections
        FROM purchase_items i JOIN products pr ON pr.id=i.product_id
        WHERE i.purchase_id=? ORDER BY i.id''',
        [purchaseId],
      ),
      allocations: await db.rawQuery(
        '''SELECT a.*, pe.name person_name
        FROM purchase_allocations a
        JOIN purchase_items i ON i.id=a.purchase_item_id
        JOIN persons pe ON pe.id=a.person_id
        WHERE i.purchase_id=? ORDER BY a.purchase_item_id, a.id''',
        [purchaseId],
      ),
      payments: await db.rawQuery(
        '''SELECT pp.*, pe.name payer_name
        FROM provider_payments pp JOIN persons pe ON pe.id=pp.payer_person_id
        WHERE pp.purchase_id=? ORDER BY pp.payment_date, pp.id''',
        [purchaseId],
      ),
    );
  }

  /// Sólo copia un archivo: basta la compuerta, no hay contexto de modalidad.
  Future<String> storeInvoiceImage(String sourcePath) =>
      _session.appDatabase.replacement.write(() async {
        _session.ensureGateAllowed();
        final invoices = await resolveInvoicesDirectory();
        final extension = p.extension(sourcePath).isEmpty
            ? '.jpg'
            : p.extension(sourcePath);
        final target = p.join(
          invoices.path,
          'invoice_${DateTime.now().microsecondsSinceEpoch}$extension',
        );
        await File(sourcePath).copy(target);
        return target;
      });
}
