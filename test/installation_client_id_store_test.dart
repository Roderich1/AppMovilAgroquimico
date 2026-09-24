import 'dart:convert';
import 'dart:io';

import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/backup_service.dart';
import 'package:agroquimicos/data/installation_client_id_store.dart';
import 'package:agroquimicos/data/installation_identity_initializer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
// Dependencia transitiva ya usada por la suite para sustituir path_provider.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'backup_container_support.dart';

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

void main() {
  sqfliteFfiInit();

  late Directory workspace;
  late Directory noBackupDirectory;
  late int generation;
  late InstallationClientIdStore store;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('agro_client_id_');
    noBackupDirectory = Directory(p.join(workspace.path, 'android_no_backup'));
    generation = 0;
    store = InstallationClientIdStore(
      directoryProvider: () async => noBackupDirectory,
      secureBytes: (length) => List<int>.generate(
        length,
        (index) => (index + generation * 31) & 0xff,
      ),
    );
    PathProviderPlatform.instance = _WorkspacePathProvider(workspace.path);
  });

  tearDown(() async {
    try {
      await workspace.delete(recursive: true);
    } on FileSystemException {
      // SQLite puede retener temporalmente archivos en Windows.
    }
  });

  test('first getOrCreate creates a canonical UUID v4', () async {
    final clientId = await store.getOrCreate();

    expect(InstallationClientIdStore.isCanonicalUuidV4(clientId), isTrue);
    expect(clientId.split('-')[2].startsWith('4'), isTrue);
    expect('89ab'.contains(clientId.split('-')[3][0]), isTrue);
  });

  test('initialization creates a missing identity and reports READY', () async {
    final result = await initializeInstallationIdentity(store: store);

    expect(result.status, InstallationIdentityStatus.ready);
    expect(
      InstallationClientIdStore.isCanonicalUuidV4((await store.read())!),
      isTrue,
    );
  });

  test('initialization reads a valid identity and reports READY', () async {
    final clientId = await store.getOrCreate();
    final reopened = InstallationClientIdStore(
      directoryProvider: () async => noBackupDirectory,
      secureBytes: (_) => List<int>.filled(16, 255),
    );

    final result = await initializeInstallationIdentity(store: reopened);

    expect(result.status, InstallationIdentityStatus.ready);
    expect(await reopened.read(), clientId);
  });

  test('getOrCreate and a reopened store preserve the same identity', () async {
    final first = await store.getOrCreate();
    final second = await store.getOrCreate();
    final reopened = InstallationClientIdStore(
      directoryProvider: () async => noBackupDirectory,
      secureBytes: (_) => List<int>.filled(16, 255),
    );

    expect(second, first);
    expect(await reopened.getOrCreate(), first);
  });

  test('explicit rotation writes a different valid UUID', () async {
    final first = await store.getOrCreate();
    generation = 1;
    final rotated = await store.rotate();

    expect(rotated, isNot(first));
    expect(InstallationClientIdStore.isCanonicalUuidV4(rotated), isTrue);
    expect(await store.read(), rotated);
  });

  test(
    'a corrupt file fails explicitly and is not silently replaced',
    () async {
      await noBackupDirectory.create(recursive: true);
      final file = File(
        p.join(noBackupDirectory.path, InstallationClientIdStore.fileName),
      );
      await file.writeAsString('android-id-from-hardware');

      await expectLater(
        store.getOrCreate(),
        throwsA(isA<InstallationClientIdCorruptException>()),
      );
      expect(await file.readAsString(), 'android-id-from-hardware');
    },
  );

  test(
    'corrupt identity is preserved and initialization reports CORRUPT',
    () async {
      await noBackupDirectory.create(recursive: true);
      final file = File(
        p.join(noBackupDirectory.path, InstallationClientIdStore.fileName),
      );
      const corruptContents = 'android-id-from-hardware';
      await file.writeAsString(corruptContents);
      final diagnostics = <String>[];

      final result = await initializeInstallationIdentity(
        store: store,
        diagnostic: diagnostics.add,
      );

      expect(result.status, InstallationIdentityStatus.corrupt);
      expect(await file.readAsString(), corruptContents);
      expect(diagnostics, hasLength(1));
      expect(diagnostics.single, isNot(contains(corruptContents)));
      expect(diagnostics.single, isNot(contains(file.path)));
    },
  );

  test('identity failure does not block application bootstrap', () async {
    var continued = false;
    final unavailableStore = InstallationClientIdStore(
      directoryProvider: () async =>
          throw const FileSystemException('storage unavailable'),
    );

    final result = await bootstrapWithInstallationIdentity(
      store: unavailableStore,
      diagnostic: (_) {},
      continueStartup: () => continued = true,
    );

    expect(result.status, InstallationIdentityStatus.unavailable);
    expect(continued, isTrue);
  });

  test('failed rotation preserves the previous valid identity', () async {
    final original = await store.getOrCreate();
    final failingStore = InstallationClientIdStore(
      directoryProvider: () async => noBackupDirectory,
      secureBytes: (_) => List<int>.filled(16, 128),
      fileReplacer: (_, _) async {
        throw const FileSystemException('simulated replace failure');
      },
    );

    await expectLater(
      failingStore.rotate(),
      throwsA(isA<FileSystemException>()),
    );

    expect(await store.read(), original);
    final names = await noBackupDirectory
        .list()
        .map((entity) => p.basename(entity.path))
        .toList();
    expect(names.where((name) => name.contains('.tmp-')), isEmpty);
  });

  test(
    'Agrocuentas backup and restore never include or replace clientId',
    () async {
      final clientId = await store.getOrCreate();
      final leftoverTemporary = File(
        p.join(
          noBackupDirectory.path,
          '${InstallationClientIdStore.fileName}.tmp-leftover',
        ),
      );
      await leftoverTemporary.writeAsString('temporary-data');
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        path: p.join(workspace.path, 'domain.db'),
      );
      addTearDown(database.close);
      await database.database;
      final invoices = Directory(p.join(workspace.path, 'invoices'));
      await invoices.create();
      final service = BackupService(
        database,
        invoicesDir: () async => invoices,
      );

      final backup = await service.export();
      final entries = entriesOf(backup.path);
      final manifest = utf8.decode(entryBytes(backup.path, 'manifest.json')!);
      final tables = await (await database.database).rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );

      expect(entries, isNot(contains(InstallationClientIdStore.fileName)));
      expect(
        entries.any(
          (entry) =>
              entry.contains('${InstallationClientIdStore.fileName}.tmp'),
        ),
        isFalse,
      );
      expect(manifest, isNot(contains(clientId)));
      expect(
        tables.map((row) => row['name']),
        isNot(contains('client_registration')),
      );

      await service.restore(backup.path);
      expect(await store.read(), clientId);
    },
  );

  test(
    'Android bridge uses noBackupFilesDir and no hardware identifier',
    () async {
      final kotlin = await File(
        p.join(
          Directory.current.path,
          'android',
          'app',
          'src',
          'main',
          'kotlin',
          'com',
          'comunidad',
          'agro',
          'agroquimicos',
          'MainActivity.kt',
        ),
      ).readAsString();

      expect(kotlin, contains('noBackupFilesDir.absolutePath'));
      expect(kotlin, isNot(contains('ANDROID_ID')));
      expect(kotlin, isNot(contains('getImei')));
      expect(kotlin, isNot(contains('getSerial')));
      expect(kotlin, isNot(contains('getMacAddress')));
    },
  );
}
