import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' show Database, DatabaseExecutor, Sqflite;

import '../domain/models.dart';
import '../domain/money.dart';
import 'app_database.dart';

class BusinessRuleException implements Exception {
  BusinessRuleException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CampaignConflictException extends BusinessRuleException {
  CampaignConflictException(this.activeCampaignId, this.activeCampaignName)
    : super(
        'Está activa $activeCampaignName. Cierre esa campaña antes de activar otra.',
      );
  final int activeCampaignId;
  final String activeCampaignName;
}

class AgroRepository {
  AgroRepository(this.appDatabase);
  final AppDatabase appDatabase;

  Future<Database> get _db => appDatabase.database;
  String _date(DateTime date) => date.toUtc().toIso8601String();

  Future<int> addPerson({
    required String name,
    required PersonRole role,
    SettlementPolicy? policy,
    String? phone,
  }) async {
    final effective =
        policy ??
        switch (role) {
          PersonRole.admin => SettlementPolicy.manual,
          PersonRole.family => SettlementPolicy.byActualUsage,
          PersonRole.thirdParty => SettlementPolicy.byPurchaseAllocation,
        };
    return (await _db).insert('persons', {
      'name': name.trim(),
      'role': role.code,
      'settlement_policy': effective.code,
      'phone': phone,
      'created_at': _date(DateTime.now()),
    });
  }

  Future<int> addFarm({
    required int ownerId,
    required String name,
    required int areaM2,
    String? location,
  }) => _db.then(
    (db) => db.insert('farms', {
      'owner_person_id': ownerId,
      'name': name.trim(),
      'area_m2': areaM2,
      'location': location,
    }),
  );

  Future<int> addCampaign({
    required String name,
    required DateTime start,
    DateTime? end,
  }) async => (await _db).transaction((txn) async {
    final active =
        Sqflite.firstIntValue(
          await txn.rawQuery(
            "SELECT COUNT(*) FROM campaigns WHERE status='ACTIVE'",
          ),
        ) ??
        0;
    return txn.insert('campaigns', {
      'name': name.trim(),
      'start_date': _date(start),
      'end_date': end == null ? null : _date(end),
      'status': active == 0 ? 'ACTIVE' : 'PLANNED',
    });
  });

  Future<Map<String, Object?>?> activeCampaign() async {
    final rows = await (await _db).query(
      'campaigns',
      where: "status='ACTIVE'",
      orderBy: 'start_date DESC,id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single;
  }

  Future<void> activateCampaign(
    int campaignId, {
    bool closeCurrent = false,
  }) async {
    await (await _db).transaction((txn) async {
      final target = await txn.query(
        'campaigns',
        where: 'id=?',
        whereArgs: [campaignId],
        limit: 1,
      );
      if (target.isEmpty) throw BusinessRuleException('La campaña no existe.');
      if (target.single['status'] == 'ARCHIVED') {
        throw BusinessRuleException(
          'Una campaña archivada no puede activarse.',
        );
      }
      final active = await txn.query(
        'campaigns',
        where: "status='ACTIVE' AND id<>?",
        whereArgs: [campaignId],
        limit: 1,
      );
      if (active.isNotEmpty && !closeCurrent) {
        throw CampaignConflictException(
          active.single['id']! as int,
          active.single['name']! as String,
        );
      }
      if (active.isNotEmpty) {
        await txn.update(
          'campaigns',
          {'status': 'CLOSED', 'end_date': _date(DateTime.now())},
          where: 'id=?',
          whereArgs: [active.single['id']],
        );
      }
      await txn.update(
        'campaigns',
        {'status': 'ACTIVE', 'end_date': null},
        where: 'id=?',
        whereArgs: [campaignId],
      );
    });
  }

  Future<void> closeCampaign(int campaignId) async {
    await (await _db).transaction((txn) async {
      final changed = await txn.update(
        'campaigns',
        {'status': 'CLOSED', 'end_date': _date(DateTime.now())},
        where: "id=? AND status='ACTIVE'",
        whereArgs: [campaignId],
      );
      if (changed == 0)
        throw BusinessRuleException('Solo una campaña activa puede cerrarse.');
    });
  }

  Future<void> _ensureCampaignActive(
    DatabaseExecutor executor,
    int campaignId,
  ) async {
    final rows = await executor.query(
      'campaigns',
      columns: ['name'],
      where: "id=? AND status='ACTIVE'",
      whereArgs: [campaignId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw BusinessRuleException(
        'La campaña no está activa. Active una campaña para continuar.',
      );
    }
  }

  Future<int> addProduct({
    required String name,
    String? activeIngredient,
    String unit = 'L',
  }) => _db.then(
    (db) => db.insert('products', {
      'name': name.trim(),
      'active_ingredient': activeIngredient,
      'unit': unit,
      'base_unit': unit == 'L' ? 'ML' : 'G',
    }),
  );

  Future<int> addSupplier({
    required String name,
    String? phone,
    String? notes,
  }) => _db.then(
    (db) => db.insert('suppliers', {
      'name': name.trim(),
      'phone': phone,
      'notes': notes,
    }),
  );

  Future<int> addPlan({
    required int farmId,
    required int campaignId,
    required int productId,
    required int areaM2,
    required int doseBasePerHa,
    DateTime? plannedDate,
  }) async {
    return addPlanMulti(
      farmId: farmId,
      campaignId: campaignId,
      areaM2: areaM2,
      items: [
        PlanItemDraft(productId: productId, doseBasePerHa: doseBasePerHa),
      ],
      plannedDate: plannedDate,
    );
  }

  Future<int> addPlanMulti({
    required int farmId,
    required int campaignId,
    required int areaM2,
    required List<PlanItemDraft> items,
    DateTime? plannedDate,
    String? notes,
  }) async {
    if (areaM2 <= 0 || items.isEmpty) {
      throw BusinessRuleException(
        'El plan necesita área y al menos un producto.',
      );
    }
    final productIds = items.map((item) => item.productId).toSet();
    if (productIds.length != items.length) {
      throw BusinessRuleException('No repita productos dentro del plan.');
    }
    if (items.any((item) => item.doseBasePerHa <= 0)) {
      throw BusinessRuleException('Todas las dosis deben ser mayores a cero.');
    }
    return (await _db).transaction((txn) async {
      await _ensureCampaignActive(txn, campaignId);
      final planId = await txn.insert('application_plans', {
        'farm_id': farmId,
        'campaign_id': campaignId,
        'planned_date': plannedDate == null ? null : _date(plannedDate),
        'status': 'PLANNED',
        'notes': notes,
      });
      for (final item in items) {
        final requiredBase = divideRoundedHalfUp(
          areaM2 * item.doseBasePerHa,
          10000,
        );
        await txn.insert('application_plan_items', {
          'plan_id': planId,
          'product_id': item.productId,
          'area_m2': areaM2,
          'dose_base_per_ha': item.doseBasePerHa,
          'required_quantity_base': requiredBase,
        });
      }
      return planId;
    });
  }

  Future<int> confirmPurchase(PurchaseDraft draft) async {
    if (draft.items.isEmpty)
      throw BusinessRuleException('La compra necesita al menos un producto.');
    if (draft.items.map((item) => item.productId).toSet().length !=
        draft.items.length) {
      throw BusinessRuleException('No repita productos dentro de la compra.');
    }
    var purchaseTotal = 0;
    for (final item in draft.items) {
      if (item.quantityBase <= 0 || item.originalUnitPriceMinor <= 0) {
        throw BusinessRuleException(
          'Cantidad y precio deben ser mayores a cero.',
        );
      }
      if (item.currency == CurrencyCode.usd &&
          (item.exchangeRateScaled ?? 0) <= 0) {
        throw BusinessRuleException(
          'Una compra en USD requiere tipo de cambio.',
        );
      }
      if (item.currency == CurrencyCode.bob &&
          item.exchangeRateScaled != null) {
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
      purchaseTotal += subtotalMinor(
        quantityBase: item.quantityBase,
        unitPriceMinor: item.originalUnitPriceMinor,
        fxScaled: item.exchangeRateScaled,
      );
    }

    return (await _db).transaction((txn) async {
      await _ensureCampaignActive(txn, draft.campaignId);
      final purchaseId = await txn.insert('purchases', {
        'supplier_id': draft.supplierId,
        'campaign_id': draft.campaignId,
        'purchase_date': _date(draft.purchaseDate),
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
            'acquired_date': _date(draft.purchaseDate),
            'initial_quantity_base': allocation.quantityBase,
            'unit_cost_bob_minor_per_major_unit': unitBob,
            'currency_code': item.currency.code,
            'original_unit_price_minor': item.originalUnitPriceMinor,
            'exchange_rate_scaled': item.exchangeRateScaled,
          });
          await txn.insert('inventory_movements', {
            'lot_id': lotId,
            'product_id': item.productId,
            'owner_person_id': allocation.personId,
            'movement_date': _date(draft.purchaseDate),
            'type': 'PURCHASE_IN',
            'quantity_signed': allocation.quantityBase,
            'reference_type': 'PURCHASE_ALLOCATION',
            'reference_id': allocationId,
          });
          if (policy == 'BY_PURCHASE_ALLOCATION') {
            await txn.insert('account_transactions', {
              'person_id': allocation.personId,
              'campaign_id': draft.campaignId,
              'transaction_date': _date(draft.purchaseDate),
              'type': 'PURCHASE_ALLOCATION_CHARGE',
              'amount_bob_minor_signed': allocationCost,
              'reference_type': 'PURCHASE_ALLOCATION',
              'reference_id': allocationId,
            });
          }
        }
      }
      return purchaseId;
    });
  }

  Future<int> addProviderPayment({
    required int purchaseId,
    required int payerPersonId,
    required int amountBobMinor,
    required String method,
    DateTime? date,
  }) async {
    if (amountBobMinor <= 0)
      throw BusinessRuleException('El pago debe ser mayor a cero.');
    return (await _db).transaction((txn) async {
      final purchase = (await txn.query(
        'purchases',
        where: 'id = ? AND reversed_at IS NULL',
        whereArgs: [purchaseId],
        limit: 1,
      ));
      if (purchase.isEmpty)
        throw BusinessRuleException('La compra no está activa.');
      final paid =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COALESCE(SUM(amount_bob_minor),0) FROM provider_payments WHERE purchase_id = ? AND reversed_at IS NULL',
              [purchaseId],
            ),
          ) ??
          0;
      final total = purchase.single['total_bob_minor']! as int;
      if (paid + amountBobMinor > total)
        throw BusinessRuleException('El pago supera el saldo de la compra.');
      return txn.insert('provider_payments', {
        'purchase_id': purchaseId,
        'payer_person_id': payerPersonId,
        'payment_date': _date(date ?? DateTime.now()),
        'amount_bob_minor': amountBobMinor,
        'method': method,
      });
    });
  }

  Future<int> confirmApplication(ApplicationDraft draft) async {
    if (draft.lines.isEmpty)
      throw BusinessRuleException(
        'La aplicación necesita al menos un producto.',
      );
    if (draft.lines.map((line) => line.productId).toSet().length !=
        draft.lines.length) {
      throw BusinessRuleException(
        'No repita productos dentro de la aplicación.',
      );
    }
    return (await _db).transaction((txn) async {
      await _ensureCampaignActive(txn, draft.campaignId);
      final person = (await txn.query(
        'persons',
        where: 'id = ?',
        whereArgs: [draft.personId],
        limit: 1,
      )).single;
      final policy = person['settlement_policy']! as String;
      final applicationId = await txn.insert('applications', {
        'farm_id': draft.farmId,
        'person_id': draft.personId,
        'campaign_id': draft.campaignId,
        'plan_id': draft.planId,
        'applied_at': _date(draft.appliedAt),
        'status': 'CONFIRMED',
        'treated_area_m2':
            draft.treatedAreaM2 ?? draft.lines.first.treatedAreaM2,
        'notes': draft.notes,
      });
      var totalCost = 0;
      for (final line in draft.lines) {
        if (line.quantityBase <= 0)
          throw BusinessRuleException(
            'La cantidad aplicada debe ser mayor a cero.',
          );
        final lots = await txn.rawQuery(
          '''
          SELECT l.*, COALESCE(SUM(m.quantity_signed), 0) AS available
          FROM inventory_lots l JOIN inventory_movements m ON m.lot_id = l.id
          WHERE l.product_id = ? AND l.owner_person_id = ? AND l.reversed_at IS NULL
          GROUP BY l.id HAVING available > 0 ORDER BY l.acquired_date, l.id
        ''',
          [line.productId, draft.personId],
        );
        final available = lots.fold<int>(
          0,
          (sum, row) => sum + (row['available']! as int),
        );
        if (available < line.quantityBase)
          throw BusinessRuleException(
            'Stock insuficiente para confirmar la aplicación.',
          );
        final product = (await txn.query(
          'products',
          columns: ['unit'],
          where: 'id=?',
          whereArgs: [line.productId],
          limit: 1,
        )).single;
        final applicationItemId = await txn.insert('application_items', {
          'application_id': applicationId,
          'product_id': line.productId,
          'quantity_base': line.quantityBase,
          'cost_bob_minor': 0,
          'treated_area_m2': line.treatedAreaM2,
          'dose_base_per_ha': line.doseBasePerHa,
          'theoretical_quantity_base': line.theoreticalQuantityBase,
          'unit': product['unit'],
          'variance_quantity_base': line.theoreticalQuantityBase == null
              ? null
              : line.quantityBase - line.theoreticalQuantityBase!,
        });
        var remaining = line.quantityBase;
        var lineCost = 0;
        for (final lot in lots) {
          if (remaining == 0) break;
          final lotAvailable = lot['available']! as int;
          final take = remaining < lotAvailable ? remaining : lotAvailable;
          final cost = costForBaseQuantity(
            take,
            lot['unit_cost_bob_minor_per_major_unit']! as int,
          );
          await txn.insert('application_consumptions', {
            'application_item_id': applicationItemId,
            'inventory_lot_id': lot['id'],
            'quantity_consumed_base': take,
            'cost_bob_minor': cost,
          });
          await txn.insert('inventory_movements', {
            'lot_id': lot['id'],
            'product_id': line.productId,
            'owner_person_id': draft.personId,
            'movement_date': _date(draft.appliedAt),
            'type': 'APPLICATION_OUT',
            'quantity_signed': -take,
            'reference_type': 'APPLICATION',
            'reference_id': applicationId,
          });
          lineCost += cost;
          remaining -= take;
        }
        await txn.update(
          'application_items',
          {
            'cost_bob_minor': lineCost,
            'fifo_estimated_cost_bob_minor': lineCost,
          },
          where: 'id = ?',
          whereArgs: [applicationItemId],
        );
        totalCost += lineCost;
      }
      await txn.update(
        'applications',
        {'total_cost_bob_minor': totalCost},
        where: 'id = ?',
        whereArgs: [applicationId],
      );
      if (policy == 'BY_ACTUAL_USAGE') {
        await txn.insert('account_transactions', {
          'person_id': draft.personId,
          'campaign_id': draft.campaignId,
          'transaction_date': _date(draft.appliedAt),
          'type': 'USAGE_CHARGE',
          'amount_bob_minor_signed': totalCost,
          'reference_type': 'APPLICATION',
          'reference_id': applicationId,
        });
      }
      if (draft.planId != null) {
        await txn.update(
          'application_plans',
          {'status': 'COMPLETED'},
          where: 'id=?',
          whereArgs: [draft.planId],
        );
      }
      return applicationId;
    });
  }

  Future<int> addAccountPayment({
    required int personId,
    int? campaignId,
    required int amountBobMinor,
    bool advance = false,
    DateTime? date,
    String? notes,
  }) async {
    if (amountBobMinor <= 0)
      throw BusinessRuleException('El importe debe ser mayor a cero.');
    return (await _db).transaction((txn) async {
      final paymentId = await txn.insert('account_transactions', {
        'person_id': personId,
        'campaign_id': campaignId,
        'transaction_date': _date(date ?? DateTime.now()),
        'type': advance ? 'ADVANCE' : 'PAYMENT',
        'amount_bob_minor_signed': -amountBobMinor,
        'reference_type': advance ? 'ADVANCE' : 'PAYMENT',
        'notes': notes,
      });
      var remaining = amountBobMinor;
      final charges = await txn.rawQuery(
        '''SELECT t.id, t.amount_bob_minor_signed -
        COALESCE((SELECT SUM(a.amount_bob_minor) FROM payment_allocations a
          WHERE a.charge_transaction_id=t.id),0) outstanding
        FROM account_transactions t
        WHERE t.person_id=? AND t.amount_bob_minor_signed>0
        ORDER BY t.transaction_date, t.id''',
        [personId],
      );
      for (final charge in charges) {
        if (remaining == 0) break;
        final outstanding = charge['outstanding']! as int;
        if (outstanding <= 0) continue;
        final allocated = remaining < outstanding ? remaining : outstanding;
        await txn.insert('payment_allocations', {
          'payment_transaction_id': paymentId,
          'charge_transaction_id': charge['id'],
          'amount_bob_minor': allocated,
        });
        remaining -= allocated;
      }
      return paymentId;
    });
  }

  Future<void> reverseApplication(int applicationId, {String? reason}) async {
    await (await _db).transaction((txn) async {
      final rows = await txn.query(
        'applications',
        where: 'id = ? AND reversed_at IS NULL',
        whereArgs: [applicationId],
      );
      if (rows.isEmpty)
        throw BusinessRuleException(
          'La aplicación ya fue revertida o no existe.',
        );
      final application = rows.single;
      final consumptions = await txn.rawQuery(
        '''SELECT c.*, i.product_id FROM application_consumptions c
        JOIN application_items i ON i.id = c.application_item_id WHERE i.application_id = ? AND c.reversed_at IS NULL''',
        [applicationId],
      );
      for (final consumption in consumptions) {
        await txn.insert('inventory_movements', {
          'lot_id': consumption['inventory_lot_id'],
          'product_id': consumption['product_id'],
          'owner_person_id': application['person_id'],
          'movement_date': _date(DateTime.now()),
          'type': 'APPLICATION_REVERSAL',
          'quantity_signed': consumption['quantity_consumed_base'],
          'reference_type': 'APPLICATION_REVERSAL',
          'reference_id': applicationId,
          'notes': reason,
        });
      }
      await txn.update(
        'application_consumptions',
        {'reversed_at': _date(DateTime.now())},
        where: 'application_item_id IN (SELECT id FROM application_items WHERE application_id = ?)',
        whereArgs: [applicationId],
      );
      final charges = await txn.query(
        'account_transactions',
        where: "reference_type = 'APPLICATION' AND reference_id = ? AND type = 'USAGE_CHARGE'",
        whereArgs: [applicationId],
      );
      for (final charge in charges) {
        await txn.insert('account_transactions', {
          'person_id': charge['person_id'],
          'campaign_id': charge['campaign_id'],
          'transaction_date': _date(DateTime.now()),
          'type': 'CREDIT_ADJUSTMENT',
          'amount_bob_minor_signed':
              -(charge['amount_bob_minor_signed']! as int),
          'reference_type': 'APPLICATION_REVERSAL',
          'reference_id': applicationId,
          'notes': reason,
          'reversal_of_id': charge['id'],
        });
      }
      await txn.update(
        'applications',
        {'status': 'REVERSED', 'reversed_at': _date(DateTime.now())},
        where: 'id = ?',
        whereArgs: [applicationId],
      );
      if (application['plan_id'] != null) {
        await txn.update(
          'application_plans',
          {'status': 'PLANNED'},
          where: 'id=?',
          whereArgs: [application['plan_id']],
        );
      }
    });
  }

  Future<void> reversePurchase(int purchaseId, {String? reason}) async {
    await (await _db).transaction((txn) async {
      final consumed =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              '''SELECT COUNT(*) FROM application_consumptions c
        JOIN inventory_lots l ON l.id = c.inventory_lot_id JOIN purchase_items i ON i.id = l.purchase_item_id
        WHERE i.purchase_id = ? AND c.reversed_at IS NULL''',
              [purchaseId],
            ),
          ) ??
          0;
      if (consumed > 0)
        throw BusinessRuleException(
          'La compra tiene lotes consumidos. Revierta primero las aplicaciones relacionadas.',
        );
      final purchase = await txn.query(
        'purchases',
        where: 'id = ? AND reversed_at IS NULL',
        whereArgs: [purchaseId],
      );
      if (purchase.isEmpty)
        throw BusinessRuleException('La compra ya fue revertida o no existe.');
      final lots = await txn.rawQuery(
        'SELECT l.* FROM inventory_lots l JOIN purchase_items i ON i.id=l.purchase_item_id WHERE i.purchase_id=?',
        [purchaseId],
      );
      for (final lot in lots) {
        final available =
            Sqflite.firstIntValue(
              await txn.rawQuery(
                'SELECT COALESCE(SUM(quantity_signed),0) FROM inventory_movements WHERE lot_id=?',
                [lot['id']],
              ),
            ) ??
            0;
        if (available != lot['initial_quantity_base'])
          throw BusinessRuleException(
            'El lote fue transferido o ajustado; requiere reversión consistente previa.',
          );
        await txn.insert('inventory_movements', {
          'lot_id': lot['id'],
          'product_id': lot['product_id'],
          'owner_person_id': lot['owner_person_id'],
          'movement_date': _date(DateTime.now()),
          'type': 'PURCHASE_REVERSAL',
          'quantity_signed': -available,
          'reference_type': 'PURCHASE_REVERSAL',
          'reference_id': purchaseId,
          'notes': reason,
        });
        await txn.update(
          'inventory_lots',
          {'reversed_at': _date(DateTime.now())},
          where: 'id=?',
          whereArgs: [lot['id']],
        );
      }
      final allocationCharges = await txn.rawQuery(
        '''SELECT t.* FROM account_transactions t JOIN purchase_allocations a ON
        t.reference_type='PURCHASE_ALLOCATION' AND t.reference_id=a.id JOIN purchase_items i ON i.id=a.purchase_item_id
        WHERE i.purchase_id=?''',
        [purchaseId],
      );
      for (final charge in allocationCharges) {
        await txn.insert('account_transactions', {
          'person_id': charge['person_id'],
          'campaign_id': charge['campaign_id'],
          'transaction_date': _date(DateTime.now()),
          'type': 'CREDIT_ADJUSTMENT',
          'amount_bob_minor_signed':
              -(charge['amount_bob_minor_signed']! as int),
          'reference_type': 'PURCHASE_REVERSAL',
          'reference_id': purchaseId,
          'notes': reason,
          'reversal_of_id': charge['id'],
        });
      }
      await txn.update(
        'provider_payments',
        {'reversed_at': _date(DateTime.now())},
        where: 'purchase_id=? AND reversed_at IS NULL',
        whereArgs: [purchaseId],
      );
      await txn.update(
        'purchases',
        {'status': 'REVERSED', 'reversed_at': _date(DateTime.now())},
        where: 'id=?',
        whereArgs: [purchaseId],
      );
    });
  }

  Future<int> transferStock({
    required int sourceLotId,
    required int destinationPersonId,
    required int quantityBase,
    DateTime? date,
    String? notes,
  }) async {
    final source = await (await _db).query(
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
    final item = await (await _db).query(
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
    return (await _db).transaction((txn) async {
      final movementDate = _date(date ?? DateTime.now());
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
        final lots = await txn.rawQuery(
          '''SELECT l.*, COALESCE(SUM(m.quantity_signed),0) available
          FROM inventory_lots l LEFT JOIN inventory_movements m ON m.lot_id=l.id
          WHERE l.owner_person_id=? AND l.product_id=? AND l.reversed_at IS NULL
          GROUP BY l.id HAVING available>0 ORDER BY l.acquired_date,l.id''',
          [fromPersonId, item.productId],
        );
        final available = lots.fold<int>(
          0,
          (sum, lot) => sum + (lot['available'] as int),
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
          final lotAvailable = source['available'] as int;
          final take = remaining < lotAvailable ? remaining : lotAvailable;
          final cost = costForBaseQuantity(
            take,
            source['unit_cost_bob_minor_per_major_unit'] as int,
          );
          final destinationLotId = await txn.insert('inventory_lots', {
            'purchase_item_id': source['purchase_item_id'],
            'product_id': item.productId,
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
              'product_id': item.productId,
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
          remaining -= take;
          itemCost += cost;
        }
        await txn.update(
          'transfer_items',
          {'total_cost_bob_minor': itemCost},
          where: 'id=?',
          whereArgs: [transferItemId],
        );
        transferCost += itemCost;
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

  @Deprecated('Compatibilidad con transferencias V3.')
  Future<int> transferProductFifoV3Legacy({
    required int fromPersonId,
    required int toPersonId,
    required int productId,
    required int quantityBase,
    DateTime? date,
    String? notes,
  }) async {
    if (quantityBase <= 0) {
      throw BusinessRuleException(
        'La cantidad transferida debe ser mayor a cero.',
      );
    }
    if (fromPersonId == toPersonId) {
      throw BusinessRuleException(
        'El origen y el destino deben ser diferentes.',
      );
    }
    return (await _db).transaction((txn) async {
      final lots = await txn.rawQuery(
        '''SELECT l.*, COALESCE(SUM(m.quantity_signed),0) available
        FROM inventory_lots l LEFT JOIN inventory_movements m ON m.lot_id=l.id
        WHERE l.owner_person_id=? AND l.product_id=? AND l.reversed_at IS NULL
        GROUP BY l.id HAVING available>0 ORDER BY l.acquired_date, l.id''',
        [fromPersonId, productId],
      );
      final available = lots.fold<int>(
        0,
        (sum, lot) => sum + (lot['available']! as int),
      );
      if (available < quantityBase) {
        throw BusinessRuleException(
          'Stock insuficiente para completar la transferencia.',
        );
      }
      final movementDate = _date(date ?? DateTime.now());
      final transferId = await txn.insert('transfers', {
        'product_id': productId,
        'from_person_id': fromPersonId,
        'to_person_id': toPersonId,
        'transfer_date': movementDate,
        'quantity_base': quantityBase,
        'total_cost_bob_minor': 0,
        'notes': notes,
      });
      var remaining = quantityBase;
      var totalCost = 0;
      for (final source in lots) {
        if (remaining == 0) break;
        final lotAvailable = source['available']! as int;
        final take = remaining < lotAvailable ? remaining : lotAvailable;
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
          'source_lot_id': source['id'],
          'destination_lot_id': destinationLotId,
          'quantity_base': take,
          'cost_bob_minor': cost,
        });
        totalCost += cost;
        remaining -= take;
      }
      await txn.update(
        'transfers',
        {'total_cost_bob_minor': totalCost},
        where: 'id=?',
        whereArgs: [transferId],
      );
      return transferId;
    });
  }

  Future<void> reverseTransfer(int transferId, {String? reason}) async {
    await (await _db).transaction((txn) async {
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
      final items = await txn.query(
        'transfer_lot_items',
        where: 'transfer_id=?',
        whereArgs: [transferId],
        orderBy: 'id',
      );
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
      final reversedAt = _date(DateTime.now());
      for (final item in items) {
        final quantity = item['quantity_base']! as int;
        for (final movement in <Map<String, Object?>>[
          {
            'lot_id': item['source_lot_id'],
            'owner_person_id': transfer['from_person_id'],
            'quantity_signed': quantity,
            'type': 'TRANSFER_REVERSAL_IN',
          },
          {
            'lot_id': item['destination_lot_id'],
            'owner_person_id': transfer['to_person_id'],
            'quantity_signed': -quantity,
            'type': 'TRANSFER_REVERSAL_OUT',
          },
        ]) {
          await txn.insert('inventory_movements', {
            ...movement,
            'product_id': transfer['product_id'],
            'movement_date': reversedAt,
            'reference_type': 'TRANSFER_REVERSAL',
            'reference_id': transferId,
            'notes': reason,
          });
        }
        await txn.update(
          'inventory_lots',
          {'reversed_at': reversedAt},
          where: 'id=?',
          whereArgs: [item['destination_lot_id']],
        );
      }
      await txn.update(
        'transfers',
        {'status': 'REVERSED', 'reversed_at': reversedAt},
        where: 'id=?',
        whereArgs: [transferId],
      );
    });
  }

  Future<List<Map<String, Object?>>> transfers({int limit = 50}) async =>
      (await _db).rawQuery(
        '''SELECT t.*, pr.name product_name, pr.unit,
        source.name from_person_name, destination.name to_person_name,
        (SELECT COUNT(*) FROM transfer_lot_items i WHERE i.transfer_id=t.id) lot_count,
        COALESCE((SELECT COUNT(*) FROM transfer_items ti WHERE ti.transfer_id=t.id),1) item_count,
        COALESCE((SELECT GROUP_CONCAT(p.name || ' ' || (ti.quantity_base / 1000.0) || ' ' || p.unit, ' · ')
          FROM transfer_items ti JOIN products p ON p.id=ti.product_id WHERE ti.transfer_id=t.id),
          pr.name || ' ' || (t.quantity_base / 1000.0) || ' ' || pr.unit) products_summary
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
  }) async => (await _db).rawQuery(
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

  @Deprecated('Use transferProductFifo; kept for source compatibility.')
  Future<int> transferStockLegacy({
    required int sourceLotId,
    required int destinationPersonId,
    required int quantityBase,
    DateTime? date,
    String? notes,
  }) async {
    if (quantityBase <= 0) {
      throw BusinessRuleException(
        'La cantidad transferida debe ser mayor a cero.',
      );
    }
    return (await _db).transaction((txn) async {
      final rows = await txn.query(
        'inventory_lots',
        where: 'id = ? AND reversed_at IS NULL',
        whereArgs: [sourceLotId],
      );
      if (rows.isEmpty)
        throw BusinessRuleException('El lote de origen no está activo.');
      final source = rows.single;
      final available =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COALESCE(SUM(quantity_signed),0) FROM inventory_movements WHERE lot_id=?',
              [sourceLotId],
            ),
          ) ??
          0;
      if (available < quantityBase) {
        throw BusinessRuleException('Stock insuficiente en el lote de origen.');
      }
      final movementDate = _date(date ?? DateTime.now());
      final newLotId = await txn.insert('inventory_lots', {
        'purchase_item_id': source['purchase_item_id'],
        'product_id': source['product_id'],
        'owner_person_id': destinationPersonId,
        'acquired_date': source['acquired_date'],
        'initial_quantity_base': quantityBase,
        'unit_cost_bob_minor_per_major_unit':
            source['unit_cost_bob_minor_per_major_unit'],
        'currency_code': source['currency_code'],
        'original_unit_price_minor': source['original_unit_price_minor'],
        'exchange_rate_scaled': source['exchange_rate_scaled'],
        'parent_lot_id': sourceLotId,
        'notes': notes,
      });
      await txn.insert('inventory_movements', {
        'lot_id': sourceLotId,
        'product_id': source['product_id'],
        'owner_person_id': source['owner_person_id'],
        'movement_date': movementDate,
        'type': 'TRANSFER_OUT',
        'quantity_signed': -quantityBase,
        'reference_type': 'INVENTORY_LOT',
        'reference_id': newLotId,
        'notes': notes,
      });
      await txn.insert('inventory_movements', {
        'lot_id': newLotId,
        'product_id': source['product_id'],
        'owner_person_id': destinationPersonId,
        'movement_date': movementDate,
        'type': 'TRANSFER_IN',
        'quantity_signed': quantityBase,
        'reference_type': 'INVENTORY_LOT',
        'reference_id': sourceLotId,
        'notes': notes,
      });
      return newLotId;
    });
  }

  Future<List<Map<String, Object?>>> list(String table, {String? orderBy}) =>
      _db.then((db) => db.query(table, orderBy: orderBy ?? 'id DESC'));

  Future<void> renameCatalog(String table, int id, String name) async {
    const allowed = {'persons', 'farms', 'products', 'suppliers', 'campaigns'};
    if (!allowed.contains(table)) throw ArgumentError('Catálogo no permitido.');
    if (name.trim().isEmpty)
      throw BusinessRuleException('El nombre no puede estar vacío.');
    await (await _db).update(
      table,
      {'name': name.trim()},
      where: 'id=?',
      whereArgs: [id],
    );
  }

  Future<void> archiveCatalog(String table, int id) async {
    const activeTables = {'persons', 'farms', 'products', 'suppliers'};
    if (activeTables.contains(table)) {
      await (await _db).update(
        table,
        {'active': 0},
        where: 'id=?',
        whereArgs: [id],
      );
      return;
    }
    if (table == 'campaigns') {
      await (await _db).update(
        table,
        {'status': 'CLOSED'},
        where: 'id=?',
        whereArgs: [id],
      );
      return;
    }
    throw ArgumentError('Catálogo no permitido.');
  }

  Future<List<Map<String, Object?>>> people() async =>
      (await _db).query('persons', where: 'active=1', orderBy: 'name');
  Future<List<Map<String, Object?>>> products() async =>
      (await _db).query('products', where: 'active=1', orderBy: 'name');
  Future<List<Map<String, Object?>>> suppliers() async =>
      (await _db).query('suppliers', where: 'active=1', orderBy: 'name');
  Future<List<Map<String, Object?>>> campaigns() =>
      list('campaigns', orderBy: 'start_date DESC');
  Future<List<Map<String, Object?>>> farms() async => (await _db).rawQuery(
    'SELECT f.*, p.name owner_name FROM farms f JOIN persons p ON p.id=f.owner_person_id WHERE f.active=1 ORDER BY f.name',
  );
  Future<List<Map<String, Object?>>> purchases({int limit = 200}) async =>
      (await _db).rawQuery(
        '''SELECT p.*, s.name supplier_name, c.name campaign_name,
    COALESCE((SELECT SUM(amount_bob_minor) FROM provider_payments pp WHERE pp.purchase_id=p.id AND pp.reversed_at IS NULL),0) paid_bob_minor,
    (SELECT COUNT(*) FROM purchase_items i WHERE i.purchase_id=p.id) item_count
    FROM purchases p JOIN suppliers s ON s.id=p.supplier_id
    JOIN campaigns c ON c.id=p.campaign_id ORDER BY purchase_date DESC LIMIT ?''',
        [limit],
      );
  Future<List<Map<String, Object?>>> applications({
    int? campaignId,
    int? personId,
    int? farmId,
    int? productId,
    int? limit,
  }) async {
    final conditions = <String>[];
    final args = <Object?>[];
    if (campaignId != null) {
      conditions.add('a.campaign_id=?');
      args.add(campaignId);
    }
    if (personId != null) {
      conditions.add('a.person_id=?');
      args.add(personId);
    }
    if (farmId != null) {
      conditions.add('a.farm_id=?');
      args.add(farmId);
    }
    if (productId != null) {
      conditions.add(
        'EXISTS (SELECT 1 FROM application_items x WHERE x.application_id=a.id AND x.product_id=?)',
      );
      args.add(productId);
    }
    if (limit != null) args.add(limit);
    return (await _db).rawQuery(
      '''SELECT a.*, p.name person_name, f.name farm_name,
        c.name campaign_name,
        COALESCE(SUM(i.theoretical_quantity_base),0) theoretical_quantity_base,
        COALESCE(SUM(i.quantity_base),0) real_quantity_base,
        GROUP_CONCAT(DISTINCT pr.unit) units, COUNT(i.id) item_count,
        GROUP_CONCAT(pr.name || ' ' || (i.quantity_base / 1000.0) || ' ' || pr.unit, ' · ') items_summary
        FROM applications a JOIN persons p ON p.id=a.person_id JOIN farms f ON f.id=a.farm_id
        JOIN campaigns c ON c.id=a.campaign_id
        LEFT JOIN application_items i ON i.application_id=a.id LEFT JOIN products pr ON pr.id=i.product_id
        ${conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}'}
        GROUP BY a.id ORDER BY applied_at DESC, a.id DESC ${limit == null ? '' : 'LIMIT ?'}''',
      args,
    );
  }

  Future<List<Map<String, Object?>>> plans({int limit = 400}) async =>
      (await _db).rawQuery(
        '''SELECT i.*, p.name product_name, p.unit, f.name farm_name, pe.name owner_name,
    c.name campaign_name, a.campaign_id FROM application_plan_items i
    JOIN application_plans a ON a.id=i.plan_id JOIN products p ON p.id=i.product_id
    JOIN farms f ON f.id=a.farm_id JOIN persons pe ON pe.id=f.owner_person_id
    JOIN campaigns c ON c.id=a.campaign_id ORDER BY a.id DESC LIMIT ?''',
        [limit],
      );

  Future<List<Map<String, Object?>>> planForApplication(int planId) async =>
      (await _db).rawQuery(
        '''SELECT a.id plan_id, a.campaign_id, a.farm_id,
        f.owner_person_id person_id, f.name farm_name, f.area_m2 farm_area_m2,
        i.area_m2, i.product_id, i.dose_base_per_ha,
        i.required_quantity_base, p.name product_name, p.unit
        FROM application_plans a JOIN farms f ON f.id=a.farm_id
        JOIN application_plan_items i ON i.plan_id=a.id
        JOIN products p ON p.id=i.product_id WHERE a.id=? ORDER BY i.id''',
        [planId],
      );
  Future<List<Map<String, Object?>>> stock() async => (await _db).rawQuery(
    '''SELECT l.id lot_id, l.owner_person_id, pr.name product_name, pr.unit, pe.name owner_name,
    SUM(m.quantity_signed) quantity_base, l.unit_cost_bob_minor_per_major_unit unit_cost
    FROM inventory_movements m JOIN inventory_lots l ON l.id=m.lot_id JOIN products pr ON pr.id=m.product_id
    JOIN persons pe ON pe.id=m.owner_person_id GROUP BY l.id HAVING quantity_base <> 0 ORDER BY l.acquired_date''',
  );

  Future<List<Map<String, Object?>>> inventorySummary({int? limit}) async =>
      (await _db).rawQuery(
        '''SELECT p.id product_id, p.name product_name, p.unit,
        COALESCE(SUM(CASE WHEN m.type='PURCHASE_IN' THEN m.quantity_signed ELSE 0 END),0) purchased_base,
        COALESCE(-SUM(CASE WHEN m.type='APPLICATION_OUT' THEN m.quantity_signed ELSE 0 END),0) consumed_base,
        COALESCE(SUM(m.quantity_signed),0) available_base,
        COALESCE((SELECT SUM(pi.required_quantity_base) FROM application_plan_items pi
          JOIN application_plans ap ON ap.id=pi.plan_id JOIN campaigns c ON c.id=ap.campaign_id
          WHERE pi.product_id=p.id AND ap.status IN ('DRAFT','PLANNED') AND c.status='ACTIVE'),0) committed_base,
        COALESCE(SUM(m.quantity_signed),0) - COALESCE((SELECT SUM(pi.required_quantity_base)
          FROM application_plan_items pi JOIN application_plans ap ON ap.id=pi.plan_id
          JOIN campaigns c ON c.id=ap.campaign_id WHERE pi.product_id=p.id
          AND ap.status IN ('DRAFT','PLANNED') AND c.status='ACTIVE'),0) projected_base,
        COALESCE(SUM(CASE WHEN m.quantity_signed>0 THEN m.quantity_signed*l.unit_cost_bob_minor_per_major_unit ELSE m.quantity_signed*l.unit_cost_bob_minor_per_major_unit END)/1000,0) available_value_bob_minor,
        COUNT(DISTINCT CASE WHEN m.quantity_signed <> 0 THEN l.owner_person_id END) people_count
        FROM products p LEFT JOIN inventory_movements m ON m.product_id=p.id
        LEFT JOIN inventory_lots l ON l.id=m.lot_id GROUP BY p.id ORDER BY p.name
        ${limit == null ? '' : 'LIMIT ?'}''',
        limit == null ? null : [limit],
      );

  Future<List<Map<String, Object?>>> personStockSummary(int personId) async =>
      (await _db).rawQuery(
        '''SELECT p.id product_id, p.name product_name, p.unit,
        COALESCE(SUM(CASE WHEN m.quantity_signed>0 THEN m.quantity_signed ELSE 0 END),0) assigned_base,
        COALESCE(-SUM(CASE WHEN m.type='APPLICATION_OUT' THEN m.quantity_signed ELSE 0 END),0) consumed_base,
        COALESCE(SUM(m.quantity_signed),0) available_base
        FROM products p LEFT JOIN inventory_movements m ON m.product_id=p.id AND m.owner_person_id=?
        GROUP BY p.id HAVING available_base>0 OR assigned_base>0 ORDER BY p.name''',
        [personId],
      );

  Future<Map<String, Object?>> inventoryProductHeader(int productId) async {
    final rows = await (await _db).rawQuery(
      '''SELECT p.id product_id, p.name product_name, p.unit,
      COALESCE(SUM(CASE WHEN m.type='PURCHASE_IN' THEN m.quantity_signed ELSE 0 END),0) purchased_base,
      COALESCE(-SUM(CASE WHEN m.type='APPLICATION_OUT' THEN m.quantity_signed ELSE 0 END),0) consumed_base,
      COALESCE(SUM(m.quantity_signed),0) physical_base,
      COALESCE(SUM(m.quantity_signed*l.unit_cost_bob_minor_per_major_unit)/1000,0) value_bob_minor,
      COALESCE((SELECT SUM(pi.required_quantity_base) FROM application_plan_items pi
        JOIN application_plans ap ON ap.id=pi.plan_id JOIN campaigns c ON c.id=ap.campaign_id
        WHERE pi.product_id=p.id AND ap.status IN ('DRAFT','PLANNED') AND c.status='ACTIVE'),0) committed_base
      FROM products p LEFT JOIN inventory_movements m ON m.product_id=p.id
      LEFT JOIN inventory_lots l ON l.id=m.lot_id WHERE p.id=? GROUP BY p.id''',
      [productId],
    );
    if (rows.isEmpty) throw BusinessRuleException('El producto no existe.');
    return rows.single;
  }

  Future<List<Map<String, Object?>>> inventoryProductDistribution(
    int productId,
  ) async => (await _db).rawQuery(
    '''SELECT p.id person_id, p.name person_name,
        COALESCE(SUM(CASE WHEN m.quantity_signed>0 THEN m.quantity_signed ELSE 0 END),0) assigned_base,
        COALESCE(-SUM(CASE WHEN m.type='APPLICATION_OUT' THEN m.quantity_signed ELSE 0 END),0) consumed_base,
        COALESCE(SUM(m.quantity_signed),0) available_base
        FROM persons p LEFT JOIN inventory_movements m ON m.owner_person_id=p.id AND m.product_id=?
        GROUP BY p.id HAVING assigned_base>0 OR consumed_base>0 OR available_base<>0
        ORDER BY p.name''',
    [productId],
  );

  Future<List<Map<String, Object?>>> inventoryProductLots(
    int productId, {
    int? personId,
    int? supplierId,
    int? campaignId,
  }) async {
    final conditions = <String>['l.product_id=?', 'l.reversed_at IS NULL'];
    final args = <Object?>[productId];
    if (personId != null) {
      conditions.add('l.owner_person_id=?');
      args.add(personId);
    }
    if (supplierId != null) {
      conditions.add('pu.supplier_id=?');
      args.add(supplierId);
    }
    if (campaignId != null) {
      conditions.add('pu.campaign_id=?');
      args.add(campaignId);
    }
    return (await _db).rawQuery(
      '''SELECT l.id lot_id, l.acquired_date, l.initial_quantity_base,
      l.unit_cost_bob_minor_per_major_unit unit_cost, l.currency_code,
      l.original_unit_price_minor, l.exchange_rate_scaled, l.parent_lot_id,
      pe.name owner_name, s.name supplier_name, c.name campaign_name,
      COALESCE(SUM(m.quantity_signed),0) available_base
      FROM inventory_lots l JOIN persons pe ON pe.id=l.owner_person_id
      JOIN purchase_items pi ON pi.id=l.purchase_item_id
      JOIN purchases pu ON pu.id=pi.purchase_id JOIN suppliers s ON s.id=pu.supplier_id
      JOIN campaigns c ON c.id=pu.campaign_id
      LEFT JOIN inventory_movements m ON m.lot_id=l.id
      WHERE ${conditions.join(' AND ')} GROUP BY l.id
      HAVING available_base<>0 ORDER BY l.acquired_date,l.id LIMIT 500''',
      args,
    );
  }

  Future<List<Map<String, Object?>>> personProfiles() async =>
      (await _db).rawQuery('''SELECT p.*,
        COALESCE((SELECT SUM(f.area_m2) FROM farms f WHERE f.owner_person_id=p.id AND f.active=1),0) area_m2,
        COALESCE((SELECT SUM(t.amount_bob_minor_signed) FROM account_transactions t WHERE t.person_id=p.id),0) balance,
        COALESCE((SELECT COUNT(DISTINCT m.product_id) FROM inventory_movements m
          WHERE m.owner_person_id=p.id GROUP BY m.owner_person_id HAVING SUM(m.quantity_signed)<>0),0) stock_products
        FROM persons p WHERE p.active=1 ORDER BY p.name''');

  Future<Map<String, Object?>> personProfile(int personId) async {
    final rows = await (await _db).rawQuery(
      '''SELECT p.*,
      COALESCE((SELECT SUM(f.area_m2) FROM farms f WHERE f.owner_person_id=p.id AND f.active=1),0) area_m2,
      COALESCE((SELECT SUM(t.amount_bob_minor_signed) FROM account_transactions t WHERE t.person_id=p.id),0) balance
      FROM persons p WHERE p.id=?''',
      [personId],
    );
    if (rows.isEmpty) throw BusinessRuleException('La persona no existe.');
    return rows.single;
  }

  Future<List<Map<String, Object?>>> farmsForPerson(int personId) async =>
      (await _db).query(
        'farms',
        where: 'owner_person_id=? AND active=1',
        whereArgs: [personId],
        orderBy: 'name',
      );

  Future<Map<String, Object?>> farmProfile(int farmId) async {
    final rows = await (await _db).rawQuery(
      '''SELECT f.*, p.name owner_name FROM farms f
      JOIN persons p ON p.id=f.owner_person_id WHERE f.id=?''',
      [farmId],
    );
    if (rows.isEmpty) throw BusinessRuleException('El chaco no existe.');
    return rows.single;
  }

  Future<List<Map<String, Object?>>> farmLogbook(
    int farmId, {
    int? campaignId,
    int? productId,
  }) async {
    final conditions = <String>['a.farm_id=?'];
    final args = <Object?>[farmId];
    if (campaignId != null) {
      conditions.add('a.campaign_id=?');
      args.add(campaignId);
    }
    if (productId != null) {
      conditions.add('i.product_id=?');
      args.add(productId);
    }
    return (await _db).rawQuery(
      '''SELECT a.id application_id, a.applied_at, a.status, a.notes,
      c.name campaign_name, pe.name person_name, i.id application_item_id,
      pr.id product_id, pr.name product_name, pr.unit, i.treated_area_m2,
      i.dose_base_per_ha, i.theoretical_quantity_base, i.quantity_base,
      i.cost_bob_minor,
      (SELECT GROUP_CONCAT('#' || ac.inventory_lot_id || ': ' || ac.quantity_consumed_base)
        FROM application_consumptions ac WHERE ac.application_item_id=i.id AND ac.reversed_at IS NULL) fifo_lots
      FROM applications a JOIN campaigns c ON c.id=a.campaign_id
      JOIN persons pe ON pe.id=a.person_id JOIN application_items i ON i.application_id=a.id
      JOIN products pr ON pr.id=i.product_id
      WHERE ${conditions.join(' AND ')} ORDER BY a.applied_at DESC,a.id DESC,i.id''',
      args,
    );
  }

  Future<Map<String, Object?>> campaignCloseSummary(int campaignId) async {
    final db = await _db;
    Future<int> value(String sql) async =>
        Sqflite.firstIntValue(await db.rawQuery(sql, [campaignId])) ?? 0;
    return {
      'purchases_count': await value(
        'SELECT COUNT(*) FROM purchases WHERE campaign_id=? AND reversed_at IS NULL',
      ),
      'purchases_bob_minor': await value(
        'SELECT COALESCE(SUM(total_bob_minor),0) FROM purchases WHERE campaign_id=? AND reversed_at IS NULL',
      ),
      'applications_count': await value(
        'SELECT COUNT(*) FROM applications WHERE campaign_id=? AND reversed_at IS NULL',
      ),
      'applications_bob_minor': await value(
        'SELECT COALESCE(SUM(total_cost_bob_minor),0) FROM applications WHERE campaign_id=? AND reversed_at IS NULL',
      ),
      'pending_plans': await value(
        "SELECT COUNT(*) FROM application_plans WHERE campaign_id=? AND status IN ('DRAFT','PLANNED')",
      ),
      'receivable_bob_minor': await value(
        'SELECT COALESCE(SUM(amount_bob_minor_signed),0) FROM account_transactions WHERE campaign_id=?',
      ),
    };
  }

  Future<Map<String, Object?>> personCampaignBalance(
    int personId,
    int campaignId,
  ) async {
    final db = await _db;
    final campaign = (await db.query(
      'campaigns',
      columns: ['start_date'],
      where: 'id=?',
      whereArgs: [campaignId],
    )).single;
    final start = campaign['start_date'];
    final rows = await db.rawQuery(
      '''SELECT
      COALESCE(SUM(CASE WHEN c.start_date < ? THEN t.amount_bob_minor_signed ELSE 0 END),0) opening_balance,
      COALESCE(SUM(CASE WHEN t.campaign_id=? AND t.amount_bob_minor_signed>0 THEN t.amount_bob_minor_signed ELSE 0 END),0) campaign_charges,
      COALESCE(-SUM(CASE WHEN t.campaign_id=? AND t.amount_bob_minor_signed<0 THEN t.amount_bob_minor_signed ELSE 0 END),0) campaign_payments,
      COALESCE(SUM(t.amount_bob_minor_signed),0) total_balance
      FROM account_transactions t LEFT JOIN campaigns c ON c.id=t.campaign_id
      WHERE t.person_id=?''',
      [start, campaignId, campaignId, personId],
    );
    return rows.single;
  }

  Future<Map<String, Object?>> productStockInsight({
    required int personId,
    required int productId,
    required int campaignId,
  }) async {
    final db = await _db;
    final ownerAvailable =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COALESCE(SUM(quantity_signed),0) FROM inventory_movements WHERE owner_person_id=? AND product_id=?',
            [personId, productId],
          ),
        ) ??
        0;
    final physicalTotal =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COALESCE(SUM(quantity_signed),0) FROM inventory_movements WHERE product_id=?',
            [productId],
          ),
        ) ??
        0;
    final consumedCampaign =
        Sqflite.firstIntValue(
          await db.rawQuery(
            '''SELECT COALESCE(-SUM(m.quantity_signed),0) FROM inventory_movements m
            JOIN applications a ON a.id=m.reference_id AND m.reference_type='APPLICATION'
            WHERE m.owner_person_id=? AND m.product_id=? AND m.type='APPLICATION_OUT'
            AND a.campaign_id=? AND a.reversed_at IS NULL''',
            [personId, productId, campaignId],
          ),
        ) ??
        0;
    final lots = await db.rawQuery(
      '''SELECT l.unit_cost_bob_minor_per_major_unit unit_cost, SUM(m.quantity_signed) available
      FROM inventory_lots l JOIN inventory_movements m ON m.lot_id=l.id
      WHERE l.owner_person_id=? AND l.product_id=? AND l.reversed_at IS NULL
      GROUP BY l.id HAVING available>0 ORDER BY l.acquired_date,l.id''',
      [personId, productId],
    );
    return {
      'owner_available_base': ownerAvailable,
      'physical_total_base': physicalTotal,
      'consumed_campaign_base': consumedCampaign,
      'next_fifo_cost_minor': lots.isEmpty ? 0 : lots.first['unit_cost'],
      'available_lots': lots.length,
    };
  }

  Future<int> estimateFifoCost({
    required int personId,
    required int productId,
    required int quantityBase,
  }) async {
    final lots = await (await _db).rawQuery(
      '''SELECT l.unit_cost_bob_minor_per_major_unit unit_cost, SUM(m.quantity_signed) available
      FROM inventory_lots l JOIN inventory_movements m ON m.lot_id=l.id
      WHERE l.owner_person_id=? AND l.product_id=? AND l.reversed_at IS NULL
      GROUP BY l.id HAVING available>0 ORDER BY l.acquired_date,l.id''',
      [personId, productId],
    );
    var remaining = quantityBase;
    var cost = 0;
    for (final lot in lots) {
      if (remaining <= 0) break;
      final available = lot['available']! as int;
      final take = remaining < available ? remaining : available;
      cost += costForBaseQuantity(take, lot['unit_cost']! as int);
      remaining -= take;
    }
    return cost;
  }

  Future<List<Map<String, Object?>>> settlements({int? campaignId}) async =>
      (await _db).rawQuery(
        '''SELECT p.id, p.name, p.role,
    COALESCE(SUM(t.amount_bob_minor_signed),0) balance,
    COALESCE(SUM(CASE WHEN t.amount_bob_minor_signed>0 THEN t.amount_bob_minor_signed ELSE 0 END),0) charges,
    COALESCE(-SUM(CASE WHEN t.amount_bob_minor_signed<0 THEN t.amount_bob_minor_signed ELSE 0 END),0) payments
    FROM persons p LEFT JOIN account_transactions t ON t.person_id=p.id ${campaignId == null ? '' : 'AND t.campaign_id=?'}
    WHERE p.role<>'ADMIN' GROUP BY p.id ORDER BY balance DESC, p.name''',
        [if (campaignId != null) campaignId],
      );

  Future<List<Map<String, Object?>>> topSettlements({int limit = 5}) async =>
      (await _db).rawQuery(
        '''SELECT p.id, p.name, p.role, COALESCE(SUM(t.amount_bob_minor_signed),0) balance
        FROM persons p LEFT JOIN account_transactions t ON t.person_id=p.id
        WHERE p.role<>'ADMIN' GROUP BY p.id ORDER BY balance DESC,p.name LIMIT ?''',
        [limit],
      );
  Future<List<Map<String, Object?>>> statement(
    int personId, {
    int? campaignId,
  }) async => (await _db).rawQuery(
    '''SELECT * FROM account_transactions
    WHERE person_id=? ${campaignId == null ? '' : 'AND campaign_id=?'} ORDER BY transaction_date,id''',
    [personId, if (campaignId != null) campaignId],
  );

  Future<List<Map<String, Object?>>> detailedStatement(
    int personId, {
    int? campaignId,
  }) async => (await _db).rawQuery(
    '''SELECT t.*,
    COALESCE(
      (SELECT GROUP_CONCAT(p.name, ', ') FROM application_items i JOIN products p ON p.id=i.product_id
       WHERE i.application_id=t.reference_id AND t.reference_type='APPLICATION'),
      (SELECT p.name FROM purchase_allocations a JOIN purchase_items i ON i.id=a.purchase_item_id
       JOIN products p ON p.id=i.product_id WHERE a.id=t.reference_id AND t.reference_type='PURCHASE_ALLOCATION'),
      t.notes, t.type) concept,
    (SELECT f.name FROM applications a JOIN farms f ON f.id=a.farm_id
     WHERE a.id=t.reference_id AND t.reference_type='APPLICATION') farm_name
    FROM account_transactions t WHERE t.person_id=?
    ${campaignId == null ? '' : 'AND t.campaign_id=?'} ORDER BY t.transaction_date,t.id''',
    [personId, if (campaignId != null) campaignId],
  );

  Future<List<Map<String, Object?>>> farmCostReport({int? campaignId}) async =>
      (await _db).rawQuery(
        '''SELECT f.id, f.name, f.area_m2, p.name owner_name,
        COALESCE(SUM(a.total_cost_bob_minor),0) total_cost_bob_minor
        FROM farms f JOIN persons p ON p.id=f.owner_person_id
        LEFT JOIN applications a ON a.farm_id=f.id AND a.reversed_at IS NULL
        ${campaignId == null ? '' : 'AND a.campaign_id=?'} GROUP BY f.id ORDER BY f.name''',
        campaignId == null ? null : [campaignId],
      );

  Future<List<Map<String, Object?>>> productCostReport({
    int? campaignId,
  }) async => (await _db).rawQuery(
    '''SELECT p.id, p.name, p.unit,
        COALESCE(SUM(CASE WHEN a.id IS NOT NULL THEN i.quantity_base ELSE 0 END),0) quantity_base,
        COALESCE(SUM(CASE WHEN a.id IS NOT NULL THEN i.cost_bob_minor ELSE 0 END),0) total_cost_bob_minor
        FROM products p LEFT JOIN application_items i ON i.product_id=p.id
        LEFT JOIN applications a ON a.id=i.application_id AND a.reversed_at IS NULL
        ${campaignId == null ? '' : 'WHERE a.campaign_id=?'} GROUP BY p.id ORDER BY p.name''',
    campaignId == null ? null : [campaignId],
  );

  Future<DashboardSummary> dashboard() async {
    final db = await _db;
    final purchases =
        Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COALESCE(SUM(total_bob_minor),0) FROM purchases WHERE reversed_at IS NULL",
          ),
        ) ??
        0;
    final provider =
        Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COALESCE(SUM(amount_bob_minor),0) FROM provider_payments WHERE reversed_at IS NULL",
          ),
        ) ??
        0;
    final family =
        Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COALESCE(SUM(t.amount_bob_minor_signed),0) FROM account_transactions t JOIN persons p ON p.id=t.person_id WHERE p.role='FAMILY'",
          ),
        ) ??
        0;
    final third =
        Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COALESCE(SUM(t.amount_bob_minor_signed),0) FROM account_transactions t JOIN persons p ON p.id=t.person_id WHERE p.role='THIRD_PARTY'",
          ),
        ) ??
        0;
    final received =
        -(Sqflite.firstIntValue(
              await db.rawQuery(
                "SELECT COALESCE(SUM(amount_bob_minor_signed),0) FROM account_transactions WHERE type IN ('PAYMENT','ADVANCE')",
              ),
            ) ??
            0);
    final stock =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COALESCE(SUM(quantity_signed),0) FROM inventory_movements',
          ),
        ) ??
        0;
    return DashboardSummary(
      purchasesBobMinor: purchases,
      providerPaidMinor: provider,
      familyReceivableMinor: family,
      thirdPartyReceivableMinor: third,
      receivedMinor: received,
      stockBase: stock,
    );
  }

  Future<String> exportBackup() async {
    await (await _db).execute('PRAGMA wal_checkpoint(FULL)');
    final source = appDatabase.openedPath;
    if (source == null || source == ':memory:')
      throw BusinessRuleException(
        'Esta base de datos no admite exportación a archivo.',
      );
    final downloads =
        await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final target = p.join(
      downloads.path,
      'agroquimicos_backup_${DateTime.now().toIso8601String().replaceAll(':', '-')}.db',
    );
    await File(source).copy(target);
    return target;
  }

  Future<String> storeInvoiceImage(String sourcePath) async {
    final directory = await getApplicationDocumentsDirectory();
    final invoices = Directory(p.join(directory.path, 'invoices'));
    await invoices.create(recursive: true);
    final extension = p.extension(sourcePath).isEmpty
        ? '.jpg'
        : p.extension(sourcePath);
    final target = p.join(
      invoices.path,
      'invoice_${DateTime.now().microsecondsSinceEpoch}$extension',
    );
    await File(sourcePath).copy(target);
    return target;
  }
}
