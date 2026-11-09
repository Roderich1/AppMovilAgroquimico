package com.comunidad.agro.agroquimicos

import android.annotation.SuppressLint
import android.app.ActivityManager
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
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

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
            // Lo que el sistema entregó de verdad (diagnóstico F09): sin audio.
            Log.i(
                TAG,
                "captura: pedido=$SAMPLE_RATE Hz real=${audio.sampleRate} Hz " +
                    "canales=${audio.channelCount} formato=${audio.audioFormat} " +
                    "fuente=VOICE_RECOGNITION",
            )
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

        /**
         * Vosk cerró la frase [seq]; su resultado llega después en [onSegment].
         * Con implementación vacía: quien sólo registra segmentos (la prueba
         * instrumentada) no necesita atenderlo.
         */
        fun onPhrase(gen: Int, seq: Int, vosk: String, review: Boolean) {}

        /**
         * Diagnóstico de la frase [seq], justo antes de su [onSegment]: sólo
         * números y códigos (duración y nivel del audio, cómo se cerró, qué
         * pasó con la revisión). Nunca audio ni texto.
         */
        fun onPhraseInfo(gen: Int, seq: Int, info: Map<String, Any?>) {}

        /**
         * Sólo diagnóstico: otra transcripción del mismo audio de la frase
         * [seq] con la pista [label]. Va a la vista temporal, nunca al
         * formulario ni al registro.
         */
        fun onComparison(gen: Int, seq: Int, label: String, text: String?, ms: Long, outcome: String) {}
        fun onSegment(gen: Int, seq: Int, vosk: String, review: String?, reviewMs: Long)
        fun onEnded(gen: Int, reason: String)
        fun onError(gen: Int, code: String, detail: String?)
    }

    private val models = LocalVoiceModels(context.applicationContext)
    private val activityManager =
        context.applicationContext.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager

    /** Carga de modelos y orden de start/stop/cancel. Nunca el hilo principal. */
    private val control: ExecutorService = Executors.newSingleThreadExecutor { r ->
        Thread(r, "agro-voz-control")
    }

    /** Una revisión a la vez en todo el proceso: es la parte pesada. */
    private val reviewer: ExecutorService = Executors.newSingleThreadExecutor { r ->
        Thread(r, "agro-voz-revision").apply { priority = Thread.NORM_PRIORITY - 1 }
    }

    /** Aborta la revisión que pasa de su tope. */
    private val watchdog: ScheduledExecutorService = Executors.newSingleThreadScheduledExecutor { r ->
        Thread(r, "agro-voz-tope").apply { isDaemon = true }
    }

    /** La revisión en curso; el tope sólo aborta si sigue siendo ésta. */
    @Volatile private var reviewToken: Any? = null

    private var vosk: Model? = null
    @Volatile private var whisper: Long = 0L
    @Volatile private var whisperFailure: String? = null

    @Volatile private var turn: Turn? = null

    // ------------------------------------------------------------ disponibilidad

    /**
     * Qué trae este APK y hechos del aparato para decidir la segunda pasada.
     * No abre el micrófono ni carga nada pesado. La decisión la toma Dart
     * (`ReviewCapabilityPolicy`): aquí sólo se informa, sin interpretar.
     */
    fun describe(): Map<String, Any?> {
        val memory = try {
            ActivityManager.MemoryInfo().also { activityManager?.getMemoryInfo(it) }
        } catch (_: Throwable) {
            null
        }
        val lowRam = try {
            activityManager?.isLowRamDevice
        } catch (_: Throwable) {
            null
        }
        return mapOf(
            "modelPresent" to (models.voskName != null),
            "engineName" to "Vosk (vosk-android $VOSK_VERSION)",
            "engineVersion" to (models.voskName ?: ""),
            "reviewModel" to models.whisperName,
            "reviewVariant" to models.whisperVariant,
            "reviewModelBytes" to models.whisperBytes,
            "reviewAvailable" to (models.whisperName != null && WhisperNative.available),
            "reviewNativeLib" to WhisperNative.loadFailure,
            "reviewDetail" to whisperFailure,
            "totalMemBytes" to memory?.totalMem?.takeIf { it > 0 },
            "lowRamDevice" to lowRam,
        )
    }

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
            vosk = try {
                Model(dir.absolutePath)
            } catch (t: Throwable) {
                // La copia pasó la verificación y aun así no carga: no se
                // reutiliza. La próxima vez se rehace desde el APK.
                models.invalidateVosk()
                throw t
            }
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
    fun start(
        gen: Int,
        hints: String?,
        review: Boolean,
        reviewTimeoutMs: Long = DEFAULT_REVIEW_TIMEOUT_MS,
        compare: List<Pair<String, String>> = emptyList(),
    ) {
        if (turn != null) {
            listener.onError(gen, "busy", "turn-already-open")
            return
        }
        val next = Turn(
            gen, hints?.takeIf { it.isNotBlank() }, review,
            reviewTimeoutMs.coerceIn(MIN_REVIEW_TIMEOUT_MS, MAX_REVIEW_TIMEOUT_MS),
            compare.take(MAX_COMPARISONS),
        )
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

    /**
     * Descarta el turno: no habrá más eventos suyos.
     *
     * Con [gen], sólo si es el turno en curso (#119). Sin número —la Activity
     * perdió el foco, o se desmonta— se descarta el que haya.
     */
    fun cancel(gen: Int? = null) {
        val current = turn ?: return
        if (gen != null && current.gen != gen) return
        current.cancel()
        finish(current)
    }

    /**
     * Suelta la memoria de los modelos si no hay turno en curso.
     *
     * Es lo que pide la pantalla que se va. Si otra ya abrió un turno, los
     * modelos siguen cargados para ella; los soltará quien salga después.
     */
    fun releaseIfIdle() {
        control.execute {
            if (turn != null) return@execute
            vosk?.close()
            vosk = null
        }
        reviewer.execute {
            if (turn != null) return@execute
            if (whisper != 0L) WhisperNative.free(whisper)
            whisper = 0L
        }
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

    private inner class Turn(
        val gen: Int,
        val hints: String?,
        val review: Boolean,
        /** Tope de la revisión de cada frase desde que Vosk la cierra. */
        val reviewTimeoutMs: Long,
        /**
         * Sólo diagnóstico: otras pistas (etiqueta, pista) con las que volver a
         * transcribir el MISMO audio de la frase en memoria, después de
         * entregarla. Sus textos van a la vista temporal, nunca al formulario.
         */
        val compare: List<Pair<String, String>> = emptyList(),
    ) {

        /** Muestras leídas del micrófono en el turno (todas van a Vosk). */
        @Volatile private var capturedSamples = 0L

        /** Momento en que Vosk cerró cada frase. Bajo `lock`. */
        private val closedAtBySeq = HashMap<Int, Long>()

        private val queue = ArrayBlockingQueue<ShortArray>(QUEUE_CHUNKS)
        @Volatile var cancelled = false
        @Volatile private var capturing = true
        @Volatile private var endReason = "stoppedByUser"
        @Volatile private var source: PcmSource? = null
        @Volatile private var dropped = 0
        private var droppedAtClose = 0

        /** Diagnóstico por frase, hasta entregarla. Bajo `lock`. */
        private val info = HashMap<Int, MutableMap<String, Any?>>()

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
            synchronized(lock) { if (reviewing > 0) abortReview() }
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
                    capturedSamples += read
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
                        close(text, segment.take(), "pausa")
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
                close(textOf(recognizer.finalResult, "text"), segment.take(), endReason)
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

        /**
         * Vosk cerró una frase (pausa o fin). Sin texto, no hay frase.
         *
         * [closedBy]: `pausa` si la cerró una pausa; si no, el motivo del fin
         * del turno (`stoppedByUser`, `timeout`).
         */
        private fun close(text: String, pcm: ShortArray, closedBy: String) {
            val droppedNow = dropped
            val droppedHere = droppedNow - droppedAtClose
            droppedAtClose = droppedNow
            if (text.isEmpty() || cancelled) return
            val seq: Int
            val reviewIt: Boolean
            val closedAt = SystemClock.elapsedRealtime()
            synchronized(lock) {
                seq = nextSeq++
                waiting[seq] = text
                partial = ""
                // Revisión acotada: con dos frases ya esperando, la siguiente
                // se entrega tal como la oyó Vosk en vez de crecer la espera.
                reviewIt = review && whisperFailure == null && WhisperNative.available &&
                    reviewing < MAX_PENDING_REVIEWS
                if (reviewIt) reviewing++
                closedAtBySeq[seq] = closedAt
                info[seq] = PcmStats.of(pcm).toMutableMap().apply {
                    put("closedBy", closedBy)
                    put("droppedMs", droppedHere * 100)
                    // Vosk recibe todo lo capturado en el turno; Whisper, sólo
                    // el audio de esta frase (`audioMs`, el mismo búfer medido).
                    put("turnCapturedMs", capturedSamples * 1000L / SAMPLE_RATE)
                    put("reviewAudioMs", if (reviewIt) pcm.size * 1000L / SAMPLE_RATE else 0L)
                    put(
                        "reviewOutcome",
                        when {
                            reviewIt -> "pending"
                            !review -> "off"
                            whisperFailure != null || !WhisperNative.available -> "unavailable"
                            else -> "queue-full"
                        },
                    )
                }
            }
            // Dart arranca aquí el tope de la frase: si su resultado no llega a
            // tiempo, entrega este texto y descarta lo que venga después.
            listener.onPhrase(gen, seq, text, reviewIt)
            if (!reviewIt) {
                complete(seq, null, 0)
                return
            }
            publishPartial()
            reviewer.execute {
                var result: String? = null
                var took = 0L
                var loadMs = 0L
                val aborted = AtomicBoolean(false)
                val queuedMs = SystemClock.elapsedRealtime() - closedAt
                // Lo que quede del tope de esta frase: la espera en la cola (y
                // la primera carga del modelo) también cuentan. Agotado, ni se
                // empieza.
                val wasLoaded = whisper != 0L
                val loadStart = SystemClock.elapsedRealtime()
                val budgetLeft = !cancelled &&
                    reviewTimeoutMs - (SystemClock.elapsedRealtime() - closedAt) > 0
                val ready = budgetLeft && ensureWhisper()
                if (budgetLeft && !wasLoaded) loadMs = SystemClock.elapsedRealtime() - loadStart
                var outcome = when {
                    cancelled -> "cancelled"
                    !budgetLeft -> "budget-exhausted"
                    !ready -> "unavailable"
                    else -> "pending"
                }
                if (ready) {
                    val started = SystemClock.elapsedRealtime()
                    val remaining = reviewTimeoutMs - (started - closedAt)
                    val samples = FloatArray(pcm.size) { pcm[it] / 32768f }
                    val token = Any()
                    reviewToken = token
                    val guard = watchdog.schedule(
                        {
                            if (reviewToken === token) {
                                aborted.set(true)
                                WhisperNative.abort()
                            }
                        },
                        maxOf(1L, remaining),
                        TimeUnit.MILLISECONDS,
                    )
                    result = try {
                        if (remaining > 0) {
                            WhisperNative.transcribe(whisper, samples, hints, threads(), FloatArray(1))
                        } else {
                            null
                        }
                    } catch (_: Throwable) {
                        null
                    } finally {
                        reviewToken = null
                        guard.cancel(false)
                    }
                    took = SystemClock.elapsedRealtime() - started
                    outcome = when {
                        result != null -> "ok"
                        cancelled -> "cancelled"
                        aborted.get() || remaining <= 0 -> "aborted"
                        else -> "error"
                    }
                }
                synchronized(lock) {
                    reviewing--
                    info[seq]?.apply {
                        put("reviewOutcome", outcome)
                        put("loadMs", loadMs)
                        put("queuedMs", queuedMs)
                    }
                }
                complete(seq, result?.trim(), took)
                if (ready && compare.isNotEmpty()) compareContexts(seq, pcm)
            }
        }

        /**
         * Sólo diagnóstico: vuelve a transcribir el audio de la frase con cada
         * pista de [compare], después de haberla entregado, con el mismo tope
         * por transcripción. Los textos van sólo a la vista temporal. El audio
         * sigue sólo en memoria y se suelta al terminar.
         */
        private fun compareContexts(seq: Int, pcm: ShortArray) {
            val samples = FloatArray(pcm.size) { pcm[it] / 32768f }
            for ((label, prompt) in compare) {
                if (cancelled || whisper == 0L) return
                val aborted = AtomicBoolean(false)
                val token = Any()
                reviewToken = token
                val guard = watchdog.schedule(
                    {
                        if (reviewToken === token) {
                            aborted.set(true)
                            WhisperNative.abort()
                        }
                    },
                    reviewTimeoutMs,
                    TimeUnit.MILLISECONDS,
                )
                val started = SystemClock.elapsedRealtime()
                val text = try {
                    WhisperNative.transcribe(
                        whisper, samples, prompt.takeIf { it.isNotBlank() }, threads(), FloatArray(1),
                    )
                } catch (_: Throwable) {
                    null
                } finally {
                    reviewToken = null
                    guard.cancel(false)
                }
                val took = SystemClock.elapsedRealtime() - started
                val outcome = when {
                    text != null -> "ok"
                    cancelled -> "cancelled"
                    aborted.get() -> "aborted"
                    else -> "error"
                }
                if (cancelled) return
                listener.onComparison(gen, seq, label, text?.trim(), took, outcome)
            }
        }

        private fun complete(seq: Int, review: String?, took: Long) {
            val ready = mutableListOf<Triple<Int, String, Pair<String?, Long>>>()
            val details = HashMap<Int, Map<String, Any?>>()
            synchronized(lock) {
                done[seq] = review to took
                while (done.containsKey(nextCommit)) {
                    val result = done.remove(nextCommit)!!
                    val vosk = waiting.remove(nextCommit)!!
                    ready += Triple(nextCommit, vosk, result)
                    info.remove(nextCommit)?.let { details[nextCommit] = it }
                    closedAtBySeq.remove(nextCommit)?.let { at ->
                        details[nextCommit] = (details[nextCommit] ?: emptyMap()) +
                            ("closeToDeliverMs" to SystemClock.elapsedRealtime() - at)
                    }
                    nextCommit++
                }
            }
            if (cancelled) return
            for ((s, vosk, result) in ready) {
                details[s]?.let { listener.onPhraseInfo(gen, s, it) }
                listener.onSegment(gen, s, vosk, result.first, result.second)
            }
            publishPartial()
        }

        /**
         * Al detener: se espera a las revisiones, como mucho el tope de una
         * frase (cada una ya corre el suyo desde que se cerró).
         */
        private fun awaitReviews() {
            val deadline = SystemClock.elapsedRealtime() + reviewTimeoutMs
            while (!cancelled) {
                val pending = synchronized(lock) { waiting.size }
                if (pending == 0) return
                if (SystemClock.elapsedRealtime() > deadline) {
                    // Se agotó el tope: la revisión en curso se aborta y esas
                    // frases salen tal como las oyó Vosk.
                    abortReview()
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

    private fun abortReview() {
        if (WhisperNative.available) WhisperNative.abort()
    }

    /**
     * Métricas del audio de una frase, sin conservar el audio (diagnóstico F09).
     *
     * Niveles en dBFS por ventanas de 50 ms. El «suelo» es el percentil 10 de
     * las ventanas (ruido de fondo); una ventana es voz si supera el suelo en
     * [VOICE_MARGIN_DB]. `trailingQuietMs` cerca de 0 en una frase cerrada al
     * detener indica que se habló hasta el último instante capturado: el final
     * pudo quedar cortado.
     */
    internal object PcmStats {
        private const val WINDOW_MS = 50
        private const val VOICE_MARGIN_DB = 12.0
        private const val CLIP_LEVEL = 32_700

        fun of(pcm: ShortArray, rate: Int = SAMPLE_RATE): Map<String, Any?> {
            val n = pcm.size
            if (n == 0) return mapOf("audioMs" to 0L)
            var peak = 0
            var clipped = 0
            var sumSq = 0.0
            for (s in pcm) {
                val a = abs(s.toInt())
                if (a > peak) peak = a
                if (a >= CLIP_LEVEL) clipped++
                sumSq += a.toDouble() * a
            }
            val window = rate * WINDOW_MS / 1000
            val levels = ArrayList<Double>()
            val energy = ArrayList<Double>()
            val sizes = ArrayList<Int>()
            var start = 0
            while (start < n) {
                val end = min(n, start + window)
                var w = 0.0
                for (k in start until end) w += pcm[k].toDouble() * pcm[k]
                levels += dbfs(sqrt(w / (end - start)))
                energy += w
                sizes += end - start
                start = end
            }
            val sorted = levels.sorted()
            val floor = sorted[(sorted.size - 1) / 10]
            val loudest = sorted.last()
            val voice = floor + VOICE_MARGIN_DB
            val hasVoice = loudest >= voice
            // Nivel durante el habla y durante el silencio, por separado: la
            // media de toda la frase mezcla los dos (POCO 2026-11-09).
            var speechE = 0.0
            var speechN = 0
            var quietE = 0.0
            var quietN = 0
            for (k in levels.indices) {
                if (levels[k] >= voice) {
                    speechE += energy[k]
                    speechN += sizes[k]
                } else {
                    quietE += energy[k]
                    quietN += sizes[k]
                }
            }
            fun quiet(range: IntProgression): Int {
                var count = 0
                for (k in range) {
                    if (levels[k] >= voice) break
                    count++
                }
                return count * WINDOW_MS
            }
            return mapOf(
                "audioMs" to n * 1000L / rate,
                "rmsDbfs" to dbfs(sqrt(sumSq / n)).roundToInt(),
                "speechRmsDbfs" to if (speechN > 0) dbfs(sqrt(speechE / speechN)).roundToInt() else null,
                "silenceRmsDbfs" to if (quietN > 0) dbfs(sqrt(quietE / quietN)).roundToInt() else null,
                "speechMs" to speechN * 1000L / rate,
                "levelMethod" to "v50ms-p10-12dB",
                "peakDbfs" to dbfs(peak.toDouble()).roundToInt(),
                "floorDbfs" to floor.roundToInt(),
                "loudestDbfs" to loudest.roundToInt(),
                "clipPermille" to clipped * 1000 / n,
                "voiceDetected" to hasVoice,
                "leadingQuietMs" to if (hasVoice) quiet(levels.indices) else -1,
                "trailingQuietMs" to if (hasVoice) quiet(levels.indices.reversed()) else -1,
            )
        }

        private fun dbfs(amplitude: Double): Double =
            if (amplitude <= 0.0) -96.0 else maxOf(-96.0, 20 * log10(amplitude / 32768.0))
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
        /** Sólo diagnóstico: pistas alternativas por frase, como mucho. */
        private const val MAX_COMPARISONS = 3
        private const val IDLE_LIMIT_MS = 30_000L
        /** Como `LocalSpeechTranscriptionAdapter.defaultReviewTimeout`. */
        const val DEFAULT_REVIEW_TIMEOUT_MS = 5_000L
        private const val MIN_REVIEW_TIMEOUT_MS = 500L
        private const val MAX_REVIEW_TIMEOUT_MS = 30_000L
        private val END = ShortArray(0)

        private fun threads(): Int = min(4, Runtime.getRuntime().availableProcessors()).coerceAtLeast(1)

        private fun textOf(json: String?, field: String): String = try {
            JSONObject(json ?: "").optString(field, "").trim()
        } catch (_: Throwable) {
            ""
        }
    }
}
