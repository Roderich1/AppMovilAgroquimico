import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'database_constants.dart';
import 'schema_v20.dart';

/// SQLite requiere recrear las tablas para ampliar sus CHECK. Las claves
/// foráneas quedan activas y la actualización de sqflite es transaccional.
Future<void> allowAccountPasswordInAudit(Database db) async {
  // Padres antes de hijos para recrear y copiar, y al revés para retirar
  // las tablas anteriores. Al renombrar un padre SQLite actualiza el FK
  // de su hijo para que ambos sigan relacionados durante la migración.
  const tables = [
    'reversal_audit',
    'reversal_audit_effects',
    'late_operation_drafts',
    'lot_data_corrections',
    'lot_data_correction_lots',
  ];
  for (final table in tables) {
    final objects = await db.rawQuery(
      "SELECT type, name FROM sqlite_master WHERE tbl_name = ? "
      "AND type IN ('trigger', 'index') AND sql IS NOT NULL",
      [table],
    );
    for (final object in objects) {
      final type = object['type'] == 'trigger' ? 'TRIGGER' : 'INDEX';
      final name = (object['name'] as String).replaceAll('"', '""');
      await db.execute('DROP $type "$name"');
    }
    await db.execute('ALTER TABLE $table RENAME TO v21_$table');
  }
  for (final statement in [
    ...dbReviewAuditSchema,
    ...dbInventoryAlertsSchema,
  ]) {
    await db.execute(statement);
  }
  for (final table in tables) {
    final rows = await db.rawQuery('SELECT 1 FROM v21_$table LIMIT 1');
    if (rows.isNotEmpty) {
      await db.execute('INSERT INTO $table SELECT * FROM v21_$table');
    }
  }
  for (final table in tables.reversed) {
    await db.execute('DROP TABLE v21_$table');
  }
}
