import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'schema_v20.dart';

Future<void> upgradeSchemaV12ToV20(
  Database db,
  int oldVersion, {
  required List<String> voiceEvidenceSchema,
}) async {
  if (oldVersion < 12) {
    await applyInventoryAlertsSchema(db);
  }
  if (oldVersion < 13) {
    await applyEstimationCopiesSchema(db);
  }
  if (oldVersion < 14) {
    await applyVoiceEvidenceSchema(db, voiceEvidenceSchema);
  }
  if (oldVersion < 15) {
    await applyProductIdentificationSchema(db);
  }
  if (oldVersion < 16) {
    await applyJointPurchaseSchema(db);
  }
  if (oldVersion < 17) {
    await applyJointPurchaseHistorySchema(db);
  }
  if (oldVersion < 18) {
    await applyJointPurchaseConsentSchema(db);
  }
  if (oldVersion < 19) {
    await applyJointPurchaseResponsibleSchema(db);
  }
  if (oldVersion < 20) {
    await applyJointPurchaseAccessSchema(db);
  }
}

Future<void> applyJointPurchaseAccessSchema(DatabaseExecutor db) async {
  await applyJointPurchaseConsentSchema(db);
  for (final statement in dbJointPurchaseAccessSchema) {
    await db.execute(statement);
  }
}

Future<void> applyJointPurchaseResponsibleSchema(DatabaseExecutor db) async {
  for (final table in dbJointPurchaseResponsibleColumns.entries) {
    final existing = (await db.rawQuery('PRAGMA table_info(${table.key})'))
        .map((row) => row['name'] as String)
        .toSet();
    if (existing.isEmpty) continue;
    for (final column in table.value.entries) {
      if (existing.contains(column.key)) continue;
      await db.execute(
        'ALTER TABLE ${table.key} ADD COLUMN ${column.key} ${column.value}',
      );
    }
  }
}

Future<void> applyJointPurchaseConsentSchema(DatabaseExecutor db) async {
  for (final statement in dbJointPurchaseConsentSchema) {
    await db.execute(statement);
  }
}

Future<void> applyJointPurchaseHistorySchema(DatabaseExecutor db) async {
  final existing = (await db.rawQuery(
    'PRAGMA table_info(joint_purchase_calls)',
  )).map((row) => row['name'] as String).toSet();
  if (existing.isNotEmpty) {
    for (final column in dbJointPurchaseHistoryColumns.entries) {
      if (existing.contains(column.key)) continue;
      await db.execute(
        'ALTER TABLE joint_purchase_calls ADD COLUMN '
        '${column.key} ${column.value}',
      );
    }
  }
  for (final statement in dbJointPurchaseHistorySchema) {
    await db.execute(statement);
  }
}

Future<void> applyJointPurchaseSchema(DatabaseExecutor db) async {
  for (final statement in dbJointPurchaseSchema) {
    await db.execute(statement);
  }
}

Future<void> applyProductIdentificationSchema(DatabaseExecutor db) async {
  final existing = (await db.rawQuery('PRAGMA table_info(products)'))
      .map((row) => row['name'] as String)
      .toSet();
  if (existing.isNotEmpty) {
    for (final column in dbProductPhotoColumns.entries) {
      if (existing.contains(column.key)) continue;
      await db.execute(
        'ALTER TABLE products ADD COLUMN ${column.key} ${column.value}',
      );
    }
  }
  for (final statement in dbProductIdentificationSchema) {
    await db.execute(statement);
  }
}

Future<void> applyVoiceEvidenceSchema(
  DatabaseExecutor db,
  List<String> schema,
) async {
  for (final statement in schema) {
    await db.execute(statement);
  }
}

Future<void> applyEstimationCopiesSchema(DatabaseExecutor db) async {
  for (final statement in dbEstimationCopiesSchema) {
    await db.execute(statement);
  }
}

Future<void> applyInventoryAlertsSchema(DatabaseExecutor db) async {
  final tables = (await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table'",
  )).map((row) => row['name'] as String).toSet();
  for (final table in dbInventoryAlertsColumns.entries) {
    if (!tables.contains(table.key)) continue;
    final existing = (await db.rawQuery('PRAGMA table_info(${table.key})'))
        .map((row) => row['name'] as String)
        .toSet();
    for (final column in table.value.entries) {
      if (existing.contains(column.key)) continue;
      await db.execute(
        'ALTER TABLE ${table.key} ADD COLUMN ${column.key} ${column.value}',
      );
    }
  }
  for (final statement in dbInventoryAlertsSchema) {
    await db.execute(statement);
  }
}
