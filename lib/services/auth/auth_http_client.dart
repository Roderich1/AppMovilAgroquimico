import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_endpoint_config.dart';
import 'auth_api_exception.dart';

class AuthHttpResponse {
  const AuthHttpResponse(this.statusCode, this.bodyBytes, {this.retryAfter});

  final int statusCode;
  final List<int> bodyBytes;

  /// Único encabezado que se conserva: la demora que pide el servidor (Sync
  /// v1, 429/503). Ningún otro encabezado sale de este límite.
  final String? retryAfter;

  Map<String, dynamic> requireJsonObject() {
    try {
      final decoded = jsonDecode(utf8.decode(bodyBytes, allowMalformed: false));
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // The raw payload is deliberately discarded, including in the error.
    }
    throw const AuthApiException(AuthApiErrorKind.invalidResponse);
  }
}

/// Stateless transport: no cookie jar, token cache, persistence or logging.
class AuthHttpClient {
  AuthHttpClient({
    required ApiEndpointConfig config,
    required http.Client client,
    this.timeout = const Duration(seconds: 10),
  }) : _config = config,
       _client = client;

  final ApiEndpointConfig _config;
  final http.Client _client;
  final Duration timeout;

  Future<AuthHttpResponse> request(
    String method,
    String path, {
    Map<String, Object?>? jsonBody,
    String? accessToken,
  }) async {
    try {
      return await _send(method, path, jsonBody, accessToken).timeout(timeout);
    } on TimeoutException {
      throw const AuthApiException(AuthApiErrorKind.timeout);
    } on AuthApiException {
      rethrow;
    } on Exception {
      // ClientException, socket errors and platform errors must not reach logs.
      throw const AuthApiException(AuthApiErrorKind.network);
    }
  }

  Future<AuthHttpResponse> _send(
    String method,
    String path,
    Map<String, Object?>? jsonBody,
    String? accessToken,
  ) async {
    final request = http.Request(method, _config.endpoint(path));
    request.followRedirects = false;
    request.headers['Accept'] = 'application/json';
    if (jsonBody != null) {
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(jsonBody);
    }
    if (accessToken != null) {
      request.headers['Authorization'] = 'Bearer $accessToken';
    }
    final response = await http.Response.fromStream(
      await _client.send(request),
    );
    if (response.statusCode >= 300 && response.statusCode < 400) {
      // Neither Location nor the redirect body may escape this boundary.
      throw AuthApiException(
        AuthApiErrorKind.server,
        statusCode: response.statusCode,
      );
    }
    return AuthHttpResponse(
      response.statusCode,
      response.bodyBytes,
      retryAfter: response.headers['retry-after'],
    );
  }
}
