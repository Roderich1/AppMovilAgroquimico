import 'farmer_estimation.dart';

/// Identidad propietaria: Member, sindicato y vínculo de titular vigentes.
class EstimationIdentity {
  const EstimationIdentity({
    required this.memberId,
    required this.tenantId,
    required this.bindingId,
  });

  final String memberId;
  final String tenantId;
  final int bindingId;

  @override
  bool operator ==(Object other) =>
      other is EstimationIdentity &&
      other.memberId == memberId &&
      other.tenantId == tenantId &&
      other.bindingId == bindingId;

  @override
  int get hashCode => Object.hash(memberId, tenantId, bindingId);

  @override
  String toString() => 'EstimationIdentity(redacted)';
}

/// Lo vigente al pedir una descarga: sólo con esto se puede guardar.
class EstimationCopyGrant {
  const EstimationCopyGrant(this.identity, this.contextId, this.generation);
  final EstimationIdentity identity;
  final String contextId;
  final int generation;
}

enum EstimationSaveOutcome {
  saved,

  /// Ya hay una copia igual o más reciente de esa campaña: se conserva.
  keptNewer,

  /// La sesión, el titular o el contexto cambiaron durante la descarga.
  accessChanged,

  /// La campaña se retiró (404) después de pedir la descarga.
  targetRetired,

  /// La respuesta no es de esta identidad o de este sindicato.
  otherSubject,
}

class StoredEstimationCopy {
  const StoredEstimationCopy({required this.download, required this.savedAt});

  final FarmerDownload download;

  /// Hora del teléfono al guardar; la fecha de descarga es la del servidor.
  final DateTime savedAt;
}
