package com.srisarani.fotozenai.receipt

import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface

internal object ReceiptUsbInterfaceHelper {
    fun hasPrinterInterface(dev: UsbDevice): Boolean {
        for (index in 0 until dev.interfaceCount) {
            if (dev.getInterface(index).interfaceClass == UsbConstants.USB_CLASS_PRINTER) {
                return true
            }
        }
        return false
    }

    fun locatePrinterInterface(dev: UsbDevice): Pair<UsbInterface, UsbEndpoint> {
        for (index in 0 until dev.interfaceCount) {
            val intf = dev.getInterface(index)
            if (intf.interfaceClass != UsbConstants.USB_CLASS_PRINTER) continue
            val outEp = findBulkOutEndpoint(intf) ?: continue
            return intf to outEp
        }
        throw ReceiptPrinterException("No USB printer bulk OUT endpoint found")
    }

    private fun findBulkOutEndpoint(intf: UsbInterface): UsbEndpoint? {
        for (epIndex in 0 until intf.endpointCount) {
            val ep = intf.getEndpoint(epIndex)
            if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK &&
                ep.direction == UsbConstants.USB_DIR_OUT
            ) {
                return ep
            }
        }
        return null
    }
}
