import 'package:flutter/services.dart';

/// A non-secret, disk-committed marker. Failure to read is never interpreted
/// as clear by callers. Android stores it alongside the excluded pointer.
abstract interface class RefreshGuard {
  Future<bool> isQuarantined();
  Future<void> quarantine();
  Future<void> clear();
}

class AndroidRefreshGuard implements RefreshGuard {
  const AndroidRefreshGuard({this.channel = defaultChannel});

  static const defaultChannel = MethodChannel(
    'agrocuentas/secure_session_pointer',
  );
  final MethodChannel channel;

  @override
  Future<bool> isQuarantined() async {
    return await channel.invokeMethod<bool>('readRefreshGuard') ??
        (throw StateError('Refresh guard unavailable'));
  }

  @override
  Future<void> quarantine() async {
    if (await channel.invokeMethod<bool>('setRefreshGuard') != true) {
      throw StateError('Refresh guard commit unconfirmed');
    }
  }

  @override
  Future<void> clear() async {
    if (await channel.invokeMethod<bool>('clearRefreshGuard') != false) {
      throw StateError('Refresh guard clear unconfirmed');
    }
  }
}
