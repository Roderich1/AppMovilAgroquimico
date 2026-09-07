package com.comunidad.agro.voicebench.engine

import android.content.Context
import com.comunidad.agro.voicebench.BuildConfig
import com.comunidad.agro.voicebench.whisper.WhisperLib
import java.io.File

/**
 * `whisper.cpp` sobre un audio ya grabado.
 *
 * ## Por qué no captura
 *
 * Igual que [VoskSession]: la captura es de [com.comunidad.agro.voicebench.audio.PcmCapture].
 * El candidato híbrido necesita pasarle a Whisper **exactamente el mismo audio**
 * que ya oyó Vosk; si esta clase grabara por su cuenta serían dos capturas y
 * dos micrófonos, que es lo que `ADR-004` prohíbe.
 *
 * ## Salida sospechosa
 *
 * Whisper **sí** inventa sobre silencio: en la Fase 0, con el modelo tiny,
 * devolvió `[MÚSICA]` sin que nadie hablara y sin error (`RISK-026`). Por eso
 * [transcribe] no devuelve texto a secas sino un resultado que marca lo que
 * huele mal, y quien lo reciba decide. Ningún texto sospechoso se acepta solo.
 */
class WhisperSession(private val context: Context) {

    /** Lo que produjo una pasada, con lo que se sabe de su fiabilidad. */
    data class Outcome(
        val text: String?,
        val flags: List<String>,
        val elapsedMs: Long,
        val audioMs: Long,
        val error: String? = null,
    ) {
        /** Segundos de audio por segundo de cómputo. `ADR-004` pide <= 0,50. */
        val realTimeFactor: Double
            get() = if (audioMs <= 0) 0.0 else elapsedMs.toDouble() / audioMs

        /** Hay texto y nada lo marca como dudoso. */
        val isUsable: Boolean get() = !text.isNullOrEmpty() && flags.isEmpty()
    }

    private var contextPtr: Long = 0

    var lastModelLoadMs: Long = 0
        private set

    val isLoaded: Boolean get() = contextPtr != 0L

    var modelFile: File? = null
        private set

    /** Carga el modelo si hace falta. `null` si quedó listo. */
    fun ensureLoaded(): String? {
        if (contextPtr != 0L) return null
        if (!WhisperLib.loaded) return "serviceUnavailable"
        val model = ensureModel() ?: return "serviceUnavailable"
        modelFile = model
        val started = System.nanoTime()
        contextPtr = try {
            WhisperLib.initContext(model.absolutePath)
        } catch (_: Throwable) {
            0L
        }
        lastModelLoadMs = (System.nanoTime() - started) / 1_000_000
        return if (contextPtr == 0L) "engineFailure" else null
    }

    /**
     * Transcribe [samples]. Bloquea: llámese desde un hilo de trabajo.
     *
     * @param language pista de idioma (`es`). El wrapper original de
     *   `whisper.cpp` la dejaba clavada en `en`, que es justo lo que falsearía
     *   esta medición.
     */
    fun transcribe(samples: FloatArray, language: String): Outcome {
        val audioMs = samples.size * 1000L / 16_000
        ensureLoaded()?.let {
            return Outcome(null, emptyList(), 0, audioMs, error = it)
        }
        if (samples.isEmpty()) {
            return Outcome(null, listOf(FLAG_NO_SPEECH), 0, 0, error = "empty-audio")
        }

        val started = System.nanoTime()
        val rc = try {
            WhisperLib.fullTranscribe(contextPtr, threadCount(), language, samples)
        } catch (t: Throwable) {
            return Outcome(
                null,
                emptyList(),
                (System.nanoTime() - started) / 1_000_000,
                audioMs,
                error = t.javaClass.simpleName,
            )
        }
        val elapsedMs = (System.nanoTime() - started) / 1_000_000
        if (rc != 0) {
            return Outcome(null, emptyList(), elapsedMs, audioMs, error = "whisper-full-$rc")
        }

        val text = buildString {
            for (i in 0 until WhisperLib.getTextSegmentCount(contextPtr)) {
                append(WhisperLib.getTextSegment(contextPtr, i))
            }
        }.trim()

        return Outcome(text.ifEmpty { null }, suspicionFlags(text, audioMs), elapsedMs, audioMs)
    }

    fun release() {
        if (contextPtr != 0L) {
            WhisperLib.freeContext(contextPtr)
            contextPtr = 0
        }
    }

    // ------------------------------------------------------------------ privado

    /**
     * Qué hace sospechoso a este texto.
     *
     * Nada de esto lo descarta automáticamente: lo marca para que la interfaz
     * pida revisión en vez de proponer un dato inventado.
     */
    private fun suspicionFlags(text: String, audioMs: Long): List<String> {
        val flags = mutableListOf<String>()
        if (text.isEmpty()) {
            flags += FLAG_NO_SPEECH
            return flags
        }
        // Anotaciones del propio modelo: `[MÚSICA]`, `(risas)`, `[BLANK_AUDIO]`.
        // Whisper las emite cuando no oyó habla, y en la Fase 0 pasaron por
        // resultado válido.
        if (ANNOTATION.containsMatchIn(text)) flags += FLAG_ANNOTATION
        // Repetición degenerada: el mismo trozo una y otra vez.
        if (isDegenerate(text)) flags += FLAG_REPETITION
        // Mucho texto para muy poco audio: no cabe en el tiempo que se grabó.
        if (audioMs in 1..2_000 && text.length > 80) flags += FLAG_TOO_MUCH_TEXT
        return flags
    }

    private fun isDegenerate(text: String): Boolean {
        val words = text.lowercase().split(WHITESPACE).filter { it.isNotBlank() }
        if (words.size < 6) return false
        val distinct = words.toSet().size
        return distinct * 4 <= words.size
    }

    private fun threadCount(): Int =
        Runtime.getRuntime().availableProcessors().coerceIn(2, 4)

    /**
     * Deja el modelo disponible como archivo.
     *
     * Prioriza `<externalFilesDir>/models/<nombre>` para poder sustituirlo sin
     * recompilar; si no existe, lo copia desde los assets del APK. **Nunca lo
     * descarga.**
     */
    private fun ensureModel(): File? {
        val name = BuildConfig.WHISPER_MODEL
        if (name.isEmpty()) return null

        val sideloaded = File(File(context.getExternalFilesDir(null), "models"), name)
        if (sideloaded.isFile && sideloaded.length() > 0) return sideloaded

        val target = File(context.filesDir, name)
        if (target.isFile && target.length() > 0) return target

        return try {
            context.assets.open("models/$name").use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            }
            target
        } catch (_: Throwable) {
            null
        }
    }

    companion object {
        const val FLAG_NO_SPEECH = "noSpeech"
        const val FLAG_ANNOTATION = "possibleHallucination"
        const val FLAG_REPETITION = "degenerateRepetition"
        const val FLAG_TOO_MUCH_TEXT = "lowSpeechRatio"

        private val ANNOTATION = Regex("""[\[(](?:[^\[\])]{0,40})[\])]""")
        private val WHITESPACE = Regex("""\s+""")

        /** whisper usa el código de idioma (`es`), no el locale completo. */
        fun languageOf(locale: String): String =
            locale.replace('_', '-').substringBefore('-').lowercase()
    }
}
