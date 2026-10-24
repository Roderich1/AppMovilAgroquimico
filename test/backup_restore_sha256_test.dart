// F08-BKP-05 (#36) y la parte crítica de #55 (RNF-10): el manifiesto guarda el
// SHA-256 de `database.db`, pero la validación no lo contrastaba. Una base
// SQLite íntegra pero distinta de la respaldada pasaba `integrity_check` y se
// restauraba. La exportación atómica está en backup_export_atomic_test.dart.
//
// Las manipulaciones son reales: se abre la base de dentro del contenedor, se
// cambia una fila con SQL y se vuelve a empaquetar; el manifiesto queda como
// lo escribió la aplicación.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/backup_service.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'backup_container_support.dart';

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
    workspace = await Directory.systemTemp.createTemp('agro_sha_');
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

  Uint8List photoBytes(int seed) =>
      Uint8List.fromList(List<int>.generate(2048, (i) => (i * seed) % 251));

  Future<(AppDatabase, AgroRepository)> seeded(
    String name, {
    String person = 'Familiar',
    int photos = 1,
  }) async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      path: pathFor(name),
    );
    final repo = AgroRepository(database);
    final family = await repo.addPerson(name: person, role: PersonRole.family);
    final supplier = await repo.addSupplier(name: 'Proveedor');
    final campaign = await repo.addCampaign(
      name: 'Campaña',
      start: DateTime.utc(2026),
    );
    final product = await repo.addProduct(name: 'Glifosato');
    for (var index = 0; index < photos; index++) {
      final file = File(p.join(invoices.path, '${name}_$index.jpg'));
      await file.writeAsBytes(photoBytes(index + 1), flush: true);
      await repo.confirmPurchase(
        PurchaseDraft(
          supplierId: supplier,
          campaignId: campaign,
          purchaseDate: DateTime.utc(2026, 1, 10 + index),
          invoiceNumber: 'F-$index',
          invoiceImagePath: file.path,
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
    return (database, repo);
  }

  // Sólo la API que ya existía en la base caf158e: así esta regresión se
  // puede ejecutar también sobre el código anterior a la corrección (M5).
  BackupService serviceFor(AppDatabase database) =>
      BackupService(database, invoicesDir: () async => invoices);

  Map<String, Object?> manifestOf(String path) =>
      jsonDecode(utf8.decode(entryBytes(path, 'manifest.json')!))
          as Map<String, Object?>;

  Future<void> rewriteManifest(
    String path,
    void Function(Map<String, Object?> manifest) change,
  ) async {
    final manifest = manifestOf(path);
    change(manifest);
    await rewriteEntry(
      path,
      'manifest.json',
      utf8.encode(jsonEncode(manifest)),
    );
  }

  /// Exporta un respaldo de una base con «Respaldada» y lo deja cerrado.
  Future<String> exported() async {
    final (database, _) = await seeded('origen.db', person: 'Respaldada');
    final path = (await serviceFor(database).export()).path;
    await database.close();
    return path;
  }

  /// Cambia una fila de la base de dentro del contenedor con SQL real: la base
  /// resultante es SQLite íntegra y con todas las tablas; sólo difiere su
  /// contenido del que describe el manifiesto.
  Future<void> tamperDatabase(String container) async {
    final extracted = await extractDatabaseFrom(container);
    final raw = await databaseFactoryFfi.openDatabase(extracted);
    await raw.update(
      'persons',
      {'name': 'Alterada'},
      where: 'name=?',
      whereArgs: ['Respaldada'],
    );
    final check = await raw.rawQuery('PRAGMA integrity_check');
    expect(check.single.values.single, 'ok');
    await raw.close();
    await rewriteEntry(
      container,
      'database.db',
      await File(extracted).readAsBytes(),
    );
  }

  /// Fotografías actuales, por nombre y SHA-256.
  Future<Map<String, String>> photosNow() async => {
    await for (final entity in invoices.list())
      if (entity is File)
        p.basename(entity.path): sha256
            .convert(await entity.readAsBytes())
            .toString(),
  };

  group('SHA-256 de la base', () {
    test('una base alterada con SQL válido se rechaza al validar', () async {
      final path = await exported();
      final declared =
          (manifestOf(path)['database']! as Map<String, Object?>)['sha256'];
      await tamperDatabase(path);
      expect(
        sha256.convert(entryBytes(path, 'database.db')!).toString(),
        isNot(declared),
        reason: 'la manipulación debe cambiar los bytes de la base',
      );

      final probe = AppDatabase(
        factory: databaseFactoryFfi,
        path: pathFor('probe.db'),
      );
      addTearDown(probe.close);
      final validation = await serviceFor(probe).validate(path);
      expect(validation.isValid, isFalse);
      expect(validation.problem, contains('no coincide'));
    });

    test(
      'restaurar una base alterada no toca la base ni las fotos actuales',
      () async {
        final backup = await exported();
        await tamperDatabase(backup);

        final (current, repo) = await seeded('actual.db', person: 'Actual');
        addTearDown(current.close);
        final peopleBefore = await repo.people();
        final photosBefore = await photosNow();
        await current.close();
        final bytesBefore = await File(pathFor('actual.db')).readAsBytes();

        await expectLater(
          serviceFor(current).restore(backup),
          throwsA(
            isA<BackupException>().having(
              (e) => e.message,
              'message',
              contains('no coincide'),
            ),
          ),
        );

        // Ni siquiera se abrió para escribir: el archivo es el mismo.
        expect(await File(pathFor('actual.db')).readAsBytes(), bytesBefore);
        expect(await AgroRepository(current).people(), peopleBefore);
        expect(await photosNow(), photosBefore);
        final leftovers = workspace
            .listSync(recursive: true)
            .map((e) => p.basename(e.path))
            .where((name) => name.contains('.previo-'));
        expect(
          leftovers,
          isEmpty,
          reason: 'no se llegó a preparar el reemplazo',
        );
      },
    );

    test('un manifiesto sin SHA-256 de la base se rechaza', () async {
      final path = await exported();
      await rewriteManifest(path, (manifest) {
        (manifest['database']! as Map<String, Object?>).remove('sha256');
      });
      final probe = AppDatabase(
        factory: databaseFactoryFfi,
        path: pathFor('probe.db'),
      );
      addTearDown(probe.close);
      final validation = await serviceFor(probe).validate(path);
      expect(validation.isValid, isFalse);
    });

    test('un manifiesto sin descripción de la base se rechaza', () async {
      final path = await exported();
      await rewriteManifest(path, (manifest) => manifest.remove('database'));
      final probe = AppDatabase(
        factory: databaseFactoryFfi,
        path: pathFor('probe.db'),
      );
      addTearDown(probe.close);
      expect((await serviceFor(probe).validate(path)).isValid, isFalse);
    });

    test('un tamaño declarado distinto del real se rechaza', () async {
      final path = await exported();
      await rewriteManifest(path, (manifest) {
        final database = manifest['database']! as Map<String, Object?>;
        database['bytes'] = (database['bytes']! as int) + 1;
      });
      final probe = AppDatabase(
        factory: databaseFactoryFfi,
        path: pathFor('probe.db'),
      );
      addTearDown(probe.close);
      expect((await serviceFor(probe).validate(path)).isValid, isFalse);
    });

    test('el respaldo íntegro sigue siendo válido y restaurable', () async {
      final path = await exported();
      final (current, _) = await seeded('actual.db', person: 'Actual');
      addTearDown(current.close);
      final validation = await serviceFor(current).validate(path);
      expect(validation.isValid, isTrue);
      final result = await serviceFor(current).restore(path);
      expect(result.restoredAttachments, 1);
      final names = {
        for (final row in await AgroRepository(current).people()) row['name'],
      };
      expect(names, contains('Respaldada'));
      expect(names, isNot(contains('Actual')));
    });
  });

  group('fotografías del contenedor', () {
    test(
      'una fotografía no descrita en el manifiesto no se restaura',
      () async {
        final path = await exported();
        await addEntry(path, 'invoices/intrusa.jpg', photoBytes(9));
        expect(entriesOf(path), contains('invoices/intrusa.jpg'));
        final (current, _) = await seeded(
          'actual.db',
          person: 'Actual',
          photos: 0,
        );
        addTearDown(current.close);

        final result = await serviceFor(current).restore(path);

        expect(result.restoredAttachments, 1);
        expect(
          File(p.join(invoices.path, 'intrusa.jpg')).existsSync(),
          isFalse,
        );
      },
    );

    test('un nombre de fotografía con ruta se rechaza', () async {
      final path = await exported();
      await rewriteManifest(path, (manifest) {
        final attachments = manifest['attachments']! as List<Object?>;
        (attachments.single! as Map<String, Object?>)['name'] = '../fuera.jpg';
      });
      final probe = AppDatabase(
        factory: databaseFactoryFfi,
        path: pathFor('probe.db'),
      );
      addTearDown(probe.close);
      expect((await serviceFor(probe).validate(path)).isValid, isFalse);
    });
  });
}
