// #125: con otra campaña activa, una sucesora cuyo inicio aún no llegó no se
// activa, con ni sin `closeCurrent`: cerraría la actual antes de tiempo y el
// día de hoy quedaría dentro de una campaña cerrada. El día de inicio cuenta
// como llegado (inclusivo). Sin otra activa, una planificada futura sí se
// activa (excepción ya documentada, que no se amplía ni se quita) y cierra en
// su propio día de inicio. Llegar la fecha no salta las guardas existentes.
//
// Fechas relativas a hoy, en días locales. Pruebas de HOST (sqflite_common_ffi,
// base en archivo); la CI las repite en America/La_Paz.
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/campaign_calendar.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';

class Seed {
  Seed(this.database, this.repo);
  final AppDatabase database;
  final AgroRepository repo;
  late int person;
  late int supplier;
  late int product;
  late int current;

  Future<Database> get db => database.database;

  Future<Map<String, List<Map<String, Object?>>>> dump() async =>
      dumpTables(await db);

  Future<Map<String, Object?>> campaign(int id) async =>
      (await (await db).query(
        'campaigns',
        where: 'id=?',
        whereArgs: [id],
      )).single;

  Future<String?> endDay(int id) async {
    final end = (await campaign(id))['end_date'] as String?;
    return end == null ? null : storedLocalDay(end);
  }

  Future<List<CampaignPeriod>> periods() async => [
    for (final row in await (await db).query('campaigns', orderBy: 'id'))
      CampaignPeriod.fromRow(row),
  ];

  Future<int> buy(DateTime at, int campaignId) => repo.confirmPurchase(
    PurchaseDraft(
      supplierId: supplier,
      campaignId: campaignId,
      purchaseDate: at,
      items: [
        PurchaseItemDraft(
          productId: product,
          quantityBase: 1000,
          currency: CurrencyCode.bob,
          originalUnitPriceMinor: 10000,
          allocations: [AllocationDraft(personId: person, quantityBase: 1000)],
        ),
      ],
    ),
  );
}

/// «Actual» activa desde el 01/01/2026, abierta.
Future<Seed> seed(String name) async {
  final database = openDb(await tempDbPath(name));
  final s = Seed(database, AgroRepository(database));
  s
    ..person = await s.repo.addPerson(name: 'Titular', role: PersonRole.family)
    ..supplier = await s.repo.addSupplier(name: 'Proveedor')
    ..product = await s.repo.addProduct(name: 'Glifosato')
    ..current = await s.repo.addCampaign(
      name: 'Actual',
      start: DateTime(2026, 1, 1),
    );
  return s;
}

DateTime daysFromToday(int days) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + days, 12);
}

Matcher notYet(String fragment) => throwsA(
  isA<CampaignActivationNotYetException>().having(
    (e) => e.message,
    'message',
    contains(fragment),
  ),
);

void main() {
  sqfliteFfiInit();

  test('antes del inicio: se rechaza con y sin closeCurrent, con la fecha '
      'desde la que se podrá activar, y ninguna tabla cambia', () async {
    final s = await seed('too-early');
    final start = daysFromToday(10);
    final successor = await s.repo.addCampaign(name: 'Siguiente', start: start);
    // El alta ya fijó el fin de «Actual» el día previo al inicio (futuro).
    expect(await s.endDay(s.current), previousLocalDay(localDay(start)));
    final before = await s.dump();
    final when = displayDay(localDay(start));
    await expectLater(
      s.repo.activateCampaign(successor),
      notYet('Se podrá activar desde el $when'),
    );
    await expectLater(
      s.repo.activateCampaign(successor, closeCurrent: true),
      notYet('Se podrá activar desde el $when'),
    );
    // No es el conflicto genérico (que la pantalla resuelve con «Cerrar y
    // activar»): es un rechazo propio.
    await expectLater(
      s.repo.activateCampaign(successor),
      throwsA(isNot(isA<CampaignConflictException>())),
    );
    expect(await s.dump(), before);
    expect((await s.campaign(s.current))['status'], 'ACTIVE');
    expect((await s.campaign(successor))['status'], 'PLANNED');
    // Hoy sigue operable en «Actual».
    final today = localDay(DateTime.now());
    expect(campaignsContaining(await s.periods(), today).single.id, s.current);
    await s.buy(DateTime.now(), s.current);
  });

  test('mañana a medianoche local también es futuro; el día de inicio, '
      'inclusive, se admite y deja hoy dentro de la nueva activa', () async {
    final s = await seed('inclusive');
    final tomorrow = daysFromToday(1);
    final successor = await s.repo.addCampaign(
      name: 'Siguiente',
      start: startOfLocalDay(localDay(tomorrow)),
    );
    await expectLater(
      s.repo.activateCampaign(successor, closeCurrent: true),
      notYet(displayDay(localDay(tomorrow))),
    );

    final t = await seed('inclusive-today');
    final today = localDay(DateTime.now());
    final todaySuccessor = await t.repo.addCampaign(
      name: 'Siguiente',
      start: startOfLocalDay(today),
    );
    await t.repo.activateCampaign(todaySuccessor, closeCurrent: true);
    expect((await t.campaign(t.current))['status'], 'CLOSED');
    expect(await t.endDay(t.current), previousLocalDay(today));
    expect((await t.campaign(todaySuccessor))['status'], 'ACTIVE');
    // Hoy pertenece a la nueva activa y opera.
    expect(
      campaignsContaining(await t.periods(), today).single.id,
      todaySuccessor,
    );
    await t.buy(DateTime.now(), todaySuccessor);
  });

  test('un inicio ya pasado se admite como siempre', () async {
    final s = await seed('past-start');
    final successor = await s.repo.addCampaign(
      name: 'Siguiente',
      start: daysFromToday(-3),
    );
    await s.repo.activateCampaign(successor, closeCurrent: true);
    expect((await s.campaign(successor))['status'], 'ACTIVE');
    expect(await s.endDay(s.current), localDay(daysFromToday(-4)));
  });

  test('sin otra activa, una planificada futura sí se activa (excepción '
      'conservada) y su cierre sigue siendo en su día de inicio', () async {
    final s = await seed('no-active');
    final start = daysFromToday(10);
    final future = await s.repo.addCampaign(name: 'Futura', start: start);
    // Camino válido: cerrar la actual con su fin efectivo (#122) y activar.
    await s.repo.closeCampaign(s.current);
    expect(await s.endDay(s.current), localDay(DateTime.now()));
    await s.repo.activateCampaign(future);
    expect((await s.campaign(future))['status'], 'ACTIVE');
    // La excepción no se amplía: el cierre de la que no empezó es en su
    // inicio, ni antes ni después.
    await expectLater(
      s.repo.closeCampaign(future, end: daysFromToday(11)),
      throwsA(isA<CampaignCalendarException>()),
    );
    await s.repo.closeCampaign(future, end: start);
    expect(await s.endDay(future), localDay(start));
  });

  test('llegar la fecha no salta las guardas existentes: una actual abierta '
      'con operaciones de hoy no se cierra a ayer', () async {
    final s = await seed('guards');
    await s.buy(DateTime.now(), s.current);
    final db = await s.db;
    // Base anterior a la regla de orden: una planificada abierta que empieza
    // hoy, insertada como la dejaba el alta antigua, con la actual aún sin fin.
    final legacy = await db.insert('campaigns', {
      'name': 'Heredada',
      'start_date': startOfLocalDay(localDay(DateTime.now()))
          .toUtc()
          .toIso8601String(),
      'status': 'PLANNED',
    });
    final before = await s.dump();
    await expectLater(
      s.repo.activateCampaign(legacy, closeCurrent: true),
      throwsA(
        isA<CampaignCalendarException>().having(
          (e) => e.message,
          'message',
          contains('tiene operaciones del'),
        ),
      ),
    );
    expect(await s.dump(), before);
  });
}
