import 'dart:io';

import 'package:flutter/widgets.dart' show BuildContext;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../app.dart' show backupServiceProvider, databaseProvider;
import '../../data/owner_binding_store.dart';
import '../../guarded_restore.dart';
import '../auth/auth_api_exception.dart';
import '../auth/first_activation_providers.dart';
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

/// Llavero de claves de recuperación del respaldo, en el almacén seguro.
final backupKeyringProvider = Provider<BackupKeyring>(
  (ref) => BackupKeyring(const SecureStorageBackupKeyVault()),
);

enum BackupKeyAction { show, rotate }

/// Autoriza volver a mostrar o cambiar la clave de recuperación
/// (F08-ADR-003 §3.3). La composición lo conecta con la credencial local del
/// titular (`LocalOwnerCredential.verify` de A, propósitos
/// SHOW_BACKUP_RECOVERY_KEY y ROTATE_BACKUP_RECOVERY_KEY, `subjectRef` = el
/// identificador de la clave en hex). Esa credencial sólo autoriza: nunca
/// interviene en la derivación de la clave. Sin conectar, falla cerrado.
typedef BackupKeyAuthorizer = Future<bool> Function(
  BuildContext context,
  BackupKeyAction action,
  String keyIdHex,
);

final backupKeyAuthorizerProvider = Provider<BackupKeyAuthorizer>(
  (ref) =>
      (context, action, keyIdHex) async => false,
);
