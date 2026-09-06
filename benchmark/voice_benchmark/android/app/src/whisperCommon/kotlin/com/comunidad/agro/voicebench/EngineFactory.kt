package com.comunidad.agro.voicebench

import android.content.Context
import com.comunidad.agro.voicebench.engine.WhisperEngine

/**
 * Fábrica de los sabores `whisperTiny` y `whisperBase`.
 *
 * Ambos comparten código: lo único que cambia es el modelo empaquetado, que
 * llega por `BuildConfig.WHISPER_MODEL`.
 */
fun createEngine(context: Context): TranscriptionEngine = WhisperEngine(context)
