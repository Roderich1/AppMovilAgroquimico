import 'package:sqflite/sqflite.dart' show DatabaseExecutor, Transaction;

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
  notLinkable('NOT_LINKABLE', 'La unidad central ya no es L ni KG.');

  const BindingInvalidReason(this.code, this.message);
  final String code;
  final String message;

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
    required this.status,
    required this.invalidReason,
    required this.boundAt,
    required this.checkedAt,
  });

  final int campaignId;
  final String tenantId;
  final String campaignRef;
  final String centralName;
  final BindingStatus status;
  final BindingInvalidReason? invalidReason;
  final String boundAt;
  final String checkedAt;

  bool get isValid => status == BindingStatus.valid;

  static CampaignBinding fromRow(Map<String, Object?> row) => CampaignBinding(
    campaignId: row['campaign_id']! as int,
    tenantId: row['tenant_id']! as String,
    campaignRef: row['campaign_ref']! as String,
    centralName: row['central_name']! as String,
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

/// Estados de la outbox que todavía pueden cambiar el estado central: con
/// alguno de ellos, el vínculo de esa referencia no se corrige ni se quita.
const String unsettledOutboxStatuses =
    "('PENDING','SENDING','OUTCOME_UNKNOWN','CONFLICT','AUTH_PAUSED',"
    "'OWNER_PAUSED','RESTORE_PAUSED','VERSION_MISMATCH')";

/// Vínculos explícitos entre campañas/productos locales y referencias
/// centrales (F05-SYNC-08). Nunca vincula por nombre: cada vínculo nace de
/// una elección confirmada del agricultor. No crea catálogo central ni
/// guarda stock o fichas: sólo la referencia, el nombre, la unidad y el
/// estado.
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

  Future<List<CampaignBinding>> campaignBindings([
    DatabaseExecutor? executor,
  ]) async {
    final db = executor ?? await _database.database;
    return (await db.query(
      'campaign_bindings',
      orderBy: 'campaign_id',
    )).map(CampaignBinding.fromRow).toList();
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

  static Future<CampaignBinding?> campaignBindingOf(
    DatabaseExecutor db,
    int campaignId,
  ) async {
    final rows = await db.query(
      'campaign_bindings',
      where: 'campaign_id=?',
      whereArgs: [campaignId],
    );
    return rows.isEmpty ? null : CampaignBinding.fromRow(rows.single);
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
  /// confirmación explícita del agricultor. Sólo campañas que admiten aportes.
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
    await _write((txn) async {
      await _requireOwnerTenant(txn, tenantId);
      final local = await txn.query(
        'campaigns',
        columns: ['id'],
        where: 'id=?',
        whereArgs: [campaignId],
      );
      if (local.isEmpty) {
        throw CentralBindingException('La campaña local no existe.');
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
        'campaign_ref, central_name, status, invalid_reason, bound_at, '
        'checked_at) VALUES (?,?,?,?,?,NULL,?,?)',
        [campaignId, tenantId, central.ref, central.name, 'VALID', now, now],
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
  /// vínculo cuya referencia desaparece, o cuya campaña ya no admite aportes,
  /// queda inválido: bloquea publicaciones nuevas sin borrar nada. Si vuelve a
  /// cumplir, queda vigente otra vez. Devuelve cuántos vínculos cambiaron.
  Future<int> refreshFrom(CentralReferences references, String tenantId) =>
      _write((txn) async {
        final now = _now();
        var changed = 0;
        for (final binding in await campaignBindings(txn)) {
          if (binding.tenantId != tenantId) continue;
          final central = references.campaign(binding.campaignRef);
          final reason = central == null
              ? BindingInvalidReason.referenceMissing
              : central.acceptsContributions
              ? null
              : BindingInvalidReason.notAccepting;
          if (reason != binding.invalidReason) changed++;
          await txn.update(
            'campaign_bindings',
            {
              'status': reason == null ? 'VALID' : 'INVALID',
              'invalid_reason': reason?.code,
              'central_name': central?.name ?? binding.centralName,
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
