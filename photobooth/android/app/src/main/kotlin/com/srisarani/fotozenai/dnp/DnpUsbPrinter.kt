package com.srisarani.fotozenai.dnp

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.util.Log

/**
 * USB driver for DNP DS-RX1 / DS-RX1HS (VID 0x1343, PID 0x0005).
 */
class DnpUsbPrinter(
    private val context: Context,
    private val usbManager: UsbManager,
) {
    private var device: UsbDevice? = null
    private var connection: UsbDeviceConnection? = null
    private var usbInterface: UsbInterface? = null
    private var command: DnpCommand? = null
    private var printerName: String = "DNP DS-RX1"

    val isConnected: Boolean
        get() = connection != null && command != null

    fun findDevice(): UsbDevice? =
        usbManager.deviceList.values.firstOrNull { dev ->
            dev.vendorId == DNP_VENDOR_ID &&
                (dev.productId == DNP_PRODUCT_ID_RX1 || dev.productId == DNP_PRODUCT_ID_RX1_ALT)
        }

    fun hasPermission(dev: UsbDevice): Boolean =
        usbManager.hasPermission(dev)

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
        // MainActivity handles the broadcast; store callback via companion for simplicity.
        pendingPermissionCallback = onResult
        pendingDevice = dev
    }

    fun connect(dev: UsbDevice): String {
        if (!usbManager.hasPermission(dev)) {
            throw DnpPrinterException("USB permission not granted")
        }

        val (intf, inEp, outEp) = locateEndpoints(dev)
        val conn = usbManager.openDevice(dev)
            ?: throw DnpPrinterException("Could not open USB device")

        if (!conn.claimInterface(intf, true)) {
            conn.close()
            throw DnpPrinterException("Could not claim USB interface")
        }

        device = dev
        connection = conn
        usbInterface = intf
        command = DnpCommand(conn, inEp, outEp)

        // Allow the printer USB stack to settle (important on Android TV hosts).
        Thread.sleep(200)
        val version = queryFirmwareVersion()
        printerName = if (version.contains("2.")) "DNP DS-RX1HS" else "DNP DS-RX1"
        Log.i(TAG, "Connected to $printerName (FW $version)")
        return "$printerName (FW $version)"
    }

    val displayName: String
        get() = printerName

    /** Query live printer STATUS code (0=idle, 1=printing, 1000+=error). */
    fun queryLiveStatus(): Int {
        val cmd = command ?: throw DnpPrinterException("Printer not connected")
        repeat(STATUS_QUERY_RETRIES) { attempt ->
            if (attempt > 0) Thread.sleep(200L * attempt)
            try {
                val raw = cmd.sendResponseCommand("STATUS", "")
                DnpCommand.parseIntResponse(raw)?.let { return it }
                Log.w(TAG, "Unparsed STATUS response (attempt ${attempt + 1}): '$raw'")
            } catch (e: Exception) {
                Log.w(TAG, "STATUS query failed (attempt ${attempt + 1}): ${e.message}")
            }
        }
        return -1
    }

    fun statusLabel(code: Int): String = when (code) {
        -1 -> "Connected — status unreadable"
        0 -> "Idle"
        1 -> "Printing"
        500 -> "Cooling print head"
        510 -> "Cooling paper motor"
        900 -> "Standby"
        else -> printerStatusMessage(code)
    }

    /** Unknown status (-1) still allows print — USB link is up; status query may fail on some TV hosts. */
    fun isReadyStatus(code: Int): Boolean = code == 0 || code == 1 || code == -1

    fun disconnect() {
        try {
            usbInterface?.let { connection?.releaseInterface(it) }
        } catch (_: Exception) {
        }
        connection?.close()
        device = null
        connection = null
        usbInterface = null
        command = null
    }

    fun print(
        bitmapPixels: IntArray,
        width: Int,
        height: Int,
        size: DnpPrintSize,
        copies: Int,
        matte: Boolean,
        onProgress: PrintProgressCallback? = null,
    ) {
        val cmd = command ?: throw DnpPrinterException("Printer not connected")
        val report: PrintProgressCallback = { stage, message, progress ->
            onProgress?.invoke(stage, message, progress)
        }

        report("wait_ready", "Checking printer is ready…", 0.25)
        waitUntilReady(cmd, report)

        report("convert", "Building print data…", 0.28)
        val (y, m, c) = DnpPrintJobBuilder.rgbToPlanes(bitmapPixels, width, height)
        val jobData = DnpPrintJobBuilder.buildJob(y, m, c, width, height)

        report("send_settings", "Sending print settings…", 0.32)
        cmd.recoverEndpoints()
        sendPrintSetup(cmd, copies, size, matte)

        report("send_data", "Sending image data…", 0.35)
        sendJobChunks(cmd, jobData, report)

        // Reference driver sleeps 1s after the job stream before polling STATUS.
        Thread.sleep(1000)
        cmd.recoverEndpoints()
        report("printing", "Print job started — waiting for printer…", 0.90)
        waitForPrintComplete(cmd, report)
    }

    /** Send CNTRL START as a standalone command (32-byte ESC/P header). */
    private fun sendStartCommand(cmd: DnpCommand) {
        cmd.sendCommand("CNTRL", "START", null)
    }

    private fun sendPrintSetup(cmd: DnpCommand, copies: Int, size: DnpPrintSize, matte: Boolean) {
        cmd.sendCommand("CNTRL", "QTY", String.format("%07d\r", copies).toByteArray())

        cmd.sendCommand("CNTRL", "BUFFCNTRL", "00000001".toByteArray())

        val overcoat = if (matte) "00000001" else "00000000"
        cmd.sendCommand("CNTRL", "OVERCOAT", overcoat.toByteArray())

        if (size.usesStripCutter) {
            cmd.sendCommand("CNTRL", "CUTTER", "00000120".toByteArray())
        }

        val multicut = String.format("%08d", size.multicut)
        cmd.sendCommand("IMAGE", "MULTICUT", multicut.toByteArray())
    }

    private fun sendJobChunks(cmd: DnpCommand, jobData: ByteArray, onProgress: PrintProgressCallback) {
        var offset = 0
        val total = jobData.size.coerceAtLeast(1)
        var lastReportedPct = -1
        while (offset < jobData.size) {
            if (offset + 32 > jobData.size) {
                cmd.sendRaw(jobData.copyOfRange(offset, jobData.size))
                break
            }
            if (isStartChunk(jobData, offset)) {
                cmd.sendRaw(jobData.copyOfRange(offset, offset + 32))
                offset += 32
                break
            }
            val lenStr = String(jobData, offset + 24, 8, Charsets.US_ASCII).trim()
            val payloadLen = lenStr.toIntOrNull()
            if (payloadLen == null || payloadLen <= 0) {
                cmd.sendRaw(jobData.copyOfRange(offset, jobData.size))
                break
            }
            val chunkLen = payloadLen + 32
            if (offset + chunkLen > jobData.size) {
                cmd.sendRaw(jobData.copyOfRange(offset, jobData.size))
                break
            }
            cmd.sendRaw(jobData.copyOfRange(offset, offset + chunkLen))
            offset += chunkLen
            val fraction = offset.toDouble() / total
            val pct = (fraction * 100).toInt().coerceIn(0, 100)
            if (pct - lastReportedPct >= 5 || pct >= 100) {
                lastReportedPct = pct
                onProgress(
                    "send_data",
                    "Sending image data ($pct%)…",
                    0.35 + fraction * 0.50,
                )
            }
        }
        Thread.sleep(500)
    }

    /** Legacy stream terminator — not a standard 32-byte IMAGE/CNTRL block. */
    private fun isStartChunk(jobData: ByteArray, offset: Int): Boolean {
        if (offset + 13 > jobData.size) return false
        if (jobData[offset] != 0x1B.toByte() || jobData[offset + 1] != 0x50.toByte()) return false
        val tag = String(jobData, offset + 2, 11, Charsets.US_ASCII)
        return tag == "CNTRL START"
    }

    private fun parseStatus(cmd: DnpCommand, raw: String? = null): Int {
        if (raw != null) {
            return DnpCommand.parseIntResponse(raw) ?: -1
        }
        val response = cmd.queryResponse("STATUS", "") ?: return -1
        return DnpCommand.parseIntResponse(response) ?: -1
    }

    private fun waitUntilReady(cmd: DnpCommand, onProgress: PrintProgressCallback) {
        var lastReportedMessage: String? = null
        var unreadableStatusCount = 0
        repeat(MAX_STATUS_RETRIES) {
            val status = parseStatus(cmd)
            when (status) {
                0, 1 -> {
                    val buffers = cmd.sendResponseCommand("INFO", "FREE_PBUFFER")
                    val available = parseFreeBufferCount(buffers)
                    if (available >= 1 || (available < 0 && status == 0)) {
                        onProgress("wait_ready", "Printer ready", 0.30)
                        return
                    }
                    val msg = "Waiting for printer buffer…"
                    if (msg != lastReportedMessage) {
                        lastReportedMessage = msg
                        onProgress("wait_ready", msg, null)
                    }
                }
                -1 -> {
                    unreadableStatusCount++
                    if (unreadableStatusCount >= 5) {
                        onProgress(
                            "wait_ready",
                            "Proceeding — status check limited on this USB host",
                            0.30,
                        )
                        return
                    }
                    val msg = "Reading printer status…"
                    if (msg != lastReportedMessage) {
                        lastReportedMessage = msg
                        onProgress("wait_ready", msg, null)
                    }
                }
                500, 510, 900 -> {
                    val msg = statusLabel(status)
                    if (msg != lastReportedMessage) {
                        lastReportedMessage = msg
                        onProgress("wait_ready", msg, null)
                    }
                }
                1000, 1010, 1100, 1200, 1300, 1400 ->
                    throw DnpPrinterException(printerStatusMessage(status))
                else -> throw DnpPrinterException("Printer error: $status")
            }
            Thread.sleep(1000)
        }
        throw DnpPrinterException("Printer not ready (timeout)")
    }

    private fun waitForPrintComplete(cmd: DnpCommand, onProgress: PrintProgressCallback) {
        var lastReportedLabel: String? = null
        var unreadableStatusCount = 0
        var sawPrinterActive = false
        var startRetried = false
        repeat(MAX_STATUS_RETRIES) { attempt ->
            val status = parseStatus(cmd)
            Log.d(TAG, "Print wait poll $attempt: status=$status (active=$sawPrinterActive)")
            if (status == 1 || status == 500 || status == 510) {
                sawPrinterActive = true
                unreadableStatusCount = 0
            }
            if (status == 0 && sawPrinterActive) {
                onProgress("complete", "Print finished", 1.0)
                return
            }
            if (status == 0 && !sawPrinterActive && attempt >= MIN_START_POLLS && !startRetried) {
                Log.w(TAG, "Printer still idle after job send; retrying CNTRL START")
                startRetried = true
                try {
                    sendStartCommand(cmd)
                    Thread.sleep(1000)
                } catch (e: Exception) {
                    Log.w(TAG, "CNTRL START retry failed: ${e.message}")
                }
            } else if (status == 0 && !sawPrinterActive && startRetried &&
                attempt >= MIN_START_POLLS + START_RETRY_GRACE_POLLS
            ) {
                throw DnpPrinterException(
                    "Print did not start — check media is loaded and printer is ready",
                )
            }
            if (status >= 1000) {
                throw DnpPrinterException(printerStatusMessage(status))
            }
            if (status == -1) {
                unreadableStatusCount++
                if (unreadableStatusCount >= UNREADABLE_STATUS_COMPLETE) {
                    onProgress("complete", "Print sent — check printer output", 1.0)
                    return
                }
                val msg = "Waiting for printer (status check limited)…"
                if (msg != lastReportedLabel || attempt == 0) {
                    lastReportedLabel = msg
                    val fraction = 0.90 + (attempt.toDouble() / MAX_STATUS_RETRIES) * 0.09
                    onProgress("printing", msg, fraction.coerceAtMost(0.99))
                }
            } else if (status != 0) {
                unreadableStatusCount = 0
                val label = statusLabel(status)
                if (label != lastReportedLabel || attempt == 0) {
                    lastReportedLabel = label
                    val fraction = 0.90 + (attempt.toDouble() / MAX_STATUS_RETRIES) * 0.09
                    onProgress("printing", label, fraction.coerceAtMost(0.99))
                }
            }
            Thread.sleep(1000)
        }
        throw DnpPrinterException("Print timed out")
    }

    /** Parse FREE_PBUFFER response (reference driver skips first 3 chars). */
    private fun parseFreeBufferCount(raw: String): Int {
        DnpCommand.parseIntResponse(raw.drop(3))?.let { return it }
        DnpCommand.parseIntResponse(raw)?.let { return it }
        return -1
    }

    private fun queryFirmwareVersion(): String =
        try {
            command?.sendResponseCommand("INFO", "FVER") ?: "unknown"
        } catch (_: Exception) {
            "unknown"
        }

    private fun locateEndpoints(dev: UsbDevice): Triple<UsbInterface, android.hardware.usb.UsbEndpoint, android.hardware.usb.UsbEndpoint> {
        var fallback: Triple<UsbInterface, android.hardware.usb.UsbEndpoint, android.hardware.usb.UsbEndpoint>? = null
        for (i in 0 until dev.interfaceCount) {
            val intf = dev.getInterface(i)
            var inEp: android.hardware.usb.UsbEndpoint? = null
            var outEp: android.hardware.usb.UsbEndpoint? = null
            for (j in 0 until intf.endpointCount) {
                val ep = intf.getEndpoint(j)
                if (ep.type != UsbConstants.USB_ENDPOINT_XFER_BULK) continue
                if (ep.direction == UsbConstants.USB_DIR_IN) inEp = ep
                else outEp = ep
            }
            if (inEp != null && outEp != null) {
                val candidate = Triple(intf, inEp, outEp)
                if (intf.interfaceClass == UsbConstants.USB_CLASS_PRINTER || i == 0) {
                    Log.i(TAG, "Using USB interface $i (class ${intf.interfaceClass})")
                    return candidate
                }
                if (fallback == null) fallback = candidate
            }
        }
        if (fallback != null) {
            Log.i(TAG, "Using fallback USB interface (class ${fallback.first.interfaceClass})")
            return fallback
        }
        throw DnpPrinterException("No bulk USB endpoints found")
    }

    private fun printerStatusMessage(code: Int): String = when (code) {
        1000 -> "Cover open"
        1010 -> "Scrap box missing"
        1100 -> "Paper end — load new media"
        1200 -> "Ribbon end — replace ribbon"
        1300 -> "Paper jam"
        1400 -> "Ribbon error"
        1500 -> "Paper size mismatch — check loaded media"
        1600 -> "Print data error — check image size and print settings"
        else -> "Printer error ($code)"
    }

    companion object {
        const val ACTION_USB_PERMISSION = "com.srisarani.fotozenai.USB_PERMISSION"
        private const val TAG = "DnpUsbPrinter"
        private const val DNP_VENDOR_ID = 0x1343
        private const val DNP_PRODUCT_ID_RX1 = 0x0005
        private const val DNP_PRODUCT_ID_RX1_ALT = 0x0005
        private const val MAX_STATUS_RETRIES = 120
        private const val STATUS_QUERY_RETRIES = 4
        private const val UNREADABLE_STATUS_COMPLETE = 8
        /** Ignore idle STATUS until the printer has had time to accept START. */
        private const val MIN_START_POLLS = 3
        /** Extra polls after CNTRL START retry before reporting failure. */
        private const val START_RETRY_GRACE_POLLS = 10

        @Volatile
        var pendingPermissionCallback: ((Boolean) -> Unit)? = null

        @Volatile
        var pendingDevice: UsbDevice? = null
    }
}
