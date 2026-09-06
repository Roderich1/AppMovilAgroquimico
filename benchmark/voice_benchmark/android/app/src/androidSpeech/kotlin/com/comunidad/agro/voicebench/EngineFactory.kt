package com.comunidad.agro.voicebench

import android.content.Context
import com.comunidad.agro.voicebench.engine.AndroidSpeechEngine

/**
 * Fábrica del sabor `androidSpeech`.
 *
 * Existe una función con este mismo nombre en cada sabor. Gradle compila sólo la
 * del sabor elegido, así que el APK de Android no contiene una línea de Whisper
 * y viceversa: cada medición corre contra un binario que sólo tiene su motor.
 */
fun createEngine(context: Context): TranscriptionEngine = AndroidSpeechEngine(context)
