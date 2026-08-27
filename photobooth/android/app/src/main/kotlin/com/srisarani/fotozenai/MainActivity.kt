package com.srisarani.fotozenai

import android.content.Intent
import android.hardware.usb.UsbManager
import android.os.Bundle
import android.view.KeyEvent
import com.srisarani.fotozenai.canon.CanonSidecarService
import com.srisarani.fotozenai.canon.CanonSidecarStatusMethodChannel
import com.srisarani.fotozenai.canon.CanonUsbPermissionManager
import com.srisarani.fotozenai.canoncapture.CanonCameraStack
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {
    private var hardwareKeysHandler: HardwareKeysHandler? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // ComponentActivity is required for enableEdgeToEdge(); FlutterActivity is not one.
        EdgeToEdgeDisplay.enable(this)
        super.onCreate(savedInstanceState)
        PaymentNotificationChannelSetup.registerIfNeeded(this)
        // Only one Canon stack may touch the camera — see CanonCameraStack. Default is
        // EDSDK; ZenAI direct_ptp persists PTP so cold start skips the sidecar.
        if (CanonCameraStack.usesEdsdkSidecar(this)) {
            CanonSidecarService.start(this)
            handleUsbIntent(intent)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleUsbIntent(intent)
    }

    private fun handleUsbIntent(intent: Intent?) {
        if (!CanonCameraStack.usesEdsdkSidecar(this)) return
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
        // Both channels register regardless: Dart may query either one's status, and a
        // channel with no camera behind it answers "not available" rather than hanging.
        CanonSidecarStatusMethodChannel.register(flutterEngine, this)
        CanonPtpMethodChannel.register(flutterEngine, this)
        hardwareKeysHandler = HardwareKeysHandler.attach(flutterEngine)
    }

    override fun onResume() {
        super.onResume()
        DnpUsbMethodChannel.onResume(this)
        ReceiptUsbMethodChannel.onResume(this)
        if (CanonCameraStack.usesEdsdkSidecar(this)) {
            CanonUsbPermissionManager.requestPermissionIfNeeded(this)
        } else {
            CanonPtpMethodChannel.onResume(this)
        }
    }

    override fun onStop() {
        // Release the DSLR on the way out so a later process kill cannot leave the camera
        // mid-transaction, which costs a physical power cycle to clear.
        if (CanonCameraStack.usesPtp(this)) {
            CanonPtpMethodChannel.onStop()
        }
        super.onStop()
    }

    override fun onDestroy() {
        if (CanonCameraStack.usesEdsdkSidecar(this)) {
            CanonSidecarService.stop(this)
        }
        DnpUsbMethodChannel.onDestroy()
        ReceiptUsbMethodChannel.onDestroy()
        SelphyMethodChannel.onDestroy()
        CanonPtpMethodChannel.onDestroy()
        super.onDestroy()
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ) {
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
