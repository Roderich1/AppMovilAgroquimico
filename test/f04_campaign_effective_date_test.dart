// Criterio 5 de GATE-F04 (#28): compra y aplicación multiproducto quedan en
// la campaña de su fecha efectiva (RN-15, RN-16, RF-03, RF-07, RF-12), en los
// dos modos y tras cerrar y reabrir la base. Una fecha sin campaña, ambigua,
// de una campaña cerrada o de una planificada se rechaza sin escrituras
// parciales. El calendario no se solapa al dar de alta, activar ni cerrar, y
// ninguna operación cambia de campaña.
//
// Pruebas de HOST (sqflite_common_ffi, base en archivo). No son DEVICE.
import 'dart:io';

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
    // segunda, y activarla no se lo borra. Hasta #125 «Primavera» empezaba
    // el 01/12 y «Otoño» el 01/03/2027, fechas futuras; una sucesora que
    // todavía no empezó ya no se activa cerrando la actual, así que las dos
    // se mueven a inicios ya pasados. El propósito no cambia.
    final spring = await s.repo.addCampaign(
      name: 'Primavera',
      start: DateTime(2026, 10, 1),
    );
    await s.repo.addCampaign(name: 'Otoño', start: DateTime(2026, 10, 10));
    expect(await s.endDay(s.winter), '2026-09-30');
    expect(await s.endDay(spring), '2026-10-09');
    await s.repo.activateCampaign(spring, closeCurrent: true);
    expect(await s.endDay(spring), '2026-10-09');
    expect(await s.endDay(s.winter), '2026-09-30');
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
        // «Siguiente» empieza el 01/10: «Invierno» termina el 30/09, que
        // sigue siendo suyo hasta el último minuto. Hasta #121 la siguiente
        // empezaba el 01/12 y la compra del último minuto era del 30/11, una
        // fecha futura; como una compra ya realizada no puede tener fecha
        // futura, el calendario de la prueba se movió al pasado. El propósito
        // no cambia: los dos extremos del día local son inclusivos.
        await s.repo.addCampaign(
          name: 'Siguiente',
          start: DateTime(2026, 10, 1),
        );
        expect(await s.endDay(s.winter), '2026-09-30');
        final last = await s.repo.confirmPurchase(
          s.purchase(DateTime(2026, 9, 30, 23, 59), people: people(s)),
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
          s.repo.confirmApplication(s.application(DateTime(2026, 10, 1))),
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

    test('el alta y el cierre tampoco dejan fuera una necesidad declarada ni '
        'sus versiones', () async {
      final s = await seed('needs', personal: true);
      final db = await s.db;
      final binding = (await db.query('owner_bindings', limit: 1)).single;
      final need = await db.insert('declared_needs', {
        'owner_binding_id': binding['id'],
        'campaign_id': s.winter,
        'product_id': s.p1,
        'status': 'ACTIVE',
        'quantity_base': 1000,
        'reference_date': '2026-09-20',
        'current_version': 1,
        'updated_at': DateTime(2026, 9, 20).toUtc().toIso8601String(),
      });
      var before = await s.dump();
      await expectLater(
        s.repo.addCampaign(name: 'Pronto', start: DateTime(2026, 9, 20)),
        calendarRejection('20/09/2026'),
      );
      expect(await s.dump(), before);
      await db.insert('declared_need_versions', {
        'declared_need_id': need,
        'version': 1,
        'status': 'ACTIVE',
        'quantity_base': 1000,
        'reference_date': '2026-09-25',
        'created_at': DateTime(2026, 9, 25).toUtc().toIso8601String(),
      });
      before = await s.dump();
      await expectLater(
        s.repo.addCampaign(name: 'Pronto', start: DateTime(2026, 9, 22)),
        calendarRejection('25/09/2026'),
      );
      await expectLater(
        s.repo.closeCampaign(s.winter, end: DateTime(2026, 9, 24)),
        calendarRejection('25/09/2026'),
      );
      expect(await s.dump(), before);
      await s.repo.addCampaign(name: 'Después', start: DateTime(2026, 9, 26));
      expect(await s.endDay(s.winter), '2026-09-25');
    });

    test('el cierre no admite un fin futuro', () async {
      final s = await seed('future-end');
      final before = await s.dump();
      await expectLater(
        s.repo.closeCampaign(
          s.winter,
          end: DateTime.now().add(const Duration(days: 2)),
        ),
        calendarRejection('no puede ser posterior'),
      );
      expect(await s.dump(), before);
    });

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

  group('fecha efectiva elegida (#121)', () {
    test('el instante de un día elegido: hoy es ahora; otro día, su '
        'medianoche local, y el día civil no cambia al guardarlo', () {
      final now = DateTime.now();
      expect(
        identical(effectiveInstantForDay(localDay(now), now), now),
        isTrue,
      );
      final past = effectiveInstantForDay('2026-08-15', now);
      expect(localDay(past), '2026-08-15');
      expect([past.hour, past.minute, past.second], [0, 0, 0]);
      final stored = past.toUtc().toIso8601String();
      expect(storedLocalDay(stored), '2026-08-15');
      // Representación declarada de la hora no conocida: la medianoche local
      // del día, guardada en UTC. En UTC es «T00:00:00.000Z»; en La Paz
      // (−04:00) es «T04:00:00.000Z». El día que se lee de vuelta es el mismo.
      final offset = now.timeZoneOffset;
      if (offset == Duration.zero) {
        expect(stored, '2026-08-15T00:00:00.000Z');
      }
      if (offset == const Duration(hours: -4)) {
        expect(stored, '2026-08-15T04:00:00.000Z');
      }
      // Centinela del paso regional de la CI.
      if (Platform.environment['AGRO_TZ_REGRESSION'] != null) {
        expect(offset, const Duration(hours: -4));
      }
    });

    test(
      'una fecha futura se rechaza en compra y aplicación sin escribir',
      () async {
        final s = await seed('future-date');
        final tomorrow = DateTime.now().add(const Duration(days: 1));
        final before = await s.dump();
        await expectLater(
          s.repo.confirmPurchase(s.purchase(tomorrow, people: [s.titular])),
          rejectedAs(CampaignDateProblem.future, 'posterior a hoy'),
        );
        await expectLater(
          s.repo.confirmApplication(s.application(tomorrow)),
          rejectedAs(CampaignDateProblem.future, 'posterior a hoy'),
        );
        // También a medianoche local de mañana, que es lo que mandaría un
        // formulario con el día de mañana elegido.
        await expectLater(
          s.repo.confirmPurchase(
            s.purchase(
              effectiveInstantForDay(localDay(tomorrow), DateTime.now()),
              people: [s.titular],
            ),
          ),
          rejectedAs(CampaignDateProblem.future, 'posterior a hoy'),
        );
        expect(await s.dump(), before);
      },
    );

    test('un día pasado elegido dentro de la campaña activa: multiproducto, '
        'clasificado en su campaña y conservado tras reabrir', () async {
      final s = await seed('chosen-past');
      final at = effectiveInstantForDay('2026-08-15', DateTime.now());
      final purchaseId = await s.repo.confirmPurchase(
        s.purchase(at, people: [s.titular, s.relative]),
      );
      await s.repo.confirmApplication(s.application(at));
      await s.reopen();
      final db = await s.db;
      final purchase = (await db.query(
        'purchases',
        where: 'id=?',
        whereArgs: [purchaseId],
      )).single;
      expect(purchase['campaign_id'], s.winter);
      expect(purchase['purchase_date'], at.toUtc().toIso8601String());
      expect(
        storedLocalDay(purchase['purchase_date']! as String),
        '2026-08-15',
      );
      expect(await db.query('purchase_items'), hasLength(2));
      final application = (await db.query('applications')).single;
      expect(application['campaign_id'], s.winter);
      expect(
        storedLocalDay(application['applied_at']! as String),
        '2026-08-15',
      );
      expect(await db.query('application_items'), hasLength(2));
    });

    test('fronteras a medianoche local: el primer día de la activa entra y el '
        'último de la cerrada se rechaza como cerrada', () async {
      final s = await seed('chosen-borders');
      final now = DateTime.now();
      final id = await s.repo.confirmPurchase(
        s.purchase(
          effectiveInstantForDay('2026-07-01', now),
          people: [s.titular],
        ),
      );
      final purchase = (await (await s.db).query(
        'purchases',
        where: 'id=?',
        whereArgs: [id],
      )).single;
      expect(purchase['campaign_id'], s.winter);
      expect(
        storedLocalDay(purchase['purchase_date']! as String),
        '2026-07-01',
      );
      final before = await s.dump();
      await expectLater(
        s.repo.confirmPurchase(
          s.purchase(
            effectiveInstantForDay('2026-06-30', now),
            people: [s.titular],
          ),
        ),
        rejectedAs(CampaignDateProblem.closed, 'Verano'),
      );
      expect(await s.dump(), before);
    });
  });

  group('cierre con fin previsto (#122)', () {
    test('un fin previsto futuro no cierra la campaña en el futuro: se pide y '
        'valida el fin efectivo igual que sin fin previsto', () async {
      final s = await seed('close-planned-future');
      final planned = DateTime.now().add(const Duration(days: 44));
      await s.repo.setCampaignEnd(s.winter, end: planned);
      expect(await s.endDay(s.winter), localDay(planned));
      final before = await s.dump();
      await expectLater(
        s.repo.closeCampaign(s.winter, end: planned),
        calendarRejection('no puede ser posterior'),
      );
      expect(await s.dump(), before);
      // Sin fin explícito, el fin efectivo es hoy: el previsto no se conserva.
      await s.repo.closeCampaign(s.winter);
      expect(await s.endDay(s.winter), localDay(DateTime.now()));
      expect((await s.campaign(s.winter))['status'], 'CLOSED');
    });

    test(
      'con fin previsto, el fin efectivo tampoco va antes del inicio ni '
      'deja fuera registros; igual al previsto ya pasado, se acepta',
      () async {
        final s = await seed('close-planned-ops');
        await s.repo.confirmPurchase(
          s.purchase(DateTime(2026, 8, 10), people: [s.titular]),
        );
        await s.repo.setCampaignEnd(s.winter, end: DateTime(2026, 9, 30));
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
        await s.repo.closeCampaign(s.winter, end: DateTime(2026, 9, 30));
        expect(await s.endDay(s.winter), '2026-09-30');
        expect((await s.campaign(s.winter))['status'], 'CLOSED');
      },
    );

    test('el fin efectivo no solapa la campaña siguiente', () async {
      final s = await seed('close-overlap');
      await s.repo.addCampaign(name: 'Siguiente', start: DateTime(2026, 9, 15));
      expect(await s.endDay(s.winter), '2026-09-14');
      final before = await s.dump();
      await expectLater(
        s.repo.closeCampaign(s.winter, end: DateTime(2026, 9, 20)),
        calendarRejection('se solapa'),
      );
      expect(await s.dump(), before);
      await s.repo.closeCampaign(s.winter, end: DateTime(2026, 9, 14));
      expect(await s.endDay(s.winter), '2026-09-14');
    });

    test(
      'la excepción de la campaña activa que no empezó se conserva y no se '
      'amplía: su fin es su día de inicio, también con fin previsto',
      () async {
        final s = await seed('close-not-started');
        final start = DateTime.now().add(const Duration(days: 10));
        final future = await s.repo.addCampaign(name: 'Futura', start: start);
        // #125: mientras «Invierno» esté activa, la sucesora futura no se
        // activa, ni cerrando la actual. Hasta #124 esto cerraba «Invierno»
        // con un fin futuro; ahora el camino es cerrar la actual con su fin
        // efectivo y activar la planificada sin otra activa, que es la
        // excepción documentada.
        await expectLater(
          s.repo.activateCampaign(future, closeCurrent: true),
          throwsA(isA<CampaignActivationNotYetException>()),
        );
        await s.repo.closeCampaign(s.winter);
        expect(await s.endDay(s.winter), localDay(DateTime.now()));
        await s.repo.activateCampaign(future);
        expect((await s.campaign(future))['status'], 'ACTIVE');
        await s.repo.setCampaignEnd(
          future,
          end: start.add(const Duration(days: 20)),
        );
        final before = await s.dump();
        await expectLater(
          s.repo.closeCampaign(future),
          calendarRejection('anterior al inicio'),
        );
        await expectLater(
          s.repo.closeCampaign(future, end: start.add(const Duration(days: 1))),
          calendarRejection('no puede ser posterior'),
        );
        expect(await s.dump(), before);
        await s.repo.closeCampaign(future, end: start);
        expect(await s.endDay(future), localDay(start));
        expect((await s.campaign(future))['status'], 'CLOSED');
      },
    );
  });
}
