import 'package:sqflite/sqflite.dart'
    show ConflictAlgorithm, DatabaseExecutor, Transaction;

import '../domain/installation_access.dart';
import '../domain/models.dart';
import '../domain/operation_mode.dart';
import '../domain/person_roles.dart';
import 'agro_repository.dart' show BusinessRuleException;
import 'app_database.dart';

/// Vínculo inmutable entre el titular local (una persona de `persons`) y el
/// Member/tenant autenticado que lo eligió explícitamente.
class OwnerBinding {
  const OwnerBinding({
    required this.id,
    required this.personId,
    required this.scope,
    required this.ownerRole,
    required this.boundAt,
    this.endedAt,
    this.endReason,
  });

  final int id;
  final int personId;
  final OwnerScope scope;

  /// Rol privado con el que se aceptó al titular (no el rol central).
  final PersonRole ownerRole;
  final String boundAt;
  final String? endedAt;
  final String? endReason;

  bool get isActive => endedAt == null;

  static OwnerBinding fromRow(Map<String, Object?> row) => OwnerBinding(
    id: row['id']! as int,
    personId: row['person_id']! as int,
    scope: OwnerScope(
      memberId: row['member_id']! as String,
      tenantId: row['tenant_id']! as String,
    ),
    ownerRole: personRoleFromCode(row['owner_role'])!,
    boundAt: row['bound_at']! as String,
    endedAt: row['ended_at'] as String?,
    endReason: row['end_reason'] as String?,
  );
}

/// Operaciones de sincronización aún no asentadas de un vínculo. La outbox de
/// F05 implementará este puerto; hasta entonces no existe ninguna.
abstract interface class SyncQueueInspector {
  /// Filas PENDING, SENDING, OUTCOME_UNKNOWN, CONFLICT o ACKED del vínculo.
  Future<int> operationsBoundTo(DatabaseExecutor db, int bindingId);
}

class NoSyncQueueYet implements SyncQueueInspector {
  const NoSyncQueueYet();

  @override
  Future<int> operationsBoundTo(DatabaseExecutor db, int bindingId) async => 0;
}

class OwnerBindingException extends BusinessRuleException {
  OwnerBindingException(super.message);
}

/// La persona figura como administradora de pagos: puede ser titular sólo si
/// se confirma explícitamente que es el agricultor propietario.
class OwnerAdministratorConfirmationRequired extends OwnerBindingException {
  OwnerAdministratorConfirmationRequired()
    : super(
        'Esta persona figura como administradora de pagos. Confirme que es el '
        'agricultor titular: conserva su rol, sus movimientos y sus reglas de '
        'cobro, y no se crea otra persona.',
      );
}

final RegExp _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// Lee y escribe las marcas locales de la política de activación y el
/// vínculo de titular. Nunca deduce el titular por nombre o teléfono, nunca
/// cambia roles de personas y nunca reasigna operaciones. El rol privado de
/// negocio (`persons.role`) no se confunde con el rol central de la cuenta.
class OwnerBindingStore {
  OwnerBindingStore(this._database, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _database;
  final DateTime Function() _clock;

  String _now() => _clock().toUtc().toIso8601String();

  /// Toda escritura del vínculo pasa por la exclusión de sustitución: no
  /// entra mientras se restaura un respaldo.
  Future<void> _transaction(Future<void> Function(Transaction txn) body) =>
      _database.replacement.write(
        () async => (await _database.database).transaction(body),
      );

  Future<OwnerBinding?> activeBinding([DatabaseExecutor? executor]) async {
    final db = executor ?? await _database.database;
    final rows = await db.query('owner_bindings', where: 'ended_at IS NULL');
    return rows.isEmpty ? null : OwnerBinding.fromRow(rows.single);
  }

  Future<List<OwnerBinding>> history() async {
    final db = await _database.database;
    final rows = await db.query('owner_bindings', orderBy: 'id');
    return rows.map(OwnerBinding.fromRow).toList();
  }

  Future<String?> _setting(DatabaseExecutor db, String key) async {
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key=?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : rows.single['value'] as String?;
  }

  /// Sin la clave (sólo por manipulación externa) se trata como histórica:
  /// conserva continuidad y no habilita publicar sin vínculo.
  Future<InstallOrigin> origin() async {
    final value = await _setting(
      await _database.database,
      AppDatabase.installOriginKey,
    );
    return value == AppDatabase.installOriginNew
        ? InstallOrigin.newUnderPolicy
        : InstallOrigin.legacyPrePolicy;
  }

  Future<String?> activatedInstallationRef() async =>
      _setting(await _database.database, AppDatabase.activatedInstallationKey);

  /// Entradas locales del clasificador de acceso (lo que vive en SQLite).
  Future<InstallationAccessInputs> accessInputs({
    required LocalSessionCondition session,
    required OwnerScope? sessionScope,
    required String? currentInstallationRef,
  }) async => InstallationAccessInputs(
    origin: await origin(),
    activeBinding: (await activeBinding())?.scope,
    activatedInstallationRef: await activatedInstallationRef(),
    currentInstallationRef: currentInstallationRef,
    session: session,
    sessionScope: session == LocalSessionCondition.readable
        ? sessionScope
        : null,
  );

  static void _validateScope(OwnerScope scope) {
    if (!_uuid.hasMatch(scope.memberId) || !_uuid.hasMatch(scope.tenantId)) {
      throw OwnerBindingException('El contexto autenticado no es válido.');
    }
  }

  /// Devuelve el rol privado con el que queda el titular. No lo modifica.
  Future<PersonRole> _requireEligibleOwner(
    DatabaseExecutor db,
    int personId, {
    required bool confirmAdministrator,
  }) async {
    final rows = await db.query(
      'persons',
      columns: ['role', 'active'],
      where: 'id=?',
      whereArgs: [personId],
    );
    if (rows.isEmpty) {
      throw OwnerBindingException('La persona elegida no existe.');
    }
    if (rows.single['active'] != 1) {
      throw OwnerBindingException('La persona elegida está archivada.');
    }
    final role = personRoleFromCode(rows.single['role']);
    final eligibility = role == null ? null : ownerEligibility(role);
    if (eligibility == null || eligibility == OwnerEligibility.notEligible) {
      throw OwnerBindingException(
        'Un tercero no puede ser el titular de estos datos. Los roles no se '
        'cambian automáticamente.',
      );
    }
    if (eligibility == OwnerEligibility.requiresAdministratorConfirmation &&
        !confirmAdministrator) {
      throw OwnerAdministratorConfirmationRequired();
    }
    return role!;
  }

  Future<void> _writeActivatedInstallation(
    DatabaseExecutor db,
    String installationRef,
  ) => db.insert('app_settings', {
    'key': AppDatabase.activatedInstallationKey,
    'value': installationRef,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  /// Vincula una persona existente como titular del Member autenticado.
  /// Sólo con la sesión legible del mismo contexto y sin vínculo previo. Un
  /// administrador de pagos exige [confirmAdministrator].
  Future<OwnerBinding> bindExistingPerson({
    required int personId,
    required OwnerScope scope,
    required String installationRef,
    bool confirmAdministrator = false,
  }) async {
    _validateScope(scope);
    await _transaction((txn) async {
      if (await activeBinding(txn) != null) {
        throw OwnerBindingException('Ya existe un titular vinculado.');
      }
      final role = await _requireEligibleOwner(
        txn,
        personId,
        confirmAdministrator: confirmAdministrator,
      );
      await txn.insert('owner_bindings', {
        'person_id': personId,
        'member_id': scope.memberId,
        'tenant_id': scope.tenantId,
        'owner_role': role.code,
        'bound_at': _now(),
      });
      await _writeActivatedInstallation(txn, installationRef);
    });
    return (await activeBinding())!;
  }

  /// Crea la persona del titular (familiar) y su vínculo en una transacción.
  Future<OwnerBinding> bindNewPerson({
    required String name,
    String? phone,
    required OwnerScope scope,
    required String installationRef,
  }) async {
    _validateScope(scope);
    if (name.trim().isEmpty) {
      throw OwnerBindingException('Indique el nombre del titular.');
    }
    await _transaction((txn) async {
      if (await activeBinding(txn) != null) {
        throw OwnerBindingException('Ya existe un titular vinculado.');
      }
      final personId = await txn.insert('persons', {
        'name': name.trim(),
        'role': PersonRole.family.code,
        'settlement_policy': SettlementPolicy.byActualUsage.code,
        'phone': phone?.trim().isEmpty == true ? null : phone?.trim(),
        'created_at': _now(),
      });
      await txn.insert('owner_bindings', {
        'person_id': personId,
        'member_id': scope.memberId,
        'tenant_id': scope.tenantId,
        'owner_role': PersonRole.family.code,
        'bound_at': _now(),
      });
      await _writeActivatedInstallation(txn, installationRef);
    });
    return (await activeBinding())!;
  }

  /// Tras reactivar con el mismo Member en otra instalación (restauración),
  /// registra la instalación actual. No toca el vínculo ni ninguna operación.
  Future<void> recordActivatedInstallation({
    required OwnerScope sessionScope,
    required String installationRef,
  }) async {
    await _transaction((txn) async {
      final binding = await activeBinding(txn);
      if (binding == null || binding.scope != sessionScope) {
        throw OwnerBindingException(
          'La cuenta activa no corresponde al titular de estos datos.',
        );
      }
      await _writeActivatedInstallation(txn, installationRef);
    });
  }

  /// Cambia de titular dentro del mismo Member. Se rechaza en modo propio y
  /// mientras el vínculo actual tenga operaciones de sincronización sin
  /// asentar: una intención nunca cambia de propietario.
  Future<OwnerBinding> changeOwner({
    required int newPersonId,
    required OwnerScope sessionScope,
    SyncQueueInspector queue = const NoSyncQueueYet(),
    bool confirmAdministrator = false,
  }) async {
    await _transaction((txn) async {
      final current = await activeBinding(txn);
      if (current == null) {
        throw OwnerBindingException('No hay titular vinculado.');
      }
      if (current.scope != sessionScope) {
        throw OwnerBindingException(
          'La cuenta activa no corresponde al titular de estos datos.',
        );
      }
      if (current.personId == newPersonId) {
        throw OwnerBindingException('Esa persona ya es el titular.');
      }
      final mode = OperationMode.fromCode(
        await _setting(txn, AppDatabase.operationModeKey),
      );
      if (mode == OperationMode.personal) {
        throw OwnerBindingException(
          'Cambie primero a inventario compartido para cambiar de titular.',
        );
      }
      if (await queue.operationsBoundTo(txn, current.id) > 0) {
        throw OwnerBindingException(
          'Hay envíos al sindicato del titular actual sin asentar. '
          'No se pueden reasignar a otro titular.',
        );
      }
      final role = await _requireEligibleOwner(
        txn,
        newPersonId,
        confirmAdministrator: confirmAdministrator,
      );
      await txn.update(
        'owner_bindings',
        {'ended_at': _now(), 'end_reason': 'OWNER_CHANGED'},
        where: 'id=?',
        whereArgs: [current.id],
      );
      await txn.insert('owner_bindings', {
        'person_id': newPersonId,
        'member_id': current.scope.memberId,
        'tenant_id': current.scope.tenantId,
        'owner_role': role.code,
        'bound_at': _now(),
      });
    });
    return (await activeBinding())!;
  }
}
