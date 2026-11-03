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
    '/api/v1/sync/v1/push',
    '/api/v1/sync/v1/references',
    '/api/v1/me/backups',
  };

  /// Consulta owner-scoped de una operación: sólo un UUID v4 en minúsculas.
  static final _operationPath = RegExp(
    r'^/api/v1/sync/v1/operations/[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  /// Respaldo privado propio (F08): un id de servidor (UUID v4 en
  /// minúsculas), opcionalmente seguido de `/content`.
  static final _backupPath = RegExp(
    r'^/api/v1/me/backups/[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}(/content)?$',
  );

  /// Estimación del consumo (F12-EST-07-MOB, MOB #164; INT-09): las dos
  /// consultas del Agricultor. Exigen exactamente el parámetro indicado, con
  /// la referencia de la campaña objetivo (UUID v4 en minúsculas).
  static const _queryPaths = <String, String>{
    '/api/v1/estimation/results': 'target_campaign_ref',
    '/api/v1/estimation/download': 'target_campaign_ref',
  };

  static final _uuidV4 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  factory ApiEndpointConfig.fromEnvironment() {
    const value = String.fromEnvironment('AGRO_API_BASE_URL');
    final parsed = Uri.tryParse(value);
    if (parsed == null) {
      throw const AuthApiException(AuthApiErrorKind.configuration);
    }
    return ApiEndpointConfig(parsed);
  }

  final Uri origin;

  /// [query] sólo se admite en las rutas de [_queryPaths], y allí es
  /// obligatoria: un único parámetro conocido con un UUID v4.
  Uri endpoint(String absolutePath, {Map<String, String> query = const {}}) {
    final queryKey = _queryPaths[absolutePath];
    // Exact raw-string matching also rejects encoded dot segments, alternative
    // spellings, query/fragment suffixes and authority/absolute references.
    if (!_allowedPaths.contains(absolutePath) &&
        !_operationPath.hasMatch(absolutePath) &&
        !_backupPath.hasMatch(absolutePath) &&
        queryKey == null) {
      throw const AuthApiException(AuthApiErrorKind.configuration);
    }
    if (queryKey == null
        ? query.isNotEmpty
        : (query.length != 1 || !_uuidV4.hasMatch(query[queryKey] ?? ''))) {
      throw const AuthApiException(AuthApiErrorKind.configuration);
    }
    final resolved = origin.resolve(absolutePath);
    if (resolved.hasQuery || resolved.hasFragment) {
      throw const AuthApiException(AuthApiErrorKind.configuration);
    }
    final destination = query.isEmpty
        ? resolved
        : resolved.replace(queryParameters: query);
    if (destination.scheme != origin.scheme ||
        destination.host != origin.host ||
        destination.port != origin.port ||
        destination.userInfo.isNotEmpty ||
        destination.path != absolutePath ||
        destination.hasQuery != query.isNotEmpty ||
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
