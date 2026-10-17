import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'database_replacement.dart';

class AppDatabase {
  AppDatabase({DatabaseFactory? factory, String? path})
    : _factory = factory,
      _customPath = path;

  /// Versión actual del esquema SQLite.
  ///
  /// Toda base, creada desde cero o migrada desde cualquier versión anterior,
  /// debe terminar con el mismo esquema. `test/schema_equivalence_test.dart`
  /// lo verifica automáticamente.
  static const int schemaVersion = 10;

  /// Primera versión con `owner_bindings` e `install_origin`: una base
  /// anterior es histórica y no declara titular.
  static const int ownerBindingsSinceVersion = 8;

  /// Primera versión con la sincronización F05 (vínculos centrales,
  /// necesidad declarada y outbox).
  static const int syncSinceVersion = 9;

  /// Clave en `app_settings` con cuántos vínculos de campaña anteriores a la
  /// regla de período (D-F04-C2, v10) quedaron marcados «período sin
  /// comprobar» al migrar. Sólo se escribe si hubo al menos uno. No se borra
  /// ningún vínculo ni ninguna intención: se señalan para revisión.
  static const String campaignPeriodReviewKey =
      'schema_v10_campaign_period_review';

  /// Clave en `app_settings` donde se registra que la migración a v5 no pudo
  /// imponer la unicidad por existir filas duplicadas previas. Su presencia
  /// indica que hay datos que requieren revisión manual del propietario.
  static const String duplicateAnomalyKey = 'schema_v5_duplicate_anomaly';

  /// Clave en `app_settings` donde se registra que la migración a v6 encontró
  /// planes aplicados más de una vez —posible con la regla anterior— y no pudo
  /// imponer la unicidad. Su presencia indica datos que el propietario debe
  /// revisar; no se borra ninguna aplicación.
  static const String planReuseAnomalyKey = 'schema_v6_plan_reuse_anomaly';

  /// Clave en `app_settings` donde se registra cuántos movimientos
  /// `TRANSFER_REVERSAL_*` reparó la migración a v7 (F04-BUG-01). Solo se
  /// escribe si se reparó al menos uno.
  static const String transferReversalRepairKey =
      'schema_v7_transfer_reversal_repair';

  /// Clave en `app_settings` con el origen de la base respecto de la política
  /// de primera activación (v8). La escribe el esquema, no el contenido: una
  /// base creada por esta versión nace con [installOriginNew]; una que llega
  /// migrada desde v7 o anterior recibe [installOriginLegacy]. Nunca se infiere
  /// de si la base tiene filas.
  static const String installOriginKey = 'install_origin';
  static const String installOriginNew = 'NEW_UNDER_POLICY';
  static const String installOriginLegacy = 'LEGACY_PRE_POLICY';

  /// Resumen de un solo sentido de la instalación donde se activó por última
  /// vez esta base (ver `installationReference`). No es el installationClientId.
  static const String activatedInstallationKey = 'activated_installation_ref';

  /// Modalidad vigente (`PERSONAL` | `SHARED`); sin la clave rige `SHARED`.
  static const String operationModeKey = 'operation_mode';
  static const String operationModeChangedAtKey = 'operation_mode_changed_at';

  /// Vínculo del titular con su Member (v8). Filas de solo agregado: un
  /// vínculo sólo puede cerrarse una vez; nunca se borra ni se reescribe.
  /// `owner_role` es el rol privado con el que se aceptó al titular (ADMIN
  /// sólo con confirmación explícita); no es el rol central de la cuenta.
  static const List<String> ownerBindingSchema = <String>[
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

  /// Sincronización F05 (v9). Sólo se añaden tablas: ninguna clave local
  /// cambia y ninguna tabla existente recibe un identificador global.
  ///
  /// - `campaign_bindings` / `product_bindings` (F05-SYNC-08): vínculo
  ///   explícito de una campaña o un producto local con su referencia
  ///   central del tenant. Sólo guardan la referencia, el nombre, la unidad y
  ///   el estado necesarios para vincular. Una referencia central no se
  ///   vincula a dos registros locales. Desde v10 (D-F04-C2) el vínculo de
  ///   campaña guarda también el período central en días civiles
  ///   (`central_start_day`, `central_end_day`), lo mínimo para comprobar sin
  ///   red que el período local cabe en él; un vínculo VALID siempre lo tiene.
  /// - `sync_outbox` (F05-SYNC-01/02): una fila por intención, con su
  ///   `operation_id` UUID v4 y el vínculo de titular al que pertenece. Sólo
  ///   lleva los cuatro campos de la whitelist F06 y la causalidad F05. Una
  ///   intención que ya salió del teléfono no se modifica (trigger) y
  ///   ninguna se borra.
  /// - `declared_needs` / `declared_need_versions` (F06-COLL-04): una
  ///   necesidad vigente por titular, campaña y producto, con su historial
  ///   inmutable.
  static const List<String> syncSchema = <String>[
    campaignBindingsTable,
    campaignBindingsIndex,
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

  /// Vínculo de campaña (v10). `central_start_day`/`central_end_day` son días
  /// civiles `aaaa-mm-dd` del contrato de referencias; un vínculo VALID los
  /// tiene siempre. `PERIOD_INCOMPATIBLE`: el período local no cabe en el
  /// central. `PERIOD_UNVERIFIED`: vínculo anterior a v10, sin período
  /// central guardado, hasta actualizar las referencias.
  static const String campaignBindingsTable =
      '''CREATE TABLE campaign_bindings (
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
  static const String campaignBindingsIndex =
      'CREATE UNIQUE INDEX idx_campaign_bindings_ref '
      'ON campaign_bindings(tenant_id, campaign_ref)';

  final DatabaseFactory? _factory;
  final String? _customPath;
  Database? _db;
  String? _path;

  /// Exclusión entre escrituras y sustitución de la base (restaurar). Todo
  /// lo que escribe en esta base pasa por [DatabaseReplacementGuard.write].
  final DatabaseReplacementGuard replacement = DatabaseReplacementGuard();

  Future<Database> get database async {
    // Durante una sustitución no se reabre el archivo a medio copiar.
    await replacement.whenReadable();
    return _db ??= await _open();
  }

  String? get openedPath => _path;

  /// Fábrica efectiva para esta plataforma (o la inyectada en tests).
  ///
  /// La necesita [BackupService] para abrir y validar un archivo de respaldo
  /// candidato sin tocar la base en uso.
  DatabaseFactory get resolvedFactory => _factory ?? _platformFactory();

  /// Ruta que se usaría al abrir, esté o no abierta ya la base.
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
        onCreate: (db, version) => _createSchema(db),
        onUpgrade: _upgradeSchema,
      ),
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

  Future<void> _createSchema(Database db) async {
    const statements = <String>[
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
      // **Un plan representa UNA aplicación planificada** (UIBUG-045). Que no
      // pueda aplicarse dos veces no es una regla de pantalla: es una
      // invariante de los datos, y vive donde vive el dato. El índice parcial
      // sigue el mismo patrón que `idx_campaign_single_active`.
      'CREATE UNIQUE INDEX idx_application_plan_single_use ON applications(plan_id) WHERE plan_id IS NOT NULL',
    ];
    for (final statement in statements) {
      await db.execute(statement);
    }
    for (final statement in ownerBindingSchema) {
      await db.execute(statement);
    }
    for (final statement in syncSchema) {
      await db.execute(statement);
    }
    // Una base creada por esta versión nace bajo la política de activación.
    await db.insert('app_settings', {
      'key': installOriginKey,
      'value': installOriginNew,
    });
  }

  Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
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
      await _upgradeToV5(db);
    }
    if (oldVersion < 6) {
      await _upgradeToV6(db);
    }
    if (oldVersion < 7) {
      await _upgradeToV7(db);
    }
    if (oldVersion < 8) {
      await _upgradeToV8(db);
    }
    if (oldVersion < 9) {
      await _upgradeToV9(db);
    }
    if (oldVersion < 10) {
      await _upgradeToV10(db);
    }
  }

  /// Migración a la versión 10 — **período local contenido en el central**
  /// (D-F04-C2).
  ///
  /// `campaign_bindings` gana `central_start_day` y `central_end_day` y dos
  /// motivos de invalidez. SQLite no amplía un CHECK: la tabla se reconstruye
  /// copiando todas sus filas (mismos `campaign_id`, referencias, nombres y
  /// fechas de alta). Un vínculo que estaba VALID pasa a INVALID con
  /// `PERIOD_UNVERIFIED`: su período central no se conocía, así que no se
  /// puede demostrar que el local quepa; al actualizar las referencias vuelve
  /// a VALID si cabe. Uno ya INVALID conserva su motivo. No se toca ninguna
  /// intención de la outbox, necesidad ni operación; se deja constancia en
  /// `app_settings` de cuántos vínculos quedaron por revisar.
  Future<void> _upgradeToV10(Database db) async {
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
      campaignBindingsTable.replaceFirst(
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
    await db.execute(campaignBindingsIndex);
    if (unverified > 0 && existingTables.contains('app_settings')) {
      await db.insert('app_settings', {
        'key': campaignPeriodReviewKey,
        'value': '$unverified',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  /// Migración a la versión 9 — **sincronización F05** (vínculos centrales,
  /// necesidad declarada y outbox).
  ///
  /// Sólo crea tablas nuevas, vacías: no vincula nada por nombre, no crea
  /// intenciones a partir de datos existentes y no toca ninguna fila. Una
  /// base histórica no publica nada hasta que el titular vincule y declare
  /// de forma explícita.
  Future<void> _upgradeToV9(Database db) async {
    final existingTables = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    )).map((row) => row['name'] as String).toSet();
    if (existingTables.contains('sync_outbox')) return;
    for (final statement in syncSchema) {
      await db.execute(statement);
    }
  }

  /// Migración a la versión 8 — **política de activación y vínculo de
  /// titular** (F03 / F04-MODE).
  ///
  /// Toda base que llega aquí existía antes de la política: se marca
  /// [installOriginLegacy] para tratarla como histórica (compatibilidad
  /// explícita), aunque esté vacía. No se crea ningún vínculo de titular ni se
  /// atribuye nada a ninguna cuenta; eso exige una elección explícita después.
  /// No modifica ninguna fila existente.
  Future<void> _upgradeToV8(Database db) async {
    final existingTables = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    )).map((row) => row['name'] as String).toSet();
    if (!existingTables.contains('owner_bindings')) {
      for (final statement in ownerBindingSchema) {
        await db.execute(statement);
      }
    }
    if (!existingTables.contains('app_settings')) {
      await db.execute(
        'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
    }
    await db.insert('app_settings', {
      'key': installOriginKey,
      'value': installOriginLegacy,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Migración a la versión 7 — **reparación de reversiones de transferencia**
  /// (F04-BUG-01).
  ///
  /// Hasta v6, `reverseTransfer` asignaba a todos los movimientos
  /// `TRANSFER_REVERSAL_IN` / `TRANSFER_REVERSAL_OUT` el `product_id` de la
  /// cabecera `transfers`, que solo guarda el primer producto. En una
  /// transferencia multiproducto eso descuadraba los saldos por producto.
  ///
  /// No cambia el esquema: una base nueva ya nace con la versión 7 y sin
  /// movimientos que reparar. Solo corrige datos, con
  /// [repairTransferReversalProducts], y deja constancia en `app_settings`
  /// de cuántas filas reparó.
  Future<void> _upgradeToV7(Database db) async {
    final existingTables = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    )).map((row) => row['name'] as String).toSet();

    if (!existingTables.contains('inventory_movements') ||
        !existingTables.contains('inventory_lots')) {
      return;
    }

    final repaired = await repairTransferReversalProducts(db);
    if (repaired > 0 && existingTables.contains('app_settings')) {
      await db.insert('app_settings', {
        'key': transferReversalRepairKey,
        'value': '$repaired',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  /// Asigna a cada movimiento `TRANSFER_REVERSAL_*` el `product_id` de su
  /// lote cuando difiere de él. Devuelve cuántas filas cambió.
  ///
  /// Es idempotente: sobre una base ya reparada no encuentra diferencias y
  /// no toca ninguna fila. El resto de movimientos no se modifica.
  static Future<int> repairTransferReversalProducts(DatabaseExecutor db) =>
      db.rawUpdate('''UPDATE inventory_movements
        SET product_id = (SELECT l.product_id FROM inventory_lots l
          WHERE l.id = inventory_movements.lot_id)
        WHERE type IN ('TRANSFER_REVERSAL_IN', 'TRANSFER_REVERSAL_OUT')
          AND lot_id IS NOT NULL
          AND product_id <> (SELECT l.product_id FROM inventory_lots l
            WHERE l.id = inventory_movements.lot_id)''');

  /// Migración a la versión 6 — **un plan se aplica una sola vez**.
  ///
  /// Decisión de producto (UIBUG-045, MODELO A): un plan no es una plantilla
  /// reutilizable, sino **una aplicación planificada**. Al registrarla pasa de
  /// `PLANNED` a `APPLIED` y ya no puede volver a aplicarse — tampoco si esa
  /// aplicación se revierte después, porque revertir corrige un movimiento
  /// real, no devuelve la intención al futuro.
  ///
  /// Hace tres cosas, y ninguna borra datos del usuario:
  ///
  /// 1. Unifica el vocabulario: el estado que se escribía al aplicar era
  ///    `COMPLETED`; pasa a llamarse `APPLIED`.
  /// 2. Repara los planes que la regla anterior devolvía a `PLANNED` al
  ///    revertir la aplicación: si existe una aplicación que los referencia,
  ///    el plan ya se consumió.
  /// 3. Impone la invariante en el motor con un índice único parcial sobre
  ///    `applications(plan_id)`.
  ///
  /// El paso 3 puede chocar con datos anteriores: bajo la regla vieja era
  /// posible aplicar → revertir → volver a aplicar, dejando dos aplicaciones
  /// con el mismo `plan_id`. En ese caso se conserva un índice NO único y se
  /// deja constancia en `app_settings`, igual que hizo v5 con sus duplicados:
  /// eliminar aplicaciones del usuario sin su consentimiento sería peor que
  /// mantener la divergencia.
  Future<void> _upgradeToV6(Database db) async {
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
        'key': planReuseAnomalyKey,
        'value': '$reused',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  /// Migración a la versión 5.
  ///
  /// Corrige dos divergencias entre `_createSchema` y las rutas de migración
  /// anteriores, que dejaban a las bases migradas con un esquema distinto al de
  /// una instalación nueva:
  ///
  /// 1. `idx_application_item_unique` e `idx_plan_item_unique` se creaban como
  ///    índices NO únicos en la migración a v4, mientras que en una base nueva
  ///    son UNIQUE. Eso dejaba a las instalaciones migradas sin la garantía de
  ///    unicidad a nivel de motor.
  /// 2. `app_settings` solo se creaba en `_createSchema`, nunca al migrar.
  ///
  /// No borra ni modifica ninguna fila de datos del usuario. Si encuentra
  /// duplicados preexistentes que impiden imponer la unicidad, conserva el
  /// índice no único (para no degradar el rendimiento de las consultas) y deja
  /// constancia en `app_settings`, en lugar de fallar o de eliminar filas.
  Future<void> _upgradeToV5(Database db) async {
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
        // Se conserva el índice no único: eliminar filas del usuario sin su
        // consentimiento sería peor que mantener la divergencia.
        await db.execute(
          'CREATE INDEX ${promotion.index} '
          'ON ${promotion.table}(${promotion.columns})',
        );
        anomalies.add('${promotion.table}:$duplicates');
      }
    }

    if (anomalies.isNotEmpty) {
      await db.insert('app_settings', {
        'key': duplicateAnomalyKey,
        'value': anomalies.join(','),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
