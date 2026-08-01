package com.srisarani.fotozenai.receipt

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.util.Log
import java.io.File

/**
 * USB ESC/POS thermal receipt printer (Posiflow KP 307 UEWB and compatible
 * USB Printer Class devices). Excludes DNP dye-sub printers (VID 0x1343).
 */
class ReceiptUsbPrinter(
    private val context: Context,
    private val usbManager: UsbManager,
) {
    private var device: UsbDevice? = null
    private var connection: UsbDeviceConnection? = null
    private var usbInterface: UsbInterface? = null
    private var outEndpoint: UsbEndpoint? = null

    val isConnected: Boolean
        get() = connection != null && outEndpoint != null

    fun findDevice(): UsbDevice? =
        usbManager.deviceList.values.firstOrNull { dev ->
            dev.vendorId != DNP_VENDOR_ID && ReceiptUsbInterfaceHelper.hasPrinterInterface(dev)
        }

    fun hasPermission(dev: UsbDevice): Boolean = usbManager.hasPermission(dev)

    fun requestPermission(dev: UsbDevice, onResult: (Boolean) -> Unit) {
        if (usbManager.hasPermission(dev)) {
            onResult(true)
            return
        }
        val intent = PendingIntent.getBroadcast(
            context,
            0,
            Intent(ACTION_USB_PERMISSION),
            PendingIntent.FLAG_IMMUTABLE,
        )
        usbManager.requestPermission(dev, intent)
        pendingPermissionCallback = onResult
        pendingDevice = dev
    }

    fun connect(dev: UsbDevice): String {
        if (!usbManager.hasPermission(dev)) {
            throw ReceiptPrinterException("USB permission not granted")
        }
        if (isConnected && device?.deviceId == dev.deviceId) {
            return displayName(dev)
        }
        disconnect()

        val (intf, outEp) = ReceiptUsbInterfaceHelper.locatePrinterInterface(dev)
        val conn = usbManager.openDevice(dev)
            ?: throw ReceiptPrinterException("Could not open USB receipt printer")

        if (!conn.claimInterface(intf, true)) {
            conn.close()
            throw ReceiptPrinterException("Could not claim USB printer interface")
        }

        device = dev
        connection = conn
        usbInterface = intf
        outEndpoint = outEp

        Thread.sleep(150)
        val name = displayName(dev)
        Log.i(TAG, "Connected to receipt printer: $name")
        return name
    }

    fun writeEscPos(bytes: ByteArray) {
        val conn = connection ?: throw ReceiptPrinterException("Receipt printer not connected")
        val outEp = outEndpoint ?: throw ReceiptPrinterException("Receipt printer not connected")
        ReceiptUsbBulkWriter.write(conn, outEp, bytes)
    }

    fun writeEscPosFile(filePath: String) {
        val file = File(filePath)
        if (!file.isFile) {
            throw ReceiptPrinterException("Receipt payload file not found")
        }
        file.inputStream().use { input ->
            val buffer = ByteArray(4096)
            while (true) {
                val read = input.read(buffer)
                if (read <= 0) break
                writeEscPos(if (read == buffer.size) buffer else buffer.copyOf(read))
            }
        }
    }

    fun disconnect() {
        try {
            usbInterface?.let { connection?.releaseInterface(it) }
        } catch (_: Exception) {
        }
        try {
            connection?.close()
        } catch (_: Exception) {
        }
        device = null
        connection = null
        usbInterface = null
        outEndpoint = null
    }

    private fun displayName(dev: UsbDevice): String {
        val product = dev.productName?.trim().orEmpty()
        if (product.isNotEmpty()) return product
        return "USB receipt printer (${dev.vendorId}:${dev.productId})"
    }

    companion object {
        private const val TAG = "ReceiptUsbPrinter"
        const val ACTION_USB_PERMISSION = "com.srisarani.fotozenai.RECEIPT_USB_PERMISSION"
        private const val DNP_VENDOR_ID = 0x1343

        var pendingPermissionCallback: ((Boolean) -> Unit)? = null
        var pendingDevice: UsbDevice? = null
    }
}

class ReceiptPrinterException(message: String) : Exception(message)
