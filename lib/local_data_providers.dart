import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/agro_repository.dart';
import 'data/app_database.dart';
import 'data/backup_service.dart';
import 'data/farmer_operation_gate.dart';
import 'data/ind_c_chacos_reads.dart';
import 'domain/agro_gateway.dart';
import 'installation_access.dart';
import 'services/auth/local_owner_credential_providers.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

/// El repositorio de la app aplica la política de activación en cada
/// escritura (#76). Las pruebas que no tratan la activación sobrescriben este
/// proveedor con un repositorio sin restricción.
final repositoryProvider = Provider<AgroRepository>(
  (ref) => AgroRepository(
    ref.watch(databaseProvider),
    gate: FarmerOperationGate(() => ref.read(installationAccessProvider)),
    // RF-13/RF-03: consume sólo autorizaciones vigentes emitidas en esta instalación.
    ownerCredential: () => ref.read(localOwnerCredentialProvider),
  ),
);

final agroGatewayProvider = Provider<AgroGateway>(
  (ref) => ref.watch(repositoryProvider),
);

final indChacosGatewayProvider = Provider<IndCChacosGateway>(
  (ref) => DataIndCChacosGateway(ref.watch(repositoryProvider)),
);

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(ref.watch(databaseProvider)),
);
