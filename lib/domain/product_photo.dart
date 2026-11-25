import 'dart:io';

/// Foto vigente de un producto (E1-D10).
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
