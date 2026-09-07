package com.comunidad.agro.voicebench.engine

import android.content.Context
import com.comunidad.agro.voicebench.BuildConfig
import java.io.File

/**
 * Deja el modelo de Vosk disponible como carpeta en disco privado.
 *
 * ## Por qué hace falta copiarlo
 *
 * Vosk abre el modelo con rutas de sistema de archivos: no sabe leer de los
 * assets de un APK. Se copia una vez a `filesDir` y se reutiliza.
 *
 * ## Prioridad de búsqueda
 *
 * 1. `<externalFilesDir>/models/<nombre>/` — permite sustituir el modelo sin
 *    recompilar, que es lo que hace falta para probar otro candidato en el
 *    mismo teléfono sin rehacer el APK.
 * 2. `<filesDir>/<nombre>/` — la copia ya hecha.
 * 3. Los assets del APK.
 *
 * **Nunca se descarga.** El teléfono no necesita Internet: es justamente lo que
 * `ADR-004` quiere demostrar.
 *
 * La copia se marca terminada con un archivo centinela. Sin él, una copia
 * interrumpida —proceso muerto, disco lleno— dejaría un modelo a medias que
 * Vosk abriría con resultados imposibles de explicar.
 */
object VoskModelStore {

    private const val SENTINEL = ".completo"

    /** Carpeta lista para `Model(path)`, o `null` si no se pudo preparar. */
    fun ensureModel(context: Context): File? {
        val name = BuildConfig.VOSK_MODEL
        if (name.isEmpty()) return null

        val sideloaded = File(File(context.getExternalFilesDir(null), "models"), name)
        if (sideloaded.isDirectory && File(sideloaded, "am").isDirectory) {
            return sideloaded
        }

        val target = File(context.filesDir, name)
        if (File(target, SENTINEL).isFile) return target

        // Una copia anterior incompleta no sirve: se rehace entera.
        if (target.exists()) target.deleteRecursively()

        return try {
            copyAsset(context, "models/$name", target)
            File(target, SENTINEL).writeBytes(ByteArray(0))
            target
        } catch (_: Throwable) {
            target.deleteRecursively()
            null
        }
    }

    /** Tamaño instalado del modelo, para registrarlo en la medición. */
    fun installedBytes(model: File): Long =
        model.walkTopDown().filter { it.isFile }.sumOf { it.length() }

    private fun copyAsset(context: Context, assetPath: String, target: File) {
        val children = context.assets.list(assetPath) ?: emptyArray()
        if (children.isEmpty()) {
            target.parentFile?.mkdirs()
            context.assets.open(assetPath).use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            }
            return
        }
        target.mkdirs()
        for (child in children) {
            copyAsset(context, "$assetPath/$child", File(target, child))
        }
    }
}
