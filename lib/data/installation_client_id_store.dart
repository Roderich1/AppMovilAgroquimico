import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef InstallationDirectoryProvider = Future<Directory> Function();
typedef SecureByteGenerator = List<int> Function(int length);

class InstallationClientIdCorruptException implements Exception {
  const InstallationClientIdCorruptException(this.path);

  final String path;

  @override
  String toString() =>
      'InstallationClientIdCorruptException: el archivo de identidad en $path '
      'no contiene un UUID v4 canónico.';
}

/// Identidad lógica y seudónima de esta instalación.
///
/// No usa IMEI, Android ID, serial, MAC, advertising ID ni ningún fingerprint.
/// El valor no es secreto ni concede autenticación/autorización. En Android se
/// guarda bajo `noBackupFilesDir`, fuera de SQLite, `.agrobackup` y Auto Backup.
class InstallationClientIdStore {
  InstallationClientIdStore({
    InstallationDirectoryProvider? directoryProvider,
    SecureByteGenerator? secureBytes,
  }) : _directoryProvider = directoryProvider ?? _defaultInstallationDirectory,
       _secureBytes = secureBytes ?? _randomSecureBytes;

  static const MethodChannel _androidStorage = MethodChannel(
    'agrocuentas/installation_identity',
  );
  static const String fileName = 'client_id';
  static final RegExp _uuidV4 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  final InstallationDirectoryProvider _directoryProvider;
  final SecureByteGenerator _secureBytes;
  Future<String>? _pendingGetOrCreate;

  Future<String> getOrCreate() {
    final pending = _pendingGetOrCreate;
    if (pending != null) return pending;
    final operation = _getOrCreate();
    _pendingGetOrCreate = operation;
    return operation.whenComplete(() {
      if (identical(_pendingGetOrCreate, operation)) {
        _pendingGetOrCreate = null;
      }
    });
  }

  Future<String?> read() async {
    final file = await _file();
    if (!await file.exists()) return null;
    final value = (await file.readAsString()).trim();
    if (!isCanonicalUuidV4(value)) {
      throw InstallationClientIdCorruptException(file.path);
    }
    return value;
  }

  /// Rotación explícita: crea una identidad nueva. El caller remoto futuro
  /// deberá registrar la nueva y revocar la anterior; aquí no se finge una
  /// operación atómica entre Mobile y Central.
  Future<String> rotate() async {
    final previous = await read();
    var replacement = _newUuidV4();
    while (replacement == previous) {
      replacement = _newUuidV4();
    }
    await _write(replacement);
    return replacement;
  }

  static bool isCanonicalUuidV4(String value) => _uuidV4.hasMatch(value);

  Future<String> _getOrCreate() async {
    final existing = await read();
    if (existing != null) return existing;
    final created = _newUuidV4();
    await _write(created);
    return created;
  }

  String _newUuidV4() {
    final bytes = _secureBytes(16);
    if (bytes.length != 16 || bytes.any((value) => value < 0 || value > 255)) {
      throw StateError('La fuente segura debe producir exactamente 16 bytes.');
    }
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<File> _file() async {
    final directory = await _directoryProvider();
    return File(p.join(directory.path, fileName));
  }

  Future<void> _write(String value) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString('$value\n', flush: true);
  }

  static List<int> _randomSecureBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  static Future<Directory> _defaultInstallationDirectory() async {
    if (Platform.isAndroid) {
      final root = await _androidStorage.invokeMethod<String>(
        'getNoBackupDirectory',
      );
      if (root == null || root.isEmpty) {
        throw StateError('Android no devolvió su directorio no-backup.');
      }
      return Directory(p.join(root, 'installation_identity'));
    }

    // El target físico F02-B es Android. Este fallback mantiene la abstracción
    // utilizable en otros hosts, pero su exclusión del backup queda NOT_MEASURED.
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'installation_identity'));
  }
}
