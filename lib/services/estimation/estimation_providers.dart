// Estimación del consumo en el teléfono (F12-EST-07-MOB, MOB #164): consulta
// con conexión (perfil FARMER), descarga explícita y copia en SQLite.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart' show databaseProvider;
import '../../data/app_log.dart';
import '../../data/estimation_copy_store.dart';
import '../../data/owner_binding_store.dart';
import '../../domain/estimation/farmer_estimation.dart';
import '../../domain/installation_access.dart';
import '../../domain/sync/central_references.dart';
import '../../installation_access.dart';
import '../auth/auth_api_exception.dart';
import '../auth/existing_session_providers.dart';
import '../auth/existing_session_startup.dart';
import '../auth/first_activation_providers.dart';
import '../auth/remote_session_coordinator.dart' show RemoteSessionPhase;
import '../auth/remote_session_providers.dart';
import '../sync/sync_access.dart';
import '../sync/sync_api.dart' show SyncQueryException;
import '../sync/sync_providers.dart';
import 'estimation_api.dart';

final estimationApiProvider = Provider<EstimationApi>((ref) {
  if (ref.watch(apiEndpointConfigProvider) == null) {
    throw const AuthApiException(AuthApiErrorKind.configuration);
  }
  return EstimationApi(ref.watch(authHttpClientProvider));
});

final estimationCopyStoreProvider = Provider<EstimationCopyStore>(
  (ref) => EstimationCopyStore(ref.watch(databaseProvider)),
);

/// La identidad que puede leer la copia: instalación activada, sesión segura
/// legible del mismo Member y sindicato que el titular vigente. Sin ella, null.
Future<EstimationIdentity?> currentEstimationIdentity(Ref ref) async {
  if (ref.read(installationAccessProvider) !=
      InstallationAccessState.activated) {
    return null;
  }
  final scope = ref.read(installationAccessProvider.notifier).sessionScope;
  if (scope == null) return null;
  final binding = await OwnerBindingStore(ref.read(databaseProvider))
      .activeBinding();
  if (binding == null || binding.scope != scope) return null;
  return EstimationIdentity(
    memberId: scope.memberId,
    tenantId: scope.tenantId,
    bindingId: binding.id,
  );
}

/// Por qué no se consulta con conexión.
enum EstimationUnavailable {
  /// Sin conexión o sin servicio configurado: se puede leer la copia.
  offline,

  /// La sesión necesita volver a verificarse o el servidor la rechazó: no se
  /// ofrece la copia como alternativa.
  sessionRejected,

  /// La instalación no está activada para el titular vigente.
  noIdentity,
}

class EstimationUnavailableException implements Exception {
  const EstimationUnavailableException(this.reason);
  final EstimationUnavailable reason;
}

/// Lo que se hizo ante un rechazo del servidor.
enum EstimationRejection {
  /// 401: la sesión ya no vale. Copias borradas.
  session,

  /// 403 o un perfil que no es el del Agricultor. Copias borradas.
  permission,

  /// 409 POLICY_PENDING. Copias borradas.
  policy,

  /// 404: la campaña no existe o es de otro sindicato. Su copia, borrada.
  notFound,
}

class EstimationRejectedException implements Exception {
  const EstimationRejectedException(this.rejection, {this.discarded = true});
  final EstimationRejection rejection;

  /// false si el borrado falló: la copia sigue sin poder leerse en esta
  /// ejecución, pero **no** se afirma borrada.
  final bool discarded;
}

class EstimationService {
  EstimationService(this._ref);

  final Ref _ref;

  /// Tras un fallo al invalidar (SQLite no escribió nada), ninguna copia se
  /// lee mientras dure esta ejecución de la aplicación.
  bool _blocked = false;

  EstimationCopyStore get _store => _ref.read(estimationCopyStoreProvider);

  Future<EstimationIdentity?> identity() => currentEstimationIdentity(_ref);

  /// Copias legibles para la identidad vigente. Antes elimina las que no son
  /// suyas (ya no eran legibles).
  Future<List<StoredEstimationCopy>> readableCopies() async {
    final identity = await this.identity();
    try {
      await _store.discardForeign(identity);
    } on Object catch (error) {
      AppLog.error('No se pudo limpiar copias ajenas (${error.runtimeType})');
    }
    if (_blocked) return const [];
    return _store.readable(identity);
  }

  /// Acceso en línea por acción explícita del Agricultor.
  Future<(EstimationIdentity, VerifiedAccess)> _access() async {
    final identity = await this.identity();
    if (identity == null) {
      throw const EstimationUnavailableException(
        EstimationUnavailable.noIdentity,
      );
    }
    if (_ref.read(apiEndpointConfigProvider) == null) {
      throw const EstimationUnavailableException(EstimationUnavailable.offline);
    }
    var access = _ref.read(syncAccessHolderProvider).current;
    if (access == null) {
      final verified = await _ref
          .read(remoteSessionProvider.notifier)
          .verifyOnline();
      access = _ref.read(syncAccessHolderProvider).current;
      if (verified.phase != RemoteSessionPhase.remoteAvailable ||
          access == null) {
        throw EstimationUnavailableException(switch (verified.phase) {
          RemoteSessionPhase.outcomeUnknown ||
          RemoteSessionPhase.configurationUnavailable =>
            EstimationUnavailable.offline,
          _ => EstimationUnavailable.sessionRejected,
        });
      }
    }
    if (access.scope.memberId != identity.memberId ||
        access.scope.tenantId != identity.tenantId) {
      throw const EstimationUnavailableException(
        EstimationUnavailable.sessionRejected,
      );
    }
    return (identity, access);
  }

  /// Campañas del sindicato, para elegir la campaña objetivo.
  Future<List<CentralCampaign>> campaigns() async {
    final (_, access) = await _access();
    try {
      final references = await _ref
          .read(syncApiProvider)
          .references(access.accessToken);
      return references.campaigns;
    } on SyncQueryException catch (error) {
      if (error.statusCode == null) {
        throw const EstimationUnavailableException(
          EstimationUnavailable.offline,
        );
      }
      if (error.authRequired || error.forbidden) {
        _ref.read(syncAccessHolderProvider).clear();
        throw const EstimationUnavailableException(
          EstimationUnavailable.sessionRejected,
        );
      }
      rethrow;
    }
  }

  /// Los resultados permitidos con conexión (perfil FARMER).
  Future<FarmerResults> results(String campaignRef) async {
    final (_, access) = await _access();
    try {
      return await _ref
          .read(estimationApiProvider)
          .results(campaignRef, access.accessToken);
    } on EstimationQueryException catch (error) {
      throw await _rejected(error, campaignRef);
    }
  }

  /// Descarga explícita y copia. El acceso se toma **antes** de pedirla: si
  /// al responder ya no es el mismo (cierre de sesión, cambio de titular,
  /// rechazo, restauración), la respuesta no se guarda para nadie.
  Future<(EstimationSaveOutcome, StoredEstimationCopy?)> download(
    String campaignRef,
  ) async {
    final (identity, access) = await _access();
    final grant = await _store.grant(identity);
    final FarmerDownloadResponse response;
    try {
      response = await _ref
          .read(estimationApiProvider)
          .download(campaignRef, access.accessToken);
    } on EstimationQueryException catch (error) {
      throw await _rejected(error, campaignRef);
    }
    final outcome = await _store.save(
      grant,
      response.download,
      response.payload,
    );
    return (
      outcome,
      _blocked ? null : await _store.read(identity, campaignRef),
    );
  }

  /// Un rechazo nunca deja la copia como alternativa: se borra la afectada
  /// (todas, salvo con un 404) y se renueva el acceso.
  Future<Object> _rejected(
    EstimationQueryException error,
    String campaignRef,
  ) async {
    final EstimationRejection? rejection = switch (error) {
      _ when error.sessionRejected => EstimationRejection.session,
      _ when error.forbidden || error.invalidResponse =>
        EstimationRejection.permission,
      _ when error.policyPending => EstimationRejection.policy,
      _ when error.notFound => EstimationRejection.notFound,
      _ => null,
    };
    if (rejection == null) {
      return error.unreachable
          ? const EstimationUnavailableException(EstimationUnavailable.offline)
          : error;
    }
    if (rejection == EstimationRejection.session ||
        rejection == EstimationRejection.permission) {
      _ref.read(syncAccessHolderProvider).clear();
    }
    try {
      if (rejection == EstimationRejection.notFound) {
        await _store.discardCampaign(campaignRef);
      } else {
        await _store.discardAll();
      }
      return EstimationRejectedException(rejection);
    } on Object catch (failure) {
      AppLog.error('No se pudo borrar la copia (${failure.runtimeType})');
      _blocked = true;
      return EstimationRejectedException(rejection, discarded: false);
    }
  }
}

final estimationServiceProvider = Provider<EstimationService>(
  EstimationService.new,
);

/// Descarta la copia al cerrar la sesión y elimina la de otra identidad o
/// titular cuando cambia el acceso de la instalación. La lectura ya exige la
/// identidad vigente; esto sólo la elimina físicamente.
final estimationCopyGuardProvider = Provider<void>((ref) {
  Future<void> run(Future<void> Function() body) async {
    try {
      await body();
    } on Object catch (error) {
      AppLog.error('No se pudo descartar la copia (${error.runtimeType})');
    }
  }

  ref.listen(runtimeSessionTransitionProvider, (_, next) {
    if (next == ExistingSessionStartupState.noLocalSession) {
      unawaited(run(() => ref.read(estimationCopyStoreProvider).discardAll()));
    }
  });
  ref.listen(installationAccessProvider, (_, next) {
    if (next == null) return;
    unawaited(
      run(() async {
        final identity = await currentEstimationIdentity(ref);
        await ref.read(estimationCopyStoreProvider).discardForeign(identity);
      }),
    );
  });
});
