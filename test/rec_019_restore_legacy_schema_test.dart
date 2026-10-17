// REC-019 (#55), requisito (b) del comentario del 2026-10-15: un test que
// RESTAURE un respaldo de esquema antiguo y compruebe la migración. El test
// «restaurar un respaldo de esquema antiguo dispara la migración» de
// backup_service_test.dart sólo valida una base v3 de juguete. Aquí se
// restaura de verdad (un `.db`, con BackupService.restore) una base v7
// sintetizada con downgradeToV7 (el esquema anterior a #77) y se comprueba la
// versión final, la integridad, las tablas nuevas, la marca de base histórica
// y que ninguna fila de negocio se pierda.
import 'dart:io';

import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';

void main() {
  sqfliteFfiInit();

  late Directory workspace;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('agro_rec019_');
  });
  tearDown(() async {
    try {
      await workspace.delete(recursive: true);
    } on FileSystemException {
      // En Windows el motor puede retener un archivo un instante; es temporal.
    }
  });

  String pathFor(String name) => p.join(workspace.path, name);

  test('restaurar una copia v7 (sintetizada) la migra a la versión actual sin perder '
      'filas y como base histórica', () async {
    // Copia v7: hogar con compra, aplicación y chacos, llevada al esquema v7
    // exacto (sin las tablas ni marcas de v8/v9).
    final source = AppDatabase(
      factory: databaseFactoryFfi,
      path: pathFor('v7.db'),
    );
    final household = await seedHousehold(AgroRepository(source));
    await household.buy(household.titular, 5000);
    await household.apply(household.titular, household.titularFarm, 2000);
    await source.close();
    await downgradeToV7(pathFor('v7.db'));

    final v7 = await databaseFactoryFfi.openDatabase(pathFor('v7.db'));
    expect((await v7.rawQuery('PRAGMA user_version')).single.values.single, 7);
    final v7Business = await dumpTables(v7);
    final v7Tables = v7Business.keys.toSet();
    expect(v7Tables, isNot(contains('owner_bindings')));
    expect(v7Tables, isNot(contains('sync_outbox')));
    await v7.close();

    // Destino actual con otros datos: la restauración los sustituye.
    final target = AppDatabase(
      factory: databaseFactoryFfi,
      path: pathFor('destino.db'),
    );
    addTearDown(target.close);
    await AgroRepository(target).addProduct(name: 'Se reemplaza');

    final validation = await BackupService(target).validate(pathFor('v7.db'));
    expect(validation.isValid, isTrue, reason: validation.problem);
    expect(validation.schemaVersion, 7);

    await BackupService(target).restore(pathFor('v7.db'));

    final db = await target.database;
    expect(
      (await db.rawQuery('PRAGMA user_version')).single.values.single,
      AppDatabase.schemaVersion,
      reason: 'la copia v7 se migra hasta la versión actual',
    );
    expect(
      (await db.rawQuery('PRAGMA integrity_check')).single.values.single,
      'ok',
    );
    final restored = await dumpTables(db);
    // Las tablas de la v7 conservan exactamente sus filas; app_settings sólo
    // gana la marca de base histórica.
    for (final table in v7Tables.difference({'app_settings'})) {
      expect(restored[table], v7Business[table], reason: table);
    }
    expect(
      (await settings(db))[AppDatabase.installOriginKey],
      AppDatabase.installOriginLegacy,
    );
    // Las tablas que añadieron v8 y v9 existen y nacen vacías: restaurar no
    // atribuye titular ni crea intenciones.
    expect(restored['owner_bindings'], isEmpty);
    expect(restored['sync_outbox'], isEmpty);
    // Los datos son los de la copia, y se leen con el dominio actual.
    final repo = AgroRepository(target);
    expect((await repo.products()).map((r) => r['name']), ['Glifosato']);
    expect(
      (await stockByPersonProduct(db))[(household.titular, household.product)],
      3000,
    );
  });
}
