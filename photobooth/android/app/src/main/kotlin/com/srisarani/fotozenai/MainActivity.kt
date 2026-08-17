package com.srisarani.fotozenai

import android.content.Intent
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
        DnpUsbMethodChannel.register(flutterEngine, this)
        ReceiptUsbMethodChannel.register(flutterEngine, this)
        SelphyMethodChannel.register(flutterEngine, this)
        CanonPtpMethodChannel.register(flutterEngine, this)
        hardwareKeysHandler = HardwareKeysHandler.attach(flutterEngine)
    }

    override fun onResume() {
        super.onResume()
        DnpUsbMethodChannel.onResume(this)
        ReceiptUsbMethodChannel.onResume(this)
        CanonPtpMethodChannel.onResume(this)
    }

    override fun onStop() {
        // Release the DSLR on the way out so a later process kill cannot leave the camera
        // mid-transaction, which costs a physical power cycle to clear.
        CanonPtpMethodChannel.onStop()
        super.onStop()
    }

    override fun onDestroy() {
        DnpUsbMethodChannel.onDestroy()
        ReceiptUsbMethodChannel.onDestroy()
        SelphyMethodChannel.onDestroy()
        CanonPtpMethodChannel.onDestroy()
        super.onDestroy()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        // The native DSLR capture screen returns its shots this way; anything it does not
        // claim falls through to Flutter's own plugin result handling.
        if (CanonPtpMethodChannel.onActivityResult(requestCode, resultCode, data)) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (hardwareKeysHandler?.handleKeyEvent(event) == true) {
            return true
        }
        return super.dispatchKeyEvent(event)
    }
}
