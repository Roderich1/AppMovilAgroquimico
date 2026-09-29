import 'auth_api_exception.dart';

Never _invalid() =>
    throw const AuthApiException(AuthApiErrorKind.invalidResponse);

Map<String, dynamic> _object(Object? value) =>
    value is Map<String, dynamic> ? value : _invalid();

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is String && value.isNotEmpty ? value : _invalid();
}

bool _bool(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is bool ? value : _invalid();
}

DateTime _date(Map<String, dynamic> json, String key) {
  final value = DateTime.tryParse(_string(json, key));
  return value ?? _invalid();
}

String _oneOf(Map<String, dynamic> json, String key, Set<String> allowed) {
  final value = _string(json, key);
  return allowed.contains(value) ? value : _invalid();
}

class LoginV2Request {
  const LoginV2Request({required this.email, required this.password});

  final String email;
  final String password;

  Map<String, Object?> toJson() => {
    'email': email,
    'password': password,
    'refreshTransport': 'BODY',
  };

  @override
  String toString() => 'LoginV2Request(redacted)';
}

class RefreshV2Request {
  const RefreshV2Request(this.refreshToken);

  final String refreshToken;

  Map<String, Object?> toJson() => {'refreshToken': refreshToken};

  @override
  String toString() => 'RefreshV2Request(redacted)';
}

class RegisterClientRequest {
  const RegisterClientRequest(this.clientId);

  /// The F02-B installation UUID. It is not an authentication secret.
  final String clientId;

  Map<String, Object?> toJson() => {'clientId': clientId};

  @override
  String toString() => 'RegisterClientRequest(redacted)';
}

class BindSessionClientRequest {
  const BindSessionClientRequest(this.registrationId);

  final String registrationId;

  Map<String, Object?> toJson() => {'registrationId': registrationId};
}

class V2Account {
  const V2Account(this.id, this.name, this.email, this.isActive);

  factory V2Account.fromJson(Map<String, dynamic> json) => V2Account(
    _string(json, 'id'),
    _string(json, 'name'),
    _string(json, 'email'),
    _bool(json, 'isActive'),
  );

  final String id;
  final String name;
  final String email;
  final bool isActive;
}

class V2Member {
  const V2Member(this.id, this.role, this.isActive);

  factory V2Member.fromJson(Map<String, dynamic> json) => V2Member(
    _string(json, 'id'),
    _oneOf(json, 'role', _roles),
    _bool(json, 'isActive'),
  );

  final String id;
  final String role;
  final bool isActive;
}

class V2Tenant {
  const V2Tenant(this.id, this.name, this.slug, this.isActive);

  factory V2Tenant.fromJson(Map<String, dynamic> json) => V2Tenant(
    _string(json, 'id'),
    _string(json, 'name'),
    _string(json, 'slug'),
    _bool(json, 'isActive'),
  );

  final String id;
  final String name;
  final String slug;
  final bool isActive;
}

class V2Session {
  const V2Session(
    this.id,
    this.status,
    this.refreshTransport,
    this.createdAt,
    this.lastSeenAt,
    this.expiresAt,
    this.clientRegistrationId,
  );

  factory V2Session.fromJson(Map<String, dynamic> json) {
    final clientRegistrationId = json['clientRegistrationId'];
    if (clientRegistrationId != null &&
        (clientRegistrationId is! String || clientRegistrationId.isEmpty)) {
      _invalid();
    }
    return V2Session(
      _string(json, 'id'),
      _oneOf(json, 'status', {'ACTIVE'}),
      _oneOf(json, 'refreshTransport', {'BODY', 'COOKIE'}),
      _date(json, 'createdAt'),
      _date(json, 'lastSeenAt'),
      _date(json, 'expiresAt'),
      clientRegistrationId as String?,
    );
  }

  final String id;
  final String status;
  final String refreshTransport;
  final DateTime createdAt;
  final DateTime lastSeenAt;
  final DateTime expiresAt;
  final String? clientRegistrationId;
}

const _roles = {'AGRICULTOR', 'DIRECTIVA', 'ADMINISTRADOR'};

class V2AuthContext {
  const V2AuthContext(
    this.account,
    this.member,
    this.tenant,
    this.role,
    this.session,
  );

  factory V2AuthContext.fromJson(Map<String, dynamic> json) => V2AuthContext(
    V2Account.fromJson(_object(json['account'])),
    V2Member.fromJson(_object(json['member'])),
    V2Tenant.fromJson(_object(json['tenant'])),
    _oneOf(json, 'role', _roles),
    V2Session.fromJson(_object(json['session'])),
  );

  final V2Account account;
  final V2Member member;
  final V2Tenant tenant;
  final String role;
  final V2Session session;
}

class V2AuthResponse {
  const V2AuthResponse(
    this.accessToken,
    this.refreshToken,
    this.sessionExpiresAt,
    this.context,
  );

  factory V2AuthResponse.fromJson(Map<String, dynamic> json) {
    if (json['contractVersion'] != 2 || json['refreshTransport'] != 'BODY') {
      _invalid();
    }
    final context = V2AuthContext.fromJson(_object(json['context']));
    if (context.session.refreshTransport != 'BODY') _invalid();
    return V2AuthResponse(
      _string(json, 'accessToken'),
      _string(json, 'refreshToken'),
      _date(json, 'sessionExpiresAt'),
      context,
    );
  }

  final String accessToken;
  final String refreshToken;
  final DateTime sessionExpiresAt;
  final V2AuthContext context;

  @override
  String toString() => 'V2AuthResponse(redacted)';
}

class ClientRegistrationResponse {
  const ClientRegistrationResponse(
    this.registrationId,
    this.status,
    this.createdAt,
    this.lastSeenAt,
    this.revokedAt,
  );

  factory ClientRegistrationResponse.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('revokedAt')) _invalid();
    final revokedAt = json['revokedAt'];
    if (revokedAt != null && revokedAt is! String) _invalid();
    return ClientRegistrationResponse(
      _string(json, 'registrationId'),
      _oneOf(json, 'status', {'ACTIVE', 'REVOKED'}),
      _date(json, 'createdAt'),
      _date(json, 'lastSeenAt'),
      revokedAt == null ? null : _date(json, 'revokedAt'),
    );
  }

  final String registrationId;
  final String status;
  final DateTime createdAt;
  final DateTime lastSeenAt;
  final DateTime? revokedAt;
}

class BindSessionClientResponse {
  const BindSessionClientResponse(this.registrationId, this.status);

  factory BindSessionClientResponse.fromJson(Map<String, dynamic> json) =>
      BindSessionClientResponse(
        _string(json, 'registrationId'),
        _oneOf(json, 'status', {'ACTIVE'}),
      );

  final String registrationId;
  final String status;
}
