// OE3, cierre HOST de #18 (AUTH-01, cliente HTTP): lo que faltaba según el
// inventario de OE3 del 2026-11-03.
//
// 1. 403 y 404 se traducen a `forbidden` y `notFound` en las seis operaciones
//    del contrato, sin conservar el cuerpo, la URL ni credenciales.
// 2. `ApiEndpointConfig.fromEnvironment()` lee `AGRO_API_BASE_URL`, que es una
//    constante de compilación (`String.fromEnvironment`). Una prueba no puede
//    cambiarla en tiempo de ejecución: se comprueba en cada ejecución lo que
//    la propia ejecución compiló. Sin `--dart-define` (la suite completa y la
//    CI) se prueba la ausencia. Las variantes con valor se ejecutan aparte:
//
//      flutter test test/oe3_auth_01_403_404_entorno_test.dart \
//        --dart-define=AGRO_API_BASE_URL=https://api.example.test:8443 \
//        --dart-define=OE3_ENV_EXPECT=valid
//      ... --dart-define=AGRO_API_BASE_URL=http://api.example.test \
//        --dart-define=OE3_ENV_EXPECT=invalid
//      ... --dart-define=AGRO_API_BASE_URL=https://[ \
//        --dart-define=OE3_ENV_EXPECT=unparsable
//
//    `OE3_ENV_EXPECT` dice qué se espera; un valor desconocido falla. Lo que
//    no se prueba aquí es el valor que lleva compilado una APK concreta.
//
// Pruebas de HOST con `MockClient`; no hay red ni dispositivo.
import 'package:agroquimicos/services/auth/api_endpoint_config.dart';
import 'package:agroquimicos/services/auth/auth_api_exception.dart';
import 'package:agroquimicos/services/auth/auth_http_client.dart';
import 'package:agroquimicos/services/auth/auth_v2_api.dart';
import 'package:agroquimicos/services/auth/auth_v2_models.dart';
import 'package:agroquimicos/services/auth/first_activation_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _access = 'access-secret-for-test';
const _refresh = 'refresh-secret-for-test';
const _clientId = '550e8400-e29b-41d4-a716-446655440000';
const _registrationId = '550e8400-e29b-41d4-a716-446655440001';
const _password = 'password-for-test';

const _envOrigin = String.fromEnvironment('AGRO_API_BASE_URL');
const _envExpect = String.fromEnvironment(
  'OE3_ENV_EXPECT',
  defaultValue: 'absent',
);

AuthV2Api _api(MockClient client) => AuthV2Api(
  AuthHttpClient(
    config: ApiEndpointConfig(Uri.parse('https://api.example.test')),
    client: client,
    timeout: const Duration(seconds: 1),
  ),
);

/// Las seis operaciones del contrato F02 que usa #18.
final _operations = <String, Future<Object?> Function(AuthV2Api)>{
  'login': (api) => api.login(
    const LoginV2Request(email: 'farmer@example.test', password: _password),
  ),
  'registerClient': (api) =>
      api.registerClient(accessToken: _access, clientId: _clientId),
  'bindSessionClient': (api) => api.bindSessionClient(
    accessToken: _access,
    registrationId: _registrationId,
  ),
  'currentContext': (api) => api.currentContext(_access),
  'refresh': (api) => api.refresh(_refresh),
  'logout': (api) => api.logout(refreshToken: _refresh),
};

Matcher _safeAuthError(AuthApiErrorKind kind, int status, String secretBody) =>
    throwsA(
      isA<AuthApiException>()
          .having((error) => error.kind, 'kind', kind)
          .having((error) => error.statusCode, 'statusCode', status)
          .having(
            (error) => error.toString(),
            'sin cuerpo, URL ni credenciales',
            allOf([
              isNot(contains(secretBody)),
              isNot(contains('api.example.test')),
              isNot(contains(_access)),
              isNot(contains(_refresh)),
              isNot(contains(_password)),
            ]),
          ),
    );

void main() {
  group('#18: 403 y 404', () {
    for (final status in <int, AuthApiErrorKind>{
      403: AuthApiErrorKind.forbidden,
      404: AuthApiErrorKind.notFound,
    }.entries) {
      for (final operation in _operations.entries) {
        test('HTTP ${status.key} en ${operation.key} es '
            '${status.value.name}, sin datos del cuerpo', () async {
          const body = 'cuerpo-secreto $_access $_refresh $_clientId';
          var sends = 0;
          final api = _api(
            MockClient((request) async {
              sends++;
              return http.Response(body, status.key);
            }),
          );
          await expectLater(
            operation.value(api),
            _safeAuthError(status.value, status.key, body),
          );
          // Un 403 o 404 no se reintenta ni se sigue por otro camino.
          expect(sends, 1);
        });
      }
    }
  });

  group('#18: AGRO_API_BASE_URL (constante de compilación)', () {
    test('fromEnvironment refleja lo compilado en esta ejecución '
        '(OE3_ENV_EXPECT=$_envExpect)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      Matcher configurationError() => throwsA(
        isA<AuthApiException>()
            .having(
              (error) => error.kind,
              'kind',
              AuthApiErrorKind.configuration,
            )
            .having(
              (error) => error.toString(),
              'sin el valor configurado',
              _envOrigin.isEmpty ? anything : isNot(contains(_envOrigin)),
            ),
      );
      switch (_envExpect) {
        case 'absent':
          // Sin `--dart-define`: no hay origen embebido ni uno por defecto.
          expect(_envOrigin, isEmpty);
          expect(ApiEndpointConfig.fromEnvironment, configurationError());
          // El proveedor lo convierte en «sin configurar», no en una excepción
          // del arranque; el cliente remoto sí falla al construirse (Riverpod
          // envuelve el error del proveedor en `ProviderException`).
          expect(container.read(apiEndpointConfigProvider), isNull);
          expect(
            () => container.read(authHttpClientProvider),
            throwsA(
              isA<ProviderException>().having(
                (error) => error.exception,
                'exception',
                isA<AuthApiException>().having(
                  (error) => error.kind,
                  'kind',
                  AuthApiErrorKind.configuration,
                ),
              ),
            ),
          );
        case 'valid':
          expect(_envOrigin, isNotEmpty);
          final config = ApiEndpointConfig.fromEnvironment();
          expect(config.origin, Uri.parse(_envOrigin));
          expect(
            config.endpoint('/api/v1/auth/v2/login'),
            Uri.parse(_envOrigin).resolve('/api/v1/auth/v2/login'),
          );
          expect(
            container.read(apiEndpointConfigProvider)?.origin,
            Uri.parse(_envOrigin),
          );
        case 'invalid':
          // Se analiza como URI, pero el validador lo rechaza (p. ej. HTTP).
          expect(Uri.tryParse(_envOrigin), isNotNull);
          expect(ApiEndpointConfig.fromEnvironment, configurationError());
          expect(container.read(apiEndpointConfigProvider), isNull);
        case 'unparsable':
          // `Uri.tryParse` devuelve null: es la otra rama de fromEnvironment.
          expect(Uri.tryParse(_envOrigin), isNull);
          expect(ApiEndpointConfig.fromEnvironment, configurationError());
          expect(container.read(apiEndpointConfigProvider), isNull);
        default:
          fail('OE3_ENV_EXPECT desconocido: $_envExpect');
      }
    });
  });
}
