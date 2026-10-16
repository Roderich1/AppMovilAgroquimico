// ignore_for_file: avoid_print
// F06 (D4, BE #21 / GATE-F06): reconciliación del dataset controlado contra un
// Backend local desechable. Se salta sin AGRO_E2E_BASE_URL.
//
// Niveles comparados con el oráculo escrito a mano (docs/evidence/F06_*.csv):
// SQLite (vista previa y necesidades) → outbox (última intención por clave) →
// Central (estado y cabeza de cada aportación propia) → agregado por celda
// (`/collective/.../summary` y su CSV, con un usuario Directiva).
//
// Primera ejecución (AGRO_E2E_WORKDIR vacío): siembra las tres bases, publica
// con el worker de D3 y pierde a propósito la primera respuesta de cada push
// (el servidor ya aplicó la operación): el worker reenvía la misma operación.
// Consulta el agregado sin asociar, confirma Bellator → Belator y lo consulta
// de nuevo. Segunda ejecución (bases ya presentes): reenvía todas las
// operaciones aceptadas tal cual y comprueba que el agregado no cambia.
//
// Variables (las credenciales sólo se leen del entorno; nunca se imprimen):
//   AGRO_E2E_BASE_URL   http://127.0.0.1:<puerto> del Backend desechable
//   AGRO_E2E_WORKDIR    carpeta fuera del repositorio para bases y resultados
//   AGRO_E2E_F{1,2,3}_EMAIL / _PASSWORD, AGRO_E2E_DIRECTIVA_EMAIL / _PASSWORD
//
// El origen https del cliente se reescribe al Backend local en el transporte
// de prueba: TLS no se ejercita aquí (lo cubre la ruta física por el túnel).
import 'dart:convert';
import 'dart:io';

import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/installation_access.dart';
import 'package:agroquimicos/domain/sync/sync_types.dart';
import 'package:agroquimicos/domain/sync/sync_wire.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/data/sync/declared_need_store.dart';
import 'package:agroquimicos/services/auth/api_endpoint_config.dart';
import 'package:agroquimicos/services/auth/auth_api_exception.dart';
import 'package:agroquimicos/services/auth/auth_http_client.dart';
import 'package:agroquimicos/services/auth/auth_v2_api.dart';
import 'package:agroquimicos/services/auth/auth_v2_models.dart';
import 'package:agroquimicos/services/sync/sync_access.dart';
import 'package:agroquimicos/services/sync/sync_api.dart';
import 'package:agroquimicos/services/sync/sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f06_dataset.dart';

final _env = Platform.environment;
final _base = _env['AGRO_E2E_BASE_URL'];

/// Reescribe el origen al Backend local y, si se pide, pierde la primera
/// respuesta de cada push **después** de que el servidor la procesó.
class _LocalTransport extends http.BaseClient {
  _LocalTransport(this.target);

  final Uri target;
  final http.Client _inner = http.Client();
  bool dropFirstPushResponse = false;
  final Set<String> _dropped = {};
  int requests = 0;
  int droppedResponses = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final original = request as http.Request;
    final url = original.url.replace(
      scheme: target.scheme,
      host: target.host,
      port: target.port,
    );
    final copy = http.Request(original.method, url)
      ..headers.addAll(original.headers)
      ..bodyBytes = original.bodyBytes;
    requests++;
    final response = await _inner.send(copy);
    if (dropFirstPushResponse && url.path == '/api/v1/sync/v1/push') {
      final operationId =
          (jsonDecode(original.body) as Map<String, dynamic>)['operationId']
              as String;
      if (_dropped.add(operationId)) {
        await response.stream.drain<void>();
        droppedResponses++;
        throw http.ClientException(
          'respuesta perdida (inyectada en la prueba)',
        );
      }
    }
    return response;
  }
}

/// Como mucho 15 peticiones por minuto (el Backend limita 20/min por IP).
class _Pace {
  final List<DateTime> _recent = [];

  Future<void> slot() async {
    while (true) {
      final now = DateTime.now();
      _recent.removeWhere(
        (t) => now.difference(t) > const Duration(seconds: 61),
      );
      if (_recent.length < 15) {
        _recent.add(now);
        return;
      }
      await Future<void>.delayed(
        _recent.first.add(const Duration(seconds: 62)).difference(now),
      );
    }
  }
}

String _short(String value) => value.substring(0, 8);

void main() {
  sqfliteFfiInit();

  test(
    'F06: SQLite → outbox → Central → agregado por celda; diferencia = 0',
    () async {
      final workdir = Directory(_env['AGRO_E2E_WORKDIR']!)
        ..createSync(recursive: true);
      final target = Uri.parse(_base!);
      expect(
        target.scheme == 'http' &&
            {'127.0.0.1', 'localhost'}.contains(target.host),
        isTrue,
        reason: 'sólo un Backend local desechable',
      );
      final transport = _LocalTransport(target);
      final pace = _Pace();
      final client = AuthHttpClient(
        config: ApiEndpointConfig(Uri.parse('https://f06-e2e.invalid')),
        client: transport,
      );
      final auth = AuthV2Api(client);
      final api = SyncApi(client);
      final firstExecution = !File(p.join(workdir.path, 'F1.db')).existsSync();
      final report = <String, Object?>{
        'execution': firstExecution ? 1 : 2,
        'startedAt': DateTime.now().toUtc().toIso8601String(),
      };
      print('E2E F06: ejecución ${firstExecution ? 1 : 2}');

      Future<V2AuthResponse> login(String who) async {
        await pace.slot();
        return auth.login(
          LoginV2Request(
            email: _env['AGRO_E2E_${who}_EMAIL']!,
            password: _env['AGRO_E2E_${who}_PASSWORD']!,
          ),
        );
      }

      final perFarmer = <String, Object?>{};
      final centralCampaigns = <String, String>{};
      final centralProducts = <String, String>{};
      for (final farmer in ['F1', 'F2', 'F3']) {
        final session = await login(farmer);
        // Como la app: la sesión se enlaza a la identidad de esta instalación.
        await pace.slot();
        final registration = await auth.registerClient(
          accessToken: session.accessToken,
          clientId: f06InstallationClientId(farmer),
        );
        await pace.slot();
        await auth.bindSessionClient(
          accessToken: session.accessToken,
          registrationId: registration.registrationId,
        );
        final scope = OwnerScope(
          memberId: session.context.member.id,
          tenantId: session.context.tenant.id,
        );
        final access = SyncAccessHolder()
          ..accept(session.accessToken, scope.memberId, scope.tenantId);
        await pace.slot();
        final references = await api.references(session.accessToken);
        for (final c in references.campaigns) {
          centralCampaigns[c.name] = c.ref;
        }
        for (final product in references.products) {
          centralProducts[product.name] = product.ref;
        }
        final campaignCode = {
          for (final MapEntry(:key, :value) in f06CentralCampaigns.entries)
            centralCampaigns[value]!: key,
        };
        final productName = {
          for (final e in centralProducts.entries) e.value: e.key,
        };
        final database = AppDatabase(
          factory: databaseFactoryFfi,
          path: p.join(workdir.path, '$farmer.db'),
        );
        addTearDown(database.close);
        final farm = firstExecution
            ? await seedF06Farm(
                database: database,
                farmer: farmer,
                scope: scope,
                installationRef: f06InstallationRef(farmer),
                references: references,
              )
            : await reopenF06Farm(database: database, farmer: farmer);
        var offset = Duration.zero;
        final worker = SyncWorker(
          outbox: farm.outbox,
          owners: OwnerBindingStore(database),
          api: () => api,
          access: access,
          budget: 1,
          clock: () => DateTime.now().add(offset),
        );

        Future<int> drain() async {
          var cycles = 0;
          while (true) {
            final summary = await farm.outbox.summary();
            final open = [
              OutboxStatus.pending,
              OutboxStatus.outcomeUnknown,
              OutboxStatus.sending,
            ].fold(0, (s, status) => s + summary.count(status));
            if (open == 0) return cycles;
            expect(cycles, lessThan(200), reason: 'la outbox no se vacía');
            await pace.slot();
            final dropped = transport.droppedResponses;
            final run = await worker.run();
            // Tras una respuesta perdida el worker se detiene sin red; ningún
            // otro bloqueo es aceptable.
            expect(
              run.blocker,
              transport.droppedResponses > dropped
                  ? SyncBlocker.unreachable
                  : isNull,
              reason: '$farmer: ${run.blocker}',
            );
            expect(run.conflicts + run.rejected, 0);
            offset += const Duration(hours: 1); // el reintento ya está maduro
            cycles++;
          }
        }

        final expected = f06ExpectedContributions(farmer);
        final farmerReport = <String, Object?>{
          'member': _short(scope.memberId),
        };
        if (firstExecution) {
          transport.dropFirstPushResponse = true;
          final published = await farm.publisher.publish(
            await farm.publisher.preview(),
          );
          final before = transport.requests;
          final cycles1 = await drain();
          final cancels = await applyF06Cancellations(farm);
          final cycles2 = await drain();
          transport.dropFirstPushResponse = false;
          farmerReport.addAll({
            'consumptionEnqueued': published,
            'cancellations': cancels,
            'workerCycles': cycles1 + cycles2,
            'pushRequests': transport.requests - before,
          });
        } else {
          // Nada cambió en SQLite: publicar de nuevo no encola nada.
          final preview = await farm.publisher.preview();
          expect(preview.hasChanges, isFalse);
          expect(await farm.publisher.publish(preview), 0);
        }

        // Nivel SQLite.
        final previewRows = (await farm.publisher.preview()).rows;
        final campaignOf = {
          for (final e in farm.campaignOf.entries) e.value: e.key,
        };
        final local = <F06Key, F06Expected>{
          for (final row in previewRows)
            (
              campaign: campaignCode[row.target.campaignRef]!,
              projection: ProjectionType.consumptionTotal.code,
              product: productName[row.target.productRef]!,
              baseUnit: row.baseUnit.code,
            ): (
              status: 'ACTIVE',
              quantity: row.quantityBase,
            ),
          for (final need in await farm.needs.needs())
            (
              campaign: campaignOf[need.campaignId]!,
              projection: ProjectionType.declaredNeed.code,
              product: need.productName,
              baseUnit: need.baseUnit.code,
            ): (
              status: need.status.code,
              quantity: need.status == DeclaredNeedStatus.active
                  ? need.quantityBase
                  : null,
            ),
        };
        expect(local, expected, reason: '$farmer: nivel SQLite');

        // Nivel outbox: última intención no descartada por clave, todas ACKED.
        final entries =
            (await (await database.database).query(
                  'sync_outbox',
                  orderBy: 'id',
                ))
                .map(OutboxEntry.fromRow)
                .where((e) => e.status != OutboxStatus.discarded);
        expect(entries.every((e) => e.status == OutboxStatus.acked), isTrue);
        final last = <F06Key, OutboxEntry>{};
        for (final entry in entries) {
          last[(
                campaign: campaignCode[entry.campaignRef]!,
                projection: entry.projectionType.code,
                product: productName[entry.productRef]!,
                baseUnit: entry.baseUnit.code,
              )] =
              entry;
        }
        expect(
          {
            for (final MapEntry(:key, :value) in last.entries)
              key: (
                status: value.action == SyncAction.cancel
                    ? 'CANCELLED'
                    : 'ACTIVE',
                quantity: value.quantityBase == null
                    ? null
                    : int.parse(value.quantityBase!),
              ),
          },
          expected,
          reason: '$farmer: nivel outbox',
        );

        // Segunda ejecución: reenvío literal de todas las operaciones aceptadas.
        if (!firstExecution) {
          var replays = 0;
          for (final entry in entries) {
            await pace.slot();
            final outcome = await api.push(entry, session.accessToken);
            expect(outcome, isA<PushAcknowledged>());
            final ack = (outcome as PushAcknowledged).ack;
            expect(
              {
                AckOutcome.applied,
                AckOutcome.alreadyApplied,
              }.contains(ack.outcome),
              isTrue,
            );
            expect(
              DateTime.parse(ack.serverAcceptedAt!),
              DateTime.parse(entry.serverAcceptedAt!),
              reason: 'la aceptación original no cambia',
            );
            replays++;
          }
          farmerReport['replayedOperations'] = replays;
        }

        // Nivel Central: estado y cabeza de cada aportación propia.
        var centralOk = 0;
        for (final MapEntry(:key, :value) in last.entries) {
          await pace.slot();
          final view = await api.operation(
            value.operationId,
            session.accessToken,
          );
          expect(
            view.contribution?.status,
            expected[key]!.status,
            reason: '$farmer $key',
          );
          expect(view.contribution?.headOperationId, value.operationId);
          centralOk++;
        }
        farmerReport.addAll({
          'contributions': expected.length,
          'centralHeadsMatched': centralOk,
          'operationsAcked': entries.length,
        });
        perFarmer[farmer] = farmerReport;
        print('  $farmer (member ${_short(scope.memberId)}): $farmerReport');
      }
      report['farmers'] = perFarmer;

      // Agregado por celda con un usuario Directiva. La app móvil no puede
      // pedir el consolidado: su cliente sólo admite las rutas de su lista.
      final directiva = await login('DIRECTIVA');
      await expectLater(
        client.request(
          'GET',
          '/api/v1/collective/campaigns/${centralCampaigns.values.first}/summary',
          accessToken: directiva.accessToken,
        ),
        throwsA(
          isA<AuthApiException>().having(
            (e) => e.kind,
            'kind',
            AuthApiErrorKind.configuration,
          ),
        ),
      );
      // La Directiva consulta como lo haría la Web: HTTP directo con su token.
      Future<http.Response> central(
        String method,
        String path, {
        Map<String, Object?>? json,
      }) async {
        await pace.slot();
        final request = http.Request(method, target.replace(path: path))
          ..headers['Authorization'] = 'Bearer ${directiva.accessToken}';
        if (json != null) {
          request.headers['Content-Type'] = 'application/json';
          request.body = jsonEncode(json);
        }
        return http.Response.fromStream(await transport.send(request));
      }

      final productName = {
        for (final e in centralProducts.entries) e.value: e.key,
      };

      Future<Map<F06Key, Map<String, Object?>>> summary() async {
        final cells = <F06Key, Map<String, Object?>>{};
        for (final MapEntry(key: code, value: name)
            in f06CentralCampaigns.entries) {
          final response = await central(
            'GET',
            '/api/v1/collective/campaigns/${centralCampaigns[name]}/summary',
          );
          expect(response.statusCode, 200);
          final body = jsonDecode(
            utf8.decode(response.bodyBytes),
          ) as Map<String, dynamic>;
          expect((body['disclosure']! as Map)['mode'], 'PROVISIONAL_SYNTHETIC');
          expect((body['disclosure']! as Map)['approved'], false);
          final coverage = body['coverage']! as Map;
          report['coverage_$code'] = coverage;
          expect(coverage['members_with_contribution'], 3);
          for (final cell
              in (body['cells']! as List).cast<Map<String, dynamic>>()) {
            cells[(
                  campaign: code,
                  projection: cell['projection_type'] as String,
                  product: productName[cell['product_ref']]!,
                  baseUnit: cell['base_unit'] as String,
                )] =
                cell;
          }
          // Mismo resultado por el canal CSV (misma política en todas las salidas).
          final csv = await central(
            'GET',
            '/api/v1/collective/campaigns/${centralCampaigns[name]}/summary.csv',
          );
          expect(csv.statusCode, 200);
          final lines = utf8.decode(csv.bodyBytes).trim().split('\n');
          final header = lines.indexWhere(
            (l) => l.startsWith('projection_type,'),
          );
          final csvCells = {
            for (final line in lines.skip(header + 1))
              () {
                final v = line.split(',');
                return '${v[0]}|${v[1]}|${v[3]}';
              }(): line.split(
                ',',
              ),
          };
          for (final cell
              in (body['cells']! as List).cast<Map<String, dynamic>>()) {
            final row =
                csvCells['${cell['projection_type']}|${cell['product_ref']}|${cell['base_unit']}']!;
            expect(row[5], cell['status']);
            expect(row[6], cell['total_base'] ?? '');
            expect(row[8], '${cell['contributors'] ?? ''}');
          }
          expect(csvCells.length, (body['cells']! as List).length);
        }
        return cells;
      }

      List<String> compare(
        String stage,
        Map<F06Key, Map<String, Object?>> got,
      ) {
        final expectedCells = f06ExpectedCells(stage);
        final lines = <String>[];
        for (final MapEntry(:key, value: want) in expectedCells.entries) {
          final cell = got[key];
          final status = cell?['status'] as String? ?? 'ABSENT';
          final total = cell?['total_base'] as String?;
          final contributors = cell?['contributors'] as int?;
          final diff = want.total == null || total == null
              ? (want.total == total ? '0' : 'n/a')
              : '${BigInt.parse(total) - BigInt.parse(want.total!)}';
          lines.add(
            '$stage,${key.campaign},${key.projection},${key.product},${key.baseUnit},'
            '${want.status},${want.total ?? ''},${want.contributors ?? ''},'
            '$status,${total ?? ''},${contributors ?? ''},$diff',
          );
          expect(status, want.status, reason: '$stage $key');
          expect(total, want.total, reason: '$stage $key');
          expect(contributors, want.contributors, reason: '$stage $key');
        }
        expect(
          got.keys.toSet().difference(expectedCells.keys.toSet()),
          isEmpty,
        );
        return lines;
      }

      final results = <String>[];
      if (firstExecution) {
        results.addAll(compare('RAW', await summary()));
      }
      {
        // Confirmación explícita de la Directiva; repetirla no cambia nada.
        final association = await central(
          'POST',
          '/api/v1/collective/product-associations',
          json: {
            'productId': centralProducts['Bellator'],
            'canonicalProductId': centralProducts['Belator'],
            'reason': 'Misma denominación escrita de dos formas (dataset F06).',
            'confirmed': true,
          },
        );
        expect(association.statusCode, anyOf(200, 201));
        final changed =
            (jsonDecode(association.body) as Map<String, dynamic>)['changed'];
        expect(changed, firstExecution);
        report['associationChanged'] = changed;
      }
      final canonical = await summary();
      results.addAll(compare('CANONICAL', canonical));
      final canonicalJson = {
        for (final MapEntry(:key, :value) in canonical.entries)
          '${key.campaign}|${key.projection}|${key.product}|${key.baseUnit}':
              value,
      };
      final previous = File(p.join(workdir.path, 'canonical_execution1.json'));
      if (firstExecution) {
        previous.writeAsStringSync(jsonEncode(canonicalJson));
      } else {
        // Idempotencia a nivel de agregado: celdas idénticas campo a campo.
        expect(canonicalJson, jsonDecode(previous.readAsStringSync()));
        report['identicalToExecution1'] = true;
      }
      report['httpRequests'] = transport.requests;
      report['droppedResponses'] = transport.droppedResponses;
      report['finishedAt'] = DateTime.now().toUtc().toIso8601String();
      final name = 'execution${firstExecution ? 1 : 2}';
      File(p.join(workdir.path, '$name.csv')).writeAsStringSync(
        'stage,campaign,projection_type,product,base_unit,expected_status,'
        'expected_total_base,expected_contributors,obtained_status,'
        'obtained_total_base,obtained_contributors,difference\n'
        '${results.join('\n')}\n',
      );
      File(
        p.join(workdir.path, '$name.json'),
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
      for (final line in results) {
        print('  $line');
      }
      print('  informe: ${jsonEncode(report)}');
    },
    skip: _base == null
        ? 'sin AGRO_E2E_BASE_URL (Backend local desechable)'
        : false,
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
