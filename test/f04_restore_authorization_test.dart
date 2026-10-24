// Restaurar un respaldo y la política de activación (RU-11, RF-01; #76).
//
// Recorrido real: base en archivo, BackupService real, controlador de acceso
// real (no un estado fijo), GuardedRestore y los proveedores de la app. Sólo
// se sustituyen la sesión segura (estado y ámbito) y la identidad de
// instalación.
//
// Reproducido sobre abfcd26: tras restaurar la copia de otro Member, el
// estado seguía `activated` (reclasificado daba `identityMismatch`) y la
// compuerta dejaba escribir sobre los datos de B con la autorización de A.
import 'dart:async';
import 'dart:io';

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/backup_service.dart';
import 'package:agroquimicos/data/database_replacement.dart';
import 'package:agroquimicos/data/farmer_operation_gate.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/data/sync/central_binding_store.dart';
import 'package:agroquimicos/data/sync/declared_need_store.dart';
import 'package:agroquimicos/data/sync/sync_outbox_store.dart';
import 'package:agroquimicos/domain/sync/sync_types.dart';
import 'package:agroquimicos/domain/installation_access.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/guarded_restore.dart';
import 'package:agroquimicos/installation_access.dart';
import 'package:agroquimicos/services/auth/existing_session_providers.dart';
import 'package:agroquimicos/services/auth/existing_session_startup.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_app_access.dart';
import 'support/f04_mode_fixtures.dart';
import 'support/f05_sync_fixtures.dart'
    show centralCampaign, centralProduct, inCampaign;

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

/// Una instalación de la app en un directorio propio.
class _Installation {
  _Installation(this.container, this.database, this.directory);
  final ProviderContainer container;
  final AppDatabase database;
  final Directory directory;

  AgroRepository get repo => container.read(repositoryProvider);
  InstallationAccessState? get access =>
      container.read(installationAccessProvider);
  GuardedRestore get guarded => container.read(guardedRestoreProvider);

  Future<Map<String, List<Map<String, Object?>>>> dump({
    Set<String> except = const {},
  }) async => dumpTables(await database.database, except: except);

  /// Copias de seguridad previas que deja una restauración.
  List<String> safetyCopies() => [
    for (final entity in directory.listSync(recursive: true))
      if (p.basename(entity.path).contains('.previo-')) entity.path,
  ];
}

void main() {
  sqfliteFfiInit();

  late Directory workspace;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('agro_f04_restore_');
    PathProviderPlatform.instance = _WorkspacePaths(workspace.path);
    await Directory(p.join(workspace.path, 'invoices')).create();
  });
  tearDown(() async {
    try {
      await workspace.delete(recursive: true);
    } on FileSystemException {
      // En Windows el motor puede retener un archivo; es temporal.
    }
  });

  Future<_Installation> install(
    String name, {
    Future<void> Function(AppDatabase database)? seed,
    ExistingSessionStartupState startup =
        ExistingSessionStartupState.localSessionAvailable,
    OwnerScope? session = memberA,
  }) async {
    final directory = await Directory(p.join(workspace.path, name))
        .create(recursive: true);
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      path: p.join(directory.path, 'agro.db'),
    );
    addTearDown(database.close);
    if (seed != null) await seed(database);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        existingSessionStartupProvider.overrideWithValue(startup),
        ...startupAccessOverrides(sessionScope: session),
      ],
    );
    addTearDown(container.dispose);
    await container.read(installationAccessProvider.notifier).refresh();
    return _Installation(container, database, directory);
  }

  /// Base de otra instalación, cerrada y copiada como respaldo `.db`.
  /// Devuelve la ruta del respaldo y su contenido completo.
  Future<(String, Map<String, List<Map<String, Object?>>>)> backupOf(
    String name,
    Future<void> Function(AppDatabase database) seed,
  ) async {
    final path = p.join(workspace.path, '$name.db');
    final database = AppDatabase(factory: databaseFactoryFfi, path: path);
    await seed(database);
    final contents = await dumpTables(await database.database);
    await database.close();
    final backup = p.join(workspace.path, 'agroquimicos_backup_$name.db');
    await File(path).copy(backup);
    return (backup, contents);
  }

  Future<void> boundTo(
    AppDatabase database,
    OwnerScope scope, {
    String? installationRef,
    String product = 'Glifosato',
  }) async {
    final household = await seedHousehold(AgroRepository(database));
    await household.repo.addProduct(name: product);
    await household.buy(household.titular, 3000);
    await OwnerBindingStore(database).bindExistingPerson(
      personId: household.titular,
      scope: scope,
      installationRef: installationRef ?? installationHere,
    );
  }

  Future<Set<Object?>> productNames(_Installation app) async => {
    for (final row in await app.repo.products()) row['name'],
  };

  group('propiedad de la copia', () {
    test('misma cuenta: restaura, recalcula y vuelve a operar sobre la base restaurada', () async {
      final app = await install(
        'a',
        seed: (db) => boundTo(db, memberA, product: 'Actual'),
      );
      expect(app.access, InstallationAccessState.activated);
      final previous = await app.dump();
      final (backup, contents) = await backupOf(
        'a_otro_telefono',
        (db) => boundTo(
          db,
          memberA,
          installationRef: installationElsewhere,
          product: 'Respaldo',
        ),
      );

      final preview = await app.guarded.preview(backup);
      expect(preview.accepted, isTrue);
      final outcome = await app.guarded.restore(backup);

      expect(outcome.access, InstallationAccessState.activated);
      expect(app.access, InstallationAccessState.activated);
      // Contenido del respaldo, fila por fila, incluido el vínculo: nada se
      // reasigna. Sólo se registra esta instalación (reactivación de A).
      expect(await app.dump(except: {'app_settings'}), {
        for (final entry in contents.entries)
          if (entry.key != 'app_settings') entry.key: entry.value,
      });
      expect(
        (await settings(
          await app.database.database,
        ))[AppDatabase.activatedInstallationKey],
        installationHere,
      );
      // La copia previa conserva lo que había.
      final safety = AppDatabase(
        factory: databaseFactoryFfi,
        path: outcome.result.safetyCopyPath,
      );
      addTearDown(safety.close);
      expect(await dumpTables(await safety.database), previous);
      // Y se opera sobre la base restaurada.
      await app.repo.addProduct(name: 'Nueva');
      expect(await productNames(app), containsAll(['Respaldo', 'Nueva']));
      expect(await productNames(app), isNot(contains('Actual')));
    });

    for (final (label, other) in [
      ('otro Member', memberB),
      ('otro tenant', memberAOtherTenant),
    ]) {
      test(
        '$label: se rechaza antes de reemplazar y se conservan base y autorización',
        () async {
          final app = await install('a', seed: (db) => boundTo(db, memberA));
          final before = await app.dump();
          final (backup, _) = await backupOf(
            'ajena',
            (db) => boundTo(db, other, installationRef: installationElsewhere),
          );

          final preview = await app.guarded.preview(backup);
          expect(preview.rejection, RestoreRejection.otherOwner);
          await expectLater(
            app.guarded.restore(backup),
            throwsA(
              isA<BackupOwnershipRejectedException>().having(
                (e) => e.rejection,
                'motivo',
                RestoreRejection.otherOwner,
              ),
            ),
          );

          expect(await app.dump(), before);
          expect(app.safetyCopies(), isEmpty, reason: 'no se tocó nada');
          expect(app.access, InstallationAccessState.activated);
          await app.repo.addProduct(name: 'Sigue operando');
        },
      );
    }

    test(
      'base actual sin vínculo y sesión de B: la copia de A se rechaza',
      () async {
        final app = await install(
          'historica',
          seed: (db) async {
            await seedHousehold(AgroRepository(db));
            await db.close();
            await downgradeToV7(p.join(workspace.path, 'historica', 'agro.db'));
          },
          session: memberB,
        );
        expect(app.access, InstallationAccessState.legacyUnbound);
        final before = await app.dump();
        final (backup, _) = await backupOf(
          'de_a',
          (db) => boundTo(db, memberA, installationRef: installationElsewhere),
        );

        await expectLater(
          app.guarded.restore(backup),
          throwsA(isA<BackupOwnershipRejectedException>()),
        );
        expect(await app.dump(), before);
        expect(app.access, InstallationAccessState.legacyUnbound);
      },
    );

    test(
      'propiedad ilegible: no se restaura y la base actual queda igual',
      () async {
        final app = await install('a', seed: (db) => boundTo(db, memberA));
        final before = await app.dump();
        final (backup, _) = await backupOf('sin_vinculos', (db) async {
          await boundTo(db, memberA);
          await (await db.database).execute(
            'ALTER TABLE owner_bindings RENAME TO owner_bindings_otra',
          );
        });

        await expectLater(
          app.guarded.preview(backup),
          throwsA(isA<BackupOwnershipException>()),
        );
        await expectLater(
          app.guarded.restore(backup),
          throwsA(isA<BackupOwnershipException>()),
        );
        expect(await app.dump(), before);
        expect(app.safetyCopies(), isEmpty);
        expect(app.access, InstallationAccessState.activated);
      },
    );

    test(
      'copia histórica sin vínculo: se restaura como histórica, sin titular',
      () async {
        final app = await install('a', seed: (db) => boundTo(db, memberA));
        final (backup, _) = await backupOf('v7', (db) async {
          await seedHousehold(AgroRepository(db));
          await db.close();
          await downgradeToV7(p.join(workspace.path, 'v7.db'));
        });

        final preview = await app.guarded.preview(backup);
        expect(preview.predicted, InstallationAccessState.legacyUnbound);
        final outcome = await app.guarded.restore(backup);

        expect(outcome.access, InstallationAccessState.legacyUnbound);
        final db = await app.database.database;
        expect(await db.query('owner_bindings'), isEmpty);
        expect(
          (await settings(db))[AppDatabase.installOriginKey],
          AppDatabase.installOriginLegacy,
        );
        expect(
          (await settings(db))[AppDatabase.activatedInstallationKey],
          isNull,
        );
      },
    );

    test('copia de A activada en otra instalación y sin sesión legible: exige reactivar', () async {
      final app = await install(
        'a',
        seed: (db) => boundTo(db, memberA),
        startup: ExistingSessionStartupState.noLocalSession,
        session: null,
      );
      expect(app.access, InstallationAccessState.activatedSessionUnavailable);
      final (backup, contents) = await backupOf(
        'a_otro_telefono',
        (db) => boundTo(db, memberA, installationRef: installationElsewhere),
      );

      final outcome = await app.guarded.restore(backup);

      expect(
        outcome.access,
        InstallationAccessState.restoredRequiresActivation,
      );
      // Restaurar no demuestra identidad: ni se registra esta instalación
      // ni se toca el vínculo.
      expect(await app.dump(), contents);
      await expectLater(
        app.repo.addProduct(name: 'X'),
        throwsA(isA<FarmerOperationBlockedException>()),
      );
    });

    test('contenedor .agrobackup de la misma cuenta', () async {
      final source = AppDatabase(
        factory: databaseFactoryFfi,
        path: p.join(workspace.path, 'origen.db'),
      );
      addTearDown(source.close);
      await boundTo(source, memberA, product: 'Del contenedor');
      final exported = await BackupService(source).export();

      final app = await install('a', seed: (db) => boundTo(db, memberA));
      final outcome = await app.guarded.restore(exported.path);

      expect(outcome.result.format, BackupFormat.container);
      expect(outcome.access, InstallationAccessState.activated);
      expect(await productNames(app), contains('Del contenedor'));
    });
  });

  group('autorización durante y después de sustituir la base', () {
    test('si el recálculo falla, el estado queda null: no se conserva la autorización anterior', () async {
      final app = await install('a', seed: (db) => boundTo(db, memberA));
      final (backup, _) = await backupOf(
        'a2',
        (db) => boundTo(db, memberA, installationRef: installationElsewhere),
      );

      final outcome = await app.guarded.restore(
        backup,
        // Con la base ya sustituida, la comprobación de propiedad posterior
        // deja de poder leerse.
        afterReplace: () async => (await app.database.database).execute(
          'ALTER TABLE owner_bindings RENAME TO owner_bindings_x',
        ),
      );

      expect(outcome.access, isNull);
      expect(app.access, isNull);
      await expectLater(
        app.repo.addProduct(name: 'X'),
        throwsA(
          isA<FarmerOperationBlockedException>().having(
            (e) => e.state,
            'pendiente',
            isNull,
          ),
        ),
      );
      // Reparada la causa, reintentar habilita la base restaurada.
      await (await app.database.database).execute(
        'ALTER TABLE owner_bindings_x RENAME TO owner_bindings',
      );
      await app.container.read(installationAccessProvider.notifier).refresh();
      expect(app.access, InstallationAccessState.activated);
    });

    test('rollback: un fallo con la base ya sustituida devuelve la anterior y recalcula', () async {
      final app = await install(
        'a',
        seed: (db) => boundTo(db, memberA, product: 'Actual'),
      );
      final before = await app.dump();
      final (backup, _) = await backupOf(
        'a2',
        (db) => boundTo(db, memberA, product: 'Respaldo'),
      );

      await expectLater(
        app.guarded.restore(
          backup,
          afterReplace: () async => throw StateError('fallo simulado'),
        ),
        throwsA(isA<StateError>()),
      );

      expect(await app.dump(), before);
      expect(app.access, InstallationAccessState.activated);
      await app.repo.addProduct(name: 'Tras deshacer');
      expect(await productNames(app), containsAll(['Actual', 'Tras deshacer']));
    });

    test(
      'durante la sustitución ninguna escritura entra y las lecturas esperan',
      () async {
        final app = await install('a', seed: (db) => boundTo(db, memberA));
        final (backup, _) = await backupOf(
          'a2',
          (db) => boundTo(
            db,
            memberA,
            installationRef: installationElsewhere,
            product: 'Respaldo',
          ),
        );
        // Zona de la prueba, capturada antes: fuera de la sustitución.
        final outside = Zone.current;
        final rejected = <String, Object?>{};
        late Future<Set<Object?>> pendingRead;

        await app.guarded.restore(
          backup,
          afterReplace: () async {
            // Desde fuera de la sustitución (como la interfaz).
            Future<void> attempt(
              String name,
              Future<Object?> Function() call,
            ) => outside.run(
              () => call().then(
                (_) => rejected[name] = null,
                onError: (Object e) => rejected[name] = e,
              ),
            );
            await attempt('addProduct', () => app.repo.addProduct(name: 'X'));
            await attempt(
              'modalidad',
              () =>
                  OperationModeStore(app.database)
                      .apply(OperationMode.personal, confirmed: true),
            );
            await attempt(
              'titular',
              () => OwnerBindingStore(app.database).bindNewPerson(
                name: 'Y',
                scope: memberA,
                installationRef: installationHere,
              ),
            );
            await attempt(
              'factura',
              () => app.repo.storeInvoiceImage('no-existe.jpg'),
            );
            pendingRead = outside.run(() => productNames(app));
          },
        );

        expect(rejected.keys, {
          'addProduct',
          'modalidad',
          'titular',
          'factura',
        });
        for (final entry in rejected.entries) {
          expect(
            entry.value,
            isA<DatabaseReplacementInProgressException>(),
            reason: entry.key,
          );
        }
        // La lectura esperó y vio la base restaurada.
        expect(await pendingRead, contains('Respaldo'));
        expect(await productNames(app), isNot(contains('X')));
        expect(
          await OperationModeStore(app.database).current(),
          OperationMode.shared,
        );
      },
    );

    test(
      'BackupService.restore también es exclusivo sin GuardedRestore',
      () async {
        final app = await install('a', seed: (db) => boundTo(db, memberA));
        final (backup, _) = await backupOf(
          'a2',
          (db) => boundTo(db, memberA, installationRef: installationElsewhere),
        );
        final outside = Zone.current;
        Object? rejected;

        await BackupService(app.database).restore(
          backup,
          afterReplace: () => outside.run(
            () => app.repo
                .addProduct(name: 'X')
                .then<void>(
                  (_) {},
                  onError: (Object e) {
                    rejected = e;
                  },
                ),
          ),
        );

        expect(rejected, isA<DatabaseReplacementInProgressException>());
        expect(await productNames(app), isNot(contains('X')));
      },
    );

    test('una escritura en curso termina antes de sustituir y queda en la copia previa', () async {
      final app = await install('a', seed: (db) => boundTo(db, memberA));
      final (backup, contents) = await backupOf(
        'a2',
        (db) => boundTo(db, memberA, installationRef: installationElsewhere),
      );

      final inFlight = app.repo.addProduct(name: 'En curso');
      final outcome = await app.guarded.restore(backup);
      final inFlightId = await inFlight;

      final safety = AppDatabase(
        factory: databaseFactoryFfi,
        path: outcome.result.safetyCopyPath,
      );
      addTearDown(safety.close);
      final previousProducts = await (await safety.database).query(
        'products',
        where: 'id=?',
        whereArgs: [inFlightId],
      );
      expect(previousProducts.single['name'], 'En curso');
      expect(await app.dump(except: {'app_settings'}), {
        for (final entry in contents.entries)
          if (entry.key != 'app_settings') entry.key: entry.value,
      });
    });
  });

  group('sincronización F05 y restauración', () {
    test('restaurar no publica: las intenciones por enviar de la copia quedan pausadas', () async {
      final app = await install('a', seed: (db) => boundTo(db, memberA));
      final (backup, contents) = await backupOf('a_con_cola', (db) async {
        await boundTo(db, memberA, installationRef: installationElsewhere);
        final repo = AgroRepository(db);
        // La campaña del hogar sembrado cubre la fecha de referencia.
        final campaign = (await repo.activeCampaign())!['id']! as int;
        final product = await repo.addProduct(name: 'Herbicida', unit: 'L');
        final second = await repo.addProduct(name: 'Fungicida', unit: 'KG');
        final bindings = CentralBindingStore(db);
        // D-F04-C2: la campaña central tiene que contener a «Campaña 1»
        // (desde el 01/01/2026 UTC, día local anterior en La Paz).
        await bindings.bindCampaign(
          campaignId: campaign,
          central: centralCampaign(startDate: '2025-01-01T00:00:00.000Z'),
          tenantId: memberA.tenantId,
        );
        await bindings.bindProduct(
          productId: product,
          central: centralProduct(),
          tenantId: memberA.tenantId,
        );
        await bindings.bindProduct(
          productId: second,
          central: centralProduct(
            ref: '3a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d',
            unit: 'KG',
          ),
          tenantId: memberA.tenantId,
        );
        final needs = DeclaredNeedStore(db);
        final outbox = SyncOutboxStore(db);
        await needs.declare(
          referenceDate: inCampaign,
          productId: product,
          quantityBase: 1000,
        );
        // Una ya aceptada y otra que salió sin respuesta.
        final accepted = await outbox.markSending(
          (await outbox.entries()).single,
        );
        await outbox.recordAccepted(accepted, '2026-10-15T12:00:00.000Z');
        await needs.declare(
          referenceDate: inCampaign,
          productId: second,
          quantityBase: 500,
        );
        await outbox.markSending(
          (await outbox.entries()).firstWhere((e) => e.attempts == 0),
        );
      });

      await app.guarded.restore(backup);

      final restored = await SyncOutboxStore(app.database).entries();
      expect(restored, hasLength(2));
      final byStatus = {for (final e in restored) e.status: e};
      expect(byStatus.keys.toSet(), {
        OutboxStatus.acked,
        OutboxStatus.restorePaused,
      });
      // El resto de la copia llega tal cual.
      expect(await app.dump(except: {'app_settings', 'sync_outbox'}), {
        for (final entry in contents.entries)
          if (entry.key != 'app_settings' && entry.key != 'sync_outbox')
            entry.key: entry.value,
      });
      // Liberar las devuelve a la cola con el mismo contenido.
      final binding = await OwnerBindingStore(app.database).activeBinding();
      expect(
        await SyncOutboxStore(app.database).releaseRestored(binding!.id),
        1,
      );
      final released = (await SyncOutboxStore(
        app.database,
      ).entries()).firstWhere((e) => e.status != OutboxStatus.acked);
      expect(released.status, OutboxStatus.outcomeUnknown);
      expect(released.attempts, 1);
    });
  });
}
