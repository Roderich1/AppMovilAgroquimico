import 'dart:convert';

import '../../domain/estimation/farmer_estimation.dart';
import '../auth/auth_api_exception.dart';
import '../auth/auth_http_client.dart';

/// Fallo de una consulta de la estimación. [statusCode] es null sin
/// respuesta HTTP (sin conexión o tiempo agotado).
class EstimationQueryException implements Exception {
  const EstimationQueryException(this.statusCode, this.errorCode);
  final int? statusCode;
  final String? errorCode;

  bool get unreachable => statusCode == null;
  bool get sessionRejected => statusCode == 401;
  bool get forbidden => statusCode == 403;
  bool get policyPending => statusCode == 409 && errorCode == 'POLICY_PENDING';
  bool get notFound => statusCode == 404;

  /// La respuesta llegó pero no es del perfil FARMER o no tiene su forma.
  bool get invalidResponse => statusCode == 200;

  @override
  String toString() => 'EstimationQueryException($statusCode, $errorCode)';
}

/// Resultado de una descarga: lo validado y el cuerpo tal como llegó, que es
/// lo que se guarda.
class FarmerDownloadResponse {
  const FarmerDownloadResponse(this.download, this.payload);
  final FarmerDownload download;
  final Map<String, Object?> payload;
}

/// `GET /api/v1/estimation/results` y `/download` (INT-09 v1) con el access
/// token V2 de la instalación. No registra cuerpos, cifras ni credenciales.
class EstimationApi {
  EstimationApi(this._http);

  final AuthHttpClient _http;

  static const _resultsPath = '/api/v1/estimation/results';
  static const _downloadPath = '/api/v1/estimation/download';

  Future<FarmerResults> results(String campaignRef, String accessToken) async {
    final body = await _get(_resultsPath, campaignRef, accessToken);
    try {
      return FarmerResults.fromJson(body);
    } on FarmerEstimationFormatException {
      throw const EstimationQueryException(200, 'INVALID_RESPONSE');
    }
  }

  Future<FarmerDownloadResponse> download(
    String campaignRef,
    String accessToken,
  ) async {
    final body = await _get(_downloadPath, campaignRef, accessToken);
    try {
      final download = FarmerDownload.fromJson(body);
      return FarmerDownloadResponse(download, body as Map<String, Object?>);
    } on FarmerEstimationFormatException {
      throw const EstimationQueryException(200, 'INVALID_RESPONSE');
    }
  }

  Future<Object?> _get(
    String path,
    String campaignRef,
    String accessToken,
  ) async {
    final AuthHttpResponse response;
    try {
      response = await _http.request(
        'GET',
        path,
        accessToken: accessToken,
        query: {'target_campaign_ref': campaignRef},
      );
    } on AuthApiException catch (error) {
      if (error.kind == AuthApiErrorKind.configuration) {
        throw const EstimationQueryException(null, 'CONFIGURATION');
      }
      throw const EstimationQueryException(null, 'UNAVAILABLE');
    }
    final body = _decode(response.bodyBytes);
    if (response.statusCode != 200) {
      final message = body is Map<String, Object?> ? body['message'] : null;
      throw EstimationQueryException(
        response.statusCode,
        message is String ? message : null,
      );
    }
    return body;
  }

  static Object? _decode(List<int> bytes) {
    try {
      return jsonDecode(utf8.decode(bytes));
    } on FormatException {
      return null;
    }
  }
}
