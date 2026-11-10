package com.comunidad.agro.agroquimicos

/**
 * Funciones nativas de `libagro_whisper.so` (whisper.cpp, segunda pasada).
 *
 * La librería no viaja en el repositorio: la produce
 * `tool/voice_local/build_whisper_libs.sh`. Si no está en el APK, [available]
 * es `false` y la voz sigue sólo con Vosk, sin error para el usuario.
 */
object WhisperNative {

    /** `null` si la librería se cargó; si no, por qué. Sin datos dictados. */
    val loadFailure: String? = try {
        System.loadLibrary("agro_whisper")
        null
    } catch (t: Throwable) {
        t.javaClass.simpleName
    }

    val available: Boolean get() = loadFailure == null

    external fun init(modelPath: String): Long
    external fun free(context: Long)
    external fun abort()
    external fun transcribe(
        context: Long,
        audio: FloatArray,
        prompt: String?,
        threads: Int,
        outNoSpeech: FloatArray,
    ): String?

    /**
     * Como [transcribe], con el ancho del haz: 1 = voraz (igual que
     * [transcribe]); > 1 = búsqueda en haz a temperatura 0, sin reintentos.
     * Sólo la usa el turno entero (F09, 2026-11-10).
     */
    external fun transcribeWith(
        context: Long,
        audio: FloatArray,
        prompt: String?,
        threads: Int,
        outNoSpeech: FloatArray,
        beamSize: Int,
    ): String?
}
