/// Clasificación de la intención dictada (EVO-010, conjunto cerrado).
///
/// Por reglas y palabras clave, sin modelo ni servicio. Los pagos y las
/// consultas por voz quedan fuera de F09: se reconocen sólo para decir que no
/// se atienden, nunca para preparar un borrador.
library;

enum VoiceIntent {
  purchase,
  plan,
  application,

  /// Pago, consulta u otra cosa que F09 no atiende.
  unsupported,

  /// Varias intenciones en la misma frase.
  ambiguous,

  /// Sin palabra clave: en una pantalla de borrador se interpreta como
  /// continuación del borrador abierto.
  none,
}

const _purchase = {
  'compra',
  'compras',
  'compre',
  'compramos',
  'comprar',
  'comprado',
  'compraron',
};
const _plan = {
  'planificacion',
  'planificar',
  'planifica',
  'planificamos',
  'plan',
  'planear',
  'programar',
};
const _application = {
  'aplicacion',
  'aplicaciones',
  'aplique',
  'aplicamos',
  'aplicar',
  'aplicaron',
  'fumigue',
  'fumigamos',
  'fumigar',
  'fumigacion',
};
const _unsupported = {
  'pago',
  'pague',
  'pagar',
  'pagamos',
  'adelanto',
  'cuanto',
  'cuantos',
  'cuanta',
  'saldo',
  'debe',
  'deuda',
};

/// Clasifica palabras ya normalizadas (`tokenize`).
VoiceIntent classifyIntent(List<String> words) {
  final found = <VoiceIntent>{};
  for (final w in words) {
    if (_purchase.contains(w)) found.add(VoiceIntent.purchase);
    if (_plan.contains(w)) found.add(VoiceIntent.plan);
    if (_application.contains(w)) found.add(VoiceIntent.application);
    if (_unsupported.contains(w)) found.add(VoiceIntent.unsupported);
  }
  // «aplicar la planificación» habla de aplicar un plan: es aplicación.
  if (found.containsAll({VoiceIntent.plan, VoiceIntent.application})) {
    found.remove(VoiceIntent.plan);
  }
  if (found.isEmpty) return VoiceIntent.none;
  if (found.length > 1) return VoiceIntent.ambiguous;
  return found.single;
}
