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

/// F03 «Recuperar acceso» (docs/architecture/F03_RECUPERACION_IDENTIDAD_LOCAL.md):
/// a runtime change of the stored session after startup. null = none yet.
/// [recovered]: a scope-checked session was committed (also over an
/// unreadable one). [signedOut]: a foreign session was durably deleted.
/// Carries no token or account identifier.
class RuntimeSessionTransition extends Notifier<ExistingSessionStartupState?> {
  @override
  ExistingSessionStartupState? build() => null;

  void recovered() => state = ExistingSessionStartupState.localSessionAvailable;

  void signedOut() => state = ExistingSessionStartupState.noLocalSession;
}

final runtimeSessionTransitionProvider =
    NotifierProvider<RuntimeSessionTransition, ExistingSessionStartupState?>(
      RuntimeSessionTransition.new,
    );

/// A successful first activation upgrades only an absent bootstrap result.
/// It does not claim remote validity or reinterpret an unreadable session.
/// An explicit F03 transition (recovery or sign-out) takes precedence.
final effectiveLocalSessionProvider = Provider<ExistingSessionStartupState>((
  ref,
) {
  final startup = ref.watch(existingSessionStartupProvider);
  final committed = ref.watch(runtimeSecureCommitCompletedProvider);
  final transition = ref.watch(runtimeSessionTransitionProvider);
  // The latest runtime event wins: every verified commit (first activation
  // or recovery) records recovered(); a durable sign-out records signedOut().
  if (transition != null) return transition;
  return committed && startup == ExistingSessionStartupState.noLocalSession
      ? ExistingSessionStartupState.localSessionAvailable
      : startup;
});
