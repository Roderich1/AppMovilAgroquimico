// D-F04-C2, C2-R1 y C2-R2 (CONTINUACION_TRAS_115_REVISION_116_2026-10-17.md §2):
//
// - Un intento registrado (attempts > 0) no demuestra que Central recibiera la
//   intención. Bajo una campaña cuya compatibilidad temporal no está
//   demostrada, ninguna intención con valor sale por POST: lo que ya salió
//   alguna vez se concilia con `GET /operations/{id}` o queda retenido con el
//   motivo visible. Un 404 no autoriza publicar.
// - La elegibilidad temporal se revalida dentro de la transacción que marca
//   el envío: si cambió entre la selección y el marcado, ni SENDING, ni
//   intento, ni transporte.
//
// El Central falso distingue «la primera petición nunca llegó» (500 sin
// registrar nada) de «commit hecho y ACK perdido» (registra y corta la
// respuesta), cuenta las aceptaciones nuevas y responde al GET. Las pruebas
// usan sólo la API que existía en `5c07dd1`, para poder ejecutarlas tal cual
// sobre ese HEAD y registrar el fallo previo.
//
// Pruebas de HOST. No son DEVICE.
import 'dart:convert';
import 'dart:math';

import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/sync/central_binding_store.dart';
import 'package:agroquimicos/data/sync/declared_need_store.dart';
import 'package:agroquimicos/data/sync/sync_outbox_store.dart';
import 'package:agroquimicos/domain/sync/central_references.dart';
import 'package:agroquimicos/domain/sync/sync_types.dart';
import 'package:agroquimicos/services/auth/api_endpoint_config.dart';
import 'package:agroquimicos/services/auth/auth_http_client.dart';
import 'package:agroquimicos/services/sync/sync_access.dart';
import 'package:agroquimicos/services/sync/sync_api.dart';
import 'package:agroquimicos/services/sync/sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';
import 'support/f05_sync_fixtures.dart';

String _civil(String day) => '${day}T00:00:00.000Z';

CentralReferences _references({String? end, bool accepts = true}) =>
    CentralReferences([
      centralCampaign(
        accepts: accepts,
        endDate: end == null ? null : _civil(end),
      ),
    ], referencesWith().products);

/// Central falso con memoria: sabe qué operaciones aceptó de verdad.
class FakeCentral {
  /// operationId → ACK APPLIED devuelto (o perdido) al aceptarla.
  final accepted = <String, String>{};
  final posts = <Map<String, dynamic>>[];
  var gets = 0;

  /// Aceptaciones **nuevas** (primera vez que Central registra un operationId).
  var newAcceptances = 0;

  /// La próxima petición POST no llega: 500 sin registrar nada.
  bool dropNextPost = false;

  /// La próxima petición POST se acepta y la respuesta se pierde.
  bool loseNextAck = false;

  /// Si está puesto, el GET responde esto (o lanza) en lugar de consultar.
  http.Response Function(String operationId)? getOverride;

  var _clock = 0;

  late final client = MockClient((request) async {
    if (request.method == 'GET') {
      gets++;
      final id = request.url.pathSegments.last;
      final override = getOverride;
      if (override != null) return override(id);
      final ack = accepted[id];
      if (ack == null) {
        return http.Response(
          errorJson('OPERATION_NOT_FOUND', 'KEEP_FOR_RETRY'),
          404,
        );
      }
      return http.Response(
        jsonEncode({
          'ack': jsonDecode(ack.replaceFirst('"APPLIED"', '"ALREADY_APPLIED"')),
          'contribution': {
            'status': 'ACTIVE',
            'headOperationId': id,
            'reconciliationReference': null,
          },
        }),
        200,
      );
    }
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    posts.add(body);
    if (dropNextPost) {
      dropNextPost = false;
      return http.Response('', 500);
    }
    final id = body['operationId'] as String;
    var ack = accepted[id];
    final String response;
    if (ack == null) {
      _clock++;
      newAcceptances++;
      ack = ackJson(
        id,
        acceptedAt:
            '2026-10-15T12:00:${_clock.toString().padLeft(2, '0')}.000Z',
      );
      accepted[id] = ack;
      response = ack;
    } else {
      response = ack.replaceFirst('"APPLIED"', '"ALREADY_APPLIED"');
    }
    if (loseNextAck) {
      loseNextAck = false;
      throw http.ClientException('respuesta perdida después del commit');
    }
    return http.Response(response, 200);
  });

  List<String> get postActions => [
    for (final body in posts) body['action'] as String,
  ];
}

/// Outbox que, tras seleccionar lo listo, ejecuta una acción una sola vez
/// (p. ej. invalidar el período) **antes** de que el worker marque el envío.
/// Reproduce la carrera de C2-R2 de forma determinista.
class RacingOutbox extends SyncOutboxStore {
  RacingOutbox(super.database, {super.clock});

  Future<void> Function()? afterSelect;

  @override
  Future<List<OutboxEntry>> readyToSend({
    required int activeBindingId,
    required DateTime now,
    Set<String> exclude = const {},
  }) async {
    final ready = await super.readyToSend(
      activeBindingId: activeBindingId,
      now: now,
    );
    final action = afterSelect;
    if (ready.isNotEmpty && action != null) {
      afterSelect = null;
      await action();
    }
    return [
      for (final entry in ready)
        if (!exclude.contains(entry.operationId)) entry,
    ];
  }
}

class Harness {
  Harness(this.fixture, this.central, this.access, this.worker, this.outbox);
  final SyncFixture fixture;
  final FakeCentral central;
  final SyncAccessHolder access;
  final SyncWorker worker;
  final SyncOutboxStore outbox;

  /// Reloj del worker: se adelanta para saltar el backoff.
  var clock = DateTime.utc(2026, 10, 15, 12);
  void later() => clock = clock.add(const Duration(hours: 1));

  Future<OutboxEntry> single() async => (await outbox.entries()).single;

  Future<Map<String, Object?>> row(String operationId) async =>
      (await (await fixture.database.database).query(
        'sync_outbox',
        where: 'operation_id=?',
        whereArgs: [operationId],
      )).single;
}

Future<Harness> harness({
  SyncFixture? fixture,
  SyncOutboxStore Function(SyncFixture)? outboxFactory,
}) async {
  final seeded = fixture ?? await seedSyncFixture();
  final central = FakeCentral();
  final access = SyncAccessHolder()
    ..accept('token-sintetico', memberA.memberId, memberA.tenantId);
  final outbox = outboxFactory?.call(seeded) ?? seeded.outbox;
  late Harness h;
  final api = SyncApi(
    AuthHttpClient(
      config: ApiEndpointConfig(Uri.parse('https://sindicato.example')),
      client: central.client,
    ),
    clock: () => h.clock,
  );
  final worker = SyncWorker(
    outbox: outbox,
    owners: seeded.owners,
    api: () => api,
    access: access,
    random: Random(7),
    clock: () => h.clock,
  );
  h = Harness(seeded, central, access, worker, outbox);
  return h;
}

Future<int> declare(SyncFixture fixture, int quantity) => fixture.needs.declare(
  referenceDate: inCampaign,
  productId: fixture.litreProductId,
  quantityBase: quantity,
);

/// Deja `campaign_bindings` como en v9 (sin período central) y la base en 9.
Future<void> downgradeCampaignBindingsToV9(String path) async {
  final db = await databaseFactoryFfi.openDatabase(path);
  await db.execute('''CREATE TABLE campaign_bindings_v9 (
        campaign_id INTEGER PRIMARY KEY REFERENCES campaigns(id),
        tenant_id TEXT NOT NULL, campaign_ref TEXT NOT NULL,
        central_name TEXT NOT NULL,
        status TEXT NOT NULL CHECK(status IN ('VALID','INVALID')),
        invalid_reason TEXT CHECK(invalid_reason IN ('REFERENCE_MISSING','NOT_ACCEPTING')),
        bound_at TEXT NOT NULL, checked_at TEXT NOT NULL,
        CHECK((status = 'VALID') = (invalid_reason IS NULL)))''');
  await db.execute(
    'INSERT INTO campaign_bindings_v9 SELECT campaign_id, tenant_id, '
    'campaign_ref, central_name, status, invalid_reason, bound_at, checked_at '
    'FROM campaign_bindings',
  );
  await db.execute('DROP TABLE campaign_bindings');
  await db.execute(
    'ALTER TABLE campaign_bindings_v9 RENAME TO campaign_bindings',
  );
  await db.execute(
    'CREATE UNIQUE INDEX idx_campaign_bindings_ref '
    'ON campaign_bindings(tenant_id, campaign_ref)',
  );
  await db.delete(
    'app_settings',
    where: 'key=?',
    whereArgs: [AppDatabase.campaignPeriodReviewKey],
  );
  await db.execute('PRAGMA user_version = 9');
  await db.close();
}

void main() {
  sqfliteFfiInit();

  group('C2-R1: un intento no demuestra recepción en Central', () {
    test('1. la primera petición nunca llegó; después el período es incompatible: ningún POST con valor, ninguna aceptación nueva', () async {
      final h = await harness();
      await declare(h.fixture, 2000);
      h.central.dropNextPost = true;
      var report = await h.worker.run();
      expect(report.sent, 1);
      var entry = await h.single();
      expect(entry.status, OutboxStatus.outcomeUnknown);
      expect(entry.attempts, 1);
      expect(h.central.newAcceptances, 0, reason: 'Central no la recibió');

      await h.fixture.bindings.refreshFrom(
        _references(end: '2026-10-31'),
        memberA.tenantId,
      );
      h.later();
      report = await h.worker.run();
      expect(report.sent, 0, reason: 'bajo período incompatible no sale POST');
      expect(h.central.posts, hasLength(1), reason: 'sólo el POST original');
      expect(h.central.newAcceptances, 0);
      expect(h.central.gets, 1, reason: 'se consulta, no se reenvía');
      entry = await h.single();
      expect(entry.status, OutboxStatus.outcomeUnknown);
      expect(entry.attempts, 1, reason: 'la consulta no cuenta como intento');
      expect(entry.lastCode, 'OPERATION_NOT_FOUND');
      expect((await h.outbox.summary()).heldForPeriod, 1);

      // Otro ciclo: sigue retenida, sin POST; el 404 no autoriza publicar.
      h.later();
      await h.worker.run();
      expect(h.central.posts, hasLength(1));
      expect(h.central.newAcceptances, 0);

      // Al caber de nuevo, la misma intención sale por POST (idempotencia).
      await h.fixture.repo.setCampaignEnd(
        h.fixture.campaignId,
        end: DateTime(2026, 10, 31),
      );
      h.later();
      report = await h.worker.run();
      expect(report.accepted, 1);
      expect(h.central.posts, hasLength(2));
      expect(h.central.posts.last['operationId'], entry.operationId);
      expect(h.central.newAcceptances, 1);
      expect((await h.single()).status, OutboxStatus.acked);
    });

    test('2. aceptada con el ACK perdido; después el período es incompatible: se concilia por GET, sin POST nuevo', () async {
      final h = await harness();
      await declare(h.fixture, 2000);
      h.central.loseNextAck = true;
      await h.worker.run();
      var entry = await h.single();
      expect(entry.status, OutboxStatus.outcomeUnknown);
      expect(h.central.newAcceptances, 1, reason: 'Central sí la aceptó');

      await h.fixture.bindings.refreshFrom(
        _references(end: '2026-10-31'),
        memberA.tenantId,
      );
      h.later();
      final report = await h.worker.run();
      expect(h.central.posts, hasLength(1), reason: 'ningún POST nuevo');
      expect(h.central.gets, 1);
      expect(report.accepted, 1);
      entry = await h.single();
      expect(entry.status, OutboxStatus.acked);
      expect(entry.serverAcceptedAt, '2026-10-15T12:00:01.000Z');
      expect(entry.attempts, 1);
      expect(h.central.newAcceptances, 1);
      expect((await h.outbox.summary()).heldForPeriod, 0);
    });

    test('3. migración v9 con resultado desconocido y período sin comprobar: no publica un valor nuevo', () async {
      final path = await tempDbPath('c2r1_v9');
      final seeded = await seedSyncFixture(path: path);
      final first = await harness(fixture: seeded);
      await declare(seeded, 2000);
      first.central.dropNextPost = true;
      await first.worker.run();
      expect((await first.single()).status, OutboxStatus.outcomeUnknown);
      await seeded.database.close();
      await downgradeCampaignBindingsToV9(path);

      final reopened = reopenFixture(seeded, openDb(path));
      final h = await harness(fixture: reopened);
      // Base migrada: el vínculo quedó «período sin comprobar».
      expect(
        (await reopened.bindings.campaignBindings()).single.invalidReason,
        BindingInvalidReason.periodUnverified,
      );
      h.later();
      final report = await h.worker.run();
      expect(report.sent, 0);
      expect(h.central.posts, isEmpty);
      expect(h.central.newAcceptances, 0);
      expect(h.central.gets, 1);
      final entry = await h.single();
      expect(entry.status, OutboxStatus.outcomeUnknown);
      expect(entry.attempts, 1);
      expect(entry.lastCode, 'OPERATION_NOT_FOUND');
      expect((await h.outbox.summary()).heldForPeriod, 1);
    });

    group(
      '4. la consulta no da un resultado fiable: ni ACK inventado ni POST',
      () {
        Future<Harness> uncertainUnderIncompatible() async {
          final h = await harness();
          await declare(h.fixture, 2000);
          h.central.dropNextPost = true;
          await h.worker.run();
          await h.fixture.bindings.refreshFrom(
            _references(end: '2026-10-31'),
            memberA.tenantId,
          );
          h.later();
          return h;
        }

        test('401: el acceso se descarta y el ciclo se detiene', () async {
          final h = await uncertainUnderIncompatible();
          h.central.getOverride = (_) =>
              http.Response(errorJson('AUTH_REQUIRED', 'KEEP_FOR_RETRY'), 401);
          final report = await h.worker.run();
          expect(report.blocker, SyncBlocker.accessRequired);
          expect(h.access.current, isNull);
          expect(h.central.posts, hasLength(1));
          final entry = await h.single();
          expect(entry.status, OutboxStatus.outcomeUnknown);
          expect(entry.attempts, 1);
        });

        test('403: la cola del vínculo se pausa, como con un POST', () async {
          final h = await uncertainUnderIncompatible();
          h.central.getOverride = (_) => http.Response(
            errorJson('AUTH_CONTEXT_FORBIDDEN', 'KEEP_FOR_RECONCILIATION'),
            403,
          );
          final report = await h.worker.run();
          expect(report.blocker, SyncBlocker.forbidden);
          expect((await h.single()).status, OutboxStatus.authPaused);
          expect(h.central.posts, hasLength(1));
        });

        test('429: espera, sigue retenida y sin POST', () async {
          final h = await uncertainUnderIncompatible();
          h.central.getOverride = (_) =>
              http.Response(errorJson('RATE_LIMITED', 'KEEP_FOR_RETRY'), 429);
          final report = await h.worker.run();
          expect(report.blocker, SyncBlocker.throttled);
          final entry = await h.single();
          expect(entry.status, OutboxStatus.outcomeUnknown);
          expect(entry.lastCode, 'RATE_LIMITED');
          expect(h.central.posts, hasLength(1));
        });

        test('sin red: resultado desconocido conservado, sin POST', () async {
          final h = await uncertainUnderIncompatible();
          h.central.getOverride = (_) => throw http.ClientException('sin red');
          final report = await h.worker.run();
          expect(report.blocker, SyncBlocker.unreachable);
          final entry = await h.single();
          expect(entry.status, OutboxStatus.outcomeUnknown);
          expect(entry.lastCode, 'UNAVAILABLE');
          expect(h.central.posts, hasLength(1));
        });

        test(
          'respuesta inválida (200 con otro cuerpo): no se confía',
          () async {
            final h = await uncertainUnderIncompatible();
            h.central.getOverride = (id) => http.Response(
              jsonEncode({
                'ack': jsonDecode(ackJson(id)),
                'contribution': null,
                'extra': true,
              }),
              200,
            );
            final report = await h.worker.run();
            expect(report.accepted, 0);
            final entry = await h.single();
            expect(entry.status, OutboxStatus.outcomeUnknown);
            expect(entry.lastCode, 'INVALID_RESPONSE');
            expect(h.central.posts, hasLength(1));
            expect((await h.outbox.summary()).heldForPeriod, 1);
          },
        );

        test('ACK de otra operación en la consulta: no se confía', () async {
          final h = await uncertainUnderIncompatible();
          h.central.getOverride = (_) => http.Response(
            jsonEncode({
              'ack': jsonDecode(
                ackJson('7a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d'),
              ),
              'contribution': null,
            }),
            200,
          );
          await h.worker.run();
          expect((await h.single()).status, OutboxStatus.outcomeUnknown);
          expect(h.central.posts, hasLength(1));
        });
      },
    );

    test('6. otro motivo de invalidez con período desconocido (vínculo migrado NOT_ACCEPTING): tampoco sale', () async {
      final path = await tempDbPath('c2r1_v9_na');
      final seeded = await seedSyncFixture(path: path);
      await declare(seeded, 2000);
      await seeded.bindings.refreshFrom(
        _references(accepts: false),
        memberA.tenantId,
      );
      await seeded.database.close();
      await downgradeCampaignBindingsToV9(path);

      final reopened = reopenFixture(seeded, openDb(path));
      final binding = (await reopened.bindings.campaignBindings()).single;
      expect(binding.invalidReason, BindingInvalidReason.notAccepting);
      expect(binding.centralStartDay, isNull);
      final h = await harness(fixture: reopened);
      final report = await h.worker.run();
      expect(report.sent, 0);
      expect(h.central.posts, isEmpty, reason: 'el período no está demostrado');
      final entry = await h.single();
      expect(entry.status, OutboxStatus.pending);
      expect(entry.attempts, 0);
      expect((await h.outbox.summary()).heldForPeriod, 1);
      expect(
        (await reopened.bindings.campaignReviews()).single.heldIntentions,
        1,
      );
    });
  });

  group('C2-R2: selección y marcado no son una sola decisión', () {
    test('5. el período se invalida entre seleccionar y marcar: cero POST, intentos sin incremento, datos intactos', () async {
      late RacingOutbox racing;
      final h = await harness(
        outboxFactory: (fixture) => racing = RacingOutbox(fixture.database),
      );
      await declare(h.fixture, 2000);
      final before = await dumpTables(
        await h.fixture.database.database,
        except: {'campaign_bindings', 'product_bindings'},
      );
      racing.afterSelect = () => h.fixture.bindings.refreshFrom(
        _references(end: '2026-10-31'),
        memberA.tenantId,
      );
      final report = await h.worker.run();
      expect(report.sent, 0);
      expect(report.blocker, isNull);
      expect(h.central.posts, isEmpty);
      final entry = await h.single();
      expect(entry.status, OutboxStatus.pending);
      expect(entry.attempts, 0);
      expect(
        await dumpTables(
          await h.fixture.database.database,
          except: {'campaign_bindings', 'product_bindings'},
        ),
        before,
        reason: 'ni la outbox ni el negocio cambian',
      );
      expect(racing.afterSelect, isNull, reason: 'la carrera sí se produjo');
    });

    test('una retirada (CANCEL) no se retiene al marcar', () async {
      late RacingOutbox racing;
      final h = await harness(
        outboxFactory: (fixture) => racing = RacingOutbox(fixture.database),
      );
      final needId = await declare(h.fixture, 2000);
      await h.worker.run();
      expect((await h.single()).status, OutboxStatus.acked);
      await h.fixture.needs.withdraw(needId);
      racing.afterSelect = () => h.fixture.bindings.refreshFrom(
        _references(end: '2026-10-31'),
        memberA.tenantId,
      );
      h.later();
      final report = await h.worker.run();
      expect(report.sent, 1);
      expect(h.central.postActions.last, 'CANCEL');
    });
  });

  group('7. el camino compatible no cambia', () {
    test(
      'reintento normal tras un fallo: mismo operationId, aceptado',
      () async {
        final h = await harness();
        await declare(h.fixture, 2000);
        h.central.dropNextPost = true;
        await h.worker.run();
        expect((await h.single()).status, OutboxStatus.outcomeUnknown);
        h.later();
        final report = await h.worker.run();
        expect(report.accepted, 1);
        expect(
          h.central.gets,
          0,
          reason: 'compatible: no hace falta consultar',
        );
        expect(h.central.posts, hasLength(2));
        expect(
          h.central.posts.first['operationId'],
          h.central.posts.last['operationId'],
        );
        expect((await h.single()).status, OutboxStatus.acked);
      },
    );

    test('CANCEL confirmado bajo período incompatible: sale con su antecesor y causalidad intactos', () async {
      final h = await harness();
      final needId = await declare(h.fixture, 2000);
      await h.worker.run();
      final accepted = await h.single();
      expect(accepted.status, OutboxStatus.acked);
      await h.fixture.bindings.refreshFrom(
        _references(end: '2026-10-31'),
        memberA.tenantId,
      );
      // Un valor nuevo no se puede declarar; retirar sí.
      await expectLater(
        h.fixture.needs.updateQuantity(needId, 3000),
        throwsA(isA<BindingRequiredException>()),
      );
      await h.fixture.needs.withdraw(needId);
      h.later();
      final report = await h.worker.run();
      expect(report.sent, 1);
      final cancel = h.central.posts.last;
      expect(cancel['action'], 'CANCEL');
      expect(
        (cancel['causal'] as Map)['predecessorOperationId'],
        accepted.operationId,
      );
      expect((cancel['payload'] as Map).containsKey('quantity_base'), isFalse);
      final entries = await h.outbox.entries();
      expect(entries.map((e) => e.status), everyElement(OutboxStatus.acked));
      // La fila aceptada original no cambió.
      final original = await h.row(accepted.operationId);
      expect(original['server_accepted_at'], accepted.serverAcceptedAt);
      expect(original['attempts'], accepted.attempts);
    });
  });
}
