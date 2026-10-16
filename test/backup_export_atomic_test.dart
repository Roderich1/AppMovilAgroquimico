// F08 (#36, #55): una exportación interrumpida no deja nada que parezca un
// respaldo. El paquete validado se copia a `.part` en la carpeta de destino,
// se cotejan sus bytes y se renombra.
//
// Las manipulaciones son reales: se abre la base de dentro del contenedor, se
// cambia una fila con SQL y se vuelve a empaquetar; el manifiesto queda como
// lo escribió la aplicación.
import 'dart:io';
import 'dart:typed_data';

import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/backup_service.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';


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

  BackupService serviceFor(
    AppDatabase database, {
    Future<void> Function(File partial)? beforePublish,
  }) => BackupService(
    database,
    invoicesDir: () async => invoices,
    beforePublish: beforePublish,
  );

  group('exportación atómica', () {
    List<String> backupNames() => [
      for (final entity in workspace.listSync())
        if (entity is File &&
            p.basename(entity.path).startsWith('agroquimicos_backup_'))
          p.basename(entity.path),
    ];

    test('un fallo con el parcial ya escrito no deja ningún archivo', () async {
      final (database, _) = await seeded('origen.db');
      addTearDown(database.close);
      final previous = (await serviceFor(database).export()).path;
      final previousBytes = await File(previous).readAsBytes();

      int? partialBytes;
      await expectLater(
        serviceFor(
          database,
          beforePublish: (partial) async {
            partialBytes = await partial.length();
            // El disco se llena o la app se interrumpe a mitad de la copia.
            final handle = await partial.open(mode: FileMode.writeOnlyAppend);
            await handle.truncate(partialBytes! ~/ 2);
            await handle.close();
            throw const FileSystemException('Sin espacio (simulado)');
          },
        ).export(),
        throwsA(isA<FileSystemException>()),
      );

      expect(
        partialBytes,
        greaterThan(0),
        reason: 'el fallo fue tras escribir',
      );
      expect(backupNames(), [p.basename(previous)]);
      expect(await File(previous).readAsBytes(), previousBytes);
      final listed = await serviceFor(database).listAvailableBackups();
      expect(listed.map((f) => f.path), [previous]);
    });

    test('una copia truncada sin excepción no se publica', () async {
      final (database, _) = await seeded('origen.db');
      addTearDown(database.close);

      await expectLater(
        serviceFor(
          database,
          beforePublish: (partial) async {
            final handle = await partial.open(mode: FileMode.writeOnlyAppend);
            await handle.truncate(100);
            await handle.close();
          },
        ).export(),
        throwsA(isA<BackupException>()),
      );
      expect(backupNames(), isEmpty);
    });

    test('un parcial abandonado se descarta y nunca se lista', () async {
      final stale = File(
        pathFor('agroquimicos_backup_2026-01-01T00-00-00.agrobackup.part'),
      );
      await stale.writeAsBytes([1, 2, 3]);
      final (database, _) = await seeded('origen.db');
      addTearDown(database.close);
      final service = serviceFor(database);
      expect(await service.listAvailableBackups(), isEmpty);

      final exported = (await service.export()).path;

      expect(stale.existsSync(), isFalse);
      expect(backupNames(), [p.basename(exported)]);
      expect((await service.validate(exported)).isValid, isTrue);
    });
  });
}
