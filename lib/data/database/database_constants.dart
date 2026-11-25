import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const int dbSchemaVersion = 20;
const int dbOwnerBindingsSinceVersion = 8;
const int dbSyncSinceVersion = 9;
const int dbReviewAuditSinceVersion = 11;
const int dbInventoryAlertsSinceVersion = 12;
const int dbEstimationCopiesSinceVersion = 13;
const int dbVoiceEvidenceSinceVersion = 14;
const int dbProductIdentificationSinceVersion = 15;
const int dbJointPurchaseSinceVersion = 16;
const int dbJointPurchaseHistorySinceVersion = 17;
const int dbJointPurchaseConsentSinceVersion = 18;
const int dbJointPurchaseResponsibleSinceVersion = 19;
const int dbJointPurchaseRoleAccessSinceVersion = 20;

const int dbDefaultAlertLeadDays = 30;

const String dbCampaignPeriodReviewKey = 'schema_v10_campaign_period_review';
const String dbDuplicateAnomalyKey = 'schema_v5_duplicate_anomaly';
const String dbPlanReuseAnomalyKey = 'schema_v6_plan_reuse_anomaly';
const String dbTransferReversalRepairKey = 'schema_v7_transfer_reversal_repair';
const String dbInstallOriginKey = 'install_origin';
const String dbInstallOriginNew = 'NEW_UNDER_POLICY';
const String dbInstallOriginLegacy = 'LEGACY_PRE_POLICY';
const String dbActivatedInstallationKey = 'activated_installation_ref';
const String dbOperationModeKey = 'operation_mode';
const String dbOperationModeChangedAtKey = 'operation_mode_changed_at';

const List<String> dbOwnerBindingSchema = <String>[
  '''CREATE TABLE owner_bindings (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      person_id INTEGER NOT NULL REFERENCES persons(id),
      member_id TEXT NOT NULL, tenant_id TEXT NOT NULL,
      owner_role TEXT NOT NULL CHECK(owner_role IN ('FAMILY','ADMIN')),
      bound_at TEXT NOT NULL, ended_at TEXT,
      end_reason TEXT CHECK(end_reason IN ('OWNER_CHANGED')),
      CHECK((ended_at IS NULL) = (end_reason IS NULL)))''',
  'CREATE UNIQUE INDEX idx_owner_bindings_single_active '
      'ON owner_bindings((1)) WHERE ended_at IS NULL',
  '''CREATE TRIGGER trg_owner_bindings_no_delete BEFORE DELETE ON owner_bindings
    BEGIN SELECT RAISE(ABORT, 'owner_bindings no admite borrado'); END''',
  '''CREATE TRIGGER trg_owner_bindings_close_only BEFORE UPDATE ON owner_bindings
    WHEN OLD.ended_at IS NOT NULL OR NEW.ended_at IS NULL
      OR NEW.id IS NOT OLD.id OR NEW.person_id IS NOT OLD.person_id
      OR NEW.member_id IS NOT OLD.member_id OR NEW.tenant_id IS NOT OLD.tenant_id
      OR NEW.owner_role IS NOT OLD.owner_role OR NEW.bound_at IS NOT OLD.bound_at
    BEGIN SELECT RAISE(ABORT, 'owner_bindings: solo se puede cerrar un vínculo activo'); END''',
];

const String dbCampaignBindingsTable = '''CREATE TABLE campaign_bindings (
      campaign_id INTEGER PRIMARY KEY REFERENCES campaigns(id),
      tenant_id TEXT NOT NULL, campaign_ref TEXT NOT NULL,
      central_name TEXT NOT NULL,
      central_start_day TEXT, central_end_day TEXT,
      status TEXT NOT NULL CHECK(status IN ('VALID','INVALID')),
      invalid_reason TEXT CHECK(invalid_reason IN ('REFERENCE_MISSING','NOT_ACCEPTING','PERIOD_INCOMPATIBLE','PERIOD_UNVERIFIED')),
      bound_at TEXT NOT NULL, checked_at TEXT NOT NULL,
      CHECK((status = 'VALID') = (invalid_reason IS NULL)),
      CHECK(status = 'INVALID' OR central_start_day IS NOT NULL),
      CHECK(central_end_day IS NULL OR central_start_day IS NOT NULL))''';

const String dbCampaignBindingsIndex =
    'CREATE UNIQUE INDEX idx_campaign_bindings_ref '
    'ON campaign_bindings(tenant_id, campaign_ref)';

const List<String> dbSyncSchema = <String>[
  dbCampaignBindingsTable,
  dbCampaignBindingsIndex,
  '''CREATE TABLE product_bindings (
      product_id INTEGER PRIMARY KEY REFERENCES products(id),
      tenant_id TEXT NOT NULL, product_ref TEXT NOT NULL,
      central_name TEXT NOT NULL, central_unit TEXT NOT NULL,
      base_unit TEXT NOT NULL CHECK(base_unit IN ('ML','G')),
      status TEXT NOT NULL CHECK(status IN ('VALID','INVALID')),
      invalid_reason TEXT CHECK(invalid_reason IN ('REFERENCE_MISSING','INACTIVE','NOT_LINKABLE')),
      bound_at TEXT NOT NULL, checked_at TEXT NOT NULL,
      CHECK((status = 'VALID') = (invalid_reason IS NULL)))''',
  'CREATE UNIQUE INDEX idx_product_bindings_ref '
      'ON product_bindings(tenant_id, product_ref)',
  '''CREATE TABLE sync_outbox (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      operation_id TEXT NOT NULL UNIQUE CHECK(length(operation_id) = 36),
      owner_binding_id INTEGER NOT NULL REFERENCES owner_bindings(id),
      projection_type TEXT NOT NULL CHECK(projection_type IN ('CONSUMPTION_TOTAL','DECLARED_NEED')),
      action TEXT NOT NULL CHECK(action IN ('PUBLISH','SUPERSEDE','CANCEL')),
      campaign_ref TEXT NOT NULL, product_ref TEXT NOT NULL,
      base_unit TEXT NOT NULL CHECK(base_unit IN ('ML','G')),
      quantity_base TEXT,
      predecessor_operation_id TEXT,
      predecessor_kind TEXT CHECK(predecessor_kind IN ('VALUE','CANCEL')),
      reconciliation_reference TEXT,
      status TEXT NOT NULL CHECK(status IN ('PENDING','SENDING','OUTCOME_UNKNOWN','ACKED','CONFLICT','REJECTED','FAILED','AUTH_PAUSED','OWNER_PAUSED','RESTORE_PAUSED','VERSION_MISMATCH','DISCARDED')),
      attempts INTEGER NOT NULL DEFAULT 0 CHECK(attempts >= 0),
      next_attempt_at TEXT, last_code TEXT,
      ack_reconciliation_reference TEXT, server_accepted_at TEXT,
      resolution_head_operation_id TEXT,
      resolution_head_kind TEXT CHECK(resolution_head_kind IN ('VALUE','CANCEL')),
      resolved_at TEXT,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL, acked_at TEXT,
      CHECK((action = 'CANCEL') = (quantity_base IS NULL)),
      CHECK((predecessor_operation_id IS NULL) = (predecessor_kind IS NULL)),
      CHECK(action = 'PUBLISH' OR predecessor_operation_id IS NOT NULL),
      CHECK((status = 'ACKED') = (server_accepted_at IS NOT NULL)),
      CHECK((resolution_head_operation_id IS NULL) = (resolution_head_kind IS NULL)),
      CHECK((resolved_at IS NULL) = (resolution_head_operation_id IS NULL)),
      CHECK(resolved_at IS NULL OR status = 'CONFLICT'))''',
  'CREATE INDEX idx_sync_outbox_contribution ON sync_outbox('
      'owner_binding_id, projection_type, campaign_ref, product_ref, base_unit, id)',
  'CREATE INDEX idx_sync_outbox_status ON sync_outbox(status, next_attempt_at)',
  '''CREATE TRIGGER trg_sync_outbox_no_delete BEFORE DELETE ON sync_outbox
    BEGIN SELECT RAISE(ABORT, 'sync_outbox no admite borrado'); END''',
  '''CREATE TRIGGER trg_sync_outbox_identity BEFORE UPDATE ON sync_outbox
    WHEN NEW.id IS NOT OLD.id OR NEW.operation_id IS NOT OLD.operation_id
      OR NEW.owner_binding_id IS NOT OLD.owner_binding_id
      OR NEW.created_at IS NOT OLD.created_at OR NEW.attempts < OLD.attempts
    BEGIN SELECT RAISE(ABORT, 'sync_outbox: la identidad de una intención no cambia'); END''',
  '''CREATE TRIGGER trg_sync_outbox_sent_immutable BEFORE UPDATE ON sync_outbox
    WHEN OLD.attempts > 0 AND (NEW.projection_type IS NOT OLD.projection_type
      OR NEW.action IS NOT OLD.action OR NEW.campaign_ref IS NOT OLD.campaign_ref
      OR NEW.product_ref IS NOT OLD.product_ref OR NEW.base_unit IS NOT OLD.base_unit
      OR NEW.quantity_base IS NOT OLD.quantity_base
      OR NEW.predecessor_operation_id IS NOT OLD.predecessor_operation_id
      OR NEW.predecessor_kind IS NOT OLD.predecessor_kind
      OR NEW.reconciliation_reference IS NOT OLD.reconciliation_reference)
    BEGIN SELECT RAISE(ABORT, 'sync_outbox: una intención enviada no se modifica'); END''',
  '''CREATE TRIGGER trg_sync_outbox_acked_final BEFORE UPDATE ON sync_outbox
    WHEN OLD.status = 'ACKED' AND (NEW.status IS NOT 'ACKED'
      OR NEW.server_accepted_at IS NOT OLD.server_accepted_at)
    BEGIN SELECT RAISE(ABORT, 'sync_outbox: una aceptación es definitiva'); END''',
  '''CREATE TABLE declared_needs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      owner_binding_id INTEGER NOT NULL REFERENCES owner_bindings(id),
      campaign_id INTEGER NOT NULL REFERENCES campaigns(id),
      product_id INTEGER NOT NULL REFERENCES products(id),
      status TEXT NOT NULL CHECK(status IN ('ACTIVE','CANCELLED')),
      quantity_base INTEGER CHECK(quantity_base >= 0),
      reference_date TEXT NOT NULL,
      current_version INTEGER NOT NULL CHECK(current_version >= 1),
      updated_at TEXT NOT NULL,
      UNIQUE(owner_binding_id, campaign_id, product_id),
      CHECK((status = 'ACTIVE') = (quantity_base IS NOT NULL)))''',
  '''CREATE TABLE declared_need_versions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      declared_need_id INTEGER NOT NULL REFERENCES declared_needs(id),
      version INTEGER NOT NULL CHECK(version >= 1),
      status TEXT NOT NULL CHECK(status IN ('ACTIVE','CANCELLED')),
      quantity_base INTEGER CHECK(quantity_base >= 0),
      reference_date TEXT NOT NULL,
      operation_id TEXT REFERENCES sync_outbox(operation_id),
      created_at TEXT NOT NULL,
      UNIQUE(declared_need_id, version),
      CHECK((status = 'ACTIVE') = (quantity_base IS NOT NULL)))''',
  '''CREATE TRIGGER trg_declared_needs_no_delete BEFORE DELETE ON declared_needs
    BEGIN SELECT RAISE(ABORT, 'declared_needs no admite borrado'); END''',
  '''CREATE TRIGGER trg_declared_need_versions_no_delete BEFORE DELETE ON declared_need_versions
    BEGIN SELECT RAISE(ABORT, 'declared_need_versions no admite borrado'); END''',
  '''CREATE TRIGGER trg_declared_need_versions_no_update BEFORE UPDATE ON declared_need_versions
    BEGIN SELECT RAISE(ABORT, 'declared_need_versions es un historial inmutable'); END''',
];

const List<String> dbReversalEffectTables = <String>[
  'inventory_movements',
  'account_transactions',
  'inventory_lots',
  'provider_payments',
  'application_consumptions',
];

const List<String> dbReviewAuditSchema = <String>[
  '''CREATE TABLE reversal_audit (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      reversal_ref TEXT NOT NULL UNIQUE CHECK(length(reversal_ref) = 36),
      operation_type TEXT NOT NULL CHECK(operation_type IN ('PURCHASE','APPLICATION','TRANSFER')),
      operation_id INTEGER NOT NULL,
      original_person_id INTEGER,
      original_effective_date TEXT,
      reason TEXT NOT NULL CHECK(length(trim(reason)) > 0),
      actor_person_id INTEGER NOT NULL REFERENCES persons(id),
      actor_binding_id INTEGER NOT NULL REFERENCES owner_bindings(id),
      actor_member_id TEXT NOT NULL CHECK(length(actor_member_id) > 0),
      actor_tenant_id TEXT NOT NULL CHECK(length(actor_tenant_id) > 0),
      actor_method TEXT NOT NULL CHECK(actor_method IN ('LOCAL_PIN')),
      credential_enrolment_ref TEXT NOT NULL CHECK(length(credential_enrolment_ref) > 0),
      recorded_at TEXT NOT NULL,
      UNIQUE(operation_type, operation_id))''',
  '''CREATE TABLE reversal_audit_effects (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      audit_id INTEGER NOT NULL REFERENCES reversal_audit(id),
      table_name TEXT NOT NULL CHECK(table_name IN ('inventory_movements','account_transactions','inventory_lots','provider_payments','application_consumptions')),
      row_id INTEGER NOT NULL,
      UNIQUE(audit_id, table_name, row_id))''',
  '''CREATE TRIGGER trg_reversal_audit_no_update BEFORE UPDATE ON reversal_audit
    BEGIN SELECT RAISE(ABORT, 'reversal_audit es un registro inmutable'); END''',
  '''CREATE TRIGGER trg_reversal_audit_no_delete BEFORE DELETE ON reversal_audit
    BEGIN SELECT RAISE(ABORT, 'reversal_audit no admite borrado'); END''',
  '''CREATE TRIGGER trg_reversal_audit_effects_no_update BEFORE UPDATE ON reversal_audit_effects
    BEGIN SELECT RAISE(ABORT, 'reversal_audit_effects es un registro inmutable'); END''',
  '''CREATE TRIGGER trg_reversal_audit_effects_no_delete BEFORE DELETE ON reversal_audit_effects
    BEGIN SELECT RAISE(ABORT, 'reversal_audit_effects no admite borrado'); END''',
  '''CREATE TABLE late_operation_drafts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      draft_ref TEXT NOT NULL UNIQUE CHECK(length(draft_ref) = 36),
      kind TEXT NOT NULL CHECK(kind IN ('PURCHASE','APPLICATION')),
      campaign_id INTEGER NOT NULL REFERENCES campaigns(id),
      effective_date TEXT NOT NULL,
      captured_at TEXT NOT NULL,
      reason TEXT NOT NULL CHECK(length(trim(reason)) > 0),
      payload TEXT NOT NULL,
      invoice_image_path TEXT,
      status TEXT NOT NULL DEFAULT 'PENDING' CHECK(status IN ('PENDING','CONFIRMED','REJECTED')),
      last_conflict_code TEXT, last_conflict_at TEXT,
      resolved_at TEXT, resolution_note TEXT,
      resolver_person_id INTEGER REFERENCES persons(id),
      resolver_binding_id INTEGER REFERENCES owner_bindings(id),
      resolver_member_id TEXT, resolver_tenant_id TEXT,
      resolver_method TEXT CHECK(resolver_method IS NULL OR resolver_method IN ('LOCAL_PIN')),
      resolver_enrolment_ref TEXT,
      result_operation_id INTEGER,
      CHECK(kind = 'PURCHASE' OR invoice_image_path IS NULL),
      CHECK((status = 'PENDING') = (resolved_at IS NULL)),
      CHECK((status = 'CONFIRMED') = (result_operation_id IS NOT NULL)),
      CHECK(status = 'PENDING' OR (resolver_person_id IS NOT NULL
        AND resolver_binding_id IS NOT NULL AND resolver_member_id IS NOT NULL
        AND resolver_tenant_id IS NOT NULL AND resolver_method IS NOT NULL
        AND resolver_enrolment_ref IS NOT NULL)))''',
  'CREATE INDEX idx_late_operation_drafts_status ON late_operation_drafts(status, captured_at)',
  '''CREATE TRIGGER trg_late_drafts_no_delete BEFORE DELETE ON late_operation_drafts
    BEGIN SELECT RAISE(ABORT, 'late_operation_drafts no admite borrado'); END''',
  '''CREATE TRIGGER trg_late_drafts_resolved_immutable BEFORE UPDATE ON late_operation_drafts
    WHEN (OLD.status <> 'PENDING' AND (NEW.status IS NOT OLD.status
        OR NEW.resolved_at IS NOT OLD.resolved_at OR NEW.result_operation_id IS NOT OLD.result_operation_id
        OR NEW.resolver_person_id IS NOT OLD.resolver_person_id OR NEW.resolver_binding_id IS NOT OLD.resolver_binding_id
        OR NEW.resolver_enrolment_ref IS NOT OLD.resolver_enrolment_ref OR NEW.resolution_note IS NOT OLD.resolution_note
        OR NEW.last_conflict_code IS NOT OLD.last_conflict_code))
      OR NEW.draft_ref IS NOT OLD.draft_ref OR NEW.kind IS NOT OLD.kind
      OR NEW.campaign_id IS NOT OLD.campaign_id
      OR NEW.effective_date IS NOT OLD.effective_date
      OR NEW.captured_at IS NOT OLD.captured_at
      OR NEW.reason IS NOT OLD.reason OR NEW.payload IS NOT OLD.payload
    BEGIN SELECT RAISE(ABORT, 'late_operation_drafts: un borrador resuelto o capturado no se modifica'); END''',
];

Future<void> discardDatabaseEstimationCopies(DatabaseExecutor db) async {
  final tables = (await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' "
    "AND name IN ('estimation_copies','estimation_copy_access',"
    "'estimation_copy_retirements')",
  )).map((row) => row['name'] as String).toSet();
  for (final table in tables) {
    await db.delete(table);
  }
}
