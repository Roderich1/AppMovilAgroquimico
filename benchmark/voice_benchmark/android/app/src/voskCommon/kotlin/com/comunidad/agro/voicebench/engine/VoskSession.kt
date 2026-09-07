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

    /**
     * Lo que Vosk ya confirmó en esta sesión.
     *
     * Hace falta porque Vosk cierra un tramo en cada pausa y se reinicia: sin
     * acumularlos, `getFinalResult()` devuelve vacío y una frase transcrita
     * correctamente se registra como «sin habla». Medido en el HONOR.
     */
    private val transcript = VoskTranscript()

    /** Cuántos tramos cerró el motor en la última sesión. Métrica. */
    val segmentCount: Int get() = transcript.segmentCount

    /** Milisegundos que tardó la última carga del modelo. Métrica de arranque. */
    var lastModelLoadMs: Long = 0
        private set

    /**
     * Por qué falló la última carga, con nombre de excepción y mensaje.
     *
     * Un diagnóstico que sólo dice `serviceUnavailable` no permite decidir
     * nada: hay media docena de motivos distintos por los que una librería
     * nativa no carga y cada uno se arregla de otra manera. Nunca lleva texto
     * dictado; sólo lo que dijo el sistema.
     */
    var lastLoadFailure: String? = null
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
        val directory = VoskModelStore.ensureModel(context)
        if (directory == null) {
            lastLoadFailure = "modelo no disponible en assets ni en almacenamiento"
            return "serviceUnavailable"
        }
        modelDirectory = directory
        return try {
            LibVosk.setLogLevel(LogLevel.WARNINGS)
            val started = System.nanoTime()
            model = Model(directory.absolutePath)
            lastModelLoadMs = (System.nanoTime() - started) / 1_000_000
            lastLoadFailure = null
            null
        } catch (t: UnsatisfiedLinkError) {
            // Librería nativa ausente o incompatible con la ABI o el tamaño de
            // página del aparato. Es un fallo distinto de "no hay modelo".
            lastLoadFailure = describe(t)
            "serviceUnavailable"
        } catch (t: Throwable) {
            lastLoadFailure = describe(t)
            "engineFailure"
        }
    }

    /** Nombre y mensaje de la excepción, incluida su causa. Sin datos dictados. */
    private fun describe(t: Throwable): String = buildString {
        append(t.javaClass.name)
        t.message?.let { append(": ").append(it.take(300)) }
        t.cause?.let { cause ->
            append(" <- ").append(cause.javaClass.name)
            cause.message?.let { append(": ").append(it.take(200)) }
        }
    }

    /** Abre un reconocedor para una sesión nueva. */
    fun open(): String? {
        ensureLoaded()?.let { return it }
        close()
        transcript.reset()
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
                // Fin de un tramo: Vosk lo entrega y **se reinicia**. Hay que
                // guardarlo aquí; `getFinalResult()` ya no lo devolverá.
                transcript.addSegment(textOf(active.result, "text"))
            } else {
                transcript.setPartial(textOf(active.partialResult, "partial"))
            }
            transcript.display()
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
            transcript.finish(textOf(active.finalResult, "text"))
        } catch (_: Throwable) {
            // Si el motor falla al cerrar, lo ya confirmado sigue siendo válido:
            // perderlo castigaría al usuario por un fallo del último tramo.
            transcript.finish(null)
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
