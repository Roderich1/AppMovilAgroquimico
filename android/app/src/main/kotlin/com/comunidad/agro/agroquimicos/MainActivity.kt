package com.comunidad.agro.agroquimicos

import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Actividad única de Agrocuentas.
 *
 * Lo añadido por `EVO-009` es el puente de voz y el reenvío del resultado del
 * permiso de micrófono. No abre base de datos ni conoce el dominio.
 */
class MainActivity : FlutterActivity() {

    private var voice: VoiceSpeechBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        voice = VoiceSpeechBridge(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
            VoiceSpeechEngine(applicationContext),
        )
    }

    override fun onPause() {
        // Perder el foco suelta el microfono, SIEMPRE. Es `EVO-009-REQ-005`, y
        // se cumple tambien del lado nativo: si el proceso se congela, Dart
        // podria no llegar a pedirlo y el reconocedor quedaria escuchando.
        voice?.onHostPaused()
        super.onPause()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        voice?.detach()
        voice = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == VoiceSpeechBridge.MIC_REQUEST) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            voice?.onPermissionResult(granted)
        }
    }
}
