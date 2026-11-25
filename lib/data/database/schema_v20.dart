import 'database_constants.dart';

const List<String> dbJointPurchaseAccessSchema = <String>[
  '''CREATE TABLE IF NOT EXISTS joint_purchase_access_ops (
      operation_id TEXT PRIMARY KEY,
      call_id TEXT NOT NULL,
      tenant_id TEXT NOT NULL,
      member_id TEXT NOT NULL,
      sequence INTEGER NOT NULL CHECK (sequence >= 1),
      scope TEXT NOT NULL CHECK (scope IN ('ADMINISTRATION','TOTALS_ONLY')),
      consent_version TEXT NOT NULL,
      decided_at TEXT NOT NULL,
      send_status TEXT NOT NULL CHECK (send_status IN ('PENDING_SEND','RECEIVED','REJECTED','OUT_OF_TIME','SUPERSEDED','AUTH_PAUSED')),
      attempts INTEGER NOT NULL DEFAULT 0,
      next_attempt_at TEXT,
      last_code TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE (call_id, member_id, sequence))''',
  'CREATE INDEX IF NOT EXISTS idx_joint_purchase_access_ops_status '
      'ON joint_purchase_access_ops(tenant_id, member_id, send_status)',
  '''CREATE TRIGGER IF NOT EXISTS trg_joint_purchase_access_ops_sequence
      BEFORE INSERT ON joint_purchase_access_ops
      WHEN EXISTS (SELECT 1 FROM joint_purchase_consent_ops c
        WHERE c.call_id = NEW.call_id AND c.member_id = NEW.member_id
        AND c.sequence = NEW.sequence)
      BEGIN SELECT RAISE(ABORT, 'JOINT_PURCHASE_DECISION_SEQUENCE_USED'); END''',
];

const Map<String, Map<String, String>> dbJointPurchaseResponsibleColumns = {
  'joint_purchase_calls': {'responsible_version': 'INTEGER'},
  'joint_purchase_participation_ops': {'responsible_version': 'INTEGER'},
  'joint_purchase_consent_ops': {
    'responsible_version': 'INTEGER',
    'authorize_responsible':
        'INTEGER NOT NULL DEFAULT 0 CHECK (authorize_responsible IN (0,1))',
  },
};

const Map<String, String> dbJointPurchaseHistoryColumns = {
  'finished_at': 'TEXT',
};

const List<String> dbJointPurchaseHistorySchema = <String>[
  '''CREATE TABLE IF NOT EXISTS joint_purchase_history_state (
      tenant_id TEXT NOT NULL,
      member_id TEXT NOT NULL,
      older_count INTEGER NOT NULL CHECK (older_count >= 0),
      server_time TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      PRIMARY KEY (tenant_id, member_id))''',
];

const List<String> dbJointPurchaseConsentSchema = <String>[
  '''CREATE TABLE IF NOT EXISTS joint_purchase_consent_ops (
      operation_id TEXT PRIMARY KEY,
      call_id TEXT NOT NULL,
      tenant_id TEXT NOT NULL,
      member_id TEXT NOT NULL,
      sequence INTEGER NOT NULL CHECK (sequence >= 1),
      scope TEXT NOT NULL CHECK (scope IN ('RESPONSIBLE_ONLY','COLLABORATORS')),
      consent_version TEXT NOT NULL,
      decided_at TEXT NOT NULL,
      send_status TEXT NOT NULL CHECK (send_status IN ('PENDING_SEND','RECEIVED','REJECTED','OUT_OF_TIME','SUPERSEDED','AUTH_PAUSED')),
      attempts INTEGER NOT NULL DEFAULT 0,
      next_attempt_at TEXT,
      last_code TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE (call_id, member_id, sequence))''',
  'CREATE INDEX IF NOT EXISTS idx_joint_purchase_consent_ops_status '
      'ON joint_purchase_consent_ops(tenant_id, member_id, send_status)',
];

const List<String> dbJointPurchaseSchema = <String>[
  '''CREATE TABLE IF NOT EXISTS joint_purchase_calls (
      call_id TEXT PRIMARY KEY,
      tenant_id TEXT NOT NULL,
      member_id TEXT NOT NULL,
      name TEXT NOT NULL,
      campaign_ref TEXT,
      campaign_name TEXT,
      status TEXT NOT NULL CHECK (status IN ('OPEN','CLOSED','CANCELLED')),
      opened_at TEXT,
      deadline_at TEXT NOT NULL,
      responsible_name TEXT,
      products_json TEXT NOT NULL,
      server_participation_json TEXT,
      fetched_at TEXT NOT NULL,
      server_time_at_fetch TEXT NOT NULL,
      seen_at TEXT)''',
  '''CREATE TABLE IF NOT EXISTS joint_purchase_participation_ops (
      operation_id TEXT PRIMARY KEY,
      call_id TEXT NOT NULL,
      tenant_id TEXT NOT NULL,
      member_id TEXT NOT NULL,
      sequence INTEGER NOT NULL,
      kind TEXT NOT NULL CHECK (kind IN ('CONFIRM','WITHDRAW')),
      lines_json TEXT,
      consent_version TEXT,
      consent_accepted_at TEXT,
      send_status TEXT NOT NULL CHECK (send_status IN ('PENDING_SEND','RECEIVED','REJECTED','OUT_OF_TIME','SUPERSEDED','AUTH_PAUSED')),
      attempts INTEGER NOT NULL DEFAULT 0,
      next_attempt_at TEXT,
      last_code TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE (call_id, member_id, sequence))''',
  'CREATE INDEX IF NOT EXISTS idx_joint_purchase_calls_unseen '
      'ON joint_purchase_calls(tenant_id, member_id, status, seen_at, deadline_at)',
  'CREATE INDEX IF NOT EXISTS idx_joint_purchase_ops_status '
      'ON joint_purchase_participation_ops(tenant_id, member_id, send_status)',
];

const Map<String, String> dbProductPhotoColumns = {
  'photo_path': 'TEXT',
  'photo_sha256': 'TEXT',
  'photo_updated_at': 'TEXT',
};

const List<String> dbProductIdentificationSchema = <String>[
  '''CREATE TABLE IF NOT EXISTS product_identification_requests (
      request_id TEXT PRIMARY KEY,
      product_id INTEGER NOT NULL UNIQUE REFERENCES products(id),
      tenant_id TEXT NOT NULL,
      sent_name TEXT NOT NULL,
      sent_active_ingredient TEXT,
      sent_unit TEXT NOT NULL CHECK (sent_unit IN ('L','KG')),
      photo_consent_version TEXT,
      photo_consent_at TEXT,
      photo_sha256_consented TEXT,
      send_status TEXT NOT NULL CHECK (send_status IN ('PENDING_SEND','RECEIVED','REJECTED','AUTH_PAUSED')),
      send_attempts INTEGER NOT NULL DEFAULT 0,
      next_attempt_at TEXT,
      last_code TEXT,
      photo_send_status TEXT NOT NULL CHECK (photo_send_status IN ('NONE','PENDING_SEND','SENT','FAILED','REMOVE_PENDING','REMOVED')),
      photo_attempts INTEGER NOT NULL DEFAULT 0,
      photo_next_attempt_at TEXT,
      photo_last_code TEXT,
      server_status TEXT CHECK (server_status IN ('PENDING','LINKED')),
      server_product_ref TEXT,
      server_product_name TEXT,
      server_product_unit TEXT,
      server_resolution TEXT,
      server_note TEXT,
      server_checked_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL)''',
];

const List<String> dbEstimationCopiesSchema = <String>[
  '''CREATE TABLE IF NOT EXISTS estimation_copies (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      member_ref TEXT NOT NULL CHECK(length(member_ref) > 0),
      tenant_ref TEXT NOT NULL CHECK(length(tenant_ref) > 0),
      target_campaign_ref TEXT NOT NULL CHECK(length(target_campaign_ref) > 0),
      owner_binding_id INTEGER NOT NULL,
      context_id TEXT NOT NULL CHECK(length(context_id) > 0),
      generation INTEGER NOT NULL CHECK(generation >= 0),
      format_version INTEGER NOT NULL CHECK(format_version = 1),
      downloaded_at TEXT NOT NULL CHECK(length(downloaded_at) > 0),
      saved_at TEXT NOT NULL,
      payload TEXT NOT NULL,
      UNIQUE(member_ref, tenant_ref, target_campaign_ref))''',
  '''CREATE TABLE IF NOT EXISTS estimation_copy_access (
      id INTEGER PRIMARY KEY CHECK(id = 1),
      context_id TEXT NOT NULL CHECK(length(context_id) > 0),
      generation INTEGER NOT NULL CHECK(generation >= 0))''',
  '''CREATE TABLE IF NOT EXISTS estimation_copy_retirements (
      context_id TEXT NOT NULL CHECK(length(context_id) > 0),
      target_campaign_ref TEXT NOT NULL CHECK(length(target_campaign_ref) > 0),
      generation INTEGER NOT NULL CHECK(generation >= 0),
      PRIMARY KEY(context_id, target_campaign_ref))''',
];

const Map<String, Map<String, String>> dbInventoryAlertsColumns = {
  'inventory_lots': {
    'expiry_date': "TEXT CHECK(expiry_date IS NULL OR (length(expiry_date) = 10 AND date(expiry_date) = expiry_date))",
    'lot_number': 'TEXT CHECK(lot_number IS NULL OR (length(trim(lot_number)) BETWEEN 1 AND 100 AND lot_number = trim(lot_number)))',
  },
  'products': {
    'min_stock_base':
        'INTEGER CHECK(min_stock_base IS NULL OR min_stock_base >= 0)',
    'alert_lead_days': 'INTEGER CHECK(alert_lead_days IS NULL OR alert_lead_days BETWEEN 0 AND 365)',
  },
};

const List<String> dbInventoryAlertsSchema = <String>[
  '''CREATE TABLE IF NOT EXISTS lot_data_corrections (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      purchase_item_id INTEGER NOT NULL REFERENCES purchase_items(id),
      previous_expiry_date TEXT, previous_lot_number TEXT,
      new_expiry_date TEXT, new_lot_number TEXT,
      reason TEXT NOT NULL CHECK(length(trim(reason)) > 0),
      actor_person_id INTEGER NOT NULL REFERENCES persons(id),
      actor_binding_id INTEGER NOT NULL REFERENCES owner_bindings(id),
      actor_member_id TEXT NOT NULL CHECK(length(actor_member_id) > 0),
      actor_tenant_id TEXT NOT NULL CHECK(length(actor_tenant_id) > 0),
      actor_method TEXT NOT NULL CHECK(actor_method IN ('LOCAL_PIN')),
      credential_enrolment_ref TEXT NOT NULL CHECK(length(credential_enrolment_ref) > 0),
      unproven_lot_count INTEGER NOT NULL DEFAULT 0 CHECK(unproven_lot_count >= 0),
      recorded_at TEXT NOT NULL,
      CHECK(previous_expiry_date IS NOT new_expiry_date OR previous_lot_number IS NOT new_lot_number))''',
  'CREATE INDEX IF NOT EXISTS idx_lot_data_corrections_item ON lot_data_corrections(purchase_item_id, id)',
  '''CREATE TABLE IF NOT EXISTS lot_data_correction_lots (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      correction_id INTEGER NOT NULL REFERENCES lot_data_corrections(id),
      lot_id INTEGER NOT NULL REFERENCES inventory_lots(id),
      UNIQUE(correction_id, lot_id))''',
  '''CREATE TRIGGER IF NOT EXISTS trg_lot_data_corrections_no_update BEFORE UPDATE ON lot_data_corrections
    BEGIN SELECT RAISE(ABORT, 'lot_data_corrections es un registro inmutable'); END''',
  '''CREATE TRIGGER IF NOT EXISTS trg_lot_data_corrections_no_delete BEFORE DELETE ON lot_data_corrections
    BEGIN SELECT RAISE(ABORT, 'lot_data_corrections no admite borrado'); END''',
  '''CREATE TRIGGER IF NOT EXISTS trg_lot_data_correction_lots_no_update BEFORE UPDATE ON lot_data_correction_lots
    BEGIN SELECT RAISE(ABORT, 'lot_data_correction_lots es un registro inmutable'); END''',
  '''CREATE TRIGGER IF NOT EXISTS trg_lot_data_correction_lots_no_delete BEFORE DELETE ON lot_data_correction_lots
    BEGIN SELECT RAISE(ABORT, 'lot_data_correction_lots no admite borrado'); END''',
];

const List<String> baseSchemaV20Statements = <String>[
  '''CREATE TABLE persons (
    id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
    role TEXT NOT NULL CHECK(role IN ('ADMIN','FAMILY','THIRD_PARTY')),
    settlement_policy TEXT NOT NULL, phone TEXT, active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL)''',
  '''CREATE TABLE farms (
    id INTEGER PRIMARY KEY AUTOINCREMENT, owner_person_id INTEGER NOT NULL REFERENCES persons(id),
    name TEXT NOT NULL, area_m2 INTEGER NOT NULL CHECK(area_m2 > 0), location TEXT, active INTEGER NOT NULL DEFAULT 1)''',
  '''CREATE TABLE campaigns (
    id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
    start_date TEXT NOT NULL, end_date TEXT, status TEXT NOT NULL DEFAULT 'PLANNED')''',
  '''CREATE TABLE products (
    id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, active_ingredient TEXT,
    unit TEXT NOT NULL CHECK(unit IN ('L','KG')), base_unit TEXT NOT NULL CHECK(base_unit IN ('ML','G')),
    active INTEGER NOT NULL DEFAULT 1)''',
  '''CREATE TABLE suppliers (
    id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, phone TEXT, notes TEXT, active INTEGER NOT NULL DEFAULT 1)''',
  '''CREATE TABLE application_plans (
    id INTEGER PRIMARY KEY AUTOINCREMENT, farm_id INTEGER NOT NULL REFERENCES farms(id),
    campaign_id INTEGER NOT NULL REFERENCES campaigns(id), planned_date TEXT, status TEXT NOT NULL DEFAULT 'DRAFT', notes TEXT)''',
  '''CREATE TABLE application_plan_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT, plan_id INTEGER NOT NULL REFERENCES application_plans(id),
    product_id INTEGER NOT NULL REFERENCES products(id), area_m2 INTEGER NOT NULL,
    dose_base_per_ha INTEGER NOT NULL, required_quantity_base INTEGER NOT NULL)''',
  '''CREATE TABLE purchases (
    id INTEGER PRIMARY KEY AUTOINCREMENT, supplier_id INTEGER NOT NULL REFERENCES suppliers(id),
    campaign_id INTEGER NOT NULL REFERENCES campaigns(id), purchase_date TEXT NOT NULL, invoice_number TEXT,
    default_currency_code TEXT, default_exchange_rate_scaled INTEGER, exchange_rate_source TEXT,
    exchange_rate_note TEXT, total_bob_minor INTEGER NOT NULL, status TEXT NOT NULL, notes TEXT,
    invoice_image_path TEXT, reversed_at TEXT)''',
  '''CREATE TABLE purchase_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT, purchase_id INTEGER NOT NULL REFERENCES purchases(id),
    product_id INTEGER NOT NULL REFERENCES products(id), quantity_base INTEGER NOT NULL,
    price_major_unit INTEGER NOT NULL DEFAULT 1000, currency_code TEXT NOT NULL,
    original_unit_price_minor INTEGER NOT NULL, exchange_rate_scaled INTEGER,
    converted_unit_price_bob_minor INTEGER NOT NULL, original_subtotal_minor INTEGER NOT NULL,
    subtotal_bob_minor INTEGER NOT NULL)''',
  '''CREATE TABLE purchase_allocations (
    id INTEGER PRIMARY KEY AUTOINCREMENT, purchase_item_id INTEGER NOT NULL REFERENCES purchase_items(id),
    person_id INTEGER NOT NULL REFERENCES persons(id), quantity_base INTEGER NOT NULL,
    charge_policy_snapshot TEXT NOT NULL, amount_bob_minor_if_allocation_charge INTEGER, notes TEXT)''',
  '''CREATE TABLE provider_payments (
    id INTEGER PRIMARY KEY AUTOINCREMENT, purchase_id INTEGER NOT NULL REFERENCES purchases(id),
    payer_person_id INTEGER NOT NULL REFERENCES persons(id), payment_date TEXT NOT NULL,
    amount_bob_minor INTEGER NOT NULL CHECK(amount_bob_minor > 0), method TEXT NOT NULL, notes TEXT, reversed_at TEXT)''',
  '''CREATE TABLE inventory_lots (
    id INTEGER PRIMARY KEY AUTOINCREMENT, purchase_item_id INTEGER NOT NULL REFERENCES purchase_items(id),
    product_id INTEGER NOT NULL REFERENCES products(id), owner_person_id INTEGER NOT NULL REFERENCES persons(id),
    acquired_date TEXT NOT NULL, initial_quantity_base INTEGER NOT NULL,
    unit_cost_bob_minor_per_major_unit INTEGER NOT NULL, currency_code TEXT NOT NULL,
    original_unit_price_minor INTEGER NOT NULL, exchange_rate_scaled INTEGER, parent_lot_id INTEGER REFERENCES inventory_lots(id),
    notes TEXT, reversed_at TEXT)''',
  '''CREATE TABLE inventory_movements (
    id INTEGER PRIMARY KEY AUTOINCREMENT, lot_id INTEGER REFERENCES inventory_lots(id),
    product_id INTEGER NOT NULL REFERENCES products(id), owner_person_id INTEGER NOT NULL REFERENCES persons(id),
    movement_date TEXT NOT NULL, type TEXT NOT NULL, quantity_signed INTEGER NOT NULL,
    reference_type TEXT, reference_id INTEGER, notes TEXT)''',
  '''CREATE TABLE applications (
    id INTEGER PRIMARY KEY AUTOINCREMENT, farm_id INTEGER NOT NULL REFERENCES farms(id),
    person_id INTEGER NOT NULL REFERENCES persons(id), campaign_id INTEGER NOT NULL REFERENCES campaigns(id),
    plan_id INTEGER REFERENCES application_plans(id),
    applied_at TEXT NOT NULL, status TEXT NOT NULL, total_cost_bob_minor INTEGER NOT NULL DEFAULT 0,
    treated_area_m2 INTEGER, notes TEXT, reversed_at TEXT)''',
  '''CREATE TABLE application_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT, application_id INTEGER NOT NULL REFERENCES applications(id),
    product_id INTEGER NOT NULL REFERENCES products(id), quantity_base INTEGER NOT NULL,
    cost_bob_minor INTEGER NOT NULL DEFAULT 0, treated_area_m2 INTEGER,
    dose_base_per_ha INTEGER, theoretical_quantity_base INTEGER, unit TEXT,
    variance_quantity_base INTEGER, fifo_estimated_cost_bob_minor INTEGER, notes TEXT)''',
  '''CREATE TABLE application_consumptions (
    id INTEGER PRIMARY KEY AUTOINCREMENT, application_item_id INTEGER NOT NULL REFERENCES application_items(id),
    inventory_lot_id INTEGER NOT NULL REFERENCES inventory_lots(id), quantity_consumed_base INTEGER NOT NULL,
    cost_bob_minor INTEGER NOT NULL, reversed_at TEXT)''',
  '''CREATE TABLE account_transactions (
    id INTEGER PRIMARY KEY AUTOINCREMENT, person_id INTEGER NOT NULL REFERENCES persons(id),
    campaign_id INTEGER REFERENCES campaigns(id), transaction_date TEXT NOT NULL, type TEXT NOT NULL,
    amount_bob_minor_signed INTEGER NOT NULL, reference_type TEXT, reference_id INTEGER, notes TEXT,
    reversal_of_id INTEGER REFERENCES account_transactions(id))''',
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
  '''CREATE TABLE transfer_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT, transfer_id INTEGER NOT NULL REFERENCES transfers(id),
    product_id INTEGER NOT NULL REFERENCES products(id), quantity_base INTEGER NOT NULL CHECK(quantity_base > 0),
    total_cost_bob_minor INTEGER NOT NULL, UNIQUE(transfer_id, product_id))''',
  '''CREATE TABLE transfer_lot_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT, transfer_id INTEGER NOT NULL REFERENCES transfers(id),
    transfer_item_id INTEGER REFERENCES transfer_items(id),
    source_lot_id INTEGER NOT NULL REFERENCES inventory_lots(id), destination_lot_id INTEGER NOT NULL REFERENCES inventory_lots(id),
    quantity_base INTEGER NOT NULL, cost_bob_minor INTEGER NOT NULL)''',
  '''CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)''',
  'CREATE INDEX idx_movements_lot ON inventory_movements(lot_id)',
  'CREATE INDEX idx_account_person_campaign ON account_transactions(person_id, campaign_id, transaction_date)',
  'CREATE INDEX idx_lots_fifo ON inventory_lots(product_id, owner_person_id, acquired_date, id)',
  "CREATE UNIQUE INDEX idx_campaign_single_active ON campaigns((1)) WHERE status='ACTIVE'",
  'CREATE INDEX idx_campaigns_status ON campaigns(status)',
  'CREATE INDEX idx_applications_filters ON applications(campaign_id, person_id, farm_id, applied_at)',
  'CREATE INDEX idx_application_items_product ON application_items(product_id)',
  'CREATE INDEX idx_inventory_filters ON inventory_movements(product_id, owner_person_id, movement_date)',
  'CREATE INDEX idx_inventory_lots_owner ON inventory_lots(product_id, owner_person_id)',
  'CREATE INDEX idx_purchases_campaign_date ON purchases(campaign_id, purchase_date)',
  'CREATE INDEX idx_transfers_filters ON transfers(product_id, from_person_id, to_person_id, transfer_date)',
  'CREATE INDEX idx_products_active_name ON products(active, name)',
  'CREATE UNIQUE INDEX idx_application_item_unique ON application_items(application_id, product_id)',
  'CREATE UNIQUE INDEX idx_plan_item_unique ON application_plan_items(plan_id, product_id)',
  'CREATE INDEX idx_transfer_items_transfer_product ON transfer_items(transfer_id, product_id)',
  'CREATE UNIQUE INDEX idx_application_plan_single_use ON applications(plan_id) WHERE plan_id IS NOT NULL',
];
