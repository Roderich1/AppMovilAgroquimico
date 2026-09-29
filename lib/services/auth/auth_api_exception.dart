enum AuthApiErrorKind {
  badRequest,
  unauthorized,
  forbidden,
  notFound,
  rateLimited,
  conflict,
  server,
  network,
  timeout,
  invalidResponse,
  configuration,
}

/// Never retains a request, response body, URL, credential or low-level error.
class AuthApiException implements Exception {
  const AuthApiException(this.kind, {this.statusCode});

  final AuthApiErrorKind kind;
  final int? statusCode;

  @override
  String toString() =>
      'AuthApiException(${kind.name}, statusCode: $statusCode)';
}
