// RF-03 (docs/architecture/F04_RF13_RF03_ACTOR_Y_TARDIAS.md §2): compra y
// aplicación tardías con revisión. El oráculo de existencias y del historial
// de cada lote está escrito aquí, a partir de las operaciones, antes de medir.
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/services/auth/local_owner_credential.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_app_access.dart';
import 'support/f04_mode_fixtures.dart';
import 'support/f04_owner_pin.dart';

class _World {
  _World(
    this.database,
    this.repo,
    this.h,
    this.binding,
    this.credential,
    this.history,
  );
  final AppDatabase database;
  final AgroRepository repo;
  final Household h;
  final OwnerBindingContext binding;
  final LocalOwnerCredential credential;
  final int history;

  Future<OwnerAuthorization> auth(AuthorizationPurpose purpose, String ref) =>
      credential.verify(
        pin: '284917',
        purpose: purpose,
        subjectRef: 'late:$ref',
        binding: binding,
      );

  Future<LateResolution> confirm(String ref) async => repo.confirmLateOperation(
    ref,
    authorization: await auth(AuthorizationPurpose.confirmLateOperation, ref),
  );

  PurchaseDraft purchase(DateTime date, int quantity) => PurchaseDraft(
    supplierId: h.supplier,
    campaignId: h.campaign,
    purchaseDate: date,
    items: [
      PurchaseItemDraft(
        productId: h.product,
        quantityBase: quantity,
        currency: CurrencyCode.bob,
        originalUnitPriceMinor: 10000,
        allocations: [
          AllocationDraft(personId: h.titular, quantityBase: quantity),
        ],
      ),
    ],
  );

  ApplicationDraft application(DateTime date, int quantity) => ApplicationDraft(
    personId: h.titular,
    farmId: h.titularFarm,
    campaignId: h.campaign,
    appliedAt: date,
    lines: [ApplicationLineDraft(productId: h.product, quantityBase: quantity)],
  );

  Future<Database> get db => database.database;

  /// Historial de un lote ordenado por día efectivo y después por id, con el
  /// saldo acumulado tras cada día.
  Future<List<int>> lotDayBalances(int lotId) async {
    final rows = await (await db).query(
      'inventory_movements',
      where: 'lot_id=?',
      whereArgs: [lotId],
    );
    final ordered = rows.toList()
      ..sort((a, b) {
        final byDay = (a['movement_date']! as String)
            .substring(0, 10)
            .compareTo((b['movement_date']! as String).substring(0, 10));
        return byDay != 0
            ? byDay
            : (a['id']! as int).compareTo(b['id']! as int);
      });
    final out = <int>[];
    var balance = 0;
    for (var i = 0; i < ordered.length; i++) {
      balance += ordered[i]['quantity_signed']! as int;
      final last =
          i == ordered.length - 1 ||
          (ordered[i + 1]['movement_date']! as String).substring(0, 10) !=
              (ordered[i]['movement_date']! as String).substring(0, 10);
      if (last) out.add(balance);
    }
    return out;
  }

  Future<int> lotOf(int purchaseId) async =>
      (await (await db).rawQuery(
            'SELECT l.id FROM inventory_lots l JOIN purchase_items i ON i.id=l.purchase_item_id WHERE i.purchase_id=?',
            [purchaseId],
          )).single['id']!
          as int;
}

DateTime _d(int y, int m, int d) => DateTime.utc(y, m, d, 15);

Future<_World> _world() async {
  final database = openDb(inMemoryDatabasePath);
  final bound = await seedActivatedInstallation(database);
  late LocalOwnerCredential credential;
  final repo = AgroRepository(
    database,
    ownerEnrolment: () => credential.knownEnrolmentId,
  );
  final h = await seedHousehold(repo);
  final history = await repo.addHistoricalCampaign(
    name: 'Campaña 2025',
    start: _d(2025, 6, 1),
    end: _d(2025, 12, 30),
  );
  final binding = OwnerBindingContext(
    bindingId: bound.id,
    personId: bound.personId,
    scope: memberA,
  );
  credential = (await TestOwnerPin.enrolled(binding)).credential;
  return _World(database, repo, h, binding, credential, history);
}

void main() {
  sqfliteFfiInit();

  group('capture', () {
    test(
      'a pending draft has no effect on stock, operations, reports or outbox',
      () async {
        final w = await _world();
        final before = await dumpTables(
          await w.db,
          except: {'late_operation_drafts'},
        );
        final ref = await w.repo.captureLatePurchase(
          w.purchase(_d(2025, 8, 10), 500),
          reason: 'Factura encontrada',
        );
        expect(
          await dumpTables(await w.db, except: {'late_operation_drafts'}),
          before,
        );
        final drafts = await w.repo.lateOperationDrafts();
        expect(drafts.single['draft_ref'], ref);
        expect(drafts.single['status'], 'PENDING');
        expect(drafts.single['campaign_id'], w.history);
        expect(drafts.single['campaign_name'], 'Campaña 2025');
      },
    );

    test('dates that are future, without a campaign or in the active campaign write nothing', () async {
      final w = await _world();
      final before = await dumpTables(await w.db);
      await expectLater(
        w.repo.captureLatePurchase(
          w.purchase(DateTime.now().add(const Duration(days: 3)), 500),
          reason: 'x',
        ),
        throwsA(
          isA<CampaignDateException>().having(
            (e) => e.problem,
            'problem',
            CampaignDateProblem.future,
          ),
        ),
      );
      await expectLater(
        w.repo.captureLatePurchase(
          w.purchase(_d(2025, 3, 1), 500),
          reason: 'x',
        ),
        throwsA(
          isA<CampaignDateException>().having(
            (e) => e.problem,
            'problem',
            CampaignDateProblem.none,
          ),
        ),
      );
      await expectLater(
        w.repo.captureLatePurchase(
          w.purchase(_d(2026, 2, 1), 500),
          reason: 'x',
        ),
        throwsA(isA<BusinessRuleException>()),
      );
      await expectLater(
        w.repo.captureLatePurchase(
          w.purchase(_d(2025, 8, 1), 500),
          reason: '  ',
        ),
        throwsA(isA<BusinessRuleException>()),
      );
      expect(await dumpTables(await w.db), before);
    });

    test('the pending draft survives reopening the database', () async {
      final path = await tempDbPath('late');
      final first = AppDatabase(factory: databaseFactoryFfi, path: path);
      await seedActivatedInstallation(first);
      final repo = AgroRepository(first);
      final h = await seedHousehold(repo);
      await repo.addHistoricalCampaign(
        name: '2025',
        start: _d(2025, 6, 1),
        end: _d(2025, 12, 30),
      );
      final ref = await repo.captureLateApplication(
        ApplicationDraft(
          personId: h.titular,
          farmId: h.titularFarm,
          campaignId: h.campaign,
          appliedAt: _d(2025, 9, 1),
          lines: [
            ApplicationLineDraft(productId: h.product, quantityBase: 100),
          ],
        ),
        reason: 'Aplicación anotada en papel',
      );
      await first.close();
      final reopened = openDb(path);
      final drafts = await AgroRepository(reopened).lateOperationDrafts();
      expect(drafts.single['draft_ref'], ref);
      expect(drafts.single['status'], 'PENDING');
    });
  });

  group('confirmation', () {
    test(
      'a late purchase is confirmed once in its closed campaign with its date',
      () async {
        final w = await _world();
        final ref = await w.repo.captureLatePurchase(
          w.purchase(_d(2025, 8, 10), 500),
          reason: 'Factura encontrada',
        );
        final result = await w.confirm(ref);
        expect(result.outcome, LateResolutionOutcome.confirmed);
        expect(result.message, contains('no se actualiza'));
        final db = await w.db;
        final purchase = (await db.query(
          'purchases',
          where: 'id=?',
          whereArgs: [result.operationId],
        )).single;
        expect(purchase['campaign_id'], w.history);
        expect(purchase['purchase_date'], _d(2025, 8, 10).toIso8601String());
        final lot = (await db.query(
          'inventory_lots',
          where: 'id=?',
          whereArgs: [await w.lotOf(result.operationId!)],
        )).single;
        expect(lot['acquired_date'], _d(2025, 8, 10).toIso8601String());
        final draft = (await db.query('late_operation_drafts')).single;
        expect(draft['status'], 'CONFIRMED');
        expect(draft['result_operation_id'], result.operationId);
        expect(draft['resolver_person_id'], w.binding.personId);
        expect(draft['resolver_method'], 'LOCAL_PIN');
        expect(
          (await stockByPersonProduct(db))[(w.h.titular, w.h.product)],
          500,
        );
        // Double confirmation: the draft is no longer pending.
        await expectLater(
          w.confirm(ref),
          throwsA(isA<BusinessRuleException>()),
        );
        expect(await db.query('purchases'), hasLength(1));
      },
    );

    test(
      'a rejected draft has no effect and cannot be confirmed afterwards',
      () async {
        final w = await _world();
        final ref = await w.repo.captureLatePurchase(
          w.purchase(_d(2025, 8, 10), 500),
          reason: 'Duplicada',
        );
        final before = await dumpTables(
          await w.db,
          except: {'late_operation_drafts'},
        );
        final result = await w.repo.rejectLateOperation(
          ref,
          authorization: await w.auth(
            AuthorizationPurpose.rejectLateOperation,
            ref,
          ),
          note: 'Ya estaba registrada',
        );
        expect(result.outcome, LateResolutionOutcome.rejected);
        expect(
          await dumpTables(await w.db, except: {'late_operation_drafts'}),
          before,
        );
        final draft = (await (await w.db).query('late_operation_drafts'))
            .single;
        expect(draft['status'], 'REJECTED');
        expect(draft['resolution_note'], 'Ya estaba registrada');
        await expectLater(
          w.confirm(ref),
          throwsA(isA<BusinessRuleException>()),
        );
      },
    );

    test('confirming needs the confirm authorization for that draft', () async {
      final w = await _world();
      final ref = await w.repo.captureLatePurchase(
        w.purchase(_d(2025, 8, 10), 500),
        reason: 'x',
      );
      final other = await w.repo.captureLatePurchase(
        w.purchase(_d(2025, 8, 11), 500),
        reason: 'y',
      );
      final before = await dumpTables(await w.db);
      for (final auth in [
        await w.auth(AuthorizationPurpose.rejectLateOperation, ref),
        await w.auth(AuthorizationPurpose.confirmLateOperation, other),
      ]) {
        await expectLater(
          w.repo.confirmLateOperation(ref, authorization: auth),
          throwsA(isA<OwnerAuthorizationRejected>()),
        );
      }
      expect(await dumpTables(await w.db), before);
    });

    test('a resolved draft is immutable in the database', () async {
      final w = await _world();
      final ref = await w.repo.captureLatePurchase(
        w.purchase(_d(2025, 8, 10), 500),
        reason: 'x',
      );
      await w.confirm(ref);
      final db = await w.db;
      await expectLater(
        db.update('late_operation_drafts', {'status': 'REJECTED'}),
        throwsA(anything),
      );
      await expectLater(
        db.update('late_operation_drafts', {'payload': '{}'}),
        throwsA(anything),
      );
      await expectLater(db.delete('late_operation_drafts'), throwsA(anything));
    });

    test('LATE_CAMPAIGN_CHANGED: the date no longer classifies in the captured campaign', () async {
      final w = await _world();
      final ref = await w.repo.captureLatePurchase(
        w.purchase(_d(2025, 8, 10), 500),
        reason: 'x',
      );
      // The period changes (e.g. corrected start): the date is no longer in it.
      await (await w.db).update(
        'campaigns',
        {'start_date': _d(2025, 9, 1).toIso8601String()},
        where: 'id=?',
        whereArgs: [w.history],
      );
      final before = await dumpTables(
        await w.db,
        except: {'late_operation_drafts'},
      );
      final result = await w.confirm(ref);
      expect(result.outcome, LateResolutionOutcome.conflict);
      expect(result.conflictCode, LateConflict.campaignChanged);
      expect(
        await dumpTables(await w.db, except: {'late_operation_drafts'}),
        before,
      );
      final draft = (await (await w.db).query('late_operation_drafts')).single;
      expect(draft['status'], 'PENDING');
      expect(draft['last_conflict_code'], LateConflict.campaignChanged);
    });
  });

  group('late application with a temporal FIFO (§2.3)', () {
    test('oracle: caps, out-of-order confirmations, later lots and unchanged history', () async {
      final w = await _world();
      final h = w.h;
      final db = await w.db;

      // L1: late purchase on 2025-07-01 (1000). L2: ordinary purchase 2026-01-02 (1000).
      final l1Ref = await w.repo.captureLatePurchase(
        w.purchase(_d(2025, 7, 1), 1000),
        reason: 'L1',
      );
      final l1 = await w.lotOf((await w.confirm(l1Ref)).operationId!);
      await h.buy(h.titular, 1000, date: _d(2026, 1, 2));
      // Ordinary application 2026-02-01 of 1500: FIFO takes L1 (1000) + L2 (500).
      final ordinary = await h.apply(h.titular, h.titularFarm, 1500);
      final ordinaryConsumptions = await db.rawQuery(
        'SELECT c.* FROM application_consumptions c JOIN application_items i ON i.id=c.application_item_id WHERE i.application_id=? ORDER BY c.id',
        [ordinary],
      );

      // A late application on 2025-09-01 of 300: L1 had 1000 that day but is
      // empty after 2026-02-01, so its cap is 0 -> conflict, nothing written.
      final early = await w.repo.captureLateApplication(
        w.application(_d(2025, 9, 1), 300),
        reason: 'A1',
      );
      final beforeConflict = await dumpTables(
        db,
        except: {'late_operation_drafts'},
      );
      final conflict = await w.confirm(early);
      expect(conflict.outcome, LateResolutionOutcome.conflict);
      expect(conflict.conflictCode, LateConflict.stockUnavailable);
      expect(
        await dumpTables(db, except: {'late_operation_drafts'}),
        beforeConflict,
      );

      // The explicit resolution: the missing late purchase L3 on 2025-08-15 (500).
      final l3Ref = await w.repo.captureLatePurchase(
        w.purchase(_d(2025, 8, 15), 500),
        reason: 'L3',
      );
      final l3 = await w.lotOf((await w.confirm(l3Ref)).operationId!);
      final resolved = await w.confirm(early);
      expect(resolved.outcome, LateResolutionOutcome.confirmed);

      // Out of chronological order: 2025-08-20 of 200 (after confirming 09-01).
      final mid = await w.repo.captureLateApplication(
        w.application(_d(2025, 8, 20), 200),
        reason: 'A2',
      );
      expect((await w.confirm(mid)).outcome, LateResolutionOutcome.confirmed);
      // 2025-08-18 of 1: L3 ends at 0 after 09-01 -> cap 0 -> conflict.
      final tooMuch = await w.repo.captureLateApplication(
        w.application(_d(2025, 8, 18), 1),
        reason: 'A3',
      );
      expect(
        (await w.confirm(tooMuch)).conflictCode,
        LateConflict.stockUnavailable,
      );
      // 2025-08-01: L3 (08-15) is acquired later and is not eligible; L1 cap 0.
      final beforeL3 = await w.repo.captureLateApplication(
        w.application(_d(2025, 8, 1), 1),
        reason: 'A4',
      );
      expect(
        (await w.confirm(beforeL3)).conflictCode,
        LateConflict.stockUnavailable,
      );

      // Oracle of lot histories (balance at the end of each day, by date):
      expect(await w.lotDayBalances(l1), [
        1000,
        0,
      ]); // 07-01 +1000, 2026-02-01 -1000
      expect(await w.lotDayBalances(l3), [
        500,
        300,
        0,
      ]); // 08-15 +500, 08-20 -200, 09-01 -300
      for (final lot in [l1, l3]) {
        expect((await w.lotDayBalances(lot)).every((b) => b >= 0), isTrue);
      }
      // The ordinary application keeps its FIFO allocation and costs.
      expect(
        await db.rawQuery(
          'SELECT c.* FROM application_consumptions c JOIN application_items i ON i.id=c.application_item_id WHERE i.application_id=? ORDER BY c.id',
          [ordinary],
        ),
        ordinaryConsumptions,
      );
      // Stock oracle: 1000 + 1000 + 500 bought - 1500 - 300 - 200 applied = 500.
      expect((await stockByPersonProduct(db))[(h.titular, h.product)], 500);
      // Late applications are in the closed campaign with their date.
      final late = await db.query(
        'applications',
        where: 'campaign_id=?',
        whereArgs: [w.history],
        orderBy: 'applied_at',
      );
      expect(late.map((a) => a['applied_at']), [
        _d(2025, 8, 20).toIso8601String(),
        _d(2025, 9, 1).toIso8601String(),
      ]);

      // m2: reversing L3's purchase is refused: its lot was consumed.
      final l3Purchase =
          (await db.query(
                'late_operation_drafts',
                where: 'draft_ref=?',
                whereArgs: [l3Ref],
              )).single['result_operation_id']!
              as int;
      await expectLater(
        w.repo.reversePurchaseUnauditedForTesting(l3Purchase, reason: 'x'),
        throwsA(isA<BusinessRuleException>()),
      );
    });

    test('a later reversal of a purchase does not leave a confirmed late application negative', () async {
      final w = await _world();
      final h = w.h;
      final db = await w.db;
      final l1Ref = await w.repo.captureLatePurchase(
        w.purchase(_d(2025, 7, 1), 1000),
        reason: 'L1',
      );
      final l1 = await w.lotOf((await w.confirm(l1Ref)).operationId!);
      final app = await w.repo.captureLateApplication(
        w.application(_d(2025, 9, 1), 400),
        reason: 'A',
      );
      expect((await w.confirm(app)).outcome, LateResolutionOutcome.confirmed);
      // Reversing L1's purchase is refused while the late application consumes it.
      final purchaseId =
          (await db.query(
                'late_operation_drafts',
                where: 'draft_ref=?',
                whereArgs: [l1Ref],
              )).single['result_operation_id']!
              as int;
      await expectLater(
        w.repo.reversePurchaseUnauditedForTesting(purchaseId, reason: 'x'),
        throwsA(isA<BusinessRuleException>()),
      );
      expect(await w.lotDayBalances(l1), [1000, 600]);
      expect((await stockByPersonProduct(db))[(h.titular, h.product)], 600);
    });
  });

  group('historical period (§2.5)', () {
    test('created closed, without overlap and without changing the active campaign', () async {
      final w = await _world();
      final db = await w.db;
      final active = (await db.query(
        'campaigns',
        where: "status='ACTIVE'",
      )).single;
      final history = (await db.query(
        'campaigns',
        where: 'id=?',
        whereArgs: [w.history],
      )).single;
      expect(history['status'], 'CLOSED');
      await expectLater(
        w.repo.addHistoricalCampaign(
          name: 'Solapa',
          start: _d(2025, 11, 1),
          end: _d(2026, 1, 5),
        ),
        throwsA(isA<CampaignCalendarException>()),
      );
      await expectLater(
        w.repo.addHistoricalCampaign(
          name: 'Hoy',
          start: _d(2024, 1, 1),
          end: DateTime.now(),
        ),
        throwsA(isA<CampaignCalendarException>()),
      );
      await w.repo.addHistoricalCampaign(
        name: '2024',
        start: _d(2024, 6, 1),
        end: _d(2024, 12, 31),
      );
      expect(
        (await db.query('campaigns', where: "status='ACTIVE'")).single,
        active,
      );
    });
  });
}
