// Cliente de las rutas del agricultor de la identificación de productos
// (contrato E1 §4.1): `/api/v1/catalog/identification-requests`.
//
// No es Sync v1 (E1-D2): no toca la outbox ni el envelope F05/F06. No
// registra cuerpos, fotos, huellas ni credenciales.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../auth/api_endpoint_config.dart';
import '../auth/auth_api_exception.dart';
import '../auth/auth_http_client.dart';
import '../../domain/sync/sync_wire.dart' show parseRetryAfter;

/// Respuesta de una llamada, ya sin encabezados ni cuerpo crudo de error.
class IdentificationResponse {
  const IdentificationResponse({
    this.statusCode,
    this.body,
    this.errorCode,
    this.retryAfter,
    this.transportCode,
  });

  /// Null si no hubo respuesta HTTP (red, plazo, transporte).
  final int? statusCode;

  /// JSON decodificado de una respuesta 2xx; null si no era JSON.
  final Object? body;

  /// `errorCode` de una respuesta de error, si tiene la forma esperada.
  final String? errorCode;

  /// Demora pedida por el servidor (429/503), si la hay.
  final Duration? retryAfter;

  /// `TIMEOUT`, `NETWORK` o `TRANSPORT` cuando no hubo respuesta.
  final String? transportCode;

  bool get ok => statusCode != null && statusCode! >= 200 && statusCode! < 300;
}

class IdentificationApi {
  IdentificationApi({
    required AuthHttpClient json,
    required ApiEndpointConfig config,
    required http.Client client,
    this.uploadTimeout = const Duration(minutes: 2),
    DateTime Function()? clock,
  }) : _json = json,
       _config = config,
       _client = client,
       _clock = clock ?? DateTime.now;

  final AuthHttpClient _json;
  final ApiEndpointConfig _config;
  final http.Client _client;
  final Duration uploadTimeout;
  final DateTime Function() _clock;

  static const basePath = '/api/v1/catalog/identification-requests';
  static final _errorCode = RegExp(r'^[A-Z][A-Z0-9_]{0,63}$');

  static String requestPath(String requestId) => '$basePath/$requestId';
  static String photoPath(String requestId) => '$basePath/$requestId/photo';

  /// `PUT /{request_id}`: crea o reenvía la solicitud (idempotente).
  Future<IdentificationResponse> upsert(
    String requestId,
    Map<String, Object?> body,
    String accessToken,
  ) => _jsonCall('PUT', requestPath(requestId), accessToken, body: body);

  /// `GET /`: solicitudes propias.
  Future<IdentificationResponse> listOwn(String accessToken) =>
      _jsonCall('GET', basePath, accessToken);

  /// `DELETE /{request_id}/photo`: retira la foto (idempotente).
  Future<IdentificationResponse> deletePhoto(
    String requestId,
    String accessToken,
  ) => _jsonCall('DELETE', photoPath(requestId), accessToken);

  /// `PUT /{request_id}/photo`: sube [file] en streaming como
  /// `application/octet-stream`, con `Content-Length` y `X-Content-SHA256`.
  Future<IdentificationResponse> uploadPhoto(
    String requestId,
    File file,
    String sha256,
    String accessToken,
  ) async {
    final Uri url;
    try {
      url = _config.endpoint(photoPath(requestId));
    } on AuthApiException {
      return const IdentificationResponse(transportCode: 'TRANSPORT');
    }
    final abort = Completer<void>();
    final timer = Timer(uploadTimeout, () {
      if (!abort.isCompleted) abort.complete();
    });
    try {
      final size = await file.length();
      final request =
          http.AbortableStreamedRequest('PUT', url, abortTrigger: abort.future)
            ..followRedirects = false
            ..contentLength = size
            ..headers.addAll({
              'Content-Type': 'application/octet-stream',
              'X-Content-SHA256': sha256,
              'Accept': 'application/json',
              'Authorization': 'Bearer $accessToken',
            });
      unawaited(
        file.openRead().pipe(request.sink).catchError((Object _) {
          // El envío falla por su lado; la respuesta (o su ausencia) decide.
        }),
      );
      final response = await http.Response.fromStream(
        await _client.send(request),
      ).timeout(uploadTimeout + const Duration(seconds: 5));
      return _classify(
        response.statusCode,
        response.bodyBytes,
        response.headers['retry-after'],
      );
    } on TimeoutException {
      return const IdentificationResponse(transportCode: 'TIMEOUT');
    } on Exception {
      // Red, archivo o cancelación: sin respuesta fiable.
      return const IdentificationResponse(transportCode: 'NETWORK');
    } finally {
      timer.cancel();
    }
  }

  Future<IdentificationResponse> _jsonCall(
    String method,
    String path,
    String accessToken, {
    Map<String, Object?>? body,
  }) async {
    final AuthHttpResponse response;
    try {
      response = await _json.request(
        method,
        path,
        jsonBody: body,
        accessToken: accessToken,
      );
    } on AuthApiException catch (error) {
      return IdentificationResponse(
        transportCode: switch (error.kind) {
          AuthApiErrorKind.timeout => 'TIMEOUT',
          AuthApiErrorKind.network => 'NETWORK',
          _ => 'TRANSPORT',
        },
      );
    }
    return _classify(
      response.statusCode,
      response.bodyBytes,
      response.retryAfter,
    );
  }

  IdentificationResponse _classify(
    int status,
    List<int> bytes,
    String? retryAfter,
  ) {
    Object? decoded;
    try {
      decoded = bytes.isEmpty ? null : jsonDecode(utf8.decode(bytes));
    } on FormatException {
      decoded = null;
    }
    if (status >= 200 && status < 300) {
      return IdentificationResponse(statusCode: status, body: decoded);
    }
    final code = decoded is Map<String, dynamic> ? decoded['errorCode'] : null;
    return IdentificationResponse(
      statusCode: status,
      errorCode: code is String && _errorCode.hasMatch(code) ? code : null,
      retryAfter: parseRetryAfter(retryAfter, _clock()),
    );
  }
}
