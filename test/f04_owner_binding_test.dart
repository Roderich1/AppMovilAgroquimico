// Vínculo de titular (criterios A y C): referencias mínimas, elección
// explícita, inmutabilidad y propiedad de la cola.
import 'dart:convert';
import 'dart:io';

import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/domain/installation_access.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';

class _PendingQueue implements SyncQueueInspector {
  const _PendingQueue(this.count);
  final int count;
  @override
  Future<int> operationsBoundTo(DatabaseExecutor db, int bindingId) async =>
      count;
}

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late AgroRepository repo;
  late OwnerBindingStore store;

  setUp(() {
    database = openDb(inMemoryDatabasePath);
    repo = AgroRepository(database);
    store = OwnerBindingStore(database);
  });

  group('elección explícita del titular', () {
    test(
      'vincular un familiar guarda sólo persona, Member, tenant y fecha',
      () async {
        final household = await seedHousehold(repo);
        final binding = await store.bindExistingPerson(
          personId: household.titular,
          scope: memberA,
          installationRef: installationHere,
        );
        expect(binding.personId, household.titular);
        expect(binding.scope, memberA);
        final db = await database.database;
        final row = (await db.query('owner_bindings')).single;
        // Sin cuenta, tokens, contraseñas ni installationClientId.
        expect(row.keys.toSet(), {
          'id',
          'person_id',
          'member_id',
          'tenant_id',
          'bound_at',
          'ended_at',
          'end_reason',
        });
        expect(
          (await settings(db))[AppDatabase.activatedInstallationKey],
          installationHere,
        );
      },
    );

    test('un administrador de pagos o un tercero no pueden ser titular; los roles no cambian', () async {
      final household = await seedHousehold(repo);
      final admin = await repo.addPerson(name: 'Paga', role: PersonRole.admin);
      final db = await database.database;
      final before = await dumpTables(db);
      for (final person in [admin, household.thirdParty]) {
        await expectLater(
          store.bindExistingPerson(
            personId: person,
            scope: memberA,
            installationRef: installationHere,
          ),
          throwsA(isA<OwnerBindingException>()),
        );
      }
      expect(await dumpTables(db), before);
    });

    test('no hay vínculo por coincidencia de nombre: una persona homónima no se vincula sola', () async {
      final household = await seedHousehold(repo);
      await repo.addPerson(name: 'Titular', role: PersonRole.family);
      expect(await store.activeBinding(), isNull);
      await store.bindExistingPerson(
        personId: household.titular,
        scope: memberA,
        installationRef: installationHere,
      );
      expect((await store.activeBinding())!.personId, household.titular);
    });

    test('persona archivada o inexistente, ámbito inválido y segundo vínculo se rechazan', () async {
      final household = await seedHousehold(repo);
      await repo.archiveCatalog('persons', household.relative);
      Future<void> rejects(Future<Object?> call) =>
          expectLater(call, throwsA(isA<OwnerBindingException>()));
      await rejects(
        store.bindExistingPerson(
          personId: household.relative,
          scope: memberA,
          installationRef: installationHere,
        ),
      );
      await rejects(
        store.bindExistingPerson(
          personId: 9999,
          scope: memberA,
          installationRef: installationHere,
        ),
      );
      await rejects(
        store.bindExistingPerson(
          personId: household.titular,
          scope: const OwnerScope(memberId: 'NO-ES-UUID', tenantId: 'x'),
          installationRef: installationHere,
        ),
      );
      await store.bindExistingPerson(
        personId: household.titular,
        scope: memberA,
        installationRef: installationHere,
      );
      await rejects(
        store.bindNewPerson(
          name: 'Otro',
          scope: memberA,
          installationRef: installationHere,
        ),
      );
      expect(await store.history(), hasLength(1));
    });

    test(
      'crear el titular nuevo y su vínculo es una sola transacción',
      () async {
        final binding = await store.bindNewPerson(
          name: 'Juana',
          scope: memberA,
          installationRef: installationHere,
        );
        final db = await database.database;
        final person = (await db.query(
          'persons',
          where: 'id=?',
          whereArgs: [binding.personId],
        )).single;
        expect(person['role'], PersonRole.family.code);
        expect(person['name'], 'Juana');
      },
    );
  });

  group('inmutabilidad del vínculo (motor SQLite)', () {
    Future<OwnerBinding> bound() async {
      final household = await seedHousehold(repo);
      return store.bindExistingPerson(
        personId: household.titular,
        scope: memberA,
        installationRef: installationHere,
      );
    }

    test(
      'no se puede reasignar persona, Member o tenant ni borrar el vínculo',
      () async {
        final binding = await bound();
        final db = await database.database;
        for (final change in <Map<String, Object?>>[
          {'person_id': binding.personId + 1},
          {'member_id': memberB.memberId},
          {'tenant_id': memberAOtherTenant.tenantId},
          {'bound_at': '2000-01-01T00:00:00.000Z'},
        ]) {
          await expectLater(
            db.update('owner_bindings', change),
            throwsA(isA<DatabaseException>()),
          );
        }
        await expectLater(
          db.delete('owner_bindings'),
          throwsA(isA<DatabaseException>()),
        );
        expect((await store.activeBinding())!.scope, memberA);
      },
    );

    test('un vínculo cerrado no se reabre ni se vuelve a cerrar', () async {
      final binding = await bound();
      final db = await database.database;
      await db.update('owner_bindings', {
        'ended_at': '2026-10-15T00:00:00.000Z',
        'end_reason': 'OWNER_CHANGED',
      });
      await expectLater(
        db.update('owner_bindings', {'ended_at': null, 'end_reason': null}),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        db.update('owner_bindings', {'ended_at': '2027-01-01T00:00:00.000Z'}),
        throwsA(isA<DatabaseException>()),
      );
      expect((await store.history()).single.id, binding.id);
    });

    test('nunca hay dos vínculos activos', () async {
      final binding = await bound();
      final db = await database.database;
      await expectLater(
        db.insert('owner_bindings', {
          'person_id': binding.personId,
          'member_id': memberA.memberId,
          'tenant_id': memberA.tenantId,
          'bound_at': '2026-10-15T00:00:00.000Z',
        }),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('cambio de titular: la cola anterior no se reasigna', () {
    late Household household;
    setUp(() async {
      household = await seedHousehold(repo);
      await store.bindExistingPerson(
        personId: household.titular,
        scope: memberA,
        installationRef: installationHere,
      );
    });

    test(
      'con envíos sin asentar del titular actual se rechaza sin cambios',
      () async {
        final db = await database.database;
        final before = await dumpTables(db);
        await expectLater(
          store.changeOwner(
            newPersonId: household.relative,
            sessionScope: memberA,
            queue: const _PendingQueue(1),
          ),
          throwsA(isA<OwnerBindingException>()),
        );
        expect(await dumpTables(db), before);
      },
    );

    test(
      'en modo propio se rechaza: primero hay que volver a compartido',
      () async {
        await OperationModeStore(database)
            .apply(OperationMode.personal, confirmed: true);
        await expectLater(
          store.changeOwner(
            newPersonId: household.relative,
            sessionScope: memberA,
          ),
          throwsA(isA<OwnerBindingException>()),
        );
      },
    );

    test('otra identidad no puede cambiar el titular', () async {
      await expectLater(
        store.changeOwner(
          newPersonId: household.relative,
          sessionScope: memberB,
        ),
        throwsA(isA<OwnerBindingException>()),
      );
    });

    test('sin cola pendiente: cierra el vínculo anterior y abre otro del mismo Member', () async {
      final db = await database.database;
      final business = await dumpTables(db, except: {'owner_bindings'});
      final next = await store.changeOwner(
        newPersonId: household.relative,
        sessionScope: memberA,
      );
      expect(next.personId, household.relative);
      expect(next.scope, memberA);
      final history = await store.history();
      expect(history, hasLength(2));
      expect(history.first.personId, household.titular);
      expect(history.first.endReason, 'OWNER_CHANGED');
      expect(history.first.endedAt, isNotNull);
      // Ningún dato de negocio cambia de propietario.
      expect(await dumpTables(db, except: {'owner_bindings'}), business);
    });
  });

  group('restaurar referencias no demuestra identidad (criterio A)', () {
    test('una base con vínculo restaurada en otra instalación exige reactivar con el mismo Member', () async {
      final household = await seedHousehold(repo);
      await household.buy(household.titular, 5000);
      await store.bindExistingPerson(
        personId: household.titular,
        scope: memberA,
        installationRef: installationElsewhere,
      );
      // Llega a esta instalación sin sesión: no se habilita.
      Future<InstallationAccessState> classifyHere({
        LocalSessionCondition session = LocalSessionCondition.absent,
        OwnerScope? scope,
      }) async => classifyInstallation(
        await store.accessInputs(
          session: session,
          sessionScope: scope,
          currentInstallationRef: installationHere,
        ),
      );
      expect(
        await classifyHere(),
        InstallationAccessState.restoredRequiresActivation,
      );

      final db = await database.database;
      final before = await dumpTables(db);
      // Otra cuenta activa: no se adoptan los datos ni se crea vínculo.
      expect(
        await classifyHere(
          session: LocalSessionCondition.readable,
          scope: memberB,
        ),
        InstallationAccessState.identityMismatch,
      );
      await expectLater(
        store.recordActivatedInstallation(
          sessionScope: memberB,
          installationRef: installationHere,
        ),
        throwsA(isA<OwnerBindingException>()),
      );
      expect(await dumpTables(db), before);

      // El mismo Member reactiva: se registra esta instalación y nada más.
      await store.recordActivatedInstallation(
        sessionScope: memberA,
        installationRef: installationHere,
      );
      expect(
        await dumpTables(db, except: {'app_settings'}),
        {...before}..remove('app_settings'),
      );
      expect(
        await classifyHere(session: LocalSessionCondition.unreadable),
        InstallationAccessState.activatedSessionUnavailable,
      );
    });
  });

  test(
    'el archivo de la base no contiene tokens ni contraseñas: sólo referencias',
    () async {
      final path = await tempDbPath('sin_secretos');
      final fileDb = openDb(path);
      final fileStore = OwnerBindingStore(fileDb);
      await fileStore.bindNewPerson(
        name: 'Juana',
        scope: memberA,
        installationRef: installationHere,
      );
      await fileDb.close();
      final bytes = await File(path).readAsString(encoding: latin1);
      expect(bytes, contains(memberA.memberId));
      expect(bytes, isNot(contains('11111111-1111-4111-8111-111111111111')));
      expect(bytes.toLowerCase(), isNot(contains('refresh')));
      expect(bytes, isNot(contains('eyJ')));
    },
  );
}
