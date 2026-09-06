import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/backup_service.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
// Dependencia transitiva de `path_provider`: se usa sólo para sustituir la
// implementación de plataforma en la prueba, sin tocar `pubspec.yaml`.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'backup_container_support.dart';

/// **Respaldo 2.0 — la base y las fotografías viajan juntas.**
///
/// Perder el teléfono no debe significar perder las facturas. El respaldo pasa
/// de ser una copia suelta de la base a un contenedor `.agrobackup` con
/// manifiesto, base y fotografías. Los respaldos `.db` históricos se siguen
/// pudiendo restaurar, avisando de que no traen fotos.
class _WorkspacePathProvider extends PathProviderPlatform {
  _WorkspacePathProvider(this.directory);
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

  late Directory workspace;
  late Directory invoices;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('agro_container_');
    invoices = Directory(p.join(workspace.path, 'invoices'));
    await invoices.create(recursive: true);
    PathProviderPlatform.instance = _WorkspacePathProvider(workspace.path);
  });

  tearDown(() async {
    try {
      await workspace.delete(recursive: true);
    } on FileSystemException {
      // En Windows el motor SQLite puede retener el archivo; es temporal.
    }
  });

  String pathFor(String name) => p.join(workspace.path, name);

  /// Bytes de una imagen cualquiera: al respaldo le da igual el formato, y así
  /// la prueba no depende de un binario versionado.
  Uint8List photoBytes(int seed) =>
      Uint8List.fromList(List<int>.generate(2048, (i) => (i * seed) % 251));

  /// Base con [photos] compras, cada una con su fotografía de factura.
  Future<(AppDatabase, AgroRepository, List<String>)> seeded({
    required String name,
    int photos = 0,
  }) async {
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

    final names = <String>[];
    for (var index = 0; index < (photos == 0 ? 1 : photos); index++) {
      String? imagePath;
      if (index < photos) {
        final fileName = 'invoice_$index.jpg';
        final file = File(p.join(invoices.path, fileName));
        await file.writeAsBytes(photoBytes(index + 1), flush: true);
        imagePath = file.path;
        names.add(fileName);
      }
      await repo.confirmPurchase(
        PurchaseDraft(
          supplierId: supplier,
          campaignId: campaign,
          purchaseDate: DateTime.utc(2026, 1, 10 + index),
          invoiceNumber: 'F-$index',
          invoiceImagePath: imagePath,
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
    }
    return (database, repo, names);
  }

  BackupService serviceFor(AppDatabase database) =>
      BackupService(database, invoicesDir: () async => invoices);

  Map<String, Object?> manifestOf(String path) =>
      jsonDecode(utf8.decode(entryBytes(path, 'manifest.json')!))
          as Map<String, Object?>;

  group('exportación', () {
    test(
      'sin fotografías produce un contenedor con manifiesto y base',
      () async {
        final (database, _, _) = await seeded(name: 'sin.db');
        addTearDown(database.close);

        final result = await serviceFor(database).export();

        expect(result.path, endsWith(BackupService.containerExtension));
        expect(result.attachmentCount, 0);
        expect(result.warnings, isEmpty);
        expect(
          entriesOf(result.path),
          containsAll(<String>['manifest.json', 'database.db']),
        );

        final manifest = manifestOf(result.path);
        expect(manifest['application'], 'agrocuentas');
        expect(
          manifest['backupFormatVersion'],
          BackupService.backupFormatVersion,
        );
        expect(manifest['databaseSchemaVersion'], AppDatabase.schemaVersion);
        expect(manifest['attachmentCount'], 0);
        expect(manifest['appVersion'], isNotNull);
        expect(DateTime.tryParse('${manifest['createdAt']}'), isNotNull);
        // Nunca un secreto en el manifiesto.
        expect(jsonEncode(manifest).toLowerCase(), isNot(contains('password')));
      },
    );

    test('con una fotografía la incluye y la describe', () async {
      final (database, _, names) = await seeded(name: 'una.db', photos: 1);
      addTearDown(database.close);

      final result = await serviceFor(database).export();

      expect(result.attachmentCount, 1);
      expect(entriesOf(result.path), contains('invoices/${names.single}'));
      // El contenido llega intacto, no sólo el nombre.
      expect(
        entryBytes(result.path, 'invoices/${names.single}'),
        photoBytes(1),
      );

      final attachment =
          (manifestOf(result.path)['attachments']! as List).single
              as Map<String, Object?>;
      expect(attachment['name'], names.single);
      expect(attachment['bytes'], 2048);
      expect(attachment['sha256'], isA<String>());
      expect(attachment['purchaseIds'], hasLength(1));
    });

    test('con varias fotografías las incluye todas', () async {
      final (database, _, names) = await seeded(name: 'varias.db', photos: 3);
      addTearDown(database.close);

      final result = await serviceFor(database).export();

      expect(result.attachmentCount, 3);
      expect(names, hasLength(3));
      for (final name in names) {
        expect(entriesOf(result.path), contains('invoices/$name'));
      }
    });

    test('una fotografía que ya no existe se avisa, no se oculta', () async {
      final (database, _, names) = await seeded(name: 'falta.db', photos: 2);
      addTearDown(database.close);
      // El usuario borró el archivo desde fuera de la aplicación.
      await File(p.join(invoices.path, names.first)).delete();

      final result = await serviceFor(database).export();

      // El respaldo se completa —bloquearlo dejaría al usuario sin copia de
      // sus cuentas por una foto perdida— pero la pérdida se declara.
      expect(result.attachmentCount, 1);
      expect(result.hasWarnings, isTrue);
      expect(result.warnings.single, contains('1 factura'));

      final missing =
          (manifestOf(result.path)['missingAttachments']! as List).single
              as Map<String, Object?>;
      expect(missing['name'], names.first);
      expect(missing['purchaseIds'], isNotEmpty);
    });

    test(
      'el archivo escrito pasa la propia validación de la aplicación',
      () async {
        final (database, _, _) = await seeded(name: 'valida.db', photos: 2);
        addTearDown(database.close);
        final service = serviceFor(database);

        final result = await service.export();
        final validation = await service.validate(result.path);

        expect(validation.isValid, isTrue, reason: validation.problem);
        expect(validation.format, BackupFormat.container);
        expect(validation.attachmentCount, 2);
        expect(validation.schemaVersion, AppDatabase.schemaVersion);
        expect(validation.isLegacyWithoutPhotos, isFalse);
      },
    );
  });

  group('validación de archivos dañados', () {
    Future<String> exported({int photos = 1}) async {
      final (database, _, _) = await seeded(name: 'src.db', photos: photos);
      final path = (await serviceFor(database).export()).path;
      await database.close();
      return path;
    }

    late AppDatabase probe;
    late BackupService service;

    setUp(() {
      probe = AppDatabase(
        factory: databaseFactoryFfi,
        path: pathFor('probe.db'),
      );
      service = serviceFor(probe);
      addTearDown(probe.close);
    });

    test('un archivo que no existe se rechaza', () async {
      final validation = await service.validate(pathFor('fantasma.agrobackup'));
      expect(validation.isValid, isFalse);
      expect(validation.problem, contains('no existe'));
    });

    test('un archivo vacío se rechaza', () async {
      final empty = File(pathFor('vacio.agrobackup'));
      await empty.writeAsBytes(const []);
      final validation = await service.validate(empty.path);
      expect(validation.isValid, isFalse);
      expect(validation.problem, contains('vacío'));
    });

    test('un archivo que no es ni ZIP ni base se rechaza', () async {
      final junk = File(pathFor('basura.agrobackup'));
      await junk.writeAsString('esto no es un respaldo');
      final validation = await service.validate(junk.path);
      expect(validation.isValid, isFalse);
    });

    test('un contenedor sin manifiesto se rechaza', () async {
      final path = await exported();
      await removeEntry(path, 'manifest.json');
      final validation = await service.validate(path);
      expect(validation.isValid, isFalse);
      expect(validation.problem, contains('manifiesto'));
    });

    test('un manifiesto ilegible se rechaza', () async {
      final path = await exported();
      await rewriteEntry(path, 'manifest.json', utf8.encode('{roto'));
      final validation = await service.validate(path);
      expect(validation.isValid, isFalse);
      expect(validation.problem, contains('dañado'));
    });

    test('un manifiesto de otra aplicación se rechaza', () async {
      final path = await exported();
      await rewriteEntry(
        path,
        'manifest.json',
        utf8.encode(jsonEncode({'application': 'otra-cosa'})),
      );
      final validation = await service.validate(path);
      expect(validation.isValid, isFalse);
      expect(validation.problem, contains('no es un respaldo de Agrocuentas'));
    });

    test('un contenedor sin base de datos se rechaza', () async {
      final path = await exported();
      await removeEntry(path, 'database.db');
      final validation = await service.validate(path);
      expect(validation.isValid, isFalse);
      expect(validation.problem, contains('base de datos'));
    });

    test('una base dañada se rechaza', () async {
      final path = await exported();
      await rewriteEntry(
        path,
        'database.db',
        Uint8List.fromList(List<int>.filled(4096, 7)),
      );
      final validation = await service.validate(path);
      expect(validation.isValid, isFalse);
    });

    test('una fotografía anunciada pero ausente se rechaza', () async {
      final path = await exported();
      await removeEntry(path, 'invoices/invoice_0.jpg');
      final validation = await service.validate(path);
      expect(validation.isValid, isFalse);
      expect(validation.problem, contains('no la contiene'));
    });

    test('una fotografía alterada se detecta por su checksum', () async {
      final path = await exported();
      await rewriteEntry(
        path,
        'invoices/invoice_0.jpg',
        Uint8List.fromList(List<int>.filled(2048, 3)),
      );
      final validation = await service.validate(path);
      expect(validation.isValid, isFalse);
      expect(validation.problem, contains('dañada'));
    });

    test(
      'un formato de contenedor futuro se rechaza con explicación',
      () async {
        final path = await exported();
        final manifest = manifestOf(path)
          ..['backupFormatVersion'] = BackupService.backupFormatVersion + 1;
        await rewriteEntry(
          path,
          'manifest.json',
          utf8.encode(jsonEncode(manifest)),
        );
        final validation = await service.validate(path);
        expect(validation.isValid, isFalse);
        expect(validation.problem, contains('Actualice la aplicación'));
      },
    );

    test('un esquema futuro se rechaza con explicación', () async {
      final path = await exported();
      final extracted = await extractDatabaseFrom(path);
      final raw = await databaseFactoryFfi.openDatabase(extracted);
      await raw.execute(
        'PRAGMA user_version = ${AppDatabase.schemaVersion + 1}',
      );
      await raw.close();
      await rewriteEntry(
        path,
        'database.db',
        await File(extracted).readAsBytes(),
      );

      final validation = await service.validate(path);
      expect(validation.isValid, isFalse);
      expect(validation.problem, contains('más reciente'));
    });
  });

  group('compatibilidad con el formato histórico', () {
    test('un .db suelto sigue siendo válido y se marca como legacy', () async {
      final (database, _, _) = await seeded(name: 'legacy_src.db');
      await database.database;
      final legacy = pathFor('agroquimicos_backup_legacy.db');
      await File(database.openedPath!).copy(legacy);
      await database.close();

      final probe = AppDatabase(
        factory: databaseFactoryFfi,
        path: pathFor('probe_legacy.db'),
      );
      addTearDown(probe.close);
      final validation = await serviceFor(probe).validate(legacy);

      expect(validation.isValid, isTrue, reason: validation.problem);
      expect(validation.format, BackupFormat.legacyDatabase);
      expect(validation.isLegacyWithoutPhotos, isTrue);
      expect(validation.attachmentCount, 0);
    });

    test('restaurarlo funciona y avisa de que no trae fotografías', () async {
      final (source, _, _) = await seeded(name: 'legacy2_src.db');
      await source.database;
      final legacy = pathFor('agroquimicos_backup_legacy2.db');
      await File(source.openedPath!).copy(legacy);
      await source.close();

      final target = AppDatabase(
        factory: databaseFactoryFfi,
        path: pathFor('legacy_target.db'),
      );
      addTearDown(target.close);
      await AgroRepository(target)
          .addPerson(name: 'Se reemplaza', role: PersonRole.family);

      final result = await serviceFor(target).restore(legacy);

      expect(result.format, BackupFormat.legacyDatabase);
      expect(result.restoredAttachments, 0);
      expect(result.warnings.single, contains('no contiene fotografías'));
      expect(
        (await AgroRepository(target).people()).map((row) => row['name']),
        contains('Familiar'),
      );
    });

    test('el listado incluye los dos formatos', () async {
      final (database, _, _) = await seeded(name: 'listado.db', photos: 1);
      addTearDown(database.close);
      final service = serviceFor(database);
      await service.export();
      await File(pathFor('agroquimicos_backup_antiguo.db'))
          .writeAsBytes(await File(database.openedPath!).readAsBytes());

      final names = (await service.listAvailableBackups())
          .map((file) => p.basename(file.path))
          .toList();

      expect(names.where((n) => n.endsWith('.agrobackup')), isNotEmpty);
      expect(names, contains('agroquimicos_backup_antiguo.db'));
    });
  });

  group('restauración', () {
    test(
      'devuelve base y fotografías, y la foto se puede volver a abrir',
      () async {
        final (source, sourceRepo, names) = await seeded(
          name: 'ciclo.db',
          photos: 2,
        );
        final backup = (await serviceFor(source).export()).path;
        final expectedPeople = (await sourceRepo.people()).length;
        await source.close();

        // Se destruye el estado: se borran las fotos y se parte de otra base.
        for (final name in names) {
          await File(p.join(invoices.path, name)).delete();
        }
        final target = AppDatabase(
          factory: databaseFactoryFfi,
          path: pathFor('ciclo_target.db'),
        );
        addTearDown(target.close);
        await AgroRepository(target)
            .addPerson(name: 'Se reemplaza', role: PersonRole.family);

        final result = await serviceFor(target).restore(backup);

        expect(result.format, BackupFormat.container);
        expect(result.restoredAttachments, 2);
        expect(result.warnings, isEmpty);

        final repo = AgroRepository(target);
        expect((await repo.people()).length, expectedPeople);

        // Cada compra apunta a un archivo que **existe** y cuyo contenido es el
        // original: la factura se puede abrir de verdad.
        final purchases = await repo.purchases();
        final withPhoto = purchases
            .where((row) => row['invoice_image_path'] != null)
            .toList();
        expect(withPhoto, hasLength(2));
        for (final row in withPhoto) {
          final file = File(row['invoice_image_path']! as String);
          expect(await file.exists(), isTrue, reason: file.path);
          expect(await file.length(), 2048);
        }
      },
    );

    test('las rutas se reconstruyen para este dispositivo', () async {
      // La base guarda rutas absolutas del teléfono donde se tomó la foto. Un
      // respaldo restaurado en otro sitio no debe seguir apuntando allí.
      final (source, _, names) = await seeded(name: 'rutas.db', photos: 1);
      final backup = (await serviceFor(source).export()).path;
      await source.close();

      final otherInvoices = Directory(p.join(workspace.path, 'otras_facturas'));
      await otherInvoices.create(recursive: true);
      final target = AppDatabase(
        factory: databaseFactoryFfi,
        path: pathFor('rutas_target.db'),
      );
      addTearDown(target.close);

      await BackupService(
        target,
        invoicesDir: () async => otherInvoices,
      ).restore(backup);

      final stored =
          (await AgroRepository(target).purchases()).firstWhere(
                (row) => row['invoice_image_path'] != null,
              )['invoice_image_path']!
              as String;

      expect(p.basename(stored), names.single);
      expect(p.dirname(stored), otherInvoices.path);
      expect(await File(stored).exists(), isTrue);
    });

    test('deja una copia de seguridad de los datos previos', () async {
      final (source, _, _) = await seeded(name: 'copia.db', photos: 1);
      final backup = (await serviceFor(source).export()).path;
      await source.close();

      final target = AppDatabase(
        factory: databaseFactoryFfi,
        path: pathFor('copia_target.db'),
      );
      addTearDown(target.close);
      await AgroRepository(target)
          .addPerson(name: 'Se reemplaza', role: PersonRole.family);

      final result = await serviceFor(target).restore(backup);

      final previous = AppDatabase(
        factory: databaseFactoryFfi,
        path: result.safetyCopyPath,
      );
      addTearDown(previous.close);
      expect(
        (await AgroRepository(previous).people()).map((row) => row['name']),
        contains('Se reemplaza'),
      );
    });

    test(
      'un respaldo inválido no toca ni la base ni las fotografías',
      () async {
        final target = AppDatabase(
          factory: databaseFactoryFfi,
          path: pathFor('intacto.db'),
        );
        addTearDown(target.close);
        await AgroRepository(target)
            .addPerson(name: 'Intacta', role: PersonRole.family);
        final keeper = File(p.join(invoices.path, 'existente.jpg'));
        await keeper.writeAsBytes(photoBytes(9), flush: true);

        final junk = File(pathFor('roto.agrobackup'));
        await junk.writeAsString('no soy un respaldo');

        await expectLater(
          serviceFor(target).restore(junk.path),
          throwsA(isA<BackupException>()),
        );

        expect(
          (await AgroRepository(target).people()).single['name'],
          'Intacta',
        );
        expect(await keeper.exists(), isTrue);
        expect(await keeper.readAsBytes(), photoBytes(9));
      },
    );

    test('un fallo a mitad de la restauración lo deshace todo', () async {
      // El peligro real no es que la restauración falle: es que falle **a
      // medias** y deje una base nueva con las fotografías viejas, o al revés.
      final (source, _, names) = await seeded(name: 'rollback.db', photos: 1);
      final backup = (await serviceFor(source).export()).path;
      await source.close();

      final target = AppDatabase(
        factory: databaseFactoryFfi,
        path: pathFor('rollback_target.db'),
      );
      addTearDown(target.close);
      final repo = AgroRepository(target);
      await repo.addPerson(name: 'Estado previo', role: PersonRole.family);
      final personsBefore = (await repo.people()).length;

      // Se prepara la carpeta de facturas con una foto propia y con un
      // obstáculo: una CARPETA con el nombre que la restauración tendrá que
      // escribir como archivo. Copiar sobre ella falla.
      final ownPhoto = File(p.join(invoices.path, 'propia.jpg'));
      await ownPhoto.writeAsBytes(photoBytes(5), flush: true);
      // La foto original ya está empaquetada en el respaldo; se retira del
      // disco para poder poner el obstáculo con su mismo nombre.
      await File(p.join(invoices.path, names.single)).delete();
      await Directory(p.join(invoices.path, names.single)).create();

      await expectLater(
        serviceFor(target).restore(backup),
        throwsA(isA<Object>()),
      );

      // La base vuelve a ser la de antes...
      final after = await AgroRepository(target).people();
      expect(after, hasLength(personsBefore));
      expect(after.single['name'], 'Estado previo');

      // ...y las fotografías que ya había siguen ahí, intactas.
      expect(await ownPhoto.exists(), isTrue);
      expect(await ownPhoto.readAsBytes(), photoBytes(5));
    });

    test('la base restaurada queda íntegra y operativa', () async {
      final (source, _, _) = await seeded(name: 'integra.db', photos: 1);
      final backup = (await serviceFor(source).export()).path;
      await source.close();

      final target = AppDatabase(
        factory: databaseFactoryFfi,
        path: pathFor('integra_target.db'),
      );
      addTearDown(target.close);
      await serviceFor(target).restore(backup);

      final db = await target.database;
      final integrity = await db.rawQuery('PRAGMA integrity_check');
      expect(integrity.first.values.first, 'ok');

      // Y sigue admitiendo escrituras: no quedó en un estado a medias.
      final repo = AgroRepository(target);
      expect(
        await repo.addPerson(name: 'Nueva', role: PersonRole.family),
        greaterThan(0),
      );
    });

    test('restaurar dos veces seguidas es estable', () async {
      final (source, _, _) = await seeded(name: 'doble.db', photos: 2);
      final backup = (await serviceFor(source).export()).path;
      await source.close();

      final target = AppDatabase(
        factory: databaseFactoryFfi,
        path: pathFor('doble_target.db'),
      );
      addTearDown(target.close);
      final service = serviceFor(target);

      final first = await service.restore(backup);
      final second = await service.restore(backup);

      expect(first.restoredAttachments, 2);
      expect(second.restoredAttachments, 2);
      expect((await AgroRepository(target).purchases()), hasLength(2));
    });
  });
}
