import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'database_constants.dart';
import 'migrations_v12_to_v20.dart';
import 'schema_v20.dart';

Future<void> createSchemaV20(
  Database db, {
  required List<String> voiceEvidenceSchema,
}) async {
  for (final statement in baseSchemaV20Statements) {
    await db.execute(statement);
  }
  for (final statement in dbOwnerBindingSchema) {
    await db.execute(statement);
  }
  for (final statement in dbSyncSchema) {
    await db.execute(statement);
  }
  for (final statement in dbReviewAuditSchema) {
    await db.execute(statement);
  }
  await applyInventoryAlertsSchema(db);
  await applyEstimationCopiesSchema(db);
  await applyVoiceEvidenceSchema(db, voiceEvidenceSchema);
  await applyProductIdentificationSchema(db);
  await applyJointPurchaseSchema(db);
  await applyJointPurchaseHistorySchema(db);
  await applyJointPurchaseConsentSchema(db);
  await applyJointPurchaseResponsibleSchema(db);
  await applyJointPurchaseAccessSchema(db);
  await db.insert('app_settings', {
    'key': dbInstallOriginKey,
    'value': dbInstallOriginNew,
  });
}
