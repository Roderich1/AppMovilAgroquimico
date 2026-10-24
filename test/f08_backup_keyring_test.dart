// F08-ADR-003 §3: llavero local de claves de recuperación. Claves efímeras;
// ninguna se imprime.
import 'dart:io';

import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/backup_encryption.dart';
import 'package:agroquimicos/services/backup/backup_keyring.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _MemoryVault implements BackupKeyVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
}

class _ThrowingVault implements BackupKeyVault {
  @override
  Future<String?> read() async => throw StateError('Keystore invalidado');
  @override
  Future<void> write(String value) async => throw StateError('no');
}

void main() {
  late _MemoryVault vault;
  late BackupKeyring keyring;

  setUp(() {
    vault = _MemoryVault();
    keyring = BackupKeyring(vault);
  });

  test('sin clave → mostrada sin confirmar → confirmada', () async {
    expect(await keyring.readiness(), KeyringReadiness.noKey);
    expect(await keyring.activeKey(), isNull);
    final key = await keyring.pendingKey();
    expect(await keyring.readiness(), KeyringReadiness.pendingConfirmation);
    // Volver a la pantalla muestra la misma clave pendiente, no otra.
    expect((await keyring.pendingKey()).sameAs(key), isTrue);
    // Nada se cifra ni descifra con una pendiente.
    expect(await keyring.activeKey(), isNull);
    expect(await keyring.keyFor(await key.keyId()), isNull);
    await keyring.confirmPending(key.displayText);
    expect(await keyring.readiness(), KeyringReadiness.ready);
    expect((await keyring.activeKey())!.key.sameAs(key), isTrue);
  });

  test('una confirmación distinta no activa la clave', () async {
    await keyring.pendingKey();
    await expectLater(
      keyring.confirmPending(BackupRecoveryKey.generate().displayText),
      throwsA(isA<BackupKeyConfirmationMismatch>()),
    );
    await expectLater(
      keyring.confirmPending('no es una clave'),
      throwsA(isA<RecoveryKeyFormatException>()),
    );
    expect(await keyring.readiness(), KeyringReadiness.pendingConfirmation);
  });

  test('descartar la pendiente no afecta a la activa', () async {
    final first = await keyring.pendingKey();
    await keyring.confirmPending(first.displayText);
    await keyring.pendingKey();
    await keyring.discardPending();
    expect(await keyring.readiness(), KeyringReadiness.ready);
    expect((await keyring.activeKey())!.key.sameAs(first), isTrue);
  });

  test(
    'rotación: la anterior queda retirada y sigue sirviendo para descifrar',
    () async {
      final first = await keyring.pendingKey();
      await keyring.confirmPending(first.displayText);
      final firstId = (await keyring.activeKey())!.keyId;
      await keyring.recordUpload('copia-1', firstId);
      final second = await keyring.pendingKey();
      // Mientras no se confirma, la activa sigue siendo la primera.
      expect((await keyring.activeKey())!.key.sameAs(first), isTrue);
      await keyring.confirmPending(second.displayText);
      final secondId = (await keyring.activeKey())!.keyId;
      await keyring.recordUpload('copia-2', secondId);
      expect((await keyring.activeKey())!.key.sameAs(second), isTrue);
      expect(
        (await keyring.keyFor(await first.keyId()))!.sameAs(first),
        isTrue,
      );
      expect(
        await keyring.classify(['copia-1', 'copia-2', 'de-otro-telefono']),
        {
          'copia-1': RemoteCopyKey.retired,
          'copia-2': RemoteCopyKey.current,
          'de-otro-telefono': RemoteCopyKey.unknown,
        },
      );
    },
  );

  test('la clave recuperada pasa a activa en un llavero vacío y a retirada si ya había otra', () async {
    final paper = BackupRecoveryKey.generate();
    await keyring.adoptRecovered(paper);
    expect((await keyring.activeKey())!.key.sameAs(paper), isTrue);

    final other = BackupKeyring(_MemoryVault());
    final own = await other.pendingKey();
    await other.confirmPending(own.displayText);
    await other.adoptRecovered(paper);
    expect((await other.activeKey())!.key.sameAs(own), isTrue);
    expect((await other.keyFor(await paper.keyId()))!.sameAs(paper), isTrue);
  });

  test('un llavero ilegible no se sobrescribe solo', () async {
    vault.value = '{dañado';
    await expectLater(
      keyring.readiness(),
      throwsA(isA<BackupKeyringUnreadable>()),
    );
    await expectLater(
      keyring.pendingKey(),
      throwsA(isA<BackupKeyringUnreadable>()),
    );
    expect(vault.value, '{dañado');
    await keyring.replaceUnreadable();
    expect(await keyring.readiness(), KeyringReadiness.noKey);
  });

  test(
    'un almacén que falla al leer cuenta como ilegible, nunca como vacío',
    () async {
      final failing = BackupKeyring(_ThrowingVault());
      await expectLater(
        failing.readiness(),
        throwsA(isA<BackupKeyringUnreadable>()),
      );
      await expectLater(
        failing.keyFor(List<int>.filled(16, 0)),
        throwsA(isA<BackupKeyringUnreadable>()),
      );
    },
  );

  test('escrituras simultáneas no se pisan', () async {
    final first = await keyring.pendingKey();
    await keyring.confirmPending(first.displayText);
    await Future.wait([
      for (var i = 0; i < 20; i++) keyring.recordUpload('c$i', 'k$i'),
    ]);
    final classified = await keyring.classify([
      for (var i = 0; i < 20; i++) 'c$i',
    ]);
    expect(classified, hasLength(20));
    expect(vault.value, contains('"c19":"k19"'));
  });

  test(
    'el llavero no está en SQLite: un respaldo de la base no lo contiene',
    () async {
      sqfliteFfiInit();
      final dir = await Directory.systemTemp.createTemp('agro_f08_keyring_');
      addTearDown(() => dir.delete(recursive: true));
      final db = AppDatabase(
        factory: databaseFactoryFfi,
        path: p.join(dir.path, 'agro.db'),
      );
      final key = await keyring.pendingKey();
      await keyring.confirmPending(key.displayText);
      await db.database;
      await db.close();
      final bytes = await File(p.join(dir.path, 'agro.db')).readAsBytes();
      final text = String.fromCharCodes(bytes);
      expect(text, isNot(contains(key.displayText)));
      expect(text, isNot(contains('keyring')));
      expect(text, isNot(contains(keyIdHex(await key.keyId()))));
    },
  );

  test('el almacén real usa su propio espacio de nombres, excluido del auto-backup', () {
    expect(
      SecureStorageBackupKeyVault.androidNamespace,
      'agrocuentas_backup_keys_v1',
    );
    for (final name in ['backup_rules.xml', 'data_extraction_rules.xml']) {
      final xml = File('android/app/src/main/res/xml/$name').readAsStringSync();
      for (final excluded in [
        'path="agrocuentas_backup_keys_v1.xml"',
        'path="FlutterSecureKeyStorage:agrocuentas_backup_keys_v1.xml"',
        'path="FlutterSecureStorageConfiguration:agrocuentas_backup_keys_v1.xml"',
        'domain="database" path="previo"',
        'domain="file" path="remote_backups"',
      ]) {
        expect(xml, contains(excluded), reason: '$name: $excluded');
      }
    }
  });
}
