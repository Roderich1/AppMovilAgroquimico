import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Foto de la etiqueta de un producto (E1-D10).
///
/// Vive en `<documentos>/product_photos/` y la base guarda la ruta
/// **relativa** a la carpeta de documentos, el SHA-256 del archivo y la fecha.
/// El archivo nunca es el que entregó la cámara o la galería: se decodifica,
/// se aplica la orientación, se reduce el lado mayor a [labelPhotoMaxSide] y
/// se vuelve a codificar como JPEG **sin metadatos** (ni EXIF, ni ubicación,
/// ni perfil de color, ni textos).
const String productPhotosFolder = 'product_photos';

/// Lado mayor máximo, en píxeles. Nunca se amplía una imagen menor.
const int labelPhotoMaxSide = 1600;

/// Calidad JPEG de la copia guardada.
const int labelPhotoJpegQuality = 82;

/// Tope de lo que se acepta decodificar: 60 megapíxeles o 40 MB de archivo.
/// Una foto de teléfono queda muy por debajo; un archivo mayor se rechaza
/// antes de reservar memoria para él.
const int _maxSourcePixels = 60 * 1000 * 1000;
const int _maxSourceBytes = 40 * 1024 * 1024;

/// Forma exacta de una ruta guardada: impide salir de la carpeta.
final RegExp _relativePhotoPath = RegExp(
  r'^product_photos/product_[0-9]+_[0-9a-f]{12}\.jpg$',
);

/// La imagen no se pudo leer o no es una imagen admitida.
class LabelPhotoFormatException implements Exception {
  const LabelPhotoFormatException();
  @override
  String toString() =>
      'No se pudo leer la imagen. Elija una foto JPEG o PNG de la etiqueta.';
}

/// Resultado del procesado: bytes JPEG sin metadatos y su huella.
class ProcessedLabelPhoto {
  const ProcessedLabelPhoto({
    required this.bytes,
    required this.sha256,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;

  /// SHA-256 en hexadecimal minúsculo de [bytes].
  final String sha256;
  final int width;
  final int height;
}

/// Procesa [source] según E1-D10. Es una función pura de nivel superior para
/// poder ejecutarla en otro isolate (`compute`).
ProcessedLabelPhoto processLabelPhoto(Uint8List source) {
  if (source.isEmpty || source.length > _maxSourceBytes) {
    throw const LabelPhotoFormatException();
  }
  final decoder = img.findDecoderForData(source);
  if (decoder == null) throw const LabelPhotoFormatException();
  final info = decoder.startDecode(source);
  if (info == null ||
      info.width <= 0 ||
      info.height <= 0 ||
      info.width * info.height > _maxSourcePixels) {
    throw const LabelPhotoFormatException();
  }
  final decoded = decoder.decode(source, frame: 0);
  if (decoded == null) throw const LabelPhotoFormatException();

  var image = img.bakeOrientation(decoded);
  final longest = image.width > image.height ? image.width : image.height;
  if (longest > labelPhotoMaxSide) {
    image = image.width >= image.height
        ? img.copyResize(
            image,
            width: labelPhotoMaxSide,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            image,
            height: labelPhotoMaxSide,
            interpolation: img.Interpolation.average,
          );
  }
  // El codificador JPEG escribe el EXIF y el perfil de color que traiga la
  // imagen: se vacían antes de codificar.
  image
    ..exif = img.ExifData()
    ..iccProfile = null
    ..textData = null;
  final bytes = img.encodeJpg(image, quality: labelPhotoJpegQuality);
  return ProcessedLabelPhoto(
    bytes: bytes,
    sha256: crypto.sha256.convert(bytes).toString(),
    width: image.width,
    height: image.height,
  );
}

/// Carpeta de documentos de la app (la base de las rutas relativas).
Future<Directory> resolveDocumentsDirectory() =>
    getApplicationDocumentsDirectory();

/// Ruta relativa del archivo de [productId] con huella [sha256].
String productPhotoRelativePath(int productId, String sha256) =>
    '$productPhotosFolder/product_${productId}_${sha256.substring(0, 12)}.jpg';

/// Archivo de una ruta guardada, o null si la ruta no tiene la forma exacta
/// (nunca se resuelve una ruta ajena a la carpeta de fotos).
File? productPhotoFile(Directory documents, String? relative) {
  if (relative == null || !_relativePhotoPath.hasMatch(relative)) return null;
  return File(p.joinAll([documents.path, ...relative.split('/')]));
}

/// Foto vigente de un producto.
class ProductPhoto {
  const ProductPhoto({
    required this.productId,
    required this.relativePath,
    required this.file,
    required this.sha256,
    required this.updatedAt,
    required this.exists,
  });

  final int productId;
  final String relativePath;
  final File file;
  final String sha256;
  final String? updatedAt;

  /// Falso si la base la registra pero el archivo ya no está (por ejemplo,
  /// tras restaurar un respaldo en otro teléfono).
  final bool exists;
}
