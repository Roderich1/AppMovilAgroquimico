package com.comunidad.agro.voicebench

import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Actividad única del banco de pruebas.
 *
 * Sólo enchufa los dos puentes y reenvía el resultado del permiso. No abre base
 * de datos ni conoce Agrocuentas.
 */
class MainActivity : FlutterActivity() {

    private var speech: SpeechBridge? = null
    private var platform: PlatformBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        speech = SpeechBridge(this, messenger, createEngine(applicationContext))
        platform = PlatformBridge(applicationContext, messenger)
    }

    override fun onPause() {
        // Perder el foco suelta el microfono, siempre. Es la regla de
        // `EVO-009-REQ-005` y aqui se cumple tambien del lado nativo, no solo
        // en Dart: si el proceso se congela, Dart podria no llegar a pedirlo.
        speech?.onHostPaused()
        super.onPause()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        speech?.detach()
        platform?.detach()
        speech = null
        platform = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == SpeechBridge.MIC_REQUEST) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            speech?.onPermissionResult(granted)
        }
    }
}
