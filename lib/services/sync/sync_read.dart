import 'sync_access.dart';

typedef ReadIsCurrent = bool Function();

class SyncReadInvalidated implements Exception {
  const SyncReadInvalidated();
}

void requireCurrentRead(ReadIsCurrent isCurrent) {
  if (!isCurrent()) throw const SyncReadInvalidated();
}

bool unrestrictedSyncRead() => true;

/// Comparte únicamente lecturas que pertenecen a la misma credencial y base.
class SyncRead<T> {
  final _active = <VerifiedAccess, (ReadIsCurrent, Future<T>)>{};

  Future<T> run(
    VerifiedAccess access,
    ReadIsCurrent isCurrent,
    Future<T> Function() read,
  ) {
    requireCurrentRead(isCurrent);
    final current = _active[access];
    if (current != null && current.$1()) return current.$2;
    final result = Future.sync(read).whenComplete(() {
      if (_active[access]?.$1 == isCurrent) _active.remove(access);
    });
    _active[access] = (isCurrent, result);
    return result;
  }
}
