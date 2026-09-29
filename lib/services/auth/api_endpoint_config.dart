import 'auth_api_exception.dart';

/// Backend origin only. No credentials or environment-specific URLs in source.
class ApiEndpointConfig {
  ApiEndpointConfig(Uri origin) : origin = _validate(origin);

  static const _allowedPaths = <String>{
    '/api/v1/auth/v2/login',
    '/api/v1/auth/clients',
    '/api/v1/auth/v2/session/client',
    '/api/v1/auth/v2/me',
    '/api/v1/auth/v2/refresh',
    '/api/v1/auth/v2/logout',
  };

  factory ApiEndpointConfig.fromEnvironment() {
    const value = String.fromEnvironment('AGRO_API_BASE_URL');
    final parsed = Uri.tryParse(value);
    if (parsed == null) {
      throw const AuthApiException(AuthApiErrorKind.configuration);
    }
    return ApiEndpointConfig(parsed);
  }

  final Uri origin;

  Uri endpoint(String absolutePath) {
    // Exact raw-string matching also rejects encoded dot segments, alternative
    // spellings, query/fragment suffixes and authority/absolute references.
    if (!_allowedPaths.contains(absolutePath)) {
      throw const AuthApiException(AuthApiErrorKind.configuration);
    }
    final destination = origin.resolve(absolutePath);
    if (destination.scheme != origin.scheme ||
        destination.host != origin.host ||
        destination.port != origin.port ||
        destination.userInfo.isNotEmpty ||
        destination.path != absolutePath ||
        destination.hasQuery ||
        destination.hasFragment) {
      throw const AuthApiException(AuthApiErrorKind.configuration);
    }
    return destination;
  }

  static Uri _validate(Uri value) {
    if (value.scheme != 'https' ||
        !value.hasAuthority ||
        value.host.isEmpty ||
        value.userInfo.isNotEmpty ||
        value.port < 1 ||
        value.port > 65535 ||
        (value.path.isNotEmpty && value.path != '/') ||
        value.hasQuery ||
        value.hasFragment) {
      throw const AuthApiException(AuthApiErrorKind.configuration);
    }
    return value;
  }
}
