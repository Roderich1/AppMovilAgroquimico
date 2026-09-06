package com.comunidad.agro.voicebench

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Une el puerto de Dart con el motor nativo del sabor instalado.
 *
 * Sólo transporta **texto y estados**. El audio no cruza este puente, no se
 * guarda en disco y no aparece en el log.
 */
class SpeechBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
    private val engine: TranscriptionEngine,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler, EngineListener {

    private val method = MethodChannel(messenger, METHOD_CHANNEL)
    private val event = EventChannel(messenger, EVENT_CHANNEL)
    private val main = Handler(Looper.getMainLooper())

    private var sink: EventChannel.EventSink? = null
    private var pendingStart: Triple<String, Boolean, Boolean>? = null

    init {
        method.setMethodCallHandler(this)
        event.setStreamHandler(this)
        engine.listener = this
    }

    fun detach() {
        engine.release()
        engine.listener = null
        method.setMethodCallHandler(null)
        event.setStreamHandler(null)
        sink = null
    }

    // ------------------------------------------------------------ MethodChannel

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "availability" -> {
                val locale = call.argument<String>("locale") ?: "es-BO"
                // Se responde desde el callback: la consulta de idiomas del
                // sistema es asincrona y bloquear aqui seria un ANR.
                engine.availability(locale) { map ->
                    val payload = map.toMutableMap()
                    payload["engineId"] = engine.engineId
                    main.post { result.success(payload) }
                }
            }

            "start" -> {
                val locale = call.argument<String>("locale") ?: "es-BO"
                val preferOffline = call.argument<Boolean>("preferOffline") ?: true
                val partials = call.argument<Boolean>("partialResults") ?: true
                if (hasMicPermission()) {
                    engine.start(locale, preferOffline, partials)
                } else {
                    // Permiso en contexto: se pide al tocar, no al abrir la app.
                    pendingStart = Triple(locale, preferOffline, partials)
                    onState("requestingPermission")
                    ActivityCompat.requestPermissions(
                        activity,
                        arrayOf(Manifest.permission.RECORD_AUDIO),
                        MIC_REQUEST,
                    )
                }
                result.success(null)
            }

            "stop" -> {
                engine.stop(); result.success(null)
            }

            "cancel" -> {
                pendingStart = null
                engine.cancel(); result.success(null)
            }

            "dispose" -> {
                pendingStart = null
                engine.release(); result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    /**
     * La Activity perdió el foco: llamada entrante, bloqueo de pantalla, cambio
     * de aplicación. Se cancela y se suelta el micrófono sin depender de que
     * Dart alcance a pedirlo.
     */
    fun onHostPaused() {
        pendingStart = null
        engine.cancel()
        onState("cancelled")
    }

    /** Lo llama la Activity al volver del diálogo de permisos. */
    fun onPermissionResult(granted: Boolean) {
        val pending = pendingStart ?: return
        pendingStart = null
        if (granted) {
            engine.start(pending.first, pending.second, pending.third)
        } else {
            // Denegación permanente: el sistema ya no muestra el diálogo.
            val permanent = !ActivityCompat.shouldShowRequestPermissionRationale(
                activity,
                Manifest.permission.RECORD_AUDIO,
            )
            onError(
                if (permanent) "permissionPermanentlyDenied" else "permissionDenied",
                null,
            )
        }
    }

    private fun hasMicPermission(): Boolean =
        ActivityCompat.checkSelfPermission(activity, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED

    // ------------------------------------------------------------- EventChannel

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    // ----------------------------------------------------------- EngineListener

    override fun onState(state: String) = send(mapOf("type" to "state", "state" to state))

    override fun onPartial(text: String) = send(mapOf("type" to "partial", "text" to text))

    override fun onFinal(text: String) = send(mapOf("type" to "final", "text" to text))

    override fun onError(code: String, detail: String?) =
        send(mapOf("type" to "error", "code" to code, "detail" to detail))

    private fun send(payload: Map<String, Any?>) {
        main.post { sink?.success(payload) }
    }

    companion object {
        const val METHOD_CHANNEL = "agro.voicebench/speech"
        const val EVENT_CHANNEL = "agro.voicebench/speech_events"
        const val MIC_REQUEST = 4201
    }
}
