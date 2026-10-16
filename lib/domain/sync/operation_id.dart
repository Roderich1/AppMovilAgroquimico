import 'dart:math';

/// UUID v4 en minúsculas (RFC 9562) para identificar una intención de
/// sincronización (contrato F05 §5). Se genera **una sola vez**, al confirmar
/// la intención, y se persiste con ella: un reintento, un reinicio o un
/// refresh reutilizan el mismo valor. Nunca se deriva de la fecha, la
/// cantidad, un entero de SQLite, el hardware ni el installationClientId.
String newOperationId([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => source.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // versión 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variante 10
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Forma exacta que admite Central para `operationId` y referencias causales.
final RegExp uuidV4Lowercase = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

/// Referencias centrales (`campaign_ref`, `product_ref`): UUID canónico en
/// minúsculas de cualquier versión.
final RegExp canonicalUuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
