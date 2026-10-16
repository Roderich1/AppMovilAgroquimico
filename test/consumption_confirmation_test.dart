// F06 (MOB #86): lo que se publica es exactamente lo que el titular confirmó.
// Una vista previa queda ligada a la identidad completa de cada destino
// (titular, proyección, campaña, producto, unidad), a su cantidad y a la
// intención previa sobre la que se planifica. Escenarios construidos sólo con
// APIs públicas sobre SQLite real.
import 'dart:async';
import 'dart:convert';

import 'package:agroquimicos/data/database_replacement.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/data/sync/consumption_publisher.dart';
import 'package:agroquimicos/domain/sync/sync_types.dart';
import 'package:agroquimicos/domain/sync/sync_wire.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';
import 'support/f05_sync_fixtures.dart';
import 'support/f06_consumption_fixtures.dart';

void main() {
  sqfliteFfiInit();

  Future<List<OutboxEntry>> outbox(ConsumptionFixture f) =>
      f.sync.outboxEntries();

  test(
    'una vista previa confirmada para un titular no publica el consumo de otro '
    'con las mismas cantidades',
    () async {
      final f = await seedConsumptionFixture();
      // Compartido: titular y familiar con el mismo consumo del mismo producto.
      await f.apply(f.ownerPersonId, {f.sync.litreProductId: 2500});
      await f.apply(f.familyPersonId, {f.sync.litreProductId: 2500});
      final before = (await f.sync.owners.activeBinding())!;

      final confirmed = await f.publisher.preview();
      expect(confirmed.rows.single.quantityBase, 2500);
      expect(confirmed.rows.single.target.ownerBindingId, before.id);

      // Sin outbox todavía, el cambio de titular está permitido.
      final after = await f.sync.owners.changeOwner(
        newPersonId: f.familyPersonId,
        sessionScope: memberA,
      );
      expect(after.personId, f.familyPersonId);
      expect(after.scope, before.scope);

      await expectLater(
        f.publisher.publish(confirmed),
        throwsA(isA<ConsumptionPublishException>()),
      );
      expect(await outbox(f), isEmpty);

      // Una vista previa nueva muestra el consumo del titular vigente.
      final fresh = await f.publisher.preview();
      expect(fresh.rows.single.target.ownerBindingId, after.id);
      expect(await f.publisher.publish(fresh), 1);
      expect((await outbox(f)).single.ownerBindingId, after.id);
    },
  );

  test('una vista previa vieja con el mismo total pero sobre otra intención '
      'previa se rechaza', () async {
    final f = await seedConsumptionFixture();
    // Cada envío recibe su ACK antes del siguiente: así cada publicación es
    // un SUPERSEDE nuevo encadenado (una intención aún no enviada se
    // actualiza en su sitio y no cambiaría la intención previa).
    Future<void> publishAndAck() async {
      await f.publisher.publish(await f.publisher.preview());
      final last = (await outbox(f)).last;
      await f.sync.outbox.recordAccepted(
        await f.sync.outbox.markSending(last),
        '2026-10-16T12:00:00.000Z',
      );
    }

    await f.apply(f.ownerPersonId, {f.sync.litreProductId: 2500});
    await publishAndAck();
    await f.apply(f.ownerPersonId, {f.sync.litreProductId: 500});
    // Pantalla que quedó abierta: SUPERSEDE 3000 sobre la primera intención.
    final stale = await f.publisher.preview();
    expect(stale.rows.single.quantityBase, 3000);

    // Mientras tanto se publican 3000 y luego 3700, y la última aplicación
    // se revierte: el total vuelve a 3000, sobre otra intención previa.
    await publishAndAck();
    final extra = await f.apply(f.ownerPersonId, {f.sync.litreProductId: 700});
    await publishAndAck();
    await f.sync.repo.reverseApplication(extra, reason: 'error de carga');
    final current = (await f.publisher.preview()).rows.single;
    expect(current.quantityBase, 3000);
    expect(current.change, stale.rows.single.change);
    expect(
      current.prior!.operationId,
      isNot(stale.rows.single.prior!.operationId),
    );

    final written = (await outbox(f)).length;
    await expectLater(
      f.publisher.publish(stale),
      throwsA(isA<ConsumptionPublishException>()),
    );
    expect((await outbox(f)).length, written);
  });

  test('durante una restauración no se publica: nada se escribe', () async {
    final f = await seedConsumptionFixture();
    await f.apply(f.ownerPersonId, {f.sync.litreProductId: 2500});
    final confirmed = await f.publisher.preview();
    final outside = Zone.current;
    Object? refused;
    await f.sync.database.replacement.replace(() async {
      await outside.run(
        () => f.publisher
            .publish(confirmed)
            .then<void>((_) {}, onError: (Object error) => refused = error),
      );
    });
    expect(refused, isA<DatabaseReplacementInProgressException>());
    expect(await outbox(f), isEmpty);
    // Terminada la restauración, la misma confirmación vuelve a valer.
    expect(await f.publisher.publish(confirmed), 1);
  });

  group('resolver un conflicto', () {
    const head = '33333333-3333-4333-8333-333333333333';
    const reference = '44444444-4444-4444-8444-444444444444';

    Future<({OutboxEntry sent, OperationView view})> conflicted(
      ConsumptionFixture f,
    ) async {
      await f.apply(f.ownerPersonId, {f.sync.litreProductId: 2500});
      await f.publisher.publish(await f.publisher.preview());
      final sent = (await outbox(f)).single;
      await f.sync.outbox.recordConflict(
        await f.sync.outbox.markSending(sent),
        'CAUSAL_FORK',
        reference,
      );
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
      return (sent: sent, view: view);
    }

    test('sólo envía el total que el titular vio y confirmó', () async {
      final f = await seedConsumptionFixture();
      final (:sent, :view) = await conflicted(f);
      final shown = (await f.publisher.preview()).rows.single;
      expect(shown.change, ConsumptionChange.conflict);
      expect(shown.quantityBase, 2500);

      // Después de mostrarse, el total local cambia (nueva aplicación).
      await f.apply(f.ownerPersonId, {f.sync.litreProductId: 500});
      final rows = await outbox(f);
      await expectLater(
        f.publisher.resolveConflict(row: shown, view: view),
        throwsA(isA<ConsumptionPublishException>()),
      );
      final unchanged = await outbox(f);
      expect(unchanged.length, rows.length);
      expect(unchanged.single.resolvedAt, isNull);

      // Con el total vigente a la vista, sí se envía ese valor.
      final current = (await f.publisher.preview()).rows.single;
      expect(current.quantityBase, 3000);
      await f.publisher.resolveConflict(row: current, view: view);
      final resolution = (await outbox(f)).last;
      expect(resolution.quantityBase, '3000');
      expect(resolution.predecessorOperationId, head);
      expect(sent.operationId, isNot(resolution.operationId));
    });

    test(
      'mientras hay un conflicto del titular no se puede cambiar de titular',
      () async {
        final f = await seedConsumptionFixture();
        await conflicted(f);
        await expectLater(
          f.sync.owners.changeOwner(
            newPersonId: f.familyPersonId,
            sessionScope: memberA,
          ),
          throwsA(isA<OwnerBindingException>()),
        );
      },
    );
  });
}
