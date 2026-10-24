import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart' show repositoryProvider;
import '../../data/owner_binding_store.dart';
import '../../installation_access.dart';
import 'local_owner_credential.dart';
import 'remote_session_providers.dart';

final credentialStorageProvider = Provider<CredentialStorage>(
  (ref) => AndroidCredentialStorage(),
);

final localOwnerCredentialProvider = Provider<LocalOwnerCredential>(
  (ref) => LocalOwnerCredential(
    storage: ref.watch(credentialStorageProvider),
    onlineVerification: ref.watch(ownerOnlineVerificationProvider),
  ),
);

/// El vínculo de titular vigente, leído de SQLite (null si no hay).
final ownerBindingContextReaderProvider =
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
final ownerOnlineVerificationProvider = Provider<OwnerOnlineVerification>(
  (ref) => OwnerOnlineVerification(
    confirmAccount: (email, password) => ref
        .read(remoteSessionProvider.notifier)
        .confirmAccount(email: email, password: password),
    readSessionScope: () => ref.read(sessionScopeReaderProvider)(),
  ),
);
