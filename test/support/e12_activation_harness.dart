// Soporte de las pruebas E-12 (F03 §4 bis): Auth V2 simulado que cuenta las
// peticiones, una identidad de instalación fija, un almacén seguro de sesión
// simulado y relojes manuales para la acreditación de activación. Ningún
// valor de aquí es una credencial real.
import 'dart:convert';

import 'package:agroquimicos/data/installation_client_id_store.dart';
import 'package:agroquimicos/domain/installation_access.dart';
import 'package:agroquimicos/installation_access.dart';
import 'package:agroquimicos/services/auth/activation_owner_evidence.dart';
import 'package:agroquimicos/services/auth/first_activation_coordinator.dart';
import 'package:agroquimicos/services/auth/local_owner_credential.dart';
import 'package:http/http.dart' as http;

import 'f04_mode_fixtures.dart';

const e12ClientId = '550e8400-e29b-41d4-a716-446655440000';
const e12RegistrationId = '550e8400-e29b-41d4-a716-446655440001';
const e12SessionId = 'session-e12';
const e12AccountId = 'account-e12';

/// Valores de prueba que nunca deben aparecer en pantalla ni en el almacén.
const e12Password = 'clave-de-prueba-no-mostrar';
const e12Access = 'access-de-prueba-no-mostrar';
const e12Refresh = 'refresh-de-prueba-no-mostrar';

final e12InstallationRef = installationReference(e12ClientId);

/// La identidad que escribe la activación simulada (Member A).
const e12Identity = SessionIdentity(
  accountId: e12AccountId,
  memberId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  tenantId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  sessionId: e12SessionId,
  registrationId: e12RegistrationId,
  installationClientId: e12ClientId,
);

Map<String, Object?> _context({String? registrationId}) => {
  'account': {
    'id': e12AccountId,
    'name': 'Agricultor',
    'email': 'agricultor@example.test',
    'isActive': true,
  },
  'member': {'id': memberA.memberId, 'role': 'AGRICULTOR', 'isActive': true},
  'tenant': {
    'id': memberA.tenantId,
    'name': 'Sindicato',
    'slug': 'sindicato',
    'isActive': true,
  },
  'role': 'AGRICULTOR',
  'session': {
    'id': e12SessionId,
    'status': 'ACTIVE',
    'refreshTransport': 'BODY',
    'createdAt': '2026-10-27T10:00:00.000Z',
    'lastSeenAt': '2026-10-27T10:00:00.000Z',
    'expiresAt': '2099-10-05T10:00:00.000Z',
    'clientRegistrationId': registrationId,
  },
};

http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status);

/// Auth V2 simulado: activación correcta del Member A, o un fallo de red.
class E12Backend {
  final paths = <String>[];
  bool failLoginNetwork = false;

  Future<http.Response> respond(http.Request request) async {
    paths.add(request.url.path);
    switch (request.url.path) {
      case '/api/v1/auth/v2/login':
        if (failLoginNetwork) throw http.ClientException('sin red');
        return _json(200, {
          'contractVersion': 2,
          'accessToken': e12Access,
          'refreshToken': e12Refresh,
          'refreshTransport': 'BODY',
          'sessionExpiresAt': '2099-10-05T10:00:00.000Z',
          'context': _context(),
        });
      case '/api/v1/auth/clients':
        return _json(201, {
          'registrationId': e12RegistrationId,
          'status': 'ACTIVE',
          'createdAt': '2026-10-27T10:00:00.000Z',
          'lastSeenAt': '2026-10-27T10:00:00.000Z',
          'revokedAt': null,
        });
      case '/api/v1/auth/v2/session/client':
        return _json(201, {
          'registrationId': e12RegistrationId,
          'status': 'ACTIVE',
        });
      case '/api/v1/auth/v2/me':
        return _json(200, _context(registrationId: e12RegistrationId));
      case '/api/v1/auth/v2/logout':
        return http.Response('', 204);
    }
    return http.Response('', 404);
  }
}

class E12IdentityStore extends InstallationClientIdStore {
  @override
  Future<String?> read() async => e12ClientId;

  @override
  Future<String> getOrCreate() async =>
      throw StateError('La activación no crea la identidad');

  @override
  Future<String> rotate() async =>
      throw StateError('La activación no rota la identidad');
}

class E12OutcomeUnknown implements SecureSessionCommitOutcomeUnknown {}

/// Escritura de la sesión simulada; [outcomeUnknown] simula un acuse
/// perdido después del puntero (resultado incierto).
class E12CommitPort implements SecureSessionCommitPort {
  int calls = 0;
  bool outcomeUnknown = false;

  @override
  Future<void> commitAndVerify(SessionCommitCandidate candidate) async {
    calls++;
    if (outcomeUnknown) throw E12OutcomeUnknown();
  }
}

/// Reloj de pared y cronómetro manuales.
class E12Clock {
  E12Clock() : now = DateTime.now();

  DateTime now;
  Duration elapsed = Duration.zero;

  void advance(Duration by, {bool monotonic = true}) {
    now = now.add(by);
    if (monotonic) elapsed += by;
  }

  ActivationEvidenceClock get evidenceClock => ActivationEvidenceClock(
    now: () => now,
    startElapsed: () {
      final start = elapsed;
      return () => elapsed - start;
    },
  );
}

/// Estado de acceso que la prueba mueve a mano.
class E12SettableAccess extends InstallationAccessController {
  E12SettableAccess(this._initial, {OwnerScope? bound}) : _bound = bound;

  final InstallationAccessState _initial;
  final OwnerScope? _bound;

  @override
  OwnerScope? get sessionScope => memberA;

  @override
  OwnerScope? get boundScope => _bound;

  @override
  InstallationAccessState? build() => _initial;

  void move(InstallationAccessState next) => state = next;

  @override
  Future<InstallationAccessState?> refresh({
    bool rereadSession = false,
  }) async => state;

  @override
  Future<InstallationAccessState?> recomputeAfterReplacement() async => state;
}

/// Almacén de credencial en memoria que registra qué claves se escriben.
class E12CredentialStorage implements CredentialStorage {
  final values = <String, String>{};
  final writes = <String>[];

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    writes.add(key);
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}
