package com.srisarani.fotozenai.canon.usb

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import androidx.core.content.ContextCompat
import com.srisarani.fotozenai.canon.CanonLog
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * Finds the camera, gets permission, claims the interface, hands back a [UsbTransport].
 *
 * Everything here needs a real Android USB stack, so it is deliberately kept as thin as
 * possible - all the logic worth testing lives in [EndpointResolver] and [UsbTransport].
 */
class UsbCameraDiscovery(private val context: Context) {

    private val usbManager: UsbManager? =
        context.getSystemService(Context.USB_SERVICE) as? UsbManager

    val isUsbHostSupported: Boolean get() = usbManager != null

    /** Every attached device that looks like a PTP camera. */
    fun findCameras(): List<UsbDevice> {
        val manager = usbManager ?: return emptyList()
        return manager.deviceList.values.filter { device ->
            val isCanon = device.vendorId == CANON_VENDOR_ID
            val hasStillImage = device.interfaces().any { it.isStillImage }
            if (isCanon && !hasStillImage) {
                // Canon body in a non-PTP USB mode - almost always the camera's own menu
                // set to a mass-storage / "PC connect off" mode. Worth calling out
                // explicitly because it looks identical to "camera not detected".
                CanonLog.w(
                    "Canon device %s exposes no still-image interface - check the camera's " +
                        "USB/connection menu setting",
                    device.deviceName,
                )
            }
            hasStillImage
        }
    }

    /** Detailed log of everything attached. First thing to look at when nothing works. */
    fun logAttachedDevices() {
        val manager = usbManager
        if (manager == null) {
            CanonLog.e("No UsbManager - this device cannot host USB (U-07)")
            return
        }
        val devices = manager.deviceList.values
        CanonLog.i("=== %d USB device(s) attached ===", devices.size)
        devices.forEach { device ->
            CanonLog.i(
                "device=%s vendor=0x%04X product=0x%04X class=%d manufacturer=%s product=%s",
                device.deviceName,
                device.vendorId,
                device.productId,
                device.deviceClass,
                device.manufacturerName ?: "?",
                device.productName ?: "?",
            )
            device.interfaces().forEach { iface ->
                CanonLog.i(
                    "  iface id=%d alt=%d class=%d/%d/%d%s",
                    iface.id,
                    iface.alternateSetting,
                    iface.interfaceClass,
                    iface.interfaceSubclass,
                    iface.interfaceProtocol,
                    if (iface.isStillImage) "  <-- still image" else "",
                )
                iface.endpoints.forEach { ep ->
                    CanonLog.i(
                        "    ep addr=0x%02X dir=%s type=%d max=%d",
                        ep.address,
                        if (ep.isIn) "IN" else "OUT",
                        ep.type,
                        ep.maxPacketSize,
                    )
                }
            }
        }
    }

    fun hasPermission(device: UsbDevice): Boolean = usbManager?.hasPermission(device) == true

    /**
     * Requests USB permission and suspends until the user answers.
     *
     * The manifest's USB_DEVICE_ATTACHED filter is the better path in practice: it lets the
     * user tick "always open for this device", which persists across reboots and is what a
     * kiosk needs (U-03, O-01). This explicit request is the fallback for when the app is
     * already running when the camera is plugged in.
     */
    suspend fun requestPermission(device: UsbDevice): Boolean {
        val manager = usbManager ?: return false
        if (manager.hasPermission(device)) return true

        return suspendCancellableCoroutine { continuation ->
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    if (intent.action != ACTION_USB_PERMISSION) return
                    context.unregisterReceiver(this)
                    val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                    CanonLog.i("USB permission %s for %s", if (granted) "GRANTED" else "DENIED", device.deviceName)
                    if (continuation.isActive) continuation.resume(granted)
                }
            }

            ContextCompat.registerReceiver(
                context,
                receiver,
                IntentFilter(ACTION_USB_PERMISSION),
                ContextCompat.RECEIVER_NOT_EXPORTED,
            )

            continuation.invokeOnCancellation { runCatching { context.unregisterReceiver(receiver) } }

            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
            val intent = Intent(ACTION_USB_PERMISSION).setPackage(context.packageName)
            manager.requestPermission(device, PendingIntent.getBroadcast(context, 0, intent, flags))
        }
    }

    /**
     * Opens [device] and returns a ready transport plus the endpoints it resolved.
     *
     * `claimInterface(force = true)` is deliberate: on Android the system MTP handler, a
     * gallery importer or a photo backup app will happily hold the device and leave us
     * with a permission we cannot use (U-02). Forcing takes it back.
     */
    fun open(device: UsbDevice): OpenedCamera {
        val manager = usbManager ?: throw UsbError.OpenFailed(device.deviceName)
        if (!manager.hasPermission(device)) throw UsbError.PermissionDenied(device.deviceName)

        val descriptors = device.interfaces()
        val (ifaceDescriptor, endpoints) = EndpointResolver.resolve(descriptors)
        CanonLog.i("Resolved still-image interface id=%d, %s", ifaceDescriptor.id, endpoints)

        val usbInterface = (0 until device.interfaceCount)
            .map { device.getInterface(it) }
            .first { it.id == ifaceDescriptor.id && it.alternateSetting == ifaceDescriptor.alternateSetting }

        val connection = manager.openDevice(device)
            ?: throw UsbError.OpenFailed(device.deviceName)

        if (!connection.claimInterface(usbInterface, true)) {
            connection.close()
            throw UsbError.ClaimFailed(ifaceDescriptor.id)
        }

        val androidEndpoints = (0 until usbInterface.endpointCount).map { usbInterface.getEndpoint(it) }
        fun find(descriptor: EndpointDescriptor?) =
            descriptor?.let { d -> androidEndpoints.first { it.address == d.address } }

        val channel = AndroidUsbBulkChannel(
            connection = connection,
            usbInterface = usbInterface,
            endpointOut = find(endpoints.bulkOut)!!,
            endpointIn = find(endpoints.bulkIn)!!,
            endpointInterrupt = find(endpoints.interruptIn),
        )

        CanonLog.i(
            "Camera opened: %s (%s), serial=%s",
            device.productName ?: "unknown",
            device.deviceName,
            runCatching { connection.serial }.getOrNull() ?: "unavailable",
        )

        if (endpoints.interruptIn == null) {
            // Not fatal for M1/M2, but M3's event loop depends on it. Flag it now rather
            // than letting M3 fail mysteriously.
            CanonLog.w("No interrupt IN endpoint - asynchronous events will be unavailable (M3)")
        }

        return OpenedCamera(
            device = device,
            transport = UsbTransport(channel),
            endpoints = endpoints,
            productName = device.productName,
        )
    }

    data class OpenedCamera(
        val device: UsbDevice,
        val transport: UsbTransport,
        val endpoints: ResolvedEndpoints,
        val productName: String?,
    )

    companion object {
        /**
         * Distinct from the printers' actions on purpose.
         *
         * `DnpUsbPrinter` owns `com.srisarani.fotozenai.USB_PERMISSION` and
         * `ReceiptUsbPrinter` owns `…RECEIPT_USB_PERMISSION`. In this app the camera, the
         * DNP printer and the receipt printer can all be attached to the same hub at the
         * same time, so a shared action string would let one device's permission result
         * satisfy another's pending callback.
         */
        const val ACTION_USB_PERMISSION = "com.srisarani.fotozenai.CANON_USB_PERMISSION"
    }
}

// ------------------------------------------------------------------ adapters

/** Converts Android's interface objects into the testable descriptor model. */
fun UsbDevice.interfaces(): List<InterfaceDescriptor> =
    (0 until interfaceCount).map { index ->
        val iface = getInterface(index)
        InterfaceDescriptor(
            id = iface.id,
            alternateSetting = iface.alternateSetting,
            interfaceClass = iface.interfaceClass,
            interfaceSubclass = iface.interfaceSubclass,
            interfaceProtocol = iface.interfaceProtocol,
            endpoints = (0 until iface.endpointCount).map { epIndex ->
                val ep = iface.getEndpoint(epIndex)
                EndpointDescriptor(
                    address = ep.address,
                    direction = if (ep.direction == UsbConstants.USB_DIR_IN) UsbDirection.IN else UsbDirection.OUT,
                    type = ep.type,
                    maxPacketSize = ep.maxPacketSize,
                )
            },
        )
    }
