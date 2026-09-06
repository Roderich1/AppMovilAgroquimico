package com.comunidad.agro.agroquimicos

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import java.util.concurrent.Executors

/**
 * Motor de transcripción de `EVO-009` sobre `android.speech.SpeechRecognizer`.
 *
 * Es el motor productivo que fijó `ADR-002`. **No añade nada al APK**: el
 * reconocimiento lo pone el sistema.
 *
 * Reglas que esta clase no puede romper:
 *
 * - el audio **no se guarda** ni sale de este proceso;
 * - el texto **nunca** se escribe en el log: los diagnósticos llevan códigos;
 * - `SpeechRecognizer` sólo se toca desde el hilo principal, que es lo que exige
 *   la API — llamarla desde otro hilo lanza excepción;
 * - todo turno acaba soltando el micrófono, gane o falle.
 */
class VoiceSpeechEngine(private val context: Context) {

    /** Quien recibe los eventos. Lo fija el puente antes de usar el motor. */
    var listener: Listener? = null

    /** Eventos del motor. Nunca transportan audio. */
    interface Listener {
        fun onStage(stage: String)
        fun onLocale(locale: String)
        fun onPartial(text: String)
        fun onFinal(text: String)
        fun onNoMatch()
        fun onTimeout()

        /**
         * @param code nombre del `TranscriptionErrorCode` de Dart.
         * @param detail diagnóstico técnico. **Nunca** la frase dictada.
         */
        fun onError(code: String, detail: String?)
    }

    private val executor = Executors.newSingleThreadExecutor()
    private var recognizer: SpeechRecognizer? = null

    /** Un turno cerrado no puede volver a emitir: Android sigue mandando. */
    private var turnClosed = true

    // ------------------------------------------------------------ disponibilidad

    /**
     * Qué declara el aparato. **Nada de esto es una garantía**: `ADR-002` midió
     * `isOnDeviceRecognitionAvailable()` devolviendo `false` en un teléfono donde
     * el reconocimiento sin red sí funcionaba. Por eso el valor viaja crudo, con
     * el nombre `onDeviceApiReports`, y la interfaz lo muestra como dato del
     * sistema y no como promesa.
     */
    fun availability(locale: String, onResult: (Map<String, Any?>) -> Unit) {
        val onDeviceApi = Build.VERSION.SDK_INT >= 31 &&
            SpeechRecognizer.isOnDeviceRecognitionAvailable(context)
        val anyAvailable = SpeechRecognizer.isRecognitionAvailable(context)

        val base = mutableMapOf<String, Any?>(
            "recognizerAvailable" to anyAvailable,
            "onDeviceApiReports" to onDeviceApi,
            "engineName" to "Android SpeechRecognizer",
            "engineVersion" to "API ${Build.VERSION.SDK_INT}",
            "airplaneMode" to airplaneMode(),
            "installedLocales" to emptyList<String>(),
            "supportedLocales" to emptyList<String>(),
        )

        if (!anyAvailable) {
            onResult(
                base.apply {
                    put("localeSupportKnown", false)
                    put("detail", "isRecognitionAvailable=false")
                },
            )
            return
        }

        // `checkRecognitionSupport` llega en API 33. Por debajo no se puede
        // preguntar qué idiomas hay instalados, e **inventar una lista vacía
        // seria mentir**: vacio significa "ninguno", no "no se sabe". Se marca
        // el dato como no consultable y la eleccion del idioma se resuelve
        // intentando, que es lo que exige `EVO-009-REQ-014`.
        if (Build.VERSION.SDK_INT < 33) {
            onResult(
                base.apply {
                    put("localeSupportKnown", false)
                    put(
                        "detail",
                        "API ${Build.VERSION.SDK_INT}: checkRecognitionSupport " +
                            "requiere API 33; idiomas instalados NO consultables. " +
                            "apiOnDevice=$onDeviceApi",
                    )
                },
            )
            return
        }

        val probe = try {
            if (onDeviceApi) {
                SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
            } else {
                SpeechRecognizer.createSpeechRecognizer(context)
            }
        } catch (t: Throwable) {
            onResult(
                base.apply {
                    put("localeSupportKnown", false)
                    put("detail", "probe:${t.javaClass.simpleName}")
                },
            )
            return
        }

        var answered = false
        probe.checkRecognitionSupport(
            buildIntent(locale, preferOffline = true, partialResults = true),
            executor,
            object : RecognitionSupportCallback {
                override fun onSupportResult(support: RecognitionSupport) {
                    if (answered) return
                    answered = true
                    onResult(
                        base.apply {
                            put("localeSupportKnown", true)
                            put("installedLocales", support.installedOnDeviceLanguages)
                            put("supportedLocales", support.supportedOnDeviceLanguages)
                            put(
                                "detail",
                                "apiOnDevice=$onDeviceApi " +
                                    "instalados=${support.installedOnDeviceLanguages.size} " +
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
                            put("localeSupportKnown", false)
                            put("detail", "checkRecognitionSupport error=$error")
                        },
                    )
                    probe.destroy()
                }
            },
        )
    }

    /**
     * Modo avión **según el sistema**, no según quien prueba.
     *
     * `AIRPLANE_MODE_ON` se lee sin permisos y sin tocar la red. Es el dato con
     * el que `ADR-002` verificó el funcionamiento sin Internet, y el único que
     * permite a la interfaz decir "aquí transcribió sin red" sin mentir.
     */
    private fun airplaneMode(): Boolean? = try {
        Settings.Global.getInt(
            context.contentResolver,
            Settings.Global.AIRPLANE_MODE_ON,
            0,
        ) != 0
    } catch (_: Throwable) {
        null
    }

    // ------------------------------------------------------------------- turno

    fun start(locale: String, preferOffline: Boolean, partialResults: Boolean) {
        releaseRecognizer()
        turnClosed = false

        val useOnDevice = preferOffline &&
            Build.VERSION.SDK_INT >= 31 &&
            SpeechRecognizer.isOnDeviceRecognitionAvailable(context)
        val rec = try {
            if (useOnDevice) {
                SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
            } else {
                SpeechRecognizer.createSpeechRecognizer(context)
            }
        } catch (t: Throwable) {
            fail("recognizerUnavailable", t.javaClass.simpleName)
            return
        }
        recognizer = rec
        rec.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {
                if (turnClosed) return
                listener?.onStage("listening")
                // El motor aceptó este idioma. Antes de esto la interfaz no
                // puede afirmar en cuál escucha (`EVO-009-REQ-015`).
                listener?.onLocale(locale)
            }

            override fun onBeginningOfSpeech() = Unit
            override fun onRmsChanged(rmsdB: Float) = Unit
            override fun onBufferReceived(buffer: ByteArray?) = Unit
            override fun onEvent(eventType: Int, params: Bundle?) = Unit

            override fun onEndOfSpeech() {
                if (turnClosed) return
                listener?.onStage("processing")
            }

            override fun onPartialResults(partialResults: Bundle?) {
                if (turnClosed) return
                val text = firstResult(partialResults) ?: return
                if (text.isNotEmpty()) listener?.onPartial(text)
            }

            override fun onResults(results: Bundle?) {
                if (turnClosed) return
                turnClosed = true
                listener?.onFinal(firstResult(results).orEmpty())
                releaseRecognizer()
            }

            override fun onError(error: Int) {
                // Tras cerrar el turno, Android puede seguir emitiendo errores
                // de la sesion ya terminada; reportarlos borraria un resultado
                // valido y provocaria un reinicio en falso.
                if (turnClosed) return
                turnClosed = true
                when (error) {
                    ERROR_NO_MATCH -> listener?.onNoMatch()
                    ERROR_SPEECH_TIMEOUT -> listener?.onTimeout()
                    else -> listener?.onError(mapError(error), "android-error-$error")
                }
                releaseRecognizer()
            }
        })
        try {
            rec.startListening(buildIntent(locale, preferOffline, partialResults))
        } catch (t: Throwable) {
            fail("engineFailure", t.javaClass.simpleName)
        }
    }

    fun stop() {
        try {
            recognizer?.stopListening()
        } catch (_: Throwable) {
            // Pedir el resultado no puede tumbar la pantalla; si falla, el
            // cierre llegara por error o por el plazo del turno.
        }
    }

    /** Descarta el turno y suelta el micrófono. No emite resultado. */
    fun cancel() {
        turnClosed = true
        try {
            recognizer?.cancel()
        } catch (_: Throwable) {
            // Cancelar siempre debe terminar soltando el microfono.
        }
        releaseRecognizer()
    }

    fun release() {
        cancel()
        listener = null
        executor.shutdownNow()
    }

    // ----------------------------------------------------------------- privado

    private fun fail(code: String, detail: String?) {
        turnClosed = true
        listener?.onError(code, detail)
        releaseRecognizer()
    }

    private fun releaseRecognizer() {
        try {
            recognizer?.destroy()
        } catch (_: Throwable) {
            // Ya estaba destruido: el objetivo era que no quedara vivo.
        }
        recognizer = null
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
        // Preferencia, no garantía (`EVO-009-REQ-013`). El sistema puede
        // ignorarla, y por eso el modo offline se comprueba transcribiendo.
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
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "busy"
        SpeechRecognizer.ERROR_CLIENT -> "clientError"
        SpeechRecognizer.ERROR_SERVER -> "serverError"
        // Constantes declaradas en API 33 pero **devueltas ya en API 31**: es
        // exactamente lo que midió `ADR-002` en el POCO X5 Pro (12 con `es-BO`,
        // 13 con `es-ES`). Se usan los enteros para no depender del nivel de
        // compilación y para que el mapeo valga en el aparato de referencia.
        ERROR_TOO_MANY_REQUESTS, ERROR_SERVER_DISCONNECTED -> "serverError"
        ERROR_LANGUAGE_NOT_SUPPORTED, ERROR_LANGUAGE_UNAVAILABLE -> "localeUnavailable"
        ERROR_CANNOT_CHECK_SUPPORT, ERROR_CANNOT_LISTEN_TO_DOWNLOAD_EVENTS ->
            "recognizerUnavailable"
        else -> "engineFailure"
    }

    private companion object {
        const val ERROR_NO_MATCH = SpeechRecognizer.ERROR_NO_MATCH
        const val ERROR_SPEECH_TIMEOUT = SpeechRecognizer.ERROR_SPEECH_TIMEOUT
        const val ERROR_TOO_MANY_REQUESTS = 10
        const val ERROR_SERVER_DISCONNECTED = 11
        const val ERROR_LANGUAGE_NOT_SUPPORTED = 12
        const val ERROR_LANGUAGE_UNAVAILABLE = 13
        const val ERROR_CANNOT_CHECK_SUPPORT = 14
        const val ERROR_CANNOT_LISTEN_TO_DOWNLOAD_EVENTS = 15
    }
}
