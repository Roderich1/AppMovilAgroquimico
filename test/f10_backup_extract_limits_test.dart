// Límites de recursos al abrir un contenedor `.agrobackup` (F10, #36 y #55).
//
// Sobre `ca74514` el contenedor se abría con `ZipDecoder` de `archive`, que
// descomprime cada entrada entera en memoria y la escribe después, sin
// límite: un archivo de cientos de KB podía expandirse a cientos de MB en
// memoria y en la carpeta temporal antes de que la validación lo rechazara.
// Además, las rutas sólo se filtraban contra `..` y rutas absolutas.
//
// Aquí se prueba el lector acotado: límites comprobados antes de extraer
// (directorio central) y durante (bytes que salen del descompresor), rutas
// con la forma del contenedor, limpieza de temporales y rechazo sin tocar la
// base ni las fotos actuales.
import 'dart:io';

import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/backup_service.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'backup_container_support.dart';
import 'support/f04_mode_fixtures.dart';
import 'support/raw_zip.dart';

typedef _Dump = Map<String, List<Map<String, Object?>>>;

void main() {
  sqfliteFfiInit();

  late Directory workspace;
  late Directory tempRoot;
  late Directory invoices;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('agro_f10_zip_');
    tempRoot = await Directory(p.join(workspace.path, 'tmp')).create();
    invoices = await Directory(p.join(workspace.path, 'invoices')).create();
  });
  tearDown(() async {
    try {
      await workspace.delete(recursive: true);
    } on FileSystemException {
      // En Windows el motor puede retener un archivo; es temporal.
    }
  });

  /// Ejecuta [body] con la carpeta temporal del sistema redirigida a
  /// [tempRoot], para comprobar que no quedan extracciones a medias.
  Future<T> inTemp<T>(Future<T> Function() body) =>
      IOOverrides.runZoned(body, getSystemTempDirectory: () => tempRoot);

  List<String> leftovers() => [
    for (final entity in tempRoot.listSync())
      if (p.basename(entity.path).startsWith('agro_backup_')) entity.path,
  ];

  List<int> photo(int seed) =>
      List<int>.generate(4096, (i) => (i * 7 + seed * 13) % 256);

  Future<Household> seed(
    AppDatabase database,
    Directory folder,
    String product,
    int photos,
  ) async {
    final household = await seedHousehold(AgroRepository(database));
    await household.repo.addProduct(name: product);
    for (var i = 0; i < photos; i++) {
      final file = File(p.join(folder.path, '${product}_$i.jpg'));
      await file.writeAsBytes(photo(i + product.length), flush: true);
      await household.repo.confirmPurchase(
        PurchaseDraft(
          supplierId: household.supplier,
          campaignId: household.campaign,
          purchaseDate: DateTime.utc(2026, 1, 10 + i),
          invoiceNumber: '$product-$i',
          invoiceImagePath: file.path,
          items: [
            PurchaseItemDraft(
              productId: household.product,
              quantityBase: 1000,
              currency: CurrencyCode.bob,
              originalUnitPriceMinor: 10000,
              allocations: [
                AllocationDraft(
                  personId: household.titular,
                  quantityBase: 1000,
                ),
              ],
            ),
          ],
        ),
      );
    }
    return household;
  }

  /// Contenedor válido exportado por la aplicación, con [photos] fotos.
  Future<String> validContainer({int photos = 3}) async {
    final directory = await Directory(p.join(workspace.path, 'origen'))
        .create();
    final folder = await Directory(p.join(directory.path, 'fotos')).create();
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      path: p.join(directory.path, 'origen.db'),
    );
    await seed(database, folder, 'Respaldo', photos);
    final result = await BackupService(
      database,
      invoicesDir: () async => folder,
      exportDirectory: () async =>
          Directory(p.join(workspace.path, 'exportados')),
    ).export();
    await database.close();
    return result.path;
  }

  /// Base actual con una foto, y su servicio con [limits].
  Future<(AppDatabase, BackupService)> current({
    BackupExtractionLimits limits = BackupExtractionLimits.standard,
  }) async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      path: p.join(workspace.path, 'actual.db'),
    );
    addTearDown(database.close);
    await seed(database, invoices, 'Actual', 1);
    return (
      database,
      BackupService(
        database,
        invoicesDir: () async => invoices,
        extractionLimits: limits,
      ),
    );
  }

  Map<String, String> photosIn(Directory folder) => {
    for (final entity in folder.listSync())
      if (entity is File)
        p.basename(entity.path): sha256
            .convert(entity.readAsBytesSync())
            .toString(),
  };

  Future<_Dump> dump(AppDatabase database) async =>
      dumpTables(await database.database);

  /// Valida y restaura [path]; comprueba que se rechaza con [message] sin
  /// tocar la base ni las fotos y sin dejar temporales.
  Future<void> expectRejectedUntouched(
    AppDatabase database,
    BackupService service,
    String path,
    String message,
  ) async {
    final before = await dump(database);
    final photosBefore = photosIn(invoices);
    final validation = await inTemp(() => service.validate(path));
    expect(validation.isValid, isFalse);
    expect(validation.problem, contains(message));
    await inTemp(
      () => expectLater(
        service.restore(path),
        throwsA(
          isA<BackupException>().having(
            (e) => e.message,
            'message',
            contains(message),
          ),
        ),
      ),
    );
    expect(await dump(database), before);
    expect(photosIn(invoices), photosBefore);
    expect(leftovers(), isEmpty, reason: 'sin extracciones a medias');
    expect(
      workspace.listSync().where(
        (e) => p.basename(e.path).contains('.previo-'),
      ),
      isEmpty,
      reason: 'el rechazo llega antes de preparar la sustitución',
    );
  }

  /// Manifiesto y base de un contenedor válido, para armar variantes.
  Future<(List<int>, List<int>)> validParts() async {
    final path = await validContainer(photos: 0);
    return (
      entryBytes(path, 'manifest.json')!,
      entryBytes(path, 'database.db')!,
    );
  }

  const tooLarge = 'supera los límites';
  const forbidden = 'rutas no permitidas';
  const malformed = 'dañado o no tiene el formato esperado';

  group('bomba de descompresión', () {
    // 300 MiB de ceros caben en unos 300 KB de deflate.
    late List<int> bomb;
    setUpAll(() => bomb = deflatedZeros(300));

    test(
      'la cabecera declara la expansión real: se rechaza antes de extraer',
      () async {
        expect(bomb.length, lessThan(1024 * 1024));
        final (manifest, _) = await validParts();
        final path = p.join(workspace.path, 'bomba_honesta.agrobackup');
        await writeRawZip(path, [
          RawZipEntry('manifest.json', data: manifest),
          RawZipEntry(
            'database.db',
            compressed: bomb,
            declaredSize: 300 * 1024 * 1024,
            crc32: 0,
          ),
        ]);
        final (database, service) = await current();
        await expectRejectedUntouched(database, service, path, tooLarge);
      },
    );

    test('la cabecera miente (1000 bytes): se corta durante la extracción, sin '
        'expandirla en memoria', () async {
      final (manifest, _) = await validParts();
      final path = p.join(workspace.path, 'bomba_mentirosa.agrobackup');
      await writeRawZip(path, [
        RawZipEntry('manifest.json', data: manifest),
        RawZipEntry(
          'database.db',
          compressed: bomb,
          declaredSize: 1000,
          crc32: 0,
        ),
      ]);
      final (database, service) = await current();
      final peakBefore = ProcessInfo.maxRss;
      await expectRejectedUntouched(database, service, path, tooLarge);
      final growth = ProcessInfo.maxRss - peakBefore;
      expect(
        growth,
        lessThan(128 * 1024 * 1024),
        reason:
            'el pico de memoria no debe crecer con la expansión '
            '(creció ${growth ~/ (1024 * 1024)} MiB)',
      );
    });
  });

  group('contenedor válido cercano a los límites', () {
    test('con los límites exactos se valida y se restaura; con uno menos en '
        'cualquiera de ellos se rechaza sin tocar nada', () async {
      final path = await validContainer();
      final input = InputFileStream(path);
      final List<ArchiveFile> files;
      try {
        files = ZipDecoder().decodeStream(input).files.toList();
      } finally {
        input.closeSync();
      }
      final entries = files.length;
      final total = files.fold<int>(0, (sum, f) => sum + f.size);
      final largest = files.fold<int>(
        0,
        (max, f) => f.size > max ? f.size : max,
      );
      final container = File(path).lengthSync();
      expect(entries, 5, reason: 'manifiesto, base y 3 fotos');

      BackupExtractionLimits exact({
        int dEntries = 0,
        int dEntry = 0,
        int dTotal = 0,
        int dContainer = 0,
      }) => BackupExtractionLimits(
        maxEntries: entries - dEntries,
        maxEntryBytes: largest - dEntry,
        maxTotalBytes: total - dTotal,
        maxContainerBytes: container - dContainer,
      );

      for (final (limits, message) in [
        (exact(dEntries: 1), 'más archivos'),
        (exact(dEntry: 1), tooLarge),
        (exact(dTotal: 1), tooLarge),
        (exact(dContainer: 1), tooLarge),
      ]) {
        final database = AppDatabase(
          factory: databaseFactoryFfi,
          path: p.join(workspace.path, 'actual_${limits.hashCode}.db'),
        );
        addTearDown(database.close);
        await seed(database, invoices, 'Actual', 0);
        await expectRejectedUntouched(
          database,
          BackupService(
            database,
            invoicesDir: () async => invoices,
            extractionLimits: limits,
          ),
          path,
          message,
        );
      }

      final (database, _) = await current();
      final service = BackupService(
        database,
        invoicesDir: () async => invoices,
        extractionLimits: exact(),
      );
      final validation = await inTemp(() => service.validate(path));
      expect(validation.isValid, isTrue, reason: validation.problem);
      expect(validation.attachmentCount, 3);
      final result = await inTemp(() => service.restore(path));
      expect(result.restoredAttachments, 3);
      expect({
        for (final row in await AgroRepository(database).products())
          row['name'],
      }, contains('Respaldo'));
      expect(leftovers(), isEmpty);
    });

    test('los límites por defecto admiten un contenedor normal', () async {
      final path = await validContainer();
      final (_, service) = await current();
      final validation = await inTemp(() => service.validate(path));
      expect(validation.isValid, isTrue, reason: validation.problem);
    });
  });

  group('rutas y forma del contenedor', () {
    for (final (name, why) in [
      ('../fuera.jpg', 'sale de la carpeta'),
      ('invoices/../../fuera.jpg', 'sale de la carpeta'),
      ('/absoluta.jpg', 'absoluta'),
      (r'invoices\fuera.jpg', 'separador de Windows'),
      ('C:fuera.jpg', 'unidad de Windows'),
      ('invoices/sub/foto.jpg', 'más de un nivel'),
      ('otros/foto.jpg', 'fuera de invoices'),
      ('notas.txt', 'archivo ajeno al contenedor'),
      ('invoices/..', 'segmento ..'),
      ('invoices/a\u0001.jpg', 'carácter de control'),
      ('invoices/${'x' * 260}.jpg', 'nombre demasiado largo'),
    ]) {
      test(
        'rechaza «${name.length > 40 ? '${name.substring(0, 40)}…' : name}» ($why)',
        () async {
          final (manifest, db) = await validParts();
          final path = p.join(workspace.path, 'ruta.agrobackup');
          await writeRawZip(path, [
            RawZipEntry('manifest.json', data: manifest),
            RawZipEntry('database.db', data: db),
            RawZipEntry(name, data: photo(1)),
          ]);
          final (database, service) = await current();
          await expectRejectedUntouched(database, service, path, forbidden);
          expect(
            File(p.join(workspace.path, 'fuera.jpg')).existsSync(),
            isFalse,
          );
          expect(
            File(p.join(tempRoot.path, 'fuera.jpg')).existsSync(),
            isFalse,
          );
        },
      );
    }

    for (final (names, why) in [
      (['database.db', 'database.db'], 'entrada repetida'),
      (['invoices/a.jpg', 'invoices/A.jpg'], 'repetida salvo mayúsculas'),
    ]) {
      test('rechaza $why', () async {
        final (manifest, db) = await validParts();
        final path = p.join(workspace.path, 'repetida.agrobackup');
        await writeRawZip(path, [
          RawZipEntry('manifest.json', data: manifest),
          if (!names.contains('database.db'))
            RawZipEntry('database.db', data: db),
          for (final name in names) RawZipEntry(name, data: db),
        ]);
        final (database, service) = await current();
        await expectRejectedUntouched(database, service, path, forbidden);
      });
    }

    test('rechaza un enlace simbólico', () async {
      final (manifest, db) = await validParts();
      final path = p.join(workspace.path, 'enlace.agrobackup');
      await writeRawZip(path, [
        RawZipEntry('manifest.json', data: manifest),
        RawZipEntry('database.db', data: db),
        RawZipEntry(
          'invoices/enlace.jpg',
          data: '/data/data/otra.app/databases/x.db'.codeUnits,
          madeBy: 3 << 8 | 20,
          externalAttributes: 0xA1FF << 16,
        ),
      ]);
      final (database, service) = await current();
      await expectRejectedUntouched(database, service, path, forbidden);
    });
  });

  group('integridad del ZIP', () {
    Future<void> rejected(
      List<RawZipEntry> Function(List<int>, List<int>) build,
    ) async {
      final (manifest, db) = await validParts();
      final path = p.join(workspace.path, 'danado.agrobackup');
      await writeRawZip(path, build(manifest, db));
      final (database, service) = await current();
      await expectRejectedUntouched(database, service, path, malformed);
    }

    test(
      'CRC del manifiesto que no coincide',
      () => rejected(
        (manifest, db) => [
          RawZipEntry('manifest.json', data: manifest, crc32: 1234),
          RawZipEntry('database.db', data: db),
        ],
      ),
    );

    test(
      'la expansión real es menor que la declarada',
      () => rejected(
        (manifest, db) => [
          RawZipEntry('manifest.json', data: manifest),
          RawZipEntry('database.db', data: db, declaredSize: db.length + 10),
        ],
      ),
    );

    test(
      'entrada guardada con tamaño comprimido distinto del declarado',
      () => rejected(
        (manifest, db) => [
          RawZipEntry('manifest.json', data: manifest),
          RawZipEntry(
            'database.db',
            data: db,
            deflate: false,
            declaredSize: db.length - 1,
          ),
        ],
      ),
    );

    test(
      'datos deflate truncados',
      () => rejected((manifest, db) {
        final full = rawDeflate(db);
        return [
          RawZipEntry('manifest.json', data: manifest),
          RawZipEntry(
            'database.db',
            data: db,
            compressed: full.sublist(0, full.length ~/ 2),
          ),
        ];
      }),
    );

    test(
      'entrada cifrada',
      () => rejected(
        (manifest, db) => [
          RawZipEntry('manifest.json', data: manifest),
          RawZipEntry('database.db', data: db, flags: 0x0801),
        ],
      ),
    );

    test(
      'método de compresión no admitido (bzip2)',
      () => rejected(
        (manifest, db) => [
          RawZipEntry('manifest.json', data: manifest),
          RawZipEntry('database.db', data: db, method: 12),
        ],
      ),
    );

    test(
      'marcadores ZIP64',
      () => rejected(
        (manifest, db) => [
          RawZipEntry('manifest.json', data: manifest),
          RawZipEntry('database.db', data: db, forceZip64Marker: true),
        ],
      ),
    );

    test('archivo que no es un ZIP aunque empiece por PK', () async {
      final path = p.join(workspace.path, 'pk.agrobackup');
      await File(path).writeAsBytes([0x50, 0x4B, 1, 2, 3, 4, 5], flush: true);
      final (database, service) = await current();
      await expectRejectedUntouched(database, service, path, malformed);
    });
  });
}
