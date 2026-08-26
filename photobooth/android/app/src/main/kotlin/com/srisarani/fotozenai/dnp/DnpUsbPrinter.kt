package com.srisarani.fotozenai.dnp

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.Build
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

    fun hasPermission(dev: UsbDevice): Boolean = usbManager.hasPermission(dev)

    /**
     * Shows the Android USB allow dialog and reports the answer.
     *
     * ## The PendingIntent must stay mutable
     *
     * [UsbManager.requestPermission] returns its answer by filling
     * [UsbManager.EXTRA_PERMISSION_GRANTED] and [UsbManager.EXTRA_DEVICE] into this
     * PendingIntent. `FLAG_IMMUTABLE` drops that fill-in, so the receiver read a missing
     * extra and defaulted to `false` — the guest tapped **Allow** and the app still
     * reported `PERMISSION_DENIED`.
     *
     * It only bit when the dialog was actually needed. `device_filter.xml` covers this
     * printer, so a plug-in with "always open for this device" ticked grants at attach and
     * [hasPermission] short-circuits above. After a replug, power cycle, reboot or app
     * reinstall the grant is gone, the dialog runs, and printing failed — which is why it
     * read as intermittent rather than broken. Staff reprint uses this same path.
     *
     * `FLAG_MUTABLE` only exists from S; below that the default is already mutable.
     */
    fun requestPermission(
        dev: UsbDevice,
        onResult: (Boolean) -> Unit,
    ) {
        if (usbManager.hasPermission(dev)) {
            Log.i(TAG, "USB permission already held for ${describe(dev)}")
            onResult(true)
            return
        }
        Log.i(TAG, "Requesting USB permission for ${describe(dev)} - showing allow dialog")
        val flags =
            PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
        val intent =
            PendingIntent.getBroadcast(
                context,
                0,
                Intent(ACTION_USB_PERMISSION).setPackage(context.packageName),
                flags,
            )
        usbManager.requestPermission(dev, intent)
        // MainActivity handles the broadcast; store callback via companion for simplicity.
        pendingPermissionCallback = onResult
        pendingDevice = dev
    }

    /** Stable one-line device identity for logs (no PII; ids are USB-assigned). */
    fun describe(dev: UsbDevice): String =
        "vid=0x%04X pid=0x%04X %s".format(dev.vendorId, dev.productId, dev.deviceName)

    /**
     * Everything currently on the USB bus, for the "no printer found" log.
     *
     * Whether the printer was absent, or present under an unexpected product id, or the
     * whole bus dropped, are three different faults that all surface as `NO_PRINTER`.
     * Without this the log cannot tell them apart after the fact.
     */
    fun describeAttachedDevices(): String =
        usbManager.deviceList.values
            .joinToString(", ") { describe(it) }
            .ifEmpty { "<none>" }

    fun connect(dev: UsbDevice): String {
        if (!usbManager.hasPermission(dev)) {
            throw DnpPrinterException("USB permission not granted")
        }

        // Always reclaim the interface. After guest checkout the native claim is
        // often left open; Staff reprints hours later would otherwise no-op on a
        // stale pipe and fail with "USB write failed at offset 0".
        disconnect()

        val (intf, inEp, outEp) = DnpUsbEndpointLocator.locate(dev)
        val conn =
            usbManager.openDevice(dev)
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

    fun statusLabel(code: Int): String =
        when (code) {
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
        } catch (e: Exception) {
            Log.w(TAG, "releaseInterface: ${e.message}")
        }
        connection?.close()
        device = null
        connection = null
        usbInterface = null
        command = null
    }

    fun print(
        job: DnpPrintJob,
        onProgress: PrintProgressCallback? = null,
    ) {
        val cmd = command ?: throw DnpPrinterException("Printer not connected")
        val report: PrintProgressCallback = { stage, message, progress ->
            onProgress?.invoke(stage, message, progress)
        }
        val monitor =
            DnpPrintStatusMonitor(
                cmd = cmd,
                onProgress = report,
                statusLabel = ::statusLabel,
                errorMessage = ::printerStatusMessage,
                sendStartCommand = { sendStartCommand(cmd) },
            )

        report("wait_ready", "Checking printer is ready…", 0.25)
        monitor.waitUntilReady()

        report("convert", "Building print data…", 0.28)
        val image = job.image
        val (y, m, c) = DnpPrintJobBuilder.rgbToPlanes(image.pixels, image.width, image.height)
        val jobData = DnpPrintJobBuilder.buildJob(y, m, c, image.width, image.height)

        report("send_settings", "Sending print settings…", 0.32)
        cmd.recoverEndpoints()
        sendPrintSetup(cmd, job.copies, job.size, job.matte)

        report("send_data", "Sending image data…", 0.35)
        sendJobChunks(cmd, jobData, report)

        // Reference driver sleeps 1s after the job stream before polling STATUS.
        Thread.sleep(1000)
        cmd.recoverEndpoints()
        report("printing", "Print job started — waiting for printer…", 0.90)
        monitor.waitForPrintComplete()
    }

    /** Send CNTRL START as a standalone command (32-byte ESC/P header). */
    private fun sendStartCommand(cmd: DnpCommand) {
        cmd.sendCommand("CNTRL", "START", null)
    }

    private fun sendPrintSetup(
        cmd: DnpCommand,
        copies: Int,
        size: DnpPrintSize,
        matte: Boolean,
    ) {
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

    private fun sendJobChunks(
        cmd: DnpCommand,
        jobData: ByteArray,
        onProgress: PrintProgressCallback,
    ) {
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
    private fun isStartChunk(
        jobData: ByteArray,
        offset: Int,
    ): Boolean {
        if (offset + 13 > jobData.size) return false
        if (jobData[offset] != 0x1B.toByte() || jobData[offset + 1] != 0x50.toByte()) return false
        val tag = String(jobData, offset + 2, 11, Charsets.US_ASCII)
        return tag == "CNTRL START"
    }

    private fun queryFirmwareVersion(): String =
        try {
            command?.sendResponseCommand("INFO", "FVER") ?: "unknown"
        } catch (_: Exception) {
            "unknown"
        }

    private fun printerStatusMessage(code: Int): String =
        when (code) {
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
        private const val STATUS_QUERY_RETRIES = 4

        @Volatile
        var pendingPermissionCallback: ((Boolean) -> Unit)? = null

        @Volatile
        var pendingDevice: UsbDevice? = null
    }
}
