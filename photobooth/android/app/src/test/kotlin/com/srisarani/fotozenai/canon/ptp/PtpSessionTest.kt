package com.srisarani.fotozenai.canon.ptp

import com.google.common.truth.Truth.assertThat
import com.srisarani.fotozenai.canon.usb.FakeUsbBulkChannel
import com.srisarani.fotozenai.canon.usb.UsbTransport
import org.junit.Assert.assertThrows
import org.junit.Test

/**
 * Drives [PtpSession] against a fake camera built from real container bytes.
 *
 * The fake channel models genuine USB packet semantics (including the P-01 zero-length
 * packet), so these exercise the whole stack from PTP semantics down to byte transfers -
 * everything except the physical endpoint.
 */
class PtpSessionTest {

    private val packetSize = 512

    private fun setup(): Triple<FakeUsbBulkChannel, UsbTransport, PtpSession> {
        val channel = FakeUsbBulkChannel(packetSize)
        val transport = UsbTransport(
            channel,
            UsbTransport.Config(readTimeoutMs = 100, zlpTimeoutMs = 5),
        )
        return Triple(channel, transport, PtpSession(transport))
    }

    private fun FakeUsbBulkChannel.queueResponse(code: Int, transactionId: Long, vararg params: Long) {
        val writer = PtpWriter()
        params.forEach { writer.u32(it) }
        enqueueTransfer(
            PtpContainer(PtpContainerType.RESPONSE, code, transactionId, writer.toByteArray()).toByteArray(),
        )
    }

    private fun FakeUsbBulkChannel.queueData(code: Int, transactionId: Long, payload: ByteArray) {
        enqueueTransfer(PtpContainer.data(code, transactionId, payload).toByteArray())
    }

    /** A minimal but structurally valid DeviceInfo payload. */
    private fun deviceInfoPayload(
        operations: IntArray = intArrayOf(
            PtpOperation.GET_DEVICE_INFO,
            PtpOperation.OPEN_SESSION,
            CanonEosOperation.SET_REMOTE_MODE,
            CanonEosOperation.SET_EVENT_MODE,
            CanonEosOperation.GET_EVENT,
        ),
        model: String = "Canon EOS 200D II",
    ): ByteArray {
        val w = PtpWriter(256)
        w.u16(100) // standard version 1.00
        w.u32(PtpVendorExtension.CANON.toLong())
        w.u16(100)
        w.string("canon.com: 1.0;")
        w.u16(0) // functional mode
        w.u32(operations.size.toLong()); operations.forEach { w.u16(it) }
        w.u32(1L); w.u16(0x4002) // events
        w.u32(2L); w.u16(0xD101); w.u16(0xD103) // properties
        w.u32(1L); w.u16(PtpObjectFormat.EXIF_JPEG) // capture formats
        w.u32(1L); w.u16(PtpObjectFormat.EXIF_JPEG) // image formats
        w.string("Canon Inc.")
        w.string(model)
        w.string("3-1-0")
        w.string("1234567890")
        return w.toByteArray()
    }

    // ================================================================ basics

    @Test
    fun `open session sends the expected command and marks the session open`() {
        val (channel, _, session) = setup()
        channel.queueResponse(PtpResponse.OK, transactionId = 0)

        session.openSession(1)

        val sent = PtpContainer.parse(channel.writes.first())
        assertThat(sent.type).isEqualTo(PtpContainerType.COMMAND)
        assertThat(sent.code).isEqualTo(PtpOperation.OPEN_SESSION)
        assertThat(sent.transactionId).isEqualTo(0L) // OpenSession uses transaction 0
        assertThat(sent.parameter(0)).isEqualTo(1L)
        assertThat(session.isOpen).isTrue()
    }

    @Test
    fun `session id must be non-zero`() {
        val (_, _, session) = setup()
        assertThrows(IllegalArgumentException::class.java) { session.openSession(0) }
    }

    /**
     * After an app crash or unclean detach the camera still believes a session is live.
     * Treating that as fatal would leave the user unable to reconnect without
     * power-cycling the camera, which on a kiosk means a site visit.
     */
    @Test
    fun `session already open is adopted rather than treated as failure`() {
        val (channel, _, session) = setup()
        channel.queueResponse(PtpResponse.SESSION_ALREADY_OPEN, transactionId = 0)

        session.openSession(1)

        assertThat(session.isOpen).isTrue()
    }

    @Test
    fun `transaction ids increment monotonically after open session`() {
        val (channel, _, session) = setup()
        channel.queueResponse(PtpResponse.OK, 0)
        channel.queueResponse(PtpResponse.OK, 1)
        channel.queueResponse(PtpResponse.OK, 2)

        session.openSession(1)
        session.transact(PtpOperation.GET_STORAGE_IDS)
        session.transact(PtpOperation.GET_STORAGE_IDS)

        val ids = channel.writes.map { PtpContainer.parse(it).transactionId }
        assertThat(ids).containsExactly(0L, 1L, 2L).inOrder()
    }

    @Test
    fun `close session never throws when the camera is gone`() {
        val (channel, _, session) = setup()
        channel.queueResponse(PtpResponse.OK, 0)
        session.openSession(1)
        channel.close() // cable pulled

        session.closeSession() // must not throw

        assertThat(session.isOpen).isFalse()
    }

    @Test
    fun `close session on an unopened session is a no-op`() {
        val (channel, _, session) = setup()

        session.closeSession()

        assertThat(channel.writes).isEmpty()
    }

    // ================================================================ data phase

    @Test
    fun `data phase then response is assembled into one result`() {
        val (channel, _, session) = setup()
        val payload = deviceInfoPayload()
        channel.queueData(PtpOperation.GET_DEVICE_INFO, 0, payload)
        channel.queueResponse(PtpResponse.OK, 0)

        val info = session.getDeviceInfo()

        assertThat(info.model).isEqualTo("Canon EOS 200D II")
        assertThat(info.manufacturer).isEqualTo("Canon Inc.")
        assertThat(info.serialNumber).isEqualTo("1234567890")
        assertThat(info.isCanonEos).isTrue()
        assertThat(info.supportsEosRemoteMode).isTrue()
        assertThat(info.supportsJpegCapture).isTrue()
    }

    @Test
    fun `response with no data phase is handled`() {
        val (channel, _, session) = setup()
        channel.queueResponse(PtpResponse.OK, 0, 0x12345678L)

        val result = session.transact(PtpOperation.CLOSE_SESSION)

        assertThat(result.data).isNull()
        assertThat(result.parameter(0)).isEqualTo(0x12345678L)
    }

    @Test
    fun `outgoing data is written as a data container after the command`() {
        val (channel, _, session) = setup()
        channel.queueResponse(PtpResponse.OK, 0)

        session.transact(PtpOperation.SET_DEVICE_PROP_VALUE, 0xD103L, outgoingData = byteArrayOf(1, 2, 3, 4))

        assertThat(channel.writes).hasSize(2)
        val command = PtpContainer.parse(channel.writes[0])
        val data = PtpContainer.parse(channel.writes[1])
        assertThat(command.type).isEqualTo(PtpContainerType.COMMAND)
        assertThat(data.type).isEqualTo(PtpContainerType.DATA)
        assertThat(data.payload).isEqualTo(byteArrayOf(1, 2, 3, 4))
        assertThat(data.transactionId).isEqualTo(command.transactionId)
    }

    /**
     * A large data phase spans many USB packets and is delivered across several reads.
     * This is the M4 download path in miniature.
     */
    @Test
    fun `large data phase spanning many packets is assembled correctly`() {
        val (channel, _, session) = setup()
        val payload = ByteArray(200_000) { (it % 251).toByte() }
        channel.queueData(PtpOperation.GET_OBJECT, 0, payload)
        channel.queueResponse(PtpResponse.OK, 0)

        val result = session.transact(PtpOperation.GET_OBJECT, 0x1000L)

        assertThat(result.data).isEqualTo(payload)
    }

    /**
     * P-01 in the context of a real transaction: a data payload whose container length is
     * an exact multiple of the packet size. If the ZLP is mishandled, the following
     * Response container read returns 0 bytes and this fails.
     */
    @Test
    fun `packet-aligned data phase does not break the following response`() {
        val (channel, _, session) = setup()
        // Container total = 12 + payload, so payload = 512*4 - 12 makes the container
        // exactly 4 packets.
        val payload = ByteArray(packetSize * 4 - PtpHeader.SIZE) { 0x5A }
        channel.queueData(PtpOperation.GET_OBJECT, 0, payload)
        channel.queueResponse(PtpResponse.OK, 0)

        val result = session.transact(PtpOperation.GET_OBJECT, 0x1000L)

        assertThat(result.data).hasLength(payload.size)
        assertThat(result.responseCode).isEqualTo(PtpResponse.OK)
    }

    // ================================================================ errors

    @Test
    fun `non-ok response throws with a readable message`() {
        val (channel, _, session) = setup()
        channel.queueResponse(PtpResponse.DEVICE_BUSY, 0)

        val error = assertThrows(PtpException.OperationFailed::class.java) {
            session.transact(PtpOperation.GET_OBJECT, 1L)
        }

        assertThat(error.message).contains("GetObject")
        assertThat(error.message).contains("DeviceBusy")
        assertThat(error.isBusy).isTrue()
    }

    @Test
    fun `operation not supported is distinguishable`() {
        val (channel, _, session) = setup()
        channel.queueResponse(PtpResponse.OPERATION_NOT_SUPPORTED, 0)

        val error = assertThrows(PtpException.OperationFailed::class.java) {
            session.transact(CanonEosOperation.DRIVE_LENS)
        }

        assertThat(error.isUnsupported).isTrue()
        assertThat(error.message).contains("EOS_DriveLens")
    }

    @Test
    fun `canon vendor response codes are flagged as such`() {
        val (channel, _, session) = setup()
        channel.queueResponse(0xA102, 0)

        val error = assertThrows(PtpException.OperationFailed::class.java) {
            session.transact(CanonEosOperation.GET_EVENT)
        }

        assertThat(error.message).contains("Canon vendor code")
    }

    @Test
    fun `tryTransact returns a failure instead of throwing`() {
        val (channel, _, session) = setup()
        channel.queueResponse(PtpResponse.OPERATION_NOT_SUPPORTED, 0)

        val result = session.tryTransact(CanonEosOperation.ZOOM)

        assertThat(result.isFailure).isTrue()
    }

    // ================================================================ P-02

    /**
     * THE test for P-02.
     *
     * A late response from a previously timed-out operation carries the wrong transaction
     * ID. Accepting it means every subsequent response belongs to the previous command -
     * a permanently desynchronised session that produces confusing InvalidTransactionID
     * errors in code that is otherwise correct.
     */
    @Test
    fun `mismatched transaction id is detected and reported`() {
        val (channel, _, session) = setup()
        channel.queueResponse(PtpResponse.OK, transactionId = 99) // stale, we expect 0

        val error = assertThrows(PtpException.TransactionMismatch::class.java) {
            session.transact(PtpOperation.GET_STORAGE_IDS)
        }

        assertThat(error.expected).isEqualTo(0L)
        assertThat(error.actual).isEqualTo(99L)
        assertThat(error.message).contains("P-02")
        assertThat(session.transactionMismatchCount).isEqualTo(1)
    }

    /**
     * Detection alone is not enough - the endpoint must be drained, or the next
     * transaction inherits the same offset and fails identically forever.
     */
    @Test
    fun `mismatch drains the endpoint so the next transaction can succeed`() {
        val (channel, _, session) = setup()
        channel.queueResponse(PtpResponse.OK, transactionId = 99) // stale
        channel.queueResponse(PtpResponse.OK, transactionId = 77) // more backlog

        assertThrows(PtpException.TransactionMismatch::class.java) {
            session.transact(PtpOperation.GET_STORAGE_IDS)
        }

        // Everything stale was discarded, so a fresh transaction lines up again.
        assertThat(channel.pendingTransfers()).isEqualTo(0)

        channel.queueResponse(PtpResponse.OK, transactionId = 1)
        val result = session.transact(PtpOperation.GET_STORAGE_IDS)
        assertThat(result.responseCode).isEqualTo(PtpResponse.OK)
    }

    @Test
    fun `truncated container header is reported with a pointer to P-01`() {
        val (channel, _, session) = setup()
        channel.enqueueTransfer(byteArrayOf(1, 2, 3)) // nonsense, too short

        val error = assertThrows(PtpException.Malformed::class.java) {
            session.transact(PtpOperation.GET_STORAGE_IDS)
        }

        assertThat(error.message).contains("P-01")
    }

    @Test
    fun `unexpected container type is rejected`() {
        val (channel, _, session) = setup()
        // A Command container coming back from the camera makes no sense.
        channel.enqueueTransfer(PtpContainer.command(PtpOperation.GET_OBJECT, 0).toByteArray())

        assertThrows(PtpException.UnexpectedContainer::class.java) {
            session.transact(PtpOperation.GET_STORAGE_IDS)
        }
    }

    // ================================================================ datasets

    @Test
    fun `device info exposes capability queries used by later milestones`() {
        val payload = deviceInfoPayload(
            operations = intArrayOf(PtpOperation.GET_DEVICE_INFO, PtpOperation.GET_PARTIAL_OBJECT),
        )

        val info = PtpDeviceInfo.parse(payload)

        assertThat(info.supportsOperation(PtpOperation.GET_PARTIAL_OBJECT)).isTrue()
        assertThat(info.supportsOperation(CanonEosOperation.GET_EVENT)).isFalse()
        assertThat(info.supportsEosRemoteMode).isFalse() // M3 would be blocked - useful to know
        assertThat(info.supportsProperty(0xD101)).isTrue()
    }

    @Test
    fun `object info parses the fields M4 depends on`() {
        val w = PtpWriter(128)
        w.u32(0x10001L)                       // storage id
        w.u16(PtpObjectFormat.EXIF_JPEG)      // object format
        w.u16(0)                              // protection
        w.u32(7_340_032L)                     // compressed size - 7MB, a real 24MP JPEG
        w.u16(PtpObjectFormat.EXIF_JPEG)      // thumb format
        w.u32(12_000L); w.u32(160L); w.u32(120L)
        w.u32(6000L); w.u32(4000L); w.u32(24L)
        w.u32(0L)                             // parent
        w.u16(0); w.u32(0L); w.u32(1L)
        w.string("IMG_0001.JPG")
        w.string("20260813T142100")
        w.string("20260813T142100")
        w.string("")

        val info = PtpObjectInfo.parse(w.toByteArray())

        assertThat(info.filename).isEqualTo("IMG_0001.JPG")
        assertThat(info.isJpeg).isTrue()
        assertThat(info.compressedSize).isEqualTo(7_340_032L)
        assertThat(info.imagePixWidth).isEqualTo(6000L)
        assertThat(info.imagePixHeight).isEqualTo(4000L)
        assertThat(info.megapixels).isWithin(0.1).of(24.0)
    }

    /**
     * Regression test for a real hardware finding (2026-08-13).
     *
     * A Canon EOS 200D II reports `vendorExtensionId = 6` (Microsoft) while implementing
     * the full EOS operation set. Code that gated EOS support on the vendor extension
     * field logged "EOS operations will not work" moments before the handshake succeeded.
     * Capability must come from the opcode list, never from the vendor field.
     */
    @Test
    fun `a body reporting the Microsoft vendor extension is still a usable EOS camera`() {
        val w = PtpWriter(256)
        w.u16(100)
        w.u32(PtpVendorExtension.MICROSOFT.toLong()) // what a real 200D II reports
        w.u16(100)
        w.string("")
        w.u16(0)
        val ops = intArrayOf(
            CanonEosOperation.SET_REMOTE_MODE,
            CanonEosOperation.SET_EVENT_MODE,
            CanonEosOperation.GET_EVENT,
        )
        w.u32(ops.size.toLong()); ops.forEach { w.u16(it) }
        w.u32(0L); w.u32(0L); w.u32(0L); w.u32(0L)
        w.string("Canon.Inc"); w.string("Canon EOS 200D II"); w.string("3-1.0.1"); w.string("ffff")

        val info = PtpDeviceInfo.parse(w.toByteArray())

        assertThat(info.declaresCanonVendorExtension).isFalse() // reports Microsoft
        assertThat(info.isCanonEos).isTrue()                    // but IS an EOS body
        assertThat(info.supportsEosRemoteMode).isTrue()
    }

    @Test
    fun `capability dump renders the committable document`() {
        val info = PtpDeviceInfo.parse(deviceInfoPayload())

        val dump = DeviceCapabilityDump.render(info)

        assertThat(dump).contains("Canon EOS 200D II")
        assertThat(dump).contains("EOS_SetRemoteMode")
        assertThat(dump).contains("Readiness checks")
        // Opcodes we transcribed but this body does not report must be called out.
        assertThat(dump).contains("Transcribed Canon opcodes NOT reported")
        assertThat(dump).contains("EOS_GetViewFinderData")
        assertThat(DeviceCapabilityDump.suggestedFilename(info))
            .isEqualTo("canon-inc-canon-eos-200d-ii-capabilities.md")
    }
}
