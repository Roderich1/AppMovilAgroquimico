package com.comunidad.agro.voicebench.audio

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import java.util.concurrent.atomic.AtomicBoolean

/**
 * La **única** captura de audio del banco.
 *
 * ## Por qué existe una sola
 *
 * `ADR-004` prohíbe abrir dos micrófonos: el candidato híbrido alimenta Vosk
 * mientras graba y pasa el mismo audio a Whisper al detener. Si cada motor
 * abriera su propio `AudioRecord`, el híbrido mediría dos capturas distintas
 * —dos ganancias, dos instantes de arranque— y la comparación con los motores
 * aislados dejaría de significar nada. Además Android puede negar el segundo
 * micrófono, que es un fallo que sólo aparece en el teléfono.
 *
 * Por eso los tres caminos —Vosk, Whisper e híbrido— usan esta clase.
 *
 * ## Lo que esta clase garantiza
 *
 * - PCM 16 kHz, mono, 16 bits, que es lo que esperan los dos motores;
 * - el audio vive **en memoria**: no se escribe a disco en ningún camino;
 * - el buffer está **acotado**: al llegar al tope se deja de acumular en vez de
 *   crecer sin límite;
 * - el micrófono se suelta siempre, gane o falle la sesión;
 * - `stop` y `cancel` son idempotentes.
 *
 * Un `generation` que aumenta en cada arranque invalida los callbacks de una
 * sesión ya cerrada: sin él, el hilo de lectura de una sesión cancelada podría
 * seguir entregando fragmentos a la siguiente.
 */
class PcmCapture {

    /** Lo que va llegando del micrófono, mientras la sesión sigue viva. */
    fun interface Sink {
        /**
         * @param generation sesión a la que pertenece este fragmento.
         * @param length bytes válidos de [buffer].
         */
        fun onAudio(generation: Long, buffer: ByteArray, length: Int)
    }

    private val recording = AtomicBoolean(false)
    private var recorder: AudioRecord? = null
    private var thread: Thread? = null

    /** Sesión actual. Aumenta en cada [start] y descarta lo anterior. */
    @Volatile
    var generation: Long = 0
        private set

    /** Copia acotada del audio de la sesión, para el motor de segunda pasada. */
    private var retained: ByteArray? = null
    private var retainedLength = 0
    private var retainLimit = 0

    val isRecording: Boolean get() = recording.get()

    /** Bytes retenidos de la sesión en curso. */
    val retainedBytes: Int get() = retainedLength

    /**
     * Abre el micrófono.
     *
     * @param retainBytes tope de audio conservado. `0` no conserva nada, que es
     *   lo que necesita un motor de streaming puro.
     * @return `null` si arrancó; si no, el código de error del puerto.
     */
    fun start(sink: Sink?, retainBytes: Int): String? {
        if (recording.get()) return "busy"

        val minBuffer = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        if (minBuffer <= 0) return "engineFailure"

        val record = try {
            AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION,
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                minBuffer * 4,
            )
        } catch (_: Throwable) {
            // Sin permiso de micrófono el constructor lanza. No es un fallo del
            // motor y la interfaz debe poder distinguirlo.
            return "permissionDenied"
        }
        if (record.state != AudioRecord.STATE_INITIALIZED) {
            record.release()
            return "permissionDenied"
        }

        generation++
        val session = generation
        recorder = record
        retainLimit = retainBytes
        retained = if (retainBytes > 0) ByteArray(retainBytes) else null
        retainedLength = 0
        recording.set(true)

        try {
            record.startRecording()
        } catch (_: Throwable) {
            releaseRecorder()
            recording.set(false)
            return "engineFailure"
        }

        thread = Thread {
            val buffer = ByteArray(minBuffer)
            while (recording.get() && session == generation) {
                val read = try {
                    record.read(buffer, 0, buffer.size)
                } catch (_: Throwable) {
                    break
                }
                if (read <= 0) continue
                retain(buffer, read)
                sink?.onAudio(session, buffer, read)
            }
        }.also { it.start() }
        return null
    }

    /**
     * Cierra la captura y devuelve el audio retenido.
     *
     * Devuelve `null` si no había sesión. El micrófono queda libre siempre.
     */
    fun stop(): ByteArray? {
        if (!recording.compareAndSet(true, false)) return null
        thread?.join(STOP_TIMEOUT_MS)
        thread = null
        releaseRecorder()
        val audio = retained?.copyOf(retainedLength)
        // El audio muere aquí salvo que el llamador lo pida: no se escribe a
        // disco ni se conserva más allá de la sesión.
        retained = null
        retainedLength = 0
        return audio
    }

    /**
     * Descarta la sesión sin devolver audio.
     *
     * Aumentar [generation] invalida cualquier callback tardío del hilo de
     * lectura: un fragmento de la sesión anterior no puede colarse en la
     * siguiente.
     */
    fun cancel() {
        recording.set(false)
        generation++
        thread?.join(STOP_TIMEOUT_MS)
        thread = null
        releaseRecorder()
        retained = null
        retainedLength = 0
    }

    private fun retain(buffer: ByteArray, length: Int) {
        val target = retained ?: return
        if (retainedLength >= retainLimit) return
        val room = minOf(length, retainLimit - retainedLength)
        System.arraycopy(buffer, 0, target, retainedLength, room)
        retainedLength += room
    }

    private fun releaseRecorder() {
        recorder?.let {
            try {
                it.stop()
            } catch (_: Throwable) {
                // Detener puede fallar si el sistema ya quito el microfono; lo
                // que importa es que se libere.
            }
            it.release()
        }
        recorder = null
    }

    companion object {
        const val SAMPLE_RATE = 16_000
        const val BYTES_PER_SECOND = SAMPLE_RATE * 2

        /** Tope por defecto: 90 s, el que fija `ADR-004`. 2,88 MB de PCM. */
        const val DEFAULT_RETAIN_SECONDS = 90
        const val DEFAULT_RETAIN_BYTES = BYTES_PER_SECOND * DEFAULT_RETAIN_SECONDS

        private const val STOP_TIMEOUT_MS = 1_000L

        /** PCM16 little-endian a float en [-1, 1], que es lo que espera whisper. */
        fun toFloatMono(pcm: ByteArray, length: Int = pcm.size): FloatArray {
            val samples = FloatArray(length / 2)
            for (i in samples.indices) {
                val lo = pcm[i * 2].toInt() and 0xFF
                val hi = pcm[i * 2 + 1].toInt()
                samples[i] = ((hi shl 8) or lo) / 32768.0f
            }
            return samples
        }
    }
}
