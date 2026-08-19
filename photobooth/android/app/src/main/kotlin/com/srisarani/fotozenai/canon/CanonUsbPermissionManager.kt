package com.srisarani.fotozenai.canon

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbManager
import android.os.Build
import android.util.Log

/**
 * Requests and tracks USB permission for the Canon DSLR camera.
 *
 * Canon vendor ID 0x04A9 covers all Canon USB devices. We identify DSLRs by
 * the PTP/MTP Still Imaging interface class (6). Selphy printers use the
 * printer class (7), so the two never conflict.
 */
object CanonUsbPermissionManager {

    private const val TAG = "CanonUsbPerm"
    private const val ACTION_USB_PERMISSION = "com.srisarani.fotozenai.CANON_USB_PERMISSION"

    /** Broadcast fired (locally) when permission is granted. */
    const val ACTION_CANON_PERMISSION_GRANTED = "com.srisarani.fotozenai.CANON_PERMISSION_GRANTED"

    private const val CANON_VENDOR_ID = 0x04A9

    /** PTP/MTP Still Imaging interface class — used by all Canon DSLRs. */
    private const val USB_CLASS_STILL_IMAGING = 6

    private var receiver: BroadcastReceiver? = null

    @Volatile
    private var permissionRequestInFlight = false

    // ── Public API ────────────────────────────────────────────────────────────

    /**
     * Finds the first Canon DSLR in the USB device list and requests permission
     * if not already granted. Returns true when permission is already held.
     *
     * When the user grants the system dialog, [ACTION_CANON_PERMISSION_GRANTED]
     * is broadcast so [CanonSidecarService] can launch the sidecar.
     */
    fun requestPermissionIfNeeded(context: Context): Boolean {
        val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
        val camera = findCanonCamera(usbManager) ?: run {
            Log.d(TAG, "No Canon DSLR found in USB device list")
            return false
        }

        if (usbManager.hasPermission(camera)) {
            Log.i(TAG, "USB permission already granted for ${camera.deviceName}")
            permissionRequestInFlight = false
            sendPermissionGranted(context)
            return true
        }

        if (permissionRequestInFlight) {
            Log.d(TAG, "USB permission dialog already showing for ${camera.deviceName}")
            return false
        }

        registerReceiver(context, usbManager)
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
            PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        else
            PendingIntent.FLAG_UPDATE_CURRENT

        val pi = PendingIntent.getBroadcast(context, 0,
            Intent(ACTION_USB_PERMISSION).setPackage(context.packageName), flags)
        permissionRequestInFlight = true
        usbManager.requestPermission(camera, pi)
        Log.i(TAG, "USB permission requested for ${camera.deviceName}")
        return false
    }

    fun unregister(context: Context) {
        receiver?.let {
            try { context.unregisterReceiver(it) } catch (_: Exception) {}
            receiver = null
        }
    }

    fun hasGrantedPermission(context: Context): Boolean {
        val usbManager = context.getSystemService(Context.USB_SERVICE) as? UsbManager
            ?: return false
        val camera = findCanonCamera(usbManager) ?: return false
        return usbManager.hasPermission(camera)
    }

    /**
     * Opens the Canon DSLR through [UsbManager]. The resulting file descriptor
     * is what libusb needs; [hasPermission] alone does not make usbfs writable.
     */
    fun openCanonConnection(context: Context): Pair<UsbDevice, UsbDeviceConnection>? {
        val usbManager = context.getSystemService(Context.USB_SERVICE) as? UsbManager
            ?: return null
        val camera = findCanonCamera(usbManager) ?: return null
        if (!usbManager.hasPermission(camera)) {
            Log.w(TAG, "Cannot open ${camera.deviceName}: no USB permission")
            return null
        }
        val connection = usbManager.openDevice(camera)
        if (connection == null) {
            Log.e(TAG, "UsbManager.openDevice returned null for ${camera.deviceName}")
            return null
        }
        detachKernelDriverForEdsdk(connection, camera)
        Log.i(TAG, "Opened ${camera.deviceName} fd=${connection.fileDescriptor}")
        return camera to connection
    }

    /**
     * Force-claim then release the PTP interface so Android's MTP/PTP driver
     * is detached. Leave the interface free — EDSDK/libusb must claim it.
     */
    private fun detachKernelDriverForEdsdk(
        connection: UsbDeviceConnection,
        camera: UsbDevice,
    ) {
        for (i in 0 until camera.interfaceCount) {
            val intf = camera.getInterface(i)
            if (intf.interfaceClass != USB_CLASS_STILL_IMAGING) continue
            try {
                val claimed = connection.claimInterface(intf, true)
                if (claimed) {
                    connection.releaseInterface(intf)
                    Log.i(TAG, "Detached kernel driver on PTP interface $i")
                } else {
                    Log.w(TAG, "claimInterface(force) failed on PTP interface $i")
                }
            } catch (e: Exception) {
                Log.w(TAG, "PTP interface $i prepare: ${e.message}")
            }
        }
    }

    // ── Device detection ──────────────────────────────────────────────────────

    fun findCanonCamera(usbManager: UsbManager): UsbDevice? =
        usbManager.deviceList.values.firstOrNull { isCanonDslr(it) }

    fun isCanonDslr(device: UsbDevice): Boolean {
        if (device.vendorId != CANON_VENDOR_ID) return false
        // Check at least one interface is PTP/MTP Still Imaging.
        for (i in 0 until device.interfaceCount) {
            if (device.getInterface(i).interfaceClass == USB_CLASS_STILL_IMAGING) return true
        }
        return false
    }

    // ── Internal ──────────────────────────────────────────────────────────────

    private fun registerReceiver(context: Context, usbManager: UsbManager) {
        unregister(context)
        receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                if (intent.action != ACTION_USB_PERMISSION) return
                val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                val device  = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
                    intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
                else
                    @Suppress("DEPRECATION") intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
                permissionRequestInFlight = false
                if (granted && device != null) {
                    Log.i(TAG, "USB permission granted for ${device.deviceName}")
                    sendPermissionGranted(ctx)
                } else {
                    Log.w(TAG, "USB permission denied")
                }
            }
        }
        val filter = IntentFilter(ACTION_USB_PERMISSION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(receiver, filter)
        }
    }

    private fun sendPermissionGranted(context: Context) {
        context.sendBroadcast(
            Intent(ACTION_CANON_PERMISSION_GRANTED).setPackage(context.packageName))
    }
}
