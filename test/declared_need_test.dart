// F06-COLL-04 (MOB #34, parte local): necesidad declarada expresa, con
// historial, campaña por fecha y sin efecto sobre el inventario.
import 'package:agroquimicos/data/farmer_operation_gate.dart';
import 'package:agroquimicos/data/sync/declared_need_store.dart';
import 'package:agroquimicos/domain/installation_access.dart';
import 'package:agroquimicos/domain/sync/operation_id.dart';
import 'package:agroquimicos/domain/sync/sync_types.dart';
import 'package:agroquimicos/domain/sync/sync_wire.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';
import 'support/f05_sync_fixtures.dart';

const _syncTables = {'sync_outbox', 'declared_needs', 'declared_need_versions'};

void main() {
  sqfliteFfiInit();

  test('declarar sin conexión: necesidad, versión e intención PENDING; el inventario no cambia', () async {
    final fixture = await seedSyncFixture();
    final db = await fixture.database.database;
    final before = await dumpTables(db, except: _syncTables);

    await fixture.needs.declare(
      referenceDate: inCampaign,
      productId: fixture.litreProductId,
      quantityBase: 25000,
    );

    final need = (await fixture.needs.needs()).single;
    expect(need.campaignId, fixture.campaignId);
    expect(need.status, DeclaredNeedStatus.active);
    expect(need.quantityBase, 25000);
    expect(need.referenceDate, '2026-10-15');
    expect(need.syncStatus, OutboxStatus.pending);
    final entry = (await fixture.outboxEntries()).single;
    expect(entry.operationId, matches(uuidV4Lowercase));
    expect(entry.ownerBindingId, fixture.ownerBindingId);
    expect(entry.action, SyncAction.publish);
    expect(entry.quantityBase, '25000');
    expect(entry.campaignRef, campaignRef);
    expect(entry.productRef, litreRef);
    expect(entry.baseUnit, BaseUnit.ml);
    expect(entry.attempts, 0);
    // Ni inventario, compras, aplicaciones ni ninguna otra tabla cambia.
    expect(await dumpTables(db, except: _syncTables), before);
  });

  test('cero es una declaración explícita, distinta de no declarar', () async {
    final fixture = await seedSyncFixture();
    expect(await fixture.needs.needs(), isEmpty);
    await fixture.needs.declare(
      referenceDate: inCampaign,
      productId: fixture.litreProductId,
      quantityBase: 0,
    );
    final need = (await fixture.needs.needs()).single;
    expect(need.status, DeclaredNeedStatus.active);
    expect(need.quantityBase, 0);
    expect((await fixture.outboxEntries()).single.quantityBase, '0');
  });

  test(
    'modificar conserva la versión anterior; sólo la nueva queda vigente',
    () async {
      final fixture = await seedSyncFixture();
      final id = await fixture.needs.declare(
        referenceDate: inCampaign,
        productId: fixture.litreProductId,
        quantityBase: 1000,
      );
      await fixture.needs.updateQuantity(id, 3000);
      final history = await fixture.needs.history(id);
      expect(history.map((v) => (v.version, v.quantityBase)), [
        (2, 3000),
        (1, 1000),
      ]);
      final needs = await fixture.needs.needs();
      expect(needs, hasLength(1));
      expect(needs.single.quantityBase, 3000);
      // Nunca salió: la intención se reescribe, no se suma ni se duplica.
      final entry = (await fixture.outboxEntries()).single;
      expect(entry.action, SyncAction.publish);
      expect(entry.quantityBase, '3000');
    },
  );

  test('tras salir del teléfono, un cambio es un SUPERSEDE encadenado, no una mutación', () async {
    final fixture = await seedSyncFixture();
    final id = await fixture.needs.declare(
      referenceDate: inCampaign,
      productId: fixture.litreProductId,
      quantityBase: 1000,
    );
    final first = await fixture.outbox.markSending(
      (await fixture.outboxEntries()).single,
    );
    await fixture.outbox.recordAccepted(first, '2026-10-15T12:00:00.000Z');
    await fixture.needs.updateQuantity(id, 1500);
    final entries = await fixture.outboxEntries();
    expect(entries, hasLength(2));
    expect(entries.first.quantityBase, '1000');
    expect(entries.last.action, SyncAction.supersede);
    expect(entries.last.predecessorOperationId, first.operationId);
    expect(entries.last.quantityBase, '1500');
    expect(entries.last.operationId, isNot(first.operationId));
  });

  test('retirar: deja de estar vigente, conserva el historial y queda pendiente de envío', () async {
    final fixture = await seedSyncFixture();
    final id = await fixture.needs.declare(
      referenceDate: inCampaign,
      productId: fixture.litreProductId,
      quantityBase: 1000,
    );
    final first = await fixture.outbox.markSending(
      (await fixture.outboxEntries()).single,
    );
    await fixture.outbox.recordAccepted(first, '2026-10-15T12:00:00.000Z');
    await fixture.needs.withdraw(id);

    final need = (await fixture.needs.needs()).single;
    expect(need.status, DeclaredNeedStatus.cancelled);
    expect(need.quantityBase, isNull);
    expect(need.syncStatus, OutboxStatus.pending);
    expect((await fixture.needs.history(id)).map((v) => v.status), [
      DeclaredNeedStatus.cancelled,
      DeclaredNeedStatus.active,
    ]);
    final cancel = (await fixture.outboxEntries()).last;
    expect(cancel.action, SyncAction.cancel);
    expect(cancel.quantityBase, isNull);
    expect(envelopeOf(cancel)['payload'], isNot(contains('quantity_base')));
  });

  test('retirar antes de que saliera el primer valor no envía nada', () async {
    final fixture = await seedSyncFixture();
    final id = await fixture.needs.declare(
      referenceDate: inCampaign,
      productId: fixture.litreProductId,
      quantityBase: 1000,
    );
    await fixture.needs.withdraw(id);
    final entry = (await fixture.outboxEntries()).single;
    expect(entry.status, OutboxStatus.discarded);
    expect((await fixture.needs.needs()).single.syncStatus, isNull);
  });

  test('sin campaña determinable no se asigna en silencio', () async {
    final fixture = await seedSyncFixture();
    // Antes del inicio de toda campaña.
    await expectLater(
      fixture.needs.declare(
        referenceDate: DateTime(2025, 1, 1),
        productId: fixture.litreProductId,
        quantityBase: 1000,
      ),
      throwsA(isA<DeclaredNeedException>()),
    );
    // Dos campañas cubren la fecha.
    await fixture.repo.addCampaign(
      name: 'Otra campaña',
      start: DateTime(2026, 10, 1),
    );
    final ambiguous = await fixture.needs.campaignFor(inCampaign);
    expect(ambiguous.problem, CampaignForDateProblem.ambiguous);
    await expectLater(
      fixture.needs.declare(
        referenceDate: inCampaign,
        productId: fixture.litreProductId,
        quantityBase: 1000,
      ),
      throwsA(isA<DeclaredNeedException>()),
    );
    expect(await fixture.outboxRows(), isEmpty);
  });

  // Reproducido en el POCO el 2026-10-15: una campaña creada a las 21:38 en
  // La Paz se guardó con el día UTC siguiente y no cubría la fecha de hoy.
  // Sólo discrimina con una zona horaria distinta de UTC.
  test(
    'la campaña se compara por día local aunque sus fechas se guarden en UTC',
    () async {
      final db = await openDb(inMemoryDatabasePath).database;
      final night = DateTime(2026, 10, 15, 23, 30);
      final id = await db.insert('campaigns', {
        'name': 'Creada de noche',
        'start_date': night.toUtc().toIso8601String(),
        'end_date': DateTime(2026, 10, 20, 0, 30).toUtc().toIso8601String(),
        'status': 'ACTIVE',
      });
      Future<CampaignForDate> on(int day) =>
          DeclaredNeedStore.campaignForDate(db, DateTime(2026, 10, day));
      for (final day in [15, 20]) {
        final covered = await on(day);
        expect(covered.campaignId, id, reason: 'día $day');
        expect(covered.problem, CampaignForDateProblem.notBound);
      }
      expect((await on(14)).problem, CampaignForDateProblem.none);
      expect((await on(21)).problem, CampaignForDateProblem.none);
    },
  );

  test('una campaña sin vínculo vigente pide vincular', () async {
    final fixture = await seedSyncFixture(bindCatalog: false);
    final resolved = await fixture.needs.campaignFor(inCampaign);
    expect(resolved.problem, CampaignForDateProblem.notBound);
    expect(resolved.message, contains('requiere vinculación'));
  });

  test('sin titular vinculado no se declara', () async {
    final database = openDb(inMemoryDatabasePath);
    final store = DeclaredNeedStore(database);
    await expectLater(
      store.declare(referenceDate: inCampaign, productId: 1, quantityBase: 1),
      throwsA(isA<DeclaredNeedException>()),
    );
  });

  test(
    'la compuerta de activación bloquea declarar sin escribir nada',
    () async {
      final fixture = await seedSyncFixture();
      final blocked = DeclaredNeedStore(
        fixture.database,
        gate: FarmerOperationGate(
          () => InstallationAccessState.newRequiresActivation,
        ),
      );
      await expectLater(
        blocked.declare(
          referenceDate: inCampaign,
          productId: fixture.litreProductId,
          quantityBase: 1000,
        ),
        throwsA(isA<FarmerOperationBlockedException>()),
      );
      expect(await fixture.outboxRows(), isEmpty);
    },
  );
}
