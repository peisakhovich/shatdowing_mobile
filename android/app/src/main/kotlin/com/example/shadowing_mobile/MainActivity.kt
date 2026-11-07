package com.example.shadowing_mobile

import android.content.Context
import android.os.PowerManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {

    private val channelName = "com.example.shadowing_mobile/wake_lock"

    private var wakeLock: PowerManager.WakeLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->

            when (call.method) {
                "acquire" -> {
                    try {
                        acquireWakeLock()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("WAKE_LOCK_ERROR", e.message, null)
                    }
                }

                "release" -> {
                    releaseWakeLock()
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun acquireWakeLock() {
        val powerManager =
            getSystemService(Context.POWER_SERVICE) as PowerManager

        if (wakeLock == null) {
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "$packageName:ShadowingWakeLock"
            )
        }

        if (wakeLock?.isHeld != true) {
            wakeLock?.acquire()
        }
    }

    private fun releaseWakeLock() {
        if (wakeLock?.isHeld == true) {
            wakeLock?.release()
        }
    }

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }
}