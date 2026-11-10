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

    /**
     * Variante del modelo de revisión elegida al compilar (`base`, `small`),
     * o `null` si el manifiesto no la declara (APK anteriores: Dart la deduce
     * del nombre).
     */
    val whisperVariant: String?
        get() = manifest?.optJSONObject("whisper")?.optString("variant")?.takeIf { it.isNotEmpty() }

    /** Bytes del modelo de revisión según el manifiesto, o `null`. */
    val whisperBytes: Long?
        get() {
            val files = manifest?.optJSONObject("whisper")?.optJSONObject("files") ?: return null
            var total = 0L
            for (name in files.keys()) total += files.getJSONObject(name).optLong("size", 0L)
            return total.takeIf { it > 0 }
        }

    /** Carpeta de Vosk lista para `Model(path)`. Lanza [ModelException]. */
    fun vosk(): File {
        val entry = manifest?.optJSONObject("vosk") ?: throw ModelException("model-missing")
        return prepare(entry)
    }

    /**
     * Variantes de Whisper que trae el APK: la principal (`whisper`, la de la
     * revisión) y las alternativas (`whisperAlternatives`, por variante), que
     * `fetch_voice_models.sh both` empaqueta para el experimento de un solo
     * transcriptor por turno. Vacía si el APK no trae Whisper.
     */
    val whisperVariants: List<String>
        get() {
            val out = mutableListOf<String>()
            if (manifest?.optJSONObject("whisper") != null) out += whisperVariant ?: "base"
            manifest?.optJSONObject("whisperAlternatives")?.let { alternatives ->
                for (key in alternatives.keys()) if (key !in out) out += key
            }
            return out
        }

    /** Nombre del modelo de la variante [variant] (`null` = la principal), o `null`. */
    fun whisperNameOf(variant: String?): String? =
        whisperEntry(variant)?.optString("name")?.takeIf { it.isNotEmpty() }

    private fun whisperEntry(variant: String?): JSONObject? {
        val main = manifest?.optJSONObject("whisper")
        if (variant == null) return main
        if (main != null && variant == (whisperVariant ?: "base")) return main
        return manifest?.optJSONObject("whisperAlternatives")?.optJSONObject(variant)
    }

    /**
     * Archivo del modelo Whisper de la variante [variant] (`null` = la
     * principal), o `null` si este APK no la trae. Lanza [ModelException] si la
     * copia o la verificación fallan.
     */
    fun whisperOrNull(variant: String? = null): File? {
        val entry = whisperEntry(variant) ?: return null
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
