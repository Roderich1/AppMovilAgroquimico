// Respaldo privado remoto (F08-BKP-04/05, MOB #35/#36).
//
// El transporte es un MockClient que imita el contrato de BE #39 en memoria:
// nada sale a la red. La base, el contenedor `.agrobackup`, GuardedRestore,
// el controlador de acceso y la outbox son los reales.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/backup_encryption.dart';
import 'package:agroquimicos/data/backup_service.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/data/sync/central_binding_store.dart';
import 'package:agroquimicos/data/sync/declared_need_store.dart';
import 'package:agroquimicos/data/sync/sync_outbox_store.dart';
import 'package:agroquimicos/domain/installation_access.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/sync/sync_types.dart';
import 'package:agroquimicos/guarded_restore.dart';
import 'package:agroquimicos/installation_access.dart';
import 'package:agroquimicos/services/auth/api_endpoint_config.dart';
import 'package:agroquimicos/services/auth/auth_http_client.dart';
import 'package:agroquimicos/services/auth/auth_api_exception.dart';
import 'package:agroquimicos/services/auth/existing_session_providers.dart';
import 'package:agroquimicos/services/auth/existing_session_startup.dart';
import 'package:agroquimicos/services/auth/remote_session_coordinator.dart';
import 'package:agroquimicos/services/auth/remote_session_providers.dart';
import 'package:agroquimicos/services/backup/backup_keyring.dart';
import 'package:agroquimicos/services/backup/remote_backup_api.dart';
import 'package:agroquimicos/services/backup/remote_backup_service.dart';
import 'package:agroquimicos/services/sync/sync_access.dart';
import 'package:agroquimicos/services/sync/sync_api.dart';
import 'package:agroquimicos/services/sync/sync_providers.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'backup_container_support.dart';
import 'support/f04_app_access.dart';
import 'support/f04_mode_fixtures.dart';
import 'support/f05_sync_fixtures.dart'
    show ackJson, centralCampaign, centralProduct, inCampaign;

const _origin = 'https://sindicato.example';
const _token = 'token-sintetico';

class _WorkspacePaths extends PathProviderPlatform {
  _WorkspacePaths(this.directory);
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

String _hex(List<int> bytes) => sha256.convert(bytes).toString();

/// Copia guardada por el servidor falso.
class _Stored {
  _Stored(
    this.id,
    this.bytes,
    this.schemaVersion,
    this.createdAt, {
    this.formatVersion = 2,
  });
  final String id;
  final Uint8List bytes;
  final int schemaVersion;
  final int formatVersion;
  final DateTime createdAt;
  late String declaredSha = _hex(bytes);

  Map<String, Object?> get json => {
    'id': id,
    'sha256': declaredSha,
    'sizeBytes': bytes.length,
    'contentType': 'application/octet-stream',
    'formatVersion': formatVersion,
    'schemaVersion': schemaVersion,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };
}

/// Imita `/api/v1/me/backups` en memoria, con fallos inyectables.
class _FakeServer {
  final stored = <String, _Stored>{};
  final requests = <http.BaseRequest>[];
  var _next = 0;

  /// Cambia los bytes servidos sin cambiar la cabecera ni los metadatos.
  bool corruptBody = false;

  /// Corta la descarga a mitad.
  bool truncateBody = false;

  /// El servidor confirma la subida con otro SHA-256.
  bool misreportUpload = false;

  /// Sin conexión.
  bool offline = false;

  /// Guarda la subida y pierde la respuesta (el cliente no la recibe).
  bool loseUploadResponse = false;

  /// Responde 401/403 a todo.
  int? rejectWith;

  String _id() {
    _next++;
    return '0000000${_next.toString().padLeft(1, '0')}-0000-4000-8000-'
        '${_next.toString().padLeft(12, '0')}';
  }

  http.StreamedResponse _json(int status, Object body) => http.StreamedResponse(
    Stream.value(utf8.encode(jsonEncode(body))),
    status,
    headers: {'content-type': 'application/json'},
  );

  late final client = MockClient.streaming((request, body) async {
    requests.add(request);
    if (offline) throw http.ClientException('sin red');
    if (rejectWith != null) {
      return _json(rejectWith!, {
        'errorCode': rejectWith == 401
            ? 'AUTH_REQUIRED'
            : 'AUTH_CONTEXT_FORBIDDEN',
      });
    }
    expect(request.headers['Authorization'], 'Bearer $_token');
    final path = request.url.path;
    if (path == '/api/v1/me/backups' && request.method == 'GET') {
      return _json(200, {
        'backups': [for (final s in stored.values.toList().reversed) s.json],
      });
    }
    if (path == '/api/v1/me/backups' && request.method == 'POST') {
      final bytes = Uint8List.fromList(
        await body.expand((chunk) => chunk).toList(),
      );
      if (_hex(bytes) != request.headers['X-Content-SHA256']) {
        return _json(422, {'errorCode': 'BACKUP_SHA256_MISMATCH'});
      }
      final entry = _Stored(
        _id(),
        bytes,
        int.parse(request.headers['X-Backup-Schema-Version']!),
        DateTime.utc(2026, 10, 16, 12, stored.length),
        formatVersion: int.parse(request.headers['X-Backup-Format-Version']!),
      );
      stored[entry.id] = entry;
      if (loseUploadResponse) {
        throw http.ClientException('respuesta perdida');
      }
      final json = Map<String, Object?>.of(entry.json);
      if (misreportUpload) json['sha256'] = 'f' * 64;
      return _json(201, json);
    }
    final match = RegExp(r'^/api/v1/me/backups/([0-9a-f-]{36})(/content)?$')
        .firstMatch(path);
    final entry = match == null ? null : stored[match.group(1)];
    if (entry == null) return _json(404, {'errorCode': 'BACKUP_NOT_FOUND'});
    if (request.method == 'DELETE') {
      stored.remove(entry.id);
      return http.StreamedResponse(const Stream.empty(), 204);
    }
    var served = Uint8List.fromList(entry.bytes);
    if (corruptBody) served[served.length - 10] ^= 0xff;
    final stream = truncateBody
        ? (StreamController<List<int>>()
                ..add(served.sublist(0, served.length ~/ 2))
                ..addError(http.ClientException('conexión cortada'))
                ..close())
              .stream
        : Stream<List<int>>.fromIterable([
            served.sublist(0, served.length ~/ 3),
            served.sublist(served.length ~/ 3),
          ]);
    return http.StreamedResponse(
      stream,
      200,
      contentLength: entry.bytes.length,
      headers: {
        'content-type': 'application/octet-stream',
        'x-content-sha256': entry.declaredSha,
      },
    );
  });

  RemoteBackupApi api() => RemoteBackupApi(
    config: ApiEndpointConfig(Uri.parse(_origin)),
    client: client,
  );
}

/// Verificación en línea simulada: concede el acceso de [grant] o falla.
class _FakeRemote extends RemoteSessionController {
  _FakeRemote(this.grant);
  final OwnerScope? grant;
  int calls = 0;

  @override
  RemoteSessionState build() =>
      const RemoteSessionState(RemoteSessionPhase.idle);

  @override
  Future<RemoteSessionState> verifyOnline() async {
    calls++;
    final scope = grant;
    if (scope == null) {
      return const RemoteSessionState(
        RemoteSessionPhase.requiresReauthentication,
      );
    }
    ref
        .read(syncAccessHolderProvider)
        .accept(_token, scope.memberId, scope.tenantId);
    return const RemoteSessionState(RemoteSessionPhase.remoteAvailable);
  }
}

/// Un teléfono: su base, su carpeta de fotografías y su sesión.
class _Phone {
  _Phone(
    this.container,
    this.database,
    this.directory,
    this.invoices,
    this.syncRequests,
    this.keyring,
    this.recoveryKey,
  );
  final ProviderContainer container;

  /// Llavero de este teléfono (almacén en memoria) y la clave confirmada con
  /// la que sube; null si se creó sin clave.
  final BackupKeyring keyring;
  final BackupRecoveryKey? recoveryKey;
  final AppDatabase database;
  final Directory directory;
  final Directory invoices;

  /// Peticiones que llegaron a Sync v1 desde este teléfono.
  final List<http.Request> syncRequests;

  InstallationAccessState? get access =>
      container.read(installationAccessProvider);

  Future<Map<String, List<Map<String, Object?>>>> dump() async =>
      dumpTables(await database.database);

  Future<Map<String, String>> photos() async => {
    if (await invoices.exists())
      await for (final f in invoices.list())
        if (f is File) p.basename(f.path): _hex(await f.readAsBytes()),
  };

  RemoteBackupService service(
    _FakeServer server,
    OwnerScope session, {
    void Function()? onAccessRejected,
  }) => RemoteBackupService(
    onAccessRejected: onAccessRejected,
    api: server.api,
    access: () async => VerifiedAccess(
      accessToken: _token,
      scope: session,
      obtainedAt: DateTime.now(),
    ),
    backups: container.read(backupServiceProvider),
    restorer: container.read(guardedRestoreProvider),
    ownerScope: () async =>
        (await OwnerBindingStore(database).activeBinding())?.scope,
    workDirectory: () async => Directory(p.join(directory.path, 'privado')),
    keyring: keyring,
  );
}

/// Almacén seguro simulado: un valor en memoria.
class _MemoryVault implements BackupKeyVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
}

void main() {
  sqfliteFfiInit();

  late Directory workspace;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('agro_f08_remote_');
    PathProviderPlatform.instance = _WorkspacePaths(workspace.path);
  });
  tearDown(() async {
    try {
      await workspace.delete(recursive: true);
    } on FileSystemException {
      // En Windows el motor puede retener un archivo; es temporal.
    }
  });

  Future<_Phone> phone(
    String name, {
    required OwnerScope session,
    required String installationRef,
    Future<void> Function(AppDatabase database, Directory invoices)? seed,
    _FakeRemote? remote,
    bool enrollKey = true,
    BackupRecoveryKey? recoveryKey,
  }) async {
    final directory = await Directory(p.join(workspace.path, name))
        .create(recursive: true);
    final invoices = Directory(p.join(directory.path, 'invoices'));
    await invoices.create();
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      path: p.join(directory.path, 'agro.db'),
    );
    addTearDown(database.close);
    if (seed != null) await seed(database, invoices);
    final syncRequests = <http.Request>[];
    final syncTransport = MockClient((request) async {
      syncRequests.add(request);
      final id = (jsonDecode(request.body) as Map)['operationId'] as String;
      return http.Response(ackJson(id), 200);
    });
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        existingSessionStartupProvider.overrideWithValue(
          ExistingSessionStartupState.localSessionAvailable,
        ),
        ...startupAccessOverrides(
          sessionScope: session,
          installationRef: installationRef,
        ),
        backupServiceProvider.overrideWithValue(
          BackupService(
            database,
            invoicesDir: () async => invoices,
            exportDirectory: () async => directory,
          ),
        ),
        remoteSessionProvider.overrideWith(() => remote ?? _FakeRemote(null)),
        syncApiProvider.overrideWithValue(
          SyncApi(
            AuthHttpClient(
              config: ApiEndpointConfig(Uri.parse(_origin)),
              client: syncTransport,
            ),
          ),
        ),
      ],
    );
    // build() lanza su propio refresh en una microtarea: se deja terminar
    // antes de desmontar, aunque la prueba acabe enseguida.
    addTearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await container.read(installationAccessProvider.notifier).refresh();
      container.dispose();
    });
    await container.read(installationAccessProvider.notifier).refresh();
    // Clave de recuperación: la que la persona ya tenía anotada
    // ([recoveryKey]) o una nueva, mostrada y confirmada (F08-ADR-003 §3.4).
    final keyring = BackupKeyring(_MemoryVault());
    BackupRecoveryKey? key = recoveryKey;
    if (key != null) {
      await keyring.adoptRecovered(key);
    } else if (enrollKey) {
      key = await keyring.pendingKey();
      await keyring.confirmPending(key.displayText);
    }
    return _Phone(
      container,
      database,
      directory,
      invoices,
      syncRequests,
      keyring,
      key,
    );
  }

  /// Datos del titular A: hogar, compra con fotografía y una cola con una
  /// intención aceptada (ACKED) y otra enviada sin respuesta.
  Future<void> farmerData(
    AppDatabase db,
    Directory invoices, {
    OwnerScope scope = memberA,
    String? installationRef,
  }) async {
    final household = await seedHousehold(AgroRepository(db));
    await household.buy(household.titular, 3000);
    final photo = File(p.join(invoices.path, 'factura_1.jpg'));
    await photo.writeAsBytes(List<int>.generate(3000, (i) => (i * 7) % 251));
    await household.repo.confirmPurchase(
      PurchaseDraft(
        supplierId: household.supplier,
        campaignId: household.campaign,
        purchaseDate: DateTime.utc(2026, 1, 5),
        invoiceNumber: 'F-1',
        invoiceImagePath: photo.path,
        items: [
          PurchaseItemDraft(
            productId: household.product,
            quantityBase: 1500,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 9000,
            allocations: [
              AllocationDraft(personId: household.titular, quantityBase: 1500),
            ],
          ),
        ],
      ),
    );
    await OwnerBindingStore(db).bindExistingPerson(
      personId: household.titular,
      scope: scope,
      installationRef: installationRef ?? installationHere,
    );
    final repo = AgroRepository(db);
    final product = await repo.addProduct(name: 'Herbicida', unit: 'L');
    final second = await repo.addProduct(name: 'Fungicida', unit: 'KG');
    final bindings = CentralBindingStore(db);
    final campaign = (await repo.activeCampaign())!['id']! as int;
    // D-F04-C2: la campaña central tiene que contener a «Campaña 1» (desde
    // el 01/01/2026 UTC, día local anterior en La Paz).
    await bindings.bindCampaign(
      campaignId: campaign,
      central: centralCampaign(startDate: '2025-01-01T00:00:00.000Z'),
      tenantId: scope.tenantId,
    );
    await bindings.bindProduct(
      productId: product,
      central: centralProduct(),
      tenantId: scope.tenantId,
    );
    await bindings.bindProduct(
      productId: second,
      central: centralProduct(
        ref: '3a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d',
        unit: 'KG',
      ),
      tenantId: scope.tenantId,
    );
    final needs = DeclaredNeedStore(db);
    final outbox = SyncOutboxStore(db);
    await needs.declare(
      referenceDate: inCampaign,
      productId: product,
      quantityBase: 1000,
    );
    final accepted = await outbox.markSending((await outbox.entries()).single);
    await outbox.recordAccepted(accepted, '2026-10-15T12:00:00.000Z');
    await needs.declare(
      referenceDate: inCampaign,
      productId: second,
      quantityBase: 500,
    );
    await outbox.markSending(
      (await outbox.entries()).firstWhere((e) => e.attempts == 0),
    );
  }

  group('cliente HTTP', () {
    test('lista vacía', () async {
      expect(await _FakeServer().api().list(_token), isEmpty);
    });

    test('la subida envía sólo el binario, su SHA-256 y versiones; ningún Member ni tenant', () async {
      final server = _FakeServer();
      final file = File(p.join(workspace.path, 'x.agrobackup'));
      await file.writeAsBytes(List<int>.generate(5000, (i) => i % 256));
      final digest = _hex(await file.readAsBytes());

      final entry = await server.api().upload(
        file,
        sha256: digest,
        formatVersion: 1,
        schemaVersion: AppDatabase.schemaVersion,
        accessToken: _token,
      );

      expect(entry.sha256, digest);
      expect(entry.sizeBytes, 5000);
      final request = server.requests.single;
      expect(request.method, 'POST');
      expect(request.url.toString(), '$_origin/api/v1/me/backups');
      expect(request.headers['Content-Type'], 'application/octet-stream');
      expect(request.headers['X-Content-SHA256'], digest);
      expect(request.contentLength, 5000);
      for (final header in request.headers.keys) {
        expect(
          header.toLowerCase(),
          isNot(anyOf(contains('member'), contains('tenant'))),
        );
      }
      expect(server.stored.values.single.bytes, await file.readAsBytes());
    });

    test(
      'sólo se da por subida si el servidor confirma el mismo SHA-256',
      () async {
        final server = _FakeServer()..misreportUpload = true;
        final file = File(p.join(workspace.path, 'x.agrobackup'));
        await file.writeAsBytes([1, 2, 3]);
        await expectLater(
          server.api().upload(
            file,
            sha256: _hex([1, 2, 3]),
            formatVersion: 1,
            schemaVersion: 9,
            accessToken: _token,
          ),
          throwsA(
            isA<RemoteBackupException>().having(
              (e) => e.kind,
              'kind',
              RemoteBackupErrorKind.invalidResponse,
            ),
          ),
        );
      },
    );

    test(
      'errores del servidor y de red se tipan sin exponer cuerpos',
      () async {
        Future<RemoteBackupErrorKind> kindFor(int status, String code) async {
          final api = RemoteBackupApi(
            config: ApiEndpointConfig(Uri.parse(_origin)),
            client: MockClient(
              (_) async =>
                  http.Response(jsonEncode({'errorCode': code}), status),
            ),
          );
          try {
            await api.list(_token);
          } on RemoteBackupException catch (error) {
            expect(error.message, isNot(contains(code)));
            return error.kind;
          }
          fail('debía fallar');
        }

        expect(
          await kindFor(401, 'AUTH_REQUIRED'),
          RemoteBackupErrorKind.authRequired,
        );
        expect(
          await kindFor(403, 'AUTH_CONTEXT_FORBIDDEN'),
          RemoteBackupErrorKind.forbidden,
        );
        expect(
          await kindFor(404, 'BACKUP_NOT_FOUND'),
          RemoteBackupErrorKind.notFound,
        );
        expect(
          await kindFor(409, 'BACKUP_QUOTA_EXCEEDED'),
          RemoteBackupErrorKind.quotaExceeded,
        );
        expect(
          await kindFor(413, 'BACKUP_TOO_LARGE'),
          RemoteBackupErrorKind.tooLarge,
        );
        expect(
          await kindFor(422, 'BACKUP_SHA256_MISMATCH'),
          RemoteBackupErrorKind.integrity,
        );
        expect(
          await kindFor(500, 'BACKUP_INTEGRITY_FAILED'),
          RemoteBackupErrorKind.integrity,
        );
        expect(
          await kindFor(503, 'BACKUP_STORAGE_UNAVAILABLE'),
          RemoteBackupErrorKind.unavailable,
        );
        final offline = _FakeServer()..offline = true;
        await expectLater(
          offline.api().list(_token),
          throwsA(
            isA<RemoteBackupException>().having(
              (e) => e.kind,
              'kind',
              RemoteBackupErrorKind.network,
            ),
          ),
        );
      },
    );

    test('las rutas de respaldo admiten sólo ids UUID v4 del servidor', () {
      final config = ApiEndpointConfig(Uri.parse(_origin));
      const id = '01234567-89ab-4cde-8f01-23456789abcd';
      expect(config.endpoint('/api/v1/me/backups').path, '/api/v1/me/backups');
      expect(
        config.endpoint('/api/v1/me/backups/$id').path,
        '/api/v1/me/backups/$id',
      );
      expect(
        config.endpoint('/api/v1/me/backups/$id/content').path,
        '/api/v1/me/backups/$id/content',
      );
      for (final bad in [
        '/api/v1/me/backups/../../auth/v2/me',
        '/api/v1/me/backups/no-es-uuid',
        '/api/v1/me/backups/$id/content/extra',
        '/api/v1/me/backups/${id.toUpperCase()}',
        '/api/v1/me/backups?memberId=x',
      ]) {
        expect(
          () => config.endpoint(bad),
          throwsA(isA<AuthApiException>()),
          reason: bad,
        );
      }
    });

    group('descarga', () {
      late _FakeServer server;
      late RemoteBackupEntry entry;
      late Directory into;
      final bytes = Uint8List.fromList(
        List<int>.generate(9000, (i) => (i * 3) % 256),
      );

      setUp(() async {
        server = _FakeServer();
        final stored = _Stored(
          '00000001-0000-4000-8000-000000000001',
          bytes,
          9,
          DateTime.utc(2026),
        );
        server.stored[stored.id] = stored;
        entry = RemoteBackupEntry.validate(stored.json)!;
        into = Directory(p.join(workspace.path, 'descargas'));
      });

      List<String> left() => into.existsSync()
          ? [for (final e in into.listSync()) p.basename(e.path)]
          : const [];

      test('íntegra: el archivo queda con los bytes exactos', () async {
        final file = await server.api().download(entry, into, _token);
        expect(await file.readAsBytes(), bytes);
        expect(left(), ['${entry.id}.agrobackup']);
      });

      test(
        'bytes alterados con la cabecera correcta: se rechaza y no queda nada',
        () async {
          server.corruptBody = true;
          await expectLater(
            server.api().download(entry, into, _token),
            throwsA(
              isA<RemoteBackupException>().having(
                (e) => e.kind,
                'kind',
                RemoteBackupErrorKind.integrity,
              ),
            ),
          );
          expect(left(), isEmpty);
        },
      );

      test('cabecera SHA-256 distinta de los metadatos: se rechaza', () async {
        server.stored[entry.id]!.declaredSha = 'e' * 64;
        await expectLater(
          server.api().download(entry, into, _token),
          throwsA(
            isA<RemoteBackupException>().having(
              (e) => e.kind,
              'kind',
              RemoteBackupErrorKind.integrity,
            ),
          ),
        );
        expect(left(), isEmpty);
      });

      test('corte a mitad de la descarga: no queda parcial', () async {
        server.truncateBody = true;
        await expectLater(
          server.api().download(entry, into, _token),
          throwsA(
            isA<RemoteBackupException>().having(
              (e) => e.kind,
              'kind',
              RemoteBackupErrorKind.network,
            ),
          ),
        );
        expect(left(), isEmpty);
      });

      test('copia ajena o inexistente: 404 sin archivo', () async {
        server.stored.clear();
        await expectLater(
          server.api().download(entry, into, _token),
          throwsA(
            isA<RemoteBackupException>().having(
              (e) => e.kind,
              'kind',
              RemoteBackupErrorKind.notFound,
            ),
          ),
        );
        expect(left(), isEmpty);
      });
    });

    test('eliminar sólo borra la copia remota', () async {
      final server = _FakeServer();
      final stored = _Stored(
        '00000001-0000-4000-8000-000000000001',
        Uint8List(4),
        9,
        DateTime.utc(2026),
      );
      server.stored[stored.id] = stored;
      final local = File(
        p.join(workspace.path, 'agroquimicos_backup_x.agrobackup'),
      );
      await local.writeAsBytes([9]);
      await server.api().delete(stored.id, _token);
      expect(server.stored, isEmpty);
      expect(local.existsSync(), isTrue);
      await expectLater(
        server.api().delete(stored.id, _token),
        throwsA(
          isA<RemoteBackupException>().having(
            (e) => e.kind,
            'kind',
            RemoteBackupErrorKind.notFound,
          ),
        ),
      );
    });
  });

  group('revisión: cancelación por plazo', _reviewTests);

  group('revisión: acceso y subida incierta', () {
    test('un 401 o 403 descarta el acceso en memoria; un 404 no', () async {
      for (final (status, expected) in [(401, 1), (403, 1)]) {
        final server = _FakeServer()..rejectWith = status;
        final app = await phone(
          'r$status',
          session: memberA,
          installationRef: installationHere,
          seed: (db, invoices) => farmerData(db, invoices),
        );
        var cleared = 0;
        await expectLater(
          app
              .service(server, memberA, onAccessRejected: () => cleared++)
              .list(),
          throwsA(isA<RemoteBackupException>()),
        );
        expect(cleared, expected, reason: '$status');
      }
      final server = _FakeServer();
      final app = await phone(
        'r404',
        session: memberA,
        installationRef: installationHere,
        seed: (db, invoices) => farmerData(db, invoices),
      );
      var cleared = 0;
      final missing = RemoteBackupEntry.validate(
        _Stored(
          '00000009-0000-4000-8000-000000000009',
          Uint8List(4),
          9,
          DateTime.utc(2026),
        ).json,
      )!;
      await expectLater(
        app
            .service(server, memberA, onAccessRejected: () => cleared++)
            .delete(missing),
        throwsA(isA<RemoteBackupException>()),
      );
      expect(cleared, 0);
    });

    test('respuesta de subida perdida: se lista, se reconoce el mismo SHA-256 y no se duplica', () async {
      final server = _FakeServer()..loseUploadResponse = true;
      final a = await phone(
        'a',
        session: memberA,
        installationRef: installationHere,
        seed: (db, invoices) => farmerData(db, invoices),
      );
      final result = await a.service(server, memberA).uploadNew();
      expect(result.confirmedByListing, isTrue);
      expect(server.stored, hasLength(1));
      expect(result.entry.sha256, _hex(server.stored.values.single.bytes));
      expect(server.requests.where((r) => r.method == 'POST'), hasLength(1));
    });

    test('los avisos de la exportación (foto que falta) llegan al resultado de la subida', () async {
      final server = _FakeServer();
      final a = await phone(
        'a',
        session: memberA,
        installationRef: installationHere,
        seed: (db, invoices) => farmerData(db, invoices),
      );
      for (final photo in a.invoices.listSync().whereType<File>()) {
        photo.deleteSync();
      }
      final result = await a.service(server, memberA).uploadNew();
      expect(result.export.warnings, isNotEmpty);
      expect(result.export.warnings.single, contains('fotografía'));
    });

    test('sin red y sin copia en el servidor: el error se informa, no se da por subida', () async {
      final server = _FakeServer()..offline = true;
      final a = await phone(
        'a',
        session: memberA,
        installationRef: installationHere,
        seed: (db, invoices) => farmerData(db, invoices),
      );
      await expectLater(
        a.service(server, memberA).uploadNew(),
        throwsA(
          isA<RemoteBackupException>().having(
            (e) => e.kind,
            'kind',
            RemoteBackupErrorKind.network,
          ),
        ),
      );
    });

    test(
      'una preparación interrumpida no deja restos en la carpeta privada',
      () async {
        final server = _FakeServer();
        final a = await phone(
          'a',
          session: memberA,
          installationRef: installationHere,
          seed: (db, invoices) => farmerData(db, invoices),
        );
        await a.service(server, memberA).uploadNew();
        final privado = Directory(p.join(a.directory.path, 'privado'));
        await privado.create();
        await File(p.join(privado.path, 'resto.agrobackup.part'))
            .writeAsBytes([1]);
        final prepared = await a
            .service(server, memberA)
            .prepareRestore(server.stored.values.single.jsonEntry);
        expect(privado.listSync().map((e) => p.basename(e.path)), [
          p.basename(prepared.file.path),
        ]);
        await a.service(server, memberA).discard(prepared);
        expect(privado.listSync(), isEmpty);
      },
    );
  });

  group('recuperación desde el servidor', () {
    test('teléfono nuevo del mismo Member: recupera datos y fotos; sólo cambian la instalación, la pausa de la cola y las rutas', () async {
      final server = _FakeServer();
      final original = await phone(
        'original',
        session: memberA,
        installationRef: installationHere,
        seed: (db, invoices) => farmerData(db, invoices),
      );
      expect(original.access, InstallationAccessState.activated);
      final before = await original.dump();
      final photosBefore = await original.photos();
      final uploaded = await original.service(server, memberA).uploadNew();
      expect(server.stored, hasLength(1));
      expect(uploaded.entry.sha256, _hex(server.stored.values.single.bytes));
      // El servidor sólo recibió el formato cifrado: ni la base ni el
      // manifiesto en texto legible.
      final served = server.stored.values.single;
      expect(served.formatVersion, 2);
      expect(served.bytes.sublist(0, 7), 'AGROENC'.codeUnits);
      final asText = String.fromCharCodes(served.bytes);
      expect(asText, isNot(contains('SQLite format 3')));
      expect(asText, isNot(contains('manifest.json')));
      expect(asText, isNot(contains('agrocuentas')));
      // Ni copia legible en la carpeta de respaldos locales (`Descargas`).
      expect(
        original.directory.listSync().where(
          (e) => p.basename(e.path).endsWith('.agrobackup'),
        ),
        isEmpty,
      );

      // Instalación limpia: activada para A en otro teléfono, sin datos y sin
      // la clave (llavero vacío, como tras perder el teléfono).
      final fresh = await phone(
        'nuevo',
        session: memberA,
        installationRef: installationElsewhere,
        enrollKey: false,
        seed: (db, _) async {
          await seedActivatedInstallation(
            db,
            installationRef: installationElsewhere,
          );
        },
      );
      final service = fresh.service(server, memberA);
      final listed = await service.list();
      expect(listed.single.id, uploaded.entry.id);

      final freshBefore = await fresh.dump();
      final pending = await service
          .prepareRestore(listed.single)
          .then<PendingDecryption>(
            (_) => fail('sin la clave no se puede preparar'),
            onError: (Object error) => (error as RecoveryKeyRequired).pending,
          );
      // Clave equivocada y clave mal escrita: nada cambia y se puede reintentar.
      await expectLater(
        service.prepareWithRecoveryKey(
          pending,
          BackupRecoveryKey.generate().displayText,
        ),
        throwsA(
          isA<BackupEnvelopeException>().having(
            (e) => e.problem,
            'problem',
            BackupEnvelopeProblem.wrongKey,
          ),
        ),
      );
      final typo = original.recoveryKey!.displayText.split('');
      typo[3] = typo[3] == 'A' ? 'B' : 'A';
      await expectLater(
        service.prepareWithRecoveryKey(pending, typo.join()),
        throwsA(isA<RecoveryKeyFormatException>()),
      );
      expect(await fresh.dump(), freshBefore);
      expect(await fresh.keyring.readiness(), KeyringReadiness.noKey);

      final prepared = await service.prepareWithRecoveryKey(
        pending,
        original.recoveryKey!.displayText.toLowerCase(),
      );
      expect(prepared.ownership.accepted, isTrue);
      expect(prepared.validation.attachmentCount, 1);
      expect(prepared.unencrypted, isFalse);
      final outcome = await service.restorePrepared(prepared);
      // La persona demostró tener la clave: queda en el llavero, activa.
      expect(await fresh.keyring.readiness(), KeyringReadiness.ready);
      expect(
        (await fresh.keyring.activeKey())!.key.sameAs(original.recoveryKey!),
        isTrue,
      );

      expect(outcome.access, InstallationAccessState.activated);
      expect(fresh.access, InstallationAccessState.activated);
      expect(await fresh.photos(), photosBefore);
      expect(
        Directory(p.join(fresh.directory.path, 'privado')).listSync(),
        isEmpty,
        reason: 'la copia descargada se borra tras restaurar',
      );

      final after = await fresh.dump();
      // Datos de negocio: idénticos tabla por tabla, salvo las
      // transformaciones que exige el protocolo.
      const transformed = {'app_settings', 'sync_outbox', 'purchases'};
      expect(
        {
          for (final e in after.entries)
            if (!transformed.contains(e.key)) e.key: e.value,
        },
        {
          for (final e in before.entries)
            if (!transformed.contains(e.key)) e.key: e.value,
        },
      );
      // Compras: sólo la ruta de la fotografía apunta a este teléfono.
      Map<String, Object?> withoutPath(Map<String, Object?> row) =>
          Map.of(row)..remove('invoice_image_path');
      expect(
        after['purchases']!.map(withoutPath),
        before['purchases']!.map(withoutPath),
      );
      final relinked = after['purchases']!
          .map((r) => r['invoice_image_path'])
          .whereType<String>()
          .single;
      expect(p.dirname(relinked), fresh.invoices.path);
      // Cola: ACKED intacta; lo que estaba por enviar, RESTORE_PAUSED con el
      // mismo operationId, cantidad y causalidad.
      Map<String, Object?> core(Map<String, Object?> row) => Map.of(row)
        ..remove('status')
        ..remove('updated_at');
      expect(after['sync_outbox']!.map(core), before['sync_outbox']!.map(core));
      expect(
        [for (final r in after['sync_outbox']!) r['status']],
        [
          for (final r in before['sync_outbox']!)
            r['status'] == 'ACKED' ? 'ACKED' : 'RESTORE_PAUSED',
        ],
      );
      // Ajustes: sólo la instalación activada pasa a ser la de este teléfono.
      final settingsBefore = {
        for (final r in before['app_settings']!) r['key']: r['value'],
      };
      final settingsAfter = {
        for (final r in after['app_settings']!) r['key']: r['value'],
      };
      expect(
        settingsAfter[AppDatabase.activatedInstallationKey],
        installationElsewhere,
      );
      expect(
        Map.of(settingsAfter)..remove(AppDatabase.activatedInstallationKey),
        Map.of(settingsBefore)..remove(AppDatabase.activatedInstallationKey),
      );
      // Y se puede operar sobre los datos recuperados.
      await fresh.container
          .read(repositoryProvider)
          .addProduct(name: 'Tras recuperar');
    });

    test('copia de otro Member: se descarga, se rechaza antes de confirmar y la base no cambia', () async {
      final server = _FakeServer();
      final a = await phone(
        'a',
        session: memberA,
        installationRef: installationHere,
        seed: (db, invoices) => farmerData(db, invoices),
      );
      await a.service(server, memberA).uploadNew();
      // Un servidor que, por error, entregara la copia de A a B, y B con la
      // clave de A: aun así la propiedad la rechaza.
      final b = await phone(
        'b',
        session: memberB,
        installationRef: installationElsewhere,
        recoveryKey: a.recoveryKey,
        seed: (db, _) async {
          await seedActivatedInstallation(
            db,
            scope: memberB,
            installationRef: installationElsewhere,
          );
        },
      );
      final before = await b.dump();
      final service = b.service(server, memberB);
      final prepared = await service.prepareRestore(
        server.stored.values.single.jsonEntry,
      );
      expect(prepared.ownership.accepted, isFalse);
      await expectLater(
        service.restorePrepared(prepared),
        throwsA(isA<BackupOwnershipRejectedException>()),
      );
      expect(await b.dump(), before);
      expect(b.access, InstallationAccessState.activated);
      expect(
        Directory(p.join(b.directory.path, 'privado')).listSync(),
        isEmpty,
      );
    });

    test('otro Member no puede subir los datos privados del titular de esta instalación', () async {
      final server = _FakeServer();
      final a = await phone(
        'a',
        session: memberA,
        installationRef: installationHere,
        seed: (db, invoices) => farmerData(db, invoices),
      );
      await expectLater(
        a.service(server, memberB).uploadNew(),
        throwsA(isA<RemoteBackupOwnerMismatch>()),
      );
      expect(server.requests, isEmpty);
    });

    for (final (name, breakIt, kind)
        in <(String, void Function(_FakeServer), RemoteBackupErrorKind)>[
          (
            'bytes alterados en la descarga',
            (s) => s.corruptBody = true,
            RemoteBackupErrorKind.integrity,
          ),
          // Un corte no es un fallo de integridad de la copia: es la red.
          (
            'corte a mitad de la descarga',
            (s) => s.truncateBody = true,
            RemoteBackupErrorKind.network,
          ),
          (
            'SHA-256 de los metadatos distinto',
            (s) => s.stored.values.single.declaredSha = 'd' * 64,
            RemoteBackupErrorKind.integrity,
          ),
        ]) {
      test('$name: no se restaura y los datos vigentes se conservan', () async {
        final server = _FakeServer();
        final a = await phone(
          'a',
          session: memberA,
          installationRef: installationHere,
          seed: (db, invoices) => farmerData(db, invoices),
        );
        await a.service(server, memberA).uploadNew();
        await a.container
            .read(repositoryProvider)
            .addProduct(name: 'Posterior al respaldo');
        final before = await a.dump();
        final photos = await a.photos();
        breakIt(server);
        final entry = server.stored.values.single.jsonEntry;

        await expectLater(
          a.service(server, memberA).prepareRestore(entry),
          throwsA(
            isA<RemoteBackupException>().having((e) => e.kind, 'kind', kind),
          ),
        );
        expect(await a.dump(), before);
        expect(await a.photos(), photos);
        expect(a.access, InstallationAccessState.activated);
        final privado = Directory(p.join(a.directory.path, 'privado'));
        expect(privado.existsSync() ? privado.listSync() : const [], isEmpty);
      });
    }

    test('contenedor alterado por dentro con hash exterior coherente: la validación interna lo rechaza', () async {
      final server = _FakeServer();
      final a = await phone(
        'a',
        session: memberA,
        installationRef: installationHere,
        seed: (db, invoices) => farmerData(db, invoices),
      );
      await a.service(server, memberA).uploadNew();
      final before = await a.dump();
      // Se altera la base de dentro del contenedor y el servidor publica el
      // SHA-256 del contenedor alterado (p. ej. una copia reemplazada).
      // Se descifra con la clave del titular, se altera la base de dentro y se
      // vuelve a cifrar con la misma clave: el cifrado no lo detecta, la
      // validación interna sí.
      final stored = server.stored.values.single;
      final envelope = File(p.join(workspace.path, 'alterado.agroenc'));
      await envelope.writeAsBytes(stored.bytes);
      final tampered = File(p.join(workspace.path, 'alterado.agrobackup'));
      await const BackupEncryption().decryptFile(
        envelope,
        tampered,
        keyFor: (_) async => a.recoveryKey,
        maxPlaintextBytes: 1 << 28,
      );
      final inner = await extractDatabaseFrom(tampered.path);
      final raw = await databaseFactoryFfi.openDatabase(inner);
      await raw.update('persons', {'name': 'Otra persona'}, where: 'id=1');
      await raw.close();
      await rewriteEntry(
        tampered.path,
        'database.db',
        await File(inner).readAsBytes(),
      );
      await const BackupEncryption().encryptFile(
        tampered,
        envelope,
        a.recoveryKey!,
      );
      final replaced = _Stored(
        stored.id,
        await envelope.readAsBytes(),
        stored.schemaVersion,
        stored.createdAt,
      );
      server.stored[stored.id] = replaced;

      await expectLater(
        a.service(server, memberA).prepareRestore(replaced.jsonEntry),
        throwsA(
          isA<BackupException>().having(
            (e) => e.message,
            'message',
            contains('no coincide'),
          ),
        ),
      );
      expect(await a.dump(), before);
    });

    test('la cola restaurada queda pausada antes de que nadie vea la base, y no se envía al abrir la app', () async {
      final server = _FakeServer();
      final remote = _FakeRemote(memberA);
      final source = await phone(
        'origen',
        session: memberA,
        installationRef: installationHere,
        seed: (db, invoices) => farmerData(db, invoices),
      );
      await source.service(server, memberA).uploadNew();
      final target = await phone(
        'destino',
        session: memberA,
        installationRef: installationElsewhere,
        remote: remote,
        recoveryKey: source.recoveryKey,
        seed: (db, _) => seedActivatedInstallation(
          db,
          installationRef: installationElsewhere,
        ),
      );
      final prepared = await target
          .service(server, memberA)
          .prepareRestore(server.stored.values.single.jsonEntry);
      List<String>? statusesInside;
      await target.container
          .read(guardedRestoreProvider)
          .restore(
            prepared.file.path,
            afterReplace: () async {
              statusesInside = [
                for (final e in await SyncOutboxStore(
                  target.database,
                ).entries())
                  e.status.code,
              ];
            },
          );
      expect(statusesInside, unorderedEquals(['ACKED', 'RESTORE_PAUSED']));

      // Abrir la app con acceso verificado: el ciclo automático no envía nada
      // de lo restaurado (ninguna petición Sync).
      target.container
          .read(syncAccessHolderProvider)
          .accept(_token, memberA.memberId, memberA.tenantId);
      final worker = target.container.read(syncWorkerProvider);
      expect((await worker.run()).sent, 0);
      expect(target.syncRequests, isEmpty);
      final statuses = [
        for (final e in await SyncOutboxStore(target.database).entries())
          e.status,
      ];
      expect(
        statuses,
        unorderedEquals([OutboxStatus.acked, OutboxStatus.restorePaused]),
      );

      // Control: sólo tras la liberación explícita del titular se reenvía la
      // misma intención (mismo operationId), una vez.
      final binding = await OwnerBindingStore(target.database).activeBinding();
      final paused = (await SyncOutboxStore(
        target.database,
      ).entries()).singleWhere((e) => e.status == OutboxStatus.restorePaused);
      expect(
        await SyncOutboxStore(target.database).releaseRestored(binding!.id),
        1,
      );
      expect((await worker.run()).sent, 1);
      expect(target.syncRequests, hasLength(1));
      expect(
        (jsonDecode(target.syncRequests.single.body) as Map)['operationId'],
        paused.operationId,
      );
    });

    test(
      'liberar lo restaurado exige verificar en línea la cuenta del titular',
      () async {
        final denied = _FakeRemote(null);
        final app = await phone(
          'a',
          session: memberA,
          installationRef: installationHere,
          remote: denied,
          seed: (db, invoices) async {
            await farmerData(db, invoices);
            await SyncOutboxStore.pauseAfterRestore(
              await db.database,
              '2026-10-16T00:00:00.000Z',
            );
          },
        );
        final controller = app.container.read(syncControllerProvider.notifier);
        expect(await controller.releaseRestored(), 0);
        expect(denied.calls, 1);
        expect([
          for (final e in await SyncOutboxStore(app.database).entries())
            e.status,
        ], unorderedEquals([OutboxStatus.acked, OutboxStatus.restorePaused]));

        // Verificada otra cuenta: tampoco.
        final other = await phone(
          'b',
          session: memberA,
          installationRef: installationHere,
          remote: _FakeRemote(memberB),
          seed: (db, invoices) async {
            await farmerData(db, invoices);
            await SyncOutboxStore.pauseAfterRestore(
              await db.database,
              '2026-10-16T00:00:00.000Z',
            );
          },
        );
        expect(
          await other.container
              .read(syncControllerProvider.notifier)
              .releaseRestored(),
          0,
        );

        // Verificada la del titular: se libera con el mismo contenido.
        final owner = await phone(
          'c',
          session: memberA,
          installationRef: installationHere,
          remote: _FakeRemote(memberA),
          seed: (db, invoices) async {
            await farmerData(db, invoices);
            await SyncOutboxStore.pauseAfterRestore(
              await db.database,
              '2026-10-16T00:00:00.000Z',
            );
          },
        );
        expect(
          await owner.container
              .read(syncControllerProvider.notifier)
              .releaseRestored(),
          1,
        );
        // La liberación lanza un ciclo de envío: se espera a que termine y se
        // comprueba que reenvía la intención liberada.
        while (owner.container.read(syncControllerProvider).busy ||
            owner.syncRequests.isEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        while (owner.container.read(syncControllerProvider).busy) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(owner.syncRequests, hasLength(1));
      },
    );
  });
}

/// Transporte que nunca responde: sólo termina si se cancela la petición.
class _HangingClient extends http.BaseClient {
  bool aborted = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request case http.Abortable(:final abortTrigger?)) {
      await abortTrigger;
      aborted = true;
      throw http.RequestAbortedException(request.url);
    }
    return Completer<http.StreamedResponse>().future;
  }
}

/// Sirve [bytes] en 10 bloques, uno cada [every]; con [stallAfter] deja de
/// enviar tras ese número de bloques. Atiende la cancelación de la petición.
class _SlowClient extends http.BaseClient {
  _SlowClient(this.bytes, {required this.every, this.stallAfter});
  final List<int> bytes;
  final Duration every;
  final int? stallAfter;
  bool aborted = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final controller = StreamController<List<int>>();
    if (request case http.Abortable(:final abortTrigger?)) {
      unawaited(
        abortTrigger.then((_) {
          aborted = true;
          if (!controller.isClosed) {
            controller.addError(http.RequestAbortedException(request.url));
            controller.close();
          }
        }),
      );
    }
    final size = (bytes.length / 10).ceil();
    unawaited(() async {
      for (var i = 0; i * size < bytes.length; i++) {
        if (stallAfter != null && i >= stallAfter!) return;
        await Future<void>.delayed(every);
        if (controller.isClosed) return;
        final end = (i + 1) * size > bytes.length
            ? bytes.length
            : (i + 1) * size;
        controller.add(bytes.sublist(i * size, end));
      }
      if (!controller.isClosed) await controller.close();
    }());
    return http.StreamedResponse(
      controller.stream,
      200,
      contentLength: bytes.length,
      headers: {'x-content-sha256': _hex(bytes)},
    );
  }
}

void _reviewTests() {
  late Directory workspace;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('agro_f08_review_');
    PathProviderPlatform.instance = _WorkspacePaths(workspace.path);
  });
  tearDown(() async {
    try {
      await workspace.delete(recursive: true);
    } on FileSystemException {
      // Temporal.
    }
  });

  RemoteBackupEntry entryFor(List<int> bytes) => RemoteBackupEntry.validate(
    _Stored(
      '00000001-0000-4000-8000-000000000001',
      Uint8List.fromList(bytes),
      9,
      DateTime.utc(2026),
    ).json,
  )!;

  test('una descarga lenta pero continua termina aunque dure más que el plazo de inactividad', () async {
    final bytes = List<int>.generate(10 * 1024, (i) => i % 256);
    final api = RemoteBackupApi(
      config: ApiEndpointConfig(Uri.parse(_origin)),
      client: _SlowClient(bytes, every: const Duration(milliseconds: 60)),
      timeout: const Duration(milliseconds: 150),
      idleTimeout: const Duration(milliseconds: 150),
      // Tope: 150 ms + 10 KiB a 8 KiB/s ≈ 1,4 s, por encima de los ~600 ms.
      minDownloadBytesPerSecond: 8 * 1024,
    );
    final watch = Stopwatch()..start();
    final file = await api.download(
      entryFor(bytes),
      Directory(p.join(workspace.path, 'lenta')),
      _token,
    );
    expect(watch.elapsed, greaterThan(const Duration(milliseconds: 300)));
    expect(await file.readAsBytes(), bytes);
  });

  test('una descarga que progresa pero supera el tope proporcional al tamaño se aborta', () async {
    final bytes = List<int>.generate(10 * 1024, (i) => i % 256);
    final client = _SlowClient(bytes, every: const Duration(milliseconds: 60));
    final api = RemoteBackupApi(
      config: ApiEndpointConfig(Uri.parse(_origin)),
      client: client,
      timeout: const Duration(milliseconds: 100),
      idleTimeout: const Duration(seconds: 5),
      // 10 KiB a 100 KiB/s = 100 ms: tope 200 ms frente a ~600 ms de envío.
      minDownloadBytesPerSecond: 100 * 1024,
    );
    final into = Directory(p.join(workspace.path, 'tope'));
    await expectLater(
      api.download(entryFor(bytes), into, _token),
      throwsA(
        isA<RemoteBackupException>().having(
          (e) => e.kind,
          'kind',
          RemoteBackupErrorKind.network,
        ),
      ),
    );
    expect(client.aborted, isTrue);
    expect(into.listSync(), isEmpty);
  });

  test('una descarga detenida se aborta por inactividad: error de red y sin archivo', () async {
    final bytes = List<int>.generate(10 * 1024, (i) => i % 256);
    final client = _SlowClient(
      bytes,
      every: const Duration(milliseconds: 20),
      stallAfter: 3,
    );
    final api = RemoteBackupApi(
      config: ApiEndpointConfig(Uri.parse(_origin)),
      client: client,
      idleTimeout: const Duration(milliseconds: 150),
    );
    final into = Directory(p.join(workspace.path, 'detenida'));
    await expectLater(
      api.download(entryFor(bytes), into, _token),
      throwsA(
        isA<RemoteBackupException>().having(
          (e) => e.kind,
          'kind',
          RemoteBackupErrorKind.network,
        ),
      ),
    );
    expect(client.aborted, isTrue);
    expect(into.listSync(), isEmpty);
  });

  test('al vencer el plazo la subida se cancela de verdad, no sólo se deja de esperar', () async {
    final hanging = _HangingClient();
    final api = RemoteBackupApi(
      config: ApiEndpointConfig(Uri.parse(_origin)),
      client: hanging,
      timeout: const Duration(milliseconds: 100),
    );
    final file = File(p.join(workspace.path, 'x.agrobackup'));
    await file.writeAsBytes(List<int>.filled(1000, 1));
    await expectLater(
      api.upload(
        file,
        sha256: 'a' * 64,
        formatVersion: 1,
        schemaVersion: 9,
        accessToken: _token,
      ),
      throwsA(
        isA<RemoteBackupException>().having(
          (e) => e.kind,
          'kind',
          RemoteBackupErrorKind.network,
        ),
      ),
    );
    expect(hanging.aborted, isTrue);
  });
}

extension on _Stored {
  // `this.`: sin él, `json` sería el códec de dart:convert.
  RemoteBackupEntry get jsonEntry => RemoteBackupEntry.validate(this.json)!;
}
