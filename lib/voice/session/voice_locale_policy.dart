import '../port/speech_transcription_port.dart';

/// Cómo se elige el español con el que se intenta escuchar (`EVO-009-REQ-016`).
///
/// ## Por qué existe una política y no una constante
///
/// `ADR-002` midió en teléfono real que `es-BO` **no existe** como idioma de
/// reconocimiento (error 12, `LANGUAGE_NOT_SUPPORTED`), que `es-ES` puede estar
/// soportado pero **sin modelo descargado** (error 13, `LANGUAGE_UNAVAILABLE`) y
/// que en ese aparato **sólo funcionó `es-US`**. De ahí salen dos prohibiciones
/// que esta clase implementa:
///
/// 1. **No prometer `es-BO`.** Se pide, porque es el idioma del producto, pero
///    la interfaz muestra siempre el locale *utilizado*, no el deseado.
/// 2. **No fijar `es-US` en silencio.** Que fuera el único instalado en un
///    teléfono no lo convierte en la respuesta correcta en otro. Fijarlo
///    escondería el fallback y convertiría una medición puntual en una regla.
///
/// ## La lista exacta
///
/// [candidates] es el orden completo y es parte del contrato: está cubierta por
/// `test/voice/voice_locale_policy_test.dart`. El criterio del orden es
/// cercanía de uso al español boliviano de campo, y sólo al final los que
/// cambian más el vocabulario o el modelo acústico.
///
/// ## Dos caminos, según lo que el sistema deje consultar
///
/// * **Se pueden consultar los idiomas instalados** (API 33+): se filtra
///   [candidates] contra esa lista y se intenta primero lo que de verdad hay.
/// * **No se pueden consultar** (API 32 y anteriores, el caso del dispositivo de
///   referencia): se intentan los candidatos **en orden, uno a uno, observando
///   el resultado real**. Es lo que obliga `EVO-009-REQ-014`: no se confía en la
///   consulta, se prueba. Un `localeUnavailable` avanza al siguiente candidato;
///   cualquier otro error detiene el recorrido, porque no es un problema de
///   idioma y seguir probando sólo gastaría intentos.
class VoiceLocalePolicy {
  const VoiceLocalePolicy();

  /// El locale que el producto pide. Nunca se muestra como el que se usará.
  static const requested = 'es-BO';

  /// Orden de intento, del más cercano al más lejano.
  ///
  /// `es-BO` va primero **a propósito**, aunque `ADR-002` lo midió fallando: si
  /// algún día existe, el usuario lo obtiene sin cambiar código, y mientras
  /// tanto el error 12 es inmediato y barato. Quitarlo sería decidir por todos
  /// los aparatos a partir de un único teléfono.
  static const candidates = <String>[
    'es-BO',
    'es-419',
    'es-PE',
    'es-AR',
    'es-CL',
    'es-CO',
    'es-MX',
    'es-US',
    'es-ES',
    'es',
  ];

  /// El orden que se intentará en este aparato, ya recortado.
  ///
  /// Cuando [TranscriptionAvailability.localeSupportKnown] es `true`, se
  /// devuelven **sólo** los candidatos presentes entre los instalados, seguidos
  /// de los que el motor declara soportar. Si nada coincide, se devuelve la
  /// lista completa igualmente: la consulta puede equivocarse —lo hizo en
  /// `ADR-002`— y negarse a intentar por lo que dijo una API sería confiar en
  /// ella justo donde se demostró que no se puede.
  List<String> attemptOrder(TranscriptionAvailability availability) {
    if (!availability.localeSupportKnown) return candidates;

    final installed = _normalized(availability.installedLocales);
    final supported = _normalized(availability.supportedLocales);

    final present = <String>[];
    final rest = <String>[];
    for (final candidate in candidates) {
      final key = _key(candidate);
      if (installed.contains(key)) {
        present.add(candidate);
      } else if (supported.contains(key)) {
        rest.add(candidate);
      }
    }
    final known = [...present, ...rest];
    if (known.isEmpty) return candidates;

    // Los no declarados van al final, no se descartan: intentar y observar es
    // más fiable que la lista del sistema (`EVO-009-REQ-014`).
    final remaining = candidates.where((c) => !known.contains(c));
    return [...known, ...remaining];
  }

  /// Si [code] significa "prueba con el siguiente idioma".
  ///
  /// Sólo [TranscriptionErrorCode.localeUnavailable]. Un fallo de permiso, de
  /// servicio o de red no mejora cambiando de idioma, y recorrer diez
  /// candidatos ante un micrófono denegado sería el bucle que
  /// `EVO-009-REQ-017` prohíbe.
  bool advancesLocale(TranscriptionErrorCode code) =>
      code == TranscriptionErrorCode.localeUnavailable;

  static Set<String> _normalized(List<String> values) =>
      values.map(_key).toSet();

  /// Android devuelve `es_US`, `es-US` y `spa-US` según versión y OEM.
  static String _key(String raw) => raw.replaceAll('_', '-').toLowerCase();
}
