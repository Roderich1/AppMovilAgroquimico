package com.comunidad.agro.agroquimicos

import android.content.Context
import android.content.SharedPreferences
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * A synchronous durability barrier for flutter_secure_storage 11.2.0's
 * SharedPreferences.apply(), followed by one committed active-slot pointer.
 * This class never receives or stores a credential.
 */
internal object SecureSessionPointerChannel {
    private class CorruptPointerException : Exception()
    private const val channelName = "agrocuentas/secure_session_pointer"
    private const val namespace = "agrocuentas_secure_session_v1"
    private const val pointerPrefs = "AgrocuentasSessionPointer"
    private const val pointerKey = "activeSlot"
    private const val refreshGuardKey = "refreshQuarantined"
    private val lock = Any()

    fun register(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        MethodChannel(messenger, channelName).setMethodCallHandler { call, result ->
            // SharedPreferences.commit() can block on disk I/O. Never run it
            // on the Android UI thread.
            Thread {
                try {
                    val value = synchronized(lock) {
                        when (call.method) {
                            "read" -> read(app)
                            "activate" -> {
                                val expected = call.argument<String>("expected")
                                val next = call.argument<String>("next")
                                requireSlotOrNull(expected)
                                requireSlot(next)
                                if (expected == next) throw IllegalArgumentException("Same slot")
                                flushEncryptedPrefs(app)
                                replacePointer(app, expected, next)
                                next
                            }
                            "clear" -> {
                                val expected = call.argument<String>("expected")
                                requireSlot(expected)
                                replacePointer(app, expected, null)
                                null
                            }
                            "flush" -> {
                                flushEncryptedPrefs(app)
                                null
                            }
                            "readRefreshGuard" -> readRefreshGuard(app)
                            "setRefreshGuard" -> {
                                if (readRefreshGuard(app)) throw IllegalStateException("Refresh already quarantined")
                                writeRefreshGuard(app, true)
                                true
                            }
                            "clearRefreshGuard" -> {
                                if (!readRefreshGuard(app)) throw IllegalStateException("Refresh guard not set")
                                writeRefreshGuard(app, false)
                                false
                            }
                            else -> throw UnsupportedOperationException("Unknown method")
                        }
                    }
                    result.success(value)
                } catch (e: Exception) {
                    // No exception text, path, key or encrypted payload crosses
                    // the channel. Dart reconciles an indeterminate activation.
                    val code = if (e is CorruptPointerException) "CORRUPT_POINTER" else "SECURE_SESSION_STORAGE"
                    result.error(code, "Storage operation failed", null)
                }
            }.start()
        }
    }

    private fun preferences(context: Context): SharedPreferences =
        context.getSharedPreferences(pointerPrefs, Context.MODE_PRIVATE)

    private fun read(context: Context): String? {
        val slot = preferences(context).getString(pointerKey, null)
        if (slot != null && slot != "a" && slot != "b") throw CorruptPointerException()
        return slot
    }

    private fun replacePointer(context: Context, expected: String?, next: String?) {
        if (read(context) != expected) throw IllegalStateException("Pointer changed")
        val editor = preferences(context).edit()
        if (next == null) editor.remove(pointerKey) else editor.putString(pointerKey, next)
        if (!editor.commit() || read(context) != next) {
            throw IllegalStateException("Pointer commit not verified")
        }
    }

    private fun readRefreshGuard(context: Context): Boolean {
        val prefs = preferences(context)
        if (!prefs.contains(refreshGuardKey)) return false
        val raw = prefs.all[refreshGuardKey]
        if (raw !is Boolean) throw IllegalStateException("Invalid refresh guard")
        return raw
    }

    private fun writeRefreshGuard(context: Context, quarantined: Boolean) {
        val prefs = preferences(context)
        if (!prefs.edit().putBoolean(refreshGuardKey, quarantined).commit() ||
            readRefreshGuard(context) != quarantined) {
            throw IllegalStateException("Refresh guard commit not verified")
        }
    }

    private fun flushEncryptedPrefs(context: Context) {
        // Android documents that commit() waits for outstanding apply() calls
        // on the same SharedPreferences instance and reports disk-write failure.
        val files = arrayOf(
            namespace,
            "FlutterSecureKeyStorage:$namespace",
            "FlutterSecureStorageConfiguration:$namespace",
        )
        for (name in files) {
            if (!context.getSharedPreferences(name, Context.MODE_PRIVATE).edit().commit()) {
                throw IllegalStateException("Encrypted storage flush failed")
            }
        }
    }

    private fun requireSlot(slot: String?) {
        if (slot != "a" && slot != "b") throw IllegalArgumentException("Invalid slot")
    }

    private fun requireSlotOrNull(slot: String?) {
        if (slot != null) requireSlot(slot)
    }
}
