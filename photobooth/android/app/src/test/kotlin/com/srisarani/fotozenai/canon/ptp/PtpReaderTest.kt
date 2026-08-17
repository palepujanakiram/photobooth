package com.srisarani.fotozenai.canon.ptp

import com.google.common.truth.Truth.assertThat
import org.junit.Assert.assertThrows
import org.junit.Test

class PtpReaderTest {

    // ================================================================ integers

    @Test
    fun `reads little-endian integers`() {
        val r = PtpReader(byteArrayOf(0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07))

        assertThat(r.u8()).isEqualTo(0x01)
        assertThat(r.u16()).isEqualTo(0x0302)
        assertThat(r.u32()).isEqualTo(0x07060504L)
    }

    @Test
    fun `u32 spans the full unsigned range`() {
        // 0xFFFFFFFF as an Int would be -1. Transaction IDs and object handles live up
        // here, so the Long return type is load-bearing, not defensive.
        val r = PtpReader(byteArrayOf(0xFF.toByte(), 0xFF.toByte(), 0xFF.toByte(), 0xFF.toByte()))

        assertThat(r.u32()).isEqualTo(4_294_967_295L)
    }

    @Test
    fun `u16 does not sign extend`() {
        val r = PtpReader(byteArrayOf(0xFF.toByte(), 0xFF.toByte()))
        assertThat(r.u16()).isEqualTo(65535)
    }

    @Test
    fun `u64 reads eight bytes little-endian`() {
        val r = PtpReader(byteArrayOf(0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01))
        assertThat(r.u64()).isEqualTo(0x0102030405060708L)
    }

    @Test
    fun `reading past the end reports the offset`() {
        val r = PtpReader(byteArrayOf(0x01, 0x02))
        val error = assertThrows(PtpException.Malformed::class.java) { r.u32() }

        assertThat(error.message).contains("offset 0")
        assertThat(error.message).contains("only 2 remain")
    }

    // ================================================================ P-03 strings

    /**
     * P-03 - the classic first bug.
     *
     * The length prefix counts CHARACTERS INCLUDING the null terminator, not bytes.
     * "Canon" is 5 chars, so the prefix is 6, and the string occupies 1 + 6*2 = 13 bytes.
     */
    @Test
    fun `string length prefix counts characters including the terminator`() {
        val bytes = ptpString("Canon")

        assertThat(bytes.size).isEqualTo(13)
        assertThat(bytes[0].toInt()).isEqualTo(6) // 5 chars + terminator

        val r = PtpReader(bytes)
        assertThat(r.string()).isEqualTo("Canon")
        assertThat(r.remaining).isEqualTo(0) // cursor landed exactly at the end
    }

    /**
     * THE regression test for P-03.
     *
     * A parser that treats the prefix as a byte count leaves the cursor mid-string, so the
     * NEXT field is garbage. Two strings back to back catch that immediately - which is
     * exactly how it manifests in GetDeviceInfo, where manufacturer parses oddly and model,
     * version and serial are nonsense.
     */
    @Test
    fun `consecutive strings both parse correctly`() {
        val bytes = ptpString("Canon") + ptpString("Canon EOS 200D II") + ptpString("3-1-0")

        val r = PtpReader(bytes)
        assertThat(r.string()).isEqualTo("Canon")
        assertThat(r.string()).isEqualTo("Canon EOS 200D II")
        assertThat(r.string()).isEqualTo("3-1-0")
        assertThat(r.remaining).isEqualTo(0)
    }

    @Test
    fun `a string is followed by an intact integer field`() {
        // The tightest possible check that the cursor landed in the right place.
        val bytes = ptpString("EOS") + byteArrayOf(0x78, 0x56, 0x34, 0x12)

        val r = PtpReader(bytes)
        assertThat(r.string()).isEqualTo("EOS")
        assertThat(r.u32()).isEqualTo(0x12345678L)
    }

    @Test
    fun `zero length prefix means absent string and consumes one byte`() {
        val bytes = byteArrayOf(0x00, 0x42)

        val r = PtpReader(bytes)
        assertThat(r.string()).isEmpty()
        assertThat(r.u8()).isEqualTo(0x42) // only the length byte was consumed
    }

    @Test
    fun `prefix of one means empty string with a terminator`() {
        // Distinct from a prefix of 0: this consumes 1 + 2 = 3 bytes.
        val bytes = byteArrayOf(0x01, 0x00, 0x00, 0x42)

        val r = PtpReader(bytes)
        assertThat(r.string()).isEmpty()
        assertThat(r.u8()).isEqualTo(0x42)
    }

    @Test
    fun `parses non-ascii characters`() {
        // UTF-16LE, so anything in the BMP round-trips.
        val bytes = ptpString("Nikon éè 日本")

        assertThat(PtpReader(bytes).string()).isEqualTo("Nikon éè 日本")
    }

    @Test
    fun `truncated string is rejected rather than silently short`() {
        // Claims 6 characters but only two code units are present.
        val bytes = byteArrayOf(0x06, 0x43, 0x00, 0x61, 0x00)

        assertThrows(PtpException.Malformed::class.java) { PtpReader(bytes).string() }
    }

    // ================================================================ arrays

    @Test
    fun `parses a u16 array`() {
        val bytes = ptpU16Array(intArrayOf(0x1001, 0x1002, 0x9114))

        assertThat(PtpReader(bytes).u16Array().toList())
            .containsExactly(0x1001, 0x1002, 0x9114).inOrder()
    }

    @Test
    fun `parses an empty array`() {
        val bytes = ptpU16Array(intArrayOf())

        assertThat(PtpReader(bytes).u16Array()).isEmpty()
    }

    @Test
    fun `parses a u32 array`() {
        val bytes = PtpWriter().u32(2L).u32(0xAABBCCDDL).u32(0x11223344L).toByteArray()

        assertThat(PtpReader(bytes).u32Array().toList())
            .containsExactly(0xAABBCCDDL, 0x11223344L).inOrder()
    }

    /**
     * An implausible array count is the loudest symptom of a cursor that drifted upstream -
     * usually P-03. The error names that cause, because otherwise it reads as an unrelated
     * array bug and sends you looking in the wrong place.
     */
    @Test
    fun `implausible array count points at upstream cursor drift`() {
        val bytes = PtpWriter().u32(0x7FFFFFFFL).toByteArray()

        val error = assertThrows(PtpException.Malformed::class.java) { PtpReader(bytes).u16Array() }

        assertThat(error.message).contains("Implausible array count")
        assertThat(error.message).contains("P-03")
    }

    @Test
    fun `array shorter than its declared count is rejected`() {
        val bytes = PtpWriter().u32(10L).u16(0x1001).toByteArray()

        assertThrows(PtpException.Malformed::class.java) { PtpReader(bytes).u16Array() }
    }

    // ================================================================ writer

    @Test
    fun `writer round-trips through reader`() {
        val bytes = PtpWriter()
            .u8(0x12)
            .u16(0x3456)
            .u32(0x789ABCDEL)
            .string("EOS 200D II")
            .toByteArray()

        val r = PtpReader(bytes)
        assertThat(r.u8()).isEqualTo(0x12)
        assertThat(r.u16()).isEqualTo(0x3456)
        assertThat(r.u32()).isEqualTo(0x789ABCDEL)
        assertThat(r.string()).isEqualTo("EOS 200D II")
        assertThat(r.remaining).isEqualTo(0)
    }

    @Test
    fun `writer emits the character-count convention`() {
        val bytes = PtpWriter().string("Hi").toByteArray()

        assertThat(bytes[0].toInt()).isEqualTo(3) // 2 chars + terminator
        assertThat(bytes.size).isEqualTo(7) // 1 + 3*2
    }

    @Test
    fun `bytes and skip move the cursor by exactly the requested amount`() {
        val r = PtpReader(byteArrayOf(1, 2, 3, 4, 5, 6))

        assertThat(r.bytes(2).toList()).containsExactly(1.toByte(), 2.toByte()).inOrder()
        r.skip(2)
        assertThat(r.u8()).isEqualTo(5)
        assertThat(r.remaining).isEqualTo(1)
    }

    // ================================================================ helpers

    companion object {
        /** Builds a PTP string exactly as the spec defines it, independent of our reader. */
        fun ptpString(value: String): ByteArray {
            val out = ByteArray(1 + (value.length + 1) * 2)
            out[0] = (value.length + 1).toByte()
            var pos = 1
            value.forEach { char ->
                out[pos++] = (char.code and 0xFF).toByte()
                out[pos++] = ((char.code shr 8) and 0xFF).toByte()
            }
            out[pos] = 0
            out[pos + 1] = 0
            return out
        }

        fun ptpU16Array(values: IntArray): ByteArray {
            val writer = PtpWriter()
            writer.u32(values.size.toLong())
            values.forEach { writer.u16(it) }
            return writer.toByteArray()
        }
    }
}
