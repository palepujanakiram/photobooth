package com.srisarani.fotozenai.receipt

import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint

internal object ReceiptUsbBulkWriter {
    private const val WRITE_TIMEOUT_MS = 30_000

    fun write(
        connection: UsbDeviceConnection,
        outEndpoint: UsbEndpoint,
        bytes: ByteArray,
    ) {
        val chunkSize = outEndpoint.maxPacketSize.coerceIn(64, 4096)
        var offset = 0
        while (offset < bytes.size) {
            val end = minOf(offset + chunkSize, bytes.size)
            writeChunk(connection, outEndpoint, bytes, offset, end)
            offset = end
        }
    }

    private fun writeChunk(
        connection: UsbDeviceConnection,
        outEndpoint: UsbEndpoint,
        bytes: ByteArray,
        offset: Int,
        end: Int,
    ) {
        var chunkOffset = offset
        while (chunkOffset < end) {
            val written = connection.bulkTransfer(
                outEndpoint,
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
    }
}
