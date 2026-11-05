package com.comunidad.agro.agroquimicos

import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Inferencia REAL del motor local con audio de referencia, en el emulador.
 *
 * Pasa archivos WAV (16 kHz, mono, 16 bits) por el mismo [LocalVoiceEngine] de
 * la app —Vosk y whisper.cpp reales, modelos del APK— sustituyendo sólo el
 * micrófono por un lector que entrega el audio **a ritmo real**, 100 ms cada
 * 100 ms. No hay respuestas prefabricadas.
 *
 * El audio viaja como assets del APK de prueba (`ref/<nombre>.wav`), que
 * `tool/voice_local/run_reference_check.sh` copia sólo durante la compilación.
 * Los resultados se escriben, sin audio, en
 * `<archivos externos de la app>/ref-results.jsonl` para la evidencia.
 *
 * Los tiempos describen el EMULADOR x86_64 de este PC, no un teléfono.
 */
@RunWith(AndroidJUnit4::class)
class LocalVoiceEngineReferenceTest {

    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val testAssets = InstrumentationRegistry.getInstrumentation().context.assets
    private val results = File(context.getExternalFilesDir(null), "ref-results.jsonl")

    private val hint = "Glifosato, Bellator, Atrazina, Paraquat, Mancozeb, Cipermetrina, " +
        "Tebuconazole, Herbicida, Fungicida, Insecticida, Ana Quispe, Beto Mamani."

    /** Lo que el motor contó durante un turno, con su momento. */
    private class Recorder : LocalVoiceEngine.Listener {
        val started = SystemClock.elapsedRealtime()
        val events = mutableListOf<Pair<Long, JSONObject>>()
        val ended = CountDownLatch(1)

        private fun add(o: JSONObject) = synchronized(events) {
            events += (SystemClock.elapsedRealtime() - started) to o
        }

        override fun onStage(gen: Int, stage: String) =
            add(JSONObject().put("type", "stage").put("gen", gen).put("stage", stage))

        override fun onPartial(gen: Int, text: String, reviewing: Int) =
            add(JSONObject().put("type", "partial").put("gen", gen).put("text", text).put("reviewing", reviewing))

        override fun onSegment(gen: Int, seq: Int, vosk: String, review: String?, reviewMs: Long) =
            add(
                JSONObject().put("type", "segment").put("gen", gen).put("seq", seq)
                    .put("vosk", vosk).put("review", review ?: JSONObject.NULL).put("reviewMs", reviewMs),
            )

        override fun onEnded(gen: Int, reason: String) {
            add(JSONObject().put("type", "ended").put("gen", gen).put("reason", reason))
            ended.countDown()
        }

        override fun onError(gen: Int, code: String, detail: String?) =
            add(JSONObject().put("type", "error").put("gen", gen).put("code", code).put("detail", detail))

        fun of(type: String) = synchronized(events) { events.filter { it.second.getString("type") == type } }
    }

    /** WAV a ritmo real. Termina con EOF, como si el usuario pulsara Detener. */
    private inner class WavSource(name: String, private val pace: Boolean = true) : LocalVoiceEngine.PcmSource {
        private val samples: ShortArray = testAssets.open("ref/$name").use { it.readBytes() }.let { bytes ->
            // Busca el bloque «data» del RIFF.
            var i = 12
            while (i + 8 <= bytes.size) {
                val id = String(bytes, i, 4)
                val size = (bytes[i + 4].toInt() and 0xff) or ((bytes[i + 5].toInt() and 0xff) shl 8) or
                    ((bytes[i + 6].toInt() and 0xff) shl 16) or ((bytes[i + 7].toInt() and 0xff) shl 24)
                if (id == "data") {
                    val n = minOf(size, bytes.size - i - 8) / 2
                    return@let ShortArray(n) {
                        ((bytes[i + 8 + 2 * it].toInt() and 0xff) or (bytes[i + 9 + 2 * it].toInt() shl 8)).toShort()
                    }
                }
                i += 8 + size
            }
            ShortArray(0)
        }
        private var position = 0
        private var opened = 0L
        @Volatile private var closed = false
        var eofAt = 0L

        override fun open(): Pair<String, String>? {
            opened = SystemClock.elapsedRealtime()
            return null
        }

        override fun read(buffer: ShortArray): Int {
            if (closed || position >= samples.size) {
                if (eofAt == 0L) eofAt = SystemClock.elapsedRealtime()
                return LocalVoiceEngine.PcmSource.EOF
            }
            if (pace) {
                val due = opened + position * 1000L / LocalVoiceEngine.SAMPLE_RATE
                val wait = due - SystemClock.elapsedRealtime()
                if (wait > 0) Thread.sleep(wait)
            }
            val n = minOf(buffer.size, samples.size - position)
            System.arraycopy(samples, position, buffer, 0, n)
            position += n
            return n
        }

        override fun close() {
            closed = true
        }

        val durationMs: Long get() = samples.size * 1000L / LocalVoiceEngine.SAMPLE_RATE
    }

    private fun wavs(prefix: String = ""): List<String> =
        (testAssets.list("ref") ?: emptyArray()).filter { it.endsWith(".wav") && it.startsWith(prefix) }.sorted()

    private fun record(name: String, recorder: Recorder, extra: JSONObject = JSONObject()) {
        val list = JSONArray()
        synchronized(recorder.events) {
            for ((t, e) in recorder.events) list.put(JSONObject(e.toString()).put("t", t))
        }
        results.appendText(extra.put("file", name).put("events", list).toString() + "\n")
    }

    @Test
    fun referenceAudioThroughTheRealEngine() {
        val files = wavs()
        assumeTrue("no hay audio de referencia en los assets de la prueba", files.isNotEmpty())
        var gen = 100
        for (file in files) {
            val recorder = Recorder()
            val source = WavSource(file)
            val engine = LocalVoiceEngine(context, recorder) { source }
            val g = gen++
            engine.start(g, hint, review = true)
            assertTrue("${file}: el turno no terminó", recorder.ended.await(180, TimeUnit.SECONDS))
            val endedAt = recorder.of("ended").single().first
            record(
                file, recorder,
                JSONObject().put("audioMs", source.durationMs)
                    .put("afterEofMs", endedAt - (source.eofAt - recorder.started)),
            )
            engine.release()

            assertTrue("${file}: errores ${recorder.of("error")}", recorder.of("error").isEmpty())
            val segments = recorder.of("segment").map { it.second }
            // Frases numeradas 0..n-1, sin huecos ni repetidas, del turno pedido.
            assertEquals(file, segments.indices.toList(), segments.map { it.getInt("seq") })
            assertTrue(segments.all { it.getInt("gen") == g })
            if (file.startsWith("x_")) {
                // Silencio y ruido: ninguna frase, ningún texto afirmado.
                assertTrue("${file}: inventó texto", segments.isEmpty())
                assertTrue(recorder.of("partial").all { it.second.getString("text").isEmpty() })
            } else {
                assertTrue("${file}: sin frase", segments.isNotEmpty())
                // Texto progresivo: hubo parciales distintos antes de la primera frase.
                val firstSegment = recorder.of("segment").first().first
                val early = recorder.of("partial").filter { it.first < firstSegment }
                    .map { it.second.getString("text") }.filter { it.isNotEmpty() }.distinct()
                assertTrue("${file}: sin parciales progresivos", early.size >= 2)
            }
        }
    }

    @Test
    fun cancelledTurnEmitsNothingAfterwards() {
        val file = wavs("p01").firstOrNull() ?: wavs("f").firstOrNull()
        assumeTrue(file != null)
        val recorder = Recorder()
        val engine = LocalVoiceEngine(context, recorder) { WavSource(file!!) }
        engine.start(7, hint, review = true)
        // Se cancela a mitad de la primera frase o durante su revisión.
        Thread.sleep(4_500)
        engine.cancel()
        val cancelledAt = SystemClock.elapsedRealtime() - recorder.started
        Thread.sleep(15_000)
        val late = synchronized(recorder.events) { recorder.events.filter { it.first > cancelledAt + 50 } }
        record("cancelar:${file!!}", recorder, JSONObject().put("cancelledAt", cancelledAt))
        engine.release()
        assertTrue("eventos tras cancelar: $late", late.isEmpty())
    }

    @Test
    fun nextTurnDoesNotReceiveThePreviousOne() {
        val first = wavs("p01").firstOrNull()
        val second = wavs("f03").firstOrNull()
        assumeTrue(first != null && second != null)
        val recorder = Recorder()
        // Una fuente nueva por turno, como el micrófono en la app.
        var nextName = first!!
        val engine = LocalVoiceEngine(context, recorder) { WavSource(nextName) }
        engine.start(1, hint, review = true)
        // Se espera a que la primera frase esté en revisión y se cancela ahí:
        // su resultado tardío no puede aparecer en el turno siguiente.
        val deadline = SystemClock.elapsedRealtime() + 60_000
        while (SystemClock.elapsedRealtime() < deadline &&
            recorder.of("partial").none { it.second.getInt("reviewing") > 0 }
        ) {
            Thread.sleep(20)
        }
        val inReview = recorder.of("partial").any { it.second.getInt("reviewing") > 0 }
        engine.cancel()
        nextName = second!!
        engine.start(2, hint, review = true)
        assertTrue(recorder.ended.await(120, TimeUnit.SECONDS))
        Thread.sleep(5_000)
        record("dos-turnos", recorder, JSONObject().put("cancelledDuringReview", inReview))
        engine.release()
        val segments = recorder.of("segment").map { it.second }
        assertTrue("no se llegó a cancelar durante una revisión", inReview)
        assertTrue("llegó una frase del turno cancelado", segments.all { it.getInt("gen") == 2 })
        assertTrue(segments.isNotEmpty())
    }
}
