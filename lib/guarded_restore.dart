// Restauración protegida (RU-11, RF-01; v1.5 §3.11: recuperación del
// propietario y «copia de otro propietario: acceso denegado»).
//
// Une el respaldo local con la política de activación:
//   1. La sustitución ocurre en exclusiva: las escrituras en curso terminan
//      antes y ninguna nueva entra hasta el final.
//   2. La propiedad de la copia se comprueba sobre la base que se va a copiar
//      y antes de reemplazar nada. Una copia de otro Member/tenant, o cuya
//      propiedad no se puede leer, deja la base actual intacta.
//   3. La autorización se recalcula con la base resultante antes de volver a
//      admitir escrituras. Si el recálculo falla, queda null (falla cerrado).
// Una copia histórica sin vínculo se restaura como histórica: no se le
// atribuye titular. Restaurar no publica ni reasigna intenciones: no escribe
// vínculos ni colas; sólo registra la instalación actual si la sesión legible
// es del mismo Member que el vínculo restaurado (reactivación).
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/backup_service.dart';
import 'data/owner_binding_store.dart';
import 'domain/installation_access.dart';
import 'domain/restore_ownership.dart';
import 'installation_access.dart';
import 'services/auth/existing_session_providers.dart';

class GuardedRestoreOutcome {
  const GuardedRestoreOutcome(this.result, this.access);

  final BackupRestoreResult result;

  /// Estado de acceso con la base restaurada; null si no se pudo comprobar
  /// (las operaciones quedan bloqueadas hasta reintentar).
  final InstallationAccessState? access;
}

class GuardedRestore {
  GuardedRestore(this._ref);

  final Ref _ref;

  Future<RestoreContext> _context() async {
    final controller = _ref.read(installationAccessProvider.notifier);
    final current = await OwnerBindingStore(_ref.read(databaseProvider))
        .activeBinding();
    return RestoreContext(
      currentBinding: current?.scope,
      session: sessionConditionOf(_ref.read(effectiveLocalSessionProvider)),
      sessionScope: controller.sessionScope,
      currentInstallationRef: _ref.read(installationRefProvider),
    );
  }

  /// Qué ocurriría al restaurar [path], sin modificar nada: para avisar o
  /// rechazar antes de pedir confirmación.
  Future<RestoreOwnershipVerdict> preview(String path) async =>
      evaluateRestoreOwnership(
        await _ref.read(backupServiceProvider).inspectOwnership(path),
        await _context(),
      );

  Future<GuardedRestoreOutcome> restore(
    String path, {
    @visibleForTesting Future<void> Function()? afterReplace,
  }) {
    final database = _ref.read(databaseProvider);
    final backup = _ref.read(backupServiceProvider);
    final access = _ref.read(installationAccessProvider.notifier);
    return database.replacement.replace(() async {
      final context = await _context();
      try {
        final result = await backup.restore(
          path,
          verifyOwnership: (ownership) async {
            final verdict = evaluateRestoreOwnership(ownership, context);
            if (!verdict.accepted) {
              throw BackupOwnershipRejectedException(
                verdict.message,
                verdict.rejection!,
              );
            }
          },
          afterReplace: afterReplace,
        );
        return GuardedRestoreOutcome(
          result,
          await access.recomputeAfterReplacement(),
        );
      } on Object {
        // Rechazada o deshecha: la base es la anterior, pero la autorización
        // se recalcula igualmente antes de volver a admitir escrituras.
        await access.recomputeAfterReplacement();
        rethrow;
      }
    });
  }
}

final guardedRestoreProvider = Provider<GuardedRestore>(GuardedRestore.new);
