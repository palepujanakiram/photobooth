package com.srisarani.fotozenai.dnp

import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.util.Log

/** Picks bulk IN/OUT endpoints on a DNP USB printer. */
internal object DnpUsbEndpointLocator {
    private const val TAG = "DnpUsbPrinter"

    fun locate(dev: UsbDevice): Triple<UsbInterface, UsbEndpoint, UsbEndpoint> {
        var fallback: Triple<UsbInterface, UsbEndpoint, UsbEndpoint>? = null
        for (i in 0 until dev.interfaceCount) {
            val candidate = bulkPair(dev.getInterface(i)) ?: continue
            if (isPreferred(candidate.first, i)) {
                Log.i(TAG, "Using USB interface $i (class ${candidate.first.interfaceClass})")
                return candidate
            }
            if (fallback == null) {
                fallback = candidate
            }
        }
        val chosen = fallback ?: throw DnpPrinterException("No bulk USB endpoints found")
        Log.i(TAG, "Using fallback USB interface (class ${chosen.first.interfaceClass})")
        return chosen
    }

    private fun isPreferred(
        intf: UsbInterface,
        index: Int,
    ): Boolean = intf.interfaceClass == UsbConstants.USB_CLASS_PRINTER || index == 0

    private fun bulkPair(intf: UsbInterface): Triple<UsbInterface, UsbEndpoint, UsbEndpoint>? {
        var inEp: UsbEndpoint? = null
        var outEp: UsbEndpoint? = null
        for (j in 0 until intf.endpointCount) {
            val ep = intf.getEndpoint(j)
            if (ep.type != UsbConstants.USB_ENDPOINT_XFER_BULK) {
                continue
            }
            if (ep.direction == UsbConstants.USB_DIR_IN) {
                inEp = ep
            } else {
                outEp = ep
            }
        }
        val foundIn = inEp ?: return null
        val foundOut = outEp ?: return null
        return Triple(intf, foundIn, foundOut)
    }
}
