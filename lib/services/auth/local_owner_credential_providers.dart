import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart' show repositoryProvider;
import '../../data/owner_binding_store.dart';
import '../../domain/installation_access.dart' show InstallationAccessState;
import '../../installation_access.dart';
import 'activation_owner_evidence.dart';
import 'first_activation_providers.dart';
import 'local_owner_credential.dart';
import 'remote_session_providers.dart';
import 'secure_session_store.dart';

final Provider<CredentialStorage> credentialStorageProvider =
    Provider<CredentialStorage>((ref) => AndroidCredentialStorage());

final Provider<LocalOwnerCredential> localOwnerCredentialProvider =
    Provider<LocalOwnerCredential>(
      (ref) => LocalOwnerCredential(
        storage: ref.watch(credentialStorageProvider),
        onlineVerification: ref.watch(ownerOnlineVerificationProvider),
      ),
    );

/// El vínculo de titular vigente, leído de SQLite (null si no hay).
final Provider<Future<OwnerBindingContext?> Function()>
ownerBindingContextReaderProvider =
    Provider<Future<OwnerBindingContext?> Function()>((ref) {
      return () async {
        final binding = await OwnerBindingStore(
          ref.read(repositoryProvider).appDatabase,
        ).activeBinding();
        return binding == null
            ? null
            : OwnerBindingContext(
                bindingId: binding.id,
                personId: binding.personId,
                scope: binding.scope,
              );
      };
    });

/// F03 §4 bis: el vínculo activo completo (con `boundAt`), para compararlo
/// con el que se ató a la acreditación de activación.
final Provider<Future<ActivationBindingRef?> Function()>
activeBindingRefReaderProvider =
    Provider<Future<ActivationBindingRef?> Function()>((ref) {
      return () async {
        final binding = await OwnerBindingStore(
          ref.read(repositoryProvider).appDatabase,
        ).activeBinding();
        return binding == null ? null : activationBindingRefOf(binding);
      };
    });

ActivationBindingRef activationBindingRefOf(OwnerBinding binding) =>
    ActivationBindingRef(
      bindingId: binding.id,
      personId: binding.personId,
      boundAt: binding.boundAt,
      scope: binding.scope,
      active: binding.isActive,
    );

/// F03 §4 bis: `activated_installation` de la base vigente.
final Provider<Future<String?> Function()>
activatedInstallationRefReaderProvider = Provider<Future<String?> Function()>((
  ref,
) {
  return () =>
      OwnerBindingStore(ref.read(repositoryProvider).appDatabase)
          .activatedInstallationRef();
});

/// F03 §4 bis: identidad de la sesión guardada, sin credenciales; null si no
/// se puede leer. El refresh token leído se descarta en el acto.
final Provider<Future<SessionIdentity?> Function()>
storedSessionIdentityReaderProvider =
    Provider<Future<SessionIdentity?> Function()>((ref) {
      final store = ref.watch(installationClientIdStoreProvider);
      return () async {
        final read = await SecureSessionStore.android(identityStore: store)
            .read();
        final session = read.session;
        if (read.status != SessionReadStatus.available || session == null) {
          return null;
        }
        return SessionIdentity(
          accountId: session.accountId,
          memberId: session.memberId,
          tenantId: session.tenantId,
          sessionId: session.sessionId,
          registrationId: session.registrationId,
          installationClientId: session.installationClientId,
        );
      };
    });

/// La acreditación en línea confirma la cuenta con un login que se cierra en
/// el acto (no la reautenticación, que sólo recupera una sesión en cuarentena)
/// y relee el ámbito de la sesión guardada. Con la acreditación de activación
/// (F03 §4 bis) emite, además, el comprobante del primer PIN sin contraseña.
final Provider<OwnerOnlineVerification> ownerOnlineVerificationProvider =
    Provider<OwnerOnlineVerification>(
      (ref) => OwnerOnlineVerification(
        confirmAccount: (email, password) => ref
            .read(remoteSessionProvider.notifier)
            .confirmAccount(email: email, password: password),
        readSessionScope: () => ref.read(sessionScopeReaderProvider)(),
        activation: ActivationEvidenceSource(
          // Sin activación en este proceso no hay controlador ni acreditación.
          take: () {
            try {
              return ref.exists(firstActivationProvider)
                  ? ref
                        .read(firstActivationProvider.notifier)
                        .takeActivationEvidence()
                  : null;
            } on Object {
              return null;
            }
          },
          readSessionIdentity: () =>
              ref.read(storedSessionIdentityReaderProvider)(),
          currentInstallationRef: () => ref.read(installationRefProvider),
          activatedInstallationRef: () =>
              ref.read(activatedInstallationRefReaderProvider)(),
          activeBinding: () => ref.read(activeBindingRefReaderProvider)(),
          accessActivated: () =>
              ref.read(installationAccessProvider) ==
              InstallationAccessState.activated,
        ),
      ),
    );
