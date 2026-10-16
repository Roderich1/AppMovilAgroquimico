import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart' show databaseProvider;
import '../../data/farmer_operation_gate.dart';
import '../../data/owner_binding_store.dart';
import '../../data/sync/central_binding_store.dart';
import '../../data/sync/consumption_publisher.dart';
import '../../data/sync/declared_need_store.dart';
import '../../data/sync/sync_outbox_store.dart';
import '../../domain/sync/central_references.dart';
import '../../domain/sync/sync_wire.dart' show OperationView;
import '../../installation_access.dart' show installationAccessProvider;
import '../auth/auth_api_exception.dart';
import '../auth/first_activation_providers.dart';
import '../auth/remote_session_coordinator.dart' show RemoteSessionPhase;
import '../auth/remote_session_providers.dart';
import 'sync_access.dart';
import 'sync_api.dart';
import 'sync_worker.dart';

FarmerOperationGate _gate(Ref ref) =>
    FarmerOperationGate(() => ref.read(installationAccessProvider));

final syncOutboxStoreProvider = Provider<SyncOutboxStore>(
  (ref) => SyncOutboxStore(ref.watch(databaseProvider)),
);

final centralBindingStoreProvider = Provider<CentralBindingStore>(
  (ref) => CentralBindingStore(ref.watch(databaseProvider), gate: _gate(ref)),
);

final declaredNeedStoreProvider = Provider<DeclaredNeedStore>(
  (ref) => DeclaredNeedStore(ref.watch(databaseProvider), gate: _gate(ref)),
);

final consumptionPublisherProvider = Provider<ConsumptionPublisher>(
  (ref) => ConsumptionPublisher(ref.watch(databaseProvider), gate: _gate(ref)),
);

/// Se construye sólo al enviar: sin URL configurada, falla cerrado.
final syncApiProvider = Provider<SyncApi>((ref) {
  if (ref.watch(apiEndpointConfigProvider) == null) {
    throw const AuthApiException(AuthApiErrorKind.configuration);
  }
  return SyncApi(ref.watch(authHttpClientProvider));
});

final syncWorkerProvider = Provider<SyncWorker>(
  (ref) => SyncWorker(
    outbox: ref.watch(syncOutboxStoreProvider),
    owners: OwnerBindingStore(ref.watch(databaseProvider)),
    api: () => ref.read(syncApiProvider),
    access: ref.watch(syncAccessHolderProvider),
  ),
);

class SyncState {
  const SyncState({
    this.summary,
    this.blocker,
    this.busy = false,
    this.message,
  });

  final SyncQueueSummary? summary;
  final SyncBlocker? blocker;
  final bool busy;

  /// Último aviso para el agricultor; nunca contiene datos ni credenciales.
  final String? message;

  SyncState copyWith({
    SyncQueueSummary? summary,
    SyncBlocker? blocker,
    bool clearBlocker = false,
    bool? busy,
    String? message,
  }) => SyncState(
    summary: summary ?? this.summary,
    blocker: clearBlocker ? null : (blocker ?? this.blocker),
    busy: busy ?? this.busy,
    message: message,
  );
}

String blockerMessage(SyncBlocker blocker) => switch (blocker) {
  SyncBlocker.noOwner =>
    'Elija el titular de estos datos para enviar al sindicato.',
  SyncBlocker.accessRequired =>
    'Verifique el acceso en línea para enviar. Sus datos siguen guardados.',
  SyncBlocker.ownerMismatch =>
    'La cuenta en sesión no es la del titular: no se envía nada.',
  SyncBlocker.forbidden =>
    'El sindicato no autorizó esta cuenta o este dispositivo. Los envíos '
        'quedan pausados; nada se borró.',
  SyncBlocker.versionMismatch =>
    'Esta versión de la aplicación no es compatible con el sindicato. '
        'Actualice la aplicación; los envíos quedan guardados.',
  SyncBlocker.unreachable =>
    'No se pudo confirmar el envío. Se reintentará con el mismo contenido.',
  SyncBlocker.throttled => 'El sindicato pidió esperar. Se reintentará.',
  SyncBlocker.replacementInProgress =>
    'Se está restaurando un respaldo. Intente después.',
};

final syncControllerProvider = NotifierProvider<SyncController, SyncState>(
  SyncController.new,
);

/// Disparadores del worker: al iniciar, tras encolar, «Sincronizar ahora» y
/// un temporizador mientras la app está abierta. Sin acceso verificado no
/// envía nada ni hace llamadas de red: la verificación (refresh) es siempre
/// una acción explícita del agricultor.
class SyncController extends Notifier<SyncState> {
  static const period = Duration(minutes: 1);
  Timer? _timer;

  @override
  SyncState build() {
    ref.onDispose(stopForeground);
    return const SyncState();
  }

  /// Al iniciar la app o volver a primer plano: un ciclo y el temporizador.
  /// Sin acceso verificado, el ciclo no hace ninguna llamada de red.
  void startForeground() {
    _timer ??= Timer.periodic(period, (_) => unawaited(kick()));
    unawaited(kick());
  }

  /// En segundo plano no se envía (no hay workers del sistema en v1).
  void stopForeground() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> refreshSummary() async {
    try {
      final summary = await ref.read(syncOutboxStoreProvider).summary();
      state = state.copyWith(summary: summary, message: state.message);
    } on Object {
      // Sin base legible todavía: el indicador simplemente no se muestra.
    }
  }

  /// Ciclo automático: sólo envía si hay acceso verificado y vigente.
  Future<SyncRunReport?> kick() async {
    if (state.busy) return null;
    state = state.copyWith(busy: true, message: state.message);
    try {
      final report = await ref.read(syncWorkerProvider).run();
      state = state.copyWith(
        blocker: report.blocker,
        clearBlocker: report.blocker == null,
        busy: false,
        message: report.blocker == null
            ? null
            : blockerMessage(report.blocker!),
      );
      return report;
    } on Object {
      state = state.copyWith(busy: false, message: null);
      return null;
    } finally {
      await refreshSummary();
    }
  }

  /// «Sincronizar ahora»: si no hay acceso vigente, lo verifica primero (el
  /// agricultor lo pidió) y reanuda lo pausado por autorización del mismo
  /// titular.
  Future<SyncRunReport?> syncNow() async {
    if (ref.read(syncAccessHolderProvider).current == null) {
      final verified = await ref
          .read(remoteSessionProvider.notifier)
          .verifyOnline();
      if (verified.phase != RemoteSessionPhase.remoteAvailable) {
        state = state.copyWith(message: verified.safeMessage);
        await refreshSummary();
        return null;
      }
    }
    await resumeAfterVerification();
    return kick();
  }

  /// Tras una verificación correcta: lo pausado por un 403 vuelve a la cola
  /// si la cuenta es la del titular.
  Future<void> resumeAfterVerification() async {
    final access = ref.read(syncAccessHolderProvider).current;
    final owner = await OwnerBindingStore(ref.read(databaseProvider))
        .activeBinding();
    if (access == null || owner == null || access.scope != owner.scope) return;
    await ref.read(syncOutboxStoreProvider).resumeAuthorizationPaused(owner.id);
  }

  /// El titular libera las intenciones que llegaron con una restauración.
  /// Exige el acceso verificado en línea de la cuenta del titular (lo
  /// verifica si hace falta): sin esa verificación no se libera nada, y abrir
  /// la app no lo hace por sí solo (F05 §11, F06 §8).
  Future<int> releaseRestored() async {
    final owner = await OwnerBindingStore(ref.read(databaseProvider))
        .activeBinding();
    if (owner == null) {
      state = state.copyWith(message: blockerMessage(SyncBlocker.noOwner));
      return 0;
    }
    final VerifiedAccess access;
    try {
      access = await ensureAccess();
    } on SyncAccessUnavailable catch (error) {
      state = state.copyWith(message: error.message);
      return 0;
    }
    if (access.scope != owner.scope) {
      state = state.copyWith(
        message: blockerMessage(SyncBlocker.ownerMismatch),
      );
      return 0;
    }
    final released = await ref
        .read(syncOutboxStoreProvider)
        .releaseRestored(owner.id);
    await refreshSummary();
    unawaited(kick());
    return released;
  }

  /// El acceso vigente, o el resultado de verificarlo ahora: lo pidió el
  /// agricultor al abrir una función en línea (también el respaldo remoto).
  Future<VerifiedAccess> ensureAccess() async {
    final current = ref.read(syncAccessHolderProvider).current;
    if (current != null) return current;
    final verified = await ref
        .read(remoteSessionProvider.notifier)
        .verifyOnline();
    final access = ref.read(syncAccessHolderProvider).current;
    if (verified.phase != RemoteSessionPhase.remoteAvailable ||
        access == null) {
      throw SyncAccessUnavailable(verified.safeMessage);
    }
    return access;
  }

  /// Resultado y estado causal de una intención propia, para resolver un
  /// conflicto.
  Future<OperationView> operationView(String operationId) async {
    final access = await ensureAccess();
    try {
      return await ref
          .read(syncApiProvider)
          .operation(operationId, access.accessToken);
    } on SyncQueryException catch (error) {
      if (error.authRequired || error.forbidden) {
        ref.read(syncAccessHolderProvider).clear();
      }
      rethrow;
    }
  }

  /// Referencias centrales del tenant con el acceso vigente (lo verifica si
  /// hace falta). Revisa además los vínculos existentes.
  Future<CentralReferences> loadReferences() async {
    final access = await ensureAccess();
    try {
      final references = await ref
          .read(syncApiProvider)
          .references(access.accessToken);
      await ref
          .read(centralBindingStoreProvider)
          .refreshFrom(references, access.scope.tenantId);
      return references;
    } on SyncQueryException catch (error) {
      if (error.authRequired || error.forbidden) {
        ref.read(syncAccessHolderProvider).clear();
      }
      rethrow;
    }
  }
}

class SyncAccessUnavailable implements Exception {
  const SyncAccessUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}
