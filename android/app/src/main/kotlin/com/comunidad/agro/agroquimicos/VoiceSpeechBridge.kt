package com.comunidad.agro.agroquimicos

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Une `AndroidSpeechTranscriptionAdapter` con el motor del sistema.
 *
 * Sólo transporta **texto y estados**. El audio no cruza este puente, no se
 * guarda en disco y no aparece en el log.
 *
 * El permiso de micrófono se pide **aquí y al tocar**, no al abrir la
 * aplicación (`EVO-009-REQ-004`): sólo este lado sabe si el diálogo hace falta.
 */
class VoiceSpeechBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
    private val engine: VoiceSpeechEngine,
) : MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    VoiceSpeechEngine.Listener {

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
        method.setMethodCallHandler(null)
        event.setStreamHandler(null)
        pendingStart = null
        sink = null
    }

    // ------------------------------------------------------------ MethodChannel

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "availability" -> {
                val locale = call.argument<String>("locale") ?: DEFAULT_LOCALE
                // Se responde desde el callback: consultar los idiomas del
                // sistema es asincrono y bloquear aqui seria un ANR.
                engine.availability(locale) { map -> main.post { result.success(map) } }
            }

            "start" -> {
                val locale = call.argument<String>("locale") ?: DEFAULT_LOCALE
                val preferOffline = call.argument<Boolean>("preferOffline") ?: true
                val partials = call.argument<Boolean>("partialResults") ?: true
                if (hasMicPermission()) {
                    engine.start(locale, preferOffline, partials)
                } else {
                    pendingStart = Triple(locale, preferOffline, partials)
                    onStage("awaitingPermission")
                    activity.requestPermissions(
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
                engine.cancel()
                result.success(null)
            }

            "openSettings" -> result.success(openAppSettings())

            "dispose" -> {
                pendingStart = null
                engine.release()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    /**
     * La Activity perdió el foco: llamada entrante, bloqueo de pantalla o cambio
     * de aplicación.
     *
     * Se cancela y se suelta el micrófono **sin depender de que Dart alcance a
     * pedirlo**: si el proceso se congela, el lado Dart podría no llegar nunca, y
     * `EVO-009-REQ-005` no admite un reconocedor vivo en segundo plano.
     */
    fun onHostPaused() {
        pendingStart = null
        engine.cancel()
        send(mapOf("type" to "cancelled"))
    }

    /** Lo llama la Activity al volver del diálogo de permisos. */
    fun onPermissionResult(granted: Boolean) {
        val pending = pendingStart ?: return
        pendingStart = null
        if (granted) {
            engine.start(pending.first, pending.second, pending.third)
            return
        }
        // Denegación permanente: el sistema ya no volverá a mostrar el diálogo,
        // así que la única salida son los ajustes de la aplicación.
        val permanent = !activity.shouldShowRequestPermissionRationale(
            Manifest.permission.RECORD_AUDIO,
        )
        onError(
            if (permanent) "permissionPermanentlyDenied" else "permissionDenied",
            null,
        )
    }

    private fun hasMicPermission(): Boolean =
        activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED

    /**
     * Abre la ficha de la aplicación en los ajustes.
     *
     * No concede nada ni descarga nada: sólo lleva al usuario al único sitio
     * donde puede revertir una denegación permanente.
     */
    private fun openAppSettings(): Boolean = try {
        activity.startActivity(
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", activity.packageName, null),
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        true
    } catch (_: Throwable) {
        false
    }

    // ------------------------------------------------------------- EventChannel

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    // --------------------------------------------------------- Engine.Listener

    override fun onStage(stage: String) = send(mapOf("type" to "stage", "stage" to stage))

    override fun onLocale(locale: String) =
        send(mapOf("type" to "locale", "locale" to locale))

    override fun onPartial(text: String) = send(mapOf("type" to "partial", "text" to text))

    override fun onFinal(text: String) = send(mapOf("type" to "final", "text" to text))

    override fun onNoMatch() = send(mapOf("type" to "noMatch"))

    override fun onTimeout() = send(mapOf("type" to "timeout"))

    override fun onError(code: String, detail: String?) =
        send(mapOf("type" to "error", "code" to code, "detail" to detail))

    private fun send(payload: Map<String, Any?>) {
        main.post { sink?.success(payload) }
    }

    companion object {
        const val METHOD_CHANNEL = "agro.voice/speech"
        const val EVENT_CHANNEL = "agro.voice/speech_events"
        const val MIC_REQUEST = 9009
        private const val DEFAULT_LOCALE = "es-BO"
    }
}
