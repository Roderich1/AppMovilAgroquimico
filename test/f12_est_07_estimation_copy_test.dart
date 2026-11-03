// F12-EST-07-MOB (MOB #164): copia descargada de la estimación en SQLite.
// Formato FARMER, cantidades exactas, acceso por identidad y titular,
// invalidación, respuestas tardías, migración v13, respaldo y Sync v1.
import 'dart:convert';
import 'dart:io';

import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/backup_service.dart';
import 'package:agroquimicos/data/estimation_copy_store.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/domain/estimation/farmer_estimation.dart';
import 'package:agroquimicos/domain/installation_access.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';
import 'support/f12_estimation_fixtures.dart';

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

/// Hogar con titular vinculado a [scope] y algo de actividad confirmada.
class _Phone {
  _Phone(this.database, this.repo, this.h, this.binding);
  final AppDatabase database;
  final AgroRepository repo;
  final Household h;
  final OwnerBinding binding;

  EstimationCopyStore get store => EstimationCopyStore(database);

  EstimationIdentity get identity => EstimationIdentity(
    memberId: binding.scope.memberId,
    tenantId: binding.scope.tenantId,
    bindingId: binding.id,
  );

  Future<EstimationSaveOutcome> save(
    Map<String, Object?> json, {
    EstimationIdentity? as,
  }) async {
    final grant = await store.grant(as ?? identity);
    return store.save(grant, FarmerDownload.fromJson(json), json);
  }
}

Future<_Phone> _phone({
  String path = inMemoryDatabasePath,
  OwnerScope scope = memberA,
}) async {
  final database = openDb(path);
  final repo = AgroRepository(database);
  final h = await seedHousehold(repo);
  final binding = await OwnerBindingStore(database).bindExistingPerson(
    personId: h.titular,
    scope: scope,
    installationRef: installationHere,
  );
  return _Phone(database, repo, h, binding);
}

/// Una copia de la base: el JSON guardado contiene este nombre de producto.
const _marker = 'Herbicida de ensayo';

void main() {
  sqfliteFfiInit();

  group('formato FARMER (INT-09 v1)', () {
    test('acepta la descarga y los resultados del perfil del Agricultor', () {
      final download = FarmerDownload.fromJson(farmerDownloadJson());
      expect(download.memberRef, memberA.memberId);
      expect(download.tenantRef, memberA.tenantId);
      expect(download.downloadedAt, DateTime.utc(2026, 11, 2, 22, 4, 34, 800));
      expect(download.results.map((r) => r.status), [
        'ESTIMATED',
        'INSUFFICIENT_DATA',
      ]);
      expect(download.results.first.validity, 'CURRENT');
      final results = FarmerResults.fromJson(farmerResultsJson());
      expect(results.results.first.estimateBase, '111000.000000');
    });

    test('rechaza el perfil institucional, naive, cobertura o cifras con un resultado sin estimar', () {
      final institutional = farmerDownloadJson()..['profile'] = 'INSTITUTIONAL';
      final withNaive = farmerDownloadJson(
        results: [
          {...estimatedResult('validity_at_download'), 'naive_base': '116000'},
        ],
      );
      final withCoverage = farmerResultsJson()
        ..['coverage'] = {'status': 'IDENTIFIED'};
      final figureWithoutEstimate = farmerDownloadJson(
        results: [
          {...insufficientResult('validity_at_download'), 'estimate_base': '0'},
        ],
      );
      final otherRole = farmerDownloadJson()
        ..['subject'] = {'member_ref': memberA.memberId, 'role': 'DIRECTIVA'};
      for (final json in [
        institutional,
        withNaive,
        figureWithoutEstimate,
        otherRole,
      ]) {
        expect(
          () => FarmerDownload.fromJson(json),
          throwsA(isA<FarmerEstimationFormatException>()),
        );
      }
      expect(
        () => FarmerResults.fromJson(withCoverage),
        throwsA(isA<FarmerEstimationFormatException>()),
      );
    });

    test('las cantidades son exactas, sin coma flotante, y una ausencia nunca es cero', () {
      expect(formatExactQuantity('111000.000000', 'ML').presentation, '111 L');
      expect(formatExactQuantity('111000.000000', 'ML').base, '111.000 mL');
      expect(formatExactQuantity('1234.5', 'ML').presentation, '1,2345 L');
      expect(formatExactQuantity('1234.5', 'ML').base, '1.234,5 mL');
      expect(
        formatExactQuantity('0.000001', 'G').presentation,
        '0,000000001 kg',
      );
      expect(formatExactQuantity('0.000001', 'G').base, '0,000001 g');
      // 0.1 + 0.2 en coma flotante no da 0.3: aquí sí.
      expect(formatExactQuantity('300.3', 'ML').presentation, '0,3003 L');
      expect(
        formatExactQuantity('9007199254740993.000001', 'ML').base,
        '9.007.199.254.740.993,000001 mL',
      );
      final download = FarmerDownload.fromJson(farmerDownloadJson());
      expect(estimationFigureText(download.results[0]), '111 L (111.000 mL)');
      expect(estimationFigureText(download.results[1]), 'Sin cifra');
    });
  });

  group('copia en SQLite: acceso por identidad y titular', () {
    test('guarda y lee la copia del titular; otra identidad, sindicato o titular no la leen', () async {
      final phone = await _phone();
      expect(
        await phone.save(farmerDownloadJson()),
        EstimationSaveOutcome.saved,
      );
      final copy = await phone.store.read(phone.identity, campaignWinter);
      expect(
        copy!.download.downloadedAt.toIso8601String(),
        '2026-11-02T22:04:34.800Z',
      );
      expect(await phone.store.readable(null), isEmpty);
      for (final other in [
        EstimationIdentity(
          memberId: memberB.memberId,
          tenantId: memberB.tenantId,
          bindingId: phone.binding.id,
        ),
        EstimationIdentity(
          memberId: memberAOtherTenant.memberId,
          tenantId: memberAOtherTenant.tenantId,
          bindingId: phone.binding.id,
        ),
        EstimationIdentity(
          memberId: memberA.memberId,
          tenantId: memberA.tenantId,
          bindingId: phone.binding.id + 1,
        ),
      ]) {
        expect(await phone.store.readable(other), isEmpty);
      }
    });

    test('no guarda la respuesta de otro Member o sindicato', () async {
      final phone = await _phone();
      expect(
        await phone.save(farmerDownloadJson(scope: memberB)),
        EstimationSaveOutcome.otherSubject,
      );
      expect(
        await phone.save(farmerDownloadJson(scope: memberAOtherTenant)),
        EstimationSaveOutcome.otherSubject,
      );
      expect(
        await (await phone.database.database).query('estimation_copies'),
        isEmpty,
      );
    });

    test('sólo se reemplaza por una descarga posterior de la misma identidad y campaña', () async {
      final phone = await _phone();
      await phone.save(farmerDownloadJson());
      expect(
        await phone.save(
          farmerDownloadJson(downloadedAt: '2026-11-02T21:00:00.000Z'),
        ),
        EstimationSaveOutcome.keptNewer,
      );
      expect(
        await phone.save(
          farmerDownloadJson(downloadedAt: '2026-11-03T08:00:00.000Z'),
        ),
        EstimationSaveOutcome.saved,
      );
      expect(
        (await phone.store.read(
          phone.identity,
          campaignWinter,
        ))!.download.downloadedAt,
        DateTime.utc(2026, 11, 3, 8),
      );
    });

    test(
      'una fila manipulada (otra campaña u otro Member en el JSON) no se lee',
      () async {
        final phone = await _phone();
        await phone.save(farmerDownloadJson());
        final db = await phone.database.database;
        await db.update('estimation_copies', {
          'payload': jsonEncode(farmerDownloadJson(campaign: campaignSummer)),
        });
        expect(await phone.store.readable(phone.identity), isEmpty);
        await db.update('estimation_copies', {
          'payload': jsonEncode(farmerDownloadJson(scope: memberB)),
        });
        expect(await phone.store.readable(phone.identity), isEmpty);
      },
    );
  });

  group('invalidación y respuestas tardías', () {
    test('un rechazo retira todas las copias y un 404 sólo esa campaña; el borrado va aparte', () async {
      final phone = await _phone();
      await phone.save(farmerDownloadJson());
      await phone.save(farmerDownloadJson(campaign: campaignSummer));
      await phone.store.retireCampaign(campaignSummer);
      expect(
        (await phone.store.readable(phone.identity))
            .map((c) => c.download.target.campaignRef),
        [campaignWinter],
      );
      final db = await phone.database.database;
      // Retirar no borra: la fila sigue hasta purgar.
      expect(await db.query('estimation_copies'), hasLength(2));
      expect(await phone.store.purge(phone.identity), 1);
      await phone.store.retireAll();
      expect(await phone.store.readable(phone.identity), isEmpty);
      expect(await db.query('estimation_copies'), hasLength(1));
      expect(await phone.store.purge(phone.identity), 1);
      expect(await db.query('estimation_copies'), isEmpty);
    });

    test('una descarga pedida antes de invalidar no se guarda al responder después (cierre, rechazo o 404)', () async {
      final phone = await _phone();
      for (final (invalidate, outcome)
          in <(Future<void> Function(), EstimationSaveOutcome)>[
            (phone.store.retireAll, EstimationSaveOutcome.accessChanged),
            (
              () => phone.store.retireCampaign(campaignWinter),
              EstimationSaveOutcome.targetRetired,
            ),
          ]) {
        final grant = await phone.store.grant(phone.identity);
        await invalidate();
        expect(
          await phone.store.save(
            grant,
            FarmerDownload.fromJson(farmerDownloadJson()),
            farmerDownloadJson(),
          ),
          outcome,
        );
      }
      expect(
        await (await phone.database.database).query('estimation_copies'),
        isEmpty,
      );
      // Una descarga pedida después sí se guarda.
      expect(
        await phone.save(farmerDownloadJson()),
        EstimationSaveOutcome.saved,
      );
    });

    test('cambiar de titular descarta la copia y una descarga en curso del anterior no se guarda', () async {
      final phone = await _phone();
      await phone.save(farmerDownloadJson());
      final pending = await phone.store.grant(phone.identity);
      final next = await OwnerBindingStore(phone.database)
          .changeOwner(newPersonId: phone.h.relative, sessionScope: memberA);
      expect(
        await (await phone.database.database).query('estimation_copies'),
        isEmpty,
      );
      expect(
        await phone.store.save(
          pending,
          FarmerDownload.fromJson(farmerDownloadJson()),
          farmerDownloadJson(),
        ),
        EstimationSaveOutcome.accessChanged,
      );
      final newIdentity = EstimationIdentity(
        memberId: memberA.memberId,
        tenantId: memberA.tenantId,
        bindingId: next.id,
      );
      // El titular nuevo descarga la suya; la del anterior no vuelve.
      expect(
        await phone.save(farmerDownloadJson(), as: newIdentity),
        EstimationSaveOutcome.saved,
      );
      expect(await phone.store.readable(phone.identity), isEmpty);
      expect(await phone.store.readable(newIdentity), hasLength(1));
    });

    test('si el titular vigente ya no es el de la descarga, no se guarda aunque el acceso siga', () async {
      final phone = await _phone();
      final pending = await phone.store.grant(phone.identity);
      // Otro vínculo por una vía que no borra el acceso (escritura directa).
      final db = await phone.database.database;
      await db.update(
        'owner_bindings',
        {'ended_at': '2026-11-02T00:00:00.000Z', 'end_reason': 'OWNER_CHANGED'},
        where: 'id=?',
        whereArgs: [phone.binding.id],
      );
      await db.insert('owner_bindings', {
        'person_id': phone.h.relative,
        'member_id': memberA.memberId,
        'tenant_id': memberA.tenantId,
        'owner_role': 'FAMILY',
        'bound_at': '2026-11-02T00:00:00.000Z',
      });
      expect(await db.query('estimation_copy_access'), hasLength(1));
      expect(
        await phone.store.save(
          pending,
          FarmerDownload.fromJson(farmerDownloadJson()),
          farmerDownloadJson(),
        ),
        EstimationSaveOutcome.accessChanged,
      );
      expect(await db.query('estimation_copies'), isEmpty);
    });

    test(
      'las filas de otra identidad o titular se eliminan físicamente',
      () async {
        final phone = await _phone();
        await phone.save(farmerDownloadJson());
        final other = EstimationIdentity(
          memberId: memberA.memberId,
          tenantId: memberA.tenantId,
          bindingId: phone.binding.id + 7,
        );
        expect(await phone.store.purge(other), 1);
        expect(
          await (await phone.database.database).query('estimation_copies'),
          isEmpty,
        );
        await phone.save(farmerDownloadJson());
        expect(await phone.store.purge(null), 1);
      },
    );

    test('guardar la copia no encola nada para Sync v1', () async {
      final phone = await _phone();
      await phone.save(farmerDownloadJson());
      final db = await phone.database.database;
      expect(await db.query('sync_outbox'), isEmpty);
    });
  });

  group('migración v13', () {
    test(
      'una base v12 migra sin tocar ninguna fila y con la copia vacía',
      () async {
        final path = await tempDbPath('v12');
        final phone = await _phone(path: path);
        await phone.h.buy(phone.h.titular, 5000);
        await phone.save(farmerDownloadJson());
        final before = await dumpTables(
          await phone.database.database,
          except: {'estimation_copies', 'estimation_copy_access'},
        );
        await phone.database.close();
        final raw = await databaseFactoryFfi.openDatabase(path);
        await raw.execute('DROP TABLE estimation_copies');
        await raw.execute('DROP TABLE estimation_copy_access');
        await raw.execute('PRAGMA user_version = 12');
        await raw.close();

        final migrated = openDb(path);
        final db = await migrated.database;
        expect(
          (await db.rawQuery('PRAGMA user_version')).single.values.single,
          13,
        );
        expect(await db.query('estimation_copies'), isEmpty);
        expect(
          await dumpTables(
            db,
            except: {'estimation_copies', 'estimation_copy_access'},
          ),
          before,
        );
      },
    );
  });

  group('respaldo privado y restauración', () {
    late Directory workspace;
    setUp(() async {
      workspace = await Directory.systemTemp.createTemp('agro_est_');
      PathProviderPlatform.instance = _WorkspacePathProvider(workspace.path);
    });
    tearDown(() async {
      try {
        await workspace.delete(recursive: true);
      } on FileSystemException {
        // En Windows SQLite puede retener el archivo; es temporal.
      }
    });

    test('el respaldo no contiene la copia; tras restaurar no hay copia y las operaciones están completas', () async {
      final source = await _phone(path: p.join(workspace.path, 'origen.db'));
      await source.h.buy(source.h.titular, 5000);
      await source.h.buy(source.h.relative, 2000);
      await source.h.apply(source.h.titular, source.h.titularFarm, 1500);
      await source.save(farmerDownloadJson());
      await source.save(farmerDownloadJson(campaign: campaignSummer));
      final sourceDb = await source.database.database;
      expect(await sourceDb.query('estimation_copies'), hasLength(2));
      const excluded = {'estimation_copies', 'estimation_copy_access'};
      final expected = await dumpTables(sourceDb, except: excluded);

      final invoices = Directory(p.join(workspace.path, 'facturas'))
        ..createSync();
      final backup = (await BackupService(
        source.database,
        invoicesDir: () async => invoices,
      ).export()).path;

      // La copia del teléfono sigue en la base de origen: sólo se excluye del respaldo.
      expect(await sourceDb.query('estimation_copies'), hasLength(2));

      // Inspección del archivo: database.db no tiene filas ni bytes de la copia.
      final archive = ZipDecoder().decodeBytes(File(backup).readAsBytesSync());
      final packed = archive.findFile('database.db')!;
      final packedBytes = packed.content as List<int>;
      expect(
        latin1.decode(packedBytes, allowInvalid: true).contains(_marker),
        isFalse,
      );
      expect(
        latin1.decode(packedBytes, allowInvalid: true).contains(campaignWinter),
        isFalse,
      );
      final inspected = p.join(workspace.path, 'inspeccion.db');
      File(inspected).writeAsBytesSync(packedBytes);
      final opened = await databaseFactoryFfi.openDatabase(
        inspected,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      expect(await opened.query('estimation_copies'), isEmpty);
      expect(await opened.query('estimation_copy_access'), isEmpty);
      expect(await dumpTables(opened, except: excluded), expected);
      await opened.close();

      // Restaurar en otro teléfono con su propia copia: queda «sin copia descargada».
      final target = await _phone(path: p.join(workspace.path, 'destino.db'));
      await target.save(farmerDownloadJson());
      await BackupService(
        target.database,
        invoicesDir: () async => invoices,
      ).restore(backup);
      final restored = await target.database.database;
      expect(await restored.query('estimation_copies'), isEmpty);
      expect(await restored.query('estimation_copy_access'), isEmpty);
      expect(await dumpTables(restored, except: excluded), expected);
    });

    test(
      'una restauración nunca trae una copia, aunque el archivo la contenga',
      () async {
        final source = await _phone(
          path: p.join(workspace.path, 'manipulado.db'),
        );
        await source.save(farmerDownloadJson());
        await source.database.close();
        // Un archivo de base (formato histórico) con la copia dentro.
        final target = await _phone(
          path: p.join(workspace.path, 'destino2.db'),
        );
        await BackupService(target.database)
            .restore(p.join(workspace.path, 'manipulado.db'));
        final restored = await target.database.database;
        expect(await restored.query('estimation_copies'), isEmpty);
        expect(await restored.query('owner_bindings'), isNotEmpty);
      },
    );

    test('una descarga pedida antes de restaurar no se guarda en la base restaurada', () async {
      final source = await _phone(path: p.join(workspace.path, 'r-origen.db'));
      final invoices = Directory(p.join(workspace.path, 'facturas'))
        ..createSync();
      final backup = (await BackupService(
        source.database,
        invoicesDir: () async => invoices,
      ).export()).path;
      final target = await _phone(path: p.join(workspace.path, 'r-destino.db'));
      final pending = await target.store.grant(target.identity);
      await BackupService(
        target.database,
        invoicesDir: () async => invoices,
      ).restore(backup);
      // El titular restaurado es el mismo vínculo (Member A, mismo id).
      expect(
        (await OwnerBindingStore(target.database).activeBinding())!.id,
        target.binding.id,
      );
      expect(
        await target.store.save(
          pending,
          FarmerDownload.fromJson(farmerDownloadJson()),
          farmerDownloadJson(),
        ),
        EstimationSaveOutcome.accessChanged,
      );
      expect(
        await (await target.database.database).query('estimation_copies'),
        isEmpty,
      );
    });
  });
}
