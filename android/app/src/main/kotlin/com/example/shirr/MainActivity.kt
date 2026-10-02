package com.example.shirr

import android.media.*
import android.os.*
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.*
import java.nio.ByteBuffer
import java.nio.ByteOrder

class MainActivity : FlutterActivity() {

    companion object {
        init {
            // Load the native library
            System.loadLibrary("essentia_jni")
        }

        // Declare the native methods
        @JvmStatic
        external fun getEssentiaVersion(): String

        @JvmStatic
        external fun detectBeats(audioBuffer: FloatArray, sampleRate: Int): FloatArray

        @JvmStatic
        external fun detectOnsets(audioBuffer: FloatArray, sampleRate: Int): FloatArray

        @JvmStatic
        external fun detectPitch(audioBuffer: FloatArray, sampleRate: Int): FloatArray
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.shirr/convert")
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

        // Set up MethodChannel for communication with Flutter
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.shirr/essentia")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getEssentiaVersion" -> {
                        // Return the Essentia version
                        result.success(getEssentiaVersion())
                    }
                    "detectBeats" -> {
                        val audioBuffer = call.argument<FloatArray>("audioBuffer")
                        val sampleRate = call.argument<Int>("sampleRate") ?: 44100

                        if (audioBuffer != null) {
                            // Call the native method for beat detection
                            val beats = detectBeats(audioBuffer, sampleRate)
                            result.success(beats)
                        } else {
                            result.error("INVALID_ARGUMENT", "Audio buffer is null", null)
                        }
                    }
                    "detectOnsets" -> {
                        val audioBuffer = call.argument<FloatArray>("audioBuffer")
                        val sampleRate = call.argument<Int>("sampleRate") ?: 44100

                        if (audioBuffer != null) {
                            // Call the native method for onset detection
                            val onsets = detectOnsets(audioBuffer, sampleRate)
                            result.success(onsets)
                        } else {
                            result.error("INVALID_ARGUMENT", "Audio buffer is null", null)
                        }
                    }
                    "detectPitch" -> {
                        val audioBuffer = call.argument<FloatArray>("audioBuffer")
                        val sampleRate = call.argument<Int>("sampleRate") ?: 44100

                        if (audioBuffer != null) {
                            // Call the native method for pitch detection
                            val pitches = detectPitch(audioBuffer, sampleRate)
                            result.success(pitches)
                        } else {
                            result.error("INVALID_ARGUMENT", "Audio buffer is null", null)
                        }
                    }
                    else -> {
                        result.notImplemented() // Method not implemented error
                    }
                }
            }
    }
}
