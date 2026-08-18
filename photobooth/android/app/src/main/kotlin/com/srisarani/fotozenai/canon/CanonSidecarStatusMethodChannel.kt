package com.srisarani.fotozenai.canon

import android.content.Context
import android.hardware.usb.UsbManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

/**
 * Exposes Canon sidecar and camera USB state to Flutter for the Device Status screen.
 *
 * Methods:
 *  - `getState`        → String ("idle" | "running" | "waiting_usb" | "restarting" |
 *                        "crashed" | "max_restarts" | "unsupported_abi")
 *  - `isCameraPresent` → Boolean (true if Canon DSLR is in the USB device list)
 */
object CanonSidecarStatusMethodChannel {
    private const val CHANNEL = "com.srisarani.fotozenai/canon_sidecar_status"

    private var appContextRef: WeakReference<Context>? = null
    /** Activity context — required for [UsbManager.requestPermission] dialog. */
    private var permissionContextRef: WeakReference<Context>? = null

    fun register(engine: FlutterEngine, context: Context) {
        appContextRef = WeakReference(context.applicationContext)
        permissionContextRef = WeakReference(context)
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getState" -> result.success(CanonSidecarService.state)
                    "isCameraPresent" -> result.success(queryCameraPresent())
                    "hasUsbPermission" -> result.success(queryUsbPermission())
                    "requestUsbPermission" -> {
                        val ctx = permissionContextRef?.get() ?: appContextRef?.get()
                        if (ctx == null) {
                            result.success(false)
                        } else {
                            result.success(
                                CanonUsbPermissionManager.requestPermissionIfNeeded(ctx),
                            )
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun queryCameraPresent(): Boolean {
        val ctx = appContextRef?.get() ?: return false
        val usbManager = ctx.getSystemService(Context.USB_SERVICE) as? UsbManager ?: return false
        return CanonUsbPermissionManager.findCanonCamera(usbManager) != null
    }

    private fun queryUsbPermission(): Boolean {
        val ctx = appContextRef?.get() ?: return false
        return CanonUsbPermissionManager.hasGrantedPermission(ctx)
    }
}
