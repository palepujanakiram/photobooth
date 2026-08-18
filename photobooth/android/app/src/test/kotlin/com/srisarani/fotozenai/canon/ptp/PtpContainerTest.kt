package com.srisarani.fotozenai.canon.ptp

import com.google.common.truth.Truth.assertThat
import org.junit.Assert.assertThrows
import org.junit.Test

class PtpContainerTest {

    @Test
    fun `command container has the documented wire layout`() {
        val container = PtpContainer.command(PtpOperation.OPEN_SESSION, transactionId = 0, 1L)
        val bytes = container.toByteArray()

        // 12-byte header + one u32 parameter
        assertThat(bytes.size).isEqualTo(16)

        val r = PtpReader(bytes)
        assertThat(r.u32()).isEqualTo(16L) // length INCLUDES the header
        assertThat(r.u16()).isEqualTo(PtpContainerType.COMMAND)
        assertThat(r.u16()).isEqualTo(PtpOperation.OPEN_SESSION)
        assertThat(r.u32()).isEqualTo(0L)
        assertThat(r.u32()).isEqualTo(1L) // session id
    }

    /**
     * The length field counting the header is the detail worth pinning. Reading `length`
     * bytes of payload instead of `length - 12` overruns by exactly one header on every
     * transaction, which desynchronises the stream immediately.
     */
    @Test
    fun `declared length includes the header`() {
        val container = PtpContainer.data(PtpOperation.GET_OBJECT, 5, ByteArray(100))

        assertThat(container.totalLength).isEqualTo(112)
        assertThat(PtpContainer.peekLength(container.toByteArray())).isEqualTo(112L)
    }

    @Test
    fun `round-trips through parse`() {
        val original = PtpContainer.command(PtpOperation.GET_OBJECT_HANDLES, 42, 0x10001L, 0L, 0L)

        val parsed = PtpContainer.parse(original.toByteArray())

        assertThat(parsed).isEqualTo(original)
        assertThat(parsed.transactionId).isEqualTo(42L)
        assertThat(parsed.parameters.toList()).containsExactly(0x10001L, 0L, 0L).inOrder()
    }

    @Test
    fun `parses a response with no parameters`() {
        val bytes = PtpWriter()
            .u32(12L).u16(PtpContainerType.RESPONSE).u16(PtpResponse.OK).u32(7L)
            .toByteArray()

        val container = PtpContainer.parse(bytes)

        assertThat(container.isOk).isTrue()
        assertThat(container.parameters).isEmpty()
        assertThat(container.transactionId).isEqualTo(7L)
    }

    @Test
    fun `parses a data container payload`() {
        val payload = ByteArray(50) { it.toByte() }
        val bytes = PtpContainer.data(PtpOperation.GET_DEVICE_INFO, 3, payload).toByteArray()

        val container = PtpContainer.parse(bytes)

        assertThat(container.type).isEqualTo(PtpContainerType.DATA)
        assertThat(container.payload).isEqualTo(payload)
    }

    @Test
    fun `parses from a non-zero offset`() {
        val prefix = byteArrayOf(0xAA.toByte(), 0xBB.toByte())
        val bytes = prefix + PtpContainer.command(PtpOperation.CLOSE_SESSION, 9).toByteArray()

        val container = PtpContainer.parse(bytes, offset = 2)

        assertThat(container.code).isEqualTo(PtpOperation.CLOSE_SESSION)
        assertThat(container.transactionId).isEqualTo(9L)
    }

    // ================================================================ validation

    @Test
    fun `rejects a truncated header`() {
        val error = assertThrows(PtpException.Malformed::class.java) {
            PtpContainer.parse(byteArrayOf(1, 2, 3, 4))
        }
        assertThat(error.message).contains("truncated")
    }

    /**
     * P-08: a container that declares more than arrived means the transfer was truncated.
     * Accepting it silently is the dangerous case, because nothing errors and the payload
     * is simply short.
     */
    @Test
    fun `rejects a container declaring more than arrived`() {
        val bytes = PtpWriter()
            .u32(500L) // claims 500 bytes
            .u16(PtpContainerType.DATA).u16(PtpOperation.GET_OBJECT).u32(1L)
            .bytes(ByteArray(20))
            .toByteArray()

        val error = assertThrows(PtpException.Malformed::class.java) { PtpContainer.parse(bytes) }

        assertThat(error.message).contains("declares length 500")
        assertThat(error.message).contains("P-08")
    }

    @Test
    fun `rejects a length smaller than the header`() {
        val bytes = PtpWriter()
            .u32(8L)
            .u16(PtpContainerType.RESPONSE).u16(PtpResponse.OK).u32(1L)
            .toByteArray()

        assertThrows(PtpException.Malformed::class.java) { PtpContainer.parse(bytes) }
    }

    @Test
    fun `rejects more than five parameters`() {
        assertThrows(IllegalArgumentException::class.java) {
            PtpContainer.command(PtpOperation.GET_OBJECT, 1, 1, 2, 3, 4, 5, 6)
        }
    }

    @Test
    fun `parameters are capped at five even if the payload is longer`() {
        val container = PtpContainer(
            type = PtpContainerType.RESPONSE,
            code = PtpResponse.OK,
            transactionId = 1,
            payload = ByteArray(40), // 10 u32s
        )

        assertThat(container.parameters).hasLength(PtpHeader.MAX_PARAMS)
    }

    // ================================================================ logging

    @Test
    fun `toString names standard and canon operations`() {
        assertThat(PtpContainer.command(PtpOperation.OPEN_SESSION, 0, 1L).toString())
            .contains("OpenSession")

        assertThat(PtpContainer.command(CanonEosOperation.SET_REMOTE_MODE, 1, 1L).toString())
            .contains("EOS_SetRemoteMode")
    }

    @Test
    fun `toString names response codes rather than showing bare hex`() {
        val response = PtpContainer(PtpContainerType.RESPONSE, PtpResponse.DEVICE_BUSY, 5)

        assertThat(response.toString()).contains("DeviceBusy")
    }

    @Test
    fun `unknown opcode still renders usefully`() {
        assertThat(PtpOperation.name(0x9999)).isEqualTo("Operation(0x9999)")
    }
}
