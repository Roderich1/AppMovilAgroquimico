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
 * Une `LocalSpeechTranscriptionAdapter` (Dart) con [LocalVoiceEngine].
 *
 * Sólo transporta **texto, estados y códigos**. El audio no cruza el puente,
 * no se guarda y no aparece en el log. El permiso se pide **al tocar**, como en
 * el puente del reconocedor del sistema (`VoiceSpeechBridge`), con las mismas
 * correcciones de `DEFECTO-005`: un solo diálogo a la vez y la petición
 * pendiente sobrevive a la pausa que provoca el propio diálogo.
 */
class LocalVoiceBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    LocalVoiceEngine.Listener {

    private val method = MethodChannel(messenger, METHOD_CHANNEL)
    private val event = EventChannel(messenger, EVENT_CHANNEL)
    private val main = Handler(Looper.getMainLooper())
    private val engine = LocalVoiceEngine(activity.applicationContext, this)

    private var sink: EventChannel.EventSink? = null
    private var pendingStart: PendingStart? = null
    private var permissionInFlight = false

    private data class PendingStart(val gen: Int, val hints: String?, val review: Boolean)

    init {
        method.setMethodCallHandler(this)
        event.setStreamHandler(this)
    }

    fun detach() {
        permissionInFlight = false
        pendingStart = null
        engine.release()
        method.setMethodCallHandler(null)
        event.setStreamHandler(null)
        sink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "describe" -> result.success(
                engine.describe() + mapOf("airplaneMode" to airplaneMode()),
            )

            "prepare" -> engine.prepare { code -> main.post { result.success(code) } }

            "start" -> {
                val gen = call.argument<Int>("gen") ?: 0
                val hints = call.argument<String>("hints")
                val review = call.argument<Boolean>("review") ?: true
                if (hasMicPermission()) {
                    engine.start(gen, hints, review)
                    result.success(null)
                } else {
                    pendingStart = PendingStart(gen, hints, review)
                    // La respuesta dice YA que habrá diálogo: llega a Dart antes
                    // que la pausa que el propio diálogo provoca. Si Dart se
                    // enterara sólo por el evento, la pausa podría llegar antes,
                    // la sesión cancelaría y conceder no arrancaría nada
                    // (medido en el emulador, 2026-11-05).
                    result.success("awaitingPermission")
                    if (!permissionInFlight) {
                        permissionInFlight = true
                        activity.requestPermissions(
                            arrayOf(Manifest.permission.RECORD_AUDIO),
                            MIC_REQUEST,
                        )
                    }
                }
            }

            "stop" -> {
                engine.stop(call.argument<Int>("gen") ?: 0)
                result.success(null)
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

    /** La Activity perdió el foco: se suelta el micrófono sin esperar a Dart. */
    fun onHostPaused() {
        // El diálogo de permisos pausa esta Activity; mientras se espera no hay
        // micrófono abierto y la petición debe sobrevivir (`DEFECTO-005`).
        if (pendingStart != null) return
        engine.cancel()
        send(mapOf("type" to "cancelled"))
    }

    fun onPermissionResult(granted: Boolean) {
        permissionInFlight = false
        val pending = pendingStart ?: return
        pendingStart = null
        if (granted) {
            engine.start(pending.gen, pending.hints, pending.review)
            return
        }
        val permanent = !activity.shouldShowRequestPermissionRationale(
            Manifest.permission.RECORD_AUDIO,
        )
        onError(
            pending.gen,
            if (permanent) "permissionPermanentlyDenied" else "permissionDenied",
            null,
        )
    }

    private fun hasMicPermission(): Boolean =
        activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED

    private fun airplaneMode(): Boolean? = try {
        Settings.Global.getInt(activity.contentResolver, Settings.Global.AIRPLANE_MODE_ON) == 1
    } catch (_: Throwable) {
        null
    }

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

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    // --------------------------------------------------------- Engine.Listener

    override fun onStage(gen: Int, stage: String) =
        send(mapOf("type" to "stage", "gen" to gen, "stage" to stage))

    override fun onPartial(gen: Int, text: String, reviewing: Int) =
        send(mapOf("type" to "partial", "gen" to gen, "text" to text, "reviewing" to reviewing))

    override fun onSegment(gen: Int, seq: Int, vosk: String, review: String?, reviewMs: Long) =
        send(
            mapOf(
                "type" to "segment", "gen" to gen, "seq" to seq, "vosk" to vosk,
                "review" to review, "reviewMs" to reviewMs,
            ),
        )

    override fun onEnded(gen: Int, reason: String) =
        send(mapOf("type" to "ended", "gen" to gen, "reason" to reason))

    override fun onError(gen: Int, code: String, detail: String?) =
        send(mapOf("type" to "error", "gen" to gen, "code" to code, "detail" to detail))

    private fun send(payload: Map<String, Any?>) {
        main.post { sink?.success(payload) }
    }

    companion object {
        const val METHOD_CHANNEL = "agro.voice/local"
        const val EVENT_CHANNEL = "agro.voice/local_events"
        const val MIC_REQUEST = 9010
    }
}
