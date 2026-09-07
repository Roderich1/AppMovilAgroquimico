package com.comunidad.agro.voicebench.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Lo que hace sospechoso a un texto de Whisper.
 *
 * ## Por qué esto se prueba sin teléfono
 *
 * `ADR-002` eligió Android sobre Whisper por una sola razón que ninguna otra
 * compensaba: con tres segundos de silencio, Whisper tiny devolvió `[MÚSICA]`
 * **y lo marcó como resultado válido, sin error** (`RISK-026`). Un motor que
 * afirma texto que nadie dijo puede afirmar un producto o un monto sobre ruido
 * de campo, y el usuario lo vería como dato propuesto.
 *
 * C3 vuelve a poner a Whisper sobre la mesa, ahora con `small`. El guardrail
 * binario de la matriz de aceptación es **cero texto aceptado sobre no-habla**,
 * y quien lo decide es esta clasificación. Vive aparte de la inferencia,
 * y sin JNI ni `Context`, justamente para poder ejercitarla entera sin modelo
 * y sin aparato: si dependiera del motor nativo, el caso de `[MÚSICA]` sólo se
 * podría comprobar con suerte y un micrófono en silencio.
 *
 * Ninguna de estas marcas descarta el texto por su cuenta. Lo señalan para que
 * la interfaz pida revisión en vez de proponer un dato inventado.
 */
class WhisperTranscriptTest {

    // ------------------------------------------------------------ sin habla

    @Test
    fun `texto vacio es ausencia de habla, no un texto raro`() {
        val flags = WhisperTranscript.flagsFor("", audioMs = 3_000)
        assertEquals(listOf(WhisperTranscript.FLAG_NO_SPEECH), flags)
    }

    @Test
    fun `solo espacios tambien es ausencia de habla`() {
        val flags = WhisperTranscript.flagsFor("   \n\t ", audioMs = 3_000)
        assertEquals(listOf(WhisperTranscript.FLAG_NO_SPEECH), flags)
    }

    // -------------------------------------------------------- alucinaciones

    @Test
    fun `el caso medido en la Fase 0 queda marcado`() {
        // Tres segundos de silencio, y esto es lo que devolvio el motor.
        val flags = WhisperTranscript.flagsFor("[MÚSICA]", audioMs = 3_000)
        assertTrue(flags.contains(WhisperTranscript.FLAG_ANNOTATION))
    }

    @Test
    fun `las demas anotaciones del propio modelo tambien`() {
        for (text in listOf("(risas)", "[BLANK_AUDIO]", "[Music]", "(aplausos)")) {
            assertTrue(
                "«$text» tendria que quedar marcado",
                WhisperTranscript.flagsFor(text, audioMs = 3_000)
                    .contains(WhisperTranscript.FLAG_ANNOTATION),
            )
        }
    }

    @Test
    fun `una anotacion dentro de una frase real tambien cuenta`() {
        val flags = WhisperTranscript.flagsFor(
            "registrar compra de cincuenta litros [MÚSICA]",
            audioMs = 6_000,
        )
        assertTrue(flags.contains(WhisperTranscript.FLAG_ANNOTATION))
    }

    // ------------------------------------------------------ repeticion loca

    @Test
    fun `la repeticion degenerada queda marcada`() {
        val flags = WhisperTranscript.flagsFor(
            "gracias gracias gracias gracias gracias gracias gracias gracias",
            audioMs = 8_000,
        )
        assertTrue(flags.contains(WhisperTranscript.FLAG_REPETITION))
    }

    @Test
    fun `una frase corta con palabras repetidas no es degenerada`() {
        // «no fueron doce, fueron dos» repite «fueron» y es una correccion
        // legitima del corpus, categoria F.
        val flags = WhisperTranscript.flagsFor(
            "no fueron doce fueron dos",
            audioMs = 4_000,
        )
        assertFalse(flags.contains(WhisperTranscript.FLAG_REPETITION))
    }

    @Test
    fun `una frase larga y variada no es degenerada`() {
        val flags = WhisperTranscript.flagsFor(
            "registrar compra de cincuenta litros de bellator a ciento " +
                "ochenta y seis bolivianos del proveedor agropecuaria del este",
            audioMs = 12_000,
        )
        assertTrue(flags.isEmpty())
    }

    // ------------------------------------------ mas texto del que cabe

    @Test
    fun `mucho texto sobre un audio muy corto queda marcado`() {
        val flags = WhisperTranscript.flagsFor(
            "esta es una frase deliberadamente larga que no cabe en dos " +
                "segundos de audio por mucho que se hable rapido de verdad",
            audioMs = 1_500,
        )
        assertTrue(flags.contains(WhisperTranscript.FLAG_TOO_MUCH_TEXT))
    }

    @Test
    fun `el mismo texto sobre audio suficiente no se marca`() {
        val flags = WhisperTranscript.flagsFor(
            "esta es una frase deliberadamente larga que no cabe en dos " +
                "segundos de audio por mucho que se hable rapido de verdad",
            audioMs = 12_000,
        )
        assertFalse(flags.contains(WhisperTranscript.FLAG_TOO_MUCH_TEXT))
    }

    @Test
    fun `sin duracion de audio no se inventa la marca`() {
        // `audioMs = 0` significa que no se midio, no que el audio durara cero.
        val flags = WhisperTranscript.flagsFor("hola que tal", audioMs = 0)
        assertFalse(flags.contains(WhisperTranscript.FLAG_TOO_MUCH_TEXT))
    }

    // ------------------------------------------------------------- utilizable

    @Test
    fun `un texto limpio es utilizable y uno marcado no`() {
        assertTrue(WhisperTranscript.isUsable("registrar una compra", emptyList()))
        assertFalse(
            WhisperTranscript.isUsable(
                "[MÚSICA]",
                listOf(WhisperTranscript.FLAG_ANNOTATION),
            ),
        )
        assertFalse(WhisperTranscript.isUsable(null, emptyList()))
        assertFalse(WhisperTranscript.isUsable("", emptyList()))
    }

    // ---------------------------------------------------------------- idioma

    @Test
    fun `el idioma sale del locale y nunca queda en ingles`() {
        // El wrapper original de whisper.cpp lo dejaba clavado en `en`, que es
        // justo lo que falsearia esta medicion.
        assertEquals("es", WhisperTranscript.languageOf("es-BO"))
        assertEquals("es", WhisperTranscript.languageOf("es_MX"))
        assertEquals("es", WhisperTranscript.languageOf("ES-ES"))
        assertEquals("es", WhisperTranscript.languageOf("es"))
    }

    // ------------------------------------------------- factor de tiempo real

    @Test
    fun `el factor de tiempo real es computo dividido por audio`() {
        // `ADR-004` pide p95 <= 0,50 en frases de hasta 60 s.
        assertEquals(0.5, WhisperTranscript.realTimeFactor(elapsedMs = 5_000, audioMs = 10_000), 1e-9)
        assertEquals(2.0, WhisperTranscript.realTimeFactor(elapsedMs = 20_000, audioMs = 10_000), 1e-9)
    }

    @Test
    fun `sin audio medido el factor no es cero, es desconocido`() {
        // Cero significaria «instantaneo», que es lo contrario de «no se midio».
        assertEquals(null, WhisperTranscript.realTimeFactorOrNull(elapsedMs = 5_000, audioMs = 0))
    }
}
