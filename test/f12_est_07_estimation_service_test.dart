// F12-EST-07-MOB (MOB #164): consulta y descarga de la estimación con el
// access token V2 de la instalación, contra un transporte HTTP simulado.
// Rechazos, respuestas tardías, sin conexión, identidad y cierre de sesión.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/estimation_copy_store.dart';
import 'package:agroquimicos/domain/estimation/farmer_estimation.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/domain/installation_access.dart';
import 'package:agroquimicos/installation_access.dart';
import 'package:agroquimicos/services/auth/api_endpoint_config.dart';
import 'package:agroquimicos/services/auth/auth_api_exception.dart';
import 'package:agroquimicos/services/auth/existing_session_providers.dart';
import 'package:agroquimicos/services/auth/first_activation_providers.dart';
import 'package:agroquimicos/services/auth/remote_session_coordinator.dart';
import 'package:agroquimicos/services/auth/remote_session_providers.dart';
import 'package:agroquimicos/services/estimation/estimation_providers.dart';
import 'package:agroquimicos/services/sync/sync_access.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';
import 'support/f12_estimation_fixtures.dart';

const _token = 'token-sintetico';
final _origin = Uri.parse('https://sindicato.example');

/// Respuesta programable por ruta; registra lo pedido (sin cuerpos).
class _Central {
  final requests = <http.BaseRequest>[];
  final routes = <String, Future<http.Response> Function()>{};

  late final client = MockClient((request) async {
    requests.add(request);
    final handler = routes[request.url.path];
    if (handler == null) throw const SocketException('Sin conexión (prueba)');
    return handler();
  });

  void json(String path, Object body, {int status = 200}) =>
      routes[path] = () async => http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        status,
        headers: {'content-type': 'application/json'},
      );

  void error(String path, int status, String message) => json(path, {
    'statusCode': status,
    'message': message,
    'error': 'x',
  }, status: status);
}

class _OfflineRemote extends RemoteSessionController {
  _OfflineRemote(this.phase);
  final RemoteSessionPhase phase;

  @override
  RemoteSessionState build() =>
      const RemoteSessionState(RemoteSessionPhase.idle);

  @override
  Future<RemoteSessionState> verifyOnline() async => RemoteSessionState(phase);
}

class _World {
  _World(this.database, this.binding, this.central, this.container);
  final AppDatabase database;
  final OwnerBinding binding;
  final _Central central;
  final ProviderContainer container;

  EstimationService get service => container.read(estimationServiceProvider);
  EstimationCopyStore get store => container.read(estimationCopyStoreProvider);
  SyncAccessHolder get holder => container.read(syncAccessHolderProvider);

  Future<List<Map<String, Object?>>> rows() async =>
      (await database.database).query('estimation_copies');
}

Future<_World> _world({
  InstallationAccessState state = InstallationAccessState.activated,
  bool token = true,
  RemoteSessionPhase verify = RemoteSessionPhase.outcomeUnknown,
}) async {
  final database = openDb(inMemoryDatabasePath);
  final binding = await OwnerBindingStore(database).bindNewPerson(
    name: 'Titular',
    scope: memberA,
    installationRef: installationHere,
  );
  final central = _Central();
  final holder = SyncAccessHolder();
  if (token) holder.accept(_token, memberA.memberId, memberA.tenantId);
  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(database),
      installationAccessProvider.overrideWith(
        () => FixedInstallationAccess(state, scope: memberA, bound: memberA),
      ),
      apiEndpointConfigProvider.overrideWithValue(ApiEndpointConfig(_origin)),
      authHttpTransportProvider.overrideWithValue(central.client),
      syncAccessHolderProvider.overrideWithValue(holder),
      remoteSessionProvider.overrideWith(() => _OfflineRemote(verify)),
    ],
  );
  addTearDown(container.dispose);
  container.read(installationAccessProvider);
  return _World(database, binding, central, container);
}

const _results = '/api/v1/estimation/results';
const _download = '/api/v1/estimation/download';

void main() {
  sqfliteFfiInit();

  group('endpoint: la consulta sólo con la campaña objetivo', () {
    final config = ApiEndpointConfig(_origin);

    test('las rutas de la estimación exigen exactamente target_campaign_ref con un UUID v4', () {
      expect(
        config
            .endpoint(_download, query: {'target_campaign_ref': campaignWinter})
            .toString(),
        'https://sindicato.example/api/v1/estimation/download?target_campaign_ref=$campaignWinter',
      );
      for (final query in [
        <String, String>{},
        {'target_campaign_ref': 'no-es-uuid'},
        {'target_campaign_ref': campaignWinter.toUpperCase()},
        {'target_campaign_ref': campaignWinter, 'tenant_ref': memberA.tenantId},
        {'tenant_ref': campaignWinter},
      ]) {
        expect(
          () => config.endpoint(_results, query: query),
          throwsA(isA<AuthApiException>()),
          reason: '$query',
        );
      }
    });

    test('ninguna otra ruta admite consulta, y las demás de la estimación siguen cerradas', () {
      expect(
        () => config.endpoint(
          '/api/v1/sync/v1/references',
          query: {'target_campaign_ref': campaignWinter},
        ),
        throwsA(isA<AuthApiException>()),
      );
      expect(
        () => config.endpoint(
          '/api/v1/estimation/runs',
          query: {'target_campaign_ref': campaignWinter},
        ),
        throwsA(isA<AuthApiException>()),
      );
      expect(config.endpoint('/api/v1/sync/v1/references').hasQuery, isFalse);
    });
  });

  group('consulta y descarga con conexión', () {
    test(
      'los resultados FARMER se piden con el token V2 y la campaña objetivo',
      () async {
        final w = await _world();
        w.central.json(_results, farmerResultsJson());
        final read = await w.service.results(campaignWinter);
        expect(read.results.first.estimateBase, '111000.000000');
        final request = w.central.requests.single;
        expect(request.url.queryParameters, {
          'target_campaign_ref': campaignWinter,
        });
        expect(request.headers['Authorization'], 'Bearer $_token');
        expect(await w.rows(), isEmpty, reason: 'consultar no guarda nada');
      },
    );

    test(
      'la descarga se guarda para el titular y se lee sin volver a pedirla',
      () async {
        final w = await _world();
        w.central.json(_download, farmerDownloadJson());
        final (outcome, copy) = await w.service.download(campaignWinter);
        expect(outcome, EstimationSaveOutcome.saved);
        expect(copy!.download.target.campaignRef, campaignWinter);
        expect((await w.rows()).single['owner_binding_id'], w.binding.id);
        final requests = w.central.requests.length;
        expect(await w.service.readableCopies(), hasLength(1));
        expect(w.central.requests.length, requests);
      },
    );

    test('una respuesta que llega después del cierre de sesión no se guarda para nadie', () async {
      final w = await _world();
      final release = Completer<void>();
      w.central.routes[_download] = () async {
        await release.future;
        return http.Response.bytes(
          utf8.encode(jsonEncode(farmerDownloadJson())),
          200,
        );
      };
      final pending = w.service.download(campaignWinter);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // Cierre de sesión mientras la descarga está en curso.
      w.container.read(estimationCopyGuardProvider);
      w.container.read(runtimeSessionTransitionProvider.notifier).signedOut();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      release.complete();
      final (outcome, _) = await pending;
      expect(outcome, EstimationSaveOutcome.accessChanged);
      expect(await w.rows(), isEmpty);
    });
  });

  group('rechazos: la copia nunca queda como alternativa', () {
    for (final (status, message, rejection) in [
      (401, 'Unauthorized', EstimationRejection.session),
      (403, 'Forbidden resource', EstimationRejection.permission),
      (409, 'POLICY_PENDING', EstimationRejection.policy),
    ]) {
      test('$status $message borra las copias del titular', () async {
        final w = await _world();
        w.central.json(_download, farmerDownloadJson());
        await w.service.download(campaignWinter);
        w.central.json(_download, farmerDownloadJson(campaign: campaignSummer));
        await w.service.download(campaignSummer);
        w.central.error(_results, status, message);
        await expectLater(
          w.service.results(campaignWinter),
          throwsA(
            isA<EstimationRejectedException>()
                .having((e) => e.rejection, 'rejection', rejection)
                .having((e) => e.discarded, 'discarded', isTrue),
          ),
        );
        expect(await w.rows(), isEmpty);
        expect(await w.service.readableCopies(), isEmpty);
        if (status != 409) expect(w.holder.current, isNull);
      });
    }

    test(
      'un perfil que no es el del Agricultor es un permiso perdido',
      () async {
        final w = await _world();
        w.central.json(_download, farmerDownloadJson());
        await w.service.download(campaignWinter);
        w.central.json(
          _results,
          farmerResultsJson()..['profile'] = 'INSTITUTIONAL',
        );
        await expectLater(
          w.service.results(campaignWinter),
          throwsA(
            isA<EstimationRejectedException>().having(
              (e) => e.rejection,
              'rejection',
              EstimationRejection.permission,
            ),
          ),
        );
        expect(await w.rows(), isEmpty);
      },
    );

    test('un 404 borra sólo la copia de esa campaña', () async {
      final w = await _world();
      w.central.json(_download, farmerDownloadJson());
      await w.service.download(campaignWinter);
      w.central.json(_download, farmerDownloadJson(campaign: campaignSummer));
      await w.service.download(campaignSummer);
      w.central.error(_download, 404, 'TARGET_CAMPAIGN_NOT_FOUND');
      await expectLater(
        w.service.download(campaignSummer),
        throwsA(
          isA<EstimationRejectedException>().having(
            (e) => e.rejection,
            'rejection',
            EstimationRejection.notFound,
          ),
        ),
      );
      expect(
        (await w.service.readableCopies()).map(
          (c) => c.download.target.campaignRef,
        ),
        [campaignWinter],
      );
    });

    test('si el borrado falla, la copia deja de leerse en esta ejecución y no se afirma borrada', () async {
      final w = await _world();
      w.central.json(_download, farmerDownloadJson());
      await w.service.download(campaignWinter);
      // El borrado falla: la tabla de acceso no admite borrar (inyectado en la prueba).
      final db = await w.database.database;
      await db.execute(
        "CREATE TRIGGER t_no_delete BEFORE DELETE ON estimation_copies "
        "BEGIN SELECT RAISE(ABORT, 'borrado inyectado'); END",
      );
      w.central.error(_results, 403, 'Forbidden resource');
      await expectLater(
        w.service.results(campaignWinter),
        throwsA(
          isA<EstimationRejectedException>().having(
            (e) => e.discarded,
            'discarded',
            isFalse,
          ),
        ),
      );
      expect(await w.rows(), hasLength(1));
      expect(await w.service.readableCopies(), isEmpty);
    });
  });

  group('sin conexión e identidad', () {
    test('sin conexión: la consulta no responde y la copia del titular se sigue leyendo', () async {
      final w = await _world();
      w.central.json(_download, farmerDownloadJson());
      await w.service.download(campaignWinter);
      w.central.routes.clear();
      await expectLater(
        w.service.results(campaignWinter),
        throwsA(
          isA<EstimationUnavailableException>().having(
            (e) => e.reason,
            'reason',
            EstimationUnavailable.offline,
          ),
        ),
      );
      expect(await w.service.readableCopies(), hasLength(1));
    });

    test(
      'sin token y sin red, verificar el acceso no rechaza: es sin conexión',
      () async {
        final w = await _world(token: false);
        await expectLater(
          w.service.campaigns(),
          throwsA(
            isA<EstimationUnavailableException>().having(
              (e) => e.reason,
              'reason',
              EstimationUnavailable.offline,
            ),
          ),
        );
        expect(w.central.requests, isEmpty);
      },
    );

    test('una sesión que hay que volver a verificar no ofrece la copia como alternativa', () async {
      final w = await _world(
        token: false,
        verify: RemoteSessionPhase.requiresReauthentication,
      );
      await expectLater(
        w.service.results(campaignWinter),
        throwsA(
          isA<EstimationUnavailableException>().having(
            (e) => e.reason,
            'reason',
            EstimationUnavailable.sessionRejected,
          ),
        ),
      );
    });

    test('sin la instalación activada para el titular no se lee ni se consulta nada', () async {
      final w = await _world(state: InstallationAccessState.identityMismatch);
      // Una copia del titular que quedó en la base (escrita directamente).
      final identity = EstimationIdentity(
        memberId: memberA.memberId,
        tenantId: memberA.tenantId,
        bindingId: w.binding.id,
      );
      final grant = await w.store.grant(identity);
      final json = farmerDownloadJson();
      await w.store.save(grant, FarmerDownload.fromJson(json), json);
      expect(await w.service.readableCopies(), isEmpty);
      await expectLater(
        w.service.results(campaignWinter),
        throwsA(
          isA<EstimationUnavailableException>().having(
            (e) => e.reason,
            'reason',
            EstimationUnavailable.noIdentity,
          ),
        ),
      );
      expect(w.central.requests, isEmpty);
      // Y se elimina físicamente: ya no era legible.
      expect(await w.rows(), isEmpty);
    });

    test('el cierre de sesión descarta la copia', () async {
      final w = await _world();
      w.central.json(_download, farmerDownloadJson());
      await w.service.download(campaignWinter);
      w.container.read(estimationCopyGuardProvider);
      w.container.read(runtimeSessionTransitionProvider.notifier).signedOut();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await w.rows(), isEmpty);
    });
  });
}
