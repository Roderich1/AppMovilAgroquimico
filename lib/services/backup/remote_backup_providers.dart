import 'dart:io';

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
    onAccessRejected: () => ref.read(syncAccessHolderProvider).clear(),
  ),
);
