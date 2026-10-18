import 'package:sqflite/sqflite.dart' show DatabaseExecutor, Transaction;

import '../../domain/campaign_calendar.dart';
import '../../domain/sync/campaign_period_check.dart';
import '../../domain/sync/central_references.dart';
import '../../domain/sync/sync_types.dart';
import '../agro_repository.dart' show BusinessRuleException;
import '../app_database.dart';
import '../farmer_operation_gate.dart';

class CentralBindingException extends BusinessRuleException {
  CentralBindingException(super.message);
}

enum BindingStatus {
  valid('VALID'),
  invalid('INVALID');

  const BindingStatus(this.code);
  final String code;

  static BindingStatus fromCode(Object? code) =>
      values.firstWhere((status) => status.code == code);
}

/// Por qué un vínculo dejó de admitir publicaciones nuevas.
enum BindingInvalidReason {
  referenceMissing('REFERENCE_MISSING', 'Ya no figura en el sindicato.'),
  notAccepting('NOT_ACCEPTING', 'La campaña no admite nuevos aportes.'),
  inactive('INACTIVE', 'El producto está inactivo en el sindicato.'),
  notLinkable('NOT_LINKABLE', 'La unidad central ya no es L ni KG.'),

  /// D-F04-C2: el período local no cabe en el de la campaña central.
  periodIncompatible(
    'PERIOD_INCOMPATIBLE',
    'El período local no cabe en el de la campaña del sindicato.',
  ),

  /// D-F04-C2: vínculo anterior a la regla, sin el período central guardado.
  /// Hasta actualizar las referencias no se puede demostrar que quepa.
  periodUnverified(
    'PERIOD_UNVERIFIED',
    'El período de la campaña del sindicato no se ha comprobado: actualice '
        'las referencias.',
  );

  const BindingInvalidReason(this.code, this.message);
  final String code;
  final String message;

  /// Motivos que bloquean el envío de intenciones nuevas desde el teléfono:
  /// Central no los detecta por sí sola (aceptaría un total con días fuera
  /// de su período).
  bool get holdsQueue => this == periodIncompatible || this == periodUnverified;

  static BindingInvalidReason? fromCode(Object? code) {
    for (final reason in values) {
      if (reason.code == code) return reason;
    }
    return null;
  }
}

class CampaignBinding {
  const CampaignBinding({
    required this.campaignId,
    required this.tenantId,
    required this.campaignRef,
    required this.centralName,
    required this.centralStartDay,
    required this.centralEndDay,
    required this.status,
    required this.invalidReason,
    required this.boundAt,
    required this.checkedAt,
  });

  final int campaignId;
  final String tenantId;
  final String campaignRef;
  final String centralName;

  /// Período central (días civiles) leído al vincular o al refrescar; nulo en
  /// vínculos anteriores a la regla, hasta que se actualicen las referencias.
  final String? centralStartDay;
  final String? centralEndDay;
  final BindingStatus status;
  final BindingInvalidReason? invalidReason;
  final String boundAt;
  final String checkedAt;

  bool get isValid => status == BindingStatus.valid;

  CentralPeriod? get centralPeriod => centralStartDay == null
      ? null
      : CentralPeriod(startDay: centralStartDay!, endDay: centralEndDay);

  /// D-F04-C2 (C2-R1): la compatibilidad temporal **no está demostrada** para
  /// [local], sea cual sea el motivo de invalidez guardado. Sin período
  /// central conocido, o sin período local (campaña que no se pudo leer), no
  /// se puede comprobar y se retiene: falla cerrado. Con los dos, el local
  /// tiene que caber. Decide la retención de la cola, aparte del motivo que
  /// se muestra.
  bool periodHold(CampaignPeriod? local) {
    final central = centralPeriod;
    if (central == null || local == null) return true;
    return periodMismatch(local, central) != null;
  }

  CampaignBinding _withStatus(BindingInvalidReason? reason) => CampaignBinding(
    campaignId: campaignId,
    tenantId: tenantId,
    campaignRef: campaignRef,
    centralName: centralName,
    centralStartDay: centralStartDay,
    centralEndDay: centralEndDay,
    status: reason == null ? BindingStatus.valid : BindingStatus.invalid,
    invalidReason: reason,
    boundAt: boundAt,
    checkedAt: checkedAt,
  );

  static CampaignBinding fromRow(Map<String, Object?> row) => CampaignBinding(
    campaignId: row['campaign_id']! as int,
    tenantId: row['tenant_id']! as String,
    campaignRef: row['campaign_ref']! as String,
    centralName: row['central_name']! as String,
    centralStartDay: row['central_start_day'] as String?,
    centralEndDay: row['central_end_day'] as String?,
    status: BindingStatus.fromCode(row['status']),
    invalidReason: BindingInvalidReason.fromCode(row['invalid_reason']),
    boundAt: row['bound_at']! as String,
    checkedAt: row['checked_at']! as String,
  );
}

class ProductBinding {
  const ProductBinding({
    required this.productId,
    required this.tenantId,
    required this.productRef,
    required this.centralName,
    required this.centralUnit,
    required this.baseUnit,
    required this.status,
    required this.invalidReason,
    required this.boundAt,
    required this.checkedAt,
  });

  final int productId;
  final String tenantId;
  final String productRef;
  final String centralName;
  final String centralUnit;
  final BaseUnit baseUnit;
  final BindingStatus status;
  final BindingInvalidReason? invalidReason;
  final String boundAt;
  final String checkedAt;

  bool get isValid => status == BindingStatus.valid;

  static ProductBinding fromRow(Map<String, Object?> row) => ProductBinding(
    productId: row['product_id']! as int,
    tenantId: row['tenant_id']! as String,
    productRef: row['product_ref']! as String,
    centralName: row['central_name']! as String,
    centralUnit: row['central_unit']! as String,
    baseUnit: BaseUnit.fromCode(row['base_unit'])!,
    status: BindingStatus.fromCode(row['status']),
    invalidReason: BindingInvalidReason.fromCode(row['invalid_reason']),
    boundAt: row['bound_at']! as String,
    checkedAt: row['checked_at']! as String,
  );
}

/// Un vínculo de campaña que requiere revisión del titular (D-F04-C2), con
/// los aportes que lo usan: los aceptados por Central y los que esperan en la
/// cola. Nada de esto se reescribe ni se reasigna; se muestra.
class CampaignBindingReview {
  const CampaignBindingReview({
    required this.binding,
    required this.local,
    required this.acceptedContributions,
    required this.heldIntentions,
  });

  final CampaignBinding binding;
  final CampaignPeriod local;

  /// Contribuciones con una intención aceptada (ACKED) bajo esta referencia.
  final int acceptedContributions;

  /// Intenciones con valor sin asentar (nunca enviadas o con resultado
  /// desconocido) que el worker retiene: no salen por POST; las inciertas se
  /// concilian por consulta.
  final int heldIntentions;
}

/// Estados de la outbox que todavía pueden cambiar el estado central: con
/// alguno de ellos, el vínculo de esa referencia no se corrige ni se quita.
const String unsettledOutboxStatuses =
    "('PENDING','SENDING','OUTCOME_UNKNOWN','CONFLICT','AUTH_PAUSED',"
    "'OWNER_PAUSED','RESTORE_PAUSED','VERSION_MISMATCH')";

/// Vínculos explícitos entre campañas/productos locales y referencias
/// centrales (F05-SYNC-08). Nunca vincula por nombre: cada vínculo nace de
/// una elección confirmada del agricultor. No crea catálogo central ni
/// guarda stock o fichas: sólo la referencia, el nombre, la unidad, el
/// período central y el estado.
///
/// D-F04-C2: un vínculo de campaña sólo está vigente si el período local
/// cabe en el central. Se comprueba al vincular, al refrescar las
/// referencias, al cambiar el calendario local y, por si acaso, cada vez que
/// se lee el vínculo ([campaignBindingOf]): así la vista previa y la
/// confirmación de una publicación nunca usan un estado viejo.
class CentralBindingStore {
  CentralBindingStore(
    this._database, {
    FarmerOperationGate gate = const FarmerOperationGate.unrestricted(),
    DateTime Function()? clock,
  }) : _gate = gate,
       _clock = clock ?? DateTime.now;

  final AppDatabase _database;
  final FarmerOperationGate _gate;
  final DateTime Function() _clock;

  String _now() => _clock().toUtc().toIso8601String();

  Future<T> _write<T>(Future<T> Function(Transaction txn) body) =>
      _database.replacement.write(() async {
        _gate.ensureAllowed();
        return (await _database.database).transaction(body);
      });

  /// Vínculos de campaña con el estado **efectivo**: el guardado, corregido
  /// si el período local ya no cabe en el central guardado.
  Future<List<CampaignBinding>> campaignBindings([
    DatabaseExecutor? executor,
  ]) async {
    final db = executor ?? await _database.database;
    return liveCampaignBindings(db);
  }

  Future<List<ProductBinding>> productBindings([
    DatabaseExecutor? executor,
  ]) async {
    final db = executor ?? await _database.database;
    return (await db.query(
      'product_bindings',
      orderBy: 'product_id',
    )).map(ProductBinding.fromRow).toList();
  }

  /// Período local de la campaña, leído de su fila; null si no existe.
  static Future<CampaignPeriod?> localPeriodOf(
    DatabaseExecutor db,
    int campaignId,
  ) => _localPeriod(db, campaignId);

  static Future<CampaignPeriod?> _localPeriod(
    DatabaseExecutor db,
    int campaignId,
  ) async {
    final rows = await db.query(
      'campaigns',
      columns: ['id', 'name', 'status', 'start_date', 'end_date'],
      where: 'id=?',
      whereArgs: [campaignId],
    );
    return rows.isEmpty ? null : CampaignPeriod.fromRow(rows.single);
  }

  /// Estado efectivo de [stored] frente al período local actual. Un motivo
  /// ajeno al período (referencia desaparecida, campaña que no admite
  /// aportes) prevalece; un período central desconocido no se puede
  /// comprobar; un período local que no cabe invalida.
  static CampaignBinding _withLivePeriodCheck(
    CampaignBinding stored,
    CampaignPeriod? local,
  ) {
    final reason = stored.invalidReason;
    if (reason != null && !reason.holdsQueue) return stored;
    final central = stored.centralPeriod;
    if (central == null) {
      return stored._withStatus(BindingInvalidReason.periodUnverified);
    }
    if (local == null) return stored;
    final mismatch = periodMismatch(local, central);
    final effective = mismatch == null
        ? null
        : BindingInvalidReason.periodIncompatible;
    return effective == reason ? stored : stored._withStatus(effective);
  }

  /// Todos los vínculos de campaña con su estado efectivo (ver clase).
  static Future<List<CampaignBinding>> liveCampaignBindings(
    DatabaseExecutor db,
  ) async {
    final periods = {
      for (final row in await db.query(
        'campaigns',
        columns: ['id', 'name', 'status', 'start_date', 'end_date'],
      ))
        row['id']! as int: CampaignPeriod.fromRow(row),
    };
    return [
      for (final row in await db.query(
        'campaign_bindings',
        orderBy: 'campaign_id',
      ))
        _withLivePeriodCheck(
          CampaignBinding.fromRow(row),
          periods[row['campaign_id']],
        ),
    ];
  }

  /// Vínculo de la campaña con su estado efectivo (ver clase).
  static Future<CampaignBinding?> campaignBindingOf(
    DatabaseExecutor db,
    int campaignId,
  ) async {
    final rows = await db.query(
      'campaign_bindings',
      where: 'campaign_id=?',
      whereArgs: [campaignId],
    );
    if (rows.isEmpty) return null;
    return _withLivePeriodCheck(
      CampaignBinding.fromRow(rows.single),
      await _localPeriod(db, campaignId),
    );
  }

  static Future<ProductBinding?> productBindingOf(
    DatabaseExecutor db,
    int productId,
  ) async {
    final rows = await db.query(
      'product_bindings',
      where: 'product_id=?',
      whereArgs: [productId],
    );
    return rows.isEmpty ? null : ProductBinding.fromRow(rows.single);
  }

  /// Texto del problema de período de [binding] frente a [local], con los dos
  /// períodos; `null` si no hay problema de período.
  static String? periodProblem(CampaignBinding binding, CampaignPeriod local) {
    final central = binding.centralPeriod;
    if (central == null) {
      return '«${local.name}» va ${local.describe}; el período de '
          '«${binding.centralName}» del sindicato no se ha comprobado todavía. '
          'Actualice las referencias del sindicato.';
    }
    final mismatch = periodMismatch(local, central);
    if (mismatch == null) return null;
    return periodMismatchMessage(
      localName: local.name,
      local: local,
      centralName: binding.centralName,
      central: central,
      mismatch: mismatch,
    );
  }

  /// Referencias de campaña cuyas intenciones con valor el worker debe
  /// retener (D-F04-C2): la compatibilidad temporal del vínculo no está
  /// demostrada ([CampaignBinding.periodHold]), **aunque el motivo de
  /// invalidez guardado sea otro** (C2-R1: un vínculo migrado con
  /// NOT_ACCEPTING y sin fechas centrales tampoco demuestra contención).
  /// Central aceptaría esos totales sin notarlo. Una sola consulta: el worker
  /// y el resumen la llaman a menudo.
  static Future<Set<String>> periodHeldCampaignRefs(DatabaseExecutor db) async {
    final rows = await db.rawQuery(
      'SELECT b.*, c.name AS c_name, c.status AS c_status, '
      'c.start_date AS c_start, c.end_date AS c_end '
      'FROM campaign_bindings b JOIN campaigns c ON c.id = b.campaign_id',
    );
    final held = <String>{};
    for (final row in rows) {
      final binding = CampaignBinding.fromRow(row);
      final local = CampaignPeriod.fromRow({
        'id': row['campaign_id'],
        'name': row['c_name'],
        'status': row['c_status'],
        'start_date': row['c_start'],
        'end_date': row['c_end'],
      });
      if (binding.periodHold(local)) held.add(binding.campaignRef);
    }
    return held;
  }

  /// Vuelve a comprobar el período de la campaña [campaignId] contra el
  /// período central guardado y asienta el resultado en la fila. Se llama
  /// desde la transacción que cambia el calendario local (alta que fija el
  /// fin de la anterior, cierre, fin previsto). Sin vínculo, o con un motivo
  /// ajeno al período, no toca nada. Devuelve el estado efectivo.
  static Future<CampaignBinding?> revalidateCampaignPeriod(
    DatabaseExecutor db,
    int campaignId, {
    required String now,
  }) async {
    final rows = await db.query(
      'campaign_bindings',
      where: 'campaign_id=?',
      whereArgs: [campaignId],
    );
    if (rows.isEmpty) return null;
    final stored = CampaignBinding.fromRow(rows.single);
    final effective = _withLivePeriodCheck(
      stored,
      await _localPeriod(db, campaignId),
    );
    if (effective.invalidReason != stored.invalidReason) {
      await db.update(
        'campaign_bindings',
        {
          'status': effective.status.code,
          'invalid_reason': effective.invalidReason?.code,
          'checked_at': now,
        },
        where: 'campaign_id=?',
        whereArgs: [campaignId],
      );
    }
    return effective;
  }

  /// Vínculos de campaña que requieren revisión del titular por su período,
  /// con cuántos aportes aceptados y cuántas intenciones retenidas tienen.
  Future<List<CampaignBindingReview>> campaignReviews() async {
    final db = await _database.database;
    return reviewsFor(
      db,
      bindings: await liveCampaignBindings(db),
      periods: {
        for (final row in await db.query(
          'campaigns',
          columns: ['id', 'name', 'status', 'start_date', 'end_date'],
        ))
          row['id']! as int: CampaignPeriod.fromRow(row),
      },
    );
  }

  /// Como [campaignReviews], sobre vínculos y períodos ya leídos: una sola
  /// consulta agregada a la outbox, y ninguna si nada requiere revisión.
  static Future<List<CampaignBindingReview>> reviewsFor(
    DatabaseExecutor db, {
    required List<CampaignBinding> bindings,
    required Map<int, CampaignPeriod> periods,
  }) async {
    final affected = [
      for (final binding in bindings)
        if (periods.containsKey(binding.campaignId) &&
            binding.periodHold(periods[binding.campaignId]))
          binding,
    ];
    if (affected.isEmpty) return const [];
    final counts = <String, (int, int)>{
      for (final row in await db.rawQuery(
        'SELECT o.campaign_ref, '
        "COUNT(DISTINCT CASE WHEN o.status='ACKED' THEN o.projection_type || o.product_ref || o.base_unit END) AS accepted, "
        "SUM(CASE WHEN o.action<>'CANCEL' AND o.status IN ('PENDING','SENDING','OUTCOME_UNKNOWN') THEN 1 ELSE 0 END) AS held "
        'FROM sync_outbox o JOIN owner_bindings w ON w.id = o.owner_binding_id '
        'WHERE w.ended_at IS NULL GROUP BY o.campaign_ref',
      ))
        row['campaign_ref']! as String: (
          row['accepted']! as int,
          (row['held'] as int?) ?? 0,
        ),
    };
    return [
      for (final binding in affected)
        CampaignBindingReview(
          binding: binding,
          local: periods[binding.campaignId]!,
          acceptedContributions: counts[binding.campaignRef]?.$1 ?? 0,
          heldIntentions: counts[binding.campaignRef]?.$2 ?? 0,
        ),
    ];
  }

  /// El tenant del titular vinculado: las referencias son de ese tenant y de
  /// ningún otro.
  Future<void> _requireOwnerTenant(Transaction txn, String tenantId) async {
    final owner = await txn.query(
      'owner_bindings',
      columns: ['tenant_id'],
      where: 'ended_at IS NULL',
    );
    if (owner.isEmpty) {
      throw CentralBindingException(
        'Elija primero el titular de estos datos para vincular con el sindicato.',
      );
    }
    if (owner.single['tenant_id'] != tenantId) {
      throw CentralBindingException(
        'La cuenta activa no corresponde al titular de estos datos.',
      );
    }
  }

  /// Una referencia que ya sostiene una necesidad vigente o envíos sin asentar
  /// no se corrige ni se quita: cambiar campaña o producto exige anular el
  /// aporte y declarar otro (F06 §6).
  Future<void> _requireNoLiveContribution(
    Transaction txn, {
    required String column,
    required String ref,
    required String needColumn,
    required int localId,
  }) async {
    final liveNeeds = await txn.rawQuery(
      "SELECT 1 FROM declared_needs WHERE $needColumn=? AND status='ACTIVE' LIMIT 1",
      [localId],
    );
    final unsettled = await txn.rawQuery(
      'SELECT 1 FROM sync_outbox WHERE $column=? '
      'AND status IN $unsettledOutboxStatuses LIMIT 1',
      [ref],
    );
    if (liveNeeds.isNotEmpty || unsettled.isNotEmpty) {
      throw CentralBindingException(
        'Hay una necesidad vigente o envíos sin asentar con este vínculo. '
        'Anule primero la necesidad para cambiarlo.',
      );
    }
  }

  /// Vincula la campaña local [campaignId] con [central], tras la
  /// confirmación explícita del agricultor. Sólo campañas que admiten aportes
  /// y sólo si el período local cabe en el central (D-F04-C2): si no, se
  /// rechaza con los dos períodos y sin escribir nada.
  Future<CampaignBinding> bindCampaign({
    required int campaignId,
    required CentralCampaign central,
    required String tenantId,
  }) async {
    if (!central.acceptsContributions) {
      throw CentralBindingException(
        'Esa campaña del sindicato no admite nuevos aportes.',
      );
    }
    final CentralPeriod centralPeriod;
    try {
      centralPeriod = CentralPeriod.of(central);
    } on FormatException {
      throw CentralBindingException(
        'Las fechas de «${central.name}» del sindicato no se pudieron leer. '
        'Actualice las referencias.',
      );
    }
    await _write((txn) async {
      await _requireOwnerTenant(txn, tenantId);
      final local = await _localPeriod(txn, campaignId);
      if (local == null) {
        throw CentralBindingException('La campaña local no existe.');
      }
      final mismatch = periodMismatch(local, centralPeriod);
      if (mismatch != null) {
        throw CentralBindingException(
          '${periodMismatchMessage(localName: local.name, local: local, centralName: central.name, central: centralPeriod, mismatch: mismatch)} '
          'No se vinculó.',
        );
      }
      final taken = await txn.query(
        'campaign_bindings',
        columns: ['campaign_id'],
        where: 'tenant_id=? AND campaign_ref=? AND campaign_id<>?',
        whereArgs: [tenantId, central.ref, campaignId],
      );
      if (taken.isNotEmpty) {
        throw CentralBindingException(
          'Esa campaña del sindicato ya está vinculada con otra campaña local.',
        );
      }
      final current = await campaignBindingOf(txn, campaignId);
      if (current != null && current.campaignRef != central.ref) {
        await _requireNoLiveContribution(
          txn,
          column: 'campaign_ref',
          ref: current.campaignRef,
          needColumn: 'campaign_id',
          localId: campaignId,
        );
      }
      final now = _now();
      await txn.rawInsert(
        'INSERT OR REPLACE INTO campaign_bindings (campaign_id, tenant_id, '
        'campaign_ref, central_name, central_start_day, central_end_day, '
        'status, invalid_reason, bound_at, checked_at) '
        'VALUES (?,?,?,?,?,?,?,NULL,?,?)',
        [
          campaignId,
          tenantId,
          central.ref,
          central.name,
          centralPeriod.startDay,
          centralPeriod.endDay,
          'VALID',
          now,
          now,
        ],
      );
    });
    return (await campaignBindingOf(await _database.database, campaignId))!;
  }

  /// Vincula el producto local [productId] con [central]. La dimensión debe
  /// coincidir (L con L, KG con KG): no hay conversión ni densidad.
  Future<ProductBinding> bindProduct({
    required int productId,
    required CentralProduct central,
    required String tenantId,
  }) async {
    final centralBase = central.baseUnit;
    if (!central.linkable || centralBase == null) {
      throw CentralBindingException(
        'Ese producto del sindicato no usa L ni KG: no se puede vincular.',
      );
    }
    if (!central.isActive) {
      throw CentralBindingException(
        'Ese producto del sindicato está inactivo.',
      );
    }
    await _write((txn) async {
      await _requireOwnerTenant(txn, tenantId);
      final local = await txn.query(
        'products',
        columns: ['base_unit'],
        where: 'id=?',
        whereArgs: [productId],
      );
      if (local.isEmpty) {
        throw CentralBindingException('El producto local no existe.');
      }
      if (local.single['base_unit'] != centralBase.code) {
        throw CentralBindingException(
          'Las unidades no coinciden (${BaseUnit.fromCode(local.single['base_unit'])?.majorUnit} '
          'local, ${centralBase.majorUnit} en el sindicato). No se convierte '
          'entre volumen y masa.',
        );
      }
      final taken = await txn.query(
        'product_bindings',
        columns: ['product_id'],
        where: 'tenant_id=? AND product_ref=? AND product_id<>?',
        whereArgs: [tenantId, central.ref, productId],
      );
      if (taken.isNotEmpty) {
        throw CentralBindingException(
          'Ese producto del sindicato ya está vinculado con otro producto local.',
        );
      }
      final current = await productBindingOf(txn, productId);
      if (current != null && current.productRef != central.ref) {
        await _requireNoLiveContribution(
          txn,
          column: 'product_ref',
          ref: current.productRef,
          needColumn: 'product_id',
          localId: productId,
        );
      }
      final now = _now();
      await txn.rawInsert(
        'INSERT OR REPLACE INTO product_bindings (product_id, tenant_id, '
        'product_ref, central_name, central_unit, base_unit, status, '
        'invalid_reason, bound_at, checked_at) VALUES (?,?,?,?,?,?,?,NULL,?,?)',
        [
          productId,
          tenantId,
          central.ref,
          central.name,
          central.unit,
          centralBase.code,
          'VALID',
          now,
          now,
        ],
      );
    });
    return (await productBindingOf(await _database.database, productId))!;
  }

  Future<void> unbindCampaign(int campaignId) => _write((txn) async {
    final current = await campaignBindingOf(txn, campaignId);
    if (current == null) return;
    await _requireNoLiveContribution(
      txn,
      column: 'campaign_ref',
      ref: current.campaignRef,
      needColumn: 'campaign_id',
      localId: campaignId,
    );
    await txn.delete(
      'campaign_bindings',
      where: 'campaign_id=?',
      whereArgs: [campaignId],
    );
  });

  Future<void> unbindProduct(int productId) => _write((txn) async {
    final current = await productBindingOf(txn, productId);
    if (current == null) return;
    await _requireNoLiveContribution(
      txn,
      column: 'product_ref',
      ref: current.productRef,
      needColumn: 'product_id',
      localId: productId,
    );
    await txn.delete(
      'product_bindings',
      where: 'product_id=?',
      whereArgs: [productId],
    );
  });

  /// Revisa los vínculos del tenant contra las referencias recién leídas. Un
  /// vínculo cuya referencia desaparece, cuya campaña ya no admite aportes o
  /// cuyo período central ya no contiene al local queda inválido: bloquea
  /// publicaciones nuevas sin borrar nada. Si vuelve a cumplir, queda vigente
  /// otra vez. El período central se guarda para comprobarlo sin red. Devuelve
  /// cuántos vínculos cambiaron.
  Future<int> refreshFrom(CentralReferences references, String tenantId) =>
      _write((txn) async {
        final now = _now();
        var changed = 0;
        final rows = await txn.query(
          'campaign_bindings',
          orderBy: 'campaign_id',
        );
        for (final row in rows) {
          final binding = CampaignBinding.fromRow(row);
          if (binding.tenantId != tenantId) continue;
          final central = references.campaign(binding.campaignRef);
          CentralPeriod? centralPeriod;
          if (central != null) {
            try {
              centralPeriod = CentralPeriod.of(central);
            } on FormatException {
              centralPeriod = null;
            }
          }
          final local = await _localPeriod(txn, binding.campaignId);
          final BindingInvalidReason? reason;
          if (central == null) {
            reason = BindingInvalidReason.referenceMissing;
          } else if (!central.acceptsContributions) {
            reason = BindingInvalidReason.notAccepting;
          } else if (centralPeriod == null) {
            reason = BindingInvalidReason.periodUnverified;
          } else if (local != null &&
              periodMismatch(local, centralPeriod) != null) {
            reason = BindingInvalidReason.periodIncompatible;
          } else {
            reason = null;
          }
          if (reason != binding.invalidReason) changed++;
          await txn.update(
            'campaign_bindings',
            {
              'status': reason == null ? 'VALID' : 'INVALID',
              'invalid_reason': reason?.code,
              'central_name': central?.name ?? binding.centralName,
              'central_start_day':
                  centralPeriod?.startDay ?? binding.centralStartDay,
              'central_end_day': centralPeriod == null
                  ? binding.centralEndDay
                  : centralPeriod.endDay,
              'checked_at': now,
            },
            where: 'campaign_id=?',
            whereArgs: [binding.campaignId],
          );
        }
        for (final binding in await productBindings(txn)) {
          if (binding.tenantId != tenantId) continue;
          final central = references.product(binding.productRef);
          final reason = central == null
              ? BindingInvalidReason.referenceMissing
              : central.baseUnit != binding.baseUnit
              ? BindingInvalidReason.notLinkable
              : !central.isActive
              ? BindingInvalidReason.inactive
              : null;
          if (reason != binding.invalidReason) changed++;
          await txn.update(
            'product_bindings',
            {
              'status': reason == null ? 'VALID' : 'INVALID',
              'invalid_reason': reason?.code,
              'central_name': central?.name ?? binding.centralName,
              'central_unit': central?.unit ?? binding.centralUnit,
              'checked_at': now,
            },
            where: 'product_id=?',
            whereArgs: [binding.productId],
          );
        }
        return changed;
      });
}
