import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm, DatabaseExecutor;

import '../domain/operation_mode.dart';
import 'agro_repository.dart' show BusinessRuleException;
import 'app_database.dart';

class ModeTransitionException extends BusinessRuleException {
  ModeTransitionException(super.message, {this.decision});

  final ModeTransitionDecision? decision;
}

/// Persistencia y transiciones de la modalidad (MODE-01, MODE-04).
///
/// La modalidad sólo vive en `app_settings`; el dominio y la base son los
/// mismos en ambas. Ninguna transición modifica ni borra datos de negocio.
class OperationModeStore {
  OperationModeStore(this._database, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _database;
  final DateTime Function() _clock;

  Future<OperationMode> current([DatabaseExecutor? executor]) async {
    final db = executor ?? await _database.database;
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key=?',
      whereArgs: [AppDatabase.operationModeKey],
    );
    return OperationMode.fromCode(
      rows.isEmpty ? null : rows.single['value'] as String?,
    );
  }

  static Future<int?> _ownerPersonId(DatabaseExecutor db) async {
    final rows = await db.query(
      'owner_bindings',
      columns: ['person_id'],
      where: 'ended_at IS NULL',
    );
    return rows.isEmpty ? null : rows.single['person_id']! as int;
  }

  /// Información activa de personas distintas del titular. Sin titular,
  /// todas las personas cuentan como terceros.
  static Future<ThirdPartyActivity> thirdPartyActivity(
    DatabaseExecutor db,
    int? ownerPersonId,
  ) async {
    final owner = ownerPersonId ?? -1;
    final stock = await db.rawQuery(
      '''SELECT owner_person_id FROM inventory_movements
      WHERE owner_person_id <> ? GROUP BY owner_person_id, product_id
      HAVING SUM(quantity_signed) <> 0''',
      [owner],
    );
    final plans = await db.rawQuery(
      '''SELECT ap.id FROM application_plans ap JOIN farms f ON f.id = ap.farm_id
      WHERE f.owner_person_id <> ? AND ap.status IN ('DRAFT', 'PLANNED')''',
      [owner],
    );
    final balances = await db.rawQuery(
      '''SELECT person_id FROM account_transactions WHERE person_id <> ?
      GROUP BY person_id HAVING SUM(amount_bob_minor_signed) <> 0''',
      [owner],
    );
    return ThirdPartyActivity(
      personsWithStock: {for (final r in stock) r['owner_person_id']! as int},
      openPlanIds: {for (final r in plans) r['id']! as int},
      personsWithAccountBalance: {
        for (final r in balances) r['person_id']! as int,
      },
    );
  }

  Future<ModeTransitionDecision> evaluate(
    OperationMode target, [
    DatabaseExecutor? executor,
  ]) async {
    final db = executor ?? await _database.database;
    final owner = await _ownerPersonId(db);
    return evaluateModeTransition(
      from: await current(db),
      to: target,
      hasOwner: owner != null,
      activity: await thirdPartyActivity(db, owner),
    );
  }

  /// Aplica la transición en una sola transacción, re-evaluándola dentro de
  /// ella. Exige confirmación explícita (CU-05, paso 5). Si algo falla, la
  /// modalidad y los datos quedan como estaban.
  Future<ModeTransitionDecision> apply(
    OperationMode target, {
    required bool confirmed,
    @visibleForTesting Future<void> Function(DatabaseExecutor txn)? afterWrite,
  }) async {
    if (!confirmed) {
      throw ModeTransitionException(
        'Confirme el cambio de modalidad para continuar.',
      );
    }
    late ModeTransitionDecision decision;
    // Fuera de una restauración: no cambia la modalidad de una base que se
    // está sustituyendo.
    await _database.replacement.write(
      () async => (await _database.database).transaction((txn) async {
        decision = await evaluate(target, txn);
        if (!decision.allowed) {
          throw ModeTransitionException(
            decision.blocks.contains(ModeTransitionBlock.ownerRequired)
                ? 'El inventario propio necesita un titular vinculado.'
                : 'Hay existencias, planes o saldos de otras personas. '
                      'Resuélvalos en modo compartido antes de pasar a propio.',
            decision: decision,
          );
        }
        if (decision.isNoop) return;
        for (final entry in {
          AppDatabase.operationModeKey: target.code,
          AppDatabase.operationModeChangedAtKey: _clock()
              .toUtc()
              .toIso8601String(),
        }.entries) {
          await txn.insert('app_settings', {
            'key': entry.key,
            'value': entry.value,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        if (afterWrite != null) await afterWrite(txn);
      }),
    );
    return decision;
  }
}
