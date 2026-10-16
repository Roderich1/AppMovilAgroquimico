// F06 (D4, BE #21 / GATE-F06): niveles SQLite y outbox del dataset controlado
// contra el oráculo escrito a mano, sin Backend. El E2E contra Central real es
// test/f06_reconciliation_integration_test.dart.
import 'package:agroquimicos/data/sync/declared_need_store.dart';
import 'package:agroquimicos/domain/installation_access.dart';
import 'package:agroquimicos/domain/sync/consumption_projection.dart';
import 'package:agroquimicos/domain/sync/sync_types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';
import 'support/f06_dataset.dart';

void main() {
  sqfliteFfiInit();
  final references = f06SyntheticReferences();
  final campaignCode = {
    for (final c in references.campaigns)
      c.ref: f06CentralCampaigns.entries
          .singleWhere((e) => e.value == c.name)
          .key,
  };
  final productName = {for (final p in references.products) p.ref: p.name};

  Future<F06Farm> seed(String farmer) async => seedF06Farm(
    database: openDb(await tempDbPath('f06_$farmer')),
    farmer: farmer,
    scope: OwnerScope(
      memberId: switch (farmer) {
        'F1' => 'e6000000-0000-4000-8000-000000000001',
        'F2' => 'e6000000-0000-4000-8000-000000000002',
        _ => 'e6000000-0000-4000-8000-000000000003',
      },
      tenantId: 'd6000000-0000-4000-8000-000000000001',
    ),
    installationRef: f06InstallationRef(farmer),
    references: references,
  );

  /// SQLite: lo que el titular publicaría (consumo) y lo que declaró (necesidad).
  Future<Map<F06Key, F06Expected>> local(F06Farm farm) async {
    final preview = await farm.publisher.preview();
    final campaignOf = {
      for (final e in farm.campaignOf.entries) e.value: e.key,
    };
    return {
      for (final row in preview.rows)
        (
          campaign: campaignCode[row.target.campaignRef]!,
          projection: ProjectionType.consumptionTotal.code,
          product: productName[row.target.productRef]!,
          baseUnit: row.baseUnit.code,
        ): (
          status: 'ACTIVE',
          quantity: row.quantityBase,
        ),
      for (final need in await farm.needs.needs())
        (
          campaign: campaignOf[need.campaignId]!,
          projection: ProjectionType.declaredNeed.code,
          product: need.productName,
          baseUnit: need.baseUnit.code,
        ): (
          status: need.status.code,
          quantity: need.status == DeclaredNeedStatus.active
              ? need.quantityBase
              : null,
        ),
    };
  }

  /// Outbox: la última intención de cada clave tras publicar el consumo.
  Future<Map<F06Key, F06Expected>> outbox(F06Farm farm) async {
    final rows = await (await farm.database.database).query(
      'sync_outbox',
      orderBy: 'id',
    );
    final last = <F06Key, OutboxEntry>{};
    for (final entry
        in rows
            .map(OutboxEntry.fromRow)
            .where((e) => e.status != OutboxStatus.discarded)) {
      last[(
            campaign: campaignCode[entry.campaignRef]!,
            projection: entry.projectionType.code,
            product: productName[entry.productRef]!,
            baseUnit: entry.baseUnit.code,
          )] =
          entry;
    }
    return {
      for (final MapEntry(:key, :value) in last.entries)
        key: (
          status: value.action == SyncAction.cancel ? 'CANCELLED' : 'ACTIVE',
          quantity: value.quantityBase == null
              ? null
              : int.parse(value.quantityBase!),
        ),
    };
  }

  for (final farmer in ['F1', 'F2', 'F3']) {
    test('$farmer: SQLite y outbox coinciden con el oráculo a mano', () async {
      final farm = await seed(farmer);
      final expected = f06ExpectedContributions(farmer);
      final consumption = expected.keys.where(
        (k) => k.projection == ProjectionType.consumptionTotal.code,
      );
      expect(
        await farm.publisher.publish(await farm.publisher.preview()),
        consumption.length,
      );
      // Primer envío simulado (ACK de todo lo pendiente) y, después, las
      // retiradas de necesidades ya sincronizadas.
      for (final entry in await farm.outbox.readyToSend(
        activeBindingId: (await farm.owners.activeBinding())!.id,
        now: DateTime.now(),
      )) {
        await farm.outbox.recordAccepted(
          await farm.outbox.markSending(entry),
          '2026-10-16T12:00:00.000Z',
        );
      }
      final cancels = expected.values.where((v) => v.status == 'CANCELLED');
      expect(await applyF06Cancellations(farm), cancels.length);
      expect(await local(farm), expected);
      expect(await outbox(farm), expected);
      // Volver a publicar sin cambios no encola nada.
      expect(await farm.publisher.publish(await farm.publisher.preview()), 0);
    });
  }

  test(
    'exclusiones del dataset: familiar, reversiones y producto sin vincular',
    () async {
      final f1 = await (await seed('F1')).publisher.preview();
      expect(f1.excludedLines, {ConsumptionExclusion.notOwner: 1});
      final f2 = await (await seed('F2')).publisher.preview();
      expect(f2.excludedLines, {ConsumptionExclusion.reversed: 1});
      final f3 = await (await seed('F3')).publisher.preview();
      expect(f3.excludedLines, {ConsumptionExclusion.reversed: 2});
      expect(
        [for (final pair in f3.excludedPairs) (pair.product, pair.reason)],
        [('Adherente casero', ConsumptionExclusion.productNotBound)],
      );
    },
  );
}
