import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/installation_access.dart' show OwnerScope;

/// Access token V2 verificado. Sólo vive en memoria: no se persiste,
/// no se registra y no viaja dentro de la outbox.
class VerifiedAccess {
  const VerifiedAccess({
    required this.accessToken,
    required this.scope,
    required this.obtainedAt,
  });

  final String accessToken;
  final OwnerScope scope;
  final DateTime obtainedAt;

  @override
  String toString() => 'VerifiedAccess(redacted)';
}

/// La renovación automática habilita únicamente las lecturas de Sindicato.
/// El worker sigue usando el acceso habilitado por una acción explícita.
class SyncAccessHolder {
  SyncAccessHolder({
    this.lifetime = const Duration(minutes: 10),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Menor que la vida del access token del servidor (15 min): se descarta
  /// antes de que Central lo rechace.
  final Duration lifetime;
  final DateTime Function() _clock;
  VerifiedAccess? _current;
  bool _readsOnly = false;
  bool Function()? _contextIsCurrent;
  bool _requiresExplicitVerification = false;

  bool get canRenewSilently => !_requiresExplicitVerification;

  void accept(String accessToken, String memberId, String tenantId) {
    _requiresExplicitVerification = false;
    _contextIsCurrent = null;
    _accept(accessToken, memberId, tenantId, readsOnly: false);
  }

  void acceptForReads(
    String accessToken,
    String memberId,
    String tenantId,
    bool Function() contextIsCurrent,
  ) {
    if (canRenewSilently) {
      _contextIsCurrent = contextIsCurrent;
      _accept(accessToken, memberId, tenantId, readsOnly: true);
    }
  }

  void _accept(
    String accessToken,
    String memberId,
    String tenantId, {
    required bool readsOnly,
  }) {
    _readsOnly = readsOnly;
    _current = VerifiedAccess(
      accessToken: accessToken,
      scope: OwnerScope(memberId: memberId, tenantId: tenantId),
      obtainedAt: _clock(),
    );
  }

  /// El usuario verificó el acceso o inició una función que lo requiere.
  bool enableGeneralAccess() {
    if (forUnionReads == null) return false;
    _readsOnly = false;
    return true;
  }

  void clear() {
    _current = null;
    _contextIsCurrent = null;
    _requiresExplicitVerification = true;
  }

  void reject(VerifiedAccess access) {
    if (identical(_current, access)) clear();
  }

  /// Credencial disponible para los flujos que requieren acción explícita.
  VerifiedAccess? get current => _readsOnly ? null : forUnionReads;

  VerifiedAccess? get forUnionReads {
    final value = _current;
    if (value == null) return null;
    if (_contextIsCurrent?.call() == false ||
        _clock().difference(value.obtainedAt) >= lifetime) {
      _current = null;
      _contextIsCurrent = null;
      return null;
    }
    return value;
  }
}

/// Una sola credencial en memoria por proceso.
final syncAccessHolderProvider = Provider<SyncAccessHolder>(
  (ref) => SyncAccessHolder(),
);
