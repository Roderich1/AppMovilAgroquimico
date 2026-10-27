import 'dart:math';

import 'package:sqflite/sqflite.dart' show DatabaseExecutor, Transaction;

import '../../domain/campaign_calendar.dart' show CampaignPeriod;
import '../../domain/numeric_input.dart' show maxBaseQuantity;
import '../../domain/sync/intention_planner.dart';
import '../../domain/sync/sync_types.dart';
import '../../domain/sync/sync_wire.dart';
import '../agro_repository.dart' show BusinessRuleException;
import '../app_database.dart';
import '../farmer_operation_gate.dart';
import 'central_binding_store.dart';
import 'sync_outbox_store.dart';

class DeclaredNeedException extends BusinessRuleException {
  DeclaredNeedException(super.message);
}

/// La campaña o el producto no tienen vínculo vigente con el sindicato.
class BindingRequiredException extends DeclaredNeedException {
  BindingRequiredException(super.message);
}

enum DeclaredNeedStatus {
  active('ACTIVE'),
  cancelled('CANCELLED');

  const DeclaredNeedStatus(this.code);
  final String code;

  static DeclaredNeedStatus fromCode(Object? code) =>
      values.firstWhere((status) => status.code == code);
}

/// Por qué no se puede determinar la campaña de una fecha.
enum CampaignForDateProblem {
  /// Ninguna campaña local cubre la fecha.
  none,

  /// Más de una campaña local la cubre: no se elige en silencio.
  ambiguous,

  /// La campaña no está vinculada con el sindicato.
  notBound,

  /// El vínculo dejó de estar vigente.
  bindingInvalid,
}

class CampaignForDate {
  const CampaignForDate({
    this.campaignId,
    this.name,
    this.problem,
    this.reason,
    this.detail,
  });

  final int? campaignId;
  final String? name;
  final CampaignForDateProblem? problem;
  final BindingInvalidReason? reason;

  /// Detalle del problema de período con los dos períodos (D-F04-C2).
  final String? detail;

  bool get isUsable => problem == null;

  String get message => switch (problem) {
    null => 'Campaña: $name',
    CampaignForDateProblem.none =>
      'Ninguna campaña cubre esa fecha. Revise las fechas de sus campañas.',
    CampaignForDateProblem.ambiguous =>
      'Más de una campaña cubre esa fecha. Corrija las fechas de sus campañas.',
    CampaignForDateProblem.notBound =>
      'La campaña $name requiere vinculación con el sindicato.',
    CampaignForDateProblem.bindingInvalid =>
      'La campaña $name no admite declaraciones: '
          '${detail ?? reason?.message ?? ''}',
  };
}

/// Producto local que se puede declarar: activo y con vínculo vigente.
class DeclarableProduct {
  const DeclarableProduct(this.productId, this.name, this.baseUnit);
  final int productId;
  final String name;
  final BaseUnit baseUnit;
}

class DeclaredNeed {
  const DeclaredNeed({
    required this.id,
    required this.ownerBindingId,
    required this.campaignId,
    required this.campaignName,
    required this.productId,
    required this.productName,
    required this.baseUnit,
    required this.status,
    required this.quantityBase,
    required this.referenceDate,
    required this.currentVersion,
    required this.updatedAt,
    required this.syncOperationId,
    required this.syncStatus,
    required this.syncCode,
    required this.conflictResolved,
    this.syncAttempts = 0,
    this.syncAckedAt,
  });

  final int id;
  final int ownerBindingId;
  final int campaignId;
  final String campaignName;
  final int productId;
  final String productName;
  final BaseUnit baseUnit;
  final DeclaredNeedStatus status;
  final int? quantityBase;
  final String referenceDate;
  final int currentVersion;
  final String updatedAt;

  /// Última intención de su contribución; null si no hay nada que enviar
  /// (p. ej. se anuló antes de que saliera la primera).
  final String? syncOperationId;
  final OutboxStatus? syncStatus;
  final String? syncCode;

  /// La última intención es un conflicto que el propietario ya resolvió.
  final bool conflictResolved;

  /// Intentos de envío de la última intención (0: todavía no salió del
  /// teléfono) y cuándo la confirmó el sindicato; sólo para mostrar.
  final int syncAttempts;
  final String? syncAckedAt;

  /// Conflicto pendiente de la decisión del propietario.
  bool get needsResolution =>
      syncStatus == OutboxStatus.conflict && !conflictResolved;
}

class DeclaredNeedVersion {
  const DeclaredNeedVersion({
    required this.version,
    required this.status,
    required this.quantityBase,
    required this.referenceDate,
    required this.operationId,
    required this.createdAt,
  });

  final int version;
  final DeclaredNeedStatus status;
  final int? quantityBase;
  final String referenceDate;
  final String? operationId;
  final String createdAt;
}

/// Cómo resuelve el propietario un conflicto (F05 §6): nunca lo decide la app.
enum ConflictChoice {
  /// Enviar de nuevo su valor local vigente como nueva intención.
  keepMine,

  /// Retirar su declaración.
  withdraw,
}

/// Necesidad declarada (F06-COLL-04, F06 §3): sólo nace de una declaración
/// expresa del agricultor, nunca de un plan, stock ni consumo. Cada cambio
/// escribe la necesidad, su versión y la intención de la outbox en **una**
/// transacción. No toca inventario.
class DeclaredNeedStore {
  DeclaredNeedStore(
    this._database, {
    FarmerOperationGate gate = const FarmerOperationGate.unrestricted(),
    DateTime Function()? clock,
    Random? random,
  }) : _gate = gate,
       _clock = clock ?? DateTime.now,
       _random = random;

  final AppDatabase _database;
  final FarmerOperationGate _gate;
  final DateTime Function() _clock;
  final Random? _random;

  String _now() => _clock().toUtc().toIso8601String();

  Future<T> _write<T>(Future<T> Function(Transaction txn) body) =>
      _database.replacement.write(() async {
        _gate.ensureAllowed();
        return (await _database.database).transaction(body);
      });

  static String _day(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// Día local de una fecha guardada. `addCampaign` guarda instantes en UTC:
  /// una campaña creada a las 21:00 en La Paz queda con el día UTC siguiente,
  /// así que el día se toma en hora local, igual que la fecha de referencia.
  static String _storedLocalDay(String stored) {
    final parsed = DateTime.tryParse(stored);
    if (parsed != null) return _day(parsed.toLocal());
    return stored.length < 10 ? stored : stored.substring(0, 10);
  }

  /// Campaña que corresponde a la fecha de referencia. Debe ser exactamente
  /// una y tener vínculo vigente; si no, no se asigna en silencio.
  static Future<CampaignForDate> campaignForDate(
    DatabaseExecutor db,
    DateTime date,
  ) async {
    final day = _day(date);
    final rows =
        (await db.rawQuery(
          'SELECT id, name, status, start_date, end_date FROM campaigns '
          'ORDER BY id',
        )).where((row) {
          final end = row['end_date'] as String?;
          return _storedLocalDay(row['start_date']! as String).compareTo(day) <=
                  0 &&
              (end == null || _storedLocalDay(end).compareTo(day) >= 0);
        }).toList();
    if (rows.isEmpty) {
      return const CampaignForDate(problem: CampaignForDateProblem.none);
    }
    if (rows.length > 1) {
      return const CampaignForDate(problem: CampaignForDateProblem.ambiguous);
    }
    final id = rows.single['id']! as int;
    final name = rows.single['name']! as String;
    final binding = await CentralBindingStore.campaignBindingOf(db, id);
    if (binding == null) {
      return CampaignForDate(
        campaignId: id,
        name: name,
        problem: CampaignForDateProblem.notBound,
      );
    }
    if (!binding.isValid) {
      String? detail;
      if (binding.invalidReason?.holdsQueue ?? false) {
        detail = CentralBindingStore.periodProblem(
          binding,
          CampaignPeriod.fromRow(rows.single),
        );
      }
      return CampaignForDate(
        campaignId: id,
        name: name,
        problem: CampaignForDateProblem.bindingInvalid,
        reason: binding.invalidReason,
        detail: detail,
      );
    }
    return CampaignForDate(campaignId: id, name: name);
  }

  Future<CampaignForDate> campaignFor(DateTime date) async =>
      campaignForDate(await _database.database, date);

  Future<List<DeclarableProduct>> declarableProducts() async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      'SELECT p.id, p.name, b.base_unit FROM products p '
      'JOIN product_bindings b ON b.product_id = p.id '
      "WHERE p.active = 1 AND b.status = 'VALID' ORDER BY p.name, p.id",
    );
    return rows
        .map(
          (row) => DeclarableProduct(
            row['id']! as int,
            row['name']! as String,
            BaseUnit.fromCode(row['base_unit'])!,
          ),
        )
        .toList();
  }

  Future<int> _activeOwner(DatabaseExecutor txn) async {
    final rows = await txn.query(
      'owner_bindings',
      columns: ['id'],
      where: 'ended_at IS NULL',
    );
    if (rows.isEmpty) {
      throw DeclaredNeedException(
        'Elija primero el titular de estos datos para declarar necesidades.',
      );
    }
    return rows.single['id']! as int;
  }

  /// Vínculos de la necesidad. Un valor nuevo exige vínculos vigentes; una
  /// retirada sólo que existan (Central admite retirar en campaña cerrada).
  Future<ContributionTarget> _target(
    DatabaseExecutor txn, {
    required int ownerBindingId,
    required int campaignId,
    required int productId,
    required bool newValue,
  }) async {
    final campaign = await CentralBindingStore.campaignBindingOf(
      txn,
      campaignId,
    );
    final product = await CentralBindingStore.productBindingOf(txn, productId);
    if (campaign == null || product == null) {
      throw BindingRequiredException(
        'La campaña o el producto requieren vinculación con el sindicato.',
      );
    }
    if (newValue && (!campaign.isValid || !product.isValid)) {
      final reason = (campaign.invalidReason ?? product.invalidReason)!;
      var detail = reason.message;
      // D-F04-C2: con los dos períodos, para que el titular sepa qué fijar.
      if (campaign.invalidReason?.holdsQueue ?? false) {
        final local = await CentralBindingStore.localPeriodOf(txn, campaignId);
        if (local != null) {
          detail = CentralBindingStore.periodProblem(campaign, local) ?? detail;
        }
      }
      throw BindingRequiredException(
        'No se puede declarar un valor nuevo: $detail',
      );
    }
    return ContributionTarget(
      ownerBindingId: ownerBindingId,
      projectionType: ProjectionType.declaredNeed,
      campaignRef: campaign.campaignRef,
      productRef: product.productRef,
      baseUnit: product.baseUnit,
    );
  }

  static void _checkQuantity(int quantityBase) {
    if (quantityBase < 0 || quantityBase > maxBaseQuantity) {
      throw DeclaredNeedException('La cantidad no es válida.');
    }
  }

  Future<void> _recordVersion(
    Transaction txn, {
    required int needId,
    required int version,
    required DeclaredNeedStatus status,
    required int? quantityBase,
    required String referenceDate,
    required String? operationId,
    required String now,
  }) => txn.insert('declared_need_versions', {
    'declared_need_id': needId,
    'version': version,
    'status': status.code,
    'quantity_base': quantityBase,
    'reference_date': referenceDate,
    'operation_id': operationId,
    'created_at': now,
  });

  /// Declara (o actualiza) la necesidad total de un producto para la campaña
  /// que corresponde a [referenceDate]. Cero es una declaración válida.
  Future<int> declare({
    required DateTime referenceDate,
    required int productId,
    required int quantityBase,
  }) {
    _checkQuantity(quantityBase);
    return _write((txn) async {
      final owner = await _activeOwner(txn);
      final campaign = await campaignForDate(txn, referenceDate);
      if (!campaign.isUsable) {
        throw campaign.problem == CampaignForDateProblem.notBound ||
                campaign.problem == CampaignForDateProblem.bindingInvalid
            ? BindingRequiredException(campaign.message)
            : DeclaredNeedException(campaign.message);
      }
      final existing = await txn.query(
        'declared_needs',
        where: 'owner_binding_id=? AND campaign_id=? AND product_id=?',
        whereArgs: [owner, campaign.campaignId, productId],
      );
      final referenceDay = existing.isEmpty
          ? _day(referenceDate)
          : existing.single['reference_date']! as String;
      return _setValue(
        txn,
        owner: owner,
        campaignId: campaign.campaignId!,
        productId: productId,
        quantityBase: quantityBase,
        referenceDay: referenceDay,
        existing: existing.isEmpty ? null : existing.single,
      );
    });
  }

  /// Nuevo total para una necesidad existente: SUPERSEDE (o PUBLISH si
  /// estaba retirada). La campaña y el producto no cambian.
  Future<int> updateQuantity(int needId, int quantityBase) {
    _checkQuantity(quantityBase);
    return _write((txn) async {
      final need = await _need(txn, needId);
      return _setValue(
        txn,
        owner: need['owner_binding_id']! as int,
        campaignId: need['campaign_id']! as int,
        productId: need['product_id']! as int,
        quantityBase: quantityBase,
        referenceDay: need['reference_date']! as String,
        existing: need,
      );
    });
  }

  Future<int> _setValue(
    Transaction txn, {
    required int owner,
    required int campaignId,
    required int productId,
    required int quantityBase,
    required String referenceDay,
    required Map<String, Object?>? existing,
  }) async {
    final now = _now();
    final target = await _target(
      txn,
      ownerBindingId: owner,
      campaignId: campaignId,
      productId: productId,
      newValue: true,
    );
    final prior = await SyncOutboxStore.latestEffective(txn, target);
    final operationId = await SyncOutboxStore.applyPlan(
      txn,
      planIntention(prior, ValueIntent(quantityBase)),
      target,
      now: now,
      random: _random,
    );
    final int needId;
    final int version;
    if (existing == null) {
      version = 1;
      needId = await txn.insert('declared_needs', {
        'owner_binding_id': owner,
        'campaign_id': campaignId,
        'product_id': productId,
        'status': DeclaredNeedStatus.active.code,
        'quantity_base': quantityBase,
        'reference_date': referenceDay,
        'current_version': version,
        'updated_at': now,
      });
    } else {
      needId = existing['id']! as int;
      version = (existing['current_version']! as int) + 1;
      await txn.update(
        'declared_needs',
        {
          'status': DeclaredNeedStatus.active.code,
          'quantity_base': quantityBase,
          'current_version': version,
          'updated_at': now,
        },
        where: 'id=?',
        whereArgs: [needId],
      );
    }
    await _recordVersion(
      txn,
      needId: needId,
      version: version,
      status: DeclaredNeedStatus.active,
      quantityBase: quantityBase,
      referenceDate: referenceDay,
      operationId: operationId,
      now: now,
    );
    return needId;
  }

  /// Retira la necesidad: CANCEL sin cantidad. El historial se conserva y la
  /// retirada queda pendiente de envío.
  Future<void> withdraw(int needId) => _write((txn) async {
    final need = await _need(txn, needId);
    if (DeclaredNeedStatus.fromCode(need['status']) !=
        DeclaredNeedStatus.active) {
      throw DeclaredNeedException('La necesidad ya está anulada.');
    }
    await _withdraw(txn, need);
  });

  Future<void> _withdraw(Transaction txn, Map<String, Object?> need) async {
    final now = _now();
    final target = await _target(
      txn,
      ownerBindingId: need['owner_binding_id']! as int,
      campaignId: need['campaign_id']! as int,
      productId: need['product_id']! as int,
      newValue: false,
    );
    final prior = await SyncOutboxStore.latestEffective(txn, target);
    final operationId = await SyncOutboxStore.applyPlan(
      txn,
      planIntention(prior, const CancelIntent()),
      target,
      now: now,
      random: _random,
    );
    final version = (need['current_version']! as int) + 1;
    await txn.update(
      'declared_needs',
      {
        'status': DeclaredNeedStatus.cancelled.code,
        'quantity_base': null,
        'current_version': version,
        'updated_at': now,
      },
      where: 'id=?',
      whereArgs: [need['id']],
    );
    await _recordVersion(
      txn,
      needId: need['id']! as int,
      version: version,
      status: DeclaredNeedStatus.cancelled,
      quantityBase: null,
      referenceDate: need['reference_date']! as String,
      operationId: operationId,
      now: now,
    );
  }

  /// Resuelve el conflicto de la contribución de [needId] según la decisión
  /// del propietario, sobre el estado que [view] trajo de Central para la
  /// intención en conflicto. La intención en conflicto no se modifica; se
  /// emite una nueva (o se reescribe la que nunca salió) con el head y la
  /// referencia vigentes.
  Future<void> resolveConflict({
    required int needId,
    required ConflictChoice choice,
    required OperationView view,
  }) => _write((txn) async {
    final need = await _need(txn, needId);
    final owner = await _activeOwner(txn);
    if (need['owner_binding_id'] != owner) {
      throw DeclaredNeedException(
        'Esta necesidad pertenece a otro titular: no se resuelve desde aquí.',
      );
    }
    final active =
        DeclaredNeedStatus.fromCode(need['status']) ==
        DeclaredNeedStatus.active;
    final sendsValue = active && choice == ConflictChoice.keepMine;
    final target = await _target(
      txn,
      ownerBindingId: owner,
      campaignId: need['campaign_id']! as int,
      productId: need['product_id']! as int,
      newValue: sendsValue,
    );
    final conflict = await SyncOutboxStore.latestEffective(txn, target);
    final contribution = view.contribution;
    final head = contribution?.headOperationId;
    if (conflict == null ||
        conflict.status != OutboxStatus.conflict ||
        conflict.resolvedAt != null ||
        conflict.operationId != view.ack.operationId ||
        contribution == null ||
        head == null) {
      throw DeclaredNeedException(
        'El estado del conflicto cambió. Vuelva a consultarlo.',
      );
    }
    final now = _now();
    await SyncOutboxStore.markConflictResolved(
      txn,
      conflict,
      headOperationId: head,
      headKind: contribution.headKind,
      now: now,
    );
    final planned = actionFor(
      sendsValue
          ? ValueIntent(need['quantity_base']! as int)
          : const CancelIntent(),
      CausalContext(
        predecessorOperationId: head,
        predecessorKind: contribution.headKind,
        reconciliationReference: contribution.reconciliationReference,
      ),
    );
    // Una sucesora que nunca salió esperaba a la intención en conflicto: pasa
    // a ser la resolución (o se descarta si no hay nada que enviar).
    final waiting = await txn.query(
      'sync_outbox',
      where: "predecessor_operation_id=? AND status='PENDING' AND attempts=0",
      whereArgs: [conflict.operationId],
    );
    final IntentionPlan plan;
    if (waiting.isNotEmpty) {
      final successor = OutboxEntry.fromRow(waiting.single);
      plan = planned == null
          ? DiscardPlan(successor)
          : RewritePlan(successor, planned);
    } else {
      plan = planned == null ? const NothingToSendPlan() : EnqueuePlan(planned);
    }
    final operationId = await SyncOutboxStore.applyPlan(
      txn,
      plan,
      target,
      now: now,
      random: _random,
    );
    if (active && choice == ConflictChoice.withdraw) {
      final version = (need['current_version']! as int) + 1;
      await txn.update(
        'declared_needs',
        {
          'status': DeclaredNeedStatus.cancelled.code,
          'quantity_base': null,
          'current_version': version,
          'updated_at': now,
        },
        where: 'id=?',
        whereArgs: [needId],
      );
      await _recordVersion(
        txn,
        needId: needId,
        version: version,
        status: DeclaredNeedStatus.cancelled,
        quantityBase: null,
        referenceDate: need['reference_date']! as String,
        operationId: operationId,
        now: now,
      );
    }
  });

  Future<Map<String, Object?>> _need(DatabaseExecutor txn, int needId) async {
    final rows = await txn.query(
      'declared_needs',
      where: 'id=?',
      whereArgs: [needId],
    );
    if (rows.isEmpty) {
      throw DeclaredNeedException('La necesidad no existe.');
    }
    return rows.single;
  }

  /// Necesidades del titular activo (las de vínculos anteriores no se
  /// muestran como propias ni se envían).
  Future<List<DeclaredNeed>> needs() async {
    final db = await _database.database;
    final owner = await db.query(
      'owner_bindings',
      columns: ['id'],
      where: 'ended_at IS NULL',
    );
    if (owner.isEmpty) return const [];
    final rows = await db.rawQuery(
      '''SELECT n.*, c.name AS campaign_name, p.name AS product_name,
        p.base_unit AS product_base_unit, o.operation_id AS sync_operation_id,
        o.status AS sync_status, o.last_code AS sync_code,
        o.resolved_at AS sync_resolved_at, o.attempts AS sync_attempts,
        o.acked_at AS sync_acked_at
      FROM declared_needs n
      JOIN campaigns c ON c.id = n.campaign_id
      JOIN products p ON p.id = n.product_id
      LEFT JOIN campaign_bindings cb ON cb.campaign_id = n.campaign_id
      LEFT JOIN product_bindings pb ON pb.product_id = n.product_id
      LEFT JOIN sync_outbox o ON o.id = (
        SELECT MAX(x.id) FROM sync_outbox x
        WHERE x.owner_binding_id = n.owner_binding_id
          AND x.projection_type = 'DECLARED_NEED'
          AND x.campaign_ref = cb.campaign_ref AND x.product_ref = pb.product_ref
          AND x.status <> 'DISCARDED')
      WHERE n.owner_binding_id = ?
      ORDER BY c.start_date DESC, p.name, n.id''',
      [owner.single['id']],
    );
    return rows
        .map(
          (row) => DeclaredNeed(
            id: row['id']! as int,
            ownerBindingId: row['owner_binding_id']! as int,
            campaignId: row['campaign_id']! as int,
            campaignName: row['campaign_name']! as String,
            productId: row['product_id']! as int,
            productName: row['product_name']! as String,
            baseUnit: BaseUnit.fromCode(row['product_base_unit'])!,
            status: DeclaredNeedStatus.fromCode(row['status']),
            quantityBase: row['quantity_base'] as int?,
            referenceDate: row['reference_date']! as String,
            currentVersion: row['current_version']! as int,
            updatedAt: row['updated_at']! as String,
            syncOperationId: row['sync_operation_id'] as String?,
            syncStatus: row['sync_status'] == null
                ? null
                : OutboxStatus.fromCode(row['sync_status']),
            syncCode: row['sync_code'] as String?,
            conflictResolved: row['sync_resolved_at'] != null,
            syncAttempts: (row['sync_attempts'] as int?) ?? 0,
            syncAckedAt: row['sync_acked_at'] as String?,
          ),
        )
        .toList();
  }

  Future<List<DeclaredNeedVersion>> history(int needId) async {
    final db = await _database.database;
    final rows = await db.query(
      'declared_need_versions',
      where: 'declared_need_id=?',
      whereArgs: [needId],
      orderBy: 'version DESC',
    );
    return rows
        .map(
          (row) => DeclaredNeedVersion(
            version: row['version']! as int,
            status: DeclaredNeedStatus.fromCode(row['status']),
            quantityBase: row['quantity_base'] as int?,
            referenceDate: row['reference_date']! as String,
            operationId: row['operation_id'] as String?,
            createdAt: row['created_at']! as String,
          ),
        )
        .toList();
  }
}
