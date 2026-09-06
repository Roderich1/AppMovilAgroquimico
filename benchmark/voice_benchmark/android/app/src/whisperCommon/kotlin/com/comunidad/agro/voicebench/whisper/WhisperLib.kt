package com.comunidad.agro.voicebench.whisper

import android.util.Log

/**
 * Enlace con `libwhisper_bench.so`.
 *
 * Los nombres de esta clase y de su `companion object` forman parte del ABI JNI:
 * cambiar el paquete o el nombre rompe la carga de símbolos. Ver
 * `android/app/src/whisperCommon/cpp/whisper_jni.c`.
 */
internal class WhisperLib {
    companion object {
        private const val TAG = "WhisperBench"

        /** `true` si las librerías nativas se cargaron. */
        var loaded: Boolean = false
            private set

        init {
            loaded = try {
                // El orden importa: `libwhisper_bench.so` depende de las de ggml.
                System.loadLibrary("ggml-base")
                System.loadLibrary("ggml-cpu")
                System.loadLibrary("ggml")
                System.loadLibrary("whisper_bench")
                true
            } catch (t: Throwable) {
                Log.e(TAG, "No se pudo cargar whisper: ${t.javaClass.simpleName}")
                false
            }
        }

        external fun initContext(modelPath: String): Long
        external fun freeContext(contextPtr: Long)

        /** Devuelve 0 si whisper terminó bien. */
        external fun fullTranscribe(
            contextPtr: Long,
            numThreads: Int,
            language: String,
            audioData: FloatArray,
        ): Int

        external fun getTextSegmentCount(contextPtr: Long): Int
        external fun getTextSegment(contextPtr: Long, index: Int): String
        external fun getSystemInfo(): String
        external fun getVersion(): String
    }
}
