import 'auth_api_exception.dart';

/// Backend origin only. No credentials or environment-specific URLs in source.
class ApiEndpointConfig {
  ApiEndpointConfig(Uri origin) : origin = _validate(origin);

  factory ApiEndpointConfig.fromEnvironment() {
    const value = String.fromEnvironment('AGRO_API_BASE_URL');
    final parsed = Uri.tryParse(value);
    if (parsed == null) {
      throw const AuthApiException(AuthApiErrorKind.configuration);
    }
    return ApiEndpointConfig(parsed);
  }

  final Uri origin;

  Uri endpoint(String absolutePath) => origin.resolve(absolutePath);

  static Uri _validate(Uri value) {
    if (value.scheme != 'https' ||
        value.host.isEmpty ||
        value.userInfo.isNotEmpty ||
        (value.path.isNotEmpty && value.path != '/') ||
        value.hasQuery ||
        value.hasFragment) {
      throw const AuthApiException(AuthApiErrorKind.configuration);
    }
    return value;
  }
}
