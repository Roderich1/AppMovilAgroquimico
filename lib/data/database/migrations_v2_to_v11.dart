import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'database_constants.dart';

Future<void> upgradeSchemaV2ToV11(Database db, int oldVersion) async {
  if (oldVersion < 2) {
    await db.execute(
      'ALTER TABLE application_items ADD COLUMN treated_area_m2 INTEGER',
    );
    await db.execute(
      'ALTER TABLE application_items ADD COLUMN dose_base_per_ha INTEGER',
    );
    await db.execute(
      'ALTER TABLE application_items ADD COLUMN theoretical_quantity_base INTEGER',
    );
  }
  if (oldVersion < 3) {
    final existingTables = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    )).map((row) => row['name'] as String).toSet();
    if (existingTables.contains('campaigns')) {
      await db.execute('''UPDATE campaigns SET status='CLOSED'
        WHERE status='ACTIVE' AND id <> (SELECT id FROM campaigns WHERE status='ACTIVE'
        ORDER BY start_date DESC, id DESC LIMIT 1)''');
    }
    const tables = <String>[
      '''CREATE TABLE payment_allocations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        payment_transaction_id INTEGER NOT NULL REFERENCES account_transactions(id),
        charge_transaction_id INTEGER NOT NULL REFERENCES account_transactions(id),
        amount_bob_minor INTEGER NOT NULL CHECK(amount_bob_minor > 0),
        UNIQUE(payment_transaction_id, charge_transaction_id))''',
      '''CREATE TABLE transfers (
        id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER NOT NULL REFERENCES products(id),
        from_person_id INTEGER NOT NULL REFERENCES persons(id), to_person_id INTEGER NOT NULL REFERENCES persons(id),
        transfer_date TEXT NOT NULL, quantity_base INTEGER NOT NULL, total_cost_bob_minor INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'CONFIRMED', notes TEXT, reversed_at TEXT,
        CHECK(from_person_id <> to_person_id))''',
      '''CREATE TABLE transfer_lot_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT, transfer_id INTEGER NOT NULL REFERENCES transfers(id),
        source_lot_id INTEGER NOT NULL REFERENCES inventory_lots(id), destination_lot_id INTEGER NOT NULL REFERENCES inventory_lots(id),
        quantity_base INTEGER NOT NULL, cost_bob_minor INTEGER NOT NULL)''',
    ];
    for (final table in tables) {
      await db.execute(table);
    }
    const indexes = <String, List<String>>{
      'campaigns': [
        "CREATE UNIQUE INDEX idx_campaign_single_active ON campaigns((1)) WHERE status='ACTIVE'",
        'CREATE INDEX idx_campaigns_status ON campaigns(status)',
      ],
      'applications': [
        'CREATE INDEX idx_applications_filters ON applications(campaign_id, person_id, farm_id, applied_at)',
      ],
      'application_items': [
        'CREATE INDEX idx_application_items_product ON application_items(product_id)',
      ],
      'inventory_movements': [
        'CREATE INDEX idx_inventory_filters ON inventory_movements(product_id, owner_person_id, movement_date)',
      ],
      'inventory_lots': [
        'CREATE INDEX idx_inventory_lots_owner ON inventory_lots(product_id, owner_person_id)',
      ],
      'purchases': [
        'CREATE INDEX idx_purchases_campaign_date ON purchases(campaign_id, purchase_date)',
      ],
      'transfers': [
        'CREATE INDEX idx_transfers_filters ON transfers(product_id, from_person_id, to_person_id, transfer_date)',
      ],
    };
    for (final entry in indexes.entries) {
      if (!existingTables.contains(entry.key) && entry.key != 'transfers') {
        continue;
      }
      for (final index in entry.value) {
        await db.execute(index);
      }
    }
  }
  if (oldVersion < 4) {
    final existingTables = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    )).map((row) => row['name'] as String).toSet();
    if (existingTables.contains('transfers')) {
      await db.execute(
        '''CREATE TABLE transfer_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT, transfer_id INTEGER NOT NULL REFERENCES transfers(id),
        product_id INTEGER NOT NULL REFERENCES products(id), quantity_base INTEGER NOT NULL CHECK(quantity_base > 0),
        total_cost_bob_minor INTEGER NOT NULL, UNIQUE(transfer_id, product_id))''',
      );
      await db.execute(
        'ALTER TABLE transfer_lot_items ADD COLUMN transfer_item_id INTEGER REFERENCES transfer_items(id)',
      );
      await db.execute(
        'CREATE INDEX idx_transfer_items_transfer_product ON transfer_items(transfer_id, product_id)',
      );
    }
    if (existingTables.contains('products')) {
      await db.execute(
        'CREATE INDEX idx_products_active_name ON products(active, name)',
      );
    }
    if (existingTables.contains('application_items')) {
      await db.execute('ALTER TABLE application_items ADD COLUMN unit TEXT');
      await db.execute(
        'ALTER TABLE application_items ADD COLUMN variance_quantity_base INTEGER',
      );
      await db.execute(
        'ALTER TABLE application_items ADD COLUMN fifo_estimated_cost_bob_minor INTEGER',
      );
      await db.execute('ALTER TABLE application_items ADD COLUMN notes TEXT');
      await db.execute(
        'CREATE INDEX idx_application_item_unique ON application_items(application_id, product_id)',
      );
    }
    if (existingTables.contains('applications')) {
      await db.execute(
        'ALTER TABLE applications ADD COLUMN treated_area_m2 INTEGER',
      );
      await db.execute(
        'ALTER TABLE applications ADD COLUMN plan_id INTEGER REFERENCES application_plans(id)',
      );
    }
    if (existingTables.contains('application_plan_items')) {
      await db.execute(
        'CREATE INDEX idx_plan_item_unique ON application_plan_items(plan_id, product_id)',
      );
    }
  }
  if (oldVersion < 5) {
    await upgradeToV5(db);
  }
  if (oldVersion < 6) {
    await upgradeToV6(db);
  }
  if (oldVersion < 7) {
    await upgradeToV7(db);
  }
  if (oldVersion < 8) {
    await upgradeToV8(db);
  }
  if (oldVersion < 9) {
    await upgradeToV9(db);
  }
  if (oldVersion < 10) {
    await upgradeToV10(db);
  }
  if (oldVersion < 11) {
    await upgradeToV11(db);
  }
}

Future<void> upgradeToV11(Database db) async {
  final existingTables = (await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table'",
  )).map((row) => row['name'] as String).toSet();
  if (existingTables.contains('reversal_audit')) return;
  for (final statement in dbReviewAuditSchema) {
    await db.execute(statement);
  }
}

Future<void> upgradeToV10(Database db) async {
  final existingTables = (await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table'",
  )).map((row) => row['name'] as String).toSet();
  if (!existingTables.contains('campaign_bindings')) return;
  final columns = (await db.rawQuery('PRAGMA table_info(campaign_bindings)'))
      .map((row) => row['name'] as String)
      .toSet();
  if (columns.contains('central_start_day')) return;

  final unverified =
      mobile.Sqflite.firstIntValue(
        await db.rawQuery(
          "SELECT COUNT(*) FROM campaign_bindings WHERE status='VALID'",
        ),
      ) ??
      0;
  await db.execute(
    dbCampaignBindingsTable.replaceFirst(
      'CREATE TABLE campaign_bindings',
      'CREATE TABLE campaign_bindings_v10',
    ),
  );
  await db.execute(
    'INSERT INTO campaign_bindings_v10 (campaign_id, tenant_id, campaign_ref, '
    'central_name, central_start_day, central_end_day, status, invalid_reason, '
    'bound_at, checked_at) '
    'SELECT campaign_id, tenant_id, campaign_ref, central_name, NULL, NULL, '
    "'INVALID', CASE WHEN status='VALID' THEN 'PERIOD_UNVERIFIED' ELSE invalid_reason END, "
    'bound_at, checked_at FROM campaign_bindings',
  );
  await db.execute('DROP TABLE campaign_bindings');
  await db.execute(
    'ALTER TABLE campaign_bindings_v10 RENAME TO campaign_bindings',
  );
  await db.execute(dbCampaignBindingsIndex);
  if (unverified > 0 && existingTables.contains('app_settings')) {
    await db.insert('app_settings', {
      'key': dbCampaignPeriodReviewKey,
      'value': '$unverified',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

Future<void> upgradeToV9(Database db) async {
  final existingTables = (await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table'",
  )).map((row) => row['name'] as String).toSet();
  if (existingTables.contains('sync_outbox')) return;
  for (final statement in dbSyncSchema) {
    await db.execute(statement);
  }
}

Future<void> upgradeToV8(Database db) async {
  final existingTables = (await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table'",
  )).map((row) => row['name'] as String).toSet();
  if (!existingTables.contains('owner_bindings')) {
    for (final statement in dbOwnerBindingSchema) {
      await db.execute(statement);
    }
  }
  if (!existingTables.contains('app_settings')) {
    await db.execute(
      'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
  }
  await db.insert('app_settings', {
    'key': dbInstallOriginKey,
    'value': dbInstallOriginLegacy,
  }, conflictAlgorithm: ConflictAlgorithm.ignore);
}

Future<void> upgradeToV7(Database db) async {
  final existingTables = (await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table'",
  )).map((row) => row['name'] as String).toSet();

  if (!existingTables.contains('inventory_movements') ||
      !existingTables.contains('inventory_lots')) {
    return;
  }

  final repaired = await repairDatabaseTransferReversalProducts(db);
  if (repaired > 0 && existingTables.contains('app_settings')) {
    await db.insert('app_settings', {
      'key': dbTransferReversalRepairKey,
      'value': '$repaired',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

Future<int> repairDatabaseTransferReversalProducts(DatabaseExecutor db) =>
    db.rawUpdate('''UPDATE inventory_movements
      SET product_id = (SELECT l.product_id FROM inventory_lots l
        WHERE l.id = inventory_movements.lot_id)
      WHERE type IN ('TRANSFER_REVERSAL_IN', 'TRANSFER_REVERSAL_OUT')
        AND lot_id IS NOT NULL
        AND product_id <> (SELECT l.product_id FROM inventory_lots l
          WHERE l.id = inventory_movements.lot_id)''');

Future<void> upgradeToV6(Database db) async {
  final existingTables = (await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table'",
  )).map((row) => row['name'] as String).toSet();

  if (!existingTables.contains('application_plans') ||
      !existingTables.contains('applications')) {
    return;
  }

  await db.execute(
    "UPDATE application_plans SET status='APPLIED' WHERE status='COMPLETED'",
  );
  await db.execute(
    '''UPDATE application_plans SET status='APPLIED'
    WHERE status <> 'APPLIED'
      AND id IN (SELECT plan_id FROM applications WHERE plan_id IS NOT NULL)''',
  );

  final reused =
      mobile.Sqflite.firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM (SELECT plan_id FROM applications '
          'WHERE plan_id IS NOT NULL GROUP BY plan_id HAVING COUNT(*) > 1)',
        ),
      ) ??
      0;

  await db.execute('DROP INDEX IF EXISTS idx_application_plan_single_use');
  if (reused == 0) {
    await db.execute(
      'CREATE UNIQUE INDEX idx_application_plan_single_use '
      'ON applications(plan_id) WHERE plan_id IS NOT NULL',
    );
  } else {
    await db.execute(
      'CREATE INDEX idx_application_plan_single_use '
      'ON applications(plan_id) WHERE plan_id IS NOT NULL',
    );
    await db.insert('app_settings', {
      'key': dbPlanReuseAnomalyKey,
      'value': '$reused',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

Future<void> upgradeToV5(Database db) async {
  final existingTables = (await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table'",
  )).map((row) => row['name'] as String).toSet();

  if (!existingTables.contains('app_settings')) {
    await db.execute(
      'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
  }

  const promotions = <({String index, String table, String columns})>[
    (
      index: 'idx_application_item_unique',
      table: 'application_items',
      columns: 'application_id, product_id',
    ),
    (
      index: 'idx_plan_item_unique',
      table: 'application_plan_items',
      columns: 'plan_id, product_id',
    ),
  ];

  final anomalies = <String>[];
  for (final promotion in promotions) {
    if (!existingTables.contains(promotion.table)) continue;

    final duplicates =
        mobile.Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM (SELECT ${promotion.columns} '
            'FROM ${promotion.table} GROUP BY ${promotion.columns} '
            'HAVING COUNT(*) > 1)',
          ),
        ) ??
        0;

    await db.execute('DROP INDEX IF EXISTS ${promotion.index}');
    if (duplicates == 0) {
      await db.execute(
        'CREATE UNIQUE INDEX ${promotion.index} '
        'ON ${promotion.table}(${promotion.columns})',
      );
    } else {
      await db.execute(
        'CREATE INDEX ${promotion.index} '
        'ON ${promotion.table}(${promotion.columns})',
      );
      anomalies.add('${promotion.table}:$duplicates');
    }
  }

  if (anomalies.isNotEmpty) {
    await db.insert('app_settings', {
      'key': dbDuplicateAnomalyKey,
      'value': anomalies.join(','),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
