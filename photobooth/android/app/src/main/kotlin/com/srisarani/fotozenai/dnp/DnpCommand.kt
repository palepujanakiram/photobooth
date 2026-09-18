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

    /**
     * Status polling after large transfers — shorter timeout, one read attempt,
     * returns null on failure.
     *
     * **One attempt, not [READ_RETRIES].** Retrying the *read* cannot recover a
     * status poll, because the thing that fails is the command: on the first poll
     * after a preceding print this printer drops the STATUS it is sent, so there
     * is no response in flight and re-reading finds nothing however many times it
     * asks. Traced on a DS-RX1HS, all four attempts failed at offset 0 across
     * 17.4s — and the very next poll, which sends a *fresh* command, answered in
     * 82ms.
     *
     * So the retry that works is the caller's: [DnpPrintCompletionWaiter] already
     * re-polls every second, and returning null promptly hands it back 17s sooner.
     * That was 71% of the gap between two consecutive prints. The multi-attempt
     * path still guards real data transfers, where a short read genuinely is worth
     * retrying.
     */
    fun queryResponse(arg1: String, arg2: String): String? {
        synchronized(ioLock) {
            return try {
                sendCommandUnlocked(arg1, arg2)
                Thread.sleep(RESPONSE_SETTLE_MS)
                readResponse(STATUS_POLL_TIMEOUT_MS, STATUS_POLL_READ_RETRIES)
            } catch (e: Exception) {
                DnpTrace.log("$arg1 query failed: ${e.javaClass.simpleName} ${e.message}")
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

    private fun readResponse(
        timeoutMs: Int = TIMEOUT_MS,
        retries: Int = READ_RETRIES,
    ): String {
        val prefix = bulkReadWithRetry(8, timeoutMs, retries)
        val len = String(prefix, Charsets.US_ASCII).trim().toIntOrNull() ?: 0
        if (len <= 0) return ""
        val body = bulkReadWithRetry(len, timeoutMs, retries)
        return cleanupResponse(String(body, Charsets.US_ASCII))
    }

    private fun cleanupResponse(raw: String): String {
        val crIndex = raw.indexOf('\r')
        val trimmed = if (crIndex >= 0) raw.substring(0, crIndex) else raw
        return trimmed.trim().trimEnd('\r', '\n')
    }

    private fun bulkReadWithRetry(
        length: Int,
        timeoutMs: Int = TIMEOUT_MS,
        retries: Int = READ_RETRIES,
    ): ByteArray {
        var lastError: DnpPrinterException? = null
        repeat(retries) { attempt ->
            if (attempt > 0) {
                clearInHalt()
                Thread.sleep(READ_RETRY_DELAY_MS * attempt)
            }
            val started = DnpTrace.now()
            try {
                return bulkRead(length, timeoutMs)
            } catch (e: DnpPrinterException) {
                // Each failed attempt burns a full timeout. Four of them stacked is
                // the ~17s that precedes the START retry, so the count and the cost
                // of each need to be visible before deciding how many are useful.
                DnpTrace.log(
                    "bulkRead attempt $attempt/$retries len=$length " +
                        "timeout=${timeoutMs}ms took=${DnpTrace.now() - started}ms: ${e.message}",
                )
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

        /** See [queryResponse]: re-reading cannot recover a dropped STATUS. */
        private const val STATUS_POLL_READ_RETRIES = 1
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
