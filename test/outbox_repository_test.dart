// F05-SYNC-02 (MOB #30): outbox SQLite atómica. La necesidad, su versión y
// la intención se escriben en una transacción; una intención enviada es
// inmutable y sólo lleva la whitelist F06.
import 'package:agroquimicos/domain/sync/operation_id.dart';
import 'package:agroquimicos/domain/sync/sync_types.dart';
import 'package:agroquimicos/domain/sync/sync_wire.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';
import 'support/f05_sync_fixtures.dart';

void main() {
  sqfliteFfiInit();

  test('la necesidad y su intención persisten tras cerrar y reabrir', () async {
    final path = await tempDbPath('declared');
    final fixture = await seedSyncFixture(path: path);
    await fixture.needs.declare(
      referenceDate: inCampaign,
      productId: fixture.kiloProductId,
      quantityBase: 0,
    );
    final operationId = (await fixture.outboxEntries()).single.operationId;
    await fixture.database.close();

    final reopened = openDb(path);
    final db = await reopened.database;
    expect((await db.query('declared_needs')).single['quantity_base'], 0);
    expect((await db.query('sync_outbox')).single['operation_id'], operationId);
  });

  test('una excepción dentro de la transacción no deja ni la necesidad ni la intención', () async {
    for (final table in ['declared_needs', 'declared_need_versions']) {
      final fixture = await seedSyncFixture(path: await tempDbPath(table));
      final db = await fixture.database.database;
      // Falla forzada en la escritura: tras insertar la intención (y, en el
      // segundo caso, también la necesidad).
      await db.execute(
        'CREATE TEMP TRIGGER fail_$table BEFORE INSERT ON $table '
        "BEGIN SELECT RAISE(ABORT, 'falla forzada'); END",
      );
      await expectLater(
        fixture.needs.declare(
          referenceDate: inCampaign,
          productId: fixture.litreProductId,
          quantityBase: 1000,
        ),
        throwsA(isA<DatabaseException>()),
      );
      await db.execute('DROP TRIGGER fail_$table');
      expect(await fixture.outboxRows(), isEmpty, reason: table);
      expect(await db.query('declared_needs'), isEmpty, reason: table);
      expect(await db.query('declared_need_versions'), isEmpty, reason: table);
    }
  });

  test('una misma intención no se registra dos veces', () async {
    final fixture = await seedSyncFixture();
    await fixture.needs.declare(
      referenceDate: inCampaign,
      productId: fixture.litreProductId,
      quantityBase: 1000,
    );
    final row = (await fixture.outboxRows()).single;
    final db = await fixture.database.database;
    await expectLater(
      db.insert('sync_outbox', {...row}..remove('id')),
      throwsA(isA<DatabaseException>()),
    );
    expect(await fixture.outboxRows(), hasLength(1));
  });

  test(
    'la outbox sólo lleva la whitelist: sin notas, personas, costos ni fotos',
    () async {
      final fixture = await seedSyncFixture();
      await fixture.needs.declare(
        referenceDate: inCampaign,
        productId: fixture.litreProductId,
        quantityBase: 1000,
      );
      final db = await fixture.database.database;
      final columns = {
        for (final row in await db.rawQuery('PRAGMA table_info(sync_outbox)'))
          row['name'] as String,
      };
      for (final forbidden in [
        'notes',
        'person_id',
        'name',
        'cost',
        'invoice',
        'tenant_id',
        'member_id',
        'token',
      ]) {
        expect(
          columns.any((c) => c.contains(forbidden)),
          isFalse,
          reason: forbidden,
        );
      }
      expect(
        (envelopeOf((await fixture.outboxEntries()).single)['payload']! as Map)
            .keys,
        {'campaign_ref', 'product_ref', 'base_unit', 'quantity_base'},
      );
    },
  );

  test('una intención enviada no se modifica ni se borra (trigger)', () async {
    final fixture = await seedSyncFixture();
    await fixture.needs.declare(
      referenceDate: inCampaign,
      productId: fixture.litreProductId,
      quantityBase: 1000,
    );
    final sent = await fixture.outbox.markSending(
      (await fixture.outboxEntries()).single,
    );
    final db = await fixture.database.database;
    for (final change in [
      {'quantity_base': '2000'},
      {'action': 'SUPERSEDE'},
      {'campaign_ref': otherCampaignRef},
      {
        'predecessor_operation_id': '33333333-3333-4333-8333-333333333333',
        'predecessor_kind': 'VALUE',
      },
      {'operation_id': newOperationId()},
      {'owner_binding_id': 99},
      {'attempts': 0},
    ]) {
      await expectLater(
        db.update('sync_outbox', change, where: 'id=?', whereArgs: [sent.id]),
        throwsA(isA<DatabaseException>()),
        reason: '$change',
      );
    }
    await expectLater(
      db.delete('sync_outbox'),
      throwsA(isA<DatabaseException>()),
    );
    await fixture.outbox.recordAccepted(sent, '2026-10-15T12:00:00.000Z');
    await expectLater(
      db.update('sync_outbox', {'status': 'PENDING'}),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      db.update('declared_need_versions', {'quantity_base': 5}),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('una edición en la misma contribución mientras el worker envía no se pierde', () async {
    final fixture = await seedSyncFixture();
    final id = await fixture.needs.declare(
      referenceDate: inCampaign,
      productId: fixture.litreProductId,
      quantityBase: 1000,
    );
    // El worker tomó la intención (attempts=1) antes de la edición.
    final sending = await fixture.outbox.markSending(
      (await fixture.outboxEntries()).single,
    );
    await fixture.needs.updateQuantity(id, 2000);
    final entries = await fixture.outboxEntries();
    expect(entries.first.quantityBase, '1000');
    expect(entries.first.status, OutboxStatus.sending);
    expect(entries.last.predecessorOperationId, sending.operationId);
    expect(entries.last.quantityBase, '2000');
  });
}
