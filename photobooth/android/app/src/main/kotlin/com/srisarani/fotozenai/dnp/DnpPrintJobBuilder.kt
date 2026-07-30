package com.srisarani.fotozenai.dnp

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Locale

/**
 * Builds a DNP dye-sub print job (Y/M/C planes + CNTRL START) from raster planes.
 */
object DnpPrintJobBuilder {

    private const val PLANE_HEADER_LEN = 40
    private const val COLOR_MAP_LEN = 1024
    private const val PLANE_META_LEN = PLANE_HEADER_LEN + COLOR_MAP_LEN
    private const val BMP_FILE_HEADER_LEN = 14
    private const val PLANE_TRAILER_LEN = 10
    private const val PPM_300 = 11808

    fun buildJob(
        yPlane: ByteArray,
        mPlane: ByteArray,
        cPlane: ByteArray,
        width: Int,
        height: Int,
    ): ByteArray {
        require(yPlane.size == width * height)
        require(mPlane.size == width * height)
        require(cPlane.size == width * height)

        val planeLen = PLANE_META_LEN + yPlane.size
        val chunks = mutableListOf<ByteArray>()
        chunks += buildPlaneChunk('Y', planeLen, width, height, yPlane)
        chunks += buildPlaneChunk('M', planeLen, width, height, mPlane)
        chunks += buildPlaneChunk('C', planeLen, width, height, cPlane)
        chunks += buildStartChunk()

        val totalSize = chunks.sumOf { it.size }
        val job = ByteArray(totalSize)
        var offset = 0
        for (chunk in chunks) {
            System.arraycopy(chunk, 0, job, offset, chunk.size)
            offset += chunk.size
        }
        return job
    }

    private fun buildPlaneChunk(
        channel: Char,
        planeLen: Int,
        width: Int,
        height: Int,
        pixels: ByteArray,
    ): ByteArray {
        val payloadLen = BMP_FILE_HEADER_LEN + planeLen + PLANE_TRAILER_LEN
        val chunk = ByteArray(32 + payloadLen)
        writeCommandHeader(chunk, "IMAGE", "${channel}PLANE", payloadLen)

        // BMP "file size" field must cover header + plane body + 10-byte trailer (reference driver).
        val bmpHeader = buildBmpFileHeader(payloadLen)
        System.arraycopy(bmpHeader, 0, chunk, 32, bmpHeader.size)

        val planeBody = buildPlaneBody(width, height, pixels)
        System.arraycopy(planeBody, 0, chunk, 32 + bmpHeader.size, planeBody.size)

        return chunk
    }

    /** Legacy `\033PCNTRL START ` in the job stream, zero-padded to 32 bytes (reference driver). */
    private fun buildStartChunk(): ByteArray {
        val chunk = ByteArray(32) { 0x00 }
        val text = "\u001BPCNTRL START "
        text.toByteArray(Charsets.US_ASCII).copyInto(chunk, 0)
        return chunk
    }

    private fun writeCommandHeader(
        dest: ByteArray,
        arg1: String,
        arg2: String,
        payloadLen: Int,
    ) {
        dest.fill(0x20)
        dest[0] = 0x1B
        dest[1] = 0x50.toByte()
        arg1.toByteArray().copyInto(dest, 2, 0, minOf(arg1.length, 6))
        arg2.toByteArray().copyInto(dest, 8, 0, minOf(arg2.length, 16))
        String.format(Locale.US, "%08d", payloadLen).toByteArray()
            .copyInto(dest, 24, 0, 8)
    }

    private fun buildBmpFileHeader(totalSize: Int): ByteArray {
        val header = ByteArray(BMP_FILE_HEADER_LEN)
        header[0] = 0x42
        header[1] = 0x4D
        putLe32(header, 2, totalSize)
        header[10] = 0x40
        header[11] = 0x04
        return header
    }

    private fun buildPlaneBody(width: Int, height: Int, pixels: ByteArray): ByteArray {
        val body = ByteArray(PLANE_META_LEN + pixels.size)
        writePlaneInfoHeader(body, width, height)
        writeColorMap(body, PLANE_HEADER_LEN)
        System.arraycopy(pixels, 0, body, PLANE_META_LEN, pixels.size)
        return body
    }

    private fun writePlaneInfoHeader(dest: ByteArray, width: Int, height: Int) {
        putLe32(dest, 0, PLANE_HEADER_LEN)
        putLe32(dest, 4, width)
        putLe32(dest, 8, height)
        dest[12] = 0x01
        dest[13] = 0x00
        dest[14] = 0x08
        dest[15] = 0x00
        putLe32(dest, 28, PPM_300)
        putLe32(dest, 32, PPM_300)
        dest[36] = 0x01
        dest[37] = 0x00
    }

    /** Linear inverted LUT used by the Windows driver spool format. */
    private fun writeColorMap(dest: ByteArray, offset: Int) {
        for (i in 0 until 256) {
            val value = (255 - i).toByte()
            val base = offset + i * 4
            dest[base] = value
            dest[base + 1] = value
            dest[base + 2] = value
            dest[base + 3] = 0
        }
    }

    private fun putLe32(dest: ByteArray, offset: Int, value: Int) {
        ByteBuffer.wrap(dest, offset, 4).order(ByteOrder.LITTLE_ENDIAN).putInt(value)
    }

    /** Split ARGB into Y/M/C planes for the Windows spool LUT (inverted 256-entry map). */
    fun rgbToPlanes(pixels: IntArray, width: Int, height: Int): Triple<ByteArray, ByteArray, ByteArray> {
        val count = width * height
        val y = ByteArray(count)
        val m = ByteArray(count)
        val c = ByteArray(count)
        for (i in 0 until count) {
            val pixel = pixels[i]
            val r = (pixel shr 16) and 0xFF
            val g = (pixel shr 8) and 0xFF
            val b = pixel and 0xFF
            // LUT maps plane value v → ink density (255 - v). Store R/G/B directly so
            // CMY ink amounts become (255-R), (255-G), (255-B) after LUT application.
            c[i] = r.toByte()
            m[i] = g.toByte()
            y[i] = b.toByte()
        }
        return Triple(y, m, c)
    }
}
