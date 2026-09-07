import '../port/speech_transcription_port.dart';

/// Cómo se elige el español con el que se intenta escuchar (`EVO-009-REQ-016`).
///
/// ## Por qué existe una política y no una constante
///
/// `ADR-002` midió en teléfono real que `es-BO` **no existe** como idioma de
/// reconocimiento (error 12, `LANGUAGE_NOT_SUPPORTED`), que `es-ES` puede estar
/// soportado pero **sin modelo descargado** (error 13, `LANGUAGE_UNAVAILABLE`) y
/// que en ese aparato **sólo funcionó `es-US`**. El gate físico en el HONOR
/// JDY-LX3P (API 36) añadió que allí el sistema **declara** `es-US` y `es-ES` y
/// aun así ambos fallan con error 13: ninguna consulta sustituye al intento.
///
/// De ahí la regla que esta clase implementa:
///
/// 1. **Se pide un locale concreto y se muestra el que de verdad se usó.** El
///    solicitado no es una promesa; la interfaz enseña siempre los dos.
/// 2. **No se fija un único idioma.** Se conserva la lista completa de respaldo
///    y se recorre intentando, porque dos mediciones puntuales no describen a
///    todos los aparatos (`RISK-023`).
///
/// ## La lista exacta
///
/// [candidates] es el orden completo y es parte del contrato: está cubierta por
/// `test/voice/voice_locale_policy_test.dart`. Encabeza [requested] por decisión
/// del propietario, y el resto sigue el criterio de cercanía de uso al español
/// boliviano de campo, dejando al final los que más cambian el vocabulario o el
/// modelo acústico.
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
  ///
  /// **Decisión del propietario, 2026-09-06**, tomada durante el gate físico en
  /// el HONOR JDY-LX3P: se pide `es-US` en lugar de `es-BO`.
  ///
  /// El motivo es la evidencia acumulada en los dos aparatos medidos: en el
  /// POCO X5 Pro (API 31) `es-US` fue **el único** que llegó a transcribir, y en
  /// el HONOR (API 36) es uno de los dos que el sistema declara soportar. Pedir
  /// un locale que ningún aparato medido ha admitido gastaba un intento y
  /// mostraba al usuario un idioma solicitado que nunca se cumplía.
  ///
  /// Esto **revisa** el punto 5 de la política productiva de `ADR-002` («no
  /// puede prometer `es-BO`») en su parte de qué se pide primero. Lo que **no**
  /// cambia, y sigue siendo obligatorio: la lista de respaldo se conserva
  /// completa, se sigue intentando y observando el resultado real, y la interfaz
  /// sigue mostrando *solicitado* y *utilizado* por separado. `es-US` es el
  /// primer intento, **no** una promesa: si falla, se recorre el resto.
  ///
  /// `es-BO` sigue en la lista, en segundo lugar, porque es el país del usuario:
  /// si algún día existe como idioma de reconocimiento, lo obtiene sin cambiar
  /// código.
  static const requested = 'es-US';

  /// Orden de intento, del más probable al más lejano.
  ///
  /// `es-US` va primero por la decisión del propietario documentada en
  /// [requested]. El resto conserva el orden por cercanía de uso al español
  /// boliviano de campo, y `es-BO` queda inmediatamente después porque es el
  /// país del usuario.
  ///
  /// La lista completa se mantiene **a propósito**: es lo que permite que un
  /// aparato con otro español instalado siga funcionando. Reducirla a `es-US`
  /// convertiría dos mediciones puntuales en una regla para todos los teléfonos,
  /// que es justo lo que `RISK-023` advierte.
  static const candidates = <String>[
    'es-US',
    'es-BO',
    'es-419',
    'es-PE',
    'es-AR',
    'es-CL',
    'es-CO',
    'es-MX',
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
