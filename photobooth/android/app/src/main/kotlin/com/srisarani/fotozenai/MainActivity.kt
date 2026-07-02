package com.srisarani.fotozenai

import android.os.Bundle
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var hardwareKeysHandler: HardwareKeysHandler? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        PaymentNotificationChannelSetup.registerIfNeeded(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        DisplayMethodChannel.register(flutterEngine, this)
        DeviceMemoryMethodChannel.register(flutterEngine, this)
        hardwareKeysHandler = HardwareKeysHandler.attach(flutterEngine)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (hardwareKeysHandler?.handleKeyEvent(event) == true) {
            return true
        }
        return super.dispatchKeyEvent(event)
    }
}
