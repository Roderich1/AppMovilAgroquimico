// Soporte de pruebas de la identificación de productos (contrato E1). Datos
// sintéticos.
import 'dart:io';
import 'dart:typed_data';

import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/sync/identification_request_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'f05_sync_fixtures.dart';

/// Producto del sindicato con el que se identifica en las pruebas.
const identifiedRef = litreRef;

/// JPEG sintético con EXIF (fabricante).
Uint8List labelJpeg({int width = 900, int height = 600, int seed = 0}) {
  final image = img.Image(width: width + 16 * seed, height: height);
  img.fill(image, color: img.ColorRgb8((40 + 70 * seed) % 256, 90, 140));
  image.exif.imageIfd['Make'] = 'Telefono sintetico';
  return img.encodeJpg(image, quality: 90);
}

/// Carpeta temporal de documentos y repositorio que guarda allí las fotos.
class PhotoWorkspace {
  PhotoWorkspace(this.root, this.repo);
  final Directory root;
  final AgroRepository repo;

  Directory get documents => Directory(p.join(root.path, 'documentos'));

  /// Guarda una foto sintética para [productId] desde «la galería».
  Future<String> savePhoto(
    int productId, {
    int seed = 0,
    bool? shareWithUnion,
  }) async {
    final source = File(p.join(root.path, 'galeria', 'foto_$seed.jpg'));
    await source.parent.create(recursive: true);
    await source.writeAsBytes(labelJpeg(seed: seed));
    final photo = await repo.setProductPhoto(
      productId,
      source.path,
      shareWithUnion: shareWithUnion,
    );
    return photo.sha256;
  }
}

Future<PhotoWorkspace> photoWorkspace(SyncFixture fixture) async {
  final root = await Directory.systemTemp.createTemp('agro_e1_');
  addTearDown(() async {
    try {
      await root.delete(recursive: true);
    } on FileSystemException {
      // Temporal.
    }
  });
  final documents = Directory(p.join(root.path, 'documentos'));
  await documents.create(recursive: true);
  return PhotoWorkspace(
    root,
    AgroRepository(
      fixture.database,
      productPhotoDocuments: () async => documents,
    ),
  );
}

/// Vista de una solicitud tal como la devuelve el sindicato (E1 §4.1).
Map<String, Object?> serverView(
  String requestId, {
  String status = 'PENDING',
  String localName = 'Adherente local',
  String unit = 'L',
  String photoState = 'NONE',
  String? photoSha,
  String? consentVersion,
  bool linked = false,
  String productName = 'Herbicida central',
  String? note,
  Map<String, Object?> extra = const {},
}) => {
  'contractVersion': 1,
  'request_id': requestId,
  'status': linked ? 'LINKED' : status,
  'local_name': localName,
  'active_ingredient': null,
  'unit': unit,
  'base_unit': unit == 'L' ? 'ML' : 'G',
  'received_at': '2026-11-11T18:20:05.120Z',
  'updated_at': '2026-11-11T18:20:05.120Z',
  'photo': {
    'state': photoState,
    'sha256': photoSha,
    'consent_version': consentVersion,
  },
  'resolution': linked
      ? {
          'kind': 'LINKED_EXISTING',
          'product_ref': identifiedRef,
          'product_name': productName,
          'unit': unit,
          'base_unit': unit == 'L' ? 'ML' : 'G',
          'is_active': true,
          'resolved_at': '2026-11-12T09:00:00.000Z',
        }
      : null,
  'pending_note': note == null
      ? null
      : {'text': note, 'at': '2026-11-12T09:00:00.000Z'},
  ...extra,
};

/// Fila cruda de la solicitud de [productId].
Future<Map<String, Object?>> requestRow(
  SyncFixture fixture,
  int productId,
) async => (await (await fixture.database.database).query(
  IdentificationRequestStore.table,
  where: 'product_id=?',
  whereArgs: [productId],
)).single;
