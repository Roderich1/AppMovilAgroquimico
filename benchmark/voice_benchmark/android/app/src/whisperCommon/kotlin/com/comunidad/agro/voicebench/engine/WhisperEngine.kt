package com.comunidad.agro.voicebench.engine

import android.content.Context
import android.os.Build
import com.comunidad.agro.voicebench.BuildConfig
import com.comunidad.agro.voicebench.EngineListener
import com.comunidad.agro.voicebench.TranscriptionEngine
import com.comunidad.agro.voicebench.audio.PcmCapture
import com.comunidad.agro.voicebench.whisper.WhisperLib
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

/**
 * Candidatos C2 y C3 —y el histórico tiny—: `whisper.cpp` con un modelo
 * multilingüe cuantizado.
 *
 * ## Diferencia de fondo con el motor de Android y con Vosk
 *
 * Whisper transcribe **una grabación completa**, no un flujo. Aquí no hay
 * resultados parciales: se graba hasta `stop()` y recién entonces se transcribe.
 * La latencia de parcial queda sin medir para este motor, y esa ausencia es en
 * sí un dato para la decisión, no un defecto del banco (`RISK-024`).
 *
 * ## Qué cambió en la Fase 0-bis
 *
 * La captura y la inferencia se separaron: ahora usa [PcmCapture], la misma que
 * Vosk y el híbrido, y [WhisperSession], la misma inferencia que el híbrido.
 * Antes tenía su propio `AudioRecord` y su propia carga de modelo. Compartirlos
 * es lo que permite afirmar que C2, C3 y C4 miden el mismo motor sobre la misma
 * captura, y que la diferencia entre ellos es sólo lo que se quiere medir.
 *
 * El audio no se guarda, no cruza a Dart y no aparece en el log.
 */
class WhisperEngine(private val context: Context) : TranscriptionEngine {

    override val engineId = BuildConfig.ENGINE_ID

    override var listener: EngineListener? = null

    private val worker = Executors.newSingleThreadExecutor()
    private val capture = PcmCapture()
    private val whisper = WhisperSession(context)

    /** Sesión lógica: descarta el resultado de una captura ya abandonada. */
    private val session = AtomicLong(0)

    private var language = "es"

    // ------------------------------------------------------------ disponibilidad

    override fun availability(locale: String, onResult: (Map<String, Any?>) -> Unit) {
        worker.execute {
            val error = whisper.ensureLoaded()
            val ready = error == null
            val model = whisper.modelFile
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
                    "installedLocales" to listOf(WhisperSession.languageOf(locale)),
                    "supportedLocales" to listOf("es", "en", "pt", "fr", "it", "de"),
                    "effectiveLocale" to WhisperSession.languageOf(locale),
                    "detail" to when {
                        model == null -> "modelo ausente: ${BuildConfig.WHISPER_MODEL}"
                        !ready -> "no se pudo cargar: $error · ${abiOf()}"
                        else ->
                            "modelo ${model.length()} bytes · " +
                                "carga ${whisper.lastModelLoadMs} ms · ${abiOf()}"
                    },
                ),
            )
        }
    }

    // ------------------------------------------------------------------- sesión

    override fun start(locale: String, preferOffline: Boolean, partialResults: Boolean) {
        // La pista de idioma se fija AQUI. El wrapper original de whisper.cpp la
        // dejaba clavada en "en", que es justo lo que falsearia esta medicion.
        language = WhisperSession.languageOf(locale)
        if (capture.isRecording) {
            listener?.onError("busy", "already-recording")
            return
        }
        if (!WhisperLib.loaded) {
            listener?.onError("serviceUnavailable", "native-libs-missing")
            return
        }
        session.incrementAndGet()
        // Whisper no consume nada al vuelo: todo el audio se retiene, acotado.
        val failure = capture.start(null, PcmCapture.DEFAULT_RETAIN_BYTES)
        if (failure != null) {
            listener?.onError(failure, "capture")
            return
        }
        listener?.onState("listening")
    }

    override fun stop() {
        if (!capture.isRecording) return
        val current = session.get()
        val audio = capture.stop()
        listener?.onState("processing")

        worker.execute {
            if (current != session.get()) return@execute
            if (audio == null || audio.isEmpty()) {
                listener?.onError("noMatch", "empty-audio")
                return@execute
            }
            val outcome = whisper.transcribe(PcmCapture.toFloatMono(audio), language)
            if (current != session.get()) return@execute

            if (outcome.error != null) {
                listener?.onError("engineFailure", outcome.error)
                return@execute
            }
            val text = outcome.text
            if (text.isNullOrEmpty()) {
                listener?.onError("noMatch", null)
                return@execute
            }
            // Las marcas de sospecha viajan aparte: el texto se entrega tal cual
            // y quien mide decide. `RISK-026` y `RISK-032`.
            if (outcome.flags.isNotEmpty()) {
                listener?.onHybridDetail(
                    mapOf(
                        "voskText" to null,
                        "whisperText" to text,
                        "source" to "whisper",
                        "flags" to outcome.flags,
                        "whisperElapsedMs" to outcome.elapsedMs,
                        "audioMs" to outcome.audioMs,
                        "realTimeFactor" to outcome.realTimeFactor,
                        "audioBytes" to audio.size,
                    ),
                )
            }
            listener?.onFinal(text)
        }
    }

    override fun cancel() {
        session.incrementAndGet()
        capture.cancel()
    }

    override fun release() {
        cancel()
        worker.execute { whisper.release() }
        worker.shutdown()
    }

    private fun abiOf(): String = Build.SUPPORTED_ABIS.firstOrNull() ?: "desconocida"
}
