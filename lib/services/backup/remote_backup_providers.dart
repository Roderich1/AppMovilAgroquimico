import 'dart:io';

import 'package:flutter/widgets.dart' show BuildContext;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../app.dart' show backupServiceProvider, databaseProvider;
import '../../data/owner_binding_store.dart';
import '../../guarded_restore.dart';
// Composición F03 + F08: el diálogo del PIN del titular (A) es la única
// forma de obtener la autorización; vive en la capa de presentación.
import '../../presentation/screens/owner_credential_screen.dart'
    show requestOwnerAuthorization;
import '../auth/auth_api_exception.dart';
import '../auth/first_activation_providers.dart';
import '../auth/local_owner_credential.dart';
import '../auth/local_owner_credential_providers.dart';
import '../sync/sync_access.dart';
import '../sync/sync_providers.dart';
import 'backup_keyring.dart';
import 'remote_backup_api.dart';
import 'remote_backup_service.dart';

/// Se construye sólo al usarse: sin URL configurada, falla cerrado.
final remoteBackupApiProvider = Provider<RemoteBackupApi>(
  (ref) => RemoteBackupApi(
    config:
        ref.watch(apiEndpointConfigProvider) ??
        (throw const AuthApiException(AuthApiErrorKind.configuration)),
    client: ref.watch(authHttpTransportProvider),
  ),
);

/// Carpeta privada de la app para las copias descargadas: no es la carpeta
/// de respaldos locales y no se ofrece en su listado.
Future<Directory> remoteBackupWorkDirectory() async => Directory(
  p.join((await getApplicationSupportDirectory()).path, 'remote_backups'),
);

final remoteBackupServiceProvider = Provider<RemoteBackupService>(
  (ref) => RemoteBackupService(
    api: () => ref.read(remoteBackupApiProvider),
    access: () => ref.read(syncControllerProvider.notifier).ensureAccess(),
    backups: ref.watch(backupServiceProvider),
    restorer: ref.watch(guardedRestoreProvider),
    ownerScope: () async => (await OwnerBindingStore(
      ref.read(databaseProvider),
    ).activeBinding())?.scope,
    workDirectory: remoteBackupWorkDirectory,
    keyring: ref.watch(backupKeyringProvider),
    onAccessRejected: () => ref.read(syncAccessHolderProvider).clear(),
  ),
);

AuthorizationPurpose _purposeOf(BackupKeyAction action) => switch (action) {
  BackupKeyAction.show => AuthorizationPurpose.showBackupRecoveryKey,
  BackupKeyAction.rotate => AuthorizationPurpose.rotateBackupRecoveryKey,
};

/// Consume en el llavero la autorización del titular (composición con F03):
/// `consumeOwnerAuthorization` de A, de un solo uso, para el propósito y la
/// clave ([keyIdHex]) exactos, contra el vínculo vigente, leído ahora, y sólo
/// si la emitió el almacén de credencial de esta instalación con su PIN
/// vigente. Lo que no sea una `OwnerAuthorization` válida falla cerrado.
final backupKeyAuthorizationConsumerProvider =
    Provider<BackupKeyAuthorizationConsumer>(
      (ref) => (authorization, action, keyIdHex) async {
        if (authorization is! OwnerAuthorization) {
          throw const BackupKeyAuthorizationRequired();
        }
        try {
          consumeOwnerAuthorization(
            authorization,
            installation: ref.read(localOwnerCredentialProvider),
            purpose: _purposeOf(action),
            subjectRef: keyIdHex,
            current: await ref.read(ownerBindingContextReaderProvider)(),
            now: DateTime.now(),
          );
        } on OwnerAuthorizationRejected {
          throw const BackupKeyAuthorizationRequired();
        }
      },
    );

/// Llavero de claves de recuperación del respaldo, en el almacén seguro.
final backupKeyringProvider = Provider<BackupKeyring>(
  (ref) => BackupKeyring(
    const SecureStorageBackupKeyVault(),
    consumeAuthorization: ref.watch(backupKeyAuthorizationConsumerProvider),
  ),
);

/// Pide al titular su PIN local (`requestOwnerAuthorization` de A) para
/// volver a mostrar o cambiar la clave de recuperación (F08-ADR-003 §3.3) y
/// devuelve la autorización sin consumir; null si se cancela o no hay PIN. El
/// PIN sólo autoriza: nunca interviene en la derivación de la clave. La
/// consume el llavero ([backupKeyAuthorizationConsumerProvider]).
typedef BackupKeyAuthorizer = Future<Object?> Function(
  BuildContext context,
  WidgetRef ref,
  BackupKeyAction action,
  String keyIdHex,
);

final backupKeyAuthorizerProvider = Provider<BackupKeyAuthorizer>(
  (_) =>
      (context, ref, action, keyIdHex) => requestOwnerAuthorization(
        context,
        ref,
        purpose: _purposeOf(action),
        subjectRef: keyIdHex,
        title: switch (action) {
          BackupKeyAction.show => 'Ver la clave de recuperación',
          BackupKeyAction.rotate => 'Cambiar la clave de recuperación',
        },
        effects: switch (action) {
          BackupKeyAction.show =>
            'Se mostrará en pantalla la clave que descifra sus respaldos. Nadie '
                'más debería verla.',
          BackupKeyAction.rotate =>
            'Se creará una clave nueva para los próximos respaldos. Conserve la '
                'anterior: las copias ya subidas la siguen necesitando.',
        },
        // F03 §4 bis.6 (C-5): al volver de configurar el PIN, la misma clave
        // activa. F08 ya informa si no hay autorización: sin doble mensaje.
        revalidate: () async {
          final active = await ref.read(backupKeyringProvider).activeKey();
          return active?.keyId == keyIdHex ? null : 'la clave activa cambió';
        },
        announceReturn: false,
      ),
);
