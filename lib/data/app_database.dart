import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class AppDatabase {
  AppDatabase({DatabaseFactory? factory, String? path})
    : _factory = factory,
      _customPath = path;

  /// Versión actual del esquema SQLite.
  ///
  /// Toda base, creada desde cero o migrada desde cualquier versión anterior,
  /// debe terminar con el mismo esquema. `test/schema_equivalence_test.dart`
  /// lo verifica automáticamente.
  static const int schemaVersion = 6;

  /// Clave en `app_settings` donde se registra que la migración a v5 no pudo
  /// imponer la unicidad por existir filas duplicadas previas. Su presencia
  /// indica que hay datos que requieren revisión manual del propietario.
  static const String duplicateAnomalyKey = 'schema_v5_duplicate_anomaly';

  /// Clave en `app_settings` donde se registra que la migración a v6 encontró
  /// planes aplicados más de una vez —posible con la regla anterior— y no pudo
  /// imponer la unicidad. Su presencia indica datos que el propietario debe
  /// revisar; no se borra ninguna aplicación.
  static const String planReuseAnomalyKey = 'schema_v6_plan_reuse_anomaly';

  final DatabaseFactory? _factory;
  final String? _customPath;
  Database? _db;
  String? _path;

  Future<Database> get database async => _db ??= await _open();
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
  }

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
