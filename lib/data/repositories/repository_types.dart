import '../app_database.dart';

export '../../domain/repository_types.dart';

/// RF-13: las filas compensatorias que escribe o anula una reversión, para
/// referenciarlas en `reversal_audit_effects`.
class ReversalEffects {
  ReversalEffects() : _discard = false;
  ReversalEffects.discard() : _discard = true;

  final bool _discard;
  final List<(String, int)> _rows = [];

  List<(String, int)> get rows => List.unmodifiable(_rows);

  void add(String table, int rowId) {
    if (_discard) return;
    if (!AppDatabase.reversalEffectTables.contains(table)) {
      throw ArgumentError.value(table, 'table', 'not a reversal effect table');
    }
    _rows.add((table, rowId));
  }
}
