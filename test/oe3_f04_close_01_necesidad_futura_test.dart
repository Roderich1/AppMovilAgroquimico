// OE3, cierre HOST de #122 (F04-CLOSE-01): «una versión de necesidad
// posterior a hoy». `F04_REPETICION_DEVICE.md` §4 lo dejó como deducción de
// dos guardas probadas por separado (ningún registro de la campaña después del
// fin, y fin <= hoy) y señaló que no había prueba que lo ejecutara ni que
// cubriera la retirada. Aquí se ejecuta:
//
// - por el camino de la app: `DeclaredNeedStore.declare` acepta una fecha de
//   referencia posterior a hoy dentro de la campaña activa (el selector de
//   `declared_needs_screen.dart` llega hasta 2100). Con esa necesidad, y con
//   otra retirada (versión CANCELLED) también futura, la campaña no se cierra
//   hoy, ni sin fin explícito, ni en ese día futuro (fin <= hoy). Ninguna
//   tabla cambia;
// - la tabla de versiones por sí sola: una versión CANCELLED fechada después
//   de hoy, sobre una necesidad fechada antes, también impide cerrar (la
//   consulta de `_lastOperationDay` no filtra por estado).
//
// Criterio de #122: «No dejar fuera compras, aplicaciones, necesidades ni sus
// versiones … Cancelar o rechazar conserva todas las tablas.»
//
// Pruebas de HOST (sqflite_common_ffi, base en memoria). No son DEVICE.
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/domain/campaign_calendar.dart';
import 'package:agroquimicos/data/sync/declared_need_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';
import 'support/f05_sync_fixtures.dart';

Matcher _calendarRejection(String fragment) => throwsA(
  isA<CampaignCalendarException>().having(
    (e) => e.message,
    'message',
    contains(fragment),
  ),
);

void main() {
  sqfliteFfiInit();

  test('una necesidad declarada para después de hoy, y otra retirada con esa '
      'fecha, impiden cerrar la campaña hoy; ninguna tabla cambia', () async {
    final fixture = await seedSyncFixture();
    final db = await fixture.database.database;
    final future = DateTime.now().add(const Duration(days: 5));
    final futureDay = localDay(future);
    final today = localDay(DateTime.now());
    expect(futureDay.compareTo(today), greaterThan(0));

    final active = await fixture.needs.declare(
      referenceDate: future,
      productId: fixture.litreProductId,
      quantityBase: 12000,
    );
    final withdrawn = await fixture.needs.declare(
      referenceDate: future,
      productId: fixture.kiloProductId,
      quantityBase: 3000,
    );
    await fixture.needs.withdraw(withdrawn);

    // Las dos quedan en la campaña activa, con sus versiones fechadas en el
    // día futuro; la retirada termina en una versión CANCELLED.
    final needs = {for (final n in await fixture.needs.needs()) n.id: n};
    expect(needs[active]!.campaignId, fixture.campaignId);
    expect(needs[active]!.referenceDate, futureDay);
    expect(needs[withdrawn]!.status, DeclaredNeedStatus.cancelled);
    expect(needs[withdrawn]!.referenceDate, futureDay);
    final versions = await db.query('declared_need_versions', orderBy: 'id');
    expect(versions.map((v) => (v['declared_need_id'], v['status'])), [
      (active, 'ACTIVE'),
      (withdrawn, 'ACTIVE'),
      (withdrawn, 'CANCELLED'),
    ]);
    expect(versions.map((v) => v['reference_date']), everyElement(futureDay));

    final before = await dumpTables(db);
    // Sin fin explícito el fin es hoy: dejaría fuera las necesidades.
    await expectLater(
      fixture.repo.closeCampaign(fixture.campaignId),
      _calendarRejection(displayDay(futureDay)),
    );
    await expectLater(
      fixture.repo.closeCampaign(fixture.campaignId, end: DateTime.now()),
      _calendarRejection(displayDay(futureDay)),
    );
    // Y no se puede elegir ese día como fin: es posterior a hoy.
    await expectLater(
      fixture.repo.closeCampaign(fixture.campaignId, end: future),
      _calendarRejection('no puede ser posterior'),
    );
    expect(await dumpTables(db), before);
    final campaign = (await db.query(
      'campaigns',
      where: 'id=?',
      whereArgs: [fixture.campaignId],
    )).single;
    expect(campaign['status'], 'ACTIVE');
    expect(campaign['end_date'], isNull);
  });

  test('sólo la versión: una versión retirada fechada después de hoy, sobre '
      'una necesidad de antes, también impide cerrar', () async {
    final fixture = await seedSyncFixture();
    final db = await fixture.database.database;
    final futureDay = localDay(DateTime.now().add(const Duration(days: 3)));
    final need = await db.insert('declared_needs', {
      'owner_binding_id': fixture.ownerBindingId,
      'campaign_id': fixture.campaignId,
      'product_id': fixture.litreProductId,
      'status': 'CANCELLED',
      'quantity_base': null,
      'reference_date': '2026-10-15',
      'current_version': 1,
      'updated_at': DateTime.utc(2026, 10, 15).toIso8601String(),
    });
    await db.insert('declared_need_versions', {
      'declared_need_id': need,
      'version': 1,
      'status': 'CANCELLED',
      'quantity_base': null,
      'reference_date': futureDay,
      'created_at': DateTime.utc(2026, 10, 15).toIso8601String(),
    });
    final before = await dumpTables(db);
    await expectLater(
      fixture.repo.closeCampaign(fixture.campaignId),
      _calendarRejection(displayDay(futureDay)),
    );
    expect(await dumpTables(db), before);
  });
}
