import '../repository_exceptions.dart' show BusinessRuleException;

abstract final class IdentificationSendStatus {
  static const pendingSend = 'PENDING_SEND';
  static const received = 'RECEIVED';
  static const rejected = 'REJECTED';
  static const authPaused = 'AUTH_PAUSED';
}

/// Estados de envío de la foto de una solicitud (E1 §5).
abstract final class IdentificationPhotoStatus {
  static const none = 'NONE';
  static const pendingSend = 'PENDING_SEND';
  static const sent = 'SENT';
  static const failed = 'FAILED';
  static const removePending = 'REMOVE_PENDING';
  static const removed = 'REMOVED';
}

class IdentificationRequestException extends BusinessRuleException {
  IdentificationRequestException(super.message);
}

/// Una solicitud de identificación guardada en el teléfono.
class IdentificationRequest {
  const IdentificationRequest({
    required this.requestId,
    required this.productId,
    required this.tenantId,
    required this.sentName,
    required this.sentActiveIngredient,
    required this.sentUnit,
    required this.photoConsentVersion,
    required this.photoConsentAt,
    required this.photoSha256Consented,
    required this.sendStatus,
    required this.sendAttempts,
    required this.nextAttemptAt,
    required this.lastCode,
    required this.photoSendStatus,
    required this.photoAttempts,
    required this.photoNextAttemptAt,
    required this.photoLastCode,
    required this.serverStatus,
    required this.serverProductRef,
    required this.serverProductName,
    required this.serverProductUnit,
    required this.serverResolution,
    required this.serverNote,
    required this.serverCheckedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String requestId;
  final int productId;
  final String tenantId;
  final String sentName;
  final String? sentActiveIngredient;
  final String sentUnit;
  final String? photoConsentVersion;
  final String? photoConsentAt;
  final String? photoSha256Consented;
  final String sendStatus;
  final int sendAttempts;
  final String? nextAttemptAt;
  final String? lastCode;
  final String photoSendStatus;
  final int photoAttempts;
  final String? photoNextAttemptAt;
  final String? photoLastCode;
  final String? serverStatus;
  final String? serverProductRef;
  final String? serverProductName;
  final String? serverProductUnit;
  final String? serverResolution;
  final String? serverNote;
  final String? serverCheckedAt;
  final String createdAt;
  final String updatedAt;

  bool get isLinked =>
      serverStatus == 'LINKED' &&
      serverProductRef != null &&
      serverProductName != null;

  /// Un fallo de la foto que se reintentará (con fecha de reintento); sin
  /// ella, el fallo es definitivo.
  bool get photoRetryable =>
      photoSendStatus == IdentificationPhotoStatus.failed &&
      photoNextAttemptAt != null;

  /// La foto compartida con el sindicato (o por compartir): reemplazarla
  /// vuelve a preguntar si se envía la nueva (E1-D11).
  bool get photoShared => const {
    IdentificationPhotoStatus.pendingSend,
    IdentificationPhotoStatus.sent,
    IdentificationPhotoStatus.failed,
    IdentificationPhotoStatus.removePending,
    IdentificationPhotoStatus.removed,
  }.contains(photoSendStatus);

  static IdentificationRequest fromRow(
    Map<String, Object?> row, [
    String prefix = '',
  ]) => IdentificationRequest(
    requestId: row['${prefix}request_id']! as String,
    productId: row['${prefix}product_id']! as int,
    tenantId: row['${prefix}tenant_id']! as String,
    sentName: row['${prefix}sent_name']! as String,
    sentActiveIngredient: row['${prefix}sent_active_ingredient'] as String?,
    sentUnit: row['${prefix}sent_unit']! as String,
    photoConsentVersion: row['${prefix}photo_consent_version'] as String?,
    photoConsentAt: row['${prefix}photo_consent_at'] as String?,
    photoSha256Consented: row['${prefix}photo_sha256_consented'] as String?,
    sendStatus: row['${prefix}send_status']! as String,
    sendAttempts: row['${prefix}send_attempts']! as int,
    nextAttemptAt: row['${prefix}next_attempt_at'] as String?,
    lastCode: row['${prefix}last_code'] as String?,
    photoSendStatus: row['${prefix}photo_send_status']! as String,
    photoAttempts: row['${prefix}photo_attempts']! as int,
    photoNextAttemptAt: row['${prefix}photo_next_attempt_at'] as String?,
    photoLastCode: row['${prefix}photo_last_code'] as String?,
    serverStatus: row['${prefix}server_status'] as String?,
    serverProductRef: row['${prefix}server_product_ref'] as String?,
    serverProductName: row['${prefix}server_product_name'] as String?,
    serverProductUnit: row['${prefix}server_product_unit'] as String?,
    serverResolution: row['${prefix}server_resolution'] as String?,
    serverNote: row['${prefix}server_note'] as String?,
    serverCheckedAt: row['${prefix}server_checked_at'] as String?,
    createdAt: row['${prefix}created_at']! as String,
    updatedAt: row['${prefix}updated_at']! as String,
  );
}

/// Un producto local activo con su solicitud, si la tiene.
class ProductWithRequest {
  const ProductWithRequest(this.product, this.request);

  /// Las columnas de `products`, como `AgroRepository.products()`.
  final Map<String, Object?> product;
  final IdentificationRequest? request;
}

/// Contrato de solicitudes de identificación para la presentación.
abstract interface class IdentificationGateway {
  Future<IdentificationRequest> create({
    required int productId,
    required bool sharePhoto,
  });
  Future<IdentificationRequest?> byProduct(int productId);
  Future<List<ProductWithRequest>> productsWithRequests();
}
