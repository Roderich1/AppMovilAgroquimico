import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/installation_access.dart' show OwnerScope;

/// Access token V2 verificado por una acción explícita del agricultor
/// (refresh o reautenticación, F03). Sólo vive en memoria: no se persiste,
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

/// Credencial de Sync v1 en memoria. El worker no renueva tokens por su
/// cuenta: la rotación del refresh es una acción explícita del agricultor
/// (F03), así que un 401 o un token vencido dejan la cola esperando a que
/// verifique el acceso en línea.
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

  void accept(String accessToken, String memberId, String tenantId) {
    _current = VerifiedAccess(
      accessToken: accessToken,
      scope: OwnerScope(memberId: memberId, tenantId: tenantId),
      obtainedAt: _clock(),
    );
  }

  void clear() => _current = null;

  /// La credencial vigente, o null si no hay o ya caducó localmente.
  VerifiedAccess? get current {
    final value = _current;
    if (value == null) return null;
    if (_clock().difference(value.obtainedAt) >= lifetime) {
      _current = null;
      return null;
    }
    return value;
  }
}

/// Una sola credencial en memoria por proceso.
final syncAccessHolderProvider = Provider<SyncAccessHolder>(
  (ref) => SyncAccessHolder(),
);
