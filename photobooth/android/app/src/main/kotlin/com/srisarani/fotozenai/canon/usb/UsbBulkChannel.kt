package com.srisarani.fotozenai.canon.usb

import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import com.srisarani.fotozenai.canon.CanonLog
import java.io.Closeable

/**
 * The single hardware seam in the USB layer.
 *
 * Everything above this interface - short-packet assembly, ZLP handling (P-01), chunking
 * (P-06), stale-data draining (P-02) - is pure logic and is unit tested against a fake.
 * That matters because those are exactly the behaviours that are miserable to debug on
 * real hardware and trivial to verify against a simulator.
 */
interface UsbBulkChannel : Closeable {

    /** Max packet size of the bulk IN endpoint. Drives short-packet and ZLP logic. */
    val bulkInMaxPacketSize: Int

    /** One bulk OUT transfer. Returns bytes written, or negative on failure. */
    fun bulkOut(data: ByteArray, offset: Int, length: Int, timeoutMs: Int): Int

    /** One bulk IN transfer. Returns bytes read (0 = zero-length packet), or negative on failure. */
    fun bulkIn(buffer: ByteArray, offset: Int, length: Int, timeoutMs: Int): Int

    /** One interrupt IN transfer. Returns bytes read, or negative. */
    fun interruptIn(buffer: ByteArray, offset: Int, length: Int, timeoutMs: Int): Int

    /** True once the underlying device is gone or the channel has been closed. */
    val isOpen: Boolean

    /**
     * Clears a stalled (halted) endpoint.
     *
     * ## Why this is needed (`U-06`, hit repeatedly during M5 development)
     *
     * If the app dies without closing the PTP session — a crash, or `am force-stop` during
     * development — the camera is left mid-transaction. On the next connect the interface
     * claims successfully and then **every `bulkTransfer` returns -1**, because the
     * endpoint is halted. It looks like a dead cable or a broken camera, and the usual
     * "fix" is power-cycling the body.
     *
     * A USB `CLEAR_FEATURE(ENDPOINT_HALT)` control request resets the endpoint's data
     * toggle and clears the stall, recovering without touching the camera. That matters a
     * great deal for a kiosk, where power-cycling means a site visit.
     *
     * @return true if both endpoints were cleared.
     */
    fun clearStall(): Boolean
}

/**
 * Real Android implementation.
 *
 * Deliberately thin: it does nothing but forward to [UsbDeviceConnection.bulkTransfer] and
 * release the interface on close. Any logic added here is logic that cannot be tested.
 *
 * Note on `bulkTransfer` with an offset: available since API 18, and we are minSdk 26,
 * so the offset overload is always safe.
 */
class AndroidUsbBulkChannel(
    private val connection: UsbDeviceConnection,
    private val usbInterface: UsbInterface,
    private val endpointOut: UsbEndpoint,
    private val endpointIn: UsbEndpoint,
    private val endpointInterrupt: UsbEndpoint?,
) : UsbBulkChannel {

    @Volatile
    private var closed = false

    override val bulkInMaxPacketSize: Int = endpointIn.maxPacketSize

    override val isOpen: Boolean get() = !closed

    override fun bulkOut(data: ByteArray, offset: Int, length: Int, timeoutMs: Int): Int {
        if (closed) throw UsbError.Closed()
        return connection.bulkTransfer(endpointOut, data, offset, length, timeoutMs)
    }

    override fun bulkIn(buffer: ByteArray, offset: Int, length: Int, timeoutMs: Int): Int {
        if (closed) throw UsbError.Closed()
        return connection.bulkTransfer(endpointIn, buffer, offset, length, timeoutMs)
    }

    override fun interruptIn(buffer: ByteArray, offset: Int, length: Int, timeoutMs: Int): Int {
        if (closed) throw UsbError.Closed()
        val endpoint = endpointInterrupt ?: return -1
        return connection.bulkTransfer(endpoint, buffer, offset, length, timeoutMs)
    }

    /**
     * Sends `CLEAR_FEATURE(ENDPOINT_HALT)` to both bulk endpoints.
     *
     * Standard USB control request:
     * ```
     * bmRequestType 0x02  host-to-device, standard, recipient = endpoint
     * bRequest      0x01  CLEAR_FEATURE
     * wValue        0x00  ENDPOINT_HALT
     * wIndex        endpoint address
     * ```
     */
    override fun clearStall(): Boolean {
        if (closed) return false

        fun clear(address: Int): Boolean {
            val result = connection.controlTransfer(
                /* requestType = */ 0x02,
                /* request = */ 0x01,
                /* value = */ 0x00,
                /* index = */ address,
                /* buffer = */ null,
                /* length = */ 0,
                /* timeout = */ CONTROL_TIMEOUT_MS,
            )
            if (result < 0) CanonLog.w("CLEAR_FEATURE(HALT) failed for endpoint 0x%02X", address)
            return result >= 0
        }

        val inCleared = clear(endpointIn.address)
        val outCleared = clear(endpointOut.address)
        CanonLog.i("Endpoint stall clear: in=%b out=%b", inCleared, outCleared)
        return inCleared && outCleared
    }

    /**
     * Release everything, in order, swallowing nothing silently.
     *
     * Getting this wrong produces U-11: works for N reconnect cycles, then stops, because
     * file descriptors leak. Both calls are attempted even if the first throws.
     */
    override fun close() {
        if (closed) return
        closed = true
        runCatching { connection.releaseInterface(usbInterface) }
            .onFailure { CanonLog.w(it, "releaseInterface failed") }
        runCatching { connection.close() }
            .onFailure { CanonLog.w(it, "connection.close failed") }
        CanonLog.i("USB channel closed and interface released")
    }

    private companion object {
        const val CONTROL_TIMEOUT_MS = 1_000
    }
}
