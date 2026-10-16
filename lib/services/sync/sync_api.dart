import 'dart:convert';

import '../../domain/sync/central_references.dart';
import '../../domain/sync/sync_types.dart';
import '../../domain/sync/sync_wire.dart';
import '../auth/auth_api_exception.dart';
import '../auth/auth_http_client.dart';

/// Resultado de un POST de Sync v1, ya clasificado para el worker.
sealed class PushOutcome {
  const PushOutcome();
}

/// ACK válido para la intención enviada.
class PushAcknowledged extends PushOutcome {
  const PushAcknowledged(this.ack);
  final SyncAck ack;
}

/// Respuesta HTTP de error. [error] es null si el cuerpo no es el cerrado de
/// §9 (p. ej. un proxy): entonces no se confía en su disposition.
class PushRequestFailed extends PushOutcome {
  const PushRequestFailed(this.statusCode, this.error, this.retryAfter);
  final int statusCode;
  final SyncRequestError? error;
  final Duration? retryAfter;
}

/// Sin respuesta fiable (timeout, red, ACK incoherente): la intención pudo
/// llegar o no a Central. Se reenvía igual.
class PushUncertain extends PushOutcome {
  const PushUncertain(this.code);
  final String code;
}

/// Fallo de una consulta (GET). [statusCode] es null sin respuesta HTTP.
class SyncQueryException implements Exception {
  const SyncQueryException(this.statusCode, this.errorCode);
  final int? statusCode;
  final String? errorCode;

  bool get authRequired => statusCode == 401;
  bool get forbidden => statusCode == 403;

  @override
  String toString() => 'SyncQueryException($statusCode, $errorCode)';
}

/// Cliente de Sync v1 sobre el transporte sin estado de F02/F03. No registra
/// cuerpos, cantidades ni credenciales.
class SyncApi {
  SyncApi(this._http, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AuthHttpClient _http;
  final DateTime Function() _clock;

  static const _pushPath = '/api/v1/sync/v1/push';
  static const _referencesPath = '/api/v1/sync/v1/references';

  Future<PushOutcome> push(OutboxEntry entry, String accessToken) async {
    final AuthHttpResponse response;
    try {
      response = await _http.request(
        'POST',
        _pushPath,
        jsonBody: envelopeOf(entry),
        accessToken: accessToken,
      );
    } on AuthApiException catch (error) {
      return PushUncertain(switch (error.kind) {
        AuthApiErrorKind.timeout => 'TIMEOUT',
        AuthApiErrorKind.network => 'NETWORK',
        _ => 'TRANSPORT',
      });
    }
    final body = _decode(response.bodyBytes);
    if (response.statusCode == 200) {
      final ack = SyncAck.validate(body, entry.operationId);
      return ack == null
          ? const PushUncertain('INVALID_ACK')
          : PushAcknowledged(ack);
    }
    return PushRequestFailed(
      response.statusCode,
      SyncRequestError.validate(body),
      parseRetryAfter(response.retryAfter, _clock()),
    );
  }

  /// Resultado y estado causal de una intención propia.
  Future<OperationView> operation(
    String operationId,
    String accessToken,
  ) async {
    final response = await _get(
      '/api/v1/sync/v1/operations/$operationId',
      accessToken,
    );
    final view = OperationView.validate(
      _decode(response.bodyBytes),
      operationId,
    );
    if (view == null) throw const SyncQueryException(200, 'INVALID_RESPONSE');
    return view;
  }

  Future<CentralReferences> references(String accessToken) async {
    final response = await _get(_referencesPath, accessToken);
    final body = _decode(response.bodyBytes);
    if (body is! Map<String, dynamic>) {
      throw const SyncQueryException(200, 'INVALID_RESPONSE');
    }
    try {
      return CentralReferences.fromJson(body);
    } on CentralReferencesFormatException {
      throw const SyncQueryException(200, 'INVALID_RESPONSE');
    }
  }

  Future<AuthHttpResponse> _get(String path, String accessToken) async {
    final AuthHttpResponse response;
    try {
      response = await _http.request('GET', path, accessToken: accessToken);
    } on AuthApiException {
      throw const SyncQueryException(null, 'UNAVAILABLE');
    }
    if (response.statusCode != 200) {
      throw SyncQueryException(
        response.statusCode,
        SyncRequestError.validate(_decode(response.bodyBytes))?.errorCode,
      );
    }
    return response;
  }

  static Object? _decode(List<int> bytes) {
    try {
      return jsonDecode(utf8.decode(bytes));
    } on FormatException {
      return null;
    }
  }
}
