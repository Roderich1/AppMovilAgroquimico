// F06-COLL-03 (MOB #33) y F06-COLL-02 (MOB #32): consumo total del titular
// publicado con la misma outbox, planner y worker de D3, sobre SQLite real.
import 'dart:convert';

import 'package:agroquimicos/data/sync/consumption_publisher.dart';
import 'package:agroquimicos/domain/sync/consumption_projection.dart';
import 'package:agroquimicos/domain/sync/sync_types.dart';
import 'package:agroquimicos/domain/sync/sync_wire.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/services/auth/api_endpoint_config.dart';
import 'package:agroquimicos/services/auth/auth_http_client.dart';
import 'package:agroquimicos/services/sync/sync_access.dart';
import 'package:agroquimicos/services/sync/sync_api.dart';
import 'package:agroquimicos/services/sync/sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';
import 'support/f05_sync_fixtures.dart';
import 'support/f06_consumption_fixtures.dart';

void main() {
  sqfliteFfiInit();

  Map<String, int> totals(ConsumptionPreview preview) => {
    for (final row in preview.rows) row.target.productRef: row.quantityBase,
  };

  Map<String, ConsumptionChange> changes(ConsumptionPreview preview) => {
    for (final row in preview.rows) row.target.productRef: row.change,
  };

  Future<List<OutboxEntry>> consumption(ConsumptionFixture f) async =>
      (await f.sync.outboxEntries())
          .where((e) => e.projectionType == ProjectionType.consumptionTotal)
          .toList();

  test('MOB #32: una aplicación con 3 productos da 3 totales; revertirla los reduce', () async {
    final f = await seedConsumptionFixture();
    final multi = await f.apply(f.ownerPersonId, {
      f.sync.litreProductId: 2500,
      f.sync.kiloProductId: 1500,
      f.extraLitreProductId: 700,
    });
    await f.apply(f.ownerPersonId, {f.sync.litreProductId: 1000});
    var preview = await f.publisher.preview();
    expect(totals(preview), {
      litreRef: 3500,
      kiloRef: 1500,
      extraLitreRef: 700,
    });
    expect(
      {for (final row in preview.rows) row.target.productRef: row.baseUnit},
      {litreRef: BaseUnit.ml, kiloRef: BaseUnit.g, extraLitreRef: BaseUnit.ml},
    );
    expect(await f.publisher.publish(preview), 3);

    await f.sync.repo.reverseApplication(multi, reason: 'error de carga');
    preview = await f.publisher.preview();
    // La reversión resta la aplicación entera de cada total; lo que queda en
    // cero se corrige a cero, no se deja el valor anterior en Central.
    expect(totals(preview), {litreRef: 1000, kiloRef: 0, extraLitreRef: 0});
    expect(changes(preview).values.toSet(), {ConsumptionChange.supersede});
  });

  test('sólo se encola lo que cambió, en una transacción y sin tocar el inventario', () async {
    final f = await seedConsumptionFixture();
    await f.apply(f.ownerPersonId, {f.sync.litreProductId: 2500});
    final db = await f.sync.database.database;
    Future<String> dump() async => jsonEncode([
      for (final table in [
        'applications',
        'application_items',
        'application_consumptions',
        'inventory_movements',
        'inventory_lots',
        'account_transactions',
      ])
        await db.query(table, orderBy: 'id'),
    ]);
    final before = await dump();
    var preview = await f.publisher.preview();
    expect(changes(preview), {litreRef: ConsumptionChange.publish});
    // La vista previa no escribe nada.
    expect(await consumption(f), isEmpty);
    expect(await f.publisher.publish(preview), 1);
    final first = (await consumption(f)).single;
    expect(first.action, SyncAction.publish);
    expect(first.quantityBase, '2500');
    expect(first.status, OutboxStatus.pending);
    expect(await dump(), before);

    preview = await f.publisher.preview();
    expect(changes(preview), {litreRef: ConsumptionChange.unchanged});
    expect(preview.hasChanges, isFalse);
    expect(await f.publisher.publish(preview), 0);

    // Aceptado por Central: un cambio posterior es un SUPERSEDE encadenado.
    await f.sync.outbox.recordAccepted(first, '2026-10-16T12:00:00.000Z');
    await f.apply(f.ownerPersonId, {f.sync.litreProductId: 500});
    preview = await f.publisher.preview();
    expect(changes(preview), {litreRef: ConsumptionChange.supersede});
    await f.publisher.publish(preview);
    final second = (await consumption(f)).last;
    expect(second.action, SyncAction.supersede);
    expect(second.quantityBase, '3000');
    expect(second.predecessorOperationId, first.operationId);
  });

  test('una vista previa desactualizada no publica nada', () async {
    final f = await seedConsumptionFixture();
    await f.apply(f.ownerPersonId, {f.sync.litreProductId: 2500});
    final stale = await f.publisher.preview();
    await f.apply(f.ownerPersonId, {f.sync.litreProductId: 100});
    await expectLater(
      f.publisher.publish(stale),
      throwsA(isA<ConsumptionPublishException>()),
    );
    expect(await consumption(f), isEmpty);
  });

  test('si falla un total, no se encola ninguno', () async {
    final f = await seedConsumptionFixture();
    await f.apply(f.ownerPersonId, {
      f.sync.litreProductId: 2500,
      f.sync.kiloProductId: 100,
    });
    final db = await f.sync.database.database;
    await db.execute(
      "CREATE TEMP TRIGGER fail_second BEFORE INSERT ON sync_outbox "
      "WHEN NEW.product_ref = '$kiloRef' BEGIN SELECT RAISE(ABORT, 'falla'); END",
    );
    await expectLater(
      f.publisher.publish(await f.publisher.preview()),
      throwsA(anything),
    );
    expect(await consumption(f), isEmpty);
  });

  test(
    'en compartido sólo cuenta el titular; lo no vinculado se avisa',
    () async {
      final f = await seedConsumptionFixture();
      await f.apply(f.ownerPersonId, {
        f.sync.litreProductId: 2500,
        f.sync.unboundProductId: 300,
      });
      await f.apply(f.familyPersonId, {f.sync.litreProductId: 9000});
      final preview = await f.publisher.preview();
      expect(totals(preview), {litreRef: 2500});
      expect(preview.excludedLines[ConsumptionExclusion.notOwner], 1);
      expect(
        preview.excludedPairs.single.reason,
        ConsumptionExclusion.productNotBound,
      );
      expect(preview.excludedPairs.single.product, 'Adherente local');
    },
  );

  test('el envelope lleva sólo los cuatro campos de F06', () async {
    final f = await seedConsumptionFixture();
    await f.apply(f.ownerPersonId, {f.sync.litreProductId: 2500});
    await f.publisher.publish(await f.publisher.preview());
    final envelope = envelopeOf((await consumption(f)).single);
    expect(envelope['projectionType'], 'CONSUMPTION_TOTAL');
    expect((envelope['payload']! as Map).keys.toSet(), {
      'campaign_ref',
      'product_ref',
      'base_unit',
      'quantity_base',
    });
    expect(jsonEncode(envelope), isNot(contains('Chaco')));
  });

  test('el worker de D3 envía el consumo y registra el ACK', () async {
    final f = await seedConsumptionFixture();
    await f.apply(f.ownerPersonId, {
      f.sync.litreProductId: 2500,
      f.sync.kiloProductId: 100,
    });
    await f.publisher.publish(await f.publisher.preview());
    final bodies = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      bodies.add(body);
      return http.Response(ackJson(body['operationId'] as String), 200);
    });
    final access = SyncAccessHolder()
      ..accept('token-sintetico', memberA.memberId, memberA.tenantId);
    final worker = SyncWorker(
      outbox: f.sync.outbox,
      owners: OwnerBindingStore(f.sync.database),
      api: () => SyncApi(
        AuthHttpClient(
          config: ApiEndpointConfig(Uri.parse('https://sindicato.example')),
          client: client,
        ),
      ),
      access: access,
    );
    final report = await worker.run();
    expect(report.accepted, 2);
    expect(bodies.map((body) => body['projectionType']).toSet(), {
      'CONSUMPTION_TOTAL',
    });
    expect(
      (await consumption(f)).every((e) => e.status == OutboxStatus.acked),
      isTrue,
    );
  });

  test(
    'un conflicto bloquea ese total; el titular envía su total actual',
    () async {
      final f = await seedConsumptionFixture();
      await f.apply(f.ownerPersonId, {f.sync.litreProductId: 2500});
      await f.publisher.publish(await f.publisher.preview());
      final sent = (await consumption(f)).single;
      await f.sync.outbox.markSending(sent);
      final sending = (await consumption(f)).single;
      const head = '33333333-3333-4333-8333-333333333333';
      const reference = '44444444-4444-4444-8444-444444444444';
      await f.sync.outbox.recordConflict(sending, 'CAUSAL_FORK', reference);
      var preview = await f.publisher.preview();
      expect(changes(preview), {litreRef: ConsumptionChange.conflict});
      expect(preview.hasChanges, isFalse);
      final view = OperationView.validate({
        'ack': jsonDecode(
          ackJson(sent.operationId, outcome: 'CONFLICT', reference: reference),
        ),
        'contribution': {
          'status': 'CONTESTED',
          'headOperationId': head,
          'reconciliationReference': reference,
        },
      }, sent.operationId)!;
      await f.publisher.resolveConflict(row: preview.rows.single, view: view);
      final resolution = (await consumption(f)).last;
      expect(resolution.action, SyncAction.supersede);
      expect(resolution.quantityBase, '2500');
      expect(resolution.predecessorOperationId, head);
      expect(resolution.reconciliationReference, reference);
      preview = await f.publisher.preview();
      expect(changes(preview), {litreRef: ConsumptionChange.unchanged});
    },
  );

  test('sin titular no se publica', () async {
    final f = await seedConsumptionFixture();
    final db = await f.sync.database.database;
    await db.update('owner_bindings', {
      'ended_at': '2026-10-16T00:00:00.000Z',
      'end_reason': 'OWNER_CHANGED',
    });
    await expectLater(
      f.publisher.preview(),
      throwsA(isA<ConsumptionPublishException>()),
    );
  });
}
