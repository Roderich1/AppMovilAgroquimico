package com.comunidad.agro.voicebench

/**
 * Lado nativo de `SpeechTranscriptionPort`.
 *
 * Cada sabor del APK provee una implementación distinta y el resto del código no
 * cambia. Es el "escape hatch" que exige `ADR-002`: reemplazar el motor no toca
 * ni Dart ni la interfaz.
 *
 * Ninguna implementación puede persistir audio ni escribir el texto en el log.
 */
interface TranscriptionEngine {

    /** Etiqueta estable para los resultados, p. ej. `android-speech`. */
    val engineId: String

    /**
     * Qué puede hacer el motor con [locale] en este aparato.
     *
     * Es asíncrono porque en Android la consulta de idiomas instalados
     * (`checkRecognitionSupport`) responde por callback. Bloquear el hilo
     * principal esperándola provocaría un ANR.
     */
    fun availability(locale: String, onResult: (Map<String, Any?>) -> Unit)

    /**
     * Empieza a escuchar. Los resultados llegan por [listener].
     *
     * Debe ser seguro llamarlo tras un [cancel] o un fallo.
     */
    fun start(locale: String, preferOffline: Boolean, partialResults: Boolean)

    /** Deja de escuchar y produce el resultado final. */
    fun stop()

    /** Descarta la sesión y suelta el micrófono. */
    fun cancel()

    /** Libera todo. Debe tolerar llamarse sin sesión abierta. */
    fun release()

    /** Quien recibe los eventos. Lo fija el puente antes de usar el motor. */
    var listener: EngineListener?
}

/** Eventos que el motor entrega al puente. */
interface EngineListener {
    fun onState(state: String)
    fun onPartial(text: String)
    fun onFinal(text: String)

    /**
     * @param code nombre del `TranscriptionErrorCode` de Dart.
     * @param detail diagnóstico técnico. **Nunca** la frase dictada.
     */
    fun onError(code: String, detail: String?)
}

/**
 * Elige, entre los idiomas que el motor tiene realmente instalados, cuál usará
 * al pedirle [requested].
 *
 * Devuelve `null` si no hay ninguno servible. Nunca inventa: si el aparato no
 * tiene español instalado, la interfaz debe decirlo en lugar de prometer que
 * funcionará (`EVO-009-REQ-008`).
 */
fun resolveEffectiveLocale(requested: String, installed: List<String>): String? {
    if (installed.isEmpty()) return null
    val wanted = requested.replace('_', '-')
    installed.firstOrNull { it.equals(wanted, ignoreCase = true) }?.let { return it }
    val language = wanted.substringBefore('-')
    return installed.firstOrNull { it.substringBefore('-').equals(language, ignoreCase = true) }
}
