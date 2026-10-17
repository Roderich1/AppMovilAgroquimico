// D-F04-C2: el período de la campaña local tiene que estar contenido en el de
// la campaña central con la que se vincula (extremos inclusivos; RN-15,
// RN-16). Se comprueba al vincular, al refrescar las referencias, al cambiar
// el calendario local, en la vista previa y la confirmación de una
// publicación, y al reabrir sin red. Los aportes anteriores no se reescriben:
// se señalan para revisión; la cola retiene lo que nunca salió; una retirada
// (CANCEL) con confirmación del titular sigue permitida.
//
// Fecha civil frente a instante: las fechas centrales se leen como el día
// civil de su `date-time` en UTC (contrato de referencias); las locales, con
// la regla de día local de #110. La CI repite este archivo en
// America/La_Paz; el centinela hace fallar ese paso si la zona no se aplicó.
//
// Pruebas de HOST (sqflite_common_ffi). No son DEVICE.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/backup_service.dart';
import 'package:agroquimicos/data/sync/central_binding_store.dart';
import 'package:agroquimicos/data/sync/consumption_publisher.dart';
import 'package:agroquimicos/data/sync/declared_need_store.dart';
import 'package:agroquimicos/data/sync/sync_outbox_store.dart';
import 'package:agroquimicos/domain/campaign_calendar.dart';
import 'package:agroquimicos/domain/sync/campaign_period_check.dart';
import 'package:agroquimicos/domain/sync/central_references.dart';
import 'package:agroquimicos/domain/sync/consumption_projection.dart'
    show ConsumptionExclusion;
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

import 'schema_equivalence_test.dart' show SchemaSignature;
import 'support/f04_mode_fixtures.dart';
import 'support/f05_sync_fixtures.dart';
import 'support/f06_consumption_fixtures.dart';

/// Desfase local de la zona del piloto (Bolivia, sin horario de verano).
const _laPaz = Duration(hours: -4);

final _now = DateTime.utc(2026, 10, 15, 12);

/// `aaaa-mm-dd` → `date-time` del contrato (medianoche UTC, como lo guarda
/// Central a partir del `type="date"` de la Web).
String _civil(String day) => '${day}T00:00:00.000Z';

CampaignPeriod _local(String start, [String? end]) => CampaignPeriod(
  id: 1,
  name: 'Local',
  status: 'ACTIVE',
  startDay: start,
  endDay: end,
);

CentralPeriod _centralPeriod(String start, [String? end]) =>
    CentralPeriod(startDay: start, endDay: end);

/// Referencias con la campaña central [start]–[end] y los productos de siempre.
CentralReferences _references({
  String start = '2026-09-01',
  String? end,
  bool accepts = true,
}) => CentralReferences([
  centralCampaign(
    accepts: accepts,
    startDate: _civil(start),
    endDate: end == null ? null : _civil(end),
  ),
], referencesWith().products);

/// Transporte guionado: cada handler responde a un request; uno de más falla.
class _Transport {
  _Transport(this.handlers);
  final List<http.Response Function(http.Request)> handlers;
  final requests = <http.Request>[];
  late final client = MockClient((request) async {
    requests.add(request);
    if (requests.length > handlers.length) {
      fail('request inesperado #${requests.length}: ${request.body}');
    }
    return handlers[requests.length - 1](request);
  });
  List<Map<String, dynamic>> get bodies => [
    for (final request in requests)
      jsonDecode(request.body) as Map<String, dynamic>,
  ];
}

http.Response _ack(http.Request request) {
  final id = (jsonDecode(request.body) as Map)['operationId'] as String;
  return http.Response(ackJson(id), 200);
}

SyncWorker _worker(SyncFixture fixture, _Transport transport) {
  final access = SyncAccessHolder(clock: () => _now)
    ..accept('token-sintetico', memberA.memberId, memberA.tenantId);
  final api = SyncApi(
    AuthHttpClient(
      config: ApiEndpointConfig(Uri.parse('https://sindicato.example')),
      client: transport.client,
    ),
    clock: () => _now,
  );
  return SyncWorker(
    outbox: fixture.outbox,
    owners: fixture.owners,
    api: () => api,
    access: access,
    random: Random(7),
    clock: () => _now,
  );
}

Future<CampaignBinding> _binding(SyncFixture fixture) async =>
    (await fixture.bindings.campaignBindings()).single;

Future<Map<String, Object?>> _campaignRow(SyncFixture fixture) async =>
    (await (await fixture.database.database).query(
      'campaigns',
      where: 'id=?',
      whereArgs: [fixture.campaignId],
    )).single;

/// Deja `campaign_bindings` exactamente como en v9 y la base en versión 9.
Future<void> _downgradeCampaignBindingsToV9(String path) async {
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

  group('fecha civil frente a instante', () {
    test('centinela: el paso regional de la CI corre en America/La_Paz', () {
      final expected = Platform.environment['AGRO_TZ_REGRESSION'];
      if (expected == null) {
        markTestSkipped('sólo en el paso regional de la CI');
        return;
      }
      expect(expected, 'America/La_Paz');
      expect(DateTime(2026, 10, 15, 12).timeZoneOffset, _laPaz);
    });

    test(
      'el día civil central es la parte de fecha en UTC, en cualquier zona',
      () {
        // Lo que Central publica para el «2026-09-01» elegido en la Web.
        expect(centralCivilDay('2026-09-01T00:00:00.000Z'), '2026-09-01');
        expect(centralCivilDay('2026-12-31T00:00:00.000Z'), '2026-12-31');
        // Un cierre real (closedAt) a las 23:30 de La Paz es el día siguiente
        // en UTC: se toma el día UTC del contrato, declarado como tal.
        expect(centralCivilDay('2026-03-01T03:30:00.000Z'), '2026-03-01');
        expect(() => centralCivilDay('ayer'), throwsFormatException);
      },
    );

    test('el día local de un instante guardado sigue la regla de #110', () {
      final stored = DateTime(2026, 12, 31, 23, 30).toUtc().toIso8601String();
      expect(storedLocalDay(stored), '2026-12-31');
      final start = DateTime(2026, 9, 1, 0, 5).toUtc().toIso8601String();
      expect(storedLocalDay(start), '2026-09-01');
    });

    test('frontera inclusiva: fin local 31/12 cabe en central hasta 31/12 (también en La Paz)', () {
      // Con una conversión a hora local, el fin central sería el 30/12 en
      // La Paz y esta contención fallaría.
      expect(
        periodMismatch(
          _local('2026-09-01', '2026-12-31'),
          CentralPeriod.of(centralCampaign(endDate: _civil('2026-12-31'))),
        ),
        isNull,
      );
      expect(
        periodMismatch(
          _local('2026-09-01', '2027-01-01'),
          CentralPeriod.of(centralCampaign(endDate: _civil('2026-12-31'))),
        ),
        PeriodMismatch.endsAfter,
      );
    });
  });

  group('regla de contención (pura)', () {
    final central = _centralPeriod('2026-09-01', '2027-02-28');

    test('contención exacta y estricta', () {
      expect(periodMismatch(_local('2026-09-01', '2027-02-28'), central), null);
      expect(periodMismatch(_local('2026-10-01', '2027-01-31'), central), null);
    });

    test('fronteras inclusivas por los dos lados', () {
      expect(periodMismatch(_local('2026-09-01', '2027-01-31'), central), null);
      expect(periodMismatch(_local('2026-10-01', '2027-02-28'), central), null);
      expect(
        periodMismatch(_local('2026-08-31', '2027-01-31'), central),
        PeriodMismatch.startsBefore,
      );
      expect(
        periodMismatch(_local('2026-10-01', '2027-03-01'), central),
        PeriodMismatch.endsAfter,
      );
    });

    test('salida antes o después, y fin abierto frente a central finito', () {
      expect(
        periodMismatch(_local('2026-01-01', '2026-06-30'), central),
        PeriodMismatch.startsBefore,
      );
      expect(
        periodMismatch(_local('2027-03-01', '2027-06-30'), central),
        PeriodMismatch.endsAfter,
      );
      expect(
        periodMismatch(_local('2026-10-01'), central),
        PeriodMismatch.openEndRequired,
      );
    });

    test('ambas abiertas: cabe si la local no empieza antes', () {
      final open = _centralPeriod('2026-09-01');
      expect(periodMismatch(_local('2026-09-01'), open), null);
      expect(periodMismatch(_local('2026-10-01'), open), null);
      expect(periodMismatch(_local('2026-10-01', '2030-01-01'), open), null);
      expect(
        periodMismatch(_local('2026-08-31'), open),
        PeriodMismatch.startsBefore,
      );
    });

    test('el mensaje muestra los dos períodos', () {
      final message = periodMismatchMessage(
        localName: 'Local',
        local: _local('2026-10-01'),
        centralName: 'Central',
        central: central,
        mismatch: PeriodMismatch.openEndRequired,
      );
      expect(message, contains('«Local» va desde el 01/10/2026'));
      expect(
        message,
        contains('«Central» del sindicato va del 01/09/2026 al 28/02/2027'),
      );
      expect(message, contains('fije un fin previsto hasta el 28/02/2027'));
      expect(message, contains('no hace falta cerrarla'));
    });
  });

  group('vincular', () {
    test('rechazo por fin abierto frente a central finito: mensaje con ambos períodos y ninguna escritura', () async {
      final fixture = await seedSyncFixture(bindCatalog: false);
      final before = await dumpTables(await fixture.database.database);
      await expectLater(
        fixture.bindings.bindCampaign(
          campaignId: fixture.campaignId,
          central: centralCampaign(endDate: _civil('2026-12-31')),
          tenantId: memberA.tenantId,
        ),
        throwsA(
          isA<CentralBindingException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('«Campaña local 2026» va desde el 01/09/2026'),
              contains(
                '«Campaña sindicato 2026» del sindicato va del 01/09/2026 al 31/12/2026',
              ),
              contains('fije un fin previsto'),
              contains('No se vinculó'),
            ),
          ),
        ),
      );
      expect(await dumpTables(await fixture.database.database), before);
    });

    test('rechazo por empezar antes y por terminar después', () async {
      final fixture = await seedSyncFixture(bindCatalog: false);
      await expectLater(
        fixture.bindings.bindCampaign(
          campaignId: fixture.campaignId,
          central: centralCampaign(startDate: _civil('2026-09-02')),
          tenantId: memberA.tenantId,
        ),
        throwsA(
          isA<CentralBindingException>().having(
            (e) => e.message,
            'message',
            contains('empieza antes que la del sindicato'),
          ),
        ),
      );
      await fixture.repo.setCampaignEnd(
        fixture.campaignId,
        end: DateTime(2027, 3, 1),
      );
      await expectLater(
        fixture.bindings.bindCampaign(
          campaignId: fixture.campaignId,
          central: centralCampaign(endDate: _civil('2027-02-28')),
          tenantId: memberA.tenantId,
        ),
        throwsA(
          isA<CentralBindingException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('termina después que la del sindicato'),
              contains('del 01/09/2026 al 01/03/2027'),
              contains('del 01/09/2026 al 28/02/2027'),
            ),
          ),
        ),
      );
      expect(await fixture.bindings.campaignBindings(), isEmpty);
    });

    test('contención exacta, estricta y fronteras: se vincula y guarda el período central', () async {
      final fixture = await seedSyncFixture(bindCatalog: false);
      await fixture.repo.setCampaignEnd(
        fixture.campaignId,
        end: DateTime(2026, 12, 31),
      );
      // Exacta.
      var binding = await fixture.bindings.bindCampaign(
        campaignId: fixture.campaignId,
        central: centralCampaign(endDate: _civil('2026-12-31')),
        tenantId: memberA.tenantId,
      );
      expect(binding.isValid, isTrue);
      expect(binding.centralStartDay, '2026-09-01');
      expect(binding.centralEndDay, '2026-12-31');
      // Estricta (corrige el vínculo a una central más amplia).
      binding = await fixture.bindings.bindCampaign(
        campaignId: fixture.campaignId,
        central: centralCampaign(
          startDate: _civil('2026-08-01'),
          endDate: _civil('2027-01-31'),
        ),
        tenantId: memberA.tenantId,
      );
      expect(binding.isValid, isTrue);
      expect(binding.centralStartDay, '2026-08-01');
      expect(binding.centralEndDay, '2027-01-31');
      // Ambas abiertas.
      binding = await fixture.bindings.bindCampaign(
        campaignId: fixture.campaignId,
        central: centralCampaign(),
        tenantId: memberA.tenantId,
      );
      expect(binding.isValid, isTrue);
      expect(binding.centralEndDay, isNull);
    });

    test('fechas centrales ilegibles: no se vincula', () async {
      final fixture = await seedSyncFixture(bindCatalog: false);
      await expectLater(
        fixture.bindings.bindCampaign(
          campaignId: fixture.campaignId,
          central: centralCampaign(startDate: 'cuando sea'),
          tenantId: memberA.tenantId,
        ),
        throwsA(isA<CentralBindingException>()),
      );
      expect(await fixture.bindings.campaignBindings(), isEmpty);
    });
  });

  group('fin previsto (sin cerrar)', () {
    test('fija el fin de una campaña activa sin cambiar su estado y permite vincular', () async {
      final fixture = await seedSyncFixture(bindCatalog: false);
      await fixture.repo.setCampaignEnd(
        fixture.campaignId,
        end: DateTime(2026, 12, 31),
      );
      final row = await _campaignRow(fixture);
      expect(row['status'], 'ACTIVE');
      expect(storedLocalDay(row['end_date']! as String), '2026-12-31');
      final binding = await fixture.bindings.bindCampaign(
        campaignId: fixture.campaignId,
        central: centralCampaign(endDate: _civil('2026-12-31')),
        tenantId: memberA.tenantId,
      );
      expect(binding.isValid, isTrue);
      // Operaciones siguen entrando dentro del período fijado.
      await fixture.bindings.bindProduct(
        productId: fixture.litreProductId,
        central: centralProduct(),
        tenantId: memberA.tenantId,
      );
      await fixture.needs.declare(
        referenceDate: DateTime(2026, 12, 31, 23, 30),
        productId: fixture.litreProductId,
        quantityBase: 1000,
      );
    });

    test(
      'rechazos: antes del inicio, deja registros fuera, solapa, cerrada',
      () async {
        final fixture = await seedSyncFixture();
        await fixture.needs.declare(
          referenceDate: DateTime(2026, 11, 20),
          productId: fixture.litreProductId,
          quantityBase: 1000,
        );
        final before = await dumpTables(await fixture.database.database);
        await expectLater(
          fixture.repo.setCampaignEnd(
            fixture.campaignId,
            end: DateTime(2026, 8, 31),
          ),
          throwsA(
            isA<CampaignCalendarException>().having(
              (e) => e.message,
              'message',
              contains('anterior al inicio'),
            ),
          ),
        );
        await expectLater(
          fixture.repo.setCampaignEnd(
            fixture.campaignId,
            end: DateTime(2026, 11, 19),
          ),
          throwsA(
            isA<CampaignCalendarException>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('registros del 20/11/2026'),
                contains('no se cambian de campaña'),
              ),
            ),
          ),
        );
        expect(await dumpTables(await fixture.database.database), before);

        // Una campaña siguiente desde el 01/01/2027 fija el fin de la actual
        // en el 31/12/2026; alargarlo la solaparía.
        await fixture.repo.addCampaign(
          name: 'Siguiente',
          start: DateTime(2027, 1, 1),
        );
        await expectLater(
          fixture.repo.setCampaignEnd(
            fixture.campaignId,
            end: DateTime(2027, 1, 1),
          ),
          throwsA(
            isA<CampaignCalendarException>().having(
              (e) => e.message,
              'message',
              contains('se solapa'),
            ),
          ),
        );
        // Acortarlo sí, mientras no deje fuera el registro del 20/11.
        await fixture.repo.setCampaignEnd(
          fixture.campaignId,
          end: DateTime(2026, 12, 15),
        );
        expect(
          storedLocalDay((await _campaignRow(fixture))['end_date']! as String),
          '2026-12-15',
        );
        // Cerrada: su período no se cambia.
        await fixture.repo.closeCampaign(fixture.campaignId);
        await expectLater(
          fixture.repo.setCampaignEnd(
            fixture.campaignId,
            end: DateTime(2026, 12, 31),
          ),
          throwsA(
            isA<CampaignCalendarException>().having(
              (e) => e.message,
              'message',
              contains('está cerrada'),
            ),
          ),
        );
      },
    );
  });

  group('referencia central actualizada', () {
    test('la central gana fin: el vínculo queda PERIOD_INCOMPATIBLE con el período guardado; vuelve a VALID si cabe', () async {
      final fixture = await seedSyncFixture();
      await fixture.needs.declare(
        referenceDate: inCampaign,
        productId: fixture.litreProductId,
        quantityBase: 5000,
      );
      // El refresco también sella `checked_at` en los vínculos de producto.
      final before = await dumpTables(
        await fixture.database.database,
        except: {'campaign_bindings', 'product_bindings'},
      );
      final changed = await fixture.bindings.refreshFrom(
        _references(end: '2026-10-31'),
        memberA.tenantId,
      );
      expect(changed, 1);
      var binding = await _binding(fixture);
      expect(binding.isValid, isFalse);
      expect(binding.invalidReason, BindingInvalidReason.periodIncompatible);
      expect(binding.centralStartDay, '2026-09-01');
      expect(binding.centralEndDay, '2026-10-31');
      // Ninguna operación, necesidad ni intención cambió.
      expect(
        await dumpTables(
          await fixture.database.database,
          except: {'campaign_bindings', 'product_bindings'},
        ),
        before,
      );
      // Un valor nuevo se rechaza con los dos períodos; retirar sigue
      // permitido (CANCEL, F06 §6).
      final need = (await fixture.needs.needs()).single;
      await expectLater(
        fixture.needs.updateQuantity(need.id, 6000),
        throwsA(
          isA<BindingRequiredException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('«Campaña local 2026» va desde el 01/09/2026'),
              contains('del 01/09/2026 al 31/10/2026'),
            ),
          ),
        ),
      );
      expect(
        (await fixture.needs.campaignFor(inCampaign)).message,
        contains('del 01/09/2026 al 31/10/2026'),
      );
      await fixture.needs.withdraw(need.id);

      // Central amplía otra vez: vuelve a caber.
      await fixture.bindings.refreshFrom(_references(), memberA.tenantId);
      binding = await _binding(fixture);
      expect(binding.isValid, isTrue);
      expect(binding.centralEndDay, isNull);
    });

    test(
      'la central mueve su inicio después del local: incompatible',
      () async {
        final fixture = await seedSyncFixture();
        await fixture.bindings.refreshFrom(
          _references(start: '2026-10-01'),
          memberA.tenantId,
        );
        final binding = await _binding(fixture);
        expect(binding.invalidReason, BindingInvalidReason.periodIncompatible);
        expect(
          CentralBindingStore.periodProblem(
            binding,
            CampaignPeriod.fromRow(await _campaignRow(fixture)),
          ),
          allOf(
            contains('empieza antes que la del sindicato'),
            contains('desde el 01/10/2026'),
          ),
        );
      },
    );

    test('un motivo ajeno al período prevalece y no se pierde', () async {
      final fixture = await seedSyncFixture();
      await fixture.bindings.refreshFrom(
        _references(end: '2026-10-31', accepts: false),
        memberA.tenantId,
      );
      final binding = await _binding(fixture);
      expect(binding.invalidReason, BindingInvalidReason.notAccepting);
      expect(binding.centralEndDay, '2026-10-31');
    });
  });

  group('edición posterior del calendario local', () {
    test('alargar el fin más allá del central invalida; acortarlo revalida (sin red)', () async {
      final fixture = await seedSyncFixture(bindCatalog: false);
      await fixture.repo.setCampaignEnd(
        fixture.campaignId,
        end: DateTime(2027, 2, 28),
      );
      await fixture.bindings.bindCampaign(
        campaignId: fixture.campaignId,
        central: centralCampaign(endDate: _civil('2027-02-28')),
        tenantId: memberA.tenantId,
      );
      await fixture.repo.setCampaignEnd(
        fixture.campaignId,
        end: DateTime(2027, 3, 15),
      );
      var binding = await _binding(fixture);
      expect(binding.invalidReason, BindingInvalidReason.periodIncompatible);
      // Asentado en la fila, no sólo calculado al leer.
      final stored = (await (await fixture.database.database).query(
        'campaign_bindings',
      )).single;
      expect(stored['status'], 'INVALID');
      expect(stored['invalid_reason'], 'PERIOD_INCOMPATIBLE');

      await fixture.repo.setCampaignEnd(
        fixture.campaignId,
        end: DateTime(2027, 2, 28),
      );
      binding = await _binding(fixture);
      expect(binding.isValid, isTrue);
    });

    test(
      'el alta de la campaña siguiente fija el fin de la actual y la revalida',
      () async {
        final fixture = await seedSyncFixture();
        await fixture.bindings.refreshFrom(
          _references(end: '2027-02-28'),
          memberA.tenantId,
        );
        expect(
          (await _binding(fixture)).invalidReason,
          BindingInvalidReason.periodIncompatible,
        );
        // Alta en orden: la actual termina el 28/02/2027, que sí cabe.
        await fixture.repo.addCampaign(
          name: 'Siguiente',
          start: DateTime(2027, 3, 1),
        );
        expect((await _binding(fixture)).isValid, isTrue);
        expect(
          storedLocalDay((await _campaignRow(fixture))['end_date']! as String),
          '2027-02-28',
        );
      },
    );

    test('cerrar la campaña fija su fin y revalida el vínculo', () async {
      final fixture = await seedSyncFixture();
      await fixture.needs.declare(
        referenceDate: inCampaign,
        productId: fixture.litreProductId,
        quantityBase: 1000,
      );
      await fixture.bindings.refreshFrom(
        _references(end: '2026-10-31'),
        memberA.tenantId,
      );
      expect((await _binding(fixture)).isValid, isFalse);
      await fixture.repo.closeCampaign(
        fixture.campaignId,
        end: DateTime(2026, 10, 16),
      );
      expect((await _binding(fixture)).isValid, isTrue);
    });
  });

  group('persistencia y reapertura', () {
    test('el período central se conserva y la comprobación funciona sin red tras reabrir', () async {
      final path = await tempDbPath('c2_reopen');
      final fixture = await seedSyncFixture(path: path, bindCatalog: false);
      await fixture.repo.setCampaignEnd(
        fixture.campaignId,
        end: DateTime(2026, 12, 31),
      );
      await fixture.bindings.bindCampaign(
        campaignId: fixture.campaignId,
        central: centralCampaign(endDate: _civil('2026-12-31')),
        tenantId: memberA.tenantId,
      );
      await fixture.database.close();

      final reopened = reopenFixture(fixture, openDb(path));
      var binding = await _binding(reopened);
      expect(binding.isValid, isTrue);
      expect(binding.centralStartDay, '2026-09-01');
      expect(binding.centralEndDay, '2026-12-31');
      // Sin referencias nuevas: el cambio local se juzga con lo guardado.
      await reopened.repo.setCampaignEnd(
        reopened.campaignId,
        end: DateTime(2027, 1, 1),
      );
      binding = await _binding(reopened);
      expect(binding.invalidReason, BindingInvalidReason.periodIncompatible);
    });
  });

  group('publicación de consumo', () {
    test('vista previa vieja: si el vínculo se volvió incompatible, publicar no escribe nada', () async {
      final fixture = await seedConsumptionFixture();
      await fixture.apply(fixture.ownerPersonId, {
        fixture.sync.litreProductId: 3000,
      });
      final stale = await fixture.publisher.preview();
      expect(stale.hasChanges, isTrue);
      await fixture.sync.bindings.refreshFrom(
        _references(end: '2026-10-31'),
        memberA.tenantId,
      );
      final before = await dumpTables(await fixture.sync.database.database);
      await expectLater(
        fixture.publisher.publish(stale),
        throwsA(isA<ConsumptionPublishException>()),
      );
      expect(
        await dumpTables(await fixture.sync.database.database),
        before,
        reason: 'una vista previa vieja no escribe nada',
      );
      expect(await fixture.sync.outboxRows(), isEmpty);

      // La vista previa nueva muestra el total real bloqueado, con los dos
      // períodos, y no ofrece publicarlo.
      final fresh = await fixture.publisher.preview();
      expect(fresh.hasChanges, isFalse);
      final row = fresh.rows.single;
      expect(row.change, ConsumptionChange.blocked);
      expect(row.quantityBase, 3000);
      expect(row.blockedDetail, contains('del 01/09/2026 al 31/10/2026'));
      expect(row.canWithdraw, isFalse);
      expect(
        fresh.excludedPairs.single.reason,
        ConsumptionExclusion.campaignBindingInvalid,
      );
      expect(fresh.excludedPairs.single.detail, isNotNull);
    });

    test('total ya aceptado (ACKED) bajo un vínculo incompatible: se señala, no se sustituye por cero ni se reasigna; el titular puede retirarlo', () async {
      final fixture = await seedConsumptionFixture();
      await fixture.apply(fixture.ownerPersonId, {
        fixture.sync.litreProductId: 3000,
      });
      await fixture.publisher.publish(await fixture.publisher.preview());
      final transport = _Transport([_ack]);
      await _worker(fixture.sync, transport).run();
      final acked = (await fixture.sync.outboxEntries()).single;
      expect(acked.status, OutboxStatus.acked);
      final ackedRow = (await fixture.sync.outboxRows()).single;

      await fixture.sync.bindings.refreshFrom(
        _references(end: '2026-10-31'),
        memberA.tenantId,
      );
      final preview = await fixture.publisher.preview();
      final row = preview.rows.single;
      expect(row.change, ConsumptionChange.blocked);
      expect(row.quantityBase, 3000);
      expect(row.prior!.operationId, acked.operationId);
      expect(row.canWithdraw, isTrue);
      expect(preview.hasChanges, isFalse);
      final reviews = await fixture.sync.bindings.campaignReviews();
      expect(reviews.single.acceptedContributions, 1);
      expect(reviews.single.heldIntentions, 0);
      // Nada se escribió al mirar.
      expect(await fixture.sync.outboxRows(), [ackedRow]);

      await fixture.publisher.withdraw(row);
      final rows = await fixture.sync.outboxRows();
      expect(rows, hasLength(2));
      expect(rows.first, ackedRow, reason: 'la aceptada no se modifica');
      final cancel = OutboxEntry.fromRow(rows.last);
      expect(cancel.action, SyncAction.cancel);
      expect(cancel.quantityBase, isNull);
      expect(cancel.predecessorOperationId, acked.operationId);
      expect(cancel.campaignRef, acked.campaignRef);
      // La retirada sí sale, aunque el vínculo esté bloqueado.
      final sending = _Transport([_ack]);
      final report = await _worker(fixture.sync, sending).run();
      expect(report.accepted, 1);
      expect(sending.bodies.single['action'], 'CANCEL');
      // Retirar dos veces no procede: el estado cambió.
      await expectLater(
        fixture.publisher.withdraw(row),
        throwsA(isA<ConsumptionPublishException>()),
      );
    });
  });

  group('cola', () {
    test('una intención que nunca salió se retiene mientras el vínculo sea incompatible; al caber, se envía igual', () async {
      final fixture = await seedSyncFixture();
      await fixture.needs.declare(
        referenceDate: inCampaign,
        productId: fixture.litreProductId,
        quantityBase: 2000,
      );
      final pendingRow = (await fixture.outboxRows()).single;
      await fixture.bindings.refreshFrom(
        _references(end: '2026-10-31'),
        memberA.tenantId,
      );
      final transport = _Transport(const []);
      final report = await _worker(fixture, transport).run();
      expect(report.sent, 0);
      expect(report.blocker, isNull);
      expect(transport.requests, isEmpty);
      expect(await fixture.outboxRows(), [pendingRow], reason: 'sin cambios');
      final summary = await fixture.outbox.summary();
      expect(summary.heldForPeriod, 1);
      expect(summary.count(OutboxStatus.pending), 1);
      expect(
        (await fixture.outbox.heldForPeriod()).single.operationId,
        pendingRow['operation_id'],
      );
      expect(
        (await fixture.bindings.campaignReviews()).single.heldIntentions,
        1,
      );

      // El titular fija el fin previsto dentro del período central.
      await fixture.repo.setCampaignEnd(
        fixture.campaignId,
        end: DateTime(2026, 10, 31),
      );
      expect((await fixture.outbox.summary()).heldForPeriod, 0);
      final sending = _Transport([_ack]);
      expect((await _worker(fixture, sending).run()).accepted, 1);
      final sent = sending.bodies.single;
      expect(sent['operationId'], pendingRow['operation_id']);
      expect((sent['payload'] as Map)['quantity_base'], '2000');
    });

    test('una intención que ya salió (resultado desconocido) se reenvía igual: es la misma, no un aporte nuevo', () async {
      final fixture = await seedSyncFixture();
      await fixture.needs.declare(
        referenceDate: inCampaign,
        productId: fixture.litreProductId,
        quantityBase: 2000,
      );
      // Primer intento sin respuesta fiable.
      final first = _Transport([(_) => http.Response('', 500)]);
      await _worker(fixture, first).run();
      final entry = (await fixture.outboxEntries()).single;
      expect(entry.attempts, 1);
      expect(entry.isUnsent, isFalse);

      await fixture.bindings.refreshFrom(
        _references(end: '2026-10-31'),
        memberA.tenantId,
      );
      expect((await fixture.outbox.summary()).heldForPeriod, 0);
      final later = DateTime.utc(2026, 10, 15, 13);
      final access = SyncAccessHolder(clock: () => later)
        ..accept('token-sintetico', memberA.memberId, memberA.tenantId);
      final retry = _Transport([_ack]);
      final worker = SyncWorker(
        outbox: fixture.outbox,
        owners: fixture.owners,
        api: () => SyncApi(
          AuthHttpClient(
            config: ApiEndpointConfig(Uri.parse('https://sindicato.example')),
            client: retry.client,
          ),
          clock: () => later,
        ),
        access: access,
        random: Random(7),
        clock: () => later,
      );
      expect((await worker.run()).accepted, 1);
      expect(retry.bodies.single['operationId'], entry.operationId);
    });
  });

  group('migración v9 → v10', () {
    Future<(String, Map<String, List<Map<String, Object?>>>)> seedV9(
      String name,
    ) async {
      final path = await tempDbPath(name);
      final fixture = await seedSyncFixture(path: path);
      await fixture.needs.declare(
        referenceDate: inCampaign,
        productId: fixture.litreProductId,
        quantityBase: 1000,
      );
      final other = await fixture.repo.addCampaign(
        name: 'Otra local',
        start: DateTime(2026, 12, 1),
      );
      await fixture.bindings.bindCampaign(
        campaignId: other,
        central: centralCampaign(ref: otherCampaignRef, name: 'Otra central'),
        tenantId: memberA.tenantId,
      );
      // La segunda referencia desaparece: INVALID por un motivo ajeno.
      await fixture.bindings.refreshFrom(referencesWith(), memberA.tenantId);
      await fixture.database.close();
      await _downgradeCampaignBindingsToV9(path);
      final v9 = await databaseFactoryFfi.openDatabase(path);
      expect(
        (await v9.rawQuery('PRAGMA user_version')).single.values.single,
        9,
      );
      final dump = await dumpTables(v9);
      expect(dump['campaign_bindings']!.first['status'], 'VALID');
      expect(
        dump['campaign_bindings']!.last['invalid_reason'],
        'REFERENCE_MISSING',
      );
      await v9.close();
      return (path, dump);
    }

    test('actualización: filas conservadas, el vínculo vigente pasa a «período sin comprobar», mismo esquema que una base nueva', () async {
      final (path, v9) = await seedV9('c2_v9');
      final upgraded = openDb(path);
      final db = await upgraded.database;
      expect(
        (await db.rawQuery('PRAGMA user_version')).single.values.single,
        AppDatabase.schemaVersion,
      );
      expect(
        (await db.rawQuery('PRAGMA integrity_check')).single.values.single,
        'ok',
      );
      final migrated = await dumpTables(db);
      for (final table in v9.keys.toSet().difference({
        'campaign_bindings',
        'app_settings',
      })) {
        expect(migrated[table], v9[table], reason: table);
      }
      final bindings = migrated['campaign_bindings']!;
      expect(bindings, hasLength(2));
      for (var i = 0; i < 2; i++) {
        for (final column in [
          'campaign_id',
          'tenant_id',
          'campaign_ref',
          'central_name',
          'bound_at',
          'checked_at',
        ]) {
          expect(bindings[i][column], v9['campaign_bindings']![i][column]);
        }
        expect(bindings[i]['central_start_day'], isNull);
        expect(bindings[i]['central_end_day'], isNull);
        expect(bindings[i]['status'], 'INVALID');
      }
      expect(bindings.first['invalid_reason'], 'PERIOD_UNVERIFIED');
      expect(bindings.last['invalid_reason'], 'REFERENCE_MISSING');
      expect((await settings(db))[AppDatabase.campaignPeriodReviewKey], '1');
      // Mismo esquema que una instalación nueva.
      final fresh = AppDatabase(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      addTearDown(fresh.close);
      final problems = (await SchemaSignature.read(await fresh.database))
          .diff(await SchemaSignature.read(db));
      expect(problems, isEmpty, reason: problems.join('\n'));

      // Hasta actualizar las referencias, la intención pendiente se retiene
      // y un valor nuevo se rechaza; al refrescar, el vínculo vuelve a VALID
      // con su período central.
      final store = CentralBindingStore(upgraded);
      final outbox = SyncOutboxStore(upgraded);
      expect((await outbox.summary()).heldForPeriod, 1);
      final needs = DeclaredNeedStore(upgraded);
      await expectLater(
        needs.updateQuantity((await needs.needs()).single.id, 2000),
        throwsA(
          isA<BindingRequiredException>().having(
            (e) => e.message,
            'message',
            contains('no se ha comprobado'),
          ),
        ),
      );
      await store.refreshFrom(
        CentralReferences([
          centralCampaign(),
          centralCampaign(ref: otherCampaignRef, name: 'Otra central'),
        ], referencesWith().products),
        memberA.tenantId,
      );
      final after = await store.campaignBindings();
      expect(after.map((b) => b.isValid), [true, true]);
      expect(after.first.centralStartDay, '2026-09-01');
      expect((await outbox.summary()).heldForPeriod, 0);
    });

    test('recuperación: restaurar una copia v9 la migra igual', () async {
      final (path, v9) = await seedV9('c2_v9_copia');
      final target = openDb(await tempDbPath('c2_destino'));
      await AgroRepository(target).addProduct(name: 'Se reemplaza');
      final validation = await BackupService(target).validate(path);
      expect(validation.isValid, isTrue, reason: validation.problem);
      expect(validation.schemaVersion, 9);
      await BackupService(target).restore(path);
      final db = await target.database;
      expect(
        (await db.rawQuery('PRAGMA user_version')).single.values.single,
        AppDatabase.schemaVersion,
      );
      final restored = await dumpTables(db);
      for (final table in v9.keys.toSet().difference({
        'campaign_bindings',
        'app_settings',
        'sync_outbox',
      })) {
        expect(restored[table], v9[table], reason: table);
      }
      // La outbox conserva sus intenciones (pausadas por la restauración).
      expect(
        restored['sync_outbox']!.map((r) => r['operation_id']),
        v9['sync_outbox']!.map((r) => r['operation_id']),
      );
      expect(
        restored['campaign_bindings']!.first['invalid_reason'],
        'PERIOD_UNVERIFIED',
      );
      expect((await settings(db))[AppDatabase.campaignPeriodReviewKey], '1');
    });
  });
}
