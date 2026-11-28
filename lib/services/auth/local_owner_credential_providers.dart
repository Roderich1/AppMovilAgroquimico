import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../local_data_providers.dart' show repositoryProvider;
import '../../data/owner_binding_store.dart';
import '../../installation_access.dart';
import 'local_owner_credential.dart';
import 'existing_session_providers.dart';
import 'remote_session_providers.dart';

final Provider<CredentialStorage> credentialStorageProvider =
    Provider<CredentialStorage>((ref) => AndroidCredentialStorage());

final Provider<LocalOwnerCredential> localOwnerCredentialProvider =
    Provider<LocalOwnerCredential>((ref) {
      final credential = LocalOwnerCredential(
        storage: ref.watch(credentialStorageProvider),
        onlineVerification: ref.watch(ownerOnlineVerificationProvider),
      );
      ref.listen(runtimeSessionTransitionProvider, (_, _) {
        credential.invalidatePasswordAuthorizations();
      });
      ref.onDispose(credential.invalidatePasswordAuthorizations);
      return credential;
    });

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

/// La acreditación en línea confirma la cuenta con un login que se cierra en
/// el acto (no la reautenticación, que sólo recupera una sesión en cuarentena)
/// y relee el ámbito de la sesión guardada.
final Provider<OwnerOnlineVerification> ownerOnlineVerificationProvider =
    Provider<OwnerOnlineVerification>(
      (ref) => OwnerOnlineVerification(
        confirmAccount: (email, password) => ref
            .read(remoteSessionProvider.notifier)
            .confirmAccount(email: email, password: password),
        readSessionScope: () => ref.read(sessionScopeReaderProvider)(),
      ),
    );
