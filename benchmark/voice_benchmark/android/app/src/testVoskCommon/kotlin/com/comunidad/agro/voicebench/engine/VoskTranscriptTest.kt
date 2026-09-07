package com.comunidad.agro.voicebench.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Acumulación de lo que Vosk confirma durante una sesión.
 *
 * Reproduce, sin teléfono y sin JNI, el defecto medido en el HONOR: el parcial
 * mostraba la frase entera y correcta, y el resultado final llegaba vacío. Un
 * motor que había acertado se registraba como «sin habla».
 */
class VoskTranscriptTest {

    @Test
    fun `sin nada dicho no hay texto`() {
        val transcript = VoskTranscript()

        assertNull(transcript.display())
        assertNull(transcript.finish(null))
    }

    @Test
    fun `el parcial se ve mientras se habla`() {
        val transcript = VoskTranscript()

        transcript.setPartial("anotar una")
        assertEquals("anotar una", transcript.display())

        transcript.setPartial("anotar una compra nueva")
        assertEquals("anotar una compra nueva", transcript.display())
    }

    @Test
    fun `un tramo cerrado por una pausa NO se pierde`() {
        // El defecto: Vosk entrega el tramo al detectar la pausa y se reinicia.
        // Tratarlo como un parcial mas y pedir despues el final devolvia vacio.
        val transcript = VoskTranscript()

        transcript.setPartial("anotar una compra nueva")
        transcript.addSegment("anotar una compra nueva")

        // `getFinalResult()` ya no tiene nada que dar: el tramo se entrego antes.
        assertEquals("anotar una compra nueva", transcript.finish(null))
    }

    @Test
    fun `varios tramos se unen en el orden en que se dijeron`() {
        val transcript = VoskTranscript()

        transcript.addSegment("cincuenta litros de bellator")
        transcript.addSegment("a ciento ochenta y seis bolivianos")

        assertEquals(
            "cincuenta litros de bellator a ciento ochenta y seis bolivianos",
            transcript.finish(null),
        )
        assertEquals(2, transcript.segmentCount)
    }

    @Test
    fun `el ultimo tramo llega en el resultado final`() {
        val transcript = VoskTranscript()

        transcript.addSegment("cincuenta litros de bellator")

        assertEquals(
            "cincuenta litros de bellator a ciento ochenta y seis bolivianos",
            transcript.finish("a ciento ochenta y seis bolivianos"),
        )
    }

    @Test
    fun `cerrar un tramo borra el parcial que lo anunciaba`() {
        // Sin esto, la frase saldria duplicada: el tramo confirmado mas el
        // parcial que decia lo mismo.
        val transcript = VoskTranscript()

        transcript.setPartial("cincuenta litros")
        transcript.addSegment("cincuenta litros")

        assertEquals("cincuenta litros", transcript.display())
    }

    @Test
    fun `lo confirmado y lo provisional se ven juntos`() {
        val transcript = VoskTranscript()

        transcript.addSegment("cincuenta litros de bellator")
        transcript.setPartial("a ciento ochenta")

        assertEquals(
            "cincuenta litros de bellator a ciento ochenta",
            transcript.display(),
        )
    }

    @Test
    fun `el texto vacio o en blanco no cuenta como tramo`() {
        val transcript = VoskTranscript()

        transcript.addSegment("")
        transcript.addSegment("   ")
        transcript.addSegment(null)

        assertEquals(0, transcript.segmentCount)
        assertNull(transcript.finish(null))
    }

    @Test
    fun `silencio sigue siendo silencio, no cadena vacia`() {
        // El guardrail de RISK-032: quien reciba esto no puede confundir
        // «no hubo habla» con «hubo habla y el texto es vacio».
        val transcript = VoskTranscript()

        transcript.setPartial("")

        assertNull(transcript.finish(""))
    }

    @Test
    fun `reset deja la sesion limpia para la siguiente`() {
        val transcript = VoskTranscript()
        transcript.addSegment("cincuenta litros")
        transcript.setPartial("de bellator")

        transcript.reset()

        assertNull(transcript.display())
        assertEquals(0, transcript.segmentCount)
    }

    @Test
    fun `los espacios sobrantes no se cuelan en el texto`() {
        val transcript = VoskTranscript()

        transcript.addSegment("  cincuenta litros  ")

        assertEquals(
            "cincuenta litros de bellator",
            transcript.finish("  de bellator "),
        )
    }
}
