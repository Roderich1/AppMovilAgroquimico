// Copia de seguridad previa a restaurar con SQLite en WAL (F10, #36 y #40).
//
// En modo WAL las últimas transacciones confirmadas viven en `-wal`, no en el
// archivo principal, hasta el siguiente checkpoint. Sobre `4f203c7` la copia
// `.previo` se tomaba copiando sólo el archivo principal **antes** de cerrar la
// base: si la restauración fallaba después de empezar la sustitución, el
// rollback devolvía esa copia y la transacción reciente se perdía.
//
// Recorrido real: base en archivo con `sqflite_common_ffi`, BackupService
// real, GuardedRestore, controlador de acceso real y contenedor `.agrobackup`
// con fotografías. El WAL se controla con `wal_autocheckpoint=0`: así la
// precondición («la transacción reciente sólo está en el WAL») se comprueba
// en vez de suponerse.
import 'dart:convert';
import 'dart:io';

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/backup_service.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/domain/installation_access.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/guarded_restore.dart';
import 'package:agroquimicos/installation_access.dart';
import 'package:agroquimicos/services/auth/existing_session_providers.dart';
import 'package:agroquimicos/services/auth/existing_session_startup.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'backup_container_support.dart';
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

typedef _Dump = Map<String, List<Map<String, Object?>>>;

void main() {
  sqfliteFfiInit();

  late Directory workspace;
  late Directory invoices;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('agro_f10_wal_');
    PathProviderPlatform.instance = _WorkspacePaths(workspace.path);
    // Carpeta de facturas de la instalación (resolveInvoicesDirectory).
    invoices = await Directory(p.join(workspace.path, 'invoices')).create();
  });
  tearDown(() async {
    try {
      await workspace.delete(recursive: true);
    } on FileSystemException {
      // En Windows el motor puede retener un archivo; es temporal.
    }
  });

  List<int> photo(String seed) => List<int>.generate(
    2048,
    (i) => (i * 31 + seed.codeUnits.fold<int>(0, (a, b) => a + b)) % 256,
  );

  /// Compra confirmada con su fotografía de factura en [folder].
  Future<int> buyWithPhoto(
    Household household,
    Directory folder,
    String photoName,
    String invoiceNumber,
  ) async {
    final file = File(p.join(folder.path, photoName));
    await file.writeAsBytes(photo('$photoName@${folder.path}'), flush: true);
    return household.repo.confirmPurchase(
      PurchaseDraft(
        supplierId: household.supplier,
        campaignId: household.campaign,
        purchaseDate: DateTime.utc(2026, 1, 5),
        invoiceNumber: invoiceNumber,
        invoiceImagePath: file.path,
        items: [
          PurchaseItemDraft(
            productId: household.product,
            quantityBase: 4000,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 12500,
            allocations: [
              AllocationDraft(personId: household.titular, quantityBase: 4000),
            ],
          ),
        ],
      ),
    );
  }

  /// Datos actuales del titular A con una compra fotografiada.
  Future<Household> seedCurrent(AppDatabase database) async {
    final household = await seedHousehold(AgroRepository(database));
    await household.repo.addProduct(name: 'Actual');
    await household.buy(household.titular, 3000);
    await buyWithPhoto(household, invoices, 'factura_comun.jpg', 'F-ACT-1');
    await OwnerBindingStore(database).bindExistingPerson(
      personId: household.titular,
      scope: memberA,
      installationRef: installationHere,
    );
    return household;
  }

  Map<String, String> photosIn(Directory folder) => {
    for (final entity in folder.listSync())
      if (entity is File)
        p.basename(entity.path): sha256
            .convert(entity.readAsBytesSync())
            .toString(),
  };

  Future<String> journalMode(AppDatabase database) async =>
      '${(await (await database.database).rawQuery('PRAGMA journal_mode')).single.values.single}'
          .toLowerCase();

  /// Pone la base en WAL sin checkpoint automático y consolida lo que haya:
  /// desde aquí, lo que se confirme queda sólo en `-wal`.
  Future<void> walWithoutAutocheckpoint(AppDatabase database) async {
    final db = await database.database;
    expect(
      '${(await db.rawQuery('PRAGMA journal_mode=WAL')).single.values.single}'
          .toLowerCase(),
      'wal',
    );
    await db.rawQuery('PRAGMA wal_autocheckpoint=0');
    final checkpoint = await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    expect(checkpoint.single.values.first, 0, reason: 'checkpoint inicial');
  }

  /// Productos de una copia del archivo principal **sin** su `-wal`: lo que
  /// tendría una copia hecha sólo del archivo principal.
  Future<Set<Object?>> productsInMainFileOnly(String databasePath) async {
    final probeDir = await Directory.systemTemp.createTemp('agro_f10_probe_');
    try {
      final copy = p.join(probeDir.path, 'principal.db');
      await File(databasePath).copy(copy);
      final probe = await databaseFactoryFfi.openDatabase(
        copy,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      try {
        return {for (final row in await probe.query('products')) row['name']};
      } finally {
        await probe.close();
      }
    } finally {
      try {
        await probeDir.delete(recursive: true);
      } on FileSystemException {
        // Temporal.
      }
    }
  }

  /// Respaldo `.agrobackup` del mismo titular, de otra base, con una
  /// fotografía que **pisa** el nombre de la actual y otra propia.
  Future<String> containerBackup() async {
    final directory = await Directory(p.join(workspace.path, 'origen'))
        .create();
    final folder = await Directory(p.join(directory.path, 'facturas')).create();
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      path: p.join(directory.path, 'origen.db'),
    );
    final household = await seedHousehold(AgroRepository(database));
    await household.repo.addProduct(name: 'Respaldo');
    await buyWithPhoto(household, folder, 'factura_comun.jpg', 'F-RES-1');
    await buyWithPhoto(household, folder, 'solo_respaldo.jpg', 'F-RES-2');
    await OwnerBindingStore(database).bindExistingPerson(
      personId: household.titular,
      scope: memberA,
      installationRef: installationHere,
    );
    final exported = await BackupService(
      database,
      invoicesDir: () async => folder,
      exportDirectory: () async =>
          Directory(p.join(workspace.path, 'exportados')),
    ).export();
    await database.close();
    return exported.path;
  }

  Future<(ProviderContainer, AppDatabase, String)> install({
    BackupService Function(AppDatabase database)? backupService,
  }) async {
    final path = p.join(workspace.path, 'agro.db');
    final database = AppDatabase(factory: databaseFactoryFfi, path: path);
    addTearDown(database.close);
    await seedCurrent(database);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        existingSessionStartupProvider.overrideWithValue(
          ExistingSessionStartupState.localSessionAvailable,
        ),
        ...startupAccessOverrides(sessionScope: memberA),
        if (backupService != null)
          backupServiceProvider.overrideWithValue(backupService(database)),
      ],
    );
    addTearDown(container.dispose);
    await container.read(installationAccessProvider.notifier).refresh();
    expect(
      container.read(installationAccessProvider),
      InstallationAccessState.activated,
    );
    return (container, database, path);
  }

  /// La transacción reciente: un producto y una compra con foto, confirmados
  /// y todavía sólo en el WAL. Comprueba esa precondición.
  Future<void> recentTransactionOnlyInWal(
    AppDatabase database,
    String path,
  ) async {
    final household = Household(AgroRepository(database), 1, 2, 3)
      ..supplier = 1
      ..campaign = 1
      ..product = 1;
    await household.repo.addProduct(name: 'Reciente');
    await buyWithPhoto(household, invoices, 'factura_reciente.jpg', 'F-REC');

    expect(await journalMode(database), 'wal');
    final wal = File('$path-wal');
    expect(
      wal.existsSync() && wal.lengthSync() > 0,
      isTrue,
      reason: 'la transacción reciente debe estar en -wal',
    );
    final mainOnly = await productsInMainFileOnly(path);
    expect(mainOnly, contains('Actual'));
    expect(
      mainOnly,
      isNot(contains('Reciente')),
      reason: 'el archivo principal solo no contiene la transacción reciente',
    );
  }

  Future<_Dump> dump(AppDatabase database) async =>
      dumpTables(await database.database);

  Future<_Dump> dumpFromDisk(String path) async {
    final reopened = AppDatabase(factory: databaseFactoryFfi, path: path);
    try {
      return await dumpTables(await reopened.database);
    } finally {
      await reopened.close();
    }
  }

  group('copia previa de una base en WAL', () {
    test(
      'fallo después de empezar la sustitución: el rollback conserva la '
      'transacción reciente, todas las tablas y las fotos; también al reabrir',
      () async {
        final backup = await containerBackup();
        final (container, database, path) = await install();
        await walWithoutAutocheckpoint(database);
        await recentTransactionOnlyInWal(database, path);

        final before = await dump(database);
        final photosBefore = photosIn(invoices);
        expect(photosBefore.keys, {
          'factura_comun.jpg',
          'factura_reciente.jpg',
        });

        var substitutionStarted = false;
        await expectLater(
          container
              .read(guardedRestoreProvider)
              .restore(
                backup,
                afterReplace: () async {
                  // La sustitución empezó de verdad: base y fotos del respaldo.
                  final names = {
                    for (final row in await (await database.database).query(
                      'products',
                    ))
                      row['name'],
                  };
                  expect(names, contains('Respaldo'));
                  expect(names, isNot(contains('Reciente')));
                  expect(
                    photosIn(invoices)['factura_comun.jpg'],
                    isNot(photosBefore['factura_comun.jpg']),
                  );
                  substitutionStarted = true;
                  throw StateError('fallo simulado tras sustituir');
                },
              ),
          throwsA(isA<StateError>()),
        );
        expect(substitutionStarted, isTrue);

        final after = await dump(database);
        expect(
          {for (final row in after['products']!) row['name']},
          contains('Reciente'),
          reason: 'la transacción reciente sobrevive al rollback',
        );
        expect(after, before);
        expect(photosIn(invoices), photosBefore);
        expect(
          container.read(installationAccessProvider),
          InstallationAccessState.activated,
        );

        // Reapertura desde disco, con otra instancia.
        await database.close();
        expect(await dumpFromDisk(path), before);
      },
    );

    test(
      'restauración correcta: la copia previa contiene la transacción reciente',
      () async {
        final backup = await containerBackup();
        final (container, database, path) = await install();
        await walWithoutAutocheckpoint(database);
        await recentTransactionOnlyInWal(database, path);
        final before = await dump(database);

        final outcome = await container
            .read(guardedRestoreProvider)
            .restore(backup);

        expect(await dumpFromDisk(outcome.result.safetyCopyPath), before);
      },
    );

    test('residuo WAL de un cierre abrupto sin abrir la base: se integra antes '
        'de copiar y el rollback no lo pierde', () async {
      final backup = await containerBackup();
      final (_, database, path) = await install();
      await walWithoutAutocheckpoint(database);
      await recentTransactionOnlyInWal(database, path);
      final before = await dump(database);

      // Lo que deja un proceso terminado sin cerrar: el archivo principal y
      // su -wal, copiados mientras la conexión seguía abierta.
      final crashDir = await Directory(
        p.join(workspace.path, 'tras_cierre_abrupto'),
      ).create();
      final crashed = p.join(crashDir.path, 'agro.db');
      await File(path).copy(crashed);
      await File('$path-wal').copy('$crashed-wal');
      final unopened = AppDatabase(factory: databaseFactoryFfi, path: crashed);
      addTearDown(unopened.close);

      await expectLater(
        BackupService(unopened).restore(
          backup,
          afterReplace: () async => throw StateError('fallo simulado'),
        ),
        throwsA(isA<StateError>()),
      );
      await unopened.close();
      expect(await dumpFromDisk(crashed), before);
    });

    // Técnica para provocar en el teléfono un fallo **después** de empezar la
    // sustitución (tool/f08_bkp/craft_negative.py, variante
    // `fallo_tras_sustituir`): una copia coherente —manifiesto recalculado—
    // cuya base no tiene `sync_outbox`. Pasa la validación (no es una tabla
    // obligatoria) y la propiedad, y falla al pausar la outbox restaurada, ya
    // con la base y las fotos sustituidas.
    test('copia coherente sin sync_outbox: falla al pausar tras sustituir y el '
        'rollback conserva la transacción reciente', () async {
      final backup = await containerBackup();
      final probe = await extractDatabaseFrom(backup);
      final db = await databaseFactoryFfi.openDatabase(
        probe,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await db.execute('PRAGMA foreign_keys = OFF');
      await db.execute('DROP TABLE sync_outbox');
      await db.close();
      final bytes = await File(probe).readAsBytes();
      final manifest = jsonDecode(
        utf8.decode(entryBytes(backup, 'manifest.json')!),
      ) as Map<String, Object?>;
      manifest['database'] = {
        'name': 'database.db',
        'bytes': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
      };
      await rewriteEntry(backup, 'database.db', bytes);
      await rewriteEntry(
        backup,
        'manifest.json',
        utf8.encode(jsonEncode(manifest)),
      );

      final (container, database, path) = await install();
      await walWithoutAutocheckpoint(database);
      await recentTransactionOnlyInWal(database, path);
      final before = await dump(database);
      final photosBefore = photosIn(invoices);

      final service = container.read(backupServiceProvider);
      expect((await service.validate(backup)).isValid, isTrue);
      await expectLater(
        container.read(guardedRestoreProvider).restore(backup),
        throwsA(
          isA<DatabaseException>().having(
            (e) => '$e',
            'error',
            contains('sync_outbox'),
          ),
        ),
      );
      expect(await dump(database), before);
      expect(photosIn(invoices), photosBefore);
      expect(
        container.read(installationAccessProvider),
        InstallationAccessState.activated,
      );
      await database.close();
      expect(await dumpFromDisk(path), before);
    });
  });

  group('fallo al preparar la copia previa: no empieza el reemplazo', () {
    Future<void> expectUntouched(
      AppDatabase database,
      _Dump before,
      Map<String, String> photosBefore,
    ) async {
      expect(await dump(database), before);
      expect(photosIn(invoices), photosBefore);
      expect(
        workspace.listSync().where(
          (e) => p.basename(e.path).contains('.previo-'),
        ),
        isEmpty,
        reason: 'no quedan copias previas a medias ni carpetas de fotos',
      );
    }

    test('el checkpoint no puede completarse (lector abierto): se rechaza sin '
        'cerrar ni sustituir nada', () async {
      final backup = await containerBackup();
      final (container, database, path) = await install();
      await walWithoutAutocheckpoint(database);
      await recentTransactionOnlyInWal(database, path);
      final before = await dump(database);
      final photosBefore = photosIn(invoices);

      // Otra conexión con una transacción de lectura abierta impide que el
      // checkpoint TRUNCATE termine: SQLite responde busy.
      final reader = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await reader.execute('BEGIN');
      await reader.rawQuery('SELECT count(*) FROM products');
      var replaced = false;
      try {
        await expectLater(
          container
              .read(guardedRestoreProvider)
              .restore(backup, afterReplace: () async => replaced = true),
          throwsA(
            isA<BackupException>().having(
              (e) => e.message,
              'message',
              contains('consolidar'),
            ),
          ),
        );
      } finally {
        await reader.execute('COMMIT');
        await reader.close();
      }
      expect(replaced, isFalse);
      await expectUntouched(database, before, photosBefore);
      expect(
        container.read(installationAccessProvider),
        InstallationAccessState.activated,
      );
      // La app sigue operando sobre sus datos.
      await AgroRepository(database).addProduct(name: 'Después');
    });

    test(
      'el -wal no queda vacío tras cerrar (otra conexión escribió): se rechaza '
      'sin copiar ni sustituir',
      () async {
        final backup = await containerBackup();
        final path = p.join(workspace.path, 'agro.db');
        Database? other;
        final (container, database, _) = await install(
          backupService: (db) => BackupService(
            db,
            afterCheckpoint: () async {
              // Otra conexión escribe después del checkpoint: al cerrar la de
              // la app, su transacción sigue sólo en -wal.
              other = await databaseFactoryFfi.openDatabase(
                path,
                options: OpenDatabaseOptions(singleInstance: false),
              );
              await other!.insert('products', {
                'name': 'Otra conexión',
                'unit': 'L',
                'base_unit': 'ML',
              });
            },
          ),
        );
        await walWithoutAutocheckpoint(database);
        await recentTransactionOnlyInWal(database, path);
        final before = await dump(database);
        final photosBefore = photosIn(invoices);

        var replaced = false;
        try {
          await expectLater(
            container
                .read(guardedRestoreProvider)
                .restore(backup, afterReplace: () async => replaced = true),
            throwsA(
              isA<BackupException>().having(
                (e) => e.message,
                'message',
                contains('cerrar la base de forma consistente'),
              ),
            ),
          );
        } finally {
          await other?.close();
        }
        expect(replaced, isFalse);
        final after = await dump(database);
        expect({
          for (final row in after['products']!) row['name'],
        }, containsAll(['Reciente', 'Otra conexión']));
        expect({
          for (final row in after['products']!) row['name'],
        }, isNot(contains('Respaldo')));
        expect(after['purchases'], before['purchases']);
        expect(photosIn(invoices), photosBefore);
        expect(
          workspace.listSync().where(
            (e) => p.basename(e.path).contains('.previo-'),
          ),
          isEmpty,
        );
      },
    );

    test('la copia previa no coincide con la base cerrada: se descarta y no se '
        'sustituye', () async {
      final backup = await containerBackup();
      final (container, database, path) = await install(
        backupService: (db) => BackupService(
          db,
          afterSafetyCopy: (copy) async {
            // Simula una copia incompleta o dañada por el almacenamiento.
            final bytes = await copy.readAsBytes();
            await copy.writeAsBytes(
              bytes.sublist(0, bytes.length ~/ 2),
              flush: true,
            );
          },
        ),
      );
      await walWithoutAutocheckpoint(database);
      await recentTransactionOnlyInWal(database, path);
      final before = await dump(database);
      final photosBefore = photosIn(invoices);

      var replaced = false;
      await expectLater(
        container
            .read(guardedRestoreProvider)
            .restore(backup, afterReplace: () async => replaced = true),
        throwsA(isA<BackupException>()),
      );
      expect(replaced, isFalse);
      await expectUntouched(database, before, photosBefore);
      await database.close();
      expect(await dumpFromDisk(path), before);
    });
  });
}
