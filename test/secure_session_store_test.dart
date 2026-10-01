import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/backup_service.dart';
import 'package:agroquimicos/data/installation_client_id_store.dart';
import 'package:agroquimicos/services/auth/first_activation_coordinator.dart';
import 'package:agroquimicos/services/auth/secure_session_store.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
// Transitive path_provider interface is used only to redirect a test export.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _id = '550e8400-e29b-41d4-a716-446655440000';
const _otherId = '550e8400-e29b-41d4-a716-446655440099';
const _refresh = 'test-only-refresh-secret';

SessionCommitCandidate _candidate({String refresh = _refresh}) =>
    SessionCommitCandidate(
      refreshToken: refresh,
      installationClientId: _id,
      registrationId: 'registration-1',
      accountId: 'account-1',
      memberId: 'member-1',
      tenantId: 'tenant-1',
      sessionId: 'session-1',
      expiresAt: DateTime.utc(2026, 10, 5),
    );

class _Identity extends InstallationClientIdStore {
  _Identity(this.value);
  String? value;

  @override
  Future<String?> read() async => value;
}

class _Slots implements EncryptedSessionSlots {
  final values = <String, String>{};
  bool failWrite = false;
  bool failRead = false;
  bool failDelete = false;
  bool corruptRead = false;
  Completer<void>? pendingWrite;
  Completer<void>? startedWrite;

  @override
  Future<void> write(String slot, String value) async {
    values[slot] = value; // Simulates apply() visible in memory.
    startedWrite?.complete();
    if (pendingWrite != null) await pendingWrite!.future;
    if (failWrite) throw StateError('$_refresh must stay private');
  }

  @override
  Future<String?> read(String slot) async {
    if (failRead) throw StateError(_refresh);
    if (corruptRead) return 'not-json';
    return values[slot];
  }

  @override
  Future<void> delete(String slot) async {
    if (failDelete) throw StateError(_refresh);
    values.remove(slot);
  }
}

class _Pointer implements DurableSessionPointer {
  String? active;
  bool failActivate = false;
  bool activateThenLoseAck = false;
  bool failClear = false;
  bool clearThenLoseAck = false;
  bool failFlush = false;
  int activations = 0;

  @override
  Future<String?> read() async => active;

  @override
  Future<void> activate({
    required String? expected,
    required String next,
  }) async {
    activations++;
    if (active != expected) throw StateError('Stale pointer');
    if (failActivate) throw StateError(_refresh);
    active = next;
    if (activateThenLoseAck) throw StateError(_refresh);
  }

  @override
  Future<void> clear({required String expected}) async {
    if (active != expected) throw StateError('Stale pointer');
    if (failClear) throw StateError(_refresh);
    active = null;
    if (clearThenLoseAck) throw StateError(_refresh);
  }

  @override
  Future<void> flushEncryptedDeletes() async {
    if (failFlush) throw StateError(_refresh);
  }
}

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.root);
  final String root;

  @override
  Future<String?> getDownloadsPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

SecureSessionStore _store(_Slots slots, _Pointer pointer, _Identity identity) =>
    SecureSessionStore(
      slots: slots,
      pointer: pointer,
      identityStore: identity,
      clock: () => DateTime.utc(2026, 9, 29),
    );

Future<void> _expectFailure(
  Future<void> operation,
  SecureSessionFailure reason,
) => expectLater(
  operation,
  throwsA(
    isA<SecureSessionStorageException>().having(
      (error) => error.reason,
      'reason',
      reason,
    ),
  ),
);

void main() {
  sqfliteFfiInit();
  test(
    'commit verifies one encrypted record and reads matching metadata',
    () async {
      final slots = _Slots();
      final pointer = _Pointer();
      final store = _store(slots, pointer, _Identity(_id));
      await store.commitAndVerify(_candidate());
      final result = await store.read();
      expect(result.status, SessionReadStatus.available);
      expect(result.session!.refreshToken, _refresh);
      expect(result.session!.registrationId, 'registration-1');
      expect(result.session!.sessionId, 'session-1');
      expect(result.expiredLocally, isFalse);
      expect(pointer.active, 'a');
      expect(slots.values.keys, ['a']);
      expect(jsonDecode(slots.values['a']!)['version'], 1);
      expect(result.toString(), isNot(contains(_refresh)));
      expect(result.session.toString(), isNot(contains(_refresh)));
    },
  );

  test(
    'no pointer means no usable session even with orphan ciphertext',
    () async {
      final slots = _Slots()..values['a'] = 'orphan';
      expect(
        (await _store(slots, _Pointer(), _Identity(_id)).read()).status,
        SessionReadStatus.absent,
      );
    },
  );

  test(
    'corrupt, missing and version-incompatible active records differ',
    () async {
      final slots = _Slots()..values['a'] = 'not-json';
      final pointer = _Pointer()..active = 'a';
      final store = _store(slots, pointer, _Identity(_id));
      expect((await store.read()).status, SessionReadStatus.corrupt);
      slots.values.remove('a');
      expect((await store.read()).status, SessionReadStatus.corrupt);
      slots.values['a'] = jsonEncode({'version': 2});
      expect((await store.read()).status, SessionReadStatus.incompatible);
      slots.failRead = true;
      expect((await store.read()).status, SessionReadStatus.unavailable);
    },
  );

  test('write failure leaves a previous active session intact', () async {
    final slots = _Slots();
    final pointer = _Pointer();
    final store = _store(slots, pointer, _Identity(_id));
    await store.commitAndVerify(_candidate(refresh: 'old-secret'));
    slots.failWrite = true;
    await _expectFailure(
      store.commitAndVerify(_candidate(refresh: 'new-secret')),
      SecureSessionFailure.writeFailed,
    );
    expect(pointer.active, 'a');
    expect((await store.read()).session!.refreshToken, 'old-secret');
    expect(pointer.activations, 1);
  });

  test('readback failure during staging cannot activate new record', () async {
    final slots = _Slots()..failRead = true;
    final pointer = _Pointer();
    final store = _store(slots, pointer, _Identity(_id));
    await _expectFailure(
      store.commitAndVerify(_candidate()),
      SecureSessionFailure.writeFailed,
    );
    expect(pointer.active, isNull);
    expect(pointer.activations, 0);
  });

  test('simulated interruption after staged apply leaves old active', () async {
    final slots = _Slots();
    final pointer = _Pointer();
    final identity = _Identity(_id);
    final store = _store(slots, pointer, identity);
    await store.commitAndVerify(_candidate(refresh: 'old-secret'));
    slots.failWrite = true;
    await _expectFailure(
      store.commitAndVerify(_candidate(refresh: 'new-secret')),
      SecureSessionFailure.writeFailed,
    );
    final reopened = _store(slots, pointer, identity);
    expect((await reopened.read()).session!.refreshToken, 'old-secret');
  });

  test(
    'lost activation acknowledgement is uncertain, never a false success',
    () async {
      final slots = _Slots();
      final pointer = _Pointer()..activateThenLoseAck = true;
      final store = _store(slots, pointer, _Identity(_id));
      await _expectFailure(
        store.commitAndVerify(_candidate()),
        SecureSessionFailure.commitUncertain,
      );
      expect(pointer.active, 'a');
    },
  );

  test('pointer failure does not delete previous session', () async {
    final slots = _Slots();
    final pointer = _Pointer();
    final store = _store(slots, pointer, _Identity(_id));
    await store.commitAndVerify(_candidate(refresh: 'old-secret'));
    pointer.failActivate = true;
    await _expectFailure(
      store.commitAndVerify(_candidate(refresh: 'new-secret')),
      SecureSessionFailure.commitUncertain,
    );
    expect((await store.read()).session!.refreshToken, 'old-secret');
  });

  test(
    'concurrent commits serialize; each uses the then-inactive slot',
    () async {
      final slots = _Slots();
      final pointer = _Pointer();
      final identity = _Identity(_id);
      final one = _store(slots, pointer, identity);
      final two = _store(slots, pointer, identity);
      final first = one.commitAndVerify(_candidate(refresh: 'first'));
      final second = two.commitAndVerify(_candidate(refresh: 'second'));
      await Future.wait([first, second]);
      expect(pointer.activations, 2);
      expect(pointer.active, 'b');
      expect((await one.read()).session!.refreshToken, 'second');
    },
  );

  test(
    'deletion clears pointer before deleting both ciphertext slots',
    () async {
      final slots = _Slots();
      final pointer = _Pointer();
      final store = _store(slots, pointer, _Identity(_id));
      await store.commitAndVerify(_candidate());
      await store.delete();
      expect((await store.read()).status, SessionReadStatus.absent);
      expect(slots.values, isEmpty);
    },
  );

  test(
    'delete failure is explicit; pointer remains absent if cleanup fails',
    () async {
      final slots = _Slots();
      final pointer = _Pointer();
      final store = _store(slots, pointer, _Identity(_id));
      await store.commitAndVerify(_candidate());
      slots.failDelete = true;
      await _expectFailure(store.delete(), SecureSessionFailure.deletionFailed);
      expect((await store.read()).status, SessionReadStatus.absent);
      slots.failDelete = false;
      await store.delete(); // Retriable orphan cleanup.
      expect(slots.values, isEmpty);
    },
  );

  test('pointer clear failure preserves session', () async {
    final slots = _Slots();
    final pointer = _Pointer();
    final store = _store(slots, pointer, _Identity(_id));
    await store.commitAndVerify(_candidate());
    pointer.failClear = true;
    await _expectFailure(
      store.delete(),
      SecureSessionFailure.deletionUncertain,
    );
    expect((await store.read()).status, SessionReadStatus.available);
  });

  test('lost clear acknowledgement never deletes ciphertext', () async {
    final slots = _Slots();
    final pointer = _Pointer();
    final store = _store(slots, pointer, _Identity(_id));
    await store.commitAndVerify(_candidate());
    pointer.clearThenLoseAck = true;
    await _expectFailure(
      store.delete(),
      SecureSessionFailure.deletionUncertain,
    );
    expect(slots.values, isNotEmpty);
  });

  test(
    'expired local metadata is reported, not mistaken for remote revocation',
    () async {
      final slots = _Slots();
      final pointer = _Pointer();
      final store = _store(slots, pointer, _Identity(_id));
      await store.commitAndVerify(_candidate());
      final later = SecureSessionStore(
        slots: slots,
        pointer: pointer,
        identityStore: _Identity(_id),
        clock: () => DateTime.utc(2026, 10, 6),
      );
      final result = await later.read();
      expect(result.status, SessionReadStatus.available);
      expect(result.expiredLocally, isTrue);
    },
  );

  test('cross-install identity mismatch never returns a credential', () async {
    final slots = _Slots();
    final pointer = _Pointer();
    await _store(slots, pointer, _Identity(_id)).commitAndVerify(_candidate());
    final other = _store(slots, pointer, _Identity(_otherId));
    expect((await other.read()).status, SessionReadStatus.corrupt);
    await _expectFailure(
      other.commitAndVerify(_candidate(refresh: 'replacement')),
      SecureSessionFailure.invalidCandidate,
    );
  });

  test(
    'invalid candidate and errors never expose token or internal path',
    () async {
      final slots = _Slots();
      final pointer = _Pointer();
      final store = _store(slots, pointer, _Identity(_id));
      final bad = SessionCommitCandidate(
        refreshToken: '',
        installationClientId: _id,
        registrationId: 'r',
        accountId: 'a',
        memberId: 'm',
        tenantId: 't',
        sessionId: 's',
        expiresAt: DateTime.utc(2026, 10, 5),
      );
      await _expectFailure(
        store.commitAndVerify(bad),
        SecureSessionFailure.invalidCandidate,
      );
      slots.failWrite = true;
      try {
        await store.commitAndVerify(_candidate());
        fail('Expected write failure');
      } on SecureSessionStorageException catch (error) {
        expect(error.toString(), isNot(contains(_refresh)));
        expect(error.toString(), isNot(contains('path')));
      }
      expect(_candidate().toString(), isNot(contains(_refresh)));
    },
  );

  test(
    'Android backup XML excludes exactly the secure-session files',
    () async {
      final oldRules = await File(
        'android/app/src/main/res/xml/backup_rules.xml',
      ).readAsString();
      final newRules = await File(
        'android/app/src/main/res/xml/data_extraction_rules.xml',
      ).readAsString();
      for (final name in [
        'agrocuentas_secure_session_v1.xml',
        'FlutterSecureKeyStorage:agrocuentas_secure_session_v1.xml',
        'FlutterSecureStorageConfiguration:agrocuentas_secure_session_v1.xml',
        'AgrocuentasSessionPointer.xml',
      ]) {
        expect(oldRules, contains(name));
        expect('path="$name"'.allMatches(newRules), hasLength(2));
      }
      expect(oldRules, isNot(contains('allowBackup="false"')));
      expect(newRules, contains('<cloud-backup>'));
      expect(newRules, contains('<device-transfer>'));
    },
  );

  test(
    'individual SQLite and exported .agrobackup omit session material',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'f03_secure_backup_',
      );
      final priorPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _TestPaths(directory.path);
      addTearDown(() async {
        PathProviderPlatform.instance = priorPaths;
        try {
          await directory.delete(recursive: true);
        } on FileSystemException {
          // SQLite can retain a temporary handle on Windows.
        }
      });
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        path: p.join(directory.path, 'individual.db'),
      );
      addTearDown(database.close);
      final store = _store(_Slots(), _Pointer(), _Identity(_id));
      await store.commitAndVerify(_candidate());
      await database.database;
      final exported = await BackupService(database).export();
      final bytes = await File(exported.path).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      expect(archive.files.map((entry) => entry.name), contains('database.db'));
      expect(
        archive.files.map((entry) => entry.name).join(' '),
        isNot(contains('session')),
      );
      expect(
        utf8.decode(bytes, allowMalformed: true),
        isNot(contains(_refresh)),
      );
      expect(
        utf8.decode(
          await File(database.openedPath!).readAsBytes(),
          allowMalformed: true,
        ),
        isNot(contains(_refresh)),
      );
    },
  );

  test(
    'real Flutter adapter sends the isolated namespace and reset policy',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'read') return null;
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      final adapter = AndroidEncryptedSessionSlots();
      await adapter.write('a', 'test-record');
      await adapter.read('a');
      expect(calls.map((call) => call.method), ['write', 'read']);
      final arguments = calls.first.arguments as Map<Object?, Object?>;
      final options = arguments['options'] as Map<Object?, Object?>;
      expect(options['storageNamespace'], SecureSessionStore.androidNamespace);
      expect(options['resetOnError'], 'false');
      expect(options['migrateOnAlgorithmChange'], 'false');
    },
  );
}
