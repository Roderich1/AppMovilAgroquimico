package com.comunidad.agro.voicebench.engine

/**
 * Qué hace sospechoso a un texto que devolvió Whisper.
 *
 * ## La razón por la que esto existe aparte
 *
 * `ADR-002` eligió Android sobre Whisper por una sola cosa que ninguna otra
 * compensaba: ante tres segundos de silencio, Whisper tiny devolvió `[MÚSICA]`
 * **y lo dio por resultado válido, sin error** (`RISK-026`). Un motor que
 * afirma texto que nadie dijo puede afirmar un producto o un monto sobre ruido
 * de campo, y el usuario lo vería como dato propuesto.
 *
 * C3 vuelve a poner a Whisper sobre la mesa con `small`, y el guardrail binario
 * de la matriz de aceptación es **cero texto aceptado sobre no-habla**. Quien
 * decide eso es esta clasificación, así que vive fuera de la inferencia: sin
 * JNI y sin `Context`, para poder ejercitarla entera en la JVM. Si dependiera
 * del motor nativo, el caso de `[MÚSICA]` sólo se podría comprobar con suerte y
 * un micrófono en silencio.
 *
 * ## Lo que esta clase no hace
 *
 * No descarta nada. Marca. La interfaz pide revisión y decide la persona;
 * ningún texto sospechoso se acepta solo.
 */
object WhisperTranscript {

    /** No hubo habla: el motor no devolvió nada. */
    const val FLAG_NO_SPEECH = "noSpeech"

    /** El texto es una anotación del propio modelo, no habla transcrita. */
    const val FLAG_ANNOTATION = "possibleHallucination"

    /** El mismo trozo una y otra vez: el decoder se quedó en bucle. */
    const val FLAG_REPETITION = "degenerateRepetition"

    /** Más texto del que cabe en el audio que se grabó. */
    const val FLAG_TOO_MUCH_TEXT = "lowSpeechRatio"

    /**
     * Anotaciones del propio modelo: `[MÚSICA]`, `(risas)`, `[BLANK_AUDIO]`.
     *
     * Whisper las emite cuando no oyó habla, y en la Fase 0 pasaron por
     * resultado válido.
     */
    private val ANNOTATION = Regex("""[\[(](?:[^\[\])]{0,40})[\])]""")

    private val WHITESPACE = Regex("""\s+""")

    /**
     * Qué marcas le corresponden a [text] para un audio de [audioMs].
     *
     * [audioMs] igual a cero significa **no medido**, no «audio de duración
     * cero»: en ese caso no se juzga la proporción entre texto y tiempo, porque
     * sería juzgar contra un dato que nadie tomó.
     */
    fun flagsFor(text: String, audioMs: Long): List<String> {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return listOf(FLAG_NO_SPEECH)

        val flags = mutableListOf<String>()
        if (ANNOTATION.containsMatchIn(trimmed)) flags += FLAG_ANNOTATION
        if (isDegenerate(trimmed)) flags += FLAG_REPETITION
        if (audioMs in 1..2_000 && trimmed.length > 80) flags += FLAG_TOO_MUCH_TEXT
        return flags
    }

    /** Hay texto y nada lo marca como dudoso. */
    fun isUsable(text: String?, flags: List<String>): Boolean =
        !text.isNullOrBlank() && flags.isEmpty()

    /**
     * El decoder se quedó repitiendo.
     *
     * Por debajo de seis palabras no se juzga: «no fueron doce, fueron dos» es
     * una corrección legítima del corpus (categoría F) y repite una palabra de
     * cinco.
     */
    fun isDegenerate(text: String): Boolean {
        val words = text.lowercase().split(WHITESPACE).filter { it.isNotBlank() }
        if (words.size < 6) return false
        return words.toSet().size * 4 <= words.size
    }

    /** whisper usa el código de idioma (`es`), no el locale completo. */
    fun languageOf(locale: String): String =
        locale.replace('_', '-').substringBefore('-').lowercase()

    /**
     * Segundos de cómputo por segundo de audio. `ADR-004` pide p95 <= 0,50.
     *
     * `null` cuando la duración del audio no se midió. Devolver cero diría
     * «instantáneo», que es lo contrario de «no se midió» y es exactamente el
     * tipo de cifra inventada que el banco no puede producir.
     */
    fun realTimeFactorOrNull(elapsedMs: Long, audioMs: Long): Double? =
        if (audioMs <= 0) null else elapsedMs.toDouble() / audioMs

    /** Igual que [realTimeFactorOrNull], con cero cuando no hay audio medido. */
    fun realTimeFactor(elapsedMs: Long, audioMs: Long): Double =
        realTimeFactorOrNull(elapsedMs, audioMs) ?: 0.0
}
