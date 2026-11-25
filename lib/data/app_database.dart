import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'database/database_constants.dart';
import 'database/migrations_v12_to_v20.dart';
import 'database/migrations_v2_to_v11.dart';
import 'database/schema_v20.dart';
import 'database_replacement.dart';

class AppDatabase {
  AppDatabase({DatabaseFactory? factory, String? path})
    : _factory = factory,
      _customPath = path;

  static const int schemaVersion = dbSchemaVersion;
  static const int ownerBindingsSinceVersion = dbOwnerBindingsSinceVersion;
  static const int syncSinceVersion = dbSyncSinceVersion;
  static const int reviewAuditSinceVersion = dbReviewAuditSinceVersion;
  static const int inventoryAlertsSinceVersion = dbInventoryAlertsSinceVersion;
  static const int estimationCopiesSinceVersion =
      dbEstimationCopiesSinceVersion;
  static const int voiceEvidenceSinceVersion = dbVoiceEvidenceSinceVersion;
  static const int productIdentificationSinceVersion =
      dbProductIdentificationSinceVersion;
  static const int jointPurchaseSinceVersion = dbJointPurchaseSinceVersion;
  static const int jointPurchaseHistorySinceVersion =
      dbJointPurchaseHistorySinceVersion;
  static const int jointPurchaseConsentSinceVersion =
      dbJointPurchaseConsentSinceVersion;
  static const int jointPurchaseResponsibleSinceVersion =
      dbJointPurchaseResponsibleSinceVersion;
  static const int jointPurchaseRoleAccessSinceVersion =
      dbJointPurchaseRoleAccessSinceVersion;

  static const List<String> jointPurchaseAccessSchema =
      dbJointPurchaseAccessSchema;
  static const Map<String, Map<String, String>>
  jointPurchaseResponsibleColumns = dbJointPurchaseResponsibleColumns;
  static const Map<String, String> jointPurchaseHistoryColumns =
      dbJointPurchaseHistoryColumns;
  static const List<String> jointPurchaseHistorySchema =
      dbJointPurchaseHistorySchema;
  static const List<String> jointPurchaseConsentSchema =
      dbJointPurchaseConsentSchema;
  static const List<String> jointPurchaseSchema = dbJointPurchaseSchema;
  static const Map<String, String> productPhotoColumns = dbProductPhotoColumns;
  static const List<String> productIdentificationSchema =
      dbProductIdentificationSchema;

  /// v14 — evidencia de dictado para la evaluación de la voz (F09-VOZ-13,
  /// MOB #167). Definida directamente aquí para cumplir la guarda de exclusión
  /// que restringe el nombre de las tablas de evidencia a `app_database.dart`.
  static const List<String> voiceEvidenceSchema = <String>[
    '''CREATE TABLE IF NOT EXISTS voice_evidence_consent (
        id INTEGER PRIMARY KEY CHECK(id = 1),
        purpose TEXT NOT NULL CHECK(purpose = 'F09_VOICE_EVALUATION'),
        consent_text_version TEXT NOT NULL CHECK(length(consent_text_version) BETWEEN 1 AND 100),
        granted_at TEXT NOT NULL CHECK(length(granted_at) > 0))''',
    '''CREATE TABLE IF NOT EXISTS voice_evidence (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        format_version INTEGER NOT NULL CHECK(format_version = 1),
        consent_granted_at TEXT NOT NULL CHECK(length(consent_granted_at) > 0),
        recorded_at TEXT NOT NULL CHECK(length(recorded_at) > 0),
        kind TEXT NOT NULL CHECK(kind IN ('PURCHASE','APPLICATION','PLAN')),
        outcome TEXT NOT NULL CHECK(outcome IN ('CONFIRMED','DISCARDED','FAILED')),
        sheet_ref TEXT CHECK(sheet_ref IS NULL OR length(sheet_ref) BETWEEN 1 AND 100),
        transcripts TEXT NOT NULL,
        proposed_fields TEXT NOT NULL,
        corrections TEXT NOT NULL,
        confirmed_fields TEXT,
        engine TEXT,
        model TEXT,
        app_commit TEXT,
        first_partial_ms INTEGER CHECK(first_partial_ms IS NULL OR first_partial_ms >= 0),
        final_ms INTEGER CHECK(final_ms IS NULL OR final_ms >= 0),
        CHECK((outcome = 'CONFIRMED') = (confirmed_fields IS NOT NULL)))''',
  ];

  /// Tablas de la evidencia de dictado (v14).
  static const Set<String> voiceEvidenceTables = {
    'voice_evidence',
    'voice_evidence_consent',
  };

  /// Borra la evidencia de dictado y su consentimiento.
  static Future<void> discardVoiceEvidence(DatabaseExecutor db) async {
    final tables = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' "
      "AND name IN ('voice_evidence','voice_evidence_consent')",
    )).map((row) => row['name'] as String).toSet();
    for (final table in tables) {
      await db.delete(table);
    }
  }

  static const List<String> estimationCopiesSchema = dbEstimationCopiesSchema;
  static Future<void> discardEstimationCopies(DatabaseExecutor db) =>
      discardDatabaseEstimationCopies(db);

  static const Map<String, Map<String, String>> inventoryAlertsColumns =
      dbInventoryAlertsColumns;
  static const int defaultAlertLeadDays = dbDefaultAlertLeadDays;
  static const List<String> inventoryAlertsSchema = dbInventoryAlertsSchema;

  static const String campaignPeriodReviewKey = dbCampaignPeriodReviewKey;
  static const String duplicateAnomalyKey = dbDuplicateAnomalyKey;
  static const String planReuseAnomalyKey = dbPlanReuseAnomalyKey;
  static const String transferReversalRepairKey = dbTransferReversalRepairKey;
  static const String installOriginKey = dbInstallOriginKey;
  static const String installOriginNew = dbInstallOriginNew;
  static const String installOriginLegacy = dbInstallOriginLegacy;
  static const String activatedInstallationKey = dbActivatedInstallationKey;
  static const String operationModeKey = dbOperationModeKey;
  static const String operationModeChangedAtKey = dbOperationModeChangedAtKey;

  static const List<String> ownerBindingSchema = dbOwnerBindingSchema;
  static const List<String> syncSchema = dbSyncSchema;
  static const List<String> reversalEffectTables = dbReversalEffectTables;
  static const List<String> reviewAuditSchema = dbReviewAuditSchema;
  static const String campaignBindingsTable = dbCampaignBindingsTable;
  static const String campaignBindingsIndex = dbCampaignBindingsIndex;

  static Future<int> repairTransferReversalProducts(DatabaseExecutor db) =>
      repairDatabaseTransferReversalProducts(db);

  final DatabaseFactory? _factory;
  final String? _customPath;
  Database? _db;
  String? _path;

  final DatabaseReplacementGuard replacement = DatabaseReplacementGuard();

  Future<Database> get database async {
    await replacement.whenReadable();
    return _db ??= await _open();
  }

  String? get openedPath => _path;

  DatabaseFactory get resolvedFactory => _factory ?? _platformFactory();

  Future<String> resolvePath() async => _customPath ?? await _defaultPath();

  Future<Database> _open() async {
    final factory = _factory ?? _platformFactory();
    final dbPath = _customPath ?? await _defaultPath();
    _path = dbPath;
    return factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) =>
            createSchemaV20(db, voiceEvidenceSchema: voiceEvidenceSchema),
        onUpgrade: _upgradeSchema,
      ),
    );
  }

  Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    await upgradeSchemaV2ToV11(db, oldVersion);
    await upgradeSchemaV12ToV20(
      db,
      oldVersion,
      voiceEvidenceSchema: voiceEvidenceSchema,
    );
  }

  DatabaseFactory _platformFactory() {
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      return databaseFactoryFfi;
    }
    return mobile.databaseFactory;
  }

  Future<String> _defaultPath() async {
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      return p.join(dir.path, 'agroquimicos_v2.db');
    }
    return p.join(await mobile.getDatabasesPath(), 'agroquimicos_v2.db');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
