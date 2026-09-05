import 'dart:io';

import 'package:agroquimicos/data/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Firma normalizada del esquema de una base, suficiente para detectar
/// divergencias entre una instalación nueva y una migrada.
///
/// Incluye tablas, columnas (nombre, tipo, nullability, default, PK) e índices
/// (nombre, unicidad, parcialidad y columnas). La unicidad de los índices es la
/// parte crítica: es exactamente donde estaba la divergencia STAB-002.
class SchemaSignature {
  SchemaSignature(this.tables, this.indexes);

  /// tabla -> lista de columnas serializadas.
  final Map<String, List<String>> tables;

  /// tabla -> lista de índices serializados.
  final Map<String, List<String>> indexes;

  static Future<SchemaSignature> read(Database db) async {
    final tableRows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' "
      "AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    final tables = <String, List<String>>{};
    final indexes = <String, List<String>>{};

    for (final row in tableRows) {
      final table = row['name']! as String;

      final columns = await db.rawQuery('PRAGMA table_info($table)');
      tables[table] =
          columns
              .map(
                (c) =>
                    '${c['name']}|type=${c['type']}|notnull=${c['notnull']}'
                    '|default=${c['dflt_value']}|pk=${c['pk']}',
              )
              .toList()
            ..sort();

      final indexList = await db.rawQuery('PRAGMA index_list($table)');
      final serialized = <String>[];
      for (final index in indexList) {
        final name = index['name']! as String;
        // Los índices internos de SQLite para restricciones UNIQUE tienen
        // nombre autogenerado; se comparan igualmente porque derivan del DDL.
        final info = await db.rawQuery('PRAGMA index_info($name)');
        final cols = info.map((i) => i['name']).join(',');
        serialized.add(
          '$name|unique=${index['unique']}|partial=${index['partial']}'
          '|origin=${index['origin']}|cols=$cols',
        );
      }
      indexes[table] = serialized..sort();
    }
    return SchemaSignature(tables, indexes);
  }

  /// Diferencias legibles entre este esquema (el de referencia, creado desde
  /// cero) y [migrated]. Lista vacía significa equivalencia.
  List<String> diff(SchemaSignature migrated) {
    final problems = <String>[];

    final allTables = {...tables.keys, ...migrated.tables.keys}.toList()
      ..sort();
    for (final table in allTables) {
      final fresh = tables[table];
      final upgraded = migrated.tables[table];
      if (upgraded == null) {
        problems.add('TABLA FALTANTE en el esquema migrado: $table');
        continue;
      }
      if (fresh == null) {
        problems.add('TABLA SOBRANTE en el esquema migrado: $table');
        continue;
      }
      for (final column in {...fresh, ...upgraded}) {
        if (!upgraded.contains(column)) {
          problems.add('$table: columna solo en el esquema NUEVO -> $column');
        } else if (!fresh.contains(column)) {
          problems.add('$table: columna solo en el esquema MIGRADO -> $column');
        }
      }
      final freshIdx = indexes[table] ?? const <String>[];
      final upgradedIdx = migrated.indexes[table] ?? const <String>[];
      for (final index in {...freshIdx, ...upgradedIdx}) {
        if (!upgradedIdx.contains(index)) {
          problems.add('$table: índice solo en el esquema NUEVO -> $index');
        } else if (!freshIdx.contains(index)) {
          problems.add('$table: índice solo en el esquema MIGRADO -> $index');
        }
      }
    }
    return problems;
  }
}

/// Esquema tal como era en la versión 3, derivado del bloque `oldVersion < 4`
/// de `_upgradeSchema`: v3 es el esquema actual **menos** exactamente lo que
/// esa migración añade.
const _v3Schema = <String>[
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
  // v3: applications SIN treated_area_m2 ni plan_id (los añade v4).
  '''CREATE TABLE applications (
    id INTEGER PRIMARY KEY AUTOINCREMENT, farm_id INTEGER NOT NULL REFERENCES farms(id),
    person_id INTEGER NOT NULL REFERENCES persons(id), campaign_id INTEGER NOT NULL REFERENCES campaigns(id),
    applied_at TEXT NOT NULL, status TEXT NOT NULL, total_cost_bob_minor INTEGER NOT NULL DEFAULT 0,
    notes TEXT, reversed_at TEXT)''',
  // v3: application_items CON las columnas de v2, SIN las de v4.
  '''CREATE TABLE application_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT, application_id INTEGER NOT NULL REFERENCES applications(id),
    product_id INTEGER NOT NULL REFERENCES products(id), quantity_base INTEGER NOT NULL,
    cost_bob_minor INTEGER NOT NULL DEFAULT 0, treated_area_m2 INTEGER,
    dose_base_per_ha INTEGER, theoretical_quantity_base INTEGER)''',
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
  // v3: transfer_lot_items SIN transfer_item_id (lo añade v4).
  '''CREATE TABLE transfer_lot_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT, transfer_id INTEGER NOT NULL REFERENCES transfers(id),
    source_lot_id INTEGER NOT NULL REFERENCES inventory_lots(id), destination_lot_id INTEGER NOT NULL REFERENCES inventory_lots(id),
    quantity_base INTEGER NOT NULL, cost_bob_minor INTEGER NOT NULL)''',
  '''CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)''',
  // Índices existentes en v3 (los 4 restantes los añade v4).
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
];

void main() {
  sqfliteFfiInit();

  Future<SchemaSignature> freshSchema() async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(database.close);
    return SchemaSignature.read(await database.database);
  }

  test(
    'una base migrada desde V3 queda con el mismo esquema que una nueva',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'agro_schema_v3_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = p.join(directory.path, 'v3.db');

      final legacy = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, _) async {
            for (final statement in _v3Schema) {
              await db.execute(statement);
            }
          },
        ),
      );
      await legacy.close();

      final upgraded = AppDatabase(factory: databaseFactoryFfi, path: path);
      addTearDown(upgraded.close);
      final migrated = await SchemaSignature.read(await upgraded.database);

      final fresh = await freshSchema();
      final problems = fresh.diff(migrated);

      expect(
        problems,
        isEmpty,
        reason:
            'El esquema migrado desde V3 difiere del creado desde cero:\n'
            '${problems.join('\n')}',
      );
    },
  );

  test(
    'los índices de unicidad existen realmente como UNIQUE en base nueva',
    () async {
      final fresh = await freshSchema();
      expect(
        fresh.indexes['application_items'],
        contains(startsWith('idx_application_item_unique|unique=1')),
      );
      expect(
        fresh.indexes['application_plan_items'],
        contains(startsWith('idx_plan_item_unique|unique=1')),
      );
    },
  );

  test(
    'una base V3 con duplicados preexistentes migra sin perder filas ni fallar',
    () async {
      final directory = await Directory.systemTemp.createTemp('agro_dup_v3_');
      addTearDown(() => directory.delete(recursive: true));
      final path = p.join(directory.path, 'v3_dup.db');

      final legacy = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, _) async {
            for (final statement in _v3Schema) {
              await db.execute(statement);
            }
            // Dos filas que violan la unicidad que v5 quiere imponer.
            for (var id = 1; id <= 2; id++) {
              await db.insert('application_items', {
                'id': id,
                'application_id': 10,
                'product_id': 20,
                'quantity_base': 1000,
                'cost_bob_minor': 5000,
              });
            }
          },
        ),
      );
      await legacy.close();

      final upgraded = AppDatabase(factory: databaseFactoryFfi, path: path);
      addTearDown(upgraded.close);
      final db = await upgraded.database;

      // 1. La migración no revienta y la base queda utilizable.
      // 2. Ninguna fila del usuario se elimina.
      expect(
        (await db.query('application_items')).length,
        2,
        reason: 'La migración no debe borrar datos del usuario.',
      );

      // 3. La anomalía queda registrada para que sea diagnosticable.
      final anomaly = await db.query(
        'app_settings',
        where: 'key=?',
        whereArgs: [AppDatabase.duplicateAnomalyKey],
      );
      expect(anomaly, hasLength(1));
      expect(anomaly.single['value'], contains('application_items:1'));

      // 4. El índice sigue existiendo (no único) para no degradar consultas.
      final signature = await SchemaSignature.read(db);
      expect(
        signature.indexes['application_items'],
        contains(startsWith('idx_application_item_unique|unique=0')),
      );
    },
  );

  test(
    'app_settings se crea al migrar, no solo en instalaciones nuevas',
    () async {
      final directory = await Directory.systemTemp.createTemp('agro_settings_');
      addTearDown(() => directory.delete(recursive: true));
      final path = p.join(directory.path, 'v3_nosettings.db');

      final legacy = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, _) async {
            for (final statement in _v3Schema) {
              // Simula una base que nunca tuvo app_settings (migrada de v1/v2).
              if (statement.contains('CREATE TABLE app_settings')) continue;
              await db.execute(statement);
            }
          },
        ),
      );
      await legacy.close();

      final upgraded = AppDatabase(factory: databaseFactoryFfi, path: path);
      addTearDown(upgraded.close);
      final db = await upgraded.database;

      expect(
        await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='app_settings'",
        ),
        isNotEmpty,
      );
    },
  );
}
