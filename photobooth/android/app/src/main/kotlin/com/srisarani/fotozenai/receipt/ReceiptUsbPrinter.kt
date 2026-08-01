package com.srisarani.fotozenai.receipt

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.util.Log

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
            dev.vendorId != DNP_VENDOR_ID && hasPrinterInterface(dev)
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

        val (intf, outEp) = locatePrinterInterface(dev)
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
        val chunkSize = outEp.maxPacketSize.coerceIn(64, 4096)
        var offset = 0
        while (offset < bytes.size) {
            val end = minOf(offset + chunkSize, bytes.size)
            var chunkOffset = offset
            while (chunkOffset < end) {
                val written = conn.bulkTransfer(
                    outEp,
                    bytes,
                    chunkOffset,
                    end - chunkOffset,
                    WRITE_TIMEOUT_MS,
                )
                if (written <= 0) {
                    throw ReceiptPrinterException("USB write failed (code $written)")
                }
                chunkOffset += written
            }
            offset = end
        }
    }

    fun writeEscPosFile(filePath: String) {
        val file = java.io.File(filePath)
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

    private fun hasPrinterInterface(dev: UsbDevice): Boolean {
        for (index in 0 until dev.interfaceCount) {
            if (dev.getInterface(index).interfaceClass == UsbConstants.USB_CLASS_PRINTER) {
                return true
            }
        }
        return false
    }

    private fun locatePrinterInterface(dev: UsbDevice): Pair<UsbInterface, UsbEndpoint> {
        for (index in 0 until dev.interfaceCount) {
            val intf = dev.getInterface(index)
            if (intf.interfaceClass != UsbConstants.USB_CLASS_PRINTER) continue
            var outEp: UsbEndpoint? = null
            for (epIndex in 0 until intf.endpointCount) {
                val ep = intf.getEndpoint(epIndex)
                if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK &&
                    ep.direction == UsbConstants.USB_DIR_OUT
                ) {
                    outEp = ep
                    break
                }
            }
            if (outEp != null) return intf to outEp
        }
        throw ReceiptPrinterException("No USB printer bulk OUT endpoint found")
    }

    companion object {
        private const val TAG = "ReceiptUsbPrinter"
        const val ACTION_USB_PERMISSION = "com.srisarani.fotozenai.RECEIPT_USB_PERMISSION"
        private const val DNP_VENDOR_ID = 0x1343
        private const val WRITE_TIMEOUT_MS = 30_000

        var pendingPermissionCallback: ((Boolean) -> Unit)? = null
        var pendingDevice: UsbDevice? = null
    }
}

class ReceiptPrinterException(message: String) : Exception(message)
