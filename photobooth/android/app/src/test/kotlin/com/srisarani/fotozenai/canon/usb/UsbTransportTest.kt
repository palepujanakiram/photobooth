package com.srisarani.fotozenai.canon.usb

import com.google.common.truth.Truth.assertThat
import org.junit.Test
import org.junit.Assert.assertThrows

class UsbTransportTest {

    private val packetSize = 512

    private fun transport(
        channel: FakeUsbBulkChannel,
        chunkSize: Int = 16 * 1024,
    ) = UsbTransport(channel, UsbTransport.Config(chunkSize = chunkSize, readTimeoutMs = 100, zlpTimeoutMs = 5))

    private fun bytes(n: Int, seed: Int = 0) = ByteArray(n) { ((it + seed) % 251).toByte() }

    // ================================================================ P-01: ZLP

    /**
     * THE test for P-01.
     *
     * A payload that is an exact multiple of the packet size leaves a zero-length packet
     * pending. If the transport does not consume it, the *next* read returns 0 bytes and
     * the stream is offset by one transfer forever.
     *
     * Here two containers are queued back to back. The first is packet-aligned. If ZLP
     * handling is wrong, the second read returns empty and this test fails - which is
     * exactly the real-world symptom, caught on a laptop instead of at 2am with a camera.
     */
    @Test
    fun `packet-aligned transfer does not poison the next read`() {
        val channel = FakeUsbBulkChannel(packetSize)
        val first = bytes(packetSize * 4) // 2048 - exact multiple, ZLP will be pending
        val second = bytes(300, seed = 7) // short packet, unambiguous
        channel.enqueueTransfer(first)
        channel.enqueueTransfer(second)

        val t = transport(channel)

        val r1 = t.readTransfer(expectedLength = first.size)
        assertThat(r1.data).isEqualTo(first)
        assertThat(r1.terminatedBy).isEqualTo(UsbTransport.Termination.LENGTH_REACHED)

        // The critical assertion: the second container arrives intact, not shifted.
        val r2 = t.readTransfer(expectedLength = second.size)
        assertThat(r2.data).isEqualTo(second)
    }

    @Test
    fun `zero-length packet terminates an unbounded read`() {
        val channel = FakeUsbBulkChannel(packetSize)
        channel.enqueueTransfer(bytes(packetSize * 2))

        // No expectedLength: the loop must recognise the ZLP as the terminator.
        val result = transport(channel).readTransfer()

        assertThat(result.size).isEqualTo(packetSize * 2)
        assertThat(result.terminatedBy).isAnyOf(
            UsbTransport.Termination.ZERO_LENGTH_PACKET,
            UsbTransport.Termination.SHORT_PACKET,
        )
    }

    @Test
    fun `a stale zero-length packet left by a previous transfer is drained`() {
        val channel = FakeUsbBulkChannel(packetSize)
        channel.enqueueZeroLengthPacket() // as if a prior bug left one behind
        channel.enqueueTransfer(bytes(128))

        val t = transport(channel)
        val discarded = t.drain()
        val result = t.readTransfer(expectedLength = 128)

        assertThat(discarded).isEqualTo(0) // a ZLP is zero bytes, but it is consumed
        assertThat(result.size).isEqualTo(128)
    }

    @Test
    fun `non-aligned transfer skips the zlp drain entirely`() {
        val channel = FakeUsbBulkChannel(packetSize)
        channel.enqueueTransfer(bytes(700)) // 700 % 512 != 0, ends on a short packet

        val t = transport(channel)
        val result = t.readTransfer(expectedLength = 700)
        val callsAfterRead = channel.bulkInCallCount

        assertThat(result.size).isEqualTo(700)
        // 700 bytes arrives in a single request. Exactly one bulkIn call proves no
        // speculative ZLP read was issued - the drain would have made it two.
        assertThat(callsAfterRead).isEqualTo(1)
    }

    // ================================================================ assembly

    @Test
    fun `assembles a transfer spanning many chunks`() {
        val channel = FakeUsbBulkChannel(packetSize)
        val payload = bytes(300_000, seed = 3)
        channel.enqueueTransfer(payload)

        // Small chunk size forces many round trips, as P-06 requires on real hardware.
        val result = transport(channel, chunkSize = 4096).readTransfer(expectedLength = payload.size)

        assertThat(result.size).isEqualTo(payload.size)
        assertThat(result.data).isEqualTo(payload)
        assertThat(result.packetsRead).isGreaterThan(50)
    }

    @Test
    fun `short packet terminates before the expected length`() {
        val channel = FakeUsbBulkChannel(packetSize)
        channel.enqueueTransfer(bytes(100))

        // Ask for more than the device has: it ends the transfer with a short packet.
        val result = transport(channel).readTransfer(expectedLength = 4096)

        assertThat(result.size).isEqualTo(100)
        assertThat(result.terminatedBy).isEqualTo(UsbTransport.Termination.SHORT_PACKET)
    }

    @Test
    fun `chunk size is aligned down to a whole number of packets`() {
        val channel = FakeUsbBulkChannel(packetSize)
        channel.enqueueTransfer(bytes(packetSize * 10))

        // 1000 is not a multiple of 512; it must be aligned down to 512, never up.
        // An unaligned request risks a babble/overflow error on real hardware.
        val result = transport(channel, chunkSize = 1000).readTransfer(expectedLength = packetSize * 10)

        assertThat(result.size).isEqualTo(packetSize * 10)
    }

    @Test
    fun `chunk size smaller than one packet is raised to one packet`() {
        val channel = FakeUsbBulkChannel(packetSize)
        channel.enqueueTransfer(bytes(2048))

        val result = transport(channel, chunkSize = 16).readTransfer(expectedLength = 2048)

        assertThat(result.size).isEqualTo(2048)
    }

    @Test
    fun `readExactly rejects a truncated transfer`() {
        val channel = FakeUsbBulkChannel(packetSize)
        channel.enqueueTransfer(bytes(50))

        // Silent truncation is P-08 - the most dangerous class of bug here, because a
        // short file that returned without error looks exactly like a good one.
        val error = assertThrows(UsbError.TransferFailed::class.java) {
            transport(channel).readExactly(5000)
        }
        assertThat(error.message).contains("wanted 5000 got 50")
    }

    @Test
    fun `readExactly returns the full payload when complete`() {
        val channel = FakeUsbBulkChannel(packetSize)
        val payload = bytes(1536) // 3 packets exactly - aligned, so ZLP is in play
        channel.enqueueTransfer(payload)

        assertThat(transport(channel).readExactly(1536)).isEqualTo(payload)
    }

    // ================================================================ write

    @Test
    fun `write loops until every byte is accepted`() {
        val channel = FakeUsbBulkChannel(packetSize)
        channel.maxBytesPerWrite = 100 // force partial writes

        val payload = bytes(1024)
        transport(channel).write(payload)

        assertThat(channel.writes.size).isEqualTo(11) // 10 x 100 + 1 x 24
        assertThat(channel.writtenBytes()).isEqualTo(payload)
    }

    @Test
    fun `write rejects an out of range slice`() {
        val channel = FakeUsbBulkChannel(packetSize)
        assertThrows(IllegalArgumentException::class.java) {
            transport(channel).write(bytes(10), offset = 5, length = 20)
        }
    }

    // ================================================================ drain / P-02

    @Test
    fun `drain discards stale data and reports the byte count`() {
        val channel = FakeUsbBulkChannel(packetSize)
        channel.enqueueTransfer(bytes(200)) // a late response nobody wants
        channel.enqueueTransfer(bytes(300))

        val discarded = transport(channel).drain()

        assertThat(discarded).isEqualTo(500)
        assertThat(channel.pendingTransfers()).isEqualTo(0)
    }

    @Test
    fun `drain on an empty endpoint is a no-op`() {
        val channel = FakeUsbBulkChannel(packetSize)
        assertThat(transport(channel).drain()).isEqualTo(0)
    }

    // ================================================================ lifecycle

    @Test
    fun `reads after close are rejected`() {
        val channel = FakeUsbBulkChannel(packetSize)
        val t = transport(channel)
        t.close()

        assertThrows(UsbError.Closed::class.java) { t.readTransfer(expectedLength = 10) }
        assertThrows(UsbError.Closed::class.java) { t.write(bytes(10)) }
    }

    @Test
    fun `read timeout surfaces as a typed error`() {
        val channel = FakeUsbBulkChannel(packetSize) // nothing queued
        val error = assertThrows(UsbError.Timeout::class.java) {
            transport(channel).readTransfer(expectedLength = 100)
        }
        assertThat(error.message).contains("bulkIn")
    }

    @Test
    fun `interrupt read returns null when no event is pending`() {
        val channel = FakeUsbBulkChannel(packetSize)
        assertThat(transport(channel).readInterrupt()).isNull()
    }

    @Test
    fun `interrupt read returns the queued event`() {
        val channel = FakeUsbBulkChannel(packetSize)
        channel.interruptData.addLast(byteArrayOf(1, 2, 3, 4))

        assertThat(transport(channel).readInterrupt()).isEqualTo(byteArrayOf(1, 2, 3, 4))
    }

    @Test
    fun `zero length expected read is legal and returns nothing`() {
        val channel = FakeUsbBulkChannel(packetSize)
        val result = transport(channel).readTransfer(expectedLength = 0)

        assertThat(result.size).isEqualTo(0)
        assertThat(result.terminatedBy).isEqualTo(UsbTransport.Termination.LENGTH_REACHED)
    }
}
