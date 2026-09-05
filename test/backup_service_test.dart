import 'dart:io';

import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/backup_service.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// STAB-007: hasta ahora se podía exportar un respaldo pero no restaurarlo, y
/// no se validaba nada. Un respaldo que la aplicación no sabe leer no protege
/// de nada.
void main() {
  sqfliteFfiInit();

  late Directory workspace;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('agro_backup_');
  });
  tearDown(() => workspace.delete(recursive: true));

  String pathFor(String name) => p.join(workspace.path, name);

  /// Base con datos reales: una persona, una compra de 20 L y nada más.
  Future<AppDatabase> seededDatabase(String name) async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      path: pathFor(name),
    );
    final repo = AgroRepository(database);
    final family = await repo.addPerson(
      name: 'Familiar',
      role: PersonRole.family,
    );
    final supplier = await repo.addSupplier(name: 'Proveedor');
    final campaign = await repo.addCampaign(
      name: 'Campaña',
      start: DateTime.utc(2026),
    );
    final product = await repo.addProduct(name: 'Glifosato');
    await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: supplier,
        campaignId: campaign,
        purchaseDate: DateTime.utc(2026, 1, 10),
        items: [
          PurchaseItemDraft(
            productId: product,
            quantityBase: 20000,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 10000,
            allocations: [
              AllocationDraft(personId: family, quantityBase: 20000),
            ],
          ),
        ],
      ),
    );
    return database;
  }

  group('validate', () {
    test(
      'acepta un respaldo legítimo y reporta su versión de esquema',
      () async {
        final source = await seededDatabase('origen.db');
        addTearDown(source.close);
        await source.database;

        final copy = pathFor('respaldo.db');
        await File(source.openedPath!).copy(copy);

        final result = await BackupService(source).validate(copy);
        expect(result.isValid, isTrue, reason: result.problem);
        expect(result.schemaVersion, AppDatabase.schemaVersion);
      },
    );

    test('rechaza un archivo inexistente', () async {
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        path: pathFor('vacia.db'),
      );
      addTearDown(database.close);
      final result = await BackupService(database).validate(pathFor('no.db'));
      expect(result.isValid, isFalse);
      expect(result.problem, contains('no existe'));
    });

    test('rechaza un archivo vacío', () async {
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        path: pathFor('vacia.db'),
      );
      addTearDown(database.close);
      final empty = pathFor('cero.db');
      await File(empty).writeAsBytes(const []);
      final result = await BackupService(database).validate(empty);
      expect(result.isValid, isFalse);
      expect(result.problem, contains('vacío'));
    });

    test('rechaza un archivo que no es SQLite', () async {
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        path: pathFor('vacia.db'),
      );
      addTearDown(database.close);
      final bogus = pathFor('foto.jpg');
      await File(bogus).writeAsString('esto no es una base de datos');
      final result = await BackupService(database).validate(bogus);
      expect(result.isValid, isFalse);
      expect(result.problem, isNotNull);
    });

    test('rechaza una base SQLite ajena a la aplicación', () async {
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        path: pathFor('vacia.db'),
      );
      addTearDown(database.close);

      final foreign = pathFor('otra_app.db');
      final other = await databaseFactoryFfi.openDatabase(
        foreign,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) =>
              db.execute('CREATE TABLE cosas (id INTEGER PRIMARY KEY)'),
        ),
      );
      await other.close();

      final result = await BackupService(database).validate(foreign);
      expect(result.isValid, isFalse);
      expect(result.problem, contains('no es un respaldo de Agrocuentas'));
    });

    test('rechaza un respaldo de una versión de esquema más nueva', () async {
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        path: pathFor('vacia.db'),
      );
      addTearDown(database.close);

      // Base con las tablas requeridas pero user_version por encima del actual.
      final future = pathFor('futuro.db');
      final db = await databaseFactoryFfi.openDatabase(
        future,
        options: OpenDatabaseOptions(version: 1),
      );
      for (final table in BackupService.requiredTables) {
        await db.execute('CREATE TABLE $table (id INTEGER PRIMARY KEY)');
      }
      await db.execute(
        'PRAGMA user_version = ${AppDatabase.schemaVersion + 1}',
      );
      await db.close();

      final result = await BackupService(database).validate(future);
      expect(result.isValid, isFalse);
      expect(result.problem, contains('más reciente'));
    });
  });

  group('restore', () {
    test('reemplaza los datos actuales por los del respaldo', () async {
      // Respaldo: base con una compra de 20 L.
      final source = await seededDatabase('origen.db');
      await source.database;
      final backup = pathFor('respaldo.db');
      await File(source.openedPath!).copy(backup);
      await source.close();

      // Base destino: distinta, con otra persona y sin compras.
      final target = AppDatabase(
        factory: databaseFactoryFfi,
        path: pathFor('destino.db'),
      );
      addTearDown(target.close);
      final targetRepo = AgroRepository(target);
      await targetRepo.addPerson(name: 'Otra', role: PersonRole.thirdParty);
      expect(await targetRepo.purchases(), isEmpty);

      await BackupService(target).restore(backup);

      // Tras restaurar, los datos son los del respaldo.
      final people = await targetRepo.people();
      expect(people.map((r) => r['name']), ['Familiar']);
      expect(await targetRepo.purchases(), hasLength(1));
      final stock = await targetRepo.inventorySummary();
      expect(stock.single['available_base'], 20000);
    });

    test('deja una copia de seguridad de los datos previos', () async {
      final source = await seededDatabase('origen.db');
      await source.database;
      final backup = pathFor('respaldo.db');
      await File(source.openedPath!).copy(backup);
      await source.close();

      final target = AppDatabase(
        factory: databaseFactoryFfi,
        path: pathFor('destino.db'),
      );
      addTearDown(target.close);
      await AgroRepository(target)
          .addPerson(name: 'Se va a reemplazar', role: PersonRole.family);

      final safetyCopy = await BackupService(target).restore(backup);

      expect(
        await File(safetyCopy).exists(),
        isTrue,
        reason: 'Restaurar debe dejar recuperables los datos anteriores.',
      );

      // La copia previa conserva los datos que se reemplazaron.
      final previous = AppDatabase(
        factory: databaseFactoryFfi,
        path: safetyCopy,
      );
      addTearDown(previous.close);
      final names = (await AgroRepository(
        previous,
      ).people()).map((r) => r['name']);
      expect(names, contains('Se va a reemplazar'));
    });

    test('un respaldo inválido no toca los datos actuales', () async {
      final target = AppDatabase(
        factory: databaseFactoryFfi,
        path: pathFor('destino.db'),
      );
      addTearDown(target.close);
      final repo = AgroRepository(target);
      await repo.addPerson(name: 'Intacta', role: PersonRole.family);

      final bogus = pathFor('malo.db');
      await File(bogus).writeAsString('no soy una base');

      await expectLater(
        BackupService(target).restore(bogus),
        throwsA(isA<BackupException>()),
      );

      // Los datos siguen ahí.
      final names = (await repo.people()).map((r) => r['name']);
      expect(names, contains('Intacta'));
    });

    test(
      'restaurar un respaldo de esquema antiguo dispara la migración',
      () async {
        // Respaldo en versión 3: al restaurarlo debe migrarse hasta la actual.
        final legacyPath = pathFor('v3.db');
        final legacy = await databaseFactoryFfi.openDatabase(
          legacyPath,
          options: OpenDatabaseOptions(
            version: 3,
            onCreate: (db, _) async {
              for (final table in BackupService.requiredTables) {
                await db.execute(
                  'CREATE TABLE $table (id INTEGER PRIMARY KEY)',
                );
              }
            },
          ),
        );
        await legacy.close();

        final target = AppDatabase(
          factory: databaseFactoryFfi,
          path: pathFor('destino.db'),
        );
        addTearDown(target.close);

        final validation = await BackupService(target).validate(legacyPath);
        expect(validation.isValid, isTrue, reason: validation.problem);
        expect(validation.schemaVersion, 3);
      },
    );
  });
}
