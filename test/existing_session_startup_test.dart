import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:agroquimicos/data/installation_client_id_store.dart';
import 'package:agroquimicos/data/installation_identity_initializer.dart';
import 'package:agroquimicos/services/auth/existing_session_startup.dart';
import 'package:agroquimicos/services/auth/secure_session_store.dart';

final _session = StoredSession(
  refreshToken: 'synthetic-secret-never-exposed',
  installationClientId: 'synthetic-client-id',
  registrationId: 'synthetic-registration-id',
  accountId: 'synthetic-account-id',
  memberId: 'synthetic-member-id',
  tenantId: 'synthetic-tenant-id',
  sessionId: 'synthetic-session-id',
  expiresAt: DateTime.utc(2030),
);

void main() {
  const ready = InstallationIdentityInitialization(
    InstallationIdentityStatus.ready,
  );

  for (final (read, expected)
      in <(SessionReadResult, ExistingSessionStartupState)>[
        (
          const SessionReadResult(SessionReadStatus.absent),
          ExistingSessionStartupState.noLocalSession,
        ),
        (
          SessionReadResult(SessionReadStatus.available, session: _session),
          ExistingSessionStartupState.localSessionAvailable,
        ),
        (
          SessionReadResult(
            SessionReadStatus.available,
            session: _session,
            expiredLocally: true,
          ),
          ExistingSessionStartupState.localSessionExpired,
        ),
        (
          const SessionReadResult(SessionReadStatus.corrupt),
          ExistingSessionStartupState.corrupt,
        ),
        (
          const SessionReadResult(SessionReadStatus.unavailable),
          ExistingSessionStartupState.unavailable,
        ),
        (
          const SessionReadResult(SessionReadStatus.incompatible),
          ExistingSessionStartupState.incompatible,
        ),
        (
          const SessionReadResult(SessionReadStatus.available),
          ExistingSessionStartupState.corrupt,
        ),
      ]) {
    test(
      '${read.status} expired=${read.expiredLocally} -> $expected',
      () async {
        var reads = 0;
        final state = await ExistingSessionStartup(
          identity: ready,
          readLocalSession: () async {
            reads++;
            return read;
          },
        ).load();
        expect(state, expected);
        expect(reads, 1);
        expect(
          state.allowsFirstActivation,
          expected == ExistingSessionStartupState.noLocalSession,
        );
      },
    );
  }

  for (final (identityStatus, expected)
      in <(InstallationIdentityStatus, ExistingSessionStartupState)>[
        (
          InstallationIdentityStatus.corrupt,
          ExistingSessionStartupState.corrupt,
        ),
        (
          InstallationIdentityStatus.unavailable,
          ExistingSessionStartupState.unavailable,
        ),
      ]) {
    test('identity $identityStatus skips secure-session read', () async {
      var reads = 0;
      final state = await ExistingSessionStartup(
        identity: InstallationIdentityInitialization(identityStatus),
        readLocalSession: () async {
          reads++;
          return SessionReadResult(
            SessionReadStatus.available,
            session: _session,
          );
        },
      ).load();
      expect(state, expected);
      expect(reads, 0);
    });
  }

  test(
    'read failure and timeout fail closed without clearing anything',
    () async {
      final failed = await ExistingSessionStartup(
        identity: ready,
        readLocalSession: () =>
            Future.error(StateError('synthetic-secret-never-exposed')),
      ).load();
      final pending = Completer<SessionReadResult>();
      final timedOut = await ExistingSessionStartup(
        identity: ready,
        readLocalSession: () => pending.future,
        readTimeout: const Duration(milliseconds: 1),
      ).load();
      expect(failed, ExistingSessionStartupState.unavailable);
      expect(timedOut, ExistingSessionStartupState.unavailable);
    },
  );

  test('observable state and messages contain no session identifiers', () {
    const secrets = [
      'synthetic-secret-never-exposed',
      'synthetic-client-id',
      'synthetic-registration-id',
      'synthetic-account-id',
      'synthetic-member-id',
      'synthetic-tenant-id',
      'synthetic-session-id',
      'StoredSession',
    ];
    for (final state in ExistingSessionStartupState.values) {
      final observable = '${state.name} ${state.safeMessage}';
      for (final secret in secrets) {
        expect(observable, isNot(contains(secret)));
      }
    }
  });

  test(
    'bootstrap supplies one store to identity and encrypted reader',
    () async {
      final store = InstallationClientIdStore();
      InstallationClientIdStore? identityStore;
      InstallationClientIdStore? sessionStore;
      final result = await bootstrapExistingSession(
        identityStore: store,
        initializeIdentity: (input) async {
          identityStore = input;
          return ready;
        },
        readSession: (input) async {
          sessionStore = input;
          return const SessionReadResult(SessionReadStatus.absent);
        },
      );
      expect(identical(store, identityStore), isTrue);
      expect(identical(store, sessionStore), isTrue);
      expect(result.session, ExistingSessionStartupState.noLocalSession);
    },
  );
}
