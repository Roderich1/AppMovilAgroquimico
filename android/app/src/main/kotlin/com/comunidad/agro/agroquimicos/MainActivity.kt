package com.comunidad.agro.agroquimicos

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "agrocuentas/installation_identity",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getNoBackupDirectory" -> result.success(noBackupFilesDir.absolutePath)
                else -> result.notImplemented()
            }
        }
    }
}
