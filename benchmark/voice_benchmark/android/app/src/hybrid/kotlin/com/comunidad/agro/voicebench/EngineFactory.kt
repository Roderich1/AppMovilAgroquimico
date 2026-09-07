package com.comunidad.agro.voicebench

import android.content.Context
import com.comunidad.agro.voicebench.engine.HybridEngine

/**
 * Fábrica del sabor `hybrid` (candidato C4).
 *
 * Es el único APK que lleva los dos motores, porque es el único que los usa
 * sobre la misma captura.
 */
fun createEngine(context: Context): TranscriptionEngine = HybridEngine(context)
