package com.comunidad.agro.agroquimicos

import android.app.Activity
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * FLAG_SECURE de la ventana mientras se muestra, se confirma o se escribe la
 * clave de recuperación del respaldo (F08-ADR-003 §3.4): sin capturas ni
 * grabación de pantalla, y con la miniatura de recientes en blanco.
 *
 * Dart lleva la cuenta de las pantallas y diálogos que la necesitan; aquí sólo
 * se aplica el estado pedido y se devuelve el que quedó. El manejador corre en
 * el hilo de la interfaz, así que la marca ya está puesta cuando Dart recibe la
 * respuesta y pinta la clave. Una actividad nueva trae un motor nuevo con la
 * cuenta a cero, y empieza sin la marca.
 */
internal object ScreenSecureChannel {
    private const val channelName = "agrocuentas/screen_secure"

    fun register(activity: Activity, messenger: BinaryMessenger) {
        MethodChannel(messenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "setSecure" -> {
                    val secure = call.argument<Boolean>("secure")
                    if (secure == null) {
                        result.error("INVALID_ARGUMENT", "secure is required", null)
                    } else {
                        if (secure) {
                            activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(isSecure(activity))
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isSecure(activity: Activity): Boolean =
        (activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE) != 0
}
