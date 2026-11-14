// F09-VOZ-13 (MOB #167): la evidencia de dictado queda fuera del respaldo
// privado F08 (ni en el archivo ni al restaurar), fuera de Sync v1 y de lo
// colectivo, y la migración v14 no toca nada existente. Textos SINTÉTICOS.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/backup_service.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/domain/sync/sync_types.dart';
import 'package:agroquimicos/services/auth/api_endpoint_config.dart';
import 'package:agroquimicos/services/auth/auth_http_client.dart';
import 'package:agroquimicos/services/sync/sync_access.dart';
import 'package:agroquimicos/services/sync/sync_api.dart';
import 'package:agroquimicos/services/sync/sync_worker.dart';
import 'package:agroquimicos/voice_evidence/draft_snapshot.dart';
import 'package:agroquimicos/voice_evidence/voice_evidence.dart';
import 'package:agroquimicos/voice_evidence/voice_evidence_store.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/f04_mode_fixtures.dart';
import '../support/f05_sync_fixtures.dart';
import 'evidence_fixtures.dart';

class _WorkspacePathProvider extends PathProviderPlatform {
  _WorkspacePathProvider(this.directory);
  final String directory;
  @override
  Future<String?> getDownloadsPath() async => directory;
  @override
  Future<String?> getApplicationDocumentsPath() async => directory;
  @override
  Future<String?> getTemporaryPath() async => directory;
  @override
  Future<String?> getApplicationSupportPath() async => directory;
}

const _excluded = {'voice_evidence', 'voice_evidence_consent'};

/// Una entrada confirmada con el marcador sintético en la transcripción.
VoiceEvidenceEntry _entry() {
  final trace = VoiceEvidenceTrace(clock: () => DateTime.utc(2100))
    ..voiceApplied(voiceProposal(), transcript: marker);
  return trace.finish(
    finalDraft: corrected(voiceProposal()),
    outcome: VoiceEvidenceOutcome.confirmed,
    sheetRef: 'FICHA-SINTETICA-1',
  );
}

/// Hogar con titular vinculado, actividad confirmada y evidencia con
/// consentimiento.
Future<(AppDatabase, Household)> _phone(String path, {int entries = 2}) async {
  final database = openDb(path);
  final repo = AgroRepository(database);
  final h = await seedHousehold(repo);
  await OwnerBindingStore(database).bindExistingPerson(
    personId: h.titular,
    scope: memberA,
    installationRef: installationHere,
  );
  await h.buy(h.titular, 5000);
  await h.buy(h.relative, 2000);
  await h.apply(h.titular, h.titularFarm, 1500);
  final store = VoiceEvidenceStore(database);
  await store.grantConsent(consentTextVersion: consentV1);
  for (var i = 0; i < entries; i++) {
    expect(await store.record(_entry()), VoiceEvidenceRecordResult.stored);
  }
  return (database, h);
}

bool _containsMarker(List<int> bytes) {
  final text = latin1.decode(bytes, allowInvalid: true);
  return text.contains(marker) ||
      text.contains('FICHA-SINTETICA-1') ||
      text.contains('Agro Norte') ||
      text.contains(consentV1);
}

void main() {
  sqfliteFfiInit();

  group('respaldo privado (F08) y restauración', () {
    late Directory workspace;
    setUp(() async {
      workspace = await Directory.systemTemp.createTemp('agro_evid_');
      PathProviderPlatform.instance = _WorkspacePathProvider(workspace.path);
    });
    tearDown(() async {
      try {
        await workspace.delete(recursive: true);
      } on FileSystemException {
        // En Windows SQLite puede retener el archivo; es temporal.
      }
    });

    test('el respaldo no contiene evidencia ni consentimiento; restaurar no los trae y las operaciones vuelven completas', () async {
      final (source, _) = await _phone(p.join(workspace.path, 'origen.db'));
      final sourceDb = await source.database;
      final expected = await dumpTables(sourceDb, except: _excluded);
      expect(await sourceDb.query('voice_evidence'), hasLength(2));

      final invoices = Directory(p.join(workspace.path, 'facturas'))
        ..createSync();
      final backup = (await BackupService(
        source,
        invoicesDir: () async => invoices,
      ).export()).path;

      // En el teléfono la evidencia sigue: sólo se excluye del respaldo.
      expect(await sourceDb.query('voice_evidence'), hasLength(2));
      expect(await VoiceEvidenceStore(source).consent(), isNotNull);

      // Inspección del archivo: ninguna entrada contiene el texto, y la base
      // empaquetada no tiene filas de evidencia ni de consentimiento.
      final archive = ZipDecoder().decodeBytes(File(backup).readAsBytesSync());
      for (final file in archive.files.where((f) => f.isFile)) {
        expect(
          _containsMarker(file.content as List<int>),
          isFalse,
          reason: file.name,
        );
      }
      final packed = archive.findFile('database.db')!;
      final inspected = p.join(workspace.path, 'inspeccion.db');
      File(inspected).writeAsBytesSync(packed.content as List<int>);
      final opened = await databaseFactoryFfi.openDatabase(
        inspected,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      expect(await opened.query('voice_evidence'), isEmpty);
      expect(await opened.query('voice_evidence_consent'), isEmpty);
      expect(await dumpTables(opened, except: _excluded), expected);
      await opened.close();

      // Restaurar en otro teléfono con su propia evidencia y consentimiento:
      // la base restaurada no trae ninguno de los dos y nada se recoge sin
      // un consentimiento nuevo.
      final (target, _) = await _phone(
        p.join(workspace.path, 'destino.db'),
        entries: 1,
      );
      await BackupService(
        target,
        invoicesDir: () async => invoices,
      ).restore(backup);
      final restored = await target.database;
      expect(await restored.query('voice_evidence'), isEmpty);
      expect(await restored.query('voice_evidence_consent'), isEmpty);
      expect(await dumpTables(restored, except: _excluded), expected);
      expect(
        await VoiceEvidenceStore(target).record(_entry()),
        VoiceEvidenceRecordResult.noConsent,
      );
    });

    test(
      'el contenedor privado del respaldo remoto tampoco la lleva',
      () async {
        final (source, _) = await _phone(p.join(workspace.path, 'remoto.db'));
        final bytes = await BackupService(source)
            .withPrivateContainer((container, _) => container.readAsBytes());
        final archive = ZipDecoder().decodeBytes(bytes);
        for (final file in archive.files.where((f) => f.isFile)) {
          expect(
            _containsMarker(file.content as List<int>),
            isFalse,
            reason: file.name,
          );
        }
      },
    );

    test(
      'una restauración nunca trae evidencia, aunque el archivo la contenga',
      () async {
        final manipulated = p.join(workspace.path, 'manipulado.db');
        final (source, _) = await _phone(manipulated);
        await source.close();
        // Un archivo de base suelta (formato histórico) con evidencia dentro.
        final (target, _) = await _phone(
          p.join(workspace.path, 'destino2.db'),
          entries: 0,
        );
        await BackupService(target).restore(manipulated);
        final restored = await target.database;
        expect(await restored.query('voice_evidence'), isEmpty);
        expect(await restored.query('voice_evidence_consent'), isEmpty);
        expect(await restored.query('owner_bindings'), isNotEmpty);
      },
    );
  });

  group('Sync v1 y lo colectivo', () {
    test(
      'con evidencia guardada, la carga enviada no contiene nada de ella',
      () async {
        final fixture = await seedSyncFixture(
          clock: () => DateTime.utc(2026, 10, 15, 12),
        );
        final store = VoiceEvidenceStore(fixture.database);
        await store.grantConsent(consentTextVersion: consentV1);
        expect(await store.record(_entry()), VoiceEvidenceRecordResult.stored);
        // Guardar evidencia no encola nada.
        expect(await fixture.outboxRows(), isEmpty);

        // Una intención real (necesidad declarada) para que el worker envíe.
        await fixture.needs.declare(
          referenceDate: inCampaign,
          productId: fixture.litreProductId,
          quantityBase: 1000,
        );
        final requests = <http.Request>[];
        final client = MockClient((request) async {
          requests.add(request);
          final id = (jsonDecode(request.body) as Map)['operationId'] as String;
          return http.Response(ackJson(id), 200);
        });
        final now = DateTime.utc(2026, 10, 15, 12);
        final access = SyncAccessHolder(clock: () => now)
          ..accept('token-sintetico', memberA.memberId, memberA.tenantId);
        final api = SyncApi(
          AuthHttpClient(
            config: ApiEndpointConfig(Uri.parse('https://sindicato.example')),
            client: client,
          ),
          clock: () => now,
        );
        final report = await SyncWorker(
          outbox: fixture.outbox,
          owners: fixture.owners,
          api: () => api,
          access: access,
          random: Random(7),
          clock: () => now,
        ).run();
        expect(report.accepted, 1);
        expect(requests, hasLength(1));
        for (final request in requests) {
          expect(_containsMarker(utf8.encode(request.body)), isFalse);
          expect(request.body.contains('transcript'), isFalse);
          expect(request.body.contains('evidence'), isFalse);
        }
        expect(
          (await fixture.outboxEntries()).single.status,
          OutboxStatus.acked,
        );
        for (final row in await fixture.outboxRows()) {
          expect(_containsMarker(utf8.encode(jsonEncode(row))), isFalse);
        }
        // La evidencia sigue en el teléfono, intacta.
        expect(await store.count(), 1);
      },
    );

    test('ningún código de Sync, lo colectivo ni los servicios lee las tablas de evidencia', () {
      // Sólo el esquema, la exclusión del respaldo y el propio almacén las
      // nombran.
      final allowed = {
        p.normalize('lib/data/app_database.dart'),
        p.normalize('lib/data/backup_service.dart'),
      };
      // Integración (2026-11-08): la presentación sí importa el módulo (el
      // enganche de las pantallas y la pantalla de consentimiento usan el
      // sumidero y el almacén). La guarda se precisa en dos partes:
      // 1. fuera del esquema, el respaldo y el propio módulo, nadie nombra
      //    las TABLAS (ninguna consulta SQL propia);
      // 2. Sync, lo colectivo y los servicios no nombran la evidencia de
      //    ninguna forma.
      final tableName = RegExp(r'\bvoice_evidence(_consent)?\b');
      final syncSide = [
        p.normalize('lib/data/sync'),
        p.normalize('lib/services'),
      ];
      final offenders = <String>[];
      for (final file
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        final path = p.normalize(file.path);
        if (allowed.contains(path)) continue;
        if (p.isWithin(p.normalize('lib/voice_evidence'), path)) continue;
        final code = file.readAsStringSync();
        final body = code
            .split('\n')
            .where((l) => !RegExp(r'^\s*(import|export) ').hasMatch(l))
            .join('\n');
        if (tableName.hasMatch(body)) offenders.add('$path (tablas)');
        if (syncSide.any((dir) => p.isWithin(dir, path)) &&
            (code.contains('voice_evidence') ||
                code.contains('VoiceEvidence') ||
                code.contains('voiceEvidence'))) {
          offenders.add('$path (Sync/servicios)');
        }
      }
      expect(offenders, isEmpty);
    });
  });

  group('migración v14', () {
    test('una base v13 migra sin tocar ninguna fila, con las tablas vacías y sin consentimiento', () async {
      final path = await tempDbPath('v13');
      final (phone, _) = await _phone(path);
      final before = await dumpTables(await phone.database, except: _excluded);
      await phone.close();
      final raw = await databaseFactoryFfi.openDatabase(path);
      await raw.execute('DROP TABLE voice_evidence');
      await raw.execute('DROP TABLE voice_evidence_consent');
      await raw.execute('PRAGMA user_version = 13');
      await raw.close();

      final migrated = openDb(path);
      final db = await migrated.database;
      expect(
        (await db.rawQuery('PRAGMA user_version')).single.values.single,
        AppDatabase.schemaVersion,
      );
      expect(await db.query('voice_evidence'), isEmpty);
      expect(await db.query('voice_evidence_consent'), isEmpty);
      expect(await dumpTables(db, except: _excluded), before);
      expect(
        await VoiceEvidenceStore(migrated).record(_entry()),
        VoiceEvidenceRecordResult.noConsent,
      );
    });

    test('un respaldo v13 (sin las tablas) se restaura y queda en v14 sin evidencia', () async {
      final workspace = await Directory.systemTemp.createTemp('agro_evid13_');
      addTearDown(() async {
        try {
          await workspace.delete(recursive: true);
        } on FileSystemException {
          // Temporal.
        }
      });
      PathProviderPlatform.instance = _WorkspacePathProvider(workspace.path);
      final legacy = p.join(workspace.path, 'v13.db');
      final (phone, _) = await _phone(legacy, entries: 0);
      await phone.close();
      final raw = await databaseFactoryFfi.openDatabase(legacy);
      await raw.execute('DROP TABLE voice_evidence');
      await raw.execute('DROP TABLE voice_evidence_consent');
      await raw.execute('PRAGMA user_version = 13');
      await raw.close();

      final (target, _) = await _phone(p.join(workspace.path, 't.db'));
      final validation = await BackupService(target).validate(legacy);
      expect(validation.isValid, isTrue);
      expect(validation.schemaVersion, 13);
      await BackupService(target).restore(legacy);
      final restored = await target.database;
      expect(
        (await restored.rawQuery('PRAGMA user_version')).single.values.single,
        AppDatabase.schemaVersion,
      );
      expect(await restored.query('voice_evidence'), isEmpty);
      expect(await restored.query('voice_evidence_consent'), isEmpty);
    });
  });
}
