import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/services/auth/api_endpoint_config.dart';
import 'package:agroquimicos/services/auth/auth_api_exception.dart';
import 'package:agroquimicos/services/auth/auth_http_client.dart';
import 'package:agroquimicos/services/auth/auth_v2_api.dart';
import 'package:agroquimicos/services/auth/auth_v2_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _access = 'access-secret-for-test';
const _refresh = 'refresh-secret-for-test';
const _clientId = '550e8400-e29b-41d4-a716-446655440000';
const _registrationId = '550e8400-e29b-41d4-a716-446655440001';

Map<String, Object?> _context({String? registrationId}) => {
  'account': {
    'id': 'user-1',
    'name': 'Test User',
    'email': 'farmer@example.test',
    'isActive': true,
  },
  'member': {'id': 'member-1', 'role': 'AGRICULTOR', 'isActive': true},
  'tenant': {
    'id': 'tenant-1',
    'name': 'Sindicato',
    'slug': 'sindicato',
    'isActive': true,
  },
  'role': 'AGRICULTOR',
  'session': {
    'id': 'session-1',
    'status': 'ACTIVE',
    'refreshTransport': 'BODY',
    'createdAt': '2026-09-28T10:00:00.000Z',
    'lastSeenAt': '2026-09-28T10:00:00.000Z',
    'expiresAt': '2026-10-05T10:00:00.000Z',
    'clientRegistrationId': registrationId,
  },
};

Map<String, Object?> _authResponse({String token = _refresh}) => {
  'contractVersion': 2,
  'accessToken': _access,
  'refreshToken': token,
  'refreshTransport': 'BODY',
  'sessionExpiresAt': '2026-10-05T10:00:00.000Z',
  'context': _context(),
};

AuthV2Api _api(
  MockClient client, {
  Duration timeout = const Duration(seconds: 1),
}) => AuthV2Api(
  AuthHttpClient(
    config: ApiEndpointConfig(Uri.parse('https://api.example.test')),
    client: client,
    timeout: timeout,
  ),
);

http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status);

void main() {
  sqfliteFfiInit();

  test('external URL is HTTPS origin-only and never prints its value', () {
    expect(
      () => ApiEndpointConfig(Uri.parse('http://api.example.test')),
      throwsA(isA<AuthApiException>()),
    );
    expect(
      () => ApiEndpointConfig(Uri.parse('https://user:secret@api.test/path')),
      throwsA(
        isA<AuthApiException>().having(
          (error) => error.toString(),
          'safe error',
          isNot(contains('secret')),
        ),
      ),
    );
  });

  test('HTTPS origin resolves exactly the six permitted auth paths', () {
    final config = ApiEndpointConfig(
      Uri.parse('https://api.example.test:8443/'),
    );
    for (final path in [
      '/api/v1/auth/v2/login',
      '/api/v1/auth/clients',
      '/api/v1/auth/v2/session/client',
      '/api/v1/auth/v2/me',
      '/api/v1/auth/v2/refresh',
      '/api/v1/auth/v2/logout',
    ]) {
      expect(
        config.endpoint(path).toString(),
        'https://api.example.test:8443$path',
      );
    }
  });

  test('HTTP and non-origin configurations are rejected safely', () {
    for (final value in [
      'http://api.example.test',
      'https://user:password-for-test@api.example.test',
      'https://api.example.test/base',
      'https://api.example.test?accessToken=$_access',
      'https://api.example.test#refreshToken=$_refresh',
      'https://api.example.test:0',
    ]) {
      expect(
        () => ApiEndpointConfig(Uri.parse(value)),
        throwsA(
          isA<AuthApiException>()
              .having(
                (error) => error.kind,
                'kind',
                AuthApiErrorKind.configuration,
              )
              .having(
                (error) => error.toString(),
                'no supplied origin',
                isNot(contains(value)),
              ),
        ),
      );
    }
  });

  test('external, traversal and decorated paths cannot escape auth scope', () {
    final config = ApiEndpointConfig(Uri.parse('https://api.example.test'));
    for (final path in [
      'https://evil.example.test/api/v1/auth/v2/login',
      '//evil.example.test/api/v1/auth/v2/login',
      '/api/v1/auth/v2/../login',
      '/api/v1/auth/v2/%2e%2e/login',
      '/api/v1/auth/v2/%2E%2E/login',
      '/api/v1/auth/v2/%2f..%2flogin',
      '/api/v1/auth/v2/login?refreshToken=$_refresh',
      '/api/v1/auth/v2/login#accessToken=$_access',
      '/public/auth/v2/login',
      '/api/v1/auth/v2/login/',
      '/api/v1/auth/v2/%6cogin',
    ]) {
      expect(
        () => config.endpoint(path),
        throwsA(
          isA<AuthApiException>()
              .having(
                (error) => error.kind,
                'kind',
                AuthApiErrorKind.configuration,
              )
              .having(
                (error) => error.toString(),
                'no supplied path',
                isNot(contains(path)),
              ),
        ),
      );
    }
  });

  test('all six auth operations explicitly disable redirects', () async {
    final seen = <String>[];
    final api = _api(
      MockClient((request) async {
        expect(request.followRedirects, isFalse);
        seen.add(request.url.path);
        switch (request.url.path) {
          case '/api/v1/auth/v2/login':
          case '/api/v1/auth/v2/refresh':
            return _json(200, _authResponse());
          case '/api/v1/auth/clients':
            return _json(201, {
              'registrationId': _registrationId,
              'status': 'ACTIVE',
              'createdAt': '2026-09-28T10:00:00.000Z',
              'lastSeenAt': '2026-09-28T10:00:00.000Z',
              'revokedAt': null,
            });
          case '/api/v1/auth/v2/session/client':
            return _json(201, {
              'registrationId': _registrationId,
              'status': 'ACTIVE',
            });
          case '/api/v1/auth/v2/me':
            return _json(200, _context());
          case '/api/v1/auth/v2/logout':
            return http.Response('', 204);
        }
        fail('Unexpected contract path');
      }),
    );

    await api.login(
      const LoginV2Request(
        email: 'farmer@example.test',
        password: 'password-for-test',
      ),
    );
    await api.registerClient(accessToken: _access, clientId: _clientId);
    await api.bindSessionClient(
      accessToken: _access,
      registrationId: _registrationId,
    );
    await api.currentContext(_access);
    await api.refresh(_refresh);
    await api.logout(refreshToken: _refresh);
    expect(seen, hasLength(6));
  });

  for (final redirectStatus in [303, 307]) {
    test('HTTP $redirectStatus is rejected without exposing Location', () async {
      var sends = 0;
      final api = _api(
        MockClient((request) async {
          sends++;
          expect(request.followRedirects, isFalse);
          expect(request.headers['authorization'], 'Bearer $_access');
          return http.Response(
            'password-for-test $_refresh $_clientId',
            redirectStatus,
            headers: {
              'location':
                  'https://evil.example.test/?accessToken=$_access&refreshToken=$_refresh',
            },
          );
        }),
      );
      await expectLater(
        api.currentContext(_access),
        throwsA(
          isA<AuthApiException>()
              .having((error) => error.kind, 'kind', AuthApiErrorKind.server)
              .having((error) => error.statusCode, 'status', redirectStatus)
              .having(
                (error) => error.toString(),
                'safe error',
                allOf([
                  isNot(contains('evil.example.test')),
                  isNot(contains(_access)),
                  isNot(contains(_refresh)),
                  isNot(contains(_clientId)),
                  isNot(contains('password-for-test')),
                ]),
              ),
        ),
      );
      // MockClient cannot prove real network navigation; the request flag and
      // lack of a second mock send are the only claims made by this test.
      expect(sends, 1);
    });
  }

  test(
    'raw transport also rejects a redirect without leaking headers',
    () async {
      final transport = AuthHttpClient(
        config: ApiEndpointConfig(Uri.parse('https://api.example.test')),
        client: MockClient((request) async {
          expect(request.followRedirects, isFalse);
          return http.Response(
            '',
            302,
            headers: {
              'location': 'https://evil.example.test/?clientId=$_clientId',
            },
          );
        }),
      );
      await expectLater(
        transport.request('GET', '/api/v1/auth/v2/me', accessToken: _access),
        throwsA(
          isA<AuthApiException>()
              .having((error) => error.kind, 'kind', AuthApiErrorKind.server)
              .having((error) => error.statusCode, 'status', 302)
              .having(
                (error) => error.toString(),
                'safe error',
                allOf([
                  isNot(contains('evil.example.test')),
                  isNot(contains(_clientId)),
                  isNot(contains(_access)),
                ]),
              ),
        ),
      );
    },
  );

  test('login serializes BODY V2 exactly and parses typed response', () async {
    final api = _api(
      MockClient((request) async {
        expect(request.method, 'POST');
        expect(
          request.url.toString(),
          'https://api.example.test/api/v1/auth/v2/login',
        );
        expect(request.headers['accept'], 'application/json');
        expect(request.headers['content-type'], contains('application/json'));
        expect(request.headers, isNot(contains('cookie')));
        expect(request.headers, isNot(contains('authorization')));
        expect(jsonDecode(request.body), {
          'email': 'farmer@example.test',
          'password': 'password-for-test',
          'refreshTransport': 'BODY',
        });
        return _json(200, _authResponse());
      }),
    );

    const request = LoginV2Request(
      email: 'farmer@example.test',
      password: 'password-for-test',
    );
    final result = await api.login(request);
    expect(result.accessToken, _access);
    expect(result.refreshToken, _refresh);
    expect(result.context.member.role, 'AGRICULTOR');
    expect(result.context.session.clientRegistrationId, isNull);
    expect(result.sessionExpiresAt.toUtc().year, 2026);
    expect(request.toString(), isNot(contains(request.password)));
    expect(result.toString(), isNot(contains(_access)));
    expect(result.toString(), isNot(contains(_refresh)));
  });

  test('register, bind and me follow exact Backend paths and DTOs', () async {
    final paths = <String>[];
    final api = _api(
      MockClient((request) async {
        paths.add(request.url.path);
        expect(request.headers['authorization'], 'Bearer $_access');
        expect(request.headers, isNot(contains('cookie')));
        switch (request.url.path) {
          case '/api/v1/auth/clients':
            expect(request.method, 'POST');
            expect(jsonDecode(request.body), {'clientId': _clientId});
            return _json(201, {
              'registrationId': _registrationId,
              'status': 'ACTIVE',
              'createdAt': '2026-09-28T10:00:00.000Z',
              'lastSeenAt': '2026-09-28T10:00:00.000Z',
              'revokedAt': null,
            });
          case '/api/v1/auth/v2/session/client':
            expect(request.method, 'POST');
            expect(jsonDecode(request.body), {
              'registrationId': _registrationId,
            });
            return _json(201, {
              'registrationId': _registrationId,
              'status': 'ACTIVE',
            });
          case '/api/v1/auth/v2/me':
            expect(request.method, 'GET');
            expect(request.body, isEmpty);
            return _json(200, _context(registrationId: _registrationId));
        }
        fail('Unexpected contract path');
      }),
    );

    final registration = await api.registerClient(
      accessToken: _access,
      clientId: _clientId,
    );
    final binding = await api.bindSessionClient(
      accessToken: _access,
      registrationId: registration.registrationId,
    );
    final context = await api.currentContext(_access);
    expect(binding.registrationId, _registrationId);
    expect(context.session.clientRegistrationId, _registrationId);
    expect(paths, [
      '/api/v1/auth/clients',
      '/api/v1/auth/v2/session/client',
      '/api/v1/auth/v2/me',
    ]);
  });

  test('BODY refresh and logout remain stateless typed contracts', () async {
    var refreshCalls = 0;
    final api = _api(
      MockClient((request) async {
        expect(request.headers, isNot(contains('cookie')));
        if (request.url.path == '/api/v1/auth/v2/refresh') {
          refreshCalls++;
          expect(request.method, 'POST');
          expect(jsonDecode(request.body), {'refreshToken': _refresh});
          return _json(200, _authResponse(token: 'rotated-refresh'));
        }
        expect(request.url.path, '/api/v1/auth/v2/logout');
        expect(request.method, 'POST');
        if (request.body.isNotEmpty) {
          expect(jsonDecode(request.body), {'refreshToken': 'rotated-refresh'});
        }
        return http.Response('', 204);
      }),
    );

    final rotated = await api.refresh(_refresh);
    expect(rotated.refreshToken, 'rotated-refresh');
    await api.logout(refreshToken: rotated.refreshToken);
    await api.logout();
    expect(refreshCalls, 1);
  });

  for (final entry in <int, AuthApiErrorKind>{
    400: AuthApiErrorKind.badRequest,
    401: AuthApiErrorKind.unauthorized,
    429: AuthApiErrorKind.rateLimited,
    409: AuthApiErrorKind.conflict,
    500: AuthApiErrorKind.server,
  }.entries) {
    test('HTTP ${entry.key} maps to safe ${entry.value.name}', () async {
      final api = _api(
        MockClient(
          (_) async => http.Response(
            'password-for-test $_access $_refresh $_clientId',
            entry.key,
          ),
        ),
      );
      await expectLater(
        api.login(
          const LoginV2Request(
            email: 'farmer@example.test',
            password: 'password-for-test',
          ),
        ),
        throwsA(
          isA<AuthApiException>()
              .having((error) => error.kind, 'kind', entry.value)
              .having(
                (error) => error.toString(),
                'redacted',
                isNot(contains('password-for-test')),
              ),
        ),
      );
    });
  }

  test('connection failure discards low-level secret-bearing error', () async {
    final api = _api(
      MockClient(
        (_) async =>
            throw http.ClientException('$_access $_refresh $_clientId'),
      ),
    );
    await expectLater(
      api.login(
        const LoginV2Request(
          email: 'farmer@example.test',
          password: 'password-for-test',
        ),
      ),
      throwsA(
        isA<AuthApiException>()
            .having((error) => error.kind, 'kind', AuthApiErrorKind.network)
            .having(
              (error) => error.toString(),
              'redacted',
              isNot(contains(_refresh)),
            ),
      ),
    );
  });

  test('timeout is typed and does not expose credentials', () async {
    final pending = Completer<http.Response>();
    final api = _api(
      MockClient((_) => pending.future),
      timeout: const Duration(milliseconds: 10),
    );
    await expectLater(
      api.refresh(_refresh),
      throwsA(
        isA<AuthApiException>()
            .having((error) => error.kind, 'kind', AuthApiErrorKind.timeout)
            .having(
              (error) => error.toString(),
              'redacted',
              isNot(contains(_refresh)),
            ),
      ),
    );
  });

  test(
    'invalid JSON, missing fields and wrong transport are rejected',
    () async {
      for (final response in [
        http.Response('not-json $_refresh', 200),
        http.Response.bytes([0xff], 200),
        _json(200, {'contractVersion': 2}),
        _json(200, {..._authResponse(), 'refreshTransport': 'COOKIE'}),
        _json(200, {..._authResponse(), 'refreshToken': null}),
        _json(200, {
          ..._authResponse(),
          'context': {'account': {}},
        }),
      ]) {
        final api = _api(MockClient((_) async => response));
        await expectLater(
          api.login(
            const LoginV2Request(
              email: 'farmer@example.test',
              password: 'password-for-test',
            ),
          ),
          throwsA(
            isA<AuthApiException>()
                .having(
                  (error) => error.kind,
                  'kind',
                  AuthApiErrorKind.invalidResponse,
                )
                .having(
                  (error) => error.toString(),
                  'redacted',
                  isNot(contains(_refresh)),
                ),
          ),
        );
      }
    },
  );

  test(
    'remote auth failure leaves local SQLite usable and untouched',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'f03_auth_local_',
      );
      addTearDown(() async => directory.delete(recursive: true));
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        path: '${directory.path}/local.db',
      );
      addTearDown(database.close);
      final db = await database.database;
      await db.execute(
        'CREATE TABLE local_marker (id INTEGER PRIMARY KEY, note TEXT)',
      );
      await db.insert('local_marker', {'id': 1, 'note': 'offline-preserved'});

      final api = _api(MockClient((_) async => http.Response('', 401)));
      await expectLater(
        api.login(
          const LoginV2Request(
            email: 'farmer@example.test',
            password: 'password-for-test',
          ),
        ),
        throwsA(isA<AuthApiException>()),
      );
      expect(await db.query('local_marker'), [
        {'id': 1, 'note': 'offline-preserved'},
      ]);
    },
  );
}
