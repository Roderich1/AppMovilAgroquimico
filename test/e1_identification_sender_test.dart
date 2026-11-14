// Contrato E1 §4.1, §4.3 y §5.3: emisor de solicitudes de identificación con
// MockClient. Datos primero y foto sólo tras RECEIVED; mismo request_id en
// cada reenvío; códigos terminales sin reintento; 401/403 pausan; 5xx y red
// se reintentan con SyncBackoff; la vista del sindicato se guarda con lista
// cerrada y nunca vincula. Sin red real; datos sintéticos.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:agroquimicos/data/sync/identification_request_store.dart';
import 'package:agroquimicos/domain/installation_access.dart';
import 'package:agroquimicos/services/auth/api_endpoint_config.dart';
import 'package:agroquimicos/services/auth/auth_api_exception.dart';
import 'package:agroquimicos/services/auth/auth_http_client.dart';
import 'package:agroquimicos/services/sync/identification_api.dart';
import 'package:agroquimicos/services/sync/identification_request_sender.dart';
import 'package:agroquimicos/services/sync/sync_access.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/e1_identification_fixtures.dart';
import 'support/f04_mode_fixtures.dart';
import 'support/f05_sync_fixtures.dart';

const _base = '/api/v1/catalog/identification-requests';

http.Response _json(Object body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

http.Response _error(String code, int status) =>
    _json({'errorCode': code}, status);

void main() {
  sqfliteFfiInit();

  late SyncFixture fixture;
  late IdentificationRequestStore store;
  late PhotoWorkspace photos;
  late IdentificationRequestSender sender;
  late List<http.Request> requests;
  late http.Response Function(http.Request request) respond;
  late DateTime now;
  final config = ApiEndpointConfig(Uri.parse('https://sindicato.example'));

  VerifiedAccess access([OwnerScope scope = memberA]) => VerifiedAccess(
    accessToken: 'token-sintetico',
    scope: scope,
    obtainedAt: now,
  );

  /// Respuesta por defecto: el sindicato acepta y lista lo recibido.
  final received = <String, Map<String, Object?>>{};
  http.Response central(http.Request request) {
    final path = request.url.path;
    if (request.method == 'GET' && path == _base) {
      return _json({
        'contractVersion': 1,
        'requests': received.values.toList(),
      }, 200);
    }
    final id = path.split('/')[5];
    if (request.method == 'PUT' && path.endsWith('/photo')) {
      final view = {
        ...received[id]!,
        'photo': {
          'state': 'STORED',
          'sha256': request.headers['x-content-sha256'],
          'consent_version': 'FOTO-1',
        },
      };
      received[id] = view;
      return _json(view, 200);
    }
    if (request.method == 'DELETE') {
      return http.Response('', 204);
    }
    final existed = received.containsKey(id);
    received[id] = serverView(id);
    return _json(received[id]!, existed ? 200 : 201);
  }

  setUp(() async {
    now = DateTime.utc(2026, 11, 11, 18, 20);
    received.clear();
    fixture = await seedSyncFixture();
    store = IdentificationRequestStore(fixture.database, clock: () => now);
    photos = await photoWorkspace(fixture);
    requests = [];
    respond = central;
    final client = MockClient((request) async {
      requests.add(request);
      return respond(request);
    });
    final api = IdentificationApi(
      json: AuthHttpClient(config: config, client: client),
      config: config,
      client: client,
      clock: () => now,
    );
    sender = IdentificationRequestSender(
      store: store,
      owners: fixture.owners,
      api: () => api,
      photoOf: photos.repo.productPhoto,
      random: Random(7),
      clock: () => now,
    );
  });

  Future<IdentificationRequest> create({bool withPhoto = false}) async {
    if (withPhoto) await photos.savePhoto(fixture.unboundProductId);
    return store.create(
      productId: fixture.unboundProductId,
      sharePhoto: withPhoto,
    );
  }

  Future<IdentificationRequest> reload(String id) async =>
      (await store.byId(id))!;

  List<String> calls() => [
    for (final r in requests)
      '${r.method} ${r.url.path.replaceFirst(_base, '')}',
  ];

  test('sin solicitudes no hay ninguna llamada de red', () async {
    final report = await sender.run(access());
    expect(requests, isEmpty);
    expect(report.received, 0);
  });

  test('envía sólo nombre, ingrediente, unidad y consentimiento; nunca ids locales ni Sync v1', () async {
    final request = await create();
    final report = await sender.run(access());
    expect(report.received, 1);
    expect(calls(), ['PUT /${request.requestId}', 'GET ']);
    final put = requests.first;
    expect(put.headers['authorization'], 'Bearer token-sintetico');
    expect(put.headers['content-type'], startsWith('application/json'));
    expect(jsonDecode(put.body), {
      'contractVersion': 1,
      'local_name': 'Adherente local',
      'active_ingredient': null,
      'unit': 'L',
      'photo_consent': null,
    });
    expect(requests.every((r) => !r.url.path.contains('/sync/')), isTrue);
    final row = await reload(request.requestId);
    expect(row.sendStatus, IdentificationSendStatus.received);
    expect(row.serverStatus, 'PENDING');
    expect(await fixture.outboxRows(), isEmpty);
  });

  test(
    'un reenvío usa el mismo request_id: 201 y luego 200 no duplican',
    () async {
      final request = await create();
      // Primer intento: la respuesta se pierde (el sindicato sí la creó).
      respond = (r) {
        central(r);
        throw const SocketException('sin respuesta');
      };
      var report = await sender.run(access());
      expect(report.retried, 1);
      var row = await reload(request.requestId);
      expect(row.sendStatus, IdentificationSendStatus.pendingSend);
      expect(row.lastCode, 'NETWORK');
      expect(row.nextAttemptAt, isNotNull);

      // Reintento: el sindicato responde 200 con el estado vigente.
      respond = central;
      now = now.add(const Duration(minutes: 20));
      report = await sender.run(access());
      expect(report.received, 1);
      final puts = requests.where((r) => r.method == 'PUT').toList();
      expect(puts, hasLength(2));
      expect(puts.map((r) => r.url.path).toSet(), {
        '$_base/${request.requestId}',
      });
      expect(puts.map((r) => r.body).toSet(), hasLength(1));
      expect(received, hasLength(1));
      row = await reload(request.requestId);
      expect(row.sendStatus, IdentificationSendStatus.received);
      expect(row.sendAttempts, 2);
      expect(await store.all(), hasLength(1));
    },
  );

  test(
    '503: sigue pendiente con reintento y no sale antes de tiempo',
    () async {
      final request = await create();
      respond = (r) =>
          r.method == 'PUT' ? _error('SERVICE_UNAVAILABLE', 503) : central(r);
      await sender.run(access());
      final row = await reload(request.requestId);
      expect(row.sendStatus, IdentificationSendStatus.pendingSend);
      expect(row.sendAttempts, 1);
      expect(row.lastCode, 'SERVICE_UNAVAILABLE');
      final retryAt = DateTime.parse(row.nextAttemptAt!);
      expect(retryAt.isAfter(now), isTrue);

      requests.clear();
      await sender.run(access());
      expect(calls(), ['GET '], reason: 'antes del reintento sólo se consulta');

      respond = central;
      now = retryAt.add(const Duration(seconds: 1));
      requests.clear();
      await sender.run(access());
      expect(calls().first, 'PUT /${request.requestId}');
      expect(
        (await reload(request.requestId)).sendStatus,
        IdentificationSendStatus.received,
      );
    },
  );

  test('422 UNIT_UNSUPPORTED: rechazada sin reintento', () async {
    final request = await create();
    respond = (r) =>
        r.method == 'PUT' ? _error('UNIT_UNSUPPORTED', 422) : central(r);
    final report = await sender.run(access());
    expect(report.rejected, 1);
    final row = await reload(request.requestId);
    expect(row.sendStatus, IdentificationSendStatus.rejected);
    expect(row.lastCode, 'UNIT_UNSUPPORTED');
    expect(row.nextAttemptAt, isNull);

    requests.clear();
    now = now.add(const Duration(days: 1));
    await sender.run(access(), includePaused: true);
    expect(calls(), ['GET ']);
  });

  test('401: queda pausada y sólo se reanuda con un envío explícito', () async {
    final request = await create();
    respond = (r) => _error('AUTH_REQUIRED', 401);
    final report = await sender.run(access());
    expect(report.authFailed, isTrue);
    expect(calls(), ['PUT /${request.requestId}']);
    expect(
      (await reload(request.requestId)).sendStatus,
      IdentificationSendStatus.authPaused,
    );

    respond = central;
    requests.clear();
    await sender.run(access());
    expect(calls(), [
      'GET ',
    ], reason: 'el ciclo automático no reanuda lo pausado');

    requests.clear();
    await sender.run(access(), includePaused: true);
    expect(calls().first, 'PUT /${request.requestId}');
    expect(
      (await reload(request.requestId)).sendStatus,
      IdentificationSendStatus.received,
    );
  });

  test('con otra cuenta en sesión no se envía nada', () async {
    await create();
    final report = await sender.run(access(memberB));
    expect(report.ownerMismatch, isTrue);
    expect(requests, isEmpty);
  });

  group('foto', () {
    test(
      'datos primero, luego la foto en octet-stream con su SHA-256 y tamaño',
      () async {
        final request = await create(withPhoto: true);
        final photo = (await photos.repo.productPhoto(
          fixture.unboundProductId,
        ))!;
        final bytes = await photo.file.readAsBytes();
        final report = await sender.run(access());
        expect(report.received, 1);
        expect(report.photosSent, 1);
        expect(calls(), [
          'PUT /${request.requestId}',
          'PUT /${request.requestId}/photo',
          'GET ',
        ]);
        final dataBody = jsonDecode(requests.first.body) as Map;
        expect(dataBody['photo_consent'], {
          'version': 'FOTO-1',
          'accepted_at': request.photoConsentAt,
        });
        final upload = requests[1];
        expect(upload.headers['content-type'], 'application/octet-stream');
        expect(upload.headers['x-content-sha256'], photo.sha256);
        expect(upload.headers['authorization'], 'Bearer token-sintetico');
        expect(upload.bodyBytes, bytes);
        expect(upload.contentLength, bytes.length);
        expect(
          crypto.sha256.convert(upload.bodyBytes).toString(),
          photo.sha256,
        );
        final row = await reload(request.requestId);
        expect(row.photoSendStatus, IdentificationPhotoStatus.sent);
      },
    );

    test(
      'la foto falla (503) y los datos quedan recibidos; luego se reintenta',
      () async {
        final request = await create(withPhoto: true);
        respond = (r) => r.url.path.endsWith('/photo')
            ? _error('PHOTO_STORAGE_UNAVAILABLE', 503)
            : central(r);
        final report = await sender.run(access());
        expect(report.received, 1);
        expect(report.photosFailed, 1);
        var row = await reload(request.requestId);
        expect(row.sendStatus, IdentificationSendStatus.received);
        expect(row.photoSendStatus, IdentificationPhotoStatus.failed);
        expect(row.photoRetryable, isTrue);
        expect(row.photoLastCode, 'PHOTO_STORAGE_UNAVAILABLE');

        respond = central;
        now = DateTime.parse(row.photoNextAttemptAt!)
            .add(const Duration(seconds: 1));
        requests.clear();
        await sender.run(access());
        // Antes de la foto se reenvía el consentimiento vigente.
        expect(calls(), [
          'PUT /${request.requestId}',
          'PUT /${request.requestId}/photo',
          'GET ',
        ]);
        row = await reload(request.requestId);
        expect(row.photoSendStatus, IdentificationPhotoStatus.sent);
        expect(row.sendStatus, IdentificationSendStatus.received);
      },
    );

    test('409 PHOTO_CONSENT_REQUIRED: la foto falla sin reintento, los datos siguen recibidos', () async {
      final request = await create(withPhoto: true);
      respond = (r) => r.url.path.endsWith('/photo')
          ? _error('PHOTO_CONSENT_REQUIRED', 409)
          : central(r);
      await sender.run(access());
      final row = await reload(request.requestId);
      expect(row.sendStatus, IdentificationSendStatus.received);
      expect(row.photoSendStatus, IdentificationPhotoStatus.failed);
      expect(row.photoRetryable, isFalse);
      expect(row.photoLastCode, 'PHOTO_CONSENT_REQUIRED');

      requests.clear();
      now = now.add(const Duration(days: 1));
      await sender.run(access(), includePaused: true);
      expect(calls(), ['GET ']);
    });

    test('422 IMAGE_INVALID: definitivo', () async {
      final request = await create(withPhoto: true);
      respond = (r) => r.url.path.endsWith('/photo')
          ? _error('IMAGE_INVALID', 422)
          : central(r);
      await sender.run(access());
      final row = await reload(request.requestId);
      expect(row.photoSendStatus, IdentificationPhotoStatus.failed);
      expect(row.photoRetryable, isFalse);
    });

    test(
      'si la foto autorizada ya no es la del teléfono, no se envía otra',
      () async {
        final request = await create(withPhoto: true);
        // Reemplazada sólo en el teléfono antes de enviarse... con un intento
        // previo (no se descarta en silencio).
        await store.markReceived(request.requestId);
        await store.markPhotoFailed(request.requestId, 'NETWORK', retryAt: now);
        await photos.savePhoto(fixture.unboundProductId, seed: 2);
        await sender.run(access());
        expect(requests.where((r) => r.url.path.endsWith('/photo')), isEmpty);
        final row = await reload(request.requestId);
        expect(row.photoSendStatus, IdentificationPhotoStatus.failed);
        expect(row.photoLastCode, 'PHOTO_MISSING');
      },
    );

    test('quitar una foto enviada la retira del sindicato (DELETE)', () async {
      final request = await create(withPhoto: true);
      await sender.run(access());
      expect(
        (await reload(request.requestId)).photoSendStatus,
        IdentificationPhotoStatus.sent,
      );
      await photos.repo.removeProductPhoto(fixture.unboundProductId);
      expect(
        (await reload(request.requestId)).photoSendStatus,
        IdentificationPhotoStatus.removePending,
      );
      requests.clear();
      final report = await sender.run(access());
      expect(report.photosRemoved, 1);
      expect(calls(), ['DELETE /${request.requestId}/photo', 'GET ']);
      expect(
        (await reload(request.requestId)).photoSendStatus,
        IdentificationPhotoStatus.removed,
      );
    });
  });

  group('vista del sindicato', () {
    test('LINKED se guarda y no vincula nada', () async {
      final request = await create();
      await sender.run(access());
      received[request.requestId] = serverView(request.requestId, linked: true);
      final report = await sender.run(access());
      expect(report.viewsApplied, 1);
      final row = await reload(request.requestId);
      expect(row.serverStatus, 'LINKED');
      expect(row.serverProductRef, identifiedRef);
      expect(row.serverProductName, 'Herbicida central');
      expect(
        (await fixture.bindings.productBindings()).map((b) => b.productId),
        isNot(contains(fixture.unboundProductId)),
      );
    });

    test('una clave desconocida en la lista no se aplica', () async {
      final request = await create();
      await sender.run(access());
      received[request.requestId] = serverView(
        request.requestId,
        linked: true,
        extra: {'reported_by': 'Persona'},
      );
      final report = await sender.run(access());
      expect(report.listUnavailable, isTrue);
      expect(report.viewsApplied, 0);
      expect((await reload(request.requestId)).serverStatus, 'PENDING');
    });

    test('una respuesta 201 con forma inválida no marca recibida', () async {
      final request = await create();
      respond = (r) => r.method == 'PUT'
          ? _json({...serverView(request.requestId), 'extra': true}, 201)
          : central(r);
      await sender.run(access());
      final row = await reload(request.requestId);
      expect(row.sendStatus, IdentificationSendStatus.pendingSend);
      expect(row.lastCode, 'INVALID_RESPONSE');
    });
  });

  group('lista de rutas (ApiEndpointConfig, E1 §4.3)', () {
    const id = '7f4b1c2e-9d3a-4f61-8b2c-0e5a6d7c8b9a';

    test('admite la ruta exacta y el UUID v4 con /photo opcional', () {
      for (final path in [_base, '$_base/$id', '$_base/$id/photo']) {
        expect(config.endpoint(path).path, path);
      }
    });

    test('rechaza cualquier otra forma', () {
      for (final path in [
        '$_base/',
        '$_base/${id.toUpperCase()}',
        '$_base/7f4b1c2e-9d3a-1f61-8b2c-0e5a6d7c8b9a',
        '$_base/$id/photo/',
        '$_base/$id/content',
        '$_base/$id/history',
        '$_base/$id/candidates',
        '$_base/$id/link',
        '$_base/$id/../$id',
        '$_base/%2e%2e/$id',
        '$_base?status=ALL',
        '$_base/$id/photo?x=1',
        '/api/v1/catalog/identification-requests-x',
      ]) {
        expect(
          () => config.endpoint(path),
          throwsA(
            isA<AuthApiException>().having(
              (e) => e.kind,
              'kind',
              AuthApiErrorKind.configuration,
            ),
          ),
          reason: path,
        );
      }
    });
  });
}
