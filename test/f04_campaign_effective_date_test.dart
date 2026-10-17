// Criterio 5 de GATE-F04 (#28): compra y aplicación multiproducto quedan en
// la campaña de su fecha efectiva (RN-15, RN-16, RF-03, RF-07, RF-12), en los
// dos modos y tras cerrar y reabrir la base. Una fecha sin campaña, ambigua,
// de una campaña cerrada o de una planificada se rechaza sin escrituras
// parciales. El calendario no se solapa al dar de alta, activar ni cerrar, y
// ninguna operación cambia de campaña.
//
// Pruebas de HOST (sqflite_common_ffi, base en archivo). No son DEVICE.
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/domain/campaign_calendar.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';

/// Calendario de las pruebas, en días locales:
/// - «Verano» del 01/01/2026 al 30/06/2026, cerrada;
/// - «Invierno» desde el 01/07/2026, activa y abierta.
class Seed {
  Seed(this.path, this.database, this.repo);
  final String path;
  AppDatabase database;
  AgroRepository repo;
  late int titular;
  late int relative;
  late int supplier;
  late int p1;
  late int p2;
  late int titularFarm;
  late int summer;
  late int winter;

  Future<Database> get db => database.database;

  Future<Map<String, List<Map<String, Object?>>>> dump() async =>
      dumpTables(await db);

  /// Cierra la base y la vuelve a abrir desde el archivo.
  Future<void> reopen() async {
    await database.close();
    database = openDb(path);
    repo = AgroRepository(database);
  }

  PurchaseDraft purchase(
    DateTime date, {
    required List<int> people,
    int? campaign,
    int quantity = 4000,
  }) => PurchaseDraft(
    supplierId: supplier,
    campaignId: campaign ?? winter,
    purchaseDate: date,
    items: [
      for (final product in [p1, p2])
        PurchaseItemDraft(
          productId: product,
          quantityBase: quantity,
          currency: CurrencyCode.bob,
          originalUnitPriceMinor: product == p1 ? 10000 : 20000,
          allocations: [
            for (final person in people)
              AllocationDraft(
                personId: person,
                quantityBase: quantity ~/ people.length,
              ),
          ],
        ),
    ],
  );

  ApplicationDraft application(DateTime date, {int quantity = 1000}) =>
      ApplicationDraft(
        personId: titular,
        farmId: titularFarm,
        campaignId: winter,
        appliedAt: date,
        lines: [
          ApplicationLineDraft(productId: p1, quantityBase: quantity),
          ApplicationLineDraft(productId: p2, quantityBase: quantity),
        ],
      );

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
}

Future<Seed> seed(String name, {bool personal = false}) async {
  final path = await tempDbPath(name);
  final database = openDb(path);
  final s = Seed(path, database, AgroRepository(database));
  final repo = s.repo;
  s
    ..titular = await repo.addPerson(name: 'Titular', role: PersonRole.family)
    ..relative = await repo.addPerson(name: 'Hermana', role: PersonRole.family)
    ..supplier = await repo.addSupplier(name: 'Proveedor')
    ..p1 = await repo.addProduct(name: 'Glifosato')
    ..p2 = await repo.addProduct(name: 'Atrazina', unit: 'KG');
  s.titularFarm = await repo.addFarm(
    ownerId: s.titular,
    name: 'Chaco titular',
    areaM2: 10000,
  );
  s.summer = await repo.addCampaign(
    name: 'Verano',
    start: DateTime(2026, 1, 1, 9),
  );
  s.winter = await repo.addCampaign(
    name: 'Invierno',
    start: DateTime(2026, 7, 1, 21, 30),
  );
  await repo.activateCampaign(s.winter, closeCurrent: true);
  if (personal) {
    await OwnerBindingStore(database).bindExistingPerson(
      personId: s.titular,
      scope: memberA,
      installationRef: installationHere,
    );
    await OperationModeStore(database)
        .apply(OperationMode.personal, confirmed: true);
  }
  return s;
}

Matcher rejectedAs(CampaignDateProblem problem, String fragment) => throwsA(
  isA<CampaignDateException>()
      .having((e) => e.problem, 'problem', problem)
      .having((e) => e.message, 'message', contains(fragment)),
);

Matcher calendarRejection(String fragment) => throwsA(
  isA<CampaignCalendarException>().having(
    (e) => e.message,
    'message',
    contains(fragment),
  ),
);

void main() {
  sqfliteFfiInit();

  test('el alta en orden fija el fin de la anterior el día previo y la '
      'activación ya no lo cambia', () async {
    final s = await seed('calendar');
    expect(await s.endDay(s.summer), '2026-06-30');
    expect((await s.campaign(s.summer))['status'], 'CLOSED');
    expect(await s.endDay(s.winter), isNull);
    expect((await s.campaign(s.winter))['status'], 'ACTIVE');
    await s.reopen();
    expect(await s.endDay(s.summer), '2026-06-30');
    expect(await s.endDay(s.winter), isNull);

    // Dos siguientes en orden: la primera queda con su fin fijado por la
    // segunda, y activarla no se lo borra.
    final spring = await s.repo.addCampaign(
      name: 'Primavera',
      start: DateTime(2026, 12, 1),
    );
    await s.repo.addCampaign(name: 'Otoño', start: DateTime(2027, 3, 1));
    expect(await s.endDay(s.winter), '2026-11-30');
    expect(await s.endDay(spring), '2027-02-28');
    await s.repo.activateCampaign(spring, closeCurrent: true);
    expect(await s.endDay(spring), '2027-02-28');
    expect(await s.endDay(s.winter), '2026-11-30');
  });

  for (final personal in [false, true]) {
    final mode = personal ? 'propio' : 'compartido';
    final people = personal
        ? (Seed s) => [s.titular]
        : (Seed s) => [s.titular, s.relative];

    group('modo $mode', () {
      test('límites inclusivos en día local: primer y último minuto', () async {
        final s = await seed('bounds-$mode', personal: personal);
        // Primer minuto del primer día de «Invierno».
        final first = await s.repo.confirmPurchase(
          s.purchase(DateTime(2026, 7, 1, 0, 1), people: people(s)),
        );
        // «Siguiente» empieza el 01/12: «Invierno» termina el 30/11, que
        // sigue siendo suyo hasta el último minuto.
        await s.repo.addCampaign(
          name: 'Siguiente',
          start: DateTime(2026, 12, 1),
        );
        expect(await s.endDay(s.winter), '2026-11-30');
        final last = await s.repo.confirmPurchase(
          s.purchase(DateTime(2026, 11, 30, 23, 59), people: people(s)),
        );
        final rows = await (await s.db).query(
          'purchases',
          where: 'id IN (?, ?)',
          whereArgs: [first, last],
        );
        expect(rows.map((r) => r['campaign_id']).toSet(), {s.winter});

        // Un minuto antes del primero y uno después del último: no.
        final before = await s.dump();
        await expectLater(
          s.repo.confirmPurchase(
            s.purchase(DateTime(2026, 6, 30, 23, 59), people: people(s)),
          ),
          rejectedAs(CampaignDateProblem.closed, '«Verano»'),
        );
        await expectLater(
          s.repo.confirmApplication(s.application(DateTime(2026, 12, 1))),
          rejectedAs(CampaignDateProblem.planned, '«Siguiente»'),
        );
        expect(await s.dump(), before);
      });

      test(
        'compra y aplicación multiproducto quedan en la campaña de su '
        'fecha y se conservan al cerrar y reabrir, con la hora completa',
        () async {
          final s = await seed('persist-$mode', personal: personal);
          final buyAt = DateTime(2026, 7, 10, 15, 45, 12);
          final applyAt = DateTime(2026, 7, 11, 22, 30);
          final purchase = await s.repo.confirmPurchase(
            s.purchase(buyAt, people: people(s)),
          );
          final application = await s.repo.confirmApplication(
            s.application(applyAt),
          );
          await s.reopen();
          final db = await s.db;
          final p = (await db.query(
            'purchases',
            where: 'id=?',
            whereArgs: [purchase],
          )).single;
          expect(p['campaign_id'], s.winter);
          expect(p['purchase_date'], buyAt.toUtc().toIso8601String());
          final items = await db.query(
            'purchase_items',
            where: 'purchase_id=?',
            whereArgs: [purchase],
          );
          expect(items, hasLength(2));
          final a = (await db.query(
            'applications',
            where: 'id=?',
            whereArgs: [application],
          )).single;
          expect(a['campaign_id'], s.winter);
          expect(a['applied_at'], applyAt.toUtc().toIso8601String());
          expect(
            await db.query(
              'application_items',
              where: 'application_id=?',
              whereArgs: [application],
            ),
            hasLength(2),
          );
        },
      );

      test('ninguna, ambigua, cerrada o planificada: rechazo explícito y '
          'ninguna escritura parcial en compra ni aplicación', () async {
        final s = await seed('reject-$mode', personal: personal);
        await s.repo.confirmPurchase(
          s.purchase(DateTime(2026, 7, 2), people: people(s)),
        );
        // Solape heredado (base anterior a la regla): una fila insertada a
        // mano que cubre agosto.
        await (await s.db).insert('campaigns', {
          'name': 'Heredada',
          'start_date': DateTime(2026, 8, 1).toUtc().toIso8601String(),
          'end_date': DateTime(2026, 8, 31).toUtc().toIso8601String(),
          'status': 'CLOSED',
        });
        final before = await s.dump();
        final cases = <(DateTime, CampaignDateProblem, String)>[
          (DateTime(2025, 12, 31, 23), CampaignDateProblem.none, 'ninguna'),
          (DateTime(2026, 8, 15), CampaignDateProblem.ambiguous, 'Heredada'),
          (DateTime(2026, 3, 15), CampaignDateProblem.closed, '«Verano»'),
        ];
        for (final (date, problem, fragment) in cases) {
          await expectLater(
            s.repo.confirmPurchase(s.purchase(date, people: people(s))),
            rejectedAs(problem, fragment),
          );
          await expectLater(
            s.repo.confirmApplication(s.application(date)),
            rejectedAs(problem, fragment),
          );
        }
        expect(await s.dump(), before);
      });
    });
  }

  test('FIFO usa la fecha completa: el lote de la mañana sale antes que el '
      'de la tarde del mismo día, aunque se registrara después', () async {
    final s = await seed('fifo');
    final afternoon = await s.repo.confirmPurchase(
      s.purchase(
        DateTime(2026, 7, 10, 17),
        people: [s.titular],
        quantity: 1000,
      ),
    );
    final morning = await s.repo.confirmPurchase(
      s.purchase(DateTime(2026, 7, 10, 8), people: [s.titular], quantity: 1000),
    );
    final application = await s.repo.confirmApplication(
      s.application(DateTime(2026, 7, 12), quantity: 500),
    );
    final db = await s.db;
    final consumed = await db.rawQuery(
      '''SELECT pi.purchase_id FROM application_consumptions ac
      JOIN application_items ai ON ai.id = ac.application_item_id
      JOIN inventory_lots l ON l.id = ac.inventory_lot_id
      JOIN purchase_items pi ON pi.id = l.purchase_item_id
      WHERE ai.application_id = ?''',
      [application],
    );
    expect(consumed.map((r) => r['purchase_id']).toSet(), {morning});
    expect(morning, isNot(afternoon));
  });

  group('calendario', () {
    test('no se intercala una campaña ni se repite un inicio', () async {
      final s = await seed('interleave');
      final before = await s.dump();
      await expectLater(
        s.repo.addCampaign(name: 'Intermedia', start: DateTime(2026, 3, 1)),
        calendarRejection('se agregan en orden'),
      );
      await expectLater(
        s.repo.addCampaign(name: 'Mismo día', start: DateTime(2026, 7, 1, 8)),
        calendarRejection('se agregan en orden'),
      );
      await expectLater(
        s.repo.addCampaign(
          name: 'Al revés',
          start: DateTime(2027, 2, 1),
          end: DateTime(2027, 1, 1),
        ),
        calendarRejection('anterior a la de inicio'),
      );
      expect(await s.dump(), before);
    });

    test(
      'el alta no deja operaciones de la anterior fuera de su período',
      () async {
        final s = await seed('add-ops');
        await s.repo.confirmPurchase(
          s.purchase(DateTime(2026, 8, 10, 23), people: [s.titular]),
        );
        final before = await s.dump();
        await expectLater(
          s.repo.addCampaign(name: 'Pronto', start: DateTime(2026, 8, 10)),
          calendarRejection('10/08/2026'),
        );
        expect(await s.dump(), before);
        await s.repo.addCampaign(name: 'Después', start: DateTime(2026, 8, 11));
        expect(await s.endDay(s.winter), '2026-08-10');
      },
    );

    test('cerrar con un fin elegido: inclusivo, no antes del inicio y sin '
        'dejar operaciones fuera', () async {
      final s = await seed('close-end');
      await s.repo.confirmPurchase(
        s.purchase(DateTime(2026, 7, 5), people: [s.titular]),
      );
      await s.repo.confirmApplication(s.application(DateTime(2026, 8, 10)));
      final before = await s.dump();
      await expectLater(
        s.repo.closeCampaign(s.winter, end: DateTime(2026, 8, 9)),
        calendarRejection('10/08/2026'),
      );
      await expectLater(
        s.repo.closeCampaign(s.winter, end: DateTime(2026, 6, 30)),
        calendarRejection('anterior al inicio'),
      );
      expect(await s.dump(), before);
      await s.repo.closeCampaign(s.winter, end: DateTime(2026, 8, 10, 23));
      expect(await s.endDay(s.winter), '2026-08-10');
      expect((await s.campaign(s.winter))['status'], 'CLOSED');
    });

    test(
      'base anterior a la regla: al activar se cierra la abierta el día '
      'previo, o se rechaza sin cambios si dejaría operaciones fuera',
      () async {
        final s = await seed('legacy');
        await s.repo.confirmPurchase(
          s.purchase(DateTime(2026, 9, 5), people: [s.titular]),
        );
        final db = await s.db;
        // Dos planificadas abiertas, como las dejaba el alta anterior.
        final early = await db.insert('campaigns', {
          'name': 'Temprana',
          'start_date': DateTime(2026, 9, 1).toUtc().toIso8601String(),
          'status': 'PLANNED',
        });
        final late = await db.insert('campaigns', {
          'name': 'Tardía',
          'start_date': DateTime(2026, 10, 1).toUtc().toIso8601String(),
          'status': 'PLANNED',
        });
        final before = await s.dump();
        await expectLater(
          s.repo.activateCampaign(early, closeCurrent: true),
          calendarRejection('05/09/2026'),
        );
        expect(await s.dump(), before);
        // «Temprana» y «Tardía» siguen abiertas las dos y solapan: tampoco
        // se activa «Tardía» mientras «Temprana» siga abierta.
        await expectLater(
          s.repo.activateCampaign(late, closeCurrent: true),
          calendarRejection('se solapa'),
        );
        expect(await s.dump(), before);
        await db.update(
          'campaigns',
          {'end_date': DateTime(2026, 9, 30).toUtc().toIso8601String()},
          where: 'id=?',
          whereArgs: [early],
        );
        await s.repo.activateCampaign(late, closeCurrent: true);
        expect(await s.endDay(s.winter), '2026-09-30');
        expect((await s.campaign(s.winter))['status'], 'CLOSED');
        expect((await s.campaign(late))['status'], 'ACTIVE');
      },
    );

    test('la propuesta de inicio respeta el orden del calendario', () async {
      final s = await seed('suggest');
      final today = localDay(DateTime.now());
      expect(localDay(await s.repo.suggestedCampaignStart()), today);
      await s.repo.addCampaign(
        name: 'Futura',
        start: DateTime.now().add(const Duration(days: 40)),
      );
      expect(
        localDay(await s.repo.suggestedCampaignStart()),
        nextLocalDay(localDay(DateTime.now().add(const Duration(days: 40)))),
      );
    });
  });
}
