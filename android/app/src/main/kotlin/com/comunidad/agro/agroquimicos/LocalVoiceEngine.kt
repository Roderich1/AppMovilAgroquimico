package com.comunidad.agro.agroquimicos

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.SystemClock
import android.util.Log
import org.json.JSONObject
import org.vosk.LibVosk
import org.vosk.LogLevel
import org.vosk.Model
import org.vosk.Recognizer
import java.util.TreeMap
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.math.min

/**
 * Reconocimiento de voz **dentro de la app**: Vosk en vivo y, si el APK la
 * trae, una segunda pasada con whisper.cpp sobre cada frase cerrada.
 *
 * ## Flujo de un turno
 *
 * ```text
 * AudioRecord 16 kHz mono ─► cola acotada (3 s) ─► Vosk ─► parciales
 *                                                    └─► frase cerrada ─► [Whisper] ─► segmento
 * ```
 *
 * * **Un solo micrófono.** La captura es de esta clase; nadie más lo abre.
 * * **Cola acotada.** Si Vosk se retrasa, se descarta el audio más viejo de la
 *   cola en vez de acumular retraso sin límite; se cuenta, sin contenido.
 * * **Segunda pasada sólo sobre voz.** Whisper sólo ve el audio de una frase en
 *   la que Vosk ya reconoció palabras. Sobre silencio, Whisper afirma texto que
 *   nadie dijo (`[MÚSICA]`, «Subtítulos por…»): no se le da esa oportunidad.
 * * **Orden.** Los segmentos salen en el orden en que se dijeron, aunque una
 *   revisión tarde más que la siguiente frase.
 * * **Sesión numerada.** Todo evento lleva el número de turno que pidió Dart;
 *   un resultado de un turno cancelado o anterior se descarta allí.
 *
 * El audio vive en memoria y se suelta al terminar cada frase; no se escribe en
 * disco y no aparece en el log. El log sólo lleva códigos y contadores.
 */
class LocalVoiceEngine(
    context: Context,
    private val listener: Listener,
    /** De dónde sale el audio. En la app, siempre el micrófono. */
    private val openSource: () -> PcmSource = ::MicrophoneSource,
) {

    /**
     * Fuente de PCM 16 kHz mono de un turno.
     *
     * La app usa sólo [MicrophoneSource]. Existe como interfaz para que la
     * prueba instrumentada (`androidTest`) pueda pasar audio de referencia por
     * el MISMO motor, con Vosk y Whisper reales, sin micrófono.
     */
    interface PcmSource {
        /** `null` si quedó abierta; si no, (código, detalle) del fallo. */
        fun open(): Pair<String, String>?

        /** Bloquea hasta tener audio. [EOF] al terminar; otro negativo es error. */
        fun read(buffer: ShortArray): Int

        /** Desbloquea [read] y suelta el recurso. Idempotente. */
        fun close()

        companion object {
            const val EOF = Int.MIN_VALUE
        }
    }

    /** El micrófono, con `AudioRecord`. El permiso lo comprobó el puente. */
    class MicrophoneSource : PcmSource {
        private var record: AudioRecord? = null

        @SuppressLint("MissingPermission")
        override fun open(): Pair<String, String>? {
            val minBuffer = AudioRecord.getMinBufferSize(
                SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
            )
            val audio = try {
                AudioRecord(
                    MediaRecorder.AudioSource.VOICE_RECOGNITION, SAMPLE_RATE,
                    AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
                    maxOf(minBuffer, CHUNK_SAMPLES * 2 * 4),
                )
            } catch (t: Throwable) {
                return "engineFailure" to "audio:${t.javaClass.simpleName}"
            }
            if (audio.state != AudioRecord.STATE_INITIALIZED) {
                audio.release()
                return "engineFailure" to "audio-init"
            }
            try {
                audio.startRecording()
            } catch (_: Throwable) {
                audio.release()
                return "engineFailure" to "audio-start"
            }
            if (audio.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                // Otra app tiene el micrófono.
                audio.release()
                return "busy" to "microphone-in-use"
            }
            record = audio
            return null
        }

        override fun read(buffer: ShortArray): Int =
            record?.read(buffer, 0, buffer.size) ?: PcmSource.EOF

        @Synchronized
        override fun close() {
            val audio = record ?: return
            record = null
            try {
                audio.stop()
            } catch (_: Throwable) {
                // Ya detenido: lo que importa es soltar el micrófono.
            }
            audio.release()
        }
    }

    interface Listener {
        fun onStage(gen: Int, stage: String)
        fun onPartial(gen: Int, text: String, reviewing: Int)
        fun onSegment(gen: Int, seq: Int, vosk: String, review: String?, reviewMs: Long)
        fun onEnded(gen: Int, reason: String)
        fun onError(gen: Int, code: String, detail: String?)
    }

    private val models = LocalVoiceModels(context.applicationContext)

    /** Carga de modelos y orden de start/stop/cancel. Nunca el hilo principal. */
    private val control: ExecutorService = Executors.newSingleThreadExecutor { r ->
        Thread(r, "agro-voz-control")
    }

    /** Una revisión a la vez en todo el proceso: es la parte pesada. */
    private val reviewer: ExecutorService = Executors.newSingleThreadExecutor { r ->
        Thread(r, "agro-voz-revision").apply { priority = Thread.NORM_PRIORITY - 1 }
    }

    private var vosk: Model? = null
    @Volatile private var whisper: Long = 0L
    @Volatile private var whisperFailure: String? = null

    @Volatile private var turn: Turn? = null

    // ------------------------------------------------------------ disponibilidad

    /** Qué trae este APK. No abre el micrófono ni carga nada pesado. */
    fun describe(): Map<String, Any?> = mapOf(
        "modelPresent" to (models.voskName != null),
        "engineName" to "Vosk (vosk-android $VOSK_VERSION)",
        "engineVersion" to (models.voskName ?: ""),
        "reviewModel" to models.whisperName,
        "reviewAvailable" to (models.whisperName != null && WhisperNative.available),
        "reviewDetail" to (WhisperNative.loadFailure ?: whisperFailure),
    )

    /**
     * Copia, verifica y carga los modelos por adelantado, sin micrófono.
     *
     * Así el primer «Hablar» no espera la copia de ~60 MB. Devuelve `null` si
     * quedó listo, o el código de error.
     */
    fun prepare(done: (String?) -> Unit) {
        control.execute { done(ensureVosk()) }
    }

    private fun ensureVosk(): String? {
        if (vosk != null) return null
        return try {
            val dir = models.vosk()
            LibVosk.setLogLevel(LogLevel.WARNINGS)
            vosk = Model(dir.absolutePath)
            null
        } catch (e: LocalVoiceModels.ModelException) {
            e.code
        } catch (_: UnsatisfiedLinkError) {
            "native-lib"
        } catch (t: Throwable) {
            "model-load:${t.javaClass.simpleName}"
        }
    }

    private fun ensureWhisper(): Boolean {
        if (whisper != 0L) return true
        if (whisperFailure != null || !WhisperNative.available) return false
        return try {
            val file = models.whisperOrNull() ?: run {
                whisperFailure = "review-model-missing"
                return false
            }
            val started = SystemClock.elapsedRealtime()
            whisper = WhisperNative.init(file.absolutePath)
            if (whisper == 0L) whisperFailure = "review-model-load"
            Log.i(TAG, "segunda pasada cargada en ${SystemClock.elapsedRealtime() - started} ms")
            whisper != 0L
        } catch (e: LocalVoiceModels.ModelException) {
            whisperFailure = e.code
            false
        } catch (t: Throwable) {
            whisperFailure = "review-${t.javaClass.simpleName}"
            false
        }
    }

    // ------------------------------------------------------------------ turnos

    /**
     * Abre un turno. El permiso de micrófono ya lo comprobó el puente.
     *
     * @param hints pista de vocabulario para la segunda pasada (nombres del
     *   catálogo); `null` o vacía si no hay.
     */
    fun start(gen: Int, hints: String?, review: Boolean) {
        if (turn != null) {
            listener.onError(gen, "busy", "turn-already-open")
            return
        }
        val next = Turn(gen, hints?.takeIf { it.isNotBlank() }, review)
        turn = next
        control.execute {
            if (next.cancelled) return@execute
            ensureVosk()?.let { code ->
                finish(next)
                listener.onError(gen, "recognizerUnavailable", code)
                listener.onEnded(gen, "error")
                return@execute
            }
            if (next.review) reviewer.execute { ensureWhisper() }
            next.begin(vosk!!)
        }
    }

    /** Deja de escuchar, termina lo pendiente y entrega lo último. */
    fun stop(gen: Int) {
        val current = turn ?: return
        if (current.gen != gen) return
        current.requestStop("stoppedByUser")
    }

    /** Descarta el turno: no habrá más eventos suyos. */
    fun cancel() {
        val current = turn ?: return
        current.cancel()
        finish(current)
    }

    /** Suelta micrófono, modelos y memoria nativa. Idempotente. */
    fun release() {
        cancel()
        control.execute {
            vosk?.close()
            vosk = null
        }
        reviewer.execute {
            if (whisper != 0L) WhisperNative.free(whisper)
            whisper = 0L
        }
    }

    private fun finish(t: Turn) {
        if (turn === t) turn = null
    }

    // ---------------------------------------------------------------- un turno

    private inner class Turn(val gen: Int, val hints: String?, val review: Boolean) {

        private val queue = ArrayBlockingQueue<ShortArray>(QUEUE_CHUNKS)
        @Volatile var cancelled = false
        @Volatile private var capturing = true
        @Volatile private var endReason = "stoppedByUser"
        @Volatile private var source: PcmSource? = null
        private var dropped = 0

        // Estado de frases: sólo lo tocan el hilo de Vosk y el de revisión, bajo `lock`.
        private val lock = Any()
        private var nextSeq = 0
        private var nextCommit = 0
        private val waiting = TreeMap<Int, String>()          // texto de Vosk aún sin entregar
        private val done = TreeMap<Int, Pair<String?, Long>>()  // revisión terminada (o saltada)
        private var reviewing = 0
        private var partial = ""
        private var lastSent = ""
        private var lastSentReviewing = -1

        fun begin(model: Model) {
            // Cancelado mientras se cargaba el modelo: ni micrófono ni reconocedor.
            if (cancelled) return
            val recognizer = try {
                Recognizer(model, SAMPLE_RATE.toFloat())
            } catch (t: Throwable) {
                fail("engineFailure", "recognizer:${t.javaClass.simpleName}")
                return
            }
            val audio = openSource()
            val failure = if (cancelled) null else audio.open()
            if (failure != null || cancelled) {
                audio.close()
                recognizer.close()
                if (failure != null) fail(failure.first, failure.second)
                return
            }
            source = audio
            listener.onStage(gen, "listening")
            Thread({ capture(audio) }, "agro-voz-captura").start()
            Thread({ decode(recognizer) }, "agro-voz-vosk").start()
        }

        fun requestStop(reason: String) {
            endReason = reason
            capturing = false
            listener.onStage(gen, "processing")
            source?.close()
        }

        fun cancel() {
            cancelled = true
            capturing = false
            source?.close()
            synchronized(lock) { if (reviewing > 0) WhisperNative.takeIf { it.available }?.abort() }
            queue.clear()
        }

        private fun capture(audio: PcmSource) {
            val buffer = ShortArray(CHUNK_SAMPLES)
            try {
                while (capturing) {
                    val read = audio.read(buffer)
                    if (read == PcmSource.EOF) break
                    if (read < 0) {
                        if (capturing) endReason = "error"
                        break
                    }
                    if (read == 0) continue
                    val chunk = buffer.copyOf(read)
                    // Cola llena: Vosk va atrasado. Se tira lo más viejo para que
                    // el retraso no crezca sin límite.
                    while (!queue.offer(chunk)) {
                        queue.poll()
                        dropped++
                    }
                }
            } finally {
                audio.close()
                source = null
                queue.put(END)
            }
        }

        private fun decode(recognizer: Recognizer) {
            val segment = PcmBuffer(MAX_SEGMENT_SAMPLES)
            var lastSpeech = SystemClock.elapsedRealtime()
            try {
                while (true) {
                    val chunk = queue.poll(200, TimeUnit.MILLISECONDS)
                    if (cancelled) return
                    if (chunk == null) continue
                    if (chunk === END) break
                    segment.append(chunk)
                    if (recognizer.acceptWaveForm(chunk, chunk.size)) {
                        val text = textOf(recognizer.result, "text")
                        if (text.isNotEmpty()) lastSpeech = SystemClock.elapsedRealtime()
                        close(text, segment.take())
                    } else {
                        val text = textOf(recognizer.partialResult, "partial")
                        if (text.isNotEmpty()) lastSpeech = SystemClock.elapsedRealtime()
                        synchronized(lock) { partial = text }
                        publishPartial()
                    }
                    // Mucho tiempo sin voz: se cierra solo. Una pausa natural
                    // dura segundos; esto sólo evita dejar el micrófono abierto.
                    if (capturing && SystemClock.elapsedRealtime() - lastSpeech > IDLE_LIMIT_MS) {
                        requestStop("timeout")
                    }
                }
                if (cancelled) return
                close(textOf(recognizer.finalResult, "text"), segment.take())
                awaitReviews()
                if (cancelled) return
                if (dropped > 0) Log.w(TAG, "audio descartado por retraso: ${dropped * 100} ms")
                // El turno queda libre ANTES de avisar: Dart puede abrir el
                // siguiente en cuanto recibe el final.
                finish(this)
                listener.onEnded(gen, endReason)
            } catch (t: Throwable) {
                finish(this)
                if (!cancelled) {
                    listener.onError(gen, "engineFailure", "decode:${t.javaClass.simpleName}")
                    listener.onEnded(gen, "error")
                }
            } finally {
                recognizer.close()
                finish(this)
            }
        }

        /** Vosk cerró una frase (pausa o fin). Sin texto, no hay frase. */
        private fun close(text: String, pcm: ShortArray) {
            if (text.isEmpty() || cancelled) return
            val seq: Int
            val reviewIt: Boolean
            synchronized(lock) {
                seq = nextSeq++
                waiting[seq] = text
                partial = ""
                // Revisión acotada: con dos frases ya esperando, la siguiente
                // se entrega tal como la oyó Vosk en vez de crecer la espera.
                reviewIt = review && whisperFailure == null && WhisperNative.available &&
                    reviewing < MAX_PENDING_REVIEWS
                if (reviewIt) reviewing++
            }
            if (!reviewIt) {
                complete(seq, null, 0)
                return
            }
            publishPartial()
            reviewer.execute {
                var result: String? = null
                var took = 0L
                if (!cancelled && ensureWhisper()) {
                    val started = SystemClock.elapsedRealtime()
                    val samples = FloatArray(pcm.size) { pcm[it] / 32768f }
                    result = try {
                        WhisperNative.transcribe(whisper, samples, hints, threads(), FloatArray(1))
                    } catch (_: Throwable) {
                        null
                    }
                    took = SystemClock.elapsedRealtime() - started
                }
                synchronized(lock) { reviewing-- }
                complete(seq, result?.trim(), took)
            }
        }

        private fun complete(seq: Int, review: String?, took: Long) {
            val ready = mutableListOf<Triple<Int, String, Pair<String?, Long>>>()
            synchronized(lock) {
                done[seq] = review to took
                while (done.containsKey(nextCommit)) {
                    val result = done.remove(nextCommit)!!
                    val vosk = waiting.remove(nextCommit)!!
                    ready += Triple(nextCommit, vosk, result)
                    nextCommit++
                }
            }
            if (cancelled) return
            for ((s, vosk, result) in ready) {
                listener.onSegment(gen, s, vosk, result.first, result.second)
            }
            publishPartial()
        }

        /** Al detener: se espera a las revisiones, con un tope. */
        private fun awaitReviews() {
            val deadline = SystemClock.elapsedRealtime() + STOP_REVIEW_BUDGET_MS
            while (!cancelled) {
                val pending = synchronized(lock) { waiting.size }
                if (pending == 0) return
                if (SystemClock.elapsedRealtime() > deadline) {
                    // Se agotó el tope: la revisión en curso se aborta y esas
                    // frases salen tal como las oyó Vosk.
                    if (WhisperNative.available) WhisperNative.abort()
                }
                Thread.sleep(50)
            }
        }

        private fun publishPartial() {
            if (cancelled) return
            val text: String
            val count: Int
            synchronized(lock) {
                text = (waiting.values + listOf(partial)).filter { it.isNotEmpty() }.joinToString(" ")
                count = reviewing
                // También cuando sólo cambia el contador: el texto de una frase
                // que pasa a revisión suele ser el mismo del último parcial.
                if (text == lastSent && count == lastSentReviewing) return
                lastSent = text
                lastSentReviewing = count
            }
            listener.onPartial(gen, text, count)
        }

        private fun fail(code: String, detail: String) {
            finish(this)
            if (cancelled) return
            listener.onError(gen, code, detail)
            listener.onEnded(gen, "error")
        }
    }

    /** Audio de la frase en curso, con tope: más allá se conserva lo último. */
    private class PcmBuffer(private val capacity: Int) {
        private var data = ShortArray(SAMPLE_RATE * 4)
        private var size = 0

        fun append(chunk: ShortArray) {
            if (size + chunk.size > capacity) {
                val keep = capacity - chunk.size
                System.arraycopy(data, size - keep, data, 0, keep)
                size = keep
            }
            if (size + chunk.size > data.size) data = data.copyOf(min(capacity, (size + chunk.size) * 2))
            System.arraycopy(chunk, 0, data, size, chunk.size)
            size += chunk.size
        }

        /** Entrega la frase y vacía el buffer. */
        fun take(): ShortArray {
            val out = data.copyOf(size)
            size = 0
            return out
        }
    }

    companion object {
        private const val TAG = "AgroVoz"
        const val VOSK_VERSION = "0.3.75"
        const val SAMPLE_RATE = 16_000
        const val CHUNK_SAMPLES = SAMPLE_RATE / 10                  // 100 ms
        private const val QUEUE_CHUNKS = 30                         // 3 s de retraso máximo
        private const val MAX_SEGMENT_SAMPLES = SAMPLE_RATE * 30    // Whisper ve hasta 30 s
        private const val MAX_PENDING_REVIEWS = 2
        private const val IDLE_LIMIT_MS = 30_000L
        private const val STOP_REVIEW_BUDGET_MS = 8_000L
        private val END = ShortArray(0)

        private fun threads(): Int = min(4, Runtime.getRuntime().availableProcessors()).coerceAtLeast(1)

        private fun textOf(json: String?, field: String): String = try {
            JSONObject(json ?: "").optString(field, "").trim()
        } catch (_: Throwable) {
            ""
        }
    }
}
