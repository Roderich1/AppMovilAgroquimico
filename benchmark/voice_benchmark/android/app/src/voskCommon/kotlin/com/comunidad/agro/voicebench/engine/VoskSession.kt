package com.comunidad.agro.voicebench.engine

import android.content.Context
import com.comunidad.agro.voicebench.audio.PcmCapture
import org.json.JSONObject
import org.vosk.LibVosk
import org.vosk.LogLevel
import org.vosk.Model
import org.vosk.Recognizer
import java.io.File

/**
 * Vosk sobre el audio que le entregue quien capture.
 *
 * ## Por qué esto no abre el micrófono
 *
 * Lo abre [PcmCapture], y es deliberado: el candidato híbrido tiene que
 * alimentar Vosk **con el mismo audio** que después recibirá Whisper. Si esta
 * clase capturara por su cuenta, el híbrido abriría dos micrófonos, que es lo
 * que `ADR-004` prohíbe, y compararía dos grabaciones distintas.
 *
 * Así, el candidato Vosk aislado y el híbrido miden el mismo motor sobre la
 * misma captura, y la diferencia entre ambos es sólo lo que se quiere medir.
 *
 * ## Sobre el silencio
 *
 * Vosk no inventa: ante silencio devuelve texto vacío. Esta clase lo traduce a
 * "sin habla" en vez de a una cadena vacía que alguien pudiera aceptar como
 * resultado. Es el guardrail que `RISK-032` exige y que Whisper tiny incumplió
 * en la Fase 0 devolviendo `[MÚSICA]`.
 */
class VoskSession(private val context: Context) {

    /** `null` hasta que se carga el modelo. */
    private var model: Model? = null
    private var recognizer: Recognizer? = null

    /** Milisegundos que tardó la última carga del modelo. Métrica de arranque. */
    var lastModelLoadMs: Long = 0
        private set

    /** El modelo ya está en memoria: la siguiente sesión arranca en caliente. */
    val isLoaded: Boolean get() = model != null

    /** Carpeta del modelo, para informar tamaño y versión. */
    var modelDirectory: File? = null
        private set

    /**
     * Carga el modelo si aún no lo estaba.
     *
     * @return `null` si quedó listo; si no, el código de error del puerto.
     */
    fun ensureLoaded(): String? {
        if (model != null) return null
        val directory = VoskModelStore.ensureModel(context) ?: return "serviceUnavailable"
        modelDirectory = directory
        return try {
            LibVosk.setLogLevel(LogLevel.WARNINGS)
            val started = System.nanoTime()
            model = Model(directory.absolutePath)
            lastModelLoadMs = (System.nanoTime() - started) / 1_000_000
            null
        } catch (_: UnsatisfiedLinkError) {
            // Librería nativa ausente o incompatible con la ABI o el tamaño de
            // página del aparato. Es un fallo distinto de "no hay modelo".
            "serviceUnavailable"
        } catch (_: Throwable) {
            "engineFailure"
        }
    }

    /** Abre un reconocedor para una sesión nueva. */
    fun open(): String? {
        ensureLoaded()?.let { return it }
        close()
        return try {
            recognizer = Recognizer(model, PcmCapture.SAMPLE_RATE.toFloat())
            null
        } catch (_: Throwable) {
            "engineFailure"
        }
    }

    /**
     * Entrega un fragmento de audio.
     *
     * @return el texto parcial actual, o `null` si no cambió nada que mostrar.
     */
    fun accept(buffer: ByteArray, length: Int): String? {
        val active = recognizer ?: return null
        return try {
            if (active.acceptWaveForm(buffer, length)) {
                // Fin de una frase: Vosk cierra un segmento y empieza otro. Para
                // el banco es texto que ya no cambiará.
                textOf(active.result, "text")
            } else {
                textOf(active.partialResult, "partial")
            }
        } catch (_: Throwable) {
            null
        }
    }

    /**
     * Cierra la sesión y devuelve el texto final.
     *
     * `null` significa **sin habla**, no cadena vacía: quien lo reciba no puede
     * confundirlo con un resultado aceptable.
     */
    fun finish(): String? {
        val active = recognizer ?: return null
        return try {
            textOf(active.finalResult, "text")
        } catch (_: Throwable) {
            null
        } finally {
            close()
        }
    }

    /** Suelta el reconocedor. El modelo se conserva para no recargarlo. */
    fun close() {
        try {
            recognizer?.close()
        } catch (_: Throwable) {
            // Cerrar dos veces no puede tumbar la medicion.
        }
        recognizer = null
    }

    /** Suelta también el modelo. Idempotente. */
    fun release() {
        close()
        try {
            model?.close()
        } catch (_: Throwable) {
            // Idem: liberar es best-effort.
        }
        model = null
    }

    /** Extrae el campo del JSON de Vosk. Vacío se devuelve como `null`. */
    private fun textOf(json: String?, field: String): String? {
        if (json.isNullOrBlank()) return null
        val text = try {
            JSONObject(json).optString(field, "")
        } catch (_: Throwable) {
            ""
        }
        return text.trim().ifEmpty { null }
    }
}
