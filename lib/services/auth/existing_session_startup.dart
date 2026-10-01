import 'dart:async';

import '../../data/installation_client_id_store.dart';
import '../../data/installation_identity_initializer.dart';
import 'secure_session_store.dart';

/// Local-only classification. It never contains a credential or account ID.
enum ExistingSessionStartupState {
  noLocalSession,
  localSessionAvailable,
  localSessionExpired,
  corrupt,
  unavailable,
  incompatible;

  bool get allowsFirstActivation => this == noLocalSession;

  String? get safeMessage => switch (this) {
    noLocalSession => null,
    localSessionAvailable =>
      'Cuenta vinculada en este dispositivo. '
          'El estado en línea aún no fue verificado.',
    localSessionExpired =>
      'Cuenta vinculada en este dispositivo. '
          'La verificación en línea está pendiente.',
    corrupt =>
      'La vinculación local no puede leerse. '
          'Los datos locales siguen disponibles.',
    unavailable =>
      'La vinculación local no está disponible. '
          'Los datos locales siguen disponibles.',
    incompatible =>
      'La versión de la vinculación local no es compatible. '
          'Los datos locales siguen disponibles.',
  };
}

/// Only the encrypted local read is admitted here: no AuthV2Api or HTTP port.
class ExistingSessionStartup {
  const ExistingSessionStartup({
    required this.identity,
    required this.readLocalSession,
    this.readTimeout = const Duration(seconds: 3),
  });

  final InstallationIdentityInitialization identity;
  final Future<SessionReadResult> Function() readLocalSession;
  final Duration readTimeout;

  Future<ExistingSessionStartupState> load() async {
    if (identity.status == InstallationIdentityStatus.corrupt) {
      return ExistingSessionStartupState.corrupt;
    }
    if (identity.status == InstallationIdentityStatus.unavailable) {
      return ExistingSessionStartupState.unavailable;
    }

    try {
      final result = await readLocalSession().timeout(readTimeout);
      return switch (result.status) {
        SessionReadStatus.absent => ExistingSessionStartupState.noLocalSession,
        SessionReadStatus.available =>
          result.session == null
              ? ExistingSessionStartupState.corrupt
              : result.expiredLocally
              ? ExistingSessionStartupState.localSessionExpired
              : ExistingSessionStartupState.localSessionAvailable,
        SessionReadStatus.corrupt => ExistingSessionStartupState.corrupt,
        SessionReadStatus.unavailable =>
          ExistingSessionStartupState.unavailable,
        SessionReadStatus.incompatible =>
          ExistingSessionStartupState.incompatible,
      };
    } on Object {
      // A slow/failed Keystore read never blocks the SQLite domain or becomes
      // a false "no session" result. No exception text is exposed or logged.
      return ExistingSessionStartupState.unavailable;
    }
  }
}

class ExistingSessionBootstrapResult {
  const ExistingSessionBootstrapResult(this.identity, this.session);

  final InstallationIdentityInitialization identity;
  final ExistingSessionStartupState session;
}

typedef InstallationIdentityLoader =
    Future<InstallationIdentityInitialization> Function(
      InstallationClientIdStore store,
    );
typedef LocalSessionReader = Future<SessionReadResult> Function(
  InstallationClientIdStore store,
);

/// The same installation store is passed to identity initialization and the
/// Android secure-session read. Tests can observe that identity without using
/// Keystore, while production always uses the encrypted implementation.
Future<ExistingSessionBootstrapResult> bootstrapExistingSession({
  required InstallationClientIdStore identityStore,
  InstallationIdentityLoader? initializeIdentity,
  LocalSessionReader? readSession,
  Duration readTimeout = const Duration(seconds: 3),
}) async {
  final identity =
      await (initializeIdentity ??
          (store) =>
              initializeInstallationIdentity(store: store))(identityStore);
  final session = await ExistingSessionStartup(
    identity: identity,
    readLocalSession: () =>
        (readSession ??
        (store) =>
            SecureSessionStore.android(identityStore: store)
                .read())(identityStore),
    readTimeout: readTimeout,
  ).load();
  return ExistingSessionBootstrapResult(identity, session);
}
