/// Cuándo la sesión reabre un turno de escucha, y cuándo deja de intentarlo.
///
/// ## El problema que resuelve
///
/// Android `SpeechRecognizer` cierra la escucha por su cuenta al detectar
/// silencio, aunque el usuario sólo estuviera pensando la siguiente frase. Sin
/// continuidad, dictar una compra obligaría a pulsar el micrófono entre frase y
/// frase. Con continuidad **sin límites**, un `ERROR_CLIENT` o un `noMatch`
/// permanente convertirían la pantalla en un bucle que reabre el micrófono para
/// siempre — exactamente lo que `EVO-009-REQ-017` prohíbe.
///
/// El equilibrio es: reabrir mientras el usuario mantenga la sesión activa y los
/// turnos sean **productivos**; frenar en cuanto dejan de serlo.
///
/// Un turno es *productivo* si trajo texto. `noMatch`, `timeout` y los errores
/// recuperables no lo son. Un turno productivo pone a cero el contador, de modo
/// que una pausa larga en mitad del dictado no gasta el presupuesto de la
/// sesión entera.
class VoiceContinuityPolicy {
  const VoiceContinuityPolicy({
    this.maxConsecutiveUnproductive = 3,
    this.maxTurns = 60,
    this.initialBackoff = const Duration(milliseconds: 400),
    this.maxBackoff = const Duration(milliseconds: 1600),
    this.maxSessionDuration = const Duration(minutes: 5),
    this.turnDuration = const Duration(seconds: 60),
  });

  /// Turnos improductivos seguidos antes de dejar de reabrir.
  ///
  /// Tres es suficiente para absorber una pausa larga o un `ERROR_CLIENT`
  /// aislado, y bajo para que un motor roto no se coma la batería.
  final int maxConsecutiveUnproductive;

  /// Tope absoluto de turnos de una sesión, productivos incluidos.
  ///
  /// Protege el caso raro pero real de un motor que devuelve un segmento vacío
  /// tras otro sin que el contador de improductivos llegue a subir.
  final int maxTurns;

  /// Espera antes del primer reintento improductivo.
  ///
  /// No es cero a propósito: reabrir `SpeechRecognizer` en el mismo instante en
  /// que se cerró es la causa conocida de bucles de `ERROR_CLIENT`.
  final Duration initialBackoff;

  /// Tope de la espera. El backoff se duplica hasta aquí y no sigue.
  final Duration maxBackoff;

  /// Duración máxima de la sesión con el micrófono disponible.
  ///
  /// Es la última red: aunque cada turno sea productivo, una sesión no puede
  /// quedarse escuchando indefinidamente.
  final Duration maxSessionDuration;

  /// Tope de un turno individual, que viaja al puerto en la petición.
  final Duration turnDuration;

  /// Espera antes del reintento número [attempt], contando desde 1.
  ///
  /// Duplica desde [initialBackoff] y satura en [maxBackoff]. Un turno
  /// productivo no pasa por aquí: reabrir con retraso cortaría el habla del
  /// usuario justo cuando está funcionando.
  Duration backoffFor(int attempt) {
    if (attempt <= 1) return initialBackoff;
    var value = initialBackoff;
    for (var i = 1; i < attempt; i++) {
      value *= 2;
      if (value >= maxBackoff) return maxBackoff;
    }
    return value;
  }
}
