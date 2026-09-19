package com.srisarani.fotozenai.eventpipeline

import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Photo-window maths for occasion frames (JustMarried-style caption bars).
 *
 * Matches zenai `frameCompositor.ts`: find the transparent hole, ignore
 * full-bleed borders, map the hole onto the letterboxed canvas, then
 * cover-crop the capture into that window — not the whole print sheet.
 */
object EventFrameHole {
    const val ALPHA_MAX = 32
    const val MIN_HOLE_AREA_FRACTION = 0.05
    const val FULL_BLEED_AREA_FRACTION = 0.85
    const val FULL_BLEED_EDGE_MARGIN = 0.04

    data class Box(val left: Int, val top: Int, val width: Int, val height: Int) {
        val right: Int get() = left + width
        val bottom: Int get() = top + height
    }

    fun alpha(pixel: Int): Int = (pixel ushr 24) and 0xFF

    /**
     * Bounding box of near-transparent pixels. Null when the overlay has no
     * usable photo window (fully opaque, or a speck smaller than 5%).
     */
    fun findTransparentHole(width: Int, height: Int, pixels: IntArray): Box? {
        if (width <= 0 || height <= 0 || pixels.size < width * height) return null
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        var count = 0
        for (y in 0 until height) {
            val row = y * width
            for (x in 0 until width) {
                if (alpha(pixels[row + x]) <= ALPHA_MAX) {
                    count++
                    if (x < minX) minX = x
                    if (y < minY) minY = y
                    if (x > maxX) maxX = x
                    if (y > maxY) maxY = y
                }
            }
        }
        val area = width * height
        if (maxX < 0 || count.toDouble() / area < MIN_HOLE_AREA_FRACTION) {
            return null
        }
        return Box(minX, minY, maxX - minX + 1, maxY - minY + 1)
    }

    /** True when the hole is an inset window, not a near-full-bleed cutout. */
    fun isPartialPhotoHole(hole: Box, canvasW: Int, canvasH: Int): Boolean {
        if (canvasW <= 0 || canvasH <= 0) return false
        val areaFrac = (hole.width.toDouble() * hole.height) / (canvasW * canvasH)
        if (areaFrac >= FULL_BLEED_AREA_FRACTION) return false
        val marginX = canvasW * FULL_BLEED_EDGE_MARGIN
        val marginY = canvasH * FULL_BLEED_EDGE_MARGIN
        return hole.left > marginX ||
            hole.top > marginY ||
            hole.right < canvasW - marginX ||
            hole.bottom < canvasH - marginY
    }

    /** Scale a hole from overlay pixels into the letterboxed dest on the canvas. */
    fun mapToDest(
        hole: Box,
        srcW: Int,
        srcH: Int,
        destLeft: Int,
        destTop: Int,
        destW: Int,
        destH: Int,
    ): Box {
        if (srcW <= 0 || srcH <= 0 || destW <= 0 || destH <= 0) {
            return Box(destLeft, destTop, max(1, destW), max(1, destH))
        }
        val left = destLeft + (hole.left.toDouble() * destW / srcW).roundToInt()
        val top = destTop + (hole.top.toDouble() * destH / srcH).roundToInt()
        val width = max(1, (hole.width.toDouble() * destW / srcW).roundToInt())
        val height = max(1, (hole.height.toDouble() * destH / srcH).roundToInt())
        return clampToDest(Box(left, top, width, height), destLeft, destTop, destW, destH)
    }

    /**
     * Source crop that cover-fills [destW]×[destH]. Centered — same gravity
     * zenai uses for a portrait photo window.
     */
    fun coverCropSource(srcW: Int, srcH: Int, destW: Int, destH: Int): Box {
        if (srcW <= 0 || srcH <= 0 || destW <= 0 || destH <= 0) {
            return Box(0, 0, max(1, srcW), max(1, srcH))
        }
        val srcRatio = srcW.toDouble() / srcH.toDouble()
        val dstRatio = destW.toDouble() / destH.toDouble()
        return if (srcRatio > dstRatio) {
            val cropWidth = max(1, (srcH * dstRatio).roundToInt().coerceAtMost(srcW))
            val inset = (srcW - cropWidth) / 2
            Box(inset, 0, cropWidth, srcH)
        } else {
            val cropHeight = max(1, (srcW / dstRatio).roundToInt().coerceAtMost(srcH))
            val inset = (srcH - cropHeight) / 2
            Box(0, inset, srcW, cropHeight)
        }
    }

    private fun clampToDest(
        hole: Box,
        destLeft: Int,
        destTop: Int,
        destW: Int,
        destH: Int,
    ): Box {
        val left = hole.left.coerceIn(destLeft, destLeft + destW - 1)
        val top = hole.top.coerceIn(destTop, destTop + destH - 1)
        val right = hole.right.coerceIn(left + 1, destLeft + destW)
        val bottom = hole.bottom.coerceIn(top + 1, destTop + destH)
        return Box(left, top, right - left, bottom - top)
    }
}
