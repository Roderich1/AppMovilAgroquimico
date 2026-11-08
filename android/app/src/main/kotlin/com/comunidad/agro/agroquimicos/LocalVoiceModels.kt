package com.comunidad.agro.agroquimicos

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

/**
 * Deja los modelos de voz del APK listos en disco privado, verificados.
 *
 * Los modelos viajan **dentro del APK** (`assets/voice/`), los deja ahí
 * `tool/voice_local/fetch_voice_models.sh` tras comprobar su SHA-256, y nunca se
 * descargan desde la app: el primer dictado no necesita conexión.
 *
 * Vosk y whisper.cpp abren archivos, no assets, así que se copian una vez a
 * `noBackupFilesDir/voice/` (fuera del respaldo de Android). Cada archivo se
 * verifica contra `assets/voice/manifest.json` **mientras se copia**; sólo si
 * todos coinciden se escribe el centinela. Una copia interrumpida o alterada no
 * se usa: se rehace entera la próxima vez.
 */
class LocalVoiceModels(private val context: Context) {

    /** Lo que dice el manifiesto del APK, o `null` si el APK no trae modelos. */
    val manifest: JSONObject? = try {
        context.assets.open("$ASSETS/manifest.json").use {
            JSONObject(it.readBytes().toString(Charsets.UTF_8))
        }
    } catch (_: Throwable) {
        null
    }

    val voskName: String? get() = manifest?.optJSONObject("vosk")?.optString("name")
    val whisperName: String? get() = manifest?.optJSONObject("whisper")?.optString("name")

    /** Carpeta de Vosk lista para `Model(path)`. Lanza [ModelException]. */
    fun vosk(): File {
        val entry = manifest?.optJSONObject("vosk") ?: throw ModelException("model-missing")
        return prepare(entry)
    }

    /** Archivo del modelo Whisper, o `null` si este APK no lo trae. */
    fun whisperOrNull(): File? {
        val entry = manifest?.optJSONObject("whisper") ?: return null
        return File(prepare(entry), entry.getString("file"))
    }

    private fun prepare(entry: JSONObject): File {
        val name = entry.getString("name")
        val files = entry.getJSONObject("files")
        val root = File(File(context.noBackupFilesDir, "voice"), name)
        val sentinel = File(root, SENTINEL)
        val fingerprint = sha256(files.toString().toByteArray())
        // Además del centinela, el tamaño de cada archivo: comprobarlo no cuesta
        // nada, y un archivo truncado después de verificarlo (almacenamiento
        // lleno, limpieza a medias) se rehace en vez de dárselo a Vosk.
        if (sentinel.isFile && sentinel.readText() == fingerprint && sizesMatch(root, files)) {
            return root
        }

        root.deleteRecursively()
        try {
            for (relative in files.keys()) {
                val expected = files.getJSONObject(relative)
                val target = File(root, relative)
                target.parentFile?.mkdirs()
                val digest = MessageDigest.getInstance("SHA-256")
                var size = 0L
                context.assets.open("$ASSETS/$name/$relative").use { input ->
                    target.outputStream().use { output ->
                        val buffer = ByteArray(1 shl 16)
                        while (true) {
                            val read = input.read(buffer)
                            if (read <= 0) break
                            digest.update(buffer, 0, read)
                            output.write(buffer, 0, read)
                            size += read
                        }
                    }
                }
                val actual = digest.digest().joinToString("") { "%02x".format(it) }
                if (size != expected.getLong("size") || actual != expected.getString("sha256")) {
                    throw ModelException("model-integrity")
                }
            }
            sentinel.writeText(fingerprint)
            return root
        } catch (e: ModelException) {
            root.deleteRecursively()
            throw e
        } catch (t: Throwable) {
            root.deleteRecursively()
            throw ModelException(
                if (t is java.io.FileNotFoundException) "model-missing" else "model-copy",
            )
        }
    }

    /**
     * Fuerza a rehacer la copia de Vosk la próxima vez. Para un modelo que pasó
     * la verificación y aun así no cargó.
     */
    fun invalidateVosk() {
        val name = voskName?.takeIf { it.isNotEmpty() } ?: return
        File(File(File(context.noBackupFilesDir, "voice"), name), SENTINEL).delete()
    }

    private fun sizesMatch(root: File, files: JSONObject): Boolean {
        for (relative in files.keys()) {
            val file = File(root, relative)
            if (!file.isFile || file.length() != files.getJSONObject(relative).getLong("size")) {
                return false
            }
        }
        return true
    }

    class ModelException(val code: String) : Exception(code)

    private fun sha256(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    companion object {
        const val ASSETS = "voice"
        private const val SENTINEL = ".verificado"
    }
}
