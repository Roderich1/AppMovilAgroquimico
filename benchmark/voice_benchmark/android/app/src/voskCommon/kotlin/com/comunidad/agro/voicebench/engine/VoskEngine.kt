package com.comunidad.agro.voicebench.engine

import android.content.Context
import android.os.Build
import com.comunidad.agro.voicebench.BuildConfig
import com.comunidad.agro.voicebench.EngineListener
import com.comunidad.agro.voicebench.TranscriptionEngine
import com.comunidad.agro.voicebench.audio.PcmCapture
import java.util.concurrent.Executors

/**
 * Candidato C1: Vosk aislado, con parciales en vivo.
 *
 * ## Qué se mide aquí y no en otro sitio
 *
 * Es el único candidato que produce texto **mientras** el usuario habla sin
 * depender de un servicio del sistema. Android también da parciales, pero
 * necesita que el fabricante haya instalado un modelo de idioma; eso es
 * exactamente lo que faltó en el HONOR y abrió esta fase. Vosk trae el suyo
 * dentro del APK.
 *
 * A cambio, su exactitud declarada es peor que la de Whisper small. Medir C1
 * aislado permite responder si el híbrido merece la pena o si basta con Vosk.
 *
 * No guarda audio, no escribe a disco y no registra lo dictado.
 */
class VoskEngine(private val context: Context) : TranscriptionEngine {

    override val engineId = BuildConfig.ENGINE_ID

    override var listener: EngineListener? = null

    private val worker = Executors.newSingleThreadExecutor()
    private val capture = PcmCapture()
    private val session = VoskSession(context)

    /** Último parcial emitido, para no repetir el mismo texto una y otra vez. */
    private var lastPartial: String? = null

    // ------------------------------------------------------------ disponibilidad

    override fun availability(locale: String, onResult: (Map<String, Any?>) -> Unit) {
        worker.execute {
            val error = session.ensureLoaded()
            val directory = session.modelDirectory
            val ready = error == null
            onResult(
                mapOf(
                    "available" to ready,
                    // Vosk corre entero en el aparato: nunca necesita red.
                    "onDeviceAvailable" to ready,
                    "requiresNetwork" to false,
                    "engineName" to "Vosk",
                    "engineVersion" to "vosk-android 0.3.75",
                    "modelName" to BuildConfig.VOSK_MODEL,
                    // El modelo es de un idioma concreto: no hay lista que
                    // consultar ni fallback posible dentro del motor.
                    "installedLocales" to listOf("es"),
                    "supportedLocales" to listOf("es"),
                    "effectiveLocale" to "es",
                    "detail" to when {
                        directory == null -> "modelo ausente: ${BuildConfig.VOSK_MODEL}"
                        !ready ->
                            "no se pudo cargar: $error · ${session.lastLoadFailure} " +
                                "· ${abiOf()}"
                        else ->
                            "modelo ${VoskModelStore.installedBytes(directory)} bytes · " +
                                "carga ${session.lastModelLoadMs} ms · ${abiOf()}"
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
        worker.execute {
            session.open()?.let {
                listener?.onError(it, "vosk-open")
                return@execute
            }
            lastPartial = null
            // Vosk consume el audio al vuelo: no hace falta retener nada, y no
            // retenerlo es la garantía más simple de que no queda audio vivo.
            val failure = capture.start(
                { generation, buffer, length ->
                    if (generation != capture.generation) return@start
                    val text = session.accept(buffer, length) ?: return@start
                    if (!partialResults || text == lastPartial) return@start
                    lastPartial = text
                    listener?.onPartial(text)
                },
                retainBytes = 0,
            )
            if (failure != null) {
                session.close()
                listener?.onError(failure, "capture")
                return@execute
            }
            listener?.onState("listening")
        }
    }

    override fun stop() {
        if (!capture.isRecording) return
        capture.stop()
        listener?.onState("processing")
        worker.execute {
            val text = session.finish()
            if (text.isNullOrEmpty()) {
                // Silencio no es texto. `RISK-032`.
                listener?.onError("noMatch", null)
            } else {
                listener?.onFinal(text)
            }
        }
    }

    override fun cancel() {
        capture.cancel()
        worker.execute { session.close() }
    }

    override fun release() {
        capture.cancel()
        worker.execute { session.release() }
        worker.shutdown()
    }

    private fun abiOf(): String = Build.SUPPORTED_ABIS.firstOrNull() ?: "desconocida"
}
