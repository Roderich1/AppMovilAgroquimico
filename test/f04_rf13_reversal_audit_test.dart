// RF-13 (docs/architecture/F04_RF13_RF03_ACTOR_Y_TARDIAS.md §1): reversión
// autorizada por el titular, con motivo, efectos, auditoría y referencias en
// una transacción; sin autorización válida no se escribe nada.
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/services/auth/local_owner_credential.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_app_access.dart';
import 'support/f04_mode_fixtures.dart';

class _Storage implements CredentialStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _Fixture {
  _Fixture(
    this.database,
    this.repo,
    this.household,
    this.binding,
    this.credential,
  );
  final AppDatabase database;
  final AgroRepository repo;
  final Household household;
  final OwnerBindingContext binding;
  final LocalOwnerCredential credential;

  Future<OwnerAuthorization> authorize(
    AuthorizationPurpose purpose,
    String subjectRef, {
    OwnerBindingContext? binding,
  }) => credential.verify(
    pin: '284917',
    purpose: purpose,
    subjectRef: subjectRef,
    binding: binding ?? this.binding,
  );

  Future<Map<String, List<Map<String, Object?>>>> dump() async =>
      dumpTables(await database.database);
}

Future<_Fixture> _fixture() async {
  final database = openDb(inMemoryDatabasePath);
  final bound = await seedActivatedInstallation(database);
  final repo = AgroRepository(database);
  final household = await seedHousehold(repo);
  final binding = OwnerBindingContext(
    bindingId: bound.id,
    personId: bound.personId,
    scope: memberA,
  );
  final credential = LocalOwnerCredential(
    storage: _Storage(),
    iterations: 1000,
  );
  final proof = await OwnerOnlineVerification(
    reauthenticate: (_, __) async => true,
    readSessionScope: () async => memberA,
  ).verify(email: 'e', password: 'p', binding: binding);
  await credential.enroll(
    pin: '284917',
    pinConfirmation: '284917',
    proof: proof,
    binding: binding,
  );
  return _Fixture(database, repo, household, binding, credential);
}

void main() {
  sqfliteFfiInit();

  test('an authorized application reversal writes effects, audit and references together', () async {
    final f = await _fixture();
    final h = f.household;
    await h.buy(h.titular, 5000);
    final applicationId = await h.apply(h.titular, h.titularFarm, 2000);
    final auth = await f.authorize(
      AuthorizationPurpose.reverseApplication,
      'application:$applicationId',
    );

    await f.repo.reverseApplication(
      applicationId,
      reason: '  Dosis registrada por error  ',
      authorization: auth,
    );

    final db = await f.database.database;
    final audit = (await db.query('reversal_audit')).single;
    expect(audit['operation_type'], 'APPLICATION');
    expect(audit['operation_id'], applicationId);
    expect(audit['reason'], 'Dosis registrada por error');
    expect(audit['original_person_id'], h.titular);
    expect(
      audit['original_effective_date'],
      DateTime.utc(2026, 2, 1).toIso8601String(),
    );
    expect(audit['actor_person_id'], f.binding.personId);
    expect(audit['actor_binding_id'], f.binding.bindingId);
    expect(audit['actor_member_id'], memberA.memberId);
    expect(audit['actor_tenant_id'], memberA.tenantId);
    expect(audit['actor_method'], 'LOCAL_PIN');
    expect(audit['credential_enrolment_ref'], auth.enrolmentId);
    expect((audit['reversal_ref']! as String).length, 36);
    // The original operation is not reassigned.
    final application = (await db.query(
      'applications',
      where: 'id=?',
      whereArgs: [applicationId],
    )).single;
    expect(application['person_id'], h.titular);
    expect(application['status'], 'REVERSED');
    // Every compensating row is referenced, and only those.
    final effects = await db.query('reversal_audit_effects', orderBy: 'id');
    final movements = await db.query(
      'inventory_movements',
      where: "reference_type='APPLICATION_REVERSAL' AND reference_id=?",
      whereArgs: [applicationId],
    );
    final consumptions = await db.rawQuery(
      'SELECT c.id FROM application_consumptions c JOIN application_items i '
      'ON i.id=c.application_item_id WHERE i.application_id=?',
      [applicationId],
    );
    expect(
      effects
          .where((e) => e['table_name'] == 'inventory_movements')
          .map((e) => e['row_id'])
          .toSet(),
      movements.map((m) => m['id']).toSet(),
    );
    expect(
      effects
          .where((e) => e['table_name'] == 'application_consumptions')
          .map((e) => e['row_id'])
          .toSet(),
      consumptions.map((c) => c['id']).toSet(),
    );
    expect(movements, isNotEmpty);
    final stored = await f.repo.reversalAudit('APPLICATION', applicationId);
    expect(stored!['reversal_ref'], audit['reversal_ref']);
  });

  test(
    'a purchase reversal records lots, movements and no single responsible',
    () async {
      final f = await _fixture();
      final h = f.household;
      final purchaseId = await h.buy(h.titular, 5000);
      await f.repo.reversePurchase(
        purchaseId,
        reason: 'Factura duplicada',
        authorization: await f.authorize(
          AuthorizationPurpose.reversePurchase,
          'purchase:$purchaseId',
        ),
      );
      final db = await f.database.database;
      final audit = (await db.query('reversal_audit')).single;
      expect(audit['operation_type'], 'PURCHASE');
      expect(audit['original_person_id'], isNull);
      final tables = (await db.query('reversal_audit_effects'))
          .map((e) => e['table_name'])
          .toSet();
      expect(tables, containsAll(['inventory_movements', 'inventory_lots']));
    },
  );

  // A missing authorization does not compile: the parameter is required and
  // non-nullable. These are the authorizations that exist but are not valid.
  group('without a valid authorization nothing is written', () {
    for (final (label, build)
        in <(String, Future<OwnerAuthorization> Function(_Fixture, int))>[
          (
            'another purpose',
            (f, id) => f.authorize(
              AuthorizationPurpose.reversePurchase,
              'application:$id',
            ),
          ),
          (
            'another subject',
            (f, id) => f.authorize(
              AuthorizationPurpose.reverseApplication,
              'application:${id + 1}',
            ),
          ),
          (
            'another binding (restored base)',
            (f, id) => f.authorize(
              AuthorizationPurpose.reverseApplication,
              'application:$id',
              binding: OwnerBindingContext(
                bindingId: f.binding.bindingId + 9,
                personId: f.binding.personId,
                scope: memberA,
              ),
            ),
          ),
        ]) {
      test(label, () async {
        final f = await _fixture();
        final h = f.household;
        await h.buy(h.titular, 5000);
        final id = await h.apply(h.titular, h.titularFarm, 2000);
        final auth = await build(f, id);
        final before = await f.dump();
        await expectLater(
          f.repo.reverseApplication(id, reason: 'motivo', authorization: auth),
          throwsA(isA<OwnerAuthorizationRejected>()),
        );
        expect(await f.dump(), before);
      });
    }

    test('an empty reason', () async {
      final f = await _fixture();
      final h = f.household;
      await h.buy(h.titular, 5000);
      final id = await h.apply(h.titular, h.titularFarm, 2000);
      final auth = await f.authorize(
        AuthorizationPurpose.reverseApplication,
        'application:$id',
      );
      final before = await f.dump();
      await expectLater(
        f.repo.reverseApplication(id, reason: '   ', authorization: auth),
        throwsA(isA<BusinessRuleException>()),
      );
      expect(await f.dump(), before);
    });
  });

  test('a used authorization and a double tap produce one reversal', () async {
    final f = await _fixture();
    final h = f.household;
    await h.buy(h.titular, 5000);
    final id = await h.apply(h.titular, h.titularFarm, 2000);
    final auth = await f.authorize(
      AuthorizationPurpose.reverseApplication,
      'application:$id',
    );
    final first = f.repo.reverseApplication(
      id,
      reason: 'motivo',
      authorization: auth,
    );
    final second = f.repo.reverseApplication(
      id,
      reason: 'motivo',
      authorization: auth,
    );
    await first;
    await expectLater(second, throwsA(isA<OwnerAuthorizationRejected>()));
    // A fresh authorization cannot reverse it again either.
    await expectLater(
      f.repo.reverseApplication(
        id,
        reason: 'otra vez',
        authorization: await f.authorize(
          AuthorizationPurpose.reverseApplication,
          'application:$id',
        ),
      ),
      throwsA(isA<BusinessRuleException>()),
    );
    final db = await f.database.database;
    expect(await db.query('reversal_audit'), hasLength(1));
  });

  test('a failure while writing the audit rolls back every effect', () async {
    final f = await _fixture();
    final h = f.household;
    await h.buy(h.titular, 5000);
    final id = await h.apply(h.titular, h.titularFarm, 2000);
    final db = await f.database.database;
    await db.execute(
      "CREATE TRIGGER test_fail BEFORE INSERT ON reversal_audit_effects "
      "BEGIN SELECT RAISE(ABORT, 'injected'); END",
    );
    final before = await f.dump();
    await expectLater(
      f.repo.reverseApplication(
        id,
        reason: 'motivo',
        authorization: await f.authorize(
          AuthorizationPurpose.reverseApplication,
          'application:$id',
        ),
      ),
      throwsA(anything),
    );
    expect(await f.dump(), before);
  });

  test('the audit is immutable', () async {
    final f = await _fixture();
    final h = f.household;
    final id = await h.buy(h.titular, 5000);
    await f.repo.reversePurchase(
      id,
      reason: 'motivo',
      authorization: await f.authorize(
        AuthorizationPurpose.reversePurchase,
        'purchase:$id',
      ),
    );
    final db = await f.database.database;
    await expectLater(
      db.update('reversal_audit', {'reason': 'x'}),
      throwsA(anything),
    );
    await expectLater(db.delete('reversal_audit'), throwsA(anything));
    await expectLater(db.delete('reversal_audit_effects'), throwsA(anything));
  });

  test(
    'a reversal from before v11 has no actor and nothing is inferred',
    () async {
      final f = await _fixture();
      final h = f.household;
      final id = await h.buy(h.titular, 5000);
      await f.repo.reversePurchaseUnauditedForTesting(id, reason: 'antiguo');
      expect(await f.repo.reversalAudit('PURCHASE', id), isNull);
      expect(
        await (await f.database.database).query('reversal_audit'),
        isEmpty,
      );
    },
  );

  test('a base without a bound titular cannot authorize new reversals but keeps operating', () async {
    final database = openDb(inMemoryDatabasePath);
    final repo = AgroRepository(database);
    final household = await seedHousehold(repo);
    final purchaseId = await household.buy(household.titular, 5000);
    final credential = LocalOwnerCredential(
      storage: _Storage(),
      iterations: 1000,
    );
    expect((await credential.status(null)).state, CredentialState.notEnrolled);
    expect(await OwnerBindingStore(database).activeBinding(), isNull);
    // Ordinary operations still work.
    await household.apply(household.titular, household.titularFarm, 1000);
    expect(purchaseId, greaterThan(0));
  });

  test('migration v10 → v11 keeps every row and adds empty tables', () async {
    final path = await tempDbPath('v10');
    final seed = AppDatabase(factory: databaseFactoryFfi, path: path);
    final household = await seedHousehold(AgroRepository(seed));
    final purchase = await household.buy(household.titular, 5000);
    await seed.repoReverse(purchase);
    await seed.close();
    await downgradeToV10(path);
    final old = await databaseFactoryFfi.openDatabase(path);
    final before = await dumpTables(old);
    await old.close();
    final migrated = openDb(path);
    final db = await migrated.database;
    expect((await db.rawQuery('PRAGMA user_version')).single.values.single, 11);
    final after = await dumpTables(
      db,
      except: {
        'reversal_audit',
        'reversal_audit_effects',
        'late_operation_drafts',
      },
    );
    expect(after, before);
    expect(await db.query('reversal_audit'), isEmpty);
    expect(await db.query('late_operation_drafts'), isEmpty);
  });
}

extension on AppDatabase {
  Future<void> repoReverse(int purchaseId) => AgroRepository(this)
      .reversePurchaseUnauditedForTesting(purchaseId, reason: 'antes de v11');
}
