package com.srisarani.fotozenai.dnp

import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Locale

/**
 * Low-level ESC/P command transport for DNP DS-series USB printers.
 * Protocol documented in the open-source selphy_print dnpds40 backend.
 */
class DnpCommand(
    private val connection: UsbDeviceConnection,
    private val endpointIn: UsbEndpoint,
    private val endpointOut: UsbEndpoint,
) {
    private val ioLock = Any()

    fun sendCommand(arg1: String, arg2: String, payload: ByteArray? = null) {
        synchronized(ioLock) {
            val header = buildHeader(arg1, arg2, payload?.size ?: 0)
            bulkWrite(header)
            if (payload != null && payload.isNotEmpty()) {
                bulkWrite(payload)
            }
        }
    }

    fun sendResponseCommand(arg1: String, arg2: String): String =
        queryResponse(arg1, arg2) ?: throw DnpPrinterException("USB read failed")

    /** Status polling after large transfers — shorter timeout, returns null on failure. */
    fun queryResponse(arg1: String, arg2: String): String? {
        synchronized(ioLock) {
            return try {
                sendCommandUnlocked(arg1, arg2)
                Thread.sleep(RESPONSE_SETTLE_MS)
                readResponse(STATUS_POLL_TIMEOUT_MS)
            } catch (e: Exception) {
                clearInHalt()
                null
            }
        }
    }

    fun recoverInEndpoint() {
        synchronized(ioLock) {
            clearInHalt()
        }
    }

    fun recoverOutEndpoint() {
        synchronized(ioLock) {
            clearOutHalt()
        }
    }

    fun recoverEndpoints() {
        synchronized(ioLock) {
            clearInHalt()
            clearOutHalt()
        }
    }

    fun sendRaw(data: ByteArray) {
        synchronized(ioLock) {
            bulkWrite(data)
        }
    }

    private fun sendCommandUnlocked(arg1: String, arg2: String, payload: ByteArray? = null) {
        val header = buildHeader(arg1, arg2, payload?.size ?: 0)
        bulkWrite(header)
        if (payload != null && payload.isNotEmpty()) {
            bulkWrite(payload)
        }
    }

    private fun buildHeader(arg1: String, arg2: String, payloadLen: Int): ByteArray {
        val header = ByteArray(32) { SPACE }
        header[0] = ESC
        header[1] = P
        copyPadded(header, 2, arg1, 6)
        copyPadded(header, 8, arg2, 16)
        if (payloadLen > 0) {
            val lenStr = String.format(Locale.US, "%08d", payloadLen)
            lenStr.toByteArray().copyInto(header, 24, 0, minOf(8, lenStr.length))
        }
        return header
    }

    private fun readResponse(timeoutMs: Int = TIMEOUT_MS): String {
        val prefix = bulkReadWithRetry(8, timeoutMs)
        val len = String(prefix, Charsets.US_ASCII).trim().toIntOrNull() ?: 0
        if (len <= 0) return ""
        val body = bulkReadWithRetry(len, timeoutMs)
        return cleanupResponse(String(body, Charsets.US_ASCII))
    }

    private fun cleanupResponse(raw: String): String {
        val crIndex = raw.indexOf('\r')
        val trimmed = if (crIndex >= 0) raw.substring(0, crIndex) else raw
        return trimmed.trim().trimEnd('\r', '\n')
    }

    private fun bulkReadWithRetry(length: Int, timeoutMs: Int = TIMEOUT_MS): ByteArray {
        var lastError: DnpPrinterException? = null
        repeat(READ_RETRIES) { attempt ->
            if (attempt > 0) {
                clearInHalt()
                Thread.sleep(READ_RETRY_DELAY_MS * attempt)
            }
            try {
                return bulkRead(length, timeoutMs)
            } catch (e: DnpPrinterException) {
                lastError = e
            }
        }
        throw lastError ?: DnpPrinterException("USB read failed")
    }

    private fun clearInHalt() {
        try {
            connection.controlTransfer(
                0x02, // USB_TYPE_STANDARD | USB_RECIP_ENDPOINT
                0x01, // CLEAR_FEATURE
                0,
                endpointIn.address,
                null,
                0,
                1000,
            )
        } catch (_: Exception) {
        }
    }

    private fun clearOutHalt() {
        try {
            connection.controlTransfer(
                0x02,
                0x01,
                0,
                endpointOut.address,
                null,
                0,
                1000,
            )
        } catch (_: Exception) {
        }
    }

    private fun bulkWrite(data: ByteArray) {
        if (data.isEmpty()) return
        var offset = 0
        val chunkSize = (endpointOut.maxPacketSize * 64).coerceAtLeast(4096)
        while (offset < data.size) {
            val length = minOf(chunkSize, data.size - offset)
            var written = connection.bulkTransfer(
                endpointOut,
                data,
                offset,
                length,
                TIMEOUT_MS,
            )
            if (written <= 0) {
                clearOutHalt()
                Thread.sleep(WRITE_RETRY_DELAY_MS)
                written = connection.bulkTransfer(
                    endpointOut,
                    data,
                    offset,
                    length,
                    TIMEOUT_MS,
                )
                if (written <= 0) {
                    throw DnpPrinterException("USB write failed at offset $offset")
                }
            }
            offset += written
        }
    }

    private fun bulkRead(length: Int, timeoutMs: Int = TIMEOUT_MS): ByteArray {
        val buffer = ByteArray(length)
        var offset = 0
        while (offset < length) {
            val read = connection.bulkTransfer(
                endpointIn,
                buffer,
                offset,
                length - offset,
                timeoutMs,
            )
            if (read <= 0) {
                throw DnpPrinterException("USB read failed at offset $offset")
            }
            offset += read
        }
        return buffer
    }

    private fun copyPadded(dest: ByteArray, offset: Int, value: String, maxLen: Int) {
        val bytes = value.toByteArray(Charsets.US_ASCII)
        System.arraycopy(bytes, 0, dest, offset, minOf(bytes.size, maxLen))
    }

    companion object {
        private const val ESC: Byte = 0x1B
        private const val P: Byte = 0x50
        private const val SPACE: Byte = 0x20
        private const val TIMEOUT_MS = 30_000
        private const val STATUS_POLL_TIMEOUT_MS = 4_000
        private const val RESPONSE_SETTLE_MS = 80L
        private const val READ_RETRIES = 4
        private const val READ_RETRY_DELAY_MS = 120L
        private const val WRITE_RETRY_DELAY_MS = 150L

        /** Parse numeric DNP response (STATUS, buffer counts, etc.). */
        fun parseIntResponse(raw: String): Int? {
            val cleaned = raw.trim().trimEnd('\r', '\n')
            if (cleaned.isEmpty()) return null
            cleaned.toIntOrNull()?.let { return it }
            cleaned.take(5).trim().toIntOrNull()?.let { return it }
            val match = Regex("(\\d+)").find(cleaned) ?: return null
            return match.groupValues[1].toIntOrNull()
        }

        fun writeLe32(value: Int): ByteArray =
            ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(value).array()
    }
}

class DnpPrinterException(message: String) : Exception(message)
