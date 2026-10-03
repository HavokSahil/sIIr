package io.siirsuite.siir

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.*

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "io.siirsuite.siir/convert")
            .setMethodCallHandler { call, result ->
                if (call.method != "decode") {
                    result.notImplemented()
                } else {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("INVALID_ARGUMENT", "Audio path is required", null)
                    } else {
                        Thread {
                            try {
                                val decoded = AudioConverter(this).decodeToWav(path)
                                runOnUiThread { result.success(decoded) }
                            } catch (error: Exception) {
                                runOnUiThread { result.error("DECODE_FAILED", error.message, null) }
                            }
                        }.start()
                    }
                }
            }

    }
}
