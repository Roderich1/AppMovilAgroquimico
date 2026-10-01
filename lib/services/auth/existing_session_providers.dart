import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'existing_session_startup.dart';

/// main.dart overrides this with the completed local read before runApp.
/// Missing wiring fails closed for activation without blocking SQLite.
final existingSessionStartupProvider = Provider<ExistingSessionStartupState>(
  (ref) => ExistingSessionStartupState.unavailable,
);

/// A verified secure commit in this runtime is distinct from the startup read.
/// It carries no token or account identifier and cannot be reset by the UI.
class RuntimeSecureCommitCompleted extends Notifier<bool> {
  @override
  bool build() => false;

  void markCompleted() => state = true;
}

final runtimeSecureCommitCompletedProvider =
    NotifierProvider<RuntimeSecureCommitCompleted, bool>(
      RuntimeSecureCommitCompleted.new,
    );

/// A successful first activation upgrades only an absent bootstrap result.
/// It does not claim remote validity or reinterpret an unreadable session.
final effectiveLocalSessionProvider = Provider<ExistingSessionStartupState>((
  ref,
) {
  final startup = ref.watch(existingSessionStartupProvider);
  final committed = ref.watch(runtimeSecureCommitCompletedProvider);
  return committed && startup == ExistingSessionStartupState.noLocalSession
      ? ExistingSessionStartupState.localSessionAvailable
      : startup;
});
