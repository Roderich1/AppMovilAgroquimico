package com.comunidad.agro.voicebench

import android.content.Context
import android.os.Build
import android.os.Debug
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Datos del aparato, memoria y carpeta de exportación.
 *
 * Deliberadamente separado de `SpeechBridge`: identificar el teléfono no es
 * transcribir, y el puerto que heredará `EVO-009` no debe cargar con esto.
 */
class PlatformBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)

    init {
        channel.setMethodCallHandler(this)
    }

    fun detach() = channel.setMethodCallHandler(null)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "deviceInfo" -> result.success(
                mapOf(
                    "device" to "${Build.MANUFACTURER} ${Build.MODEL}",
                    "androidRelease" to Build.VERSION.RELEASE,
                    "androidSdk" to Build.VERSION.SDK_INT,
                    "abi" to (Build.SUPPORTED_ABIS.firstOrNull() ?: "desconocida"),
                ),
            )

            // PSS total del proceso. Es una aproximación, y así se documenta:
            // vale para comparar motores entre sí, no como cifra absoluta.
            "memory" -> {
                val info = Debug.MemoryInfo()
                Debug.getMemoryInfo(info)
                result.success(info.totalPss.toLong() * 1024L)
            }

            // Modo avión **según el sistema**, no según lo que el operador
            // haya marcado en la pantalla. De este dato depende la única
            // afirmación que no admite duda en ADR-002: si el motor transcribe
            // sin Internet. Una tanda mal etiquetada la volveria falsa.
            // `AIRPLANE_MODE_ON` se lee sin permisos; ACCESS_NETWORK_STATE
            // no se pide para no ampliar la superficie del banco.
            "airplaneMode" -> result.success(
                Settings.Global.getInt(
                    context.contentResolver,
                    Settings.Global.AIRPLANE_MODE_ON,
                    0,
                ) != 0,
            )

            "exportDir" -> result.success(
                context.getExternalFilesDir(null)?.absolutePath,
            )

            else -> result.notImplemented()
        }
    }

    companion object {
        const val CHANNEL = "agro.voicebench/platform"
    }
}
