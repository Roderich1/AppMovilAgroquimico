// Modalidad de inventario propio o compartido (RF-06, CU-05, RN-17).
//
// Un único dominio y una única base para ambas modalidades. Cambiar de
// modalidad nunca borra ni reasigna datos; reducir a propio se bloquea
// mientras haya información activa de terceros (v1.5 CU-05 A2/E1).

enum OperationMode {
  personal('PERSONAL'),
  shared('SHARED');

  const OperationMode(this.code);
  final String code;

  /// Modalidad por defecto de una base sin la clave: compartida, que
  /// conserva el comportamiento anterior a F04.
  static const OperationMode defaultMode = OperationMode.shared;

  static OperationMode fromCode(String? code) => switch (code) {
    'PERSONAL' => OperationMode.personal,
    'SHARED' => OperationMode.shared,
    _ => defaultMode,
  };
}

/// Información activa de terceros (personas distintas del titular) que impide
/// reducir a inventario propio con seguridad.
class ThirdPartyActivity {
  const ThirdPartyActivity({
    this.personsWithStock = const {},
    this.openPlanIds = const {},
    this.personsWithAccountBalance = const {},
  });

  /// Personas con existencias distintas de cero en algún producto.
  final Set<int> personsWithStock;

  /// Planes DRAFT/PLANNED sobre chacos de terceros.
  final Set<int> openPlanIds;

  /// Personas con saldo de cuenta distinto de cero.
  final Set<int> personsWithAccountBalance;

  bool get isEmpty =>
      personsWithStock.isEmpty &&
      openPlanIds.isEmpty &&
      personsWithAccountBalance.isEmpty;
}

enum ModeTransitionBlock {
  /// No hay titular vinculado: el modo propio no tiene a quién pertenecer.
  ownerRequired,

  /// Hay información activa de terceros.
  thirdPartyActivity,
}

class ModeTransitionDecision {
  const ModeTransitionDecision._(
    this.from,
    this.to,
    this.blocks,
    this.activity,
  );

  final OperationMode from;
  final OperationMode to;
  final Set<ModeTransitionBlock> blocks;
  final ThirdPartyActivity activity;

  bool get allowed => blocks.isEmpty;
  bool get isNoop => from == to;
}

/// Evalúa una transición. PERSONAL → SHARED siempre se admite; SHARED →
/// PERSONAL exige titular y ausencia de información activa de terceros.
ModeTransitionDecision evaluateModeTransition({
  required OperationMode from,
  required OperationMode to,
  required bool hasOwner,
  required ThirdPartyActivity activity,
}) {
  final blocks = <ModeTransitionBlock>{};
  if (to == OperationMode.personal && from != OperationMode.personal) {
    if (!hasOwner) blocks.add(ModeTransitionBlock.ownerRequired);
    if (!activity.isEmpty) blocks.add(ModeTransitionBlock.thirdPartyActivity);
  }
  return ModeTransitionDecision._(from, to, blocks, activity);
}
