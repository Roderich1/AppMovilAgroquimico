package com.comunidad.agro.voicebench.engine

import android.content.Context
import android.os.Build
import com.comunidad.agro.voicebench.BuildConfig
import com.comunidad.agro.voicebench.EngineListener
import com.comunidad.agro.voicebench.TranscriptionEngine
import com.comunidad.agro.voicebench.audio.PcmCapture
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

/**
 * Candidato C4: Vosk en vivo y Whisper small al detener, sobre **una sola
 * captura**.
 *
 * ```text
 * PcmCapture (16 kHz mono 16-bit)
 *      ├── durante la captura → Vosk    → parciales, no autoritativos
 *      └── al detener, mismo audio → Whisper small → texto final propuesto
 * ```
 *
 * ## Las reglas que esta clase no puede romper
 *
 * - **Un micrófono.** Whisper no vuelve a grabar: recibe el buffer que ya se
 *   capturó. Dos `AudioRecord` abiertos es lo que `ADR-004` prohíbe.
 * - **Un motor pesado a la vez.** Vosk se cierra antes de que Whisper empiece.
 * - **Buffer acotado.** 90 s como máximo, liberado al terminar o cancelar.
 * - **El audio no sale de aquí.** No cruza a Dart, no se escribe a disco.
 * - **Nada se mezcla.** El parcial de Vosk y el final de Whisper viajan
 *   separados con su procedencia; ningún algoritmo elige por el usuario.
 * - **Los callbacks tardíos se descartan.** Una sesión cancelada mientras
 *   Whisper infería no puede entregar su texto a la siguiente.
 *
 * ## Qué pasa si Whisper falla
 *
 * Se conserva lo que dijo Vosk y se marca de dónde viene. Perder toda la
 * sesión porque la segunda pasada falló sería peor que entregar un texto peor
 * pero honesto sobre su origen.
 */
class HybridEngine(private val context: Context) : TranscriptionEngine {

    override val engineId = BuildConfig.ENGINE_ID

    override var listener: EngineListener? = null

    private val worker = Executors.newSingleThreadExecutor()
    private val capture = PcmCapture()
    private val vosk = VoskSession(context)
    private val whisper = WhisperSession(context)

    /** Sesión lógica. Descarta resultados de una captura ya abandonada. */
    private val session = AtomicLong(0)

    private var language = "es"
    private var lastPartial: String? = null
    private var voskFirstPartialMs: Long = 0
    private var startedAtNs: Long = 0

    // ------------------------------------------------------------ disponibilidad

    override fun availability(locale: String, onResult: (Map<String, Any?>) -> Unit) {
        worker.execute {
            val voskError = vosk.ensureLoaded()
            val whisperError = whisper.ensureLoaded()
            val ready = voskError == null && whisperError == null
            val model = vosk.modelDirectory
            onResult(
                mapOf(
                    "available" to ready,
                    // Los dos motores corren enteros en el aparato.
                    "onDeviceAvailable" to ready,
                    "requiresNetwork" to false,
                    "engineName" to "Vosk + whisper.cpp",
                    "engineVersion" to "vosk-android 0.3.75 · " +
                        if (com.comunidad.agro.voicebench.whisper.WhisperLib.loaded) {
                            com.comunidad.agro.voicebench.whisper.WhisperLib
                                .getVersion().take(12)
                        } else {
                            "whisper no cargado"
                        },
                    "modelName" to
                        "${BuildConfig.VOSK_MODEL} + ${BuildConfig.WHISPER_MODEL}",
                    "installedLocales" to listOf("es"),
                    "supportedLocales" to listOf("es"),
                    "effectiveLocale" to "es",
                    "detail" to buildString {
                        append("vosk=")
                        append(voskError ?: "ok ${vosk.lastModelLoadMs} ms")
                        if (model != null) {
                            append(" (${VoskModelStore.installedBytes(model)} B)")
                        }
                        append(" · whisper=")
                        append(whisperError ?: "ok ${whisper.lastModelLoadMs} ms")
                        append(" · ")
                        append(Build.SUPPORTED_ABIS.firstOrNull() ?: "abi desconocida")
                    },
                ),
            )
        }
    }

    // ------------------------------------------------------------------- sesión

    override fun start(locale: String, preferOffline: Boolean, partialResults: Boolean) {
        if (capture.isRecording) {
            listener?.onError("busy", "already-recording")
            return
        }
        language = WhisperSession.languageOf(locale)
        val current = session.incrementAndGet()

        worker.execute {
            if (current != session.get()) return@execute
            vosk.open()?.let {
                listener?.onError(it, "vosk-open")
                return@execute
            }
            lastPartial = null
            voskFirstPartialMs = 0
            startedAtNs = System.nanoTime()

            val failure = capture.start(
                { generation, buffer, length ->
                    if (generation != capture.generation || current != session.get()) {
                        return@start
                    }
                    val text = vosk.accept(buffer, length) ?: return@start
                    if (!partialResults || text == lastPartial) return@start
                    lastPartial = text
                    if (voskFirstPartialMs == 0L) {
                        voskFirstPartialMs = (System.nanoTime() - startedAtNs) / 1_000_000
                    }
                    listener?.onPartial(text)
                },
                // El mismo audio que oye Vosk se guarda para Whisper. Es la
                // única copia y está acotada a 90 s.
                retainBytes = PcmCapture.DEFAULT_RETAIN_BYTES,
            )
            if (failure != null) {
                vosk.close()
                listener?.onError(failure, "capture")
                return@execute
            }
            listener?.onState("listening")
        }
    }

    override fun stop() {
        if (!capture.isRecording) return
        val current = session.get()
        val audio = capture.stop()
        listener?.onState("processing")

        worker.execute {
            if (current != session.get()) return@execute

            // Vosk cierra ANTES de que Whisper empiece: un solo motor pesado
            // infiriendo a la vez.
            val voskText = vosk.finish()

            if (audio == null || audio.isEmpty()) {
                listener?.onError("noMatch", "empty-audio")
                return@execute
            }

            val outcome = whisper.transcribe(
                PcmCapture.toFloatMono(audio, audio.size),
                language,
            )
            if (current != session.get()) return@execute

            val whisperText = outcome.text
            val flags = outcome.flags.toMutableList()

            // Qué se propone como final, y por qué. Nunca se fusionan textos.
            val (finalText, source) = when {
                whisperText != null && outcome.flags.isEmpty() ->
                    whisperText to "whisper"
                // Whisper falló o su salida es sospechosa: se conserva lo de
                // Vosk diciendo de dónde viene, en vez de perder la sesión.
                !voskText.isNullOrEmpty() -> {
                    flags += FLAG_WHISPER_FALLBACK
                    voskText to "vosk"
                }
                whisperText != null -> whisperText to "whisper"
                else -> null to "ninguno"
            }

            listener?.onHybridDetail(
                mapOf(
                    "voskText" to voskText,
                    "whisperText" to whisperText,
                    "source" to source,
                    "flags" to flags,
                    "voskFirstPartialMs" to voskFirstPartialMs,
                    "whisperElapsedMs" to outcome.elapsedMs,
                    "audioMs" to outcome.audioMs,
                    "realTimeFactor" to outcome.realTimeFactor,
                    "whisperError" to outcome.error,
                    "audioBytes" to audio.size,
                ),
            )

            if (finalText.isNullOrEmpty()) {
                // Ni un motor ni el otro oyeron habla. No es texto.
                listener?.onError("noMatch", outcome.error)
            } else {
                listener?.onFinal(finalText)
            }
        }
    }

    override fun cancel() {
        // Invalidar la sesión ANTES de soltar nada: si Whisper está infiriendo,
        // su resultado ya no podrá entregarse.
        session.incrementAndGet()
        capture.cancel()
        worker.execute { vosk.close() }
    }

    override fun release() {
        cancel()
        worker.execute {
            vosk.release()
            whisper.release()
        }
        worker.shutdown()
    }

    private companion object {
        /** Whisper no sirvió y el texto que se propone es el de Vosk. */
        const val FLAG_WHISPER_FALLBACK = "whisperUnusable"
    }
}
