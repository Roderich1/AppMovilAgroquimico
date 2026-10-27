// Acreditación de activación (F03 §4 bis,
// docs/architecture/F03_RECUPERACION_IDENTIDAD_LOCAL.md). Prueba en memoria de
// que el titular acaba de escribir su contraseña en la primera activación de
// esta instalación: permite crear su primer PIN sin volver a pedirla.
//
// - Nunca lleva la contraseña ni tokens; nunca se guarda ni se registra.
// - Vive sólo en el proceso: un reinicio, salir de la app o cualquier cambio
//   de cuenta, sesión, instalación o vínculo la pierde (falla cerrado).
// - Vence a los [ActivationOwnerEvidence.lifetime] por el reloj de pared o por
//   el cronómetro monotónico, lo que llegue antes.
import '../../domain/installation_access.dart'
    show OwnerScope, installationReference;

/// Identidad de una sesión segura, sin credenciales.
class SessionIdentity {
  const SessionIdentity({
    required this.accountId,
    required this.memberId,
    required this.tenantId,
    required this.sessionId,
    required this.registrationId,
    required this.installationClientId,
  });

  final String accountId;
  final String memberId;
  final String tenantId;
  final String sessionId;
  final String registrationId;
  final String installationClientId;

  OwnerScope get scope => OwnerScope(memberId: memberId, tenantId: tenantId);

  bool sameAs(SessionIdentity other) =>
      accountId == other.accountId &&
      memberId == other.memberId &&
      tenantId == other.tenantId &&
      sessionId == other.sessionId &&
      registrationId == other.registrationId &&
      installationClientId == other.installationClientId;

  @override
  String toString() => 'SessionIdentity(redacted)';
}

/// El vínculo de titular al que se ata la acreditación (o el vigente con el
/// que se compara).
class ActivationBindingRef {
  const ActivationBindingRef({
    required this.bindingId,
    required this.personId,
    required this.boundAt,
    required this.scope,
    this.active = true,
  });

  final int bindingId;
  final int personId;
  final String boundAt;
  final OwnerScope scope;
  final bool active;

  bool sameAs(ActivationBindingRef other) =>
      bindingId == other.bindingId &&
      personId == other.personId &&
      boundAt == other.boundAt &&
      scope == other.scope;

  @override
  String toString() => 'ActivationBindingRef(redacted)';
}

/// Relojes de la acreditación: el de pared y un cronómetro monotónico que
/// empieza al emitirla. Inyectables en pruebas.
class ActivationEvidenceClock {
  const ActivationEvidenceClock({
    required this.now,
    required this.startElapsed,
  });

  factory ActivationEvidenceClock.system() => ActivationEvidenceClock(
    now: DateTime.now,
    startElapsed: () {
      final watch = Stopwatch()..start();
      return () => watch.elapsed;
    },
  );

  final DateTime Function() now;
  final Duration Function() Function() startElapsed;
}

class ActivationOwnerEvidence {
  ActivationOwnerEvidence({
    required this.identity,
    required this.issuedAt,
    required Duration Function() elapsed,
  }) : _elapsed = elapsed;

  /// F03 §4 bis.3 (D-1): se baja a 5 minutos si la medición E4 da una
  /// mediana por debajo de unos 3 minutos.
  static const lifetime = Duration(minutes: 10);

  final SessionIdentity identity;
  final DateTime issuedAt;
  final Duration Function() _elapsed;
  ActivationBindingRef? _binding;

  OwnerScope get scope => identity.scope;

  String get installationRef =>
      installationReference(identity.installationClientId);

  DateTime get notAfter => issuedAt.add(lifetime);

  ActivationBindingRef? get binding => _binding;

  /// Vigente por los dos relojes; un reloj de pared anterior a la emisión
  /// también la invalida.
  bool isFresh(DateTime now) =>
      !now.isBefore(issuedAt) &&
      now.difference(issuedAt) <= lifetime &&
      _elapsed() <= lifetime;

  /// Se ata una sola vez, a un vínculo activo del mismo ámbito creado después
  /// de emitirla. false si no se puede atar.
  bool attachBinding(ActivationBindingRef binding) {
    if (_binding != null || !binding.active || binding.scope != scope) {
      return false;
    }
    final boundAt = DateTime.tryParse(binding.boundAt);
    if (boundAt == null || boundAt.isBefore(issuedAt)) return false;
    _binding = binding;
    return true;
  }

  @override
  String toString() => 'ActivationOwnerEvidence(redacted)';
}
