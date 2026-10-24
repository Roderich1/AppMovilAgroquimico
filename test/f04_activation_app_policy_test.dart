// Política de activación en la app real (#76): arranque, router, compuerta
// del repositorio, elección del titular y modo de uso. Base, router y
// repositorio reales; sólo se sustituyen la sesión segura y la identidad.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/farmer_operation_gate.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/domain/installation_access.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/installation_access.dart';
import 'package:agroquimicos/presentation/screens/dashboard_screen.dart';
import 'package:agroquimicos/services/auth/existing_session_providers.dart';
import 'package:agroquimicos/services/auth/existing_session_startup.dart';
import 'package:agroquimicos/services/auth/refresh_guard.dart';
import 'package:agroquimicos/services/auth/remote_session_coordinator.dart';
import 'package:agroquimicos/services/auth/remote_session_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_app_access.dart';
import 'support/f04_mode_fixtures.dart';

void main() {
  sqfliteFfiInit();

  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      if (finder.evaluate().isNotEmpty) return;
    }
  }

  /// Avanza con E/S real (sqflite) hasta que no queden indicadores de carga.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      // Unas vueltas mínimas para que una navegación construya su pantalla.
      if (i >= 8 && find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        break;
      }
    }
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<ProviderContainer> pumpApp(
    WidgetTester tester,
    AppDatabase database, {
    required ExistingSessionStartupState session,
    OwnerScope? scope,
    String? installationRef,
  }) async {
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        existingSessionStartupProvider.overrideWithValue(session),
        ...startupAccessOverrides(
          sessionScope: scope,
          installationRef: installationRef,
        ),
        // Los controles de sesión remota del Dashboard no usan aquí el
        // almacenamiento Android: no forman parte de esta política.
        refreshGuardProvider.overrideWithValue(_ClearGuard()),
        remoteSessionProvider.overrideWith(_IdleRemote.new),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const AgroApp()),
    );
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      if (container.read(installationAccessProvider) != null) break;
    }
    await settle(tester);
    return container;
  }

  Future<Object?> attemptWrite(WidgetTester tester, ProviderContainer c) =>
      tester.runAsync<Object?>(() async {
        try {
          await c.read(repositoryProvider).addProduct(name: 'Intento');
          return null;
        } on Object catch (error) {
          return error;
        }
      });

  String path(ProviderContainer c) =>
      c.read(routerProvider).routeInformationProvider.value.uri.path;

  Future<AppDatabase> legacyDatabaseWithData(WidgetTester tester) async {
    final file = await tester.runAsync(() => tempDbPath('legacy'));
    await tester.runAsync(() async {
      final seed = AppDatabase(factory: databaseFactoryFfi, path: file!);
      final household = await seedHousehold(AgroRepository(seed));
      await household.buy(household.titular, 5000);
      await seed.close();
      await downgradeToV7(file);
    });
    return openDb(file!);
  }

  testWidgets(
    'base histórica sin vincular: abre el Dashboard, opera y no se atribuye a nadie',
    (tester) async {
      final database = await legacyDatabaseWithData(tester);
      final c = await pumpApp(
        tester,
        database,
        session: ExistingSessionStartupState.noLocalSession,
      );
      expect(
        c.read(installationAccessProvider),
        InstallationAccessState.legacyUnbound,
      );
      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(
        find.byKey(const Key('installation-access-notice')),
        findsOneWidget,
      );
      // Sin sesión legible no se ofrece elegir titular.
      expect(find.byKey(const Key('dashboard-choose-owner')), findsNothing);
      expect(await attemptWrite(tester, c), isNull);
      expect(
        await tester.runAsync(
          () async => (await database.database).query('owner_bindings'),
        ),
        isEmpty,
      );
    },
  );

  testWidgets(
    'base histórica + sesión legible: el titular se elige explícitamente, sin cambiar roles',
    (tester) async {
      final database = await legacyDatabaseWithData(tester);
      final rolesBefore = await tester.runAsync(
        () async => (await database.database).query(
          'persons',
          columns: ['id', 'name', 'role'],
          orderBy: 'id',
        ),
      );
      final c = await pumpApp(
        tester,
        database,
        session: ExistingSessionStartupState.localSessionAvailable,
        scope: memberA,
      );
      expect(
        c.read(installationAccessProvider),
        InstallationAccessState.legacyUnbound,
      );
      // Nada se vincula solo a la cuenta que inició sesión.
      expect(
        await tester.runAsync(
          () async => (await database.database).query('owner_bindings'),
        ),
        isEmpty,
      );
      await tester.ensureVisible(
        find.byKey(const Key('dashboard-choose-owner')),
      );
      await tester.tap(find.byKey(const Key('dashboard-choose-owner')));
      await settle(tester);
      final titular = rolesBefore!.firstWhere((r) => r['name'] == 'Titular');
      final candidate = find.byKey(Key('owner-candidate-${titular['id']}'));
      await tester.ensureVisible(candidate);
      await tester.tap(candidate);
      await settle(tester);
      await tester.ensureVisible(find.byKey(const Key('owner-confirm')));
      await tester.tap(find.byKey(const Key('owner-confirm')));
      await waitFor(tester, find.byType(DashboardScreen));
      await settle(tester);

      expect(
        c.read(installationAccessProvider),
        InstallationAccessState.activated,
      );
      final binding = await tester.runAsync(
        () => OwnerBindingStore(database).activeBinding(),
      );
      expect(binding!.personId, titular['id']);
      expect(binding.scope, memberA);
      expect(
        await tester.runAsync(
          () async => (await database.database).query(
            'persons',
            columns: ['id', 'name', 'role'],
            orderBy: 'id',
          ),
        ),
        rolesBefore,
      );
    },
  );

  testWidgets(
    'instalación activada con sesión ilegible: abre el Dashboard y conserva la operación',
    (tester) async {
      final database = openDb(inMemoryDatabasePath);
      await tester.runAsync(() => seedActivatedInstallation(database));
      final c = await pumpApp(
        tester,
        database,
        session: ExistingSessionStartupState.corrupt,
      );
      expect(
        c.read(installationAccessProvider),
        InstallationAccessState.activatedSessionUnavailable,
      );
      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('installation-access-notice')))
            .data,
        InstallationAccessState.activatedSessionUnavailable.message,
      );
      expect(await attemptWrite(tester, c), isNull);
    },
  );

  testWidgets(
    'instalación activada, reapertura sin red con sesión expirada: opera sin cambios',
    (tester) async {
      final database = openDb(inMemoryDatabasePath);
      await tester.runAsync(() => seedActivatedInstallation(database));
      final before = await tester.runAsync(
        () async => dumpTables(await database.database),
      );
      final c = await pumpApp(
        tester,
        database,
        session: ExistingSessionStartupState.localSessionExpired,
        scope: memberA,
      );
      expect(
        c.read(installationAccessProvider),
        InstallationAccessState.activated,
      );
      expect(find.byType(DashboardScreen), findsOneWidget);
      // Abrir no escribe nada en SQLite.
      expect(
        await tester.runAsync(() async => dumpTables(await database.database)),
        before,
      );
    },
  );

  testWidgets(
    'base restaurada de otra instalación: no se habilita sin reactivar y no cambia nada',
    (tester) async {
      final database = openDb(inMemoryDatabasePath);
      await tester.runAsync(
        () => seedActivatedInstallation(
          database,
          installationRef: installationElsewhere,
        ),
      );
      final before = await tester.runAsync(
        () async => dumpTables(await database.database),
      );
      final c = await pumpApp(
        tester,
        database,
        session: ExistingSessionStartupState.noLocalSession,
      );
      expect(
        c.read(installationAccessProvider),
        InstallationAccessState.restoredRequiresActivation,
      );
      expect(path(c), '/acceso');
      // F03 §2: with a bound titular the entry is «Recuperar acceso», which
      // requires the same Member and tenant; no free activation is offered.
      expect(find.byKey(const Key('access-activate')), findsNothing);
      expect(find.byKey(const Key('access-recover')), findsOneWidget);
      expect(
        await attemptWrite(tester, c),
        isA<FarmerOperationBlockedException>(),
      );
      expect(
        await tester.runAsync(() async => dumpTables(await database.database)),
        before,
      );
    },
  );

  testWidgets(
    'sesión de otro Member: no se habilitan ni se adoptan los datos',
    (tester) async {
      final database = openDb(inMemoryDatabasePath);
      await tester.runAsync(() => seedActivatedInstallation(database));
      final before = await tester.runAsync(
        () async => dumpTables(await database.database),
      );
      final c = await pumpApp(
        tester,
        database,
        session: ExistingSessionStartupState.localSessionAvailable,
        scope: memberB,
      );
      expect(
        c.read(installationAccessProvider),
        InstallationAccessState.identityMismatch,
      );
      expect(path(c), '/acceso');
      expect(find.byKey(const Key('access-choose-owner')), findsNothing);
      expect(find.byKey(const Key('access-needs-review')), findsOneWidget);
      expect(
        await attemptWrite(tester, c),
        isA<FarmerOperationBlockedException>(),
      );
      expect(
        await tester.runAsync(() async => dumpTables(await database.database)),
        before,
      );
    },
  );

  testWidgets(
    'base nueva con sesión dañada: no se trata como nueva ni se borra nada',
    (tester) async {
      final database = openDb(inMemoryDatabasePath);
      final before = await tester.runAsync(
        () async => dumpTables(await database.database),
      );
      final c = await pumpApp(
        tester,
        database,
        session: ExistingSessionStartupState.corrupt,
      );
      expect(
        c.read(installationAccessProvider),
        InstallationAccessState.sessionDamagedNotActivated,
      );
      expect(path(c), '/acceso');
      // La activación no se ofrece sobre una sesión ilegible (no se sobrescribe).
      expect(find.byKey(const Key('access-activate')), findsNothing);
      expect(find.byKey(const Key('access-needs-review')), findsOneWidget);
      expect(
        await attemptWrite(tester, c),
        isA<FarmerOperationBlockedException>(),
      );
      expect(
        await tester.runAsync(() async => dumpTables(await database.database)),
        before,
      );
    },
  );

  testWidgets(
    'mientras se evalúa el estado, el repositorio de la app falla cerrado',
    (tester) async {
      final database = openDb(inMemoryDatabasePath);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(database),
          installationAccessProvider.overrideWith(_NeverEvaluated.new),
        ],
      );
      addTearDown(container.dispose);
      final repository = container.read(repositoryProvider);
      final error = await tester.runAsync<Object?>(() async {
        try {
          await repository.addProduct(name: 'X');
          return null;
        } on Object catch (e) {
          return e;
        }
      });
      expect(
        error,
        isA<FarmerOperationBlockedException>().having(
          (e) => e.state,
          'estado',
          isNull,
        ),
      );
    },
  );

  group('modo de uso', () {
    testWidgets(
      'con existencias de un tercero muestra el bloqueo y no cambia nada',
      (tester) async {
        final database = openDb(inMemoryDatabasePath);
        await tester.runAsync(() async {
          final repo = AgroRepository(database);
          final household = await seedHousehold(repo);
          await household.buy(household.thirdParty, 1000);
          await OwnerBindingStore(database).bindExistingPerson(
            personId: household.titular,
            scope: memberA,
            installationRef: installationHere,
          );
        });
        final before = await tester.runAsync(
          () async => dumpTables(await database.database),
        );
        final c = await pumpApp(
          tester,
          database,
          session: ExistingSessionStartupState.localSessionAvailable,
          scope: memberA,
        );
        c.read(routerProvider).go('/modo');
        await settle(tester);
        await waitFor(tester, find.byKey(const Key('mode-change')));
        await tester.tap(find.byKey(const Key('mode-change')));
        await waitFor(tester, find.byKey(const Key('mode-blocked')));
        expect(find.byKey(const Key('mode-blocked')), findsOneWidget);
        expect(find.byKey(const Key('mode-confirm')), findsNothing);
        expect(
          await tester.runAsync(
            () async => dumpTables(await database.database),
          ),
          before,
        );
      },
    );

    testWidgets(
      'sin datos activos de terceros pide confirmación y pasa a propio',
      (tester) async {
        final database = openDb(inMemoryDatabasePath);
        await tester.runAsync(() async {
          final repo = AgroRepository(database);
          final household = await seedHousehold(repo);
          await household.buy(household.titular, 1000);
          await OwnerBindingStore(database).bindExistingPerson(
            personId: household.titular,
            scope: memberA,
            installationRef: installationHere,
          );
        });
        final business = await tester.runAsync(
          () async =>
              dumpTables(await database.database, except: {'app_settings'}),
        );
        final c = await pumpApp(
          tester,
          database,
          session: ExistingSessionStartupState.localSessionAvailable,
          scope: memberA,
        );
        c.read(routerProvider).go('/modo');
        await settle(tester);
        await waitFor(tester, find.byKey(const Key('mode-change')));
        await tester.tap(find.byKey(const Key('mode-change')));
        await waitFor(tester, find.byKey(const Key('mode-confirm')));
        expect(find.byKey(const Key('mode-consequence')), findsOneWidget);
        await tester.tap(find.byKey(const Key('mode-confirm')));
        await waitFor(tester, find.text('Modalidad actual: inventario propio'));
        expect(
          await tester.runAsync(() => OperationModeStore(database).current()),
          OperationMode.personal,
        );
        expect(
          await tester.runAsync(
            () async =>
                dumpTables(await database.database, except: {'app_settings'}),
          ),
          business,
        );
      },
    );
  });

  group('accessRedirect', () {
    test('cargando: sólo rutas de acceso', () {
      expect(accessRedirect(null, '/'), '/acceso');
      expect(accessRedirect(null, '/compras/nueva'), '/acceso');
      expect(accessRedirect(null, '/activar'), isNull);
    });
    test('estados que operan: libre, y /acceso vuelve al inicio', () {
      for (final state in [
        InstallationAccessState.activated,
        InstallationAccessState.activatedSessionUnavailable,
        InstallationAccessState.legacyUnbound,
      ]) {
        expect(accessRedirect(state, '/transferencias/nueva'), isNull);
        expect(accessRedirect(state, '/acceso'), '/');
      }
      expect(
        accessRedirect(InstallationAccessState.legacyUnbound, '/titular'),
        isNull,
      );
    });
    test('activación sin titular: sólo /titular', () {
      const s = InstallationAccessState.activationPendingOwner;
      expect(accessRedirect(s, '/'), '/titular');
      expect(accessRedirect(s, '/acceso'), '/titular');
      expect(accessRedirect(s, '/titular'), isNull);
    });
    test('bloqueados: pantalla de acceso; /titular no se abre', () {
      for (final state in [
        InstallationAccessState.newRequiresActivation,
        InstallationAccessState.restoredRequiresActivation,
        InstallationAccessState.identityMismatch,
        InstallationAccessState.sessionDamagedNotActivated,
      ]) {
        expect(accessRedirect(state, '/compras/nueva'), '/acceso');
        expect(accessRedirect(state, '/titular'), '/acceso');
        expect(accessRedirect(state, '/activar'), isNull);
      }
    });
  });

  test('la app instala la compuerta real en el repositorio', () async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(database.close);
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(database)],
    );
    addTearDown(container.dispose);
    expect(container.read(repositoryProvider), isA<AgroRepository>());
    // Sin estado evaluado, la escritura falla cerrada (no está sin restricción).
    await expectLater(
      container
          .read(repositoryProvider)
          .addPerson(name: 'X', role: PersonRole.family),
      throwsA(isA<FarmerOperationBlockedException>()),
    );
  });
}

class _NeverEvaluated extends InstallationAccessController {
  @override
  InstallationAccessState? build() => null;

  @override
  Future<InstallationAccessState?> refresh({
    bool rereadSession = false,
  }) async => null;
}

class _ClearGuard implements RefreshGuard {
  @override
  Future<bool> isQuarantined() async => false;
  @override
  Future<void> quarantine() async {}
  @override
  Future<void> clear() async {}
}

class _IdleRemote extends RemoteSessionController {
  @override
  RemoteSessionState build() =>
      const RemoteSessionState(RemoteSessionPhase.idle);
}
