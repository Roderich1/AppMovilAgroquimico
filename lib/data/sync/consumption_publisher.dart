import 'dart:math';

import 'package:sqflite/sqflite.dart' show DatabaseExecutor;

import '../../domain/sync/consumption_projection.dart';
import '../../domain/sync/intention_planner.dart';
import '../../domain/sync/sync_types.dart';
import '../../domain/sync/sync_wire.dart';
import '../agro_repository.dart' show BusinessRuleException;
import '../app_database.dart';
import '../farmer_operation_gate.dart';
import 'sync_outbox_store.dart';

class ConsumptionPublishException extends BusinessRuleException {
  ConsumptionPublishException(super.message);
}

/// Qué pasaría con un total si se publica ahora.
enum ConsumptionChange {
  /// Nunca se publicó (o se retiró): PUBLISH.
  publish,

  /// Cambió respecto del último total enviado: SUPERSEDE.
  supersede,

  /// Ya se publicó (o está en camino) ese mismo total: nada que enviar.
  unchanged,

  /// Central registró un conflicto: decide el titular.
  conflict,

  /// El vínculo dejó de ser válido: no se publica hasta corregirlo.
  blocked,
}

class ConsumptionPreviewRow {
  const ConsumptionPreviewRow({
    required this.campaignName,
    required this.productName,
    required this.baseUnit,
    required this.quantityBase,
    required this.change,
    required this.target,
    required this.prior,
  });

  final String campaignName;
  final String productName;
  final BaseUnit baseUnit;

  /// Total local vigente. Cero si todas sus aplicaciones se revirtieron.
  final int quantityBase;
  final ConsumptionChange change;
  final ContributionTarget target;

  /// Última intención vigente de ese total (null si nunca se publicó).
  final OutboxEntry? prior;

  bool get sends =>
      change == ConsumptionChange.publish ||
      change == ConsumptionChange.supersede;
}

class ConsumptionPreview {
  const ConsumptionPreview({
    required this.ownerBindingId,
    required this.rows,
    required this.excludedLines,
    required this.excludedPairs,
  });

  /// Vínculo de titular para el que se calculó: confirmar esta vista previa
  /// no publica el consumo de otro titular.
  final int ownerBindingId;
  final List<ConsumptionPreviewRow> rows;
  final Map<ConsumptionExclusion, int> excludedLines;

  /// Campaña × producto con consumo propio que no se publica, con nombres.
  final List<({String campaign, String product, ConsumptionExclusion reason})>
  excludedPairs;

  bool get hasChanges => rows.any((row) => row.sends);
}

/// Publicación explícita de `CONSUMPTION_TOTAL` (MOB #33). Calcula los
/// totales con [buildConsumptionProjection], los compara con la última
/// intención vigente de cada total y, sólo con confirmación, encola PUBLISH o
/// SUPERSEDE donde cambió: en una transacción, con la misma outbox, el mismo
/// planner y el mismo worker que la necesidad declarada (D3). No toca
/// inventario ni aplicaciones.
class ConsumptionPublisher {
  ConsumptionPublisher(
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

  /// Vista previa de sólo lectura: no escribe nada.
  Future<ConsumptionPreview> preview() async =>
      _compute(await _database.database);

  /// Encola lo que [confirmed] mostró. Si cambió cualquier cosa desde la
  /// vista previa (titular, destino, cantidad, unidad, cambio o intención
  /// previa), no escribe nada y pide revisarla otra vez. La comparación y la
  /// escritura ocurren en la misma transacción.
  Future<int> publish(
    ConsumptionPreview confirmed,
  ) => _database.replacement.write(() async {
    _gate.ensureAllowed();
    return (await _database.database).transaction((txn) async {
      final current = await _compute(txn);
      if (!_sameProposal(current, confirmed)) {
        throw ConsumptionPublishException(
          'Los consumos cambiaron desde la vista previa. Revísela de nuevo.',
        );
      }
      final now = _now();
      var enqueued = 0;
      for (final row in current.rows.where((row) => row.sends)) {
        final prior = await SyncOutboxStore.latestEffective(txn, row.target);
        final operationId = await SyncOutboxStore.applyPlan(
          txn,
          planIntention(prior, ValueIntent(row.quantityBase)),
          row.target,
          now: now,
          random: _random,
        );
        if (operationId != null) enqueued++;
      }
      return enqueued;
    });
  });

  /// El titular decide un conflicto enviando el total que vio en [row] sobre
  /// el head que Central mostró (F06 §6: el consumo lo recalcula Mobile). Si
  /// el total, su destino o la intención en conflicto cambiaron desde que se
  /// mostró, no escribe nada.
  Future<void> resolveConflict({
    required ConsumptionPreviewRow row,
    required OperationView view,
  }) => _database.replacement.write(() async {
    _gate.ensureAllowed();
    await (await _database.database).transaction((txn) async {
      final current = (await _compute(txn)).rows
          .where(
            (candidate) =>
                _targetKey(candidate.target) == _targetKey(row.target),
          )
          .toList();
      final conflict = await SyncOutboxStore.latestEffective(txn, row.target);
      final contribution = view.contribution;
      final head = contribution?.headOperationId;
      if (current.length != 1 ||
          _rowKey(current.single) != _rowKey(row) ||
          current.single.change != ConsumptionChange.conflict ||
          conflict == null ||
          conflict.operationId != view.ack.operationId ||
          contribution == null ||
          head == null) {
        throw ConsumptionPublishException(
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
        ValueIntent(current.single.quantityBase),
        CausalContext(
          predecessorOperationId: head,
          predecessorKind: contribution.headKind,
          reconciliationReference: contribution.reconciliationReference,
        ),
      );
      await SyncOutboxStore.applyPlan(
        txn,
        planned == null ? const NothingToSendPlan() : EnqueuePlan(planned),
        row.target,
        now: now,
        random: _random,
      );
    });
  });

  /// Identidad completa de un destino de la outbox.
  static String _targetKey(ContributionTarget target) =>
      '${target.ownerBindingId}|${target.projectionType.code}|'
      '${target.campaignRef}|${target.productRef}|${target.baseUnit.code}';

  /// Lo que una fila propone: destino, cantidad en su unidad base, cambio e
  /// intención previa sobre la que se planifica.
  static String _rowKey(ConsumptionPreviewRow row) =>
      '${_targetKey(row.target)}|${row.quantityBase}|${row.baseUnit.code}|'
      '${row.change.name}|${row.prior?.operationId ?? '-'}';

  /// Misma propuesta: mismo titular y las mismas filas, todas, no sólo las
  /// que se envían (una fila que cambia de estado cambia lo que se confirmó).
  static bool _sameProposal(ConsumptionPreview a, ConsumptionPreview b) {
    if (a.ownerBindingId != b.ownerBindingId) return false;
    final left = a.rows.map(_rowKey).toList()..sort();
    final right = b.rows.map(_rowKey).toList()..sort();
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  Future<ConsumptionPreview> _compute(DatabaseExecutor db) async {
    final owners = await db.query(
      'owner_bindings',
      columns: ['id', 'person_id'],
      where: 'ended_at IS NULL',
    );
    if (owners.isEmpty) {
      throw ConsumptionPublishException(
        'Elija primero el titular de estos datos para publicar su consumo.',
      );
    }
    final ownerBindingId = owners.single['id']! as int;
    final ownerPersonId = owners.single['person_id']! as int;

    final lines =
        (await db.rawQuery(
          'SELECT a.id, a.person_id, a.campaign_id, a.status, a.reversed_at, '
          'i.product_id, i.quantity_base FROM applications a '
          'JOIN application_items i ON i.application_id = a.id',
        )).map(
          (row) => AppliedLine(
            applicationId: row['id']! as int,
            personId: row['person_id']! as int,
            campaignId: row['campaign_id']! as int,
            productId: row['product_id']! as int,
            status: row['status']! as String,
            reversed: row['reversed_at'] != null,
            quantityBase: row['quantity_base']! as int,
          ),
        );
    final campaigns = {
      for (final row in await db.rawQuery(
        'SELECT b.campaign_id, b.campaign_ref, b.central_name, b.status, '
        'c.name FROM campaign_bindings b JOIN campaigns c ON c.id = b.campaign_id',
      ))
        row['campaign_id']! as int: BoundRef(
          ref: row['campaign_ref']! as String,
          localName: row['name']! as String,
          centralName: row['central_name']! as String,
          valid: row['status'] == 'VALID',
        ),
    };
    final products = {
      for (final row in await db.rawQuery(
        'SELECT b.product_id, b.product_ref, b.central_name, b.status, '
        'b.base_unit, p.name FROM product_bindings b '
        'JOIN products p ON p.id = b.product_id',
      ))
        row['product_id']! as int: BoundRef(
          ref: row['product_ref']! as String,
          localName: row['name']! as String,
          centralName: row['central_name']! as String,
          valid: row['status'] == 'VALID',
          baseUnit: BaseUnit.fromCode(row['base_unit']),
        ),
    };
    final projection = buildConsumptionProjection(
      ownerPersonId: ownerPersonId,
      lines: lines,
      campaigns: campaigns,
      products: products,
    );

    final rows = <ConsumptionPreviewRow>[];
    final seen = <String>{};
    for (final cell in projection.cells) {
      final target = ContributionTarget(
        ownerBindingId: ownerBindingId,
        projectionType: ProjectionType.consumptionTotal,
        campaignRef: cell.campaign.ref,
        productRef: cell.product.ref,
        baseUnit: cell.baseUnit,
      );
      seen.add(
        '${target.campaignRef}|${target.productRef}|${target.baseUnit.code}',
      );
      final prior = await SyncOutboxStore.latestEffective(db, target);
      rows.add(
        ConsumptionPreviewRow(
          campaignName: cell.campaign.localName,
          productName: cell.product.localName,
          baseUnit: cell.baseUnit,
          quantityBase: cell.quantityBase,
          change: _changeFor(prior, cell.quantityBase),
          target: target,
          prior: prior,
        ),
      );
    }

    // Un total ya publicado cuyas aplicaciones se revirtieron todas pasa a
    // cero: no se deja en Central un valor que ya no es cierto. Si su vínculo
    // dejó de valer, se bloquea en lugar de publicarse.
    final campaignByRef = {
      for (final entry in campaigns.entries) entry.value.ref: entry,
    };
    final productByRef = {
      for (final entry in products.entries) entry.value.ref: entry,
    };
    final published = await db.rawQuery(
      "SELECT DISTINCT campaign_ref, product_ref, base_unit FROM sync_outbox "
      "WHERE owner_binding_id=? AND projection_type='CONSUMPTION_TOTAL'",
      [ownerBindingId],
    );
    for (final row in published) {
      final key =
          '${row['campaign_ref']}|${row['product_ref']}|${row['base_unit']}';
      if (seen.contains(key)) continue;
      final target = ContributionTarget(
        ownerBindingId: ownerBindingId,
        projectionType: ProjectionType.consumptionTotal,
        campaignRef: row['campaign_ref']! as String,
        productRef: row['product_ref']! as String,
        baseUnit: BaseUnit.fromCode(row['base_unit'])!,
      );
      final prior = await SyncOutboxStore.latestEffective(db, target);
      if (prior == null || prior.action == SyncAction.cancel) continue;
      final campaign = campaignByRef[target.campaignRef];
      final product = productByRef[target.productRef];
      final excluded = projection.excludedPairs.any(
        (pair) =>
            pair.campaignId == campaign?.key && pair.productId == product?.key,
      );
      final usable =
          campaign != null &&
          product != null &&
          campaign.value.valid &&
          product.value.valid &&
          !excluded;
      rows.add(
        ConsumptionPreviewRow(
          campaignName:
              campaign?.value.localName ?? campaign?.value.centralName ?? '—',
          productName:
              product?.value.localName ?? product?.value.centralName ?? '—',
          baseUnit: target.baseUnit,
          quantityBase: 0,
          change: usable ? _changeFor(prior, 0) : ConsumptionChange.blocked,
          target: target,
          prior: prior,
        ),
      );
    }

    final campaignNames = {
      for (final row in await db.query('campaigns', columns: ['id', 'name']))
        row['id']! as int: row['name']! as String,
    };
    final productNames = {
      for (final row in await db.query('products', columns: ['id', 'name']))
        row['id']! as int: row['name']! as String,
    };
    return ConsumptionPreview(
      ownerBindingId: ownerBindingId,
      rows: rows,
      excludedLines: projection.excludedLines,
      excludedPairs: [
        for (final pair in projection.excludedPairs)
          (
            campaign: campaignNames[pair.campaignId] ?? '—',
            product: productNames[pair.productId] ?? '—',
            reason: pair.reason,
          ),
      ],
    );
  }

  static ConsumptionChange _changeFor(OutboxEntry? prior, int quantityBase) {
    if (prior == null || prior.action == SyncAction.cancel) {
      return ConsumptionChange.publish;
    }
    if (prior.status == OutboxStatus.conflict && prior.resolvedAt == null) {
      return ConsumptionChange.conflict;
    }
    return prior.quantityBase == '$quantityBase'
        ? ConsumptionChange.unchanged
        : ConsumptionChange.supersede;
  }
}
