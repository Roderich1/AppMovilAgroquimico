import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../data/installation_client_id_store.dart';
import 'first_activation_coordinator.dart';

enum SessionReadStatus { absent, available, corrupt, unavailable, incompatible }

enum SecureSessionFailure {
  invalidCandidate,
  existingSessionUnreadable,
  writeFailed,
  commitUncertain,
  deletionFailed,
  deletionUncertain,
}

/// No exception text from Android or the secure-storage plugin is exposed.
class SecureSessionStorageException implements Exception {
  const SecureSessionStorageException(this.reason);
  final SecureSessionFailure reason;

  @override
  String toString() => 'SecureSessionStorageException(${reason.name})';
}

class SecureSessionCommitUncertainException
    extends SecureSessionStorageException
    implements SecureSessionCommitOutcomeUnknown {
  const SecureSessionCommitUncertainException()
    : super(SecureSessionFailure.commitUncertain);
}

/// Contains a secret. Callers must never log or serialize this object outside
/// of the encrypted store. A local read does not prove remote authorization.
class StoredSession {
  const StoredSession({
    required this.refreshToken,
    required this.installationClientId,
    required this.registrationId,
    required this.accountId,
    required this.memberId,
    required this.tenantId,
    required this.sessionId,
    required this.expiresAt,
  });

  final String refreshToken;
  final String installationClientId;
  final String registrationId;
  final String accountId;
  final String memberId;
  final String tenantId;
  final String sessionId;
  final DateTime expiresAt;

  bool isExpiredLocally(DateTime now) => !expiresAt.isAfter(now);

  bool matches(SessionCommitCandidate candidate) =>
      refreshToken == candidate.refreshToken &&
      installationClientId == candidate.installationClientId &&
      registrationId == candidate.registrationId &&
      accountId == candidate.accountId &&
      memberId == candidate.memberId &&
      tenantId == candidate.tenantId &&
      sessionId == candidate.sessionId &&
      expiresAt.isAtSameMomentAs(candidate.expiresAt);

  @override
  String toString() => 'StoredSession(redacted)';
}

class SessionReadResult {
  const SessionReadResult(
    this.status, {
    this.session,
    this.expiredLocally = false,
  });

  final SessionReadStatus status;
  final StoredSession? session;
  final bool expiredLocally;

  @override
  String toString() =>
      'SessionReadResult(${status.name}, expiredLocally: $expiredLocally)';
}

abstract interface class EncryptedSessionSlots {
  Future<void> write(String slot, String value);
  Future<String?> read(String slot);
  Future<void> delete(String slot);
}

abstract interface class DurableSessionPointer {
  Future<String?> read();
  Future<void> activate({required String? expected, required String next});
  Future<void> clear({required String expected});
  Future<void> flushEncryptedDeletes();
}

/// One encrypted value contains token + metadata; no separate plaintext fields.
/// Dedicated namespace allows exact backup exclusions and no migration from a
/// previous (nonexistent) secure-session format.
class AndroidEncryptedSessionSlots implements EncryptedSessionSlots {
  AndroidEncryptedSessionSlots()
    : _storage = const FlutterSecureStorage(
        aOptions: AndroidOptions(
          storageNamespace: SecureSessionStore.androidNamespace,
          resetOnError: false,
          migrateOnAlgorithmChange: false,
        ),
      );

  final FlutterSecureStorage _storage;

  @override
  Future<void> write(String slot, String value) =>
      _storage.write(key: 'session_$slot', value: value);

  @override
  Future<String?> read(String slot) => _storage.read(key: 'session_$slot');

  @override
  Future<void> delete(String slot) => _storage.delete(key: 'session_$slot');
}

/// Android-side activate performs a disk-flush barrier on all three plugin
/// preference files, then commits and rereads the active-slot pointer.
class AndroidDurableSessionPointer implements DurableSessionPointer {
  const AndroidDurableSessionPointer();

  static const _channel = MethodChannel('agrocuentas/secure_session_pointer');

  @override
  Future<String?> read() => _channel.invokeMethod<String>('read');

  @override
  Future<void> activate({
    required String? expected,
    required String next,
  }) async {
    await _channel.invokeMethod<String>('activate', {
      'expected': expected,
      'next': next,
    });
  }

  @override
  Future<void> clear({required String expected}) async {
    await _channel.invokeMethod<void>('clear', {'expected': expected});
  }

  @override
  Future<void> flushEncryptedDeletes() async {
    await _channel.invokeMethod<void>('flush');
  }
}

class _IncompatibleVersion implements Exception {}

/// Android-only implementation of #19's commit port. Two encrypted slots plus
/// a synchronously committed pointer preserve the previous session until the
/// new candidate has been written and read back. All operations serialize in
/// this Dart isolate; Android uses a second lock and expected-pointer check.
class SecureSessionStore implements SecureSessionCommitPort {
  SecureSessionStore({
    required EncryptedSessionSlots slots,
    required DurableSessionPointer pointer,
    required InstallationClientIdStore identityStore,
    DateTime Function()? clock,
  }) : _slots = slots,
       _pointer = pointer,
       _identityStore = identityStore,
       _clock = clock ?? DateTime.now;

  factory SecureSessionStore.android({
    InstallationClientIdStore? identityStore,
  }) {
    if (!Platform.isAndroid) {
      throw const SecureSessionStorageException(
        SecureSessionFailure.existingSessionUnreadable,
      );
    }
    return SecureSessionStore(
      slots: AndroidEncryptedSessionSlots(),
      pointer: const AndroidDurableSessionPointer(),
      identityStore: identityStore ?? InstallationClientIdStore(),
    );
  }

  static const androidNamespace = 'agrocuentas_secure_session_v1';
  static const _recordVersion = 1;
  static Future<void> _operationTail = Future<void>.value();

  final EncryptedSessionSlots _slots;
  final DurableSessionPointer _pointer;
  final InstallationClientIdStore _identityStore;
  final DateTime Function() _clock;

  Future<T> _exclusive<T>(Future<T> Function() operation) async {
    final previous = _operationTail;
    final done = Completer<void>();
    _operationTail = done.future;
    await previous;
    try {
      return await operation();
    } finally {
      done.complete();
    }
  }

  @override
  Future<void> commitAndVerify(SessionCommitCandidate candidate) =>
      _exclusive(() => _commit(candidate));

  Future<SessionReadResult> read() => _exclusive(_readUnlocked);

  Future<void> delete() => _exclusive(_deleteUnlocked);

  Future<void> _commit(SessionCommitCandidate candidate) async {
    if (!_validCandidate(candidate)) {
      throw const SecureSessionStorageException(
        SecureSessionFailure.invalidCandidate,
      );
    }
    try {
      if (await _identityStore.read() != candidate.installationClientId) {
        throw const SecureSessionStorageException(
          SecureSessionFailure.invalidCandidate,
        );
      }
    } on SecureSessionStorageException {
      rethrow;
    } on Object {
      throw const SecureSessionStorageException(
        SecureSessionFailure.existingSessionUnreadable,
      );
    }

    final String? previous;
    try {
      previous = await _pointer.read();
    } on Object {
      throw const SecureSessionStorageException(
        SecureSessionFailure.existingSessionUnreadable,
      );
    }
    if (previous != null) {
      final old = await _readUnlocked();
      if (old.status != SessionReadStatus.available) {
        throw const SecureSessionStorageException(
          SecureSessionFailure.existingSessionUnreadable,
        );
      }
    }

    final next = previous == 'a' ? 'b' : 'a';
    final encoded = _encode(candidate);
    try {
      await _slots.write(next, encoded);
      // This checks authenticated decryption and exact payload before the
      // pointer can make the new slot visible. The native barrier follows.
      final staged = await _slots.read(next);
      if (staged != encoded) throw const FormatException('Staged mismatch');
      if (!_decode(staged!).matches(candidate)) {
        throw const FormatException('Staged fields mismatch');
      }
    } on Object {
      // Only an inactive slot may have changed. The old active pointer and
      // previous credential remain untouched.
      throw const SecureSessionStorageException(
        SecureSessionFailure.writeFailed,
      );
    }

    try {
      await _pointer.activate(expected: previous, next: next);
    } on Object {
      // A failed/lost MethodChannel response cannot prove that commit() reached
      // disk. SharedPreferences' in-memory pointer may already show `next`.
      // Never reinterpret a reread as a durable acknowledgement.
      throw const SecureSessionCommitUncertainException();
    }

    final observed = await _readUnlocked();
    if (observed.status != SessionReadStatus.available ||
        !observed.session!.matches(candidate)) {
      // The pointer was committed; never pretend a rollback occurred.
      throw const SecureSessionCommitUncertainException();
    }
  }

  Future<SessionReadResult> _readUnlocked() async {
    final String? active;
    try {
      active = await _pointer.read();
    } on PlatformException catch (error) {
      if (error.code == 'CORRUPT_POINTER') {
        return const SessionReadResult(SessionReadStatus.corrupt);
      }
      return const SessionReadResult(SessionReadStatus.unavailable);
    } on FormatException {
      return const SessionReadResult(SessionReadStatus.corrupt);
    } on Object {
      return const SessionReadResult(SessionReadStatus.unavailable);
    }
    if (active == null)
      return const SessionReadResult(SessionReadStatus.absent);
    if (active != 'a' && active != 'b') {
      return const SessionReadResult(SessionReadStatus.corrupt);
    }
    try {
      final raw = await _slots.read(active);
      if (raw == null)
        return const SessionReadResult(SessionReadStatus.corrupt);
      final session = _decode(raw);
      final currentIdentity = await _identityStore.read();
      if (currentIdentity == null ||
          currentIdentity != session.installationClientId) {
        return const SessionReadResult(SessionReadStatus.corrupt);
      }
      return SessionReadResult(
        SessionReadStatus.available,
        session: session,
        expiredLocally: session.isExpiredLocally(_clock()),
      );
    } on _IncompatibleVersion {
      return const SessionReadResult(SessionReadStatus.incompatible);
    } on InstallationClientIdCorruptException {
      return const SessionReadResult(SessionReadStatus.corrupt);
    } on FormatException {
      return const SessionReadResult(SessionReadStatus.corrupt);
    } on Object {
      return const SessionReadResult(SessionReadStatus.unavailable);
    }
  }

  Future<void> _deleteUnlocked() async {
    final String? active;
    try {
      active = await _pointer.read();
    } on Object {
      throw const SecureSessionStorageException(
        SecureSessionFailure.deletionUncertain,
      );
    }
    if (active != null) {
      try {
        await _pointer.clear(expected: active);
      } on Object {
        // A reread may only reflect SharedPreferences' in-memory state after
        // a failed commit(). Never delete ciphertext without a durable ack.
        throw const SecureSessionStorageException(
          SecureSessionFailure.deletionUncertain,
        );
      }
    }
    // Pointer is durably absent. Ciphertext cleanup is retriable if it fails.
    try {
      await _slots.delete('a');
      await _slots.delete('b');
      await _pointer.flushEncryptedDeletes();
    } on Object {
      throw const SecureSessionStorageException(
        SecureSessionFailure.deletionFailed,
      );
    }
  }

  bool _validCandidate(SessionCommitCandidate value) =>
      value.refreshToken.trim().isNotEmpty &&
      InstallationClientIdStore.isCanonicalUuidV4(value.installationClientId) &&
      value.registrationId.trim().isNotEmpty &&
      value.accountId.trim().isNotEmpty &&
      value.memberId.trim().isNotEmpty &&
      value.tenantId.trim().isNotEmpty &&
      value.sessionId.trim().isNotEmpty &&
      value.expiresAt.isAfter(_clock());

  String _encode(SessionCommitCandidate value) => jsonEncode({
    'version': _recordVersion,
    'refreshToken': value.refreshToken,
    'installationClientId': value.installationClientId,
    'registrationId': value.registrationId,
    'accountId': value.accountId,
    'memberId': value.memberId,
    'tenantId': value.tenantId,
    'sessionId': value.sessionId,
    'expiresAt': value.expiresAt.toUtc().toIso8601String(),
  });

  StoredSession _decode(String raw) {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid record');
    }
    if (decoded['version'] != _recordVersion) throw _IncompatibleVersion();
    const fields = [
      'refreshToken',
      'installationClientId',
      'registrationId',
      'accountId',
      'memberId',
      'tenantId',
      'sessionId',
      'expiresAt',
    ];
    for (final field in fields) {
      if (decoded[field] is! String ||
          (decoded[field] as String).trim().isEmpty) {
        throw const FormatException('Invalid field');
      }
    }
    if (decoded.length != fields.length + 1 ||
        !InstallationClientIdStore.isCanonicalUuidV4(
          decoded['installationClientId'] as String,
        )) {
      throw const FormatException('Invalid schema');
    }
    final expiry = DateTime.tryParse(decoded['expiresAt'] as String);
    if (expiry == null) throw const FormatException('Invalid expiry');
    return StoredSession(
      refreshToken: decoded['refreshToken'] as String,
      installationClientId: decoded['installationClientId'] as String,
      registrationId: decoded['registrationId'] as String,
      accountId: decoded['accountId'] as String,
      memberId: decoded['memberId'] as String,
      tenantId: decoded['tenantId'] as String,
      sessionId: decoded['sessionId'] as String,
      expiresAt: expiry,
    );
  }
}
