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

    private data class PendingStart(
        val gen: Int,
        val hints: String?,
        val review: Boolean,
        val reviewTimeoutMs: Long,
        val compare: List<Pair<String, String>>,
        val mode: String,
        val variant: String?,
        val turnMaxMs: Long,
        val turnTimeoutMs: Long,
        val beamSize: Int,
    ) {
        fun startOn(engine: LocalVoiceEngine) = engine.start(
            gen, hints, review, reviewTimeoutMs, compare, mode, variant, turnMaxMs, turnTimeoutMs,
            beamSize,
        )
    }

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
                // Tope de la revisión por frase; sin él (Dart anterior), el
                // valor por defecto del motor.
                val reviewTimeoutMs = call.argument<Number>("reviewTimeoutMs")?.toLong()
                    ?: LocalVoiceEngine.DEFAULT_REVIEW_TIMEOUT_MS
                // Sólo diagnóstico: pistas alternativas [etiqueta, pista] para
                // comparar sobre el mismo audio. Sin ellas, lista vacía.
                val compare = (call.argument<List<Any?>>("compare") ?: emptyList()).mapNotNull { item ->
                    val pair = item as? List<*> ?: return@mapNotNull null
                    val label = pair.getOrNull(0) as? String ?: return@mapNotNull null
                    label to (pair.getOrNull(1) as? String ?: "")
                }
                // Experimento F09: `whole` transcribe todo el turno de una vez
                // con la variante pedida de Whisper; sin él, el modo por frases.
                val mode = call.argument<String>("mode") ?: LocalVoiceEngine.MODE_PHRASES
                val variant = call.argument<String>("variant")
                val turnMaxMs = call.argument<Number>("turnMaxMs")?.toLong()
                    ?: LocalVoiceEngine.DEFAULT_TURN_MAX_MS
                val turnTimeoutMs = call.argument<Number>("turnTimeoutMs")?.toLong()
                    ?: LocalVoiceEngine.DEFAULT_TURN_TIMEOUT_MS
                // Ancho del haz del turno entero (F09, 2026-11-10); 1 = voraz.
                val beamSize = call.argument<Number>("beamSize")?.toInt() ?: 1
                val pending = PendingStart(
                    gen, hints, review, reviewTimeoutMs, compare, mode, variant, turnMaxMs, turnTimeoutMs,
                    beamSize,
                )
                if (hasMicPermission()) {
                    pending.startOn(engine)
                    result.success(null)
                } else {
                    pendingStart = pending
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

            // Con número, sólo ese turno: la pantalla que se va no puede
            // cortar el turno que ya abrió la siguiente (#119).
            "cancel" -> {
                cancelTurn(call.argument<Int>("gen"))
                result.success(null)
            }

            "openSettings" -> result.success(openAppSettings())

            // La pantalla se va: suelta su turno y, si no queda ninguno, la
            // memoria de los modelos. El motor sigue sirviendo a la siguiente.
            "dispose" -> {
                cancelTurn(call.argument<Int>("gen"))
                engine.releaseIfIdle()
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
            pending.startOn(engine)
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

    private fun cancelTurn(gen: Int?) {
        if (gen == null || pendingStart?.gen == gen) pendingStart = null
        engine.cancel(gen)
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

    override fun onPhrase(gen: Int, seq: Int, vosk: String, review: Boolean) =
        send(mapOf("type" to "phrase", "gen" to gen, "seq" to seq, "vosk" to vosk, "review" to review))

    // Sólo números y códigos de la frase; nunca audio ni texto.
    override fun onPhraseInfo(gen: Int, seq: Int, info: Map<String, Any?>) =
        send(mapOf("type" to "phraseInfo", "gen" to gen, "seq" to seq, "info" to info))

    // Sólo diagnóstico: otra transcripción del mismo audio, para la vista.
    override fun onComparison(gen: Int, seq: Int, label: String, text: String?, ms: Long, outcome: String) =
        send(
            mapOf(
                "type" to "comparison", "gen" to gen, "seq" to seq, "label" to label,
                "text" to text, "ms" to ms, "outcome" to outcome,
            ),
        )

    override fun onSegment(gen: Int, seq: Int, vosk: String, review: String?, reviewMs: Long) =
        send(
            mapOf(
                "type" to "segment", "gen" to gen, "seq" to seq, "vosk" to vosk,
                "review" to review, "reviewMs" to reviewMs,
            ),
        )

    override fun onTurnText(gen: Int, text: String?, ms: Long, outcome: String, info: Map<String, Any?>) =
        send(
            mapOf(
                "type" to "turnText", "gen" to gen, "text" to text, "ms" to ms,
                "outcome" to outcome, "info" to info,
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
