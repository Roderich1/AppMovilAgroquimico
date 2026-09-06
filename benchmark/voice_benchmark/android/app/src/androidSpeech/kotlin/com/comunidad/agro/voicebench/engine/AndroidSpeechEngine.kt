package com.comunidad.agro.voicebench.engine

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import com.comunidad.agro.voicebench.EngineListener
import com.comunidad.agro.voicebench.TranscriptionEngine
import com.comunidad.agro.voicebench.resolveEffectiveLocale
import java.util.concurrent.Executors

/**
 * Candidato A: el reconocimiento que ofrece el propio Android.
 *
 * Usa el reconocedor **on-device** cuando el aparato lo tiene y cae al del
 * sistema si no. Nunca afirma que funciona sin Internet: informa lo que el
 * sistema declara y deja que la interfaz lo muestre tal cual.
 *
 * Todo el uso de `SpeechRecognizer` ocurre en el hilo principal, que es lo que
 * exige la API. Llamarla desde otro hilo lanza excepción.
 */
class AndroidSpeechEngine(private val context: Context) : TranscriptionEngine {

    override val engineId = "android-speech"

    override var listener: EngineListener? = null

    private val executor = Executors.newSingleThreadExecutor()
    private var recognizer: SpeechRecognizer? = null
    private var sawFinal = false

    // ------------------------------------------------------------ disponibilidad

    override fun availability(locale: String, onResult: (Map<String, Any?>) -> Unit) {
        val onDeviceAvailable = SpeechRecognizer.isOnDeviceRecognitionAvailable(context)
        val anyAvailable = SpeechRecognizer.isRecognitionAvailable(context)

        val base = mutableMapOf<String, Any?>(
            "available" to anyAvailable,
            "onDeviceAvailable" to onDeviceAvailable,
            "engineName" to "Android SpeechRecognizer",
            "engineVersion" to "API ${android.os.Build.VERSION.SDK_INT}",
            "modelName" to null,
        )

        if (!anyAvailable) {
            onResult(
                base.apply {
                    put("installedLocales", emptyList<String>())
                    put("supportedLocales", emptyList<String>())
                    put("effectiveLocale", null)
                    put("requiresNetwork", true)
                    put("detail", "isRecognitionAvailable=false")
                },
            )
            return
        }

        val probe = if (onDeviceAvailable) {
            SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
        } else {
            SpeechRecognizer.createSpeechRecognizer(context)
        }
        var answered = false
        probe.checkRecognitionSupport(
            buildIntent(locale, preferOffline = true, partialResults = true),
            executor,
            object : RecognitionSupportCallback {
                override fun onSupportResult(support: RecognitionSupport) {
                    if (answered) return
                    answered = true
                    val installed = support.installedOnDeviceLanguages
                    val effective = resolveEffectiveLocale(locale, installed)
                    // Que la API on-device EXISTA no significa que pueda
                    // transcribir sin red: hace falta el modelo del idioma ya
                    // descargado. Sin el, prometer offline seria falso
                    // (`EVO-009-REQ-008`), asi que aqui se informa la capacidad
                    // real y el flag crudo de la API queda en `detail`.
                    val worksOffline = onDeviceAvailable && effective != null
                    onResult(
                        base.apply {
                            put("onDeviceAvailable", worksOffline)
                            put("installedLocales", installed)
                            put("supportedLocales", support.supportedOnDeviceLanguages)
                            put("effectiveLocale", effective)
                            put("requiresNetwork", !worksOffline)
                            put(
                                "detail",
                                "apiOnDevice=$onDeviceAvailable " +
                                    "instalados=${installed.size} " +
                                    "pendientes=${support.pendingOnDeviceLanguages.size} " +
                                    "online=${support.onlineLanguages.size}",
                            )
                        },
                    )
                    probe.destroy()
                }

                override fun onError(error: Int) {
                    if (answered) return
                    answered = true
                    onResult(
                        base.apply {
                            put("installedLocales", emptyList<String>())
                            put("supportedLocales", emptyList<String>())
                            put("effectiveLocale", null)
                            put("requiresNetwork", true)
                            put("detail", "checkRecognitionSupport error=$error")
                        },
                    )
                    probe.destroy()
                }
            },
        )
    }

    // ------------------------------------------------------------------- sesión

    override fun start(locale: String, preferOffline: Boolean, partialResults: Boolean) {
        cancel()
        sawFinal = false
        val useOnDevice =
            preferOffline && SpeechRecognizer.isOnDeviceRecognitionAvailable(context)
        val rec = try {
            if (useOnDevice) {
                SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
            } else {
                SpeechRecognizer.createSpeechRecognizer(context)
            }
        } catch (t: Throwable) {
            listener?.onError("serviceUnavailable", t.javaClass.simpleName)
            return
        }
        recognizer = rec
        rec.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) = notifyState("listening")
            override fun onBeginningOfSpeech() = Unit
            override fun onRmsChanged(rmsdB: Float) = Unit
            override fun onBufferReceived(buffer: ByteArray?) = Unit
            override fun onEndOfSpeech() = notifyState("processing")
            override fun onEvent(eventType: Int, params: Bundle?) = Unit

            override fun onPartialResults(partialResults: Bundle?) {
                val text = firstResult(partialResults) ?: return
                if (text.isNotEmpty()) listener?.onPartial(text)
            }

            override fun onResults(results: Bundle?) {
                sawFinal = true
                listener?.onFinal(firstResult(results).orEmpty())
                releaseRecognizer()
            }

            override fun onError(error: Int) {
                // Tras un final, Android puede seguir emitiendo errores de la
                // sesion ya cerrada; reportarlos borraria un resultado valido.
                if (sawFinal) return
                listener?.onError(mapError(error), "android-error-$error")
                releaseRecognizer()
            }
        })
        try {
            rec.startListening(buildIntent(locale, preferOffline, partialResults))
        } catch (t: Throwable) {
            listener?.onError("engineFailure", t.javaClass.simpleName)
            releaseRecognizer()
        }
    }

    override fun stop() {
        recognizer?.stopListening()
    }

    override fun cancel() {
        recognizer?.let {
            try {
                it.cancel()
            } catch (_: Throwable) {
                // Cancelar siempre debe terminar soltando el microfono.
            }
        }
        releaseRecognizer()
    }

    override fun release() {
        cancel()
        executor.shutdownNow()
    }

    // ------------------------------------------------------------------ privado

    private fun releaseRecognizer() {
        recognizer?.destroy()
        recognizer = null
    }

    private fun notifyState(state: String) {
        listener?.onState(state)
    }

    private fun buildIntent(
        locale: String,
        preferOffline: Boolean,
        partialResults: Boolean,
    ): Intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
        putExtra(
            RecognizerIntent.EXTRA_LANGUAGE_MODEL,
            RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
        )
        putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
        putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, partialResults)
        putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, preferOffline)
        putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
    }

    private fun firstResult(bundle: Bundle?): String? =
        bundle?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()

    private fun mapError(error: Int): String = when (error) {
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "permissionDenied"
        SpeechRecognizer.ERROR_NETWORK,
        SpeechRecognizer.ERROR_NETWORK_TIMEOUT,
        -> "networkRequired"
        SpeechRecognizer.ERROR_NO_MATCH -> "noMatch"
        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "timeout"
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "busy"
        SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE,
        SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED,
        -> "localeUnavailable"
        SpeechRecognizer.ERROR_SERVER,
        SpeechRecognizer.ERROR_SERVER_DISCONNECTED,
        SpeechRecognizer.ERROR_CANNOT_CHECK_SUPPORT,
        -> "serviceUnavailable"
        else -> "engineFailure"
    }
}
