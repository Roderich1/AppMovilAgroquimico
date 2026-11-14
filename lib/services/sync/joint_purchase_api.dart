// Cliente de las rutas del agricultor de las convocatorias de compra conjunta
// (contrato E2 §4.2): `/api/v1/me/joint-purchase-calls`.
//
// No es Sync v1: no toca la outbox ni el envelope F05/F06. No registra
// cuerpos, cantidades ni credenciales.
import 'dart:convert';

import '../../domain/sync/joint_purchase_call_view.dart'
    show
        jointPurchaseContractHeader,
        jointPurchaseContractVersion,
        jointPurchaseHistoryPageSize;
import '../../domain/sync/sync_wire.dart' show parseRetryAfter;
import '../auth/auth_api_exception.dart';
import '../auth/auth_http_client.dart';

/// Respuesta de una llamada, sin encabezados.
class JointPurchaseResponse {
  const JointPurchaseResponse({
    this.statusCode,
    this.body,
    this.errorCode,
    this.retryAfter,
    this.transportCode,
  });

  /// Null si no hubo respuesta HTTP (red, plazo, transporte).
  final int? statusCode;

  /// JSON decodificado (también en los errores: `reason` de
  /// `CALL_NOT_OPEN` y `participation` de `STALE_SEQUENCE` viajan en él).
  final Object? body;

  /// `errorCode` de una respuesta de error, si tiene la forma esperada.
  final String? errorCode;

  /// Demora pedida por el servidor (429/503), si la hay.
  final Duration? retryAfter;

  /// `TIMEOUT`, `NETWORK` o `TRANSPORT` cuando no hubo respuesta.
  final String? transportCode;

  bool get ok => statusCode != null && statusCode! >= 200 && statusCode! < 300;
  bool get isAuth => statusCode == 401 || statusCode == 403;

  /// Código para guardar: el del servidor, el de transporte o `HTTP_<n>`.
  String get code => errorCode ?? transportCode ?? 'HTTP_${statusCode ?? 0}';
}

class JointPurchaseApi {
  JointPurchaseApi({required AuthHttpClient json, DateTime Function()? clock})
    : _json = json,
      _clock = clock ?? DateTime.now;

  final AuthHttpClient _json;
  final DateTime Function() _clock;

  static const basePath = '/api/v1/me/joint-purchase-calls';
  static final _errorCode = RegExp(r'^[A-Z][A-Z0-9_]{0,63}$');

  static const historyPath = '$basePath/history';

  static String participationPath(String callId) =>
      '$basePath/$callId/participation';
  static String withdrawPath(String callId) =>
      '$basePath/$callId/participation/withdraw';
  static String consentPath(String callId) =>
      '$basePath/$callId/participation/consent';

  /// `GET /me/joint-purchase-calls`.
  Future<JointPurchaseResponse> list(String accessToken) =>
      _call('GET', basePath, accessToken);

  /// `GET /me/joint-purchase-calls/history?before=<cursor>&limit=<n>` (E2
  /// §10.1): una página de convocatorias terminadas anteriores a la ventana
  /// de recientes. Sin [before], la primera.
  Future<JointPurchaseResponse> history(
    String accessToken, {
    String? before,
    int limit = jointPurchaseHistoryPageSize,
  }) => _call(
    'GET',
    historyPath,
    accessToken,
    query: {'before': ?before, 'limit': '$limit'},
  );

  /// `PUT /me/joint-purchase-calls/{id}/participation`: `{operation_id,
  /// sequence, consent: {version, accepted_at}, lines: [{product_ref,
  /// quantity_base}]}`.
  Future<JointPurchaseResponse> confirm(
    String callId,
    Map<String, Object?> body,
    String accessToken,
  ) => _call('PUT', participationPath(callId), accessToken, body: body);

  /// `POST /me/joint-purchase-calls/{id}/participation/withdraw`:
  /// `{operation_id, sequence}`.
  Future<JointPurchaseResponse> withdraw(
    String callId,
    Map<String, Object?> body,
    String accessToken,
  ) => _call('POST', withdrawPath(callId), accessToken, body: body);

  /// `POST /me/joint-purchase-calls/{id}/participation/consent` (E2 §10.6):
  /// `{operation_id, sequence, scope, consent: {version, decided_at}}`.
  Future<JointPurchaseResponse> decideConsent(
    String callId,
    Map<String, Object?> body,
    String accessToken,
  ) => _call('POST', consentPath(callId), accessToken, body: body);

  Future<JointPurchaseResponse> _call(
    String method,
    String path,
    String accessToken, {
    Map<String, Object?>? body,
    Map<String, String> query = const {},
  }) async {
    final AuthHttpResponse response;
    try {
      response = await _json.request(
        method,
        path,
        jsonBody: body,
        accessToken: accessToken,
        query: query,
        // N7: el teléfono dice qué contrato lee; sin esto el sindicato
        // responde con la forma de las versiones anteriores.
        headers: {jointPurchaseContractHeader: '$jointPurchaseContractVersion'},
      );
    } on AuthApiException catch (error) {
      return JointPurchaseResponse(
        transportCode: switch (error.kind) {
          AuthApiErrorKind.timeout => 'TIMEOUT',
          AuthApiErrorKind.network => 'NETWORK',
          _ => 'TRANSPORT',
        },
      );
    }
    Object? decoded;
    try {
      decoded = response.bodyBytes.isEmpty
          ? null
          : jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      decoded = null;
    }
    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      return JointPurchaseResponse(statusCode: status, body: decoded);
    }
    final code = decoded is Map<String, dynamic> ? decoded['errorCode'] : null;
    return JointPurchaseResponse(
      statusCode: status,
      body: decoded,
      errorCode: code is String && _errorCode.hasMatch(code) ? code : null,
      retryAfter: parseRetryAfter(response.retryAfter, _clock()),
    );
  }
}
