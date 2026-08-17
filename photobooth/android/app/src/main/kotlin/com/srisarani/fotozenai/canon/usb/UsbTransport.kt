package com.srisarani.fotozenai.canon.usb

import com.srisarani.fotozenai.canon.CanonLog
import java.io.Closeable
import kotlin.math.min

/**
 * Byte-level USB transport for PTP.
 *
 * Responsibilities stop at bytes: chunking, short-packet assembly, zero-length-packet
 * handling and draining. It knows nothing about PTP containers - that is M2. The split
 * matters because everything in this class is testable against a fake channel, whereas
 * container semantics need the camera to be interesting.
 *
 * ## The zero-length packet (P-01)
 *
 * This is the single most important thing in this file, and the most common first-week
 * bug in the whole project.
 *
 * A USB bulk transfer ends when the device sends a packet *shorter* than the endpoint's
 * max packet size. When the payload happens to be an exact multiple of the max packet
 * size, there is no short packet to end it - so the device sends a **zero-length packet**
 * instead. Consume it and everything is fine. Miss it, and it is still sitting in the
 * endpoint when you issue your next read, so that read returns 0 bytes and every
 * subsequent read is offset by one transfer. The symptom is a garbage response code
 * followed by InvalidTransactionID forever, in parsing code that is completely correct.
 *
 * Two defences here, deliberately belt-and-braces:
 *
 * 1. [readTransfer] terminates on any packet shorter than max, **including a 0-byte one**.
 *    A ZLP is just the degenerate short packet, so the natural loop handles it.
 * 2. When reading a known length that is an exact multiple of the packet size, we issue
 *    one extra short-timeout read to drain a possibly-pending ZLP ([consumePendingZlp]).
 *    Some host stacks swallow it, some do not; this makes us correct either way.
 */
class UsbTransport(
    private val channel: UsbBulkChannel,
    private val config: Config = Config(),
) : Closeable {

    data class Config(
        /**
         * Per-read timeout. Short enough that a wedged endpoint is noticed, long enough
         * to survive a camera thinking about a big object. M4 tunes this per-operation.
         */
        val readTimeoutMs: Int = 5_000,
        val writeTimeoutMs: Int = 5_000,
        /**
         * Timeout for the speculative ZLP drain. Deliberately tiny: if no ZLP is pending
         * we pay this on every aligned transfer, so it must not be expensive.
         */
        val zlpTimeoutMs: Int = 50,
        /**
         * Max bytes per bulkTransfer call. Large single transfers are unreliable across
         * devices and kernels (P-06). Always aligned down to a packet multiple.
         */
        val chunkSize: Int = 16 * 1024,
        /** Guard against a runaway device on an unbounded read. */
        val maxTransferBytes: Int = 64 * 1024 * 1024,
    )

    enum class Termination {
        /** A packet shorter than max arrived. The normal end of a transfer. */
        SHORT_PACKET,

        /** A zero-length packet arrived. Normal when the payload is packet-aligned. */
        ZERO_LENGTH_PACKET,

        /** We read exactly the length we were told to expect. */
        LENGTH_REACHED,

        /** Hit the caller's ceiling without the device ending the transfer. Suspicious. */
        LIMIT_REACHED,
    }

    class TransferResult(
        val data: ByteArray,
        val packetsRead: Int,
        val terminatedBy: Termination,
    ) {
        val size: Int get() = data.size
        override fun toString(): String = "TransferResult(${data.size}B, $packetsRead pkts, $terminatedBy)"
    }

    val maxPacketSize: Int = channel.bulkInMaxPacketSize

    /** Chunk size aligned down to a whole number of packets, never below one packet. */
    private val alignedChunkSize: Int =
        (config.chunkSize / maxPacketSize).coerceAtLeast(1) * maxPacketSize

    private val zlpScratch = ByteArray(maxPacketSize)

    /** Larger buffer for [drain] — a stale live-view frame is far bigger than one packet. */
    private val drainScratch = ByteArray(DRAIN_BUFFER_BYTES)

    init {
        require(maxPacketSize > 0) { "bulkInMaxPacketSize must be positive, was $maxPacketSize" }
        CanonLog.i(
            "UsbTransport ready: maxPacketSize=%d chunkSize=%d (aligned from %d)",
            maxPacketSize,
            alignedChunkSize,
            config.chunkSize,
        )
    }

    // ---------------------------------------------------------------- write

    /**
     * Writes [length] bytes, looping until all are accepted.
     *
     * A partial write is not an error condition to paper over - it just means the stack
     * took what it could. Looping is correct; assuming one call writes everything is the
     * bug.
     */
    fun write(data: ByteArray, offset: Int = 0, length: Int = data.size - offset) {
        require(offset >= 0 && length >= 0 && offset + length <= data.size) {
            "bad range offset=$offset length=$length size=${data.size}"
        }
        if (!channel.isOpen) throw UsbError.Closed()

        var written = 0
        while (written < length) {
            val toWrite = min(alignedChunkSize, length - written)
            val n = channel.bulkOut(data, offset + written, toWrite, config.writeTimeoutMs)
            when {
                n < 0 -> throw UsbError.TransferFailed("bulkOut", n)
                n == 0 -> throw UsbError.Timeout("bulkOut", config.writeTimeoutMs)
                else -> written += n
            }
        }
    }

    // ---------------------------------------------------------------- read

    /**
     * Reads one logical transfer.
     *
     * @param expectedLength when known (from a PTP container header), reading stops there
     *   and a pending ZLP is drained. When null, reading continues until the device ends
     *   the transfer with a short or zero-length packet.
     * @param limit hard ceiling on bytes; defaults to [Config.maxTransferBytes].
     */
    fun readTransfer(
        expectedLength: Int? = null,
        limit: Int = config.maxTransferBytes,
        timeoutMs: Int = config.readTimeoutMs,
    ): TransferResult {
        if (!channel.isOpen) throw UsbError.Closed()
        require(expectedLength == null || expectedLength >= 0) { "expectedLength must be >= 0" }

        val ceiling = expectedLength ?: limit
        // One packet of slack: a device may legitimately send a full packet when fewer
        // bytes remain, and overflowing the buffer would be a hard crash.
        var buffer = ByteArray(min(ceiling, alignedChunkSize) + maxPacketSize)
        var total = 0
        var packets = 0

        while (true) {
            if (total >= ceiling) {
                val termination = if (expectedLength != null) {
                    consumePendingZlp(total)
                    Termination.LENGTH_REACHED
                } else {
                    CanonLog.w("readTransfer hit limit of %d bytes without device terminating", ceiling)
                    Termination.LIMIT_REACHED
                }
                return TransferResult(buffer.copyOf(total), packets, termination)
            }

            if (total + maxPacketSize > buffer.size) {
                buffer = buffer.copyOf(min(buffer.size * 2, ceiling + maxPacketSize))
            }

            val room = min(alignedChunkSize, buffer.size - total)
            val request = if (expectedLength != null) {
                min(room, expectedLength - total)
            } else {
                room
            }

            val n = channel.bulkIn(buffer, total, request, timeoutMs)

            when {
                n < 0 -> {
                    if (!channel.isOpen) throw UsbError.Detached()
                    throw UsbError.Timeout("bulkIn after ${total}B", timeoutMs)
                }

                // A zero-length packet. This IS the P-01 case, and reaching it here means
                // it has been consumed correctly rather than left to poison the next read.
                n == 0 -> {
                    packets++
                    CanonLog.v("ZLP consumed after %dB", total)
                    return TransferResult(buffer.copyOf(total), packets, Termination.ZERO_LENGTH_PACKET)
                }

                else -> {
                    total += n
                    packets++
                    // The stack fills the request unless a short packet ended the transfer.
                    if (n < request) {
                        return TransferResult(buffer.copyOf(total), packets, Termination.SHORT_PACKET)
                    }
                }
            }
        }
    }

    /** Reads exactly [length] bytes, failing if the device ends the transfer early. */
    fun readExactly(length: Int, timeoutMs: Int = config.readTimeoutMs): ByteArray {
        val result = readTransfer(expectedLength = length, timeoutMs = timeoutMs)
        if (result.size != length) {
            throw UsbError.TransferFailed(
                "readExactly wanted $length got ${result.size} (${result.terminatedBy})",
                result.size,
            )
        }
        return result.data
    }

    /**
     * Drains a zero-length packet that may be pending after a packet-aligned transfer.
     *
     * Only meaningful when [total] is a non-zero exact multiple of [maxPacketSize] - in
     * every other case the transfer already ended on a short packet and there is nothing
     * to drain, so we skip the cost entirely.
     */
    private fun consumePendingZlp(total: Int) {
        if (total == 0 || total % maxPacketSize != 0) return

        val n = channel.bulkIn(zlpScratch, 0, maxPacketSize, config.zlpTimeoutMs)
        when {
            n == 0 -> CanonLog.v("Drained pending ZLP after %dB aligned transfer", total)
            n < 0 -> CanonLog.v("No ZLP pending after %dB (host stack consumed it)", total)
            else -> CanonLog.e(
                "P-01: expected ZLP after %dB aligned transfer but got %d bytes of data. " +
                    "The stream is now misaligned - the session should be reset.",
                total,
                n,
            )
        }
    }

    /**
     * Reads and discards everything the endpoint still holds.
     *
     * This is the recovery half of P-02. After a timeout, a late response may still be
     * in flight; leaving it there offsets every subsequent read by one transfer. M2 calls
     * this whenever a response's transaction ID does not match what was sent.
     *
     * @return bytes discarded.
     */
    fun drain(timeoutMs: Int = config.zlpTimeoutMs): Int {
        if (!channel.isOpen) return 0
        var discarded = 0
        var rounds = 0
        while (rounds < MAX_DRAIN_ROUNDS && discarded < MAX_DRAIN_BYTES) {
            val n = channel.bulkIn(drainScratch, 0, drainScratch.size, timeoutMs)
            rounds++
            if (n <= 0) break
            discarded += n
        }
        if (discarded > 0) {
            CanonLog.w("Drained %dB of stale data in %d reads (P-02 recovery)", discarded, rounds)
        }
        if (discarded >= MAX_DRAIN_BYTES) {
            CanonLog.e(
                "Drain hit its %dB ceiling - the camera is still streaming. " +
                    "Live view was probably left running by an unclean exit (U-17).",
                MAX_DRAIN_BYTES,
            )
        }
        return discarded
    }

    /** Reads one interrupt packet, or null on timeout. Events are polled, so null is normal. */
    fun readInterrupt(timeoutMs: Int = config.readTimeoutMs): ByteArray? {
        if (!channel.isOpen) throw UsbError.Closed()
        val buffer = ByteArray(maxPacketSize)
        val n = channel.interruptIn(buffer, 0, buffer.size, timeoutMs)
        return if (n > 0) buffer.copyOf(n) else null
    }

    /**
     * Clears halted endpoints and discards anything stale left behind.
     *
     * Run on every connect. If the previous session ended uncleanly - a crash, a cable
     * pull mid-transaction, `am force-stop` - the endpoint is left halted and every
     * transfer returns -1 until it is cleared (`U-06`). Recovering here avoids the
     * otherwise-necessary camera power cycle.
     */
    fun recoverFromStall(): Boolean {
        val cleared = channel.clearStall()
        val discarded = drain(RECOVERY_DRAIN_TIMEOUT_MS)
        if (discarded > 0) CanonLog.i("Discarded %dB left over from a previous session", discarded)
        return cleared
    }

    override fun close() = channel.close()

    private companion object {
        /**
         * Drain budget.
         *
         * > `U-17`, observed on hardware 2026-08-14. The old budget was 64 rounds of one
         * > 512-byte packet — **32KB total**. That is fine for the ZLP or a stray response
         * > it was written for, but a Canon **live-view frame is hundreds of KB**. Killing
         * > the app mid-live-view therefore left most of a frame in the pipe, the drain gave
         * > up long before reaching the end of it, and the next connect parsed the remainder
         * > as a PTP container header: *"Container truncated: declared 1140862976"*. The
         * > camera then appeared to need a physical replug.
         *
         * Reads are 16KB rather than one packet so a full frame clears in tens of reads, and
         * the ceiling is a byte count rather than a round count so it scales with whatever
         * the device is actually holding. Both bounds remain so a chattering device cannot
         * hang the connect path.
         */
        const val MAX_DRAIN_ROUNDS = 2048
        const val MAX_DRAIN_BYTES = 8 * 1024 * 1024

        /**
         * Per-read timeout while draining after a stall clear.
         *
         * The default drain timeout is [Config.zlpTimeoutMs] (50ms), tuned for a
         * zero-length packet that is either already there or never coming. Recovery is a
         * different problem: observed on hardware 2026-08-17, a drain at 50ms found the
         * endpoint empty and reported nothing discarded, and the very next `GetDeviceInfo`
         * still read leftovers — *"Container truncated: declared 1140862976"*, the exact
         * signature `U-17` describes. The stale data was in flight, not absent.
         *
         * Costs one extra timeout on a genuinely clean endpoint, since the drain loop stops
         * on the first empty read. That is a cheap price for not needing someone to walk
         * over and power-cycle the camera.
         */
        const val RECOVERY_DRAIN_TIMEOUT_MS = 250
        const val DRAIN_BUFFER_BYTES = 16 * 1024
    }
}
