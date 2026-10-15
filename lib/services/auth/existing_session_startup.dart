import 'dart:async';

import '../../data/installation_client_id_store.dart';
import '../../data/installation_identity_initializer.dart';
import '../../domain/installation_access.dart';
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

  Future<ExistingSessionStartupState> load() async => (await loadDetailed()).$1;

  /// Igual que [load], y además el ámbito (Member, tenant) de la sesión si es
  /// legible. El ámbito no es credencial; sólo queda en memoria.
  Future<(ExistingSessionStartupState, OwnerScope?)> loadDetailed() async {
    if (identity.status == InstallationIdentityStatus.corrupt) {
      return (ExistingSessionStartupState.corrupt, null);
    }
    if (identity.status == InstallationIdentityStatus.unavailable) {
      return (ExistingSessionStartupState.unavailable, null);
    }

    try {
      final result = await readLocalSession().timeout(readTimeout);
      final session = result.session;
      final scope =
          result.status == SessionReadStatus.available && session != null
          ? OwnerScope(memberId: session.memberId, tenantId: session.tenantId)
          : null;
      return (_classify(result), scope);
    } on Object {
      // A slow/failed Keystore read never blocks the SQLite domain or becomes
      // a false "no session" result. No exception text is exposed or logged.
      return (ExistingSessionStartupState.unavailable, null);
    }
  }

  static ExistingSessionStartupState _classify(
    SessionReadResult result,
  ) => switch (result.status) {
    SessionReadStatus.absent => ExistingSessionStartupState.noLocalSession,
    SessionReadStatus.available =>
      result.session == null
          ? ExistingSessionStartupState.corrupt
          : result.expiredLocally
          ? ExistingSessionStartupState.localSessionExpired
          : ExistingSessionStartupState.localSessionAvailable,
    SessionReadStatus.corrupt => ExistingSessionStartupState.corrupt,
    SessionReadStatus.unavailable => ExistingSessionStartupState.unavailable,
    SessionReadStatus.incompatible => ExistingSessionStartupState.incompatible,
  };
}

class ExistingSessionBootstrapResult {
  const ExistingSessionBootstrapResult(
    this.identity,
    this.session, {
    this.scope,
  });

  final InstallationIdentityInitialization identity;
  final ExistingSessionStartupState session;

  /// Ámbito de la sesión legible (sólo memoria; null si no es legible).
  final OwnerScope? scope;
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
  final (session, scope) = await ExistingSessionStartup(
    identity: identity,
    readLocalSession: () =>
        (readSession ??
        (store) =>
            SecureSessionStore.android(identityStore: store)
                .read())(identityStore),
    readTimeout: readTimeout,
  ).loadDetailed();
  return ExistingSessionBootstrapResult(identity, session, scope: scope);
}
