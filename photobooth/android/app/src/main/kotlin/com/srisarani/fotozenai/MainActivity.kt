package com.srisarani.fotozenai

import android.content.Intent
import android.hardware.usb.UsbManager
import android.os.Bundle
import android.view.KeyEvent
import com.srisarani.fotozenai.canon.CanonSidecarService
import com.srisarani.fotozenai.canon.CanonSidecarStatusMethodChannel
import com.srisarani.fotozenai.canon.CanonUsbPermissionManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var hardwareKeysHandler: HardwareKeysHandler? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        PaymentNotificationChannelSetup.registerIfNeeded(this)
        CanonSidecarService.start(this)
        // Handle camera already attached when the app launches.
        handleUsbIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleUsbIntent(intent)
    }

    private fun handleUsbIntent(intent: Intent?) {
        if (intent?.action == UsbManager.ACTION_USB_DEVICE_ATTACHED) {
            CanonUsbPermissionManager.requestPermissionIfNeeded(this)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        DisplayMethodChannel.register(flutterEngine, this)
        DeviceMemoryMethodChannel.register(flutterEngine, this)
        DnpUsbMethodChannel.register(flutterEngine, this)
        ReceiptUsbMethodChannel.register(flutterEngine, this)
        SelphyMethodChannel.register(flutterEngine, this)
        CanonSidecarStatusMethodChannel.register(flutterEngine, this)
        hardwareKeysHandler = HardwareKeysHandler.attach(flutterEngine)
    }

    override fun onResume() {
        super.onResume()
        DnpUsbMethodChannel.onResume(this)
        ReceiptUsbMethodChannel.onResume(this)
        CanonUsbPermissionManager.requestPermissionIfNeeded(this)
    }

    override fun onDestroy() {
        CanonSidecarService.stop(this)
        DnpUsbMethodChannel.onDestroy()
        ReceiptUsbMethodChannel.onDestroy()
        SelphyMethodChannel.onDestroy()
        super.onDestroy()
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (hardwareKeysHandler?.handleKeyEvent(event) == true) {
            return true
        }
        return super.dispatchKeyEvent(event)
    }
}
