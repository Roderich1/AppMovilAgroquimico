// App real (base, router, repositorio, controlador de acceso): el titular
// histórico ADMIN en la interfaz y la restauración desde Liquidación. Sólo se
// sustituyen la sesión segura, la identidad y las carpetas de la plataforma.
import 'dart:io';

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/domain/installation_access.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/installation_access.dart';
import 'package:agroquimicos/operation_mode_controller.dart';
import 'package:agroquimicos/presentation/screens/dashboard_screen.dart';
import 'package:agroquimicos/presentation/widgets/adaptive_entity_picker.dart';
import 'package:agroquimicos/services/auth/existing_session_providers.dart';
import 'package:agroquimicos/services/auth/existing_session_startup.dart';
import 'package:agroquimicos/services/auth/refresh_guard.dart';
import 'package:agroquimicos/services/auth/remote_session_coordinator.dart';
import 'package:agroquimicos/services/auth/remote_session_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_app_access.dart';
import 'support/f04_mode_fixtures.dart';

class _WorkspacePaths extends PathProviderPlatform {
  _WorkspacePaths(this.directory);
  final String directory;
  @override
  Future<String?> getDownloadsPath() async => directory;
  @override
  Future<String?> getApplicationDocumentsPath() async => directory;
  @override
  Future<String?> getTemporaryPath() async => directory;
  @override
  Future<String?> getApplicationSupportPath() async => directory;
}

void main() {
  sqfliteFfiInit();

  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 150; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      if (finder.evaluate().isNotEmpty) return;
    }
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      if (i >= 8 && find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        break;
      }
    }
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<ProviderContainer> pumpApp(
    WidgetTester tester,
    AppDatabase database, {
    ExistingSessionStartupState session =
        ExistingSessionStartupState.localSessionAvailable,
    OwnerScope? scope = memberA,
  }) async {
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        existingSessionStartupProvider.overrideWithValue(session),
        ...startupAccessOverrides(sessionScope: scope),
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

  Future<List<Map<String, Object?>>> people(
    WidgetTester tester,
    AppDatabase database,
  ) async => (await tester.runAsync(
    () async => (await database.database).query('persons', orderBy: 'id'),
  ))!;

  /// Base v7 real con el agricultor registrado como ADMIN (paga), un hijo
  /// FAMILY y un vecino THIRD_PARTY; reabierta, queda histórica (v8).
  Future<AppDatabase> historicalAdminFarmer(
    WidgetTester tester, {
    bool withRelatives = true,
  }) async {
    final file = await tester.runAsync(() => tempDbPath('admin_ui'));
    await tester.runAsync(() async {
      final seed = AppDatabase(factory: databaseFactoryFfi, path: file!);
      final repo = AgroRepository(seed);
      final farmer = await repo.addPerson(
        name: 'Agricultor',
        role: PersonRole.admin,
      );
      final household = Household(
        repo,
        farmer,
        withRelatives
            ? await repo.addPerson(name: 'Hijo', role: PersonRole.family)
            : farmer,
        withRelatives
            ? await repo.addPerson(name: 'Vecino', role: PersonRole.thirdParty)
            : farmer,
      );
      household
        ..supplier = await repo.addSupplier(name: 'Proveedor')
        ..campaign = await repo.addCampaign(
          name: 'Campaña 1',
          start: DateTime.utc(2026, 1, 1),
        )
        ..product = await repo.addProduct(name: 'Glifosato');
      await repo.addFarm(
        ownerId: farmer,
        name: 'Chaco agricultor',
        areaM2: 10000,
      );
      await household.buy(farmer, 5000);
      await seed.close();
      await downgradeToV7(file);
    });
    return openDb(file!);
  }

  testWidgets(
    'base histórica con el agricultor ADMIN: se ofrece con su rol, exige confirmar y conserva persona y rol',
    (tester) async {
      // La casilla de confirmación alarga la pantalla del titular.
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final database = await historicalAdminFarmer(tester);
      final before = await people(tester, database);
      final farmer = before.firstWhere((r) => r['name'] == 'Agricultor');
      final son = before.firstWhere((r) => r['name'] == 'Hijo');
      final neighbor = before.firstWhere((r) => r['name'] == 'Vecino');
      final c = await pumpApp(tester, database);
      expect(
        c.read(installationAccessProvider),
        InstallationAccessState.legacyUnbound,
      );

      await tester.ensureVisible(
        find.byKey(const Key('dashboard-choose-owner')),
      );
      await tester.tap(find.byKey(const Key('dashboard-choose-owner')));
      await settle(tester);
      final farmerTile = find.byKey(Key('owner-candidate-${farmer['id']}'));
      expect(farmerTile, findsOneWidget);
      expect(find.byKey(Key('owner-candidate-${son['id']}')), findsOneWidget);
      expect(
        find.byKey(Key('owner-candidate-${neighbor['id']}')),
        findsNothing,
        reason: 'un tercero no se ofrece como titular',
      );
      expect(
        find.textContaining('Administrador de pagos (rol de estos registros'),
        findsOneWidget,
      );

      await tester.ensureVisible(farmerTile);
      await tester.tap(farmerTile);
      await settle(tester);
      final confirmAdmin = find.byKey(const Key('owner-confirm-administrator'));
      expect(confirmAdmin, findsOneWidget);
      // Sin la confirmación explícita no se vincula.
      await tester.ensureVisible(find.byKey(const Key('owner-confirm')));
      await tester.tap(find.byKey(const Key('owner-confirm')));
      await settle(tester);
      expect(
        find.textContaining('Confirme que es el agricultor titular'),
        findsOneWidget,
      );
      expect(
        await tester.runAsync(
          () => OwnerBindingStore(database).activeBinding(),
        ),
        isNull,
      );

      await tester.ensureVisible(confirmAdmin);
      await tester.tap(confirmAdmin);
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
      expect(binding!.personId, farmer['id']);
      expect(binding.ownerRole, PersonRole.admin);
      // Misma persona, mismo rol y política; nadie se duplicó.
      expect(await people(tester, database), before);
    },
  );

  testWidgets(
    'modo propio con titular ADMIN: el formulario de aplicación lo ofrece con su chaco',
    (tester) async {
      final database = await historicalAdminFarmer(
        tester,
        withRelatives: false,
      );
      await tester.runAsync(() async {
        final farmer =
            (await (await database.database).query('persons')).single['id']!
                as int;
        await OwnerBindingStore(database).bindExistingPerson(
          personId: farmer,
          scope: memberA,
          installationRef: installationHere,
          confirmAdministrator: true,
        );
        await OperationModeStore(database)
            .apply(OperationMode.personal, confirmed: true);
        // Otra persona sin datos: en modo propio no se ofrece.
        await AgroRepository(database)
            .addPerson(name: 'Esposa', role: PersonRole.family);
      });
      final c = await pumpApp(tester, database);
      expect(
        c.read(installationAccessProvider),
        InstallationAccessState.activated,
      );

      c.read(routerProvider).push('/aplicaciones/nueva');
      await waitFor(tester, find.text('Chaco agricultor'));
      await settle(tester);

      expect(tester.takeException(), isNull);
      // Sólo el titular y su chaco, seleccionados solos por ser únicos.
      expect(find.text('Agricultor'), findsWidgets);
      expect(find.text('Chaco agricultor'), findsOneWidget);
      expect(find.text('Esposa'), findsNothing);
    },
  );

  /// Ids de las opciones de un selector [AdaptiveEntityPicker] por etiqueta.
  Set<Object?> pickerIds(WidgetTester tester, String label) => {
    for (final item
        in tester
            .widget<AdaptiveEntityPicker<Map<String, Object?>>>(
              find.byWidgetPredicate(
                (w) =>
                    w is AdaptiveEntityPicker<Map<String, Object?>> &&
                    w.label == label,
              ),
            )
            .items)
      item['id'],
  };

  testWidgets(
    'compartido con titular ADMIN: la transferencia lo ofrece; otro ADMIN sigue fuera',
    (tester) async {
      final database = await historicalAdminFarmer(tester);
      final ids = await tester.runAsync(() async {
        final rows = await (await database.database).query('persons');
        int id(String name) =>
            rows.firstWhere((r) => r['name'] == name)['id']! as int;
        await OwnerBindingStore(database).bindExistingPerson(
          personId: id('Agricultor'),
          scope: memberA,
          installationRef: installationHere,
          confirmAdministrator: true,
        );
        final other = await AgroRepository(database)
            .addPerson(name: 'Contador', role: PersonRole.admin);
        return (
          farmer: id('Agricultor'),
          son: id('Hijo'),
          neighbor: id('Vecino'),
          other: other,
        );
      });
      final c = await pumpApp(tester, database);

      c.read(routerProvider).push('/transferencias/nueva');
      await waitFor(tester, find.text('Persona origen'));
      await settle(tester);

      expect(pickerIds(tester, 'Persona origen'), {
        ids!.farmer,
        ids.son,
        ids.neighbor,
      });
      expect(pickerIds(tester, 'Persona origen'), isNot(contains(ids.other)));
    },
  );

  testWidgets(
    'propio con titular familiar: el titular paga al proveedor en el formulario y en Compras',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final file = await tester.runAsync(() => tempDbPath('propio'));
      final database = openDb(file!);
      final ids = await tester.runAsync(() async {
        final binding = await seedActivatedInstallation(database);
        final repo = AgroRepository(database);
        final household =
            Household(
                repo,
                binding.personId,
                binding.personId,
                binding.personId,
              )
              ..supplier = await repo.addSupplier(name: 'Proveedor')
              ..campaign = await repo.addCampaign(
                name: 'Campaña 1',
                start: DateTime.utc(2026, 1, 1),
              )
              ..product = await repo.addProduct(name: 'Glifosato');
        await household.buy(binding.personId, 1000);
        await OperationModeStore(database)
            .apply(OperationMode.personal, confirmed: true);
        // Un administrador de pagos sin datos: en modo propio no paga.
        final payer = await repo.addPerson(
          name: 'Paga',
          role: PersonRole.admin,
        );
        return (titular: binding.personId, payer: payer);
      });
      final c = await pumpApp(tester, database);

      c.read(routerProvider).go('/compras');
      await waitFor(tester, find.byType(PopupMenuButton<String>));
      await settle(tester);
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await settle(tester);
      await tester.tap(find.text('Registrar pago'));
      // #26: en propio paga el titular sin elegirlo. Antes se comprobaba que
      // el selector sólo ofreciera al titular; ahora no hay selector y el
      // pago queda a su nombre, nunca al del otro administrador.
      await waitFor(tester, find.byKey(const Key('payment-personal-payer')));
      expect(find.byType(DropdownButton<int>), findsNothing);
      expect(find.text('Paga el titular: Titular'), findsOneWidget);
      expect(find.textContaining('Paga '), findsOneWidget);
      await tester.tap(find.text('Registrar'));
      await settle(tester);
      expect(
        await tester.runAsync(
          () async => (await database.database).query(
            'provider_payments',
            columns: ['payer_person_id'],
          ),
        ),
        [
          {'payer_person_id': ids!.titular},
        ],
      );

      c.read(routerProvider).push('/compras/nueva');
      await waitFor(tester, find.text('Registrar pago total ahora'));
      await settle(tester);
      await tester.ensureVisible(find.text('Registrar pago total ahora'));
      await tester.tap(find.text('Registrar pago total ahora'));
      await settle(tester);
      expect(find.text('Pagador'), findsNothing);
      expect(find.byKey(const Key('purchase-personal-payer')), findsOneWidget);
      expect(find.text('Paga el titular: Titular'), findsOneWidget);
      expect(ids.payer, isNot(ids.titular));
    },
  );

  group('restaurar desde Liquidación', () {
    late Directory workspace;

    setUp(() async {
      workspace = await Directory.systemTemp.createTemp('agro_f04_ui_');
      await Directory(p.join(workspace.path, 'invoices')).create();
      PathProviderPlatform.instance = _WorkspacePaths(workspace.path);
    });
    tearDown(() async {
      try {
        await workspace.delete(recursive: true);
      } on FileSystemException {
        // En Windows el motor puede retener un archivo; es temporal.
      }
    });

    /// Respaldo `.db` de otra base vinculada a [scope] en otra instalación.
    Future<void> backupBoundTo(
      WidgetTester tester,
      String name,
      OwnerScope scope,
    ) async {
      await tester.runAsync(() async {
        final path = p.join(workspace.path, '$name.db');
        final source = AppDatabase(factory: databaseFactoryFfi, path: path);
        await AgroRepository(source).addProduct(name: 'Del respaldo');
        await seedActivatedInstallation(
          source,
          scope: scope,
          installationRef: installationElsewhere,
        );
        await source.close();
        await File(path)
            .copy(p.join(workspace.path, 'agroquimicos_backup_$name.db'));
      });
    }

    Future<AppDatabase> currentOfA(WidgetTester tester) async {
      final file = await tester.runAsync(() => tempDbPath('actual'));
      final database = openDb(file!);
      await tester.runAsync(() async {
        await seedActivatedInstallation(database);
        await AgroRepository(database).addProduct(name: 'Actual');
      });
      return database;
    }

    Future<void> chooseBackup(
      WidgetTester tester,
      ProviderContainer c,
      String name,
    ) async {
      c.read(routerProvider).go('/liquidacion');
      await settle(tester);
      await tester.tap(find.byTooltip('Copias de seguridad'));
      await settle(tester);
      await tester.tap(find.text('Restaurar respaldo'));
      await waitFor(tester, find.text('agroquimicos_backup_$name.db'));
      await tester.tap(find.text('agroquimicos_backup_$name.db'));
    }

    testWidgets(
      'una copia de otro Member se rechaza sin pedir confirmación y sin tocar nada',
      (tester) async {
        final database = await currentOfA(tester);
        await backupBoundTo(tester, 'b', memberB);
        final before = await tester.runAsync(
          () async => dumpTables(await database.database),
        );
        final c = await pumpApp(tester, database);
        expect(
          c.read(installationAccessProvider),
          InstallationAccessState.activated,
        );

        await chooseBackup(tester, c, 'b');
        await waitFor(tester, find.textContaining('pertenece a otro titular'));

        expect(find.textContaining('pertenece a otro titular'), findsOneWidget);
        expect(find.text('¿Restaurar este respaldo?'), findsNothing);
        expect(
          await tester.runAsync(
            () async => dumpTables(await database.database),
          ),
          before,
        );
        expect(
          c.read(installationAccessProvider),
          InstallationAccessState.activated,
        );
      },
    );

    testWidgets(
      'una copia del mismo Member avisa, restaura y recalcula la autorización',
      (tester) async {
        final database = await currentOfA(tester);
        await backupBoundTo(tester, 'a', memberA);
        final c = await pumpApp(tester, database);

        await chooseBackup(tester, c, 'a');
        await waitFor(tester, find.text('¿Restaurar este respaldo?'));
        expect(
          find.textContaining('corresponde al titular de esta instalación'),
          findsOneWidget,
        );
        await tester.tap(find.text('Restaurar'));
        await waitFor(tester, find.textContaining('Respaldo restaurado'));

        expect(find.textContaining('Respaldo restaurado'), findsOneWidget);
        expect(
          c.read(installationAccessProvider),
          InstallationAccessState.activated,
        );
        final names = await tester.runAsync(
          () async => {
            for (final row in await AgroRepository(database).products())
              row['name'],
          },
        );
        expect(names, contains('Del respaldo'));
        expect(names, isNot(contains('Actual')));
      },
    );

    testWidgets(
      'una copia del mismo Member en inventario propio deja la navegación en propio sin reiniciar (#26)',
      (tester) async {
        final database = await currentOfA(tester);
        await tester.runAsync(() async {
          final path = p.join(workspace.path, 'propio.db');
          final source = AppDatabase(factory: databaseFactoryFfi, path: path);
          await seedActivatedInstallation(
            source,
            installationRef: installationElsewhere,
          );
          await OperationModeStore(source)
              .apply(OperationMode.personal, confirmed: true);
          await source.close();
          await File(path)
              .copy(p.join(workspace.path, 'agroquimicos_backup_propio.db'));
        });
        final c = await pumpApp(tester, database);
        expect(c.read(operationModeProvider), OperationMode.shared);

        await chooseBackup(tester, c, 'propio');
        await waitFor(tester, find.text('¿Restaurar este respaldo?'));
        await tester.tap(find.text('Restaurar'));
        await waitFor(tester, find.textContaining('Respaldo restaurado'));
        await settle(tester);

        expect(c.read(operationModeProvider), OperationMode.personal);
        c.read(routerProvider).go('/operaciones');
        await settle(tester);
        expect(find.text('Transferencias'), findsNothing);
        expect(find.text('Ahora: inventario propio'), findsOneWidget);
      },
    );
  });
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
