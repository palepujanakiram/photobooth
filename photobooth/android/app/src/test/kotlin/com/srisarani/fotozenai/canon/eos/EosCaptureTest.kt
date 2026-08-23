package com.srisarani.fotozenai.canon.eos

import com.google.common.truth.Truth.assertThat
import com.srisarani.fotozenai.canon.ptp.CanonEosOperation
import com.srisarani.fotozenai.canon.ptp.PtpContainer
import com.srisarani.fotozenai.canon.ptp.PtpContainerType
import com.srisarani.fotozenai.canon.ptp.PtpException
import com.srisarani.fotozenai.canon.ptp.PtpReader
import com.srisarani.fotozenai.canon.ptp.PtpResponse
import com.srisarani.fotozenai.canon.ptp.PtpSession
import com.srisarani.fotozenai.canon.usb.FakeUsbBulkChannel
import com.srisarani.fotozenai.canon.usb.UsbTransport
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertThrows
import org.junit.Test

class EosCaptureTest {
    private class Rig {
        val channel = FakeUsbBulkChannel(512)
        val transport = UsbTransport(channel, UsbTransport.Config(readTimeoutMs = 50, zlpTimeoutMs = 2))
        val ptp = PtpSession(transport)
        val properties = EosProperties(ptp)
        val capture = EosCapture(ptp, properties, EosCapture.Config(downloadChunkBytes = 1024))

        var txn = 0L

        fun ok(vararg params: Long) {
            val w =
                com.srisarani.fotozenai.canon.ptp
                    .PtpWriter()
            params.forEach { w.u32(it) }
            channel.enqueueTransfer(
                PtpContainer(PtpContainerType.RESPONSE, PtpResponse.OK, txn++, w.toByteArray()).toByteArray(),
            )
        }

        fun dataThenOk(
            code: Int,
            payload: ByteArray,
        ) {
            channel.enqueueTransfer(PtpContainer.data(code, txn, payload).toByteArray())
            channel.enqueueTransfer(
                PtpContainer(PtpContainerType.RESPONSE, PtpResponse.OK, txn++).toByteArray(),
            )
        }

        fun fail(code: Int) {
            channel.enqueueTransfer(
                PtpContainer(PtpContainerType.RESPONSE, code, txn++).toByteArray(),
            )
        }

        fun commands(): List<PtpContainer> = channel.writes.map { PtpContainer.parse(it) }.filter { it.type == PtpContainerType.COMMAND }

        fun dataSent(): List<PtpContainer> = channel.writes.map { PtpContainer.parse(it) }.filter { it.type == PtpContainerType.DATA }
    }

    // ================================================================ P-05

    /**
     * `P-05`, corrected by hardware 2026-08-13.
     *
     * With capture destination set to the host, EOS bodies want a fake free-space
     * value or they behave as though the host is full. Capacity must be set FIRST — a
     * camera that thinks the host has no space can reject the destination change outright.
     *
     * Capacity is an **operation** (`EOS_PCHDDCapacity`, 0x911A), not a device property.
     * The first implementation wrote property 0xD11A and got `DeviceBusy` on every one of
     * five retries — which reads as transient and invites a retry loop that can never
     * succeed. The M2 capability dump settled it: 0x911A is in the body's operation list.
     */
    @Test
    fun `host capture sets destination FIRST, then announces capacity`() {
        val rig = Rig()
        rig.ok()
        rig.ok()

        rig.capture.configureForHostCapture()

        // Order verified on hardware 2026-08-13. Reversed, the destination write is
        // accepted and then silently ignored: the camera saves to its card and emits
        // StorageInfoChanged instead of ObjectAdded, and the host waits forever for a
        // photo that was never offered. Nothing errors - which is what made it expensive.
        val codes = rig.commands().map { it.code }
        assertThat(codes)
            .containsExactly(
                CanonEosOperation.SET_DEVICE_PROP_VALUE_EX, // destination
                CanonEosOperation.PC_HDD_CAPACITY, // then capacity
            ).inOrder()
    }

    @Test
    fun `capacity operation sends non-zero parameters`() {
        val rig = Rig()
        rig.ok()
        rig.ok()

        rig.capture.configureForHostCapture()

        val capacity = rig.commands().first { it.code == CanonEosOperation.PC_HDD_CAPACITY }
        assertThat(capacity.parameter(0)).isGreaterThan(0L) // non-zero is the whole point
        assertThat(capacity.parameter(1)).isGreaterThan(0L)
    }

    /**
     * Destination is BOTH, not HOST.
     *
     * The card keeps the original as an archive while the host still receives every frame
     * over USB. HOST-only leaves exactly one copy of an unrepeatable photo, in app-scoped
     * storage that an uninstall deletes.
     *
     * The host bit is the load-bearing half: without it no image crosses USB at all and
     * there is nothing to print from — so assert on the bit, not just the value.
     */
    @Test
    fun `destination is set to both card and host`() {
        val rig = Rig()
        rig.ok()
        rig.ok()

        rig.capture.configureForHostCapture()

        val payload = rig.dataSent().single().payload
        val r = PtpReader(payload)
        r.u32() // size
        assertThat(r.u32().toInt()).isEqualTo(EosProperty.CAPTURE_DESTINATION)

        val destination = r.u32()
        assertThat(destination).isEqualTo(EosCaptureDestination.BOTH.toLong())
        assertThat(destination.toInt() and EosCaptureDestination.HOST).isEqualTo(
            EosCaptureDestination.HOST,
        )
        assertThat(destination.toInt() and EosCaptureDestination.CAMERA_CARD).isEqualTo(
            EosCaptureDestination.CAMERA_CARD,
        )
    }

    /** A failed destination write must not stop us announcing capacity, and vice versa. */
    @Test
    fun `destination failure does not abort capacity announcement`() {
        val rig = Rig()
        rig.fail(PtpResponse.ACCESS_DENIED)
        rig.ok()

        rig.capture.configureForHostCapture()

        assertThat(rig.commands().map { it.code }).contains(CanonEosOperation.PC_HDD_CAPACITY)
    }

    @Test
    fun `property payload carries its own size header`() {
        val rig = Rig()
        rig.ok()

        rig.properties.setUInt32(EosProperty.ISO_SPEED, 400)

        val payload = rig.dataSent().single().payload
        assertThat(payload.size).isEqualTo(12)
        val r = PtpReader(payload)
        assertThat(r.u32()).isEqualTo(12L) // size includes itself
        assertThat(r.u32().toInt()).isEqualTo(EosProperty.ISO_SPEED)
        assertThat(r.u32()).isEqualTo(400L)
    }

    /** `C-04`: in Auto modes properties are read-only and writes fail unhelpfully. */
    @Test
    fun `trySet returns false rather than throwing on a read-only property`() {
        val rig = Rig()
        rig.fail(PtpResponse.ACCESS_DENIED)

        assertThat(rig.properties.trySetUInt32(EosProperty.APERTURE, 56)).isFalse()
    }

    /**
     * `P-07`, observed on real hardware 2026-08-13: immediately after the EOS handshake the
     * camera answers `DeviceBusy` to property writes while it settles into remote mode.
     * The very first property we set is the capacity hack, so without retry the most
     * important write in the capture path is the one most likely to fail.
     */
    @Test
    fun `property write retries through DeviceBusy and eventually succeeds`() {
        val rig = Rig()
        rig.fail(PtpResponse.DEVICE_BUSY)
        rig.fail(PtpResponse.DEVICE_BUSY)
        rig.ok()

        val ok = rig.properties.setUInt32WithRetry(EosProperty.CAPACITY, 0x1000000, initialDelayMs = 1)

        assertThat(ok).isTrue()
        assertThat(rig.commands()).hasSize(3)
    }

    /** A definitive failure must not be retried - that only adds latency to a certain no. */
    @Test
    fun `property write does not retry a non-busy failure`() {
        val rig = Rig()
        rig.fail(PtpResponse.ACCESS_DENIED)

        val ok = rig.properties.setUInt32WithRetry(EosProperty.APERTURE, 56, initialDelayMs = 1)

        assertThat(ok).isFalse()
        assertThat(rig.commands()).hasSize(1) // tried once, accepted the answer
    }

    @Test
    fun `property write gives up after the attempt limit`() {
        val rig = Rig()
        repeat(4) { rig.fail(PtpResponse.DEVICE_BUSY) }

        val ok =
            rig.properties.setUInt32WithRetry(
                EosProperty.CAPACITY,
                1,
                maxAttempts = 3,
                initialDelayMs = 1,
            )

        assertThat(ok).isFalse()
        assertThat(rig.commands()).hasSize(3)
    }

    // ================================================================ release

    /**
     * The release sequence: half-press (AF) then full press, released in reverse. Getting
     * the order wrong leaves the shutter virtually held down and blocks the next capture.
     */
    @Test
    fun `release with autofocus does half press then full press, released in reverse`() =
        runTest {
            val rig = Rig()
            repeat(4) { rig.ok() }

            rig.capture.release(EosCapture.ReleaseMode.WITH_AUTOFOCUS)

            val sequence = rig.commands().map { it.code to it.parameter(0) }
            assertThat(sequence)
                .containsExactly(
                    CanonEosOperation.REMOTE_RELEASE_ON to 1L, // half - AF
                    CanonEosOperation.REMOTE_RELEASE_ON to 2L, // full - fire
                    CanonEosOperation.REMOTE_RELEASE_OFF to 2L, // release full
                    CanonEosOperation.REMOTE_RELEASE_OFF to 1L, // release half
                ).inOrder()
        }

    /**
     * `C-02`: when AF cannot lock, the camera will not fire and it looks exactly like a
     * dead event loop. A no-AF path means a possibly-soft frame instead of a hang.
     */
    @Test
    fun `release without autofocus skips the half press entirely`() =
        runTest {
            val rig = Rig()
            repeat(2) { rig.ok() }

            rig.capture.release(EosCapture.ReleaseMode.WITHOUT_AUTOFOCUS)

            val sequence = rig.commands().map { it.code to it.parameter(0) }
            assertThat(sequence)
                .containsExactly(
                    CanonEosOperation.REMOTE_RELEASE_ON to 2L,
                    CanonEosOperation.REMOTE_RELEASE_OFF to 2L,
                ).inOrder()
        }

    @Test
    fun `release falls back to RemoteRelease when On-Off is unsupported`() =
        runTest {
            val rig = Rig()
            // C-02: a failed half-press is swallowed and the full press still runs.
            // The fallback only fires when the *shutter* opcode is unsupported.
            rig.fail(PtpResponse.OPERATION_NOT_SUPPORTED)
            rig.fail(PtpResponse.OPERATION_NOT_SUPPORTED)
            rig.ok()

            rig.capture.release(EosCapture.ReleaseMode.WITH_AUTOFOCUS)

            assertThat(rig.commands().map { it.code }).contains(CanonEosOperation.REMOTE_RELEASE)
        }

    // ================================================================ download

    @Test
    fun `download assembles chunks and signals transfer complete`() {
        val rig = Rig()
        val payload = ByteArray(2500) { (it % 251).toByte() }
        // chunk size 1024 -> 1024, 1024, 452
        rig.dataThenOk(CanonEosOperation.GET_PARTIAL_OBJECT, payload.copyOfRange(0, 1024))
        rig.dataThenOk(CanonEosOperation.GET_PARTIAL_OBJECT, payload.copyOfRange(1024, 2048))
        rig.dataThenOk(CanonEosOperation.GET_PARTIAL_OBJECT, payload.copyOfRange(2048, 2500))
        rig.ok() // TransferComplete

        val result = rig.capture.download(objectHandle = 0x1234, expectedSize = 2500)

        assertThat(result.bytes).isEqualTo(payload)
        // The call that makes the SECOND capture work.
        assertThat(rig.commands().map { it.code }).contains(CanonEosOperation.TRANSFER_COMPLETE)
    }

    @Test
    fun `download requests correct offsets and sizes`() {
        val rig = Rig()
        rig.dataThenOk(CanonEosOperation.GET_PARTIAL_OBJECT, ByteArray(1024))
        rig.dataThenOk(CanonEosOperation.GET_PARTIAL_OBJECT, ByteArray(500))
        rig.ok()

        rig.capture.download(0x1234, 1524)

        val partials = rig.commands().filter { it.code == CanonEosOperation.GET_PARTIAL_OBJECT }
        assertThat(partials.map { Triple(it.parameter(0), it.parameter(1), it.parameter(2)) })
            .containsExactly(
                Triple(0x1234L, 0L, 1024L),
                Triple(0x1234L, 1024L, 500L),
            ).inOrder()
    }

    @Test
    fun `download reports progress`() {
        val rig = Rig()
        rig.dataThenOk(CanonEosOperation.GET_PARTIAL_OBJECT, ByteArray(1024))
        rig.dataThenOk(CanonEosOperation.GET_PARTIAL_OBJECT, ByteArray(1024))
        rig.ok()

        val progress = mutableListOf<Pair<Long, Long>>()
        rig.capture.download(1, 2048) { read, total -> progress += read to total }

        assertThat(progress).containsExactly(1024L to 2048L, 2048L to 2048L).inOrder()
    }

    /**
     * `P-08`: a short read that returns without error is the most dangerous failure in the
     * whole pipeline, because nothing errors and the JPEG is simply truncated. An empty
     * chunk means the download cannot progress and must fail loudly.
     */
    @Test
    fun `download rejects an empty chunk rather than looping forever`() {
        val rig = Rig()
        rig.dataThenOk(CanonEosOperation.GET_PARTIAL_OBJECT, ByteArray(0))

        val error =
            assertThrows(PtpException.Malformed::class.java) {
                rig.capture.download(1, 5000)
            }
        assertThat(error.message).contains("empty chunk")
    }

    @Test
    fun `download rejects a missing data phase`() {
        val rig = Rig()
        rig.ok() // response with no data

        val error =
            assertThrows(PtpException.Malformed::class.java) {
                rig.capture.download(1, 1000)
            }
        assertThat(error.message).contains("no data")
    }

    @Test
    fun `single chunk download works`() {
        val rig = Rig()
        val payload = ByteArray(500) { 0x5A }
        rig.dataThenOk(CanonEosOperation.GET_PARTIAL_OBJECT, payload)
        rig.ok()

        assertThat(rig.capture.download(1, 500).bytes).isEqualTo(payload)
    }

    /**
     * A failing TransferComplete must not turn a successful download into an exception -
     * we already have the bytes. It is logged loudly because the next capture may hang.
     */
    @Test
    fun `transfer complete failure does not discard a good download`() {
        val rig = Rig()
        rig.dataThenOk(CanonEosOperation.GET_PARTIAL_OBJECT, ByteArray(100))
        rig.fail(PtpResponse.GENERAL_ERROR) // TransferComplete fails

        val result = rig.capture.download(1, 100)

        assertThat(result.bytes).hasLength(100)
    }

    @Test
    fun `throughput is computed for the M9 assessment`() {
        val rig = Rig()
        rig.dataThenOk(CanonEosOperation.GET_PARTIAL_OBJECT, ByteArray(1024))
        rig.ok()

        val result = rig.capture.download(1, 1024)

        assertThat(result.throughputMbPerSec).isAtLeast(0.0)
        assertThat(result.objectHandle).isEqualTo(1L)
    }
}
