package com.comunidad.agro.voicebench

import android.content.Context
import com.comunidad.agro.voicebench.engine.VoskEngine

/**
 * Fábrica del sabor `vosk` (candidato C1).
 *
 * Existe una función con este mismo nombre en cada sabor y Gradle compila sólo
 * la del sabor elegido: el APK de Vosk no contiene una línea de Whisper y
 * viceversa. Cada medición corre contra un binario que sólo tiene su motor.
 */
fun createEngine(context: Context): TranscriptionEngine = VoskEngine(context)
