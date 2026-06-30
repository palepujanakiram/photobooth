package com.srisarani.fotozenai

import android.view.KeyEvent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class HardwareKeysHandler(
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private var enabled: Boolean = false

    init {
        channel.setMethodCallHandler(::onMethodCall)
    }

    fun handleKeyEvent(event: KeyEvent): Boolean {
        if (!enabled) return false
        val code = event.keyCode
        if (!isCaptureShutterKeyCode(code)) return false
        channel.invokeMethod(
            "onKey",
            mapOf(
                "keyCode" to code,
                "action" to event.action,
                "timestampMs" to event.eventTime,
            ),
        )
        return true
    }

    private fun isCaptureShutterKeyCode(code: Int): Boolean =
        when (code) {
            KeyEvent.KEYCODE_CAMERA,
            KeyEvent.KEYCODE_FOCUS,
            KeyEvent.KEYCODE_ENTER,
            KeyEvent.KEYCODE_DPAD_CENTER,
            KeyEvent.KEYCODE_SPACE,
            KeyEvent.KEYCODE_VOLUME_UP,
            KeyEvent.KEYCODE_VOLUME_DOWN,
            -> true

            else -> false
        }

    private fun onMethodCall(
        call: io.flutter.plugin.common.MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "setEnabled" -> {
                val args = call.arguments as? Map<*, *>
                enabled = args?.get("enabled") as? Boolean ?: false
                result.success(null)
            }

            else -> {
                result.notImplemented()
            }
        }
    }

    companion object {
        private const val CHANNEL_NAME = "photobooth/hardware_keys"

        fun attach(flutterEngine: FlutterEngine) = HardwareKeysHandler(flutterEngine.dartExecutor.binaryMessenger)
    }
}
