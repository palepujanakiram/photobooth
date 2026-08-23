package com.srisarani.fotozenai.canon.eos

import com.srisarani.fotozenai.canon.CanonLog
import com.srisarani.fotozenai.canon.ptp.PtpReader

/**
 * Block types inside a viewfinder-data payload.
 *
 * ⚠️ Transcribed; only [JPEG_IMAGE] is confirmed by use. The others are named so the
 * parser can skip them knowingly rather than treating them as corruption.
 */
object EvfBlockType {
    /** The actual JPEG frame. The only block we currently consume. */
    const val JPEG_IMAGE = 1
    const val HISTOGRAM_Y = 2
    const val HISTOGRAM_R = 3
    const val HISTOGRAM_G = 4
    const val HISTOGRAM_B = 5
    const val ZOOM_RECT = 6
    const val FOCUS_INFO = 8
    const val CROP_RECT = 11
}

/** Values for [EosProperty.EVF_OUTPUT_DEVICE]. ⚠️ VERIFY against `ptp.h`. */
object EvfOutputDevice {
    const val OFF = 0
    const val CAMERA_TFT = 1

    /**
     * Route live view to the host over USB **only**.
     *
     * > ⚠️ `C-19`, observed on hardware 2026-08-14: with PC-only routing the 200D II blanks
     * > its rear screen and displays **"Busy"** for as long as live view runs. To anyone
     * > standing at the booth the camera looks hung. It is not — but it is indistinguishable
     * > from hung, and a guest or operator will start pressing things.
     */
    const val PC = 2

    /**
     * Route to the camera's screen **and** the host.
     *
     * Preferred for a booth: frames still stream over USB, and the body keeps a live
     * viewfinder instead of the "Busy" placard. This is the same escalation the
     * `fotozen-sidecar` gphoto2 path uses (`output=TFT + PC`) after plain PC routing
     * misbehaves.
     */
    const val CAMERA_TFT_AND_PC = CAMERA_TFT or PC
}

/**
 * Parses a Canon viewfinder-data payload.
 *
 * ## The payload is NOT a bare JPEG
 *
 * The plan calls this out and it is the first thing that trips people up. The response is
 * a sequence of length-prefixed blocks, structurally identical to the EOS event array:
 *
 * ```
 * u32 size    total block length INCLUDING these 8 header bytes
 * u32 type    EvfBlockType - 1 is the JPEG frame
 * ...         payload, (size - 8) bytes
 * ```
 *
 * A single response can carry the frame plus histograms, a zoom rectangle and focus
 * information. Handing the whole payload to `BitmapFactory` produces null, and the obvious
 * next guess — skipping a fixed header — breaks as soon as the camera includes a different
 * mix of blocks.
 *
 * Pure and Android-free so it is unit tested; the bitmap decode sits on top.
 */
object EvfFrameParser {

    private const val BLOCK_HEADER_SIZE = 8
    private const val MAX_BLOCK_SIZE = 32 * 1024 * 1024

    /** Every block found, in order. */
    fun parseBlocks(payload: ByteArray): List<Pair<Int, ByteArray>> {
        val blocks = mutableListOf<Pair<Int, ByteArray>>()
        val reader = PtpReader(payload)
        while (reader.remaining >= BLOCK_HEADER_SIZE) {
            val block = readNextBlock(reader) ?: break
            blocks += block
        }
        return blocks
    }

    /** Extracts just the JPEG frame, or null if this response carried none. */
    fun extractJpeg(payload: ByteArray): ByteArray? =
        parseBlocks(payload).firstOrNull { it.first == EvfBlockType.JPEG_IMAGE }?.second

    /** True when the bytes start with a JPEG SOI marker. A cheap sanity check. */
    fun looksLikeJpeg(bytes: ByteArray): Boolean =
        bytes.size >= 2 && bytes[0] == 0xFF.toByte() && bytes[1] == 0xD8.toByte()

    private fun readNextBlock(reader: PtpReader): Pair<Int, ByteArray>? {
        val size = readBlockSize(reader) ?: return null
        val type = readU32OrNull(reader)?.toInt() ?: return null
        val dataSize = (size - BLOCK_HEADER_SIZE).toInt()
        if (dataSize > reader.remaining) {
            CanonLog.w(
                "EVF block type %d declares %dB but %dB remain",
                type,
                dataSize,
                reader.remaining,
            )
            return null
        }
        val data = if (dataSize > 0) reader.bytes(dataSize) else ByteArray(0)
        return type to data
    }

    private fun readBlockSize(reader: PtpReader): Long? {
        val size = readU32OrNull(reader) ?: return null
        if (size == 0L) return null
        if (size < BLOCK_HEADER_SIZE || size > MAX_BLOCK_SIZE) {
            CanonLog.w("Implausible EVF block size %d - stopping", size)
            return null
        }
        return size
    }

    private fun readU32OrNull(reader: PtpReader): Long? =
        try {
            reader.u32()
        } catch (_: Exception) {
            null
        }
}
