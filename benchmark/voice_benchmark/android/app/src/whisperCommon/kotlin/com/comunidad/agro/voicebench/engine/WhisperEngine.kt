package com.comunidad.agro.voicebench.engine

import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import com.comunidad.agro.voicebench.BuildConfig
import com.comunidad.agro.voicebench.EngineListener
import com.comunidad.agro.voicebench.TranscriptionEngine
import com.comunidad.agro.voicebench.whisper.WhisperLib
import java.io.ByteArrayOutputStream
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Candidato B: `whisper.cpp` con un modelo multilingüe cuantizado.
 *
 * ## Diferencia de fondo con el Candidato A
 *
 * Whisper transcribe **una grabación completa**, no un flujo. Aquí no hay
 * resultados parciales: se graba hasta `stop()` y recién entonces se transcribe.
 * Por eso la latencia de parcial queda sin medir para este motor, y esa ausencia
 * es en sí un dato para `ADR-002`, no un defecto del banco.
 *
 * El modelo se busca primero en la carpeta externa (para poder cambiarlo sin
 * recompilar) y si no está se copia desde los assets del APK. En ningún caso se
 * descarga: el teléfono no necesita Internet.
 */
class WhisperEngine(private val context: Context) : TranscriptionEngine {

    override val engineId = BuildConfig.ENGINE_ID

    override var listener: EngineListener? = null

    private val worker = Executors.newSingleThreadExecutor()
    private val recording = AtomicBoolean(false)
    private var recorder: AudioRecord? = null
    private var contextPtr: Long = 0
    private var captured: ByteArrayOutputStream? = null

    // ------------------------------------------------------------ disponibilidad

    override fun availability(locale: String, onResult: (Map<String, Any?>) -> Unit) {
        worker.execute {
            val model = runCatching { ensureModel() }.getOrNull()
            val ready = WhisperLib.loaded && model != null
            onResult(
                mapOf(
                    "available" to ready,
                    // Whisper corre entero en el aparato: nunca necesita red.
                    "onDeviceAvailable" to ready,
                    "requiresNetwork" to false,
                    "engineName" to "whisper.cpp",
                    "engineVersion" to if (WhisperLib.loaded) {
                        WhisperLib.getVersion().take(12)
                    } else {
                        "no cargado"
                    },
                    "modelName" to BuildConfig.WHISPER_MODEL,
                    // Whisper recibe el idioma como pista; no hay lista de
                    // idiomas "instalados": el modelo multilingue los trae todos.
                    "installedLocales" to listOf(whisperLanguage(locale)),
                    "supportedLocales" to listOf("es", "en", "pt", "fr", "it", "de"),
                    "effectiveLocale" to whisperLanguage(locale),
                    "detail" to if (model == null) {
                        "modelo ausente: ${BuildConfig.WHISPER_MODEL}"
                    } else {
                        "modelo ${model.length()} bytes · ${abiOf()}"
                    },
                ),
            )
        }
    }

    // ------------------------------------------------------------------- sesión

    override fun start(locale: String, preferOffline: Boolean, partialResults: Boolean) {
        // La pista de idioma se fija AQUI. El wrapper original de whisper.cpp la
        // dejaba clavada en "en", que es justo lo que falsearia esta medicion.
        language = whisperLanguage(locale)
        if (recording.get()) {
            listener?.onError("busy", "already-recording")
            return
        }
        if (!WhisperLib.loaded) {
            listener?.onError("serviceUnavailable", "native-libs-missing")
            return
        }
        val minBuffer = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        if (minBuffer <= 0) {
            listener?.onError("engineFailure", "min-buffer-$minBuffer")
            return
        }
        val record = try {
            AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION,
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                minBuffer * 4,
            )
        } catch (t: Throwable) {
            listener?.onError("permissionDenied", t.javaClass.simpleName)
            return
        }
        if (record.state != AudioRecord.STATE_INITIALIZED) {
            record.release()
            listener?.onError("permissionDenied", "audiorecord-uninitialized")
            return
        }
        recorder = record
        captured = ByteArrayOutputStream()
        recording.set(true)
        record.startRecording()
        listener?.onState("listening")

        worker.execute {
            val buffer = ByteArray(minBuffer)
            while (recording.get()) {
                val read = record.read(buffer, 0, buffer.size)
                if (read > 0) captured?.write(buffer, 0, read)
            }
        }
    }

    override fun stop() {
        if (!recording.get()) return
        val audio = finishRecording() ?: return
        listener?.onState("processing")
        worker.execute {
            try {
                val model = ensureModel()
                if (model == null) {
                    listener?.onError("serviceUnavailable", "model-missing")
                    return@execute
                }
                if (contextPtr == 0L) {
                    contextPtr = WhisperLib.initContext(model.absolutePath)
                }
                if (contextPtr == 0L) {
                    listener?.onError("engineFailure", "init-context-failed")
                    return@execute
                }
                val samples = toFloatMono(audio)
                if (samples.isEmpty()) {
                    listener?.onError("noMatch", "empty-audio")
                    return@execute
                }
                val rc = WhisperLib.fullTranscribe(
                    contextPtr,
                    threadCount(),
                    language,
                    samples,
                )
                if (rc != 0) {
                    listener?.onError("engineFailure", "whisper-full-$rc")
                    return@execute
                }
                val text = buildString {
                    for (i in 0 until WhisperLib.getTextSegmentCount(contextPtr)) {
                        append(WhisperLib.getTextSegment(contextPtr, i))
                    }
                }.trim()
                if (text.isEmpty()) {
                    listener?.onError("noMatch", null)
                } else {
                    listener?.onFinal(text)
                }
            } catch (t: Throwable) {
                listener?.onError("engineFailure", t.javaClass.simpleName)
            }
        }
    }

    override fun cancel() {
        finishRecording()
    }

    override fun release() {
        cancel()
        if (contextPtr != 0L) {
            WhisperLib.freeContext(contextPtr)
            contextPtr = 0
        }
        worker.shutdownNow()
    }

    // ------------------------------------------------------------------ privado

    /** Pista de idioma de la sesión en curso. */
    private var language: String = "es"

    /** Detiene la captura y devuelve el audio crudo, soltando el micrófono. */
    private fun finishRecording(): ByteArray? {
        if (!recording.compareAndSet(true, false)) return null
        recorder?.let {
            try {
                it.stop()
            } catch (_: Throwable) {
                // Detener puede fallar si el sistema ya quito el microfono.
            }
            it.release()
        }
        recorder = null
        val audio = captured?.toByteArray()
        // El audio muere aqui: no se escribe a disco ni se conserva.
        captured = null
        return audio
    }

    /** PCM16 little-endian a float en [-1, 1], que es lo que espera whisper. */
    private fun toFloatMono(pcm: ByteArray): FloatArray {
        val samples = FloatArray(pcm.size / 2)
        for (i in samples.indices) {
            val lo = pcm[i * 2].toInt() and 0xFF
            val hi = pcm[i * 2 + 1].toInt()
            val value = (hi shl 8) or lo
            samples[i] = value / 32768.0f
        }
        return samples
    }

    private fun threadCount(): Int =
        Runtime.getRuntime().availableProcessors().coerceIn(2, 4)

    /**
     * Deja el modelo disponible como archivo.
     *
     * Prioriza `<externalFilesDir>/models/<nombre>` para poder sustituirlo sin
     * recompilar; si no existe, lo copia desde los assets del APK.
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

    private fun abiOf(): String =
        android.os.Build.SUPPORTED_ABIS.firstOrNull() ?: "desconocida"

    /** whisper usa el código de idioma (`es`), no el locale completo (`es-BO`). */
    private fun whisperLanguage(locale: String): String =
        locale.replace('_', '-').substringBefore('-').lowercase()

    companion object {
        const val SAMPLE_RATE = 16_000

        /** Utilidad para verificar un modelo copiado a mano al teléfono. */
        fun sha256(file: File): String {
            val digest = MessageDigest.getInstance("SHA-256")
            file.inputStream().use { stream ->
                val buffer = ByteArray(1 shl 16)
                while (true) {
                    val read = stream.read(buffer)
                    if (read <= 0) break
                    digest.update(buffer, 0, read)
                }
            }
            return digest.digest().joinToString("") { "%02x".format(it) }
        }
    }
}
