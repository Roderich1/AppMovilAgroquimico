package com.comunidad.agro.voicebench.engine

/**
 * Acumula lo que Vosk va confirmando durante una sesión.
 *
 * ## El defecto que obliga a que esto exista
 *
 * Vosk no entrega un único resultado al final: **cierra un segmento cada vez
 * que detecta una pausa**. `acceptWaveForm()` devuelve `true` en ese momento y
 * `getResult()` da el texto de ese tramo; después el reconocedor **se
 * reinicia**. Si quien lo usa trata ese texto como un parcial más y luego pide
 * `getFinalResult()`, recibe una cadena vacía, porque lo dicho ya se entregó y
 * se descartó.
 *
 * Eso ocurrió en el teléfono con la primera frase medida: el parcial mostraba
 * «anotar una compra nueva», correcto y completo, y el resultado final llegaba
 * vacío y se reportaba como «sin habla». Habría dado 0 % de acierto a un motor
 * que había acertado.
 *
 * Esta clase es pura a propósito: no toca JNI ni el micrófono, así que la
 * acumulación —que es donde estaba el fallo— se prueba sin teléfono.
 */
class VoskTranscript {

    private val segments = mutableListOf<String>()
    private var partial: String = ""

    /** Empieza una sesión nueva. Idempotente. */
    fun reset() {
        segments.clear()
        partial = ""
    }

    /**
     * Vosk cerró un tramo por una pausa.
     *
     * Se guarda: es texto que ya no cambiará y que `getFinalResult()` no volverá
     * a entregar.
     */
    fun addSegment(text: String?) {
        val clean = text?.trim().orEmpty()
        if (clean.isEmpty()) return
        segments.add(clean)
        partial = ""
    }

    /** Texto provisional del tramo en curso. Sustituye al anterior. */
    fun setPartial(text: String?) {
        partial = text?.trim().orEmpty()
    }

    /**
     * Lo que debe verse en pantalla ahora: lo confirmado más lo provisional.
     *
     * `null` si todavía no hay nada, para no emitir parciales vacíos.
     */
    fun display(): String? {
        val parts = segments + listOfNotNull(partial.ifEmpty { null })
        return parts.joinToString(" ").ifEmpty { null }
    }

    /**
     * El texto completo de la sesión, con el último tramo incluido.
     *
     * `null` significa **sin habla**, no cadena vacía: quien lo reciba no puede
     * confundirlo con un resultado aceptable.
     */
    fun finish(lastResult: String?): String? {
        addSegment(lastResult)
        return segments.joinToString(" ").ifEmpty { null }
    }

    /** Cuántos tramos cerró el motor. Métrica, no contenido. */
    val segmentCount: Int get() = segments.size
}
