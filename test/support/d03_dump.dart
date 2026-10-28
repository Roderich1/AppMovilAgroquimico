// D-03: comprobación de que una aplicación aceptada sólo añade sus propias
// filas y no cambia ninguna existente (movimientos, fechas, `acquired_date`,
// costos ni consumos anteriores).
import 'package:flutter_test/flutter_test.dart';

typedef Dump = Map<String, List<Map<String, Object?>>>;

/// [after] conserva intactas, en el mismo orden, todas las filas de
/// [before]; las únicas filas nuevas son las de la aplicación [application]:
/// la aplicación, sus líneas, sus consumos, sus movimientos y su cargo.
void expectOnlyApplicationRows(Dump before, Dump after, int application) {
  expect(after.keys.toSet(), before.keys.toSet());
  final items = {
    for (final row in after['application_items']!)
      if (row['application_id'] == application) row['id'],
  };
  bool belongs(String table, Map<String, Object?> row) => switch (table) {
    'applications' => row['id'] == application,
    'application_items' => row['application_id'] == application,
    'application_consumptions' => items.contains(row['application_item_id']),
    'inventory_movements' || 'account_transactions' =>
      row['reference_type'] == 'APPLICATION' &&
          row['reference_id'] == application,
    _ => false,
  };
  for (final table in before.keys) {
    final old = before[table]!;
    final now = after[table]!;
    expect(now.length, greaterThanOrEqualTo(old.length), reason: table);
    expect(now.sublist(0, old.length), old, reason: '$table: filas previas');
    for (final row in now.sublist(old.length)) {
      expect(belongs(table, row), isTrue, reason: '$table: fila nueva $row');
    }
  }
  expect(
    after['applications']!.where((r) => r['id'] == application),
    hasLength(1),
  );
}
