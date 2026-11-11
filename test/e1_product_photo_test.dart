// E1-D10 (contrato E1 §5.1): foto de la etiqueta de un producto.
//
// - El procesado aplica la orientación, reduce el lado mayor a ≤ 1600 px sin
//   ampliar nunca y codifica un JPEG sin metadatos: ningún segmento APP1
//   (EXIF, 0xFFE1) ni APP2 (perfil ICC).
// - El repositorio guarda la copia procesada en
//   `<documentos>/product_photos/product_<id>_<sha12>.jpg`, con la ruta
//   relativa, la huella y la fecha; reemplazar borra el archivo anterior y
//   quitar borra el archivo y deja las columnas en NULL.
//
// Las imágenes se generan en la prueba con el paquete `image`: sin binarios
// versionados ni datos reales.
import 'dart:io';
import 'dart:typed_data';

import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/product_photo_storage.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Marcadores de los segmentos de cabecera de un JPEG, hasta SOS.
List<int> jpegMarkers(Uint8List bytes) {
  expect(bytes[0], 0xFF);
  expect(bytes[1], 0xD8, reason: 'SOI');
  final markers = <int>[];
  var offset = 2;
  while (offset + 4 <= bytes.length) {
    expect(bytes[offset], 0xFF, reason: 'cabecera JPEG en $offset');
    final marker = bytes[offset + 1];
    markers.add(marker);
    if (marker == 0xDA) break; // SOS: empiezan los datos de la imagen.
    final length = (bytes[offset + 2] << 8) | bytes[offset + 3];
    offset += 2 + length;
  }
  return markers;
}

/// JPEG sintético con EXIF: orientación, fabricante y fecha.
Uint8List syntheticJpeg(int width, int height, {int orientation = 1}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(30, 120, 60));
  // Una franja en la mitad izquierda, para comprobar la rotación.
  img.fillRect(
    image,
    x1: 0,
    y1: 0,
    x2: width ~/ 4,
    y2: height,
    color: img.ColorRgb8(250, 250, 250),
  );
  image.exif.imageIfd.orientation = orientation;
  image.exif.imageIfd['Make'] = 'Telefono sintetico';
  image.exif.imageIfd['DateTime'] = '2026:11:11 10:00:00';
  return img.encodeJpg(image, quality: 90);
}

void main() {
  sqfliteFfiInit();

  group('processLabelPhoto', () {
    test('reduce a 1600 px, aplica la orientación y no deja EXIF (0xFFE1)', () {
      final source = syntheticJpeg(2400, 1200, orientation: 6);
      expect(
        jpegMarkers(source),
        contains(0xE1),
        reason: 'la fuente sí trae EXIF',
      );

      final processed = processLabelPhoto(source);

      expect(jpegMarkers(processed.bytes), isNot(contains(0xE1)));
      expect(jpegMarkers(processed.bytes), isNot(contains(0xE2)));
      // Tampoco el texto «Exif» en ninguna parte del archivo.
      expect(String.fromCharCodes(processed.bytes).contains('Exif'), isFalse);
      // Orientación 6 = girar 90°: 2400×1200 queda vertical, 800×1600.
      expect(processed.width, 800);
      expect(processed.height, 1600);
      final decoded = img.decodeJpg(processed.bytes)!;
      expect(decoded.width, 800);
      expect(decoded.height, 1600);
      expect(decoded.exif.isEmpty, isTrue);
      expect(
        processed.sha256,
        crypto.sha256.convert(processed.bytes).toString(),
      );
    });

    test('una imagen pequeña no se amplía', () {
      final processed = processLabelPhoto(syntheticJpeg(320, 200));
      expect((processed.width, processed.height), (320, 200));
      expect(jpegMarkers(processed.bytes), isNot(contains(0xE1)));
    });

    test('un PNG se acepta y sale como JPEG', () {
      final png = img.encodePng(img.Image(width: 1700, height: 1700));
      final processed = processLabelPhoto(png);
      expect((processed.width, processed.height), (1600, 1600));
      expect(processed.bytes.sublist(0, 3), [0xFF, 0xD8, 0xFF]);
    });

    test('lo que no es imagen se rechaza', () {
      expect(
        () =>
            processLabelPhoto(Uint8List.fromList('no es una imagen'.codeUnits)),
        throwsA(isA<LabelPhotoFormatException>()),
      );
      expect(
        () => processLabelPhoto(Uint8List(0)),
        throwsA(isA<LabelPhotoFormatException>()),
      );
    });
  });

  group('AgroRepository: foto de la etiqueta', () {
    late Directory workspace;
    late Directory documents;
    late AgroRepository repo;
    late int product;

    Future<String> picked(String name, Uint8List bytes) async {
      final file = File(p.join(workspace.path, 'galeria', name));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      return file.path;
    }

    Future<Map<String, Object?>> productRow() async =>
        (await (await repo.appDatabase.database).query(
          'products',
          columns: ['photo_path', 'photo_sha256', 'photo_updated_at'],
          where: 'id=?',
          whereArgs: [product],
        )).single;

    List<String> storedFiles() {
      final folder = Directory(p.join(documents.path, productPhotosFolder));
      if (!folder.existsSync()) return const [];
      return [for (final entity in folder.listSync()) p.basename(entity.path)]
        ..sort();
    }

    setUp(() async {
      workspace = await Directory.systemTemp.createTemp('agro_e1_photo_');
      documents = Directory(p.join(workspace.path, 'documentos'));
      await documents.create(recursive: true);
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      repo = AgroRepository(
        database,
        productPhotoDocuments: () async => documents,
      );
      product = await repo.addProduct(name: 'Glifosato sintético');
    });

    tearDown(() async {
      await repo.appDatabase.close();
      try {
        await workspace.delete(recursive: true);
      } on FileSystemException {
        // Temporal.
      }
    });

    test(
      'guarda la copia procesada con ruta relativa, huella y fecha',
      () async {
        final source = await picked('etiqueta.jpg', syntheticJpeg(3000, 2000));
        final photo = await repo.setProductPhoto(product, source);

        final row = await productRow();
        final sha = row['photo_sha256']! as String;
        expect(
          row['photo_path'],
          'product_photos/product_${product}_${sha.substring(0, 12)}.jpg',
        );
        expect(row['photo_updated_at'], isNotNull);
        expect(photo.exists, isTrue);
        expect(photo.sha256, sha);
        final stored = await photo.file.readAsBytes();
        expect(crypto.sha256.convert(stored).toString(), sha);
        expect(jpegMarkers(stored), isNot(contains(0xE1)));
        final decoded = img.decodeJpg(stored)!;
        expect((decoded.width, decoded.height), (1600, 1067));
        // La original de la galería no se toca.
        expect(File(source).existsSync(), isTrue);
        expect(storedFiles(), [
          'product_${product}_${sha.substring(0, 12)}.jpg',
        ]);
      },
    );

    test('reemplazar borra el archivo anterior', () async {
      await repo.setProductPhoto(
        product,
        await picked('a.jpg', syntheticJpeg(800, 600)),
      );
      final first = (await productRow())['photo_path']! as String;
      await repo.setProductPhoto(
        product,
        await picked(
          'b.png',
          img.encodePng(img.Image(width: 640, height: 480)),
        ),
      );
      final second = (await productRow())['photo_path']! as String;
      expect(second, isNot(first));
      expect(storedFiles(), [p.basename(second)]);
    });

    test('quitar borra el archivo y deja las columnas en NULL', () async {
      await repo.setProductPhoto(
        product,
        await picked('a.jpg', syntheticJpeg(800, 600)),
      );
      expect(storedFiles(), hasLength(1));
      await repo.removeProductPhoto(product);
      expect(await productRow(), {
        'photo_path': null,
        'photo_sha256': null,
        'photo_updated_at': null,
      });
      expect(storedFiles(), isEmpty);
      expect(await repo.productPhoto(product), isNull);
    });

    test(
      'una imagen ilegible no cambia nada y lo dice sin rutas ni datos',
      () async {
        await repo.setProductPhoto(
          product,
          await picked('a.jpg', syntheticJpeg(800, 600)),
        );
        final before = await productRow();
        final broken = await picked(
          'roto.jpg',
          Uint8List.fromList(List.filled(64, 7)),
        );
        await expectLater(
          repo.setProductPhoto(product, broken),
          throwsA(
            isA<BusinessRuleException>().having(
              (error) => error.message,
              'message',
              allOf(isNot(contains(broken)), isNot(contains('galeria'))),
            ),
          ),
        );
        expect(await productRow(), before);
        expect(storedFiles(), hasLength(1));
      },
    );

    test('si el archivo ya no está, la foto figura como ausente', () async {
      final photo = await repo.setProductPhoto(
        product,
        await picked('a.jpg', syntheticJpeg(800, 600)),
      );
      await photo.file.delete();
      final again = await repo.productPhoto(product);
      expect(again, isNotNull);
      expect(again!.exists, isFalse);
    });

    test('las compras, aplicaciones e inventario no cambian', () async {
      final db = await repo.appDatabase.database;
      Future<Map<String, int>> counts() async => {
        for (final table in [
          'purchases',
          'purchase_items',
          'applications',
          'application_items',
          'inventory_lots',
          'inventory_movements',
        ])
          table:
              (await db.rawQuery('SELECT COUNT(*) AS c FROM $table'))
                      .single['c']!
                  as int,
      };
      final before = await counts();
      await repo.setProductPhoto(
        product,
        await picked('a.jpg', syntheticJpeg(800, 600)),
      );
      await repo.removeProductPhoto(product);
      expect(await counts(), before);
    });
  });
}
