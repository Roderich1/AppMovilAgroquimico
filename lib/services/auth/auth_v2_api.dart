import 'auth_api_exception.dart';
import 'auth_http_client.dart';
import 'auth_v2_models.dart';

/// Typed, stateless F02 Backend contract for the future F03 activation flow.
/// This service neither persists credentials nor changes the local database.
class AuthV2Api {
  const AuthV2Api(this._http);

  final AuthHttpClient _http;

  Future<V2AuthResponse> login(LoginV2Request request) async {
    final response = await _http.request(
      'POST',
      '/api/v1/auth/v2/login',
      jsonBody: request.toJson(),
    );
    _expect(response, 200);
    return V2AuthResponse.fromJson(response.requireJsonObject());
  }

  Future<ClientRegistrationResponse> registerClient({
    required String accessToken,
    required String clientId,
  }) async {
    final response = await _http.request(
      'POST',
      '/api/v1/auth/clients',
      accessToken: accessToken,
      jsonBody: RegisterClientRequest(clientId).toJson(),
    );
    _expect(response, 201);
    return ClientRegistrationResponse.fromJson(response.requireJsonObject());
  }

  Future<BindSessionClientResponse> bindSessionClient({
    required String accessToken,
    required String registrationId,
  }) async {
    final response = await _http.request(
      'POST',
      '/api/v1/auth/v2/session/client',
      accessToken: accessToken,
      jsonBody: BindSessionClientRequest(registrationId).toJson(),
    );
    _expect(response, 201);
    return BindSessionClientResponse.fromJson(response.requireJsonObject());
  }

  Future<V2AuthContext> currentContext(String accessToken) async {
    final response = await _http.request(
      'GET',
      '/api/v1/auth/v2/me',
      accessToken: accessToken,
    );
    _expect(response, 200);
    return V2AuthContext.fromJson(response.requireJsonObject());
  }

  /// BODY transport only. Rotation orchestration and secure storage belong to #20.
  Future<V2AuthResponse> refresh(String refreshToken) async {
    final response = await _http.request(
      'POST',
      '/api/v1/auth/v2/refresh',
      jsonBody: RefreshV2Request(refreshToken).toJson(),
    );
    _expect(response, 200);
    return V2AuthResponse.fromJson(response.requireJsonObject());
  }

  /// A missing credential is idempotent at the Backend (204).
  Future<void> logout({String? refreshToken}) async {
    final response = await _http.request(
      'POST',
      '/api/v1/auth/v2/logout',
      jsonBody: refreshToken == null
          ? null
          : RefreshV2Request(refreshToken).toJson(),
    );
    _expect(response, 204);
  }

  static void _expect(AuthHttpResponse response, int expectedStatus) {
    if (response.statusCode == expectedStatus) return;
    final kind = switch (response.statusCode) {
      400 => AuthApiErrorKind.badRequest,
      401 => AuthApiErrorKind.unauthorized,
      403 => AuthApiErrorKind.forbidden,
      404 => AuthApiErrorKind.notFound,
      409 => AuthApiErrorKind.conflict,
      429 => AuthApiErrorKind.rateLimited,
      _ => AuthApiErrorKind.server,
    };
    throw AuthApiException(kind, statusCode: response.statusCode);
  }
}
