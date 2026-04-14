package com.srisarani.fotozenai

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var hardwareKeysEnabled: Boolean = false
    private var hardwareKeysChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "payment_updates",
                "Payment Updates",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "FotoZen payment confirmation alerts"
                enableLights(true)
                enableVibration(true)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "photobooth/display")
            .setMethodCallHandler { call, result ->
                if (call.method == "getRotation") {
                    val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
                    @Suppress("DEPRECATION")
                    result.success(wm.defaultDisplay.rotation)
                } else {
                    result.notImplemented()
                }
            }

        hardwareKeysChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "photobooth/hardware_keys"
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "setEnabled" -> {
                        val args = call.arguments as? Map<*, *>
                        val enabled = args?.get("enabled") as? Boolean ?: false
                        hardwareKeysEnabled = enabled
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (hardwareKeysEnabled) {
            val code = event.keyCode
            if (code == KeyEvent.KEYCODE_VOLUME_UP || code == KeyEvent.KEYCODE_VOLUME_DOWN) {
                // Forward to Flutter. Consume so system volume UI doesn't show.
                hardwareKeysChannel?.invokeMethod(
                    "onKey",
                    mapOf(
                        "keyCode" to code,
                        "action" to event.action,
                        "timestampMs" to event.eventTime
                    )
                )
                return true
            }
        }
        return super.dispatchKeyEvent(event)
    }
}
