package com.srisarani.fotozenai.canon.usb

import com.srisarani.fotozenai.canon.CanonLog
import kotlin.math.min

/**
 * Assembles one logical USB bulk transfer from packet-sized reads.
 *
 * Extracted from [UsbTransport] so the packet loop stays under the file-complexity
 * budget without changing ZLP / short-packet behaviour (P-01).
 */
internal class UsbTransferReader(
    private val channel: UsbBulkChannel,
    private val maxPacketSize: Int,
    private val alignedChunkSize: Int,
    private val consumePendingZlp: (Int) -> Unit,
) {

    fun read(
        expectedLength: Int?,
        ceiling: Int,
        timeoutMs: Int,
    ): UsbTransport.TransferResult {
        var buffer = ByteArray(min(ceiling, alignedChunkSize) + maxPacketSize)
        var total = 0
        var packets = 0

        while (true) {
            if (total >= ceiling) {
                return finishAtCeiling(buffer, total, packets, expectedLength, ceiling)
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
            if (request <= 0) {
                return finishAtCeiling(buffer, total, packets, expectedLength, ceiling)
            }
            val n = channel.bulkIn(buffer, total, request, timeoutMs)
            CanonLog.v("bulkIn asked=%d got=%d (total=%d, packet=%d)", request, n, total, packets)
            when (val packet = classifyPacket(n, request, total, timeoutMs)) {
                is Packet.Error -> throw packet.error
                is Packet.Complete -> {
                    val end = packet.advance(total, packets)
                    return UsbTransport.TransferResult(
                        buffer.copyOf(end.total),
                        end.packets,
                        packet.termination,
                    )
                }
                is Packet.Continue -> {
                    val end = packet.advance(total, packets)
                    total = end.total
                    packets = end.packets
                }
            }
        }
    }

    private fun finishAtCeiling(
        buffer: ByteArray,
        total: Int,
        packets: Int,
        expectedLength: Int?,
        ceiling: Int,
    ): UsbTransport.TransferResult {
        val termination = if (expectedLength != null) {
            consumePendingZlp(total)
            UsbTransport.Termination.LENGTH_REACHED
        } else {
            CanonLog.w("readTransfer hit limit of %d bytes without device terminating", ceiling)
            UsbTransport.Termination.LIMIT_REACHED
        }
        return UsbTransport.TransferResult(buffer.copyOf(total), packets, termination)
    }

    private fun classifyPacket(
        n: Int,
        request: Int,
        total: Int,
        timeoutMs: Int,
    ): Packet {
        if (n < 0) {
            val error = if (!channel.isOpen) {
                UsbError.Detached()
            } else {
                UsbError.Timeout("bulkIn after ${total}B", timeoutMs)
            }
            return Packet.Error(error)
        }
        if (n == 0) {
            CanonLog.v("ZLP consumed after %dB", total)
            return Packet.Complete(0, UsbTransport.Termination.ZERO_LENGTH_PACKET)
        }
        if (n < request) {
            return Packet.Complete(n, UsbTransport.Termination.SHORT_PACKET)
        }
        return Packet.Continue(n)
    }

    private sealed class Packet {
        abstract val bytes: Int

        fun advance(total: Int, packets: Int): Progress =
            Progress(total + bytes, packets + 1)

        class Error(val error: UsbError) : Packet() {
            override val bytes: Int = 0
        }

        class Complete(
            override val bytes: Int,
            val termination: UsbTransport.Termination,
        ) : Packet()

        class Continue(override val bytes: Int) : Packet()
    }

    private data class Progress(val total: Int, val packets: Int)
}
