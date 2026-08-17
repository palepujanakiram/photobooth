package com.srisarani.fotozenai.canon.eos

import com.google.common.truth.Truth.assertThat
import com.srisarani.fotozenai.canon.ptp.PtpWriter
import org.junit.Test

/**
 * The plan's M6 warning, tested: *"the payload is not a bare JPEG — it has a length/type
 * header, and may carry multiple sub-blocks."*
 *
 * Handing the whole payload to `BitmapFactory` returns null, and the obvious next guess -
 * skipping a fixed-size header - works right up until the camera includes a different mix
 * of blocks. These tests pin the actual structure.
 */
class EvfFrameParserTest {

    private fun block(type: Int, data: ByteArray): ByteArray =
        PtpWriter().u32((8 + data.size).toLong()).u32(type.toLong()).bytes(data).toByteArray()

    /** A minimal but structurally valid JPEG: SOI … EOI. */
    private fun fakeJpeg(size: Int = 64): ByteArray =
        byteArrayOf(0xFF.toByte(), 0xD8.toByte()) +
            ByteArray(size - 4) { (it % 251).toByte() } +
            byteArrayOf(0xFF.toByte(), 0xD9.toByte())

    @Test
    fun `extracts the jpeg block from a single-block payload`() {
        val jpeg = fakeJpeg()

        val extracted = EvfFrameParser.extractJpeg(block(EvfBlockType.JPEG_IMAGE, jpeg))

        assertThat(extracted).isEqualTo(jpeg)
    }

    /**
     * The realistic case: the camera sends the frame alongside histograms and focus info.
     * The JPEG is not necessarily first.
     */
    @Test
    fun `finds the jpeg among histogram and focus blocks`() {
        val jpeg = fakeJpeg(128)
        val payload = block(EvfBlockType.HISTOGRAM_Y, ByteArray(256)) +
            block(EvfBlockType.ZOOM_RECT, ByteArray(16)) +
            block(EvfBlockType.JPEG_IMAGE, jpeg) +
            block(EvfBlockType.FOCUS_INFO, ByteArray(32))

        assertThat(EvfFrameParser.extractJpeg(payload)).isEqualTo(jpeg)
    }

    @Test
    fun `parses every block in order`() {
        val payload = block(EvfBlockType.JPEG_IMAGE, fakeJpeg()) +
            block(EvfBlockType.HISTOGRAM_Y, ByteArray(16)) +
            block(EvfBlockType.FOCUS_INFO, ByteArray(8))

        val blocks = EvfFrameParser.parseBlocks(payload)

        assertThat(blocks.map { it.first })
            .containsExactly(EvfBlockType.JPEG_IMAGE, EvfBlockType.HISTOGRAM_Y, EvfBlockType.FOCUS_INFO)
            .inOrder()
    }

    /**
     * The specific mistake this parser exists to prevent: treating the raw payload as a
     * JPEG. The container header means it never starts with SOI.
     */
    @Test
    fun `raw payload is not itself a valid jpeg`() {
        val payload = block(EvfBlockType.JPEG_IMAGE, fakeJpeg())

        assertThat(EvfFrameParser.looksLikeJpeg(payload)).isFalse()
        assertThat(EvfFrameParser.looksLikeJpeg(EvfFrameParser.extractJpeg(payload)!!)).isTrue()
    }

    @Test
    fun `returns null when the response carries no image block`() {
        val payload = block(EvfBlockType.HISTOGRAM_Y, ByteArray(64)) +
            block(EvfBlockType.FOCUS_INFO, ByteArray(16))

        assertThat(EvfFrameParser.extractJpeg(payload)).isNull()
    }

    @Test
    fun `empty payload yields nothing`() {
        assertThat(EvfFrameParser.parseBlocks(ByteArray(0))).isEmpty()
        assertThat(EvfFrameParser.extractJpeg(ByteArray(0))).isNull()
    }

    // ================================================================ robustness

    /**
     * This runs 30 times a second inside the polling loop. Throwing there kills the
     * stream, so malformed input must degrade rather than propagate.
     */
    @Test
    fun `random bytes never throw`() {
        val random = java.util.Random(20260813)
        repeat(400) {
            val bytes = ByteArray(random.nextInt(300)).also { random.nextBytes(it) }
            EvfFrameParser.parseBlocks(bytes)
            EvfFrameParser.extractJpeg(bytes)
        }
    }

    @Test
    fun `implausible block size stops parsing without throwing`() {
        val payload = PtpWriter().u32(0x7FFFFFFFL).u32(1L).toByteArray()

        assertThat(EvfFrameParser.parseBlocks(payload)).isEmpty()
    }

    @Test
    fun `block declaring more data than remains is dropped but earlier blocks survive`() {
        val jpeg = fakeJpeg()
        val truncated = PtpWriter().u32(9999L).u32(2L).bytes(ByteArray(10)).toByteArray()

        val blocks = EvfFrameParser.parseBlocks(block(EvfBlockType.JPEG_IMAGE, jpeg) + truncated)

        assertThat(blocks).hasSize(1)
        assertThat(blocks.single().second).isEqualTo(jpeg)
    }

    @Test
    fun `zero size terminates the block list`() {
        val jpeg = fakeJpeg()
        val payload = block(EvfBlockType.JPEG_IMAGE, jpeg) +
            PtpWriter().u32(0L).toByteArray() +
            block(EvfBlockType.HISTOGRAM_Y, ByteArray(16))

        assertThat(EvfFrameParser.parseBlocks(payload)).hasSize(1)
    }

    @Test
    fun `trailing bytes shorter than a header are ignored`() {
        val payload = block(EvfBlockType.JPEG_IMAGE, fakeJpeg()) + byteArrayOf(1, 2, 3)

        assertThat(EvfFrameParser.parseBlocks(payload)).hasSize(1)
    }

    @Test
    fun `jpeg detection requires the SOI marker`() {
        assertThat(EvfFrameParser.looksLikeJpeg(byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0, 0))).isTrue()
        assertThat(EvfFrameParser.looksLikeJpeg(byteArrayOf(0x89.toByte(), 0x50))).isFalse()
        assertThat(EvfFrameParser.looksLikeJpeg(byteArrayOf(0xFF.toByte()))).isFalse()
        assertThat(EvfFrameParser.looksLikeJpeg(ByteArray(0))).isFalse()
    }
}
