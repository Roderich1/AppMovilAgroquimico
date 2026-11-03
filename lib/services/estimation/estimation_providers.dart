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
import 'estimation_retirement_marker.dart';

final estimationApiProvider = Provider<EstimationApi>((ref) {
  if (ref.watch(apiEndpointConfigProvider) == null) {
    throw const AuthApiException(AuthApiErrorKind.configuration);
  }
  return EstimationApi(ref.watch(authHttpClientProvider));
});

final estimationCopyStoreProvider = Provider<EstimationCopyStore>(
  (ref) => EstimationCopyStore(ref.watch(databaseProvider)),
);

final estimationRetirementMarkerProvider = Provider<EstimationRetirementMarker>(
  (ref) => const SecureStorageEstimationRetirementMarker(),
);

/// Registra una retirada **antes** del borrado físico. Si SQLite no la
/// admite, deja la marca persistente del almacenamiento seguro. Devuelve
/// `false` si tampoco se pudo dejar la marca: entonces sólo queda bloquear
/// la lectura en memoria.
Future<bool> _retire(
  Ref ref,
  Future<void> Function(EstimationCopyStore) step,
) async {
  try {
    await step(ref.read(estimationCopyStoreProvider));
    return true;
  } on Object catch (error) {
    AppLog.error('No se pudo registrar la retirada (${error.runtimeType})');
  }
  try {
    await ref.read(estimationRetirementMarkerProvider).setPending();
    return true;
  } on Object catch (error) {
    AppLog.error(
      'No se pudo dejar la marca de retirada (${error.runtimeType})',
    );
    return false;
  }
}

/// Borrado físico de lo ya retirado o ajeno. Si falla, queda pendiente: la
/// lectura ya no lo admite y el siguiente intento lo borra.
Future<bool> _purge(Ref ref, EstimationIdentity? identity) async {
  try {
    await ref.read(estimationCopyStoreProvider).purge(identity);
    return true;
  } on Object catch (error) {
    AppLog.error('Borrado de la copia pendiente (${error.runtimeType})');
    return false;
  }
}

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

  /// Hay una retirada pendiente que no se pudo registrar: sin contexto local
  /// admisible no se guarda ni se muestra ninguna copia.
  noLocalContext,
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

  /// false si el borrado físico no se completó: la retirada ya impide leer
  /// la copia (también tras reiniciar), pero **no** se afirma borrada.
  final bool discarded;
}

class EstimationService {
  EstimationService(this._ref);

  final Ref _ref;

  /// Sólo si no se pudo registrar una retirada ni dejar su marca: ninguna
  /// copia se lee mientras dure esta ejecución de la aplicación.
  bool _blocked = false;

  EstimationCopyStore get _store => _ref.read(estimationCopyStoreProvider);

  Future<EstimationIdentity?> identity() => currentEstimationIdentity(_ref);

  /// `true` si hay un contexto local admisible: sin retirada pendiente, o con
  /// la pendiente ya registrada ahora en SQLite. Si la marca no se puede leer
  /// o la retirada sigue sin registrarse, `false`: no se muestran cifras.
  Future<bool> _admissibleContext() async {
    if (_blocked) return false;
    final marker = _ref.read(estimationRetirementMarkerProvider);
    try {
      if (!await marker.isPending()) return true;
      await _store.retireAll();
      await marker.clear();
      return true;
    } on Object catch (error) {
      AppLog.error('Contexto de la copia no admisible (${error.runtimeType})');
      return false;
    }
  }

  /// Copias legibles para la identidad vigente, en un contexto admisible.
  /// Antes intenta borrar lo retirado o ajeno (si falla, queda pendiente).
  Future<List<StoredEstimationCopy>> readableCopies() async {
    final identity = await this.identity();
    if (!await _admissibleContext()) return const [];
    await _purge(_ref, identity);
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
    if (!await _admissibleContext()) {
      throw const EstimationUnavailableException(
        EstimationUnavailable.noLocalContext,
      );
    }
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

  /// Un rechazo nunca deja la copia como alternativa. Primero se registra la
  /// retirada (todas, o la campaña con un 404) y después se intenta borrar.
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
    final retired = await _retire(
      _ref,
      (store) => rejection == EstimationRejection.notFound
          ? store.retireCampaign(campaignRef)
          : store.retireAll(),
    );
    if (!retired) _blocked = true;
    final deleted = retired && await _purge(_ref, await identity());
    return EstimationRejectedException(rejection, discarded: deleted);
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
      unawaited(
        run(() async {
          if (!await _retire(ref, (store) => store.retireAll())) {
            ref.read(estimationServiceProvider)._blocked = true;
          }
          await _purge(ref, null);
        }),
      );
    }
  });
  ref.listen(installationAccessProvider, (_, next) {
    if (next == null) return;
    unawaited(
      run(() async => _purge(ref, await currentEstimationIdentity(ref))),
    );
  });
});
