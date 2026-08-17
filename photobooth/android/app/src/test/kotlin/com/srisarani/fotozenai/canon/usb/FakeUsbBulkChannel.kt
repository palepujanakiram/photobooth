package com.srisarani.fotozenai.canon.usb

import kotlin.math.min

/**
 * A fake bulk endpoint that models real USB transfer semantics.
 *
 * This is the whole reason M1's hard parts are testable. It is worth being precise about
 * what it simulates, because a fake that is too forgiving would let the P-01 bug through:
 *
 * - Data is delivered from a queue of logical transfers.
 * - A read returns at most the requested byte count.
 * - **A transfer whose length is an exact multiple of the packet size carries a trailing
 *   zero-length packet.** If the reader requests *more* than the transfer holds, that ZLP
 *   is absorbed into the same request and never seen. If the reader requests *exactly* the
 *   transfer length, the request is filled and the ZLP stays pending - so the reader's
 *   NEXT read returns 0 bytes.
 *
 * That last case is precisely the failure P-01 describes, and it is reproduced here
 * faithfully so the transport can be proven to handle it.
 */
class FakeUsbBulkChannel(
    override val bulkInMaxPacketSize: Int = 512,
) : UsbBulkChannel {

    private class Transfer(val data: ByteArray, var position: Int = 0, var zlpPending: Boolean)

    private val inbound = ArrayDeque<Transfer>()

    /** Everything written by the transport, one entry per bulkOut call. */
    val writes = mutableListOf<ByteArray>()

    /** Caps how many bytes a single bulkOut accepts, to exercise partial-write looping. */
    var maxBytesPerWrite: Int = Int.MAX_VALUE

    /** When true, reads with nothing queued return -1 (timeout) instead of blocking. */
    var returnTimeoutWhenEmpty: Boolean = true

    var interruptData: ArrayDeque<ByteArray> = ArrayDeque()

    private var closed = false
    override val isOpen: Boolean get() = !closed

    var bulkInCallCount: Int = 0
        private set

    /** Queues a logical transfer, computing whether it ends with a ZLP the way a device would. */
    fun enqueueTransfer(data: ByteArray) {
        inbound.addLast(
            Transfer(
                data = data,
                zlpPending = data.isNotEmpty() && data.size % bulkInMaxPacketSize == 0,
            ),
        )
    }

    /** Queues a bare zero-length packet, e.g. to simulate a stale ZLP left by a prior bug. */
    fun enqueueZeroLengthPacket() {
        inbound.addLast(Transfer(data = ByteArray(0), zlpPending = true))
    }

    fun pendingTransfers(): Int = inbound.size

    override fun bulkIn(buffer: ByteArray, offset: Int, length: Int, timeoutMs: Int): Int {
        if (closed) throw UsbError.Closed()
        bulkInCallCount++

        while (true) {
            val transfer = inbound.firstOrNull()
                ?: return if (returnTimeoutWhenEmpty) -1 else 0

            val remaining = transfer.data.size - transfer.position

            if (remaining == 0) {
                if (transfer.zlpPending) {
                    transfer.zlpPending = false
                    inbound.removeFirst()
                    return 0 // the zero-length packet
                }
                inbound.removeFirst()
                continue // exhausted, move to the next transfer
            }

            val n = min(length, remaining)
            transfer.data.copyInto(buffer, offset, transfer.position, transfer.position + n)
            transfer.position += n

            if (transfer.position >= transfer.data.size) {
                if (n < length) {
                    // Request under-filled: the short packet (or the ZLP) terminated this
                    // request, so the ZLP is absorbed and never separately visible.
                    inbound.removeFirst()
                } else if (!transfer.zlpPending) {
                    // Request exactly filled and the final packet was short. Done.
                    inbound.removeFirst()
                }
                // Request exactly filled AND packet-aligned: leave the transfer queued with
                // zlpPending == true. The next read gets the ZLP. This is the P-01 trap.
            }
            return n
        }
    }

    override fun bulkOut(data: ByteArray, offset: Int, length: Int, timeoutMs: Int): Int {
        if (closed) throw UsbError.Closed()
        val n = min(length, maxBytesPerWrite)
        writes.add(data.copyOfRange(offset, offset + n))
        return n
    }

    override fun interruptIn(buffer: ByteArray, offset: Int, length: Int, timeoutMs: Int): Int {
        if (closed) throw UsbError.Closed()
        val next = interruptData.removeFirstOrNull() ?: return -1
        val n = min(length, next.size)
        next.copyInto(buffer, offset, 0, n)
        return n
    }

    var stallCleared = false
        private set

    override fun clearStall(): Boolean {
        stallCleared = true
        return true
    }

    override fun close() {
        closed = true
    }

    /** All bytes written, concatenated - convenient for asserting on a command sequence. */
    fun writtenBytes(): ByteArray {
        val total = writes.sumOf { it.size }
        val out = ByteArray(total)
        var pos = 0
        writes.forEach { it.copyInto(out, pos); pos += it.size }
        return out
    }
}
