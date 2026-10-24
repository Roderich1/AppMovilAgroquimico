// Llavero local de claves de recuperación del respaldo (F08-ADR-003 §3).
//
// Vive en el almacén seguro de Android (flutter_secure_storage, espacio de
// nombres propio `agrocuentas_backup_keys_v1`, excluido del auto-backup). No
// está en SQLite, así que nunca viaja dentro de un respaldo. No hay escrow ni
// copia en el servidor: si se pierden el teléfono y la clave anotada, las
// copias cifradas no se pueden recuperar.
//
// Es independiente de la sesión (Auth V2) y del PIN local: cerrar o recuperar
// la sesión, o restablecer el PIN, no lo toca, y ninguno de ellos sirve para
// derivar estas claves.
//
// Nada de este archivo registra claves ni el contenido del llavero.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../data/backup_encryption.dart';

/// Almacén de un único valor secreto (el llavero serializado).
abstract interface class BackupKeyVault {
  Future<String?> read();
  Future<void> write(String value);
}

/// Almacén seguro de Android con espacio de nombres propio. `resetOnError`
/// desactivado: un llavero ilegible no se borra solo.
class SecureStorageBackupKeyVault implements BackupKeyVault {
  const SecureStorageBackupKeyVault();

  static const androidNamespace = 'agrocuentas_backup_keys_v1';
  static const _entry = 'keyring';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      storageNamespace: androidNamespace,
      resetOnError: false,
      migrateOnAlgorithmChange: false,
    ),
  );

  @override
  Future<String?> read() => _storage.read(key: _entry);

  @override
  Future<void> write(String value) => _storage.write(key: _entry, value: value);
}

enum BackupKeyStatus {
  /// Mostrada pero todavía no confirmada: nada depende de ella.
  pending,

  /// Confirmada y en uso para las copias nuevas.
  active,

  /// Sustituida por otra; se conserva para descifrar copias anteriores.
  retired,
}

/// Situación del llavero para la interfaz.
enum KeyringReadiness {
  /// No hay clave: hay que crear una antes de subir.
  noKey,

  /// Hay una clave mostrada y sin confirmar.
  pendingConfirmation,

  /// Hay una clave activa y confirmada: se puede subir.
  ready,
}

/// El llavero existe pero no se puede leer. No se sobrescribe sin una acción
/// expresa ([BackupKeyring.replaceUnreadable]).
class BackupKeyringUnreadable implements Exception {
  const BackupKeyringUnreadable();

  String get message =>
      'No se pudo leer el llavero de claves de respaldo de este teléfono. '
      'Para descifrar una copia, escriba su clave de recuperación.';

  @override
  String toString() => message;
}

/// La clave escrita no es la que se mostró.
class BackupKeyConfirmationMismatch implements Exception {
  const BackupKeyConfirmationMismatch();

  String get message =>
      'La clave escrita no coincide con la que se mostró. Compruebe lo que '
      'anotó; la clave no se activó.';

  @override
  String toString() => message;
}

class _StoredKey {
  _StoredKey({
    required this.keyId,
    required this.key,
    required this.status,
    required this.createdAt,
    this.confirmedAt,
    this.retiredAt,
  });

  final String keyId;
  final BackupRecoveryKey key;
  BackupKeyStatus status;
  final DateTime createdAt;
  DateTime? confirmedAt;
  DateTime? retiredAt;

  Map<String, Object?> toJson() => {
    'keyId': keyId,
    'key': base64Encode(key.storedBytes),
    'status': status.name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'confirmedAt': confirmedAt?.toUtc().toIso8601String(),
    'retiredAt': retiredAt?.toUtc().toIso8601String(),
  };

  static _StoredKey fromJson(Map<String, Object?> json) => _StoredKey(
    keyId: json['keyId']! as String,
    key: BackupRecoveryKey.fromStoredBytes(
      base64Decode(json['key']! as String),
    ),
    status: BackupKeyStatus.values.byName(json['status']! as String),
    createdAt: DateTime.parse(json['createdAt']! as String),
    confirmedAt: json['confirmedAt'] == null
        ? null
        : DateTime.parse(json['confirmedAt']! as String),
    retiredAt: json['retiredAt'] == null
        ? null
        : DateTime.parse(json['retiredAt']! as String),
  );
}

class _Keyring {
  _Keyring(this.keys, this.uploads);
  final List<_StoredKey> keys;

  /// Copias subidas desde este teléfono: id remoto → identificador de clave.
  /// No es secreto; permite saber qué clave necesita cada copia sin
  /// descargarla.
  final Map<String, String> uploads;

  static const _version = 1;

  String encode() => jsonEncode({
    'version': _version,
    'keys': [for (final key in keys) key.toJson()],
    'uploads': uploads,
  });

  static _Keyring decode(String? raw) {
    if (raw == null) return _Keyring([], {});
    try {
      final json = jsonDecode(raw) as Map<String, Object?>;
      if (json['version'] != _version) throw const FormatException();
      return _Keyring([
        for (final item in json['keys']! as List)
          _StoredKey.fromJson(item as Map<String, Object?>),
      ], (json['uploads']! as Map).cast<String, String>());
    } on Object {
      throw const BackupKeyringUnreadable();
    }
  }
}

String keyIdHex(List<int> keyId) =>
    keyId.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Qué clave necesita una copia remota, por lo que sabe este teléfono.
enum RemoteCopyKey {
  /// La clave activa de este teléfono.
  current,

  /// Una clave anterior que este teléfono todavía conserva.
  retired,

  /// Subida desde otro teléfono o antes de reinstalar: hará falta la clave de
  /// recuperación correspondiente.
  unknown,
}

enum BackupKeyAction { show, rotate }

/// Consume una autorización del titular para [action] sobre la clave
/// [keyIdHex], o lanza si no vale. En la composición es
/// `consumeOwnerAuthorization` de A (propósitos SHOW_BACKUP_RECOVERY_KEY y
/// ROTATE_BACKUP_RECOVERY_KEY, `subjectRef` = [keyIdHex], contra el vínculo
/// vigente). La autorización es opaca aquí: la emite y la comprueba A.
typedef BackupKeyAuthorizationConsumer = Future<void> Function(
  Object authorization,
  BackupKeyAction action,
  String keyIdHex,
);

/// Mostrar o cambiar la clave activa exige una autorización válida del
/// titular, también si se llama al llavero sin pasar por la pantalla.
class BackupKeyAuthorizationRequired implements Exception {
  const BackupKeyAuthorizationRequired();

  String get message =>
      'Hace falta la autorización del titular en este teléfono. No se mostró '
      'ni se cambió la clave.';

  @override
  String toString() => message;
}

/// Sin conectar con la credencial local: falla cerrado.
Future<void> _denyAll(Object _, BackupKeyAction _, String _) async =>
    throw const BackupKeyAuthorizationRequired();

class BackupKeyring {
  BackupKeyring(
    this._vault, {
    DateTime Function()? clock,
    BackupKeyAuthorizationConsumer consumeAuthorization = _denyAll,
  }) : _clock = clock ?? DateTime.now,
       _consumeAuthorization = consumeAuthorization;

  final BackupKeyVault _vault;
  final DateTime Function() _clock;
  final BackupKeyAuthorizationConsumer _consumeAuthorization;

  Future<void> _authorize(
    Object? authorization,
    BackupKeyAction action,
    String keyIdHex,
  ) async {
    if (authorization == null) throw const BackupKeyAuthorizationRequired();
    try {
      await _consumeAuthorization(authorization, action, keyIdHex);
    } on BackupKeyAuthorizationRequired {
      rethrow;
    } on Object {
      throw const BackupKeyAuthorizationRequired();
    }
  }

  /// Las operaciones se encadenan: dos escrituras nunca se pisan.
  Future<void> _tail = Future.value();

  Future<T> _serial<T>(Future<T> Function() run) {
    final result = _tail.then((_) => run());
    _tail = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  /// Un almacén que no se puede leer (contenido dañado o Keystore
  /// invalidado) cuenta como ilegible: nunca como vacío.
  Future<_Keyring> _load() async {
    final String? raw;
    try {
      raw = await _vault.read();
    } on Object {
      throw const BackupKeyringUnreadable();
    }
    return _Keyring.decode(raw);
  }

  Future<void> _save(_Keyring keyring) => _vault.write(keyring.encode());

  Future<KeyringReadiness> readiness() => _serial(() async {
    final keyring = await _load();
    if (keyring.keys.any((k) => k.status == BackupKeyStatus.active)) {
      return KeyringReadiness.ready;
    }
    if (keyring.keys.any((k) => k.status == BackupKeyStatus.pending)) {
      return KeyringReadiness.pendingConfirmation;
    }
    return KeyringReadiness.noKey;
  });

  /// Primera clave, mostrada y sin confirmar: si no existe, la crea (sin
  /// autorización: nada depende todavía de ella). Con una activa no entrega
  /// nada, tampoco la pendiente de una rotación interrumpida: ésa sólo la
  /// devuelve [startRotation], con la autorización del titular.
  Future<BackupRecoveryKey> pendingKey() => _serial(() async {
    final keyring = await _load();
    if (keyring.keys.any((k) => k.status == BackupKeyStatus.active)) {
      throw const BackupKeyAuthorizationRequired();
    }
    for (final stored in keyring.keys) {
      if (stored.status == BackupKeyStatus.pending) return stored.key;
    }
    return _addPending(keyring);
  });

  /// Empieza el cambio de la clave activa: consume la autorización del
  /// titular y crea la pendiente que se mostrará y confirmará. Mientras no se
  /// confirme, la activa sigue en uso.
  Future<BackupRecoveryKey> startRotation({required Object? authorization}) =>
      _serial(() async {
        final keyring = await _load();
        final active = keyring.keys
            .where((k) => k.status == BackupKeyStatus.active)
            .firstOrNull;
        if (active == null) throw const BackupKeyAuthorizationRequired();
        await _authorize(authorization, BackupKeyAction.rotate, active.keyId);
        for (final stored in keyring.keys) {
          if (stored.status == BackupKeyStatus.pending) return stored.key;
        }
        return _addPending(keyring);
      });

  Future<BackupRecoveryKey> _addPending(_Keyring keyring) async {
    final key = BackupRecoveryKey.generate();
    keyring.keys.add(
      _StoredKey(
        keyId: keyIdHex(await key.keyId()),
        key: key,
        status: BackupKeyStatus.pending,
        createdAt: _clock().toUtc(),
      ),
    );
    await _save(keyring);
    return key;
  }

  /// Descarta la clave pendiente (p. ej. la persona no pudo anotarla). Nada
  /// dependía de ella.
  Future<void> discardPending() => _serial(() async {
    final keyring = await _load();
    keyring.keys.removeWhere((k) => k.status == BackupKeyStatus.pending);
    await _save(keyring);
  });

  /// La persona vuelve a escribir la clave anotada. Sólo si coincide pasa a
  /// activa; la anterior activa queda retirada, nunca borrada.
  Future<void> confirmPending(String typed) => _serial(() async {
    final candidate = BackupRecoveryKey.parse(typed);
    final keyring = await _load();
    final pending = keyring.keys
        .where((k) => k.status == BackupKeyStatus.pending)
        .firstOrNull;
    if (pending == null || !pending.key.sameAs(candidate)) {
      throw const BackupKeyConfirmationMismatch();
    }
    final now = _clock().toUtc();
    for (final stored in keyring.keys) {
      if (stored.status == BackupKeyStatus.active) {
        stored
          ..status = BackupKeyStatus.retired
          ..retiredAt = now;
      }
    }
    pending
      ..status = BackupKeyStatus.active
      ..confirmedAt = now;
    await _save(keyring);
  });

  /// Clave para cifrar una copia nueva: sólo la activa y confirmada.
  Future<({BackupRecoveryKey key, String keyId})?> activeKey() =>
      _serial(() async {
        final keyring = await _load();
        final active = keyring.keys
            .where((k) => k.status == BackupKeyStatus.active)
            .firstOrNull;
        return active == null ? null : (key: active.key, keyId: active.keyId);
      });

  /// Clave confirmada (activa o retirada) con ese identificador. Las
  /// pendientes no se usan para descifrar: nada se cifró con ellas.
  Future<BackupRecoveryKey?> keyFor(List<int> keyId) => _serial(() async {
    final wanted = keyIdHex(keyId);
    final keyring = await _load();
    return keyring.keys
        .where((k) => k.keyId == wanted && k.status != BackupKeyStatus.pending)
        .firstOrNull
        ?.key;
  });

  /// Tras restaurar con una clave escrita: la persona demostró tenerla fuera
  /// del teléfono, así que queda confirmada. Pasa a activa si no había otra;
  /// si la había, se conserva como retirada para descifrar.
  Future<void> adoptRecovered(BackupRecoveryKey key) => _serial(() async {
    final keyring = await _load();
    final id = keyIdHex(await key.keyId());
    final existing = keyring.keys.where((k) => k.keyId == id).firstOrNull;
    final now = _clock().toUtc();
    final hasActive = keyring.keys.any(
      (k) => k.status == BackupKeyStatus.active,
    );
    if (existing != null) {
      if (existing.status == BackupKeyStatus.pending) {
        existing
          ..status = hasActive
              ? BackupKeyStatus.retired
              : BackupKeyStatus.active
          ..confirmedAt = now;
        await _save(keyring);
      }
      return;
    }
    keyring.keys.add(
      _StoredKey(
        keyId: id,
        key: key,
        status: hasActive ? BackupKeyStatus.retired : BackupKeyStatus.active,
        createdAt: now,
        confirmedAt: now,
        retiredAt: hasActive ? now : null,
      ),
    );
    await _save(keyring);
  });

  /// Anota con qué clave se subió una copia.
  Future<void> recordUpload(String remoteId, String keyId) => _serial(() async {
    final keyring = await _load();
    keyring.uploads[remoteId] = keyId;
    await _save(keyring);
  });

  /// Qué clave necesita cada copia remota cifrada, según este teléfono.
  Future<Map<String, RemoteCopyKey>> classify(Iterable<String> remoteIds) =>
      _serial(() async {
        final keyring = await _load();
        final byId = {for (final k in keyring.keys) k.keyId: k.status};
        return {
          for (final id in remoteIds)
            id: switch (byId[keyring.uploads[id]]) {
              BackupKeyStatus.active => RemoteCopyKey.current,
              BackupKeyStatus.retired => RemoteCopyKey.retired,
              _ => RemoteCopyKey.unknown,
            },
        };
      });

  /// Muestra otra vez la clave activa: sólo con una autorización del titular
  /// que se consume aquí, no en la pantalla.
  Future<BackupRecoveryKey?> revealActive({required Object? authorization}) =>
      _serial(() async {
        final keyring = await _load();
        final active = keyring.keys
            .where((k) => k.status == BackupKeyStatus.active)
            .firstOrNull;
        if (active == null) return null;
        await _authorize(authorization, BackupKeyAction.show, active.keyId);
        return active.key;
      });

  /// El llavero no se podía leer y la persona decide empezar uno nuevo. Las
  /// claves ilegibles se pierden: sólo se hace por acción expresa.
  Future<void> replaceUnreadable() => _serial(() async {
    try {
      await _load();
      return;
    } on BackupKeyringUnreadable {
      await _save(_Keyring([], {}));
    }
  });
}
