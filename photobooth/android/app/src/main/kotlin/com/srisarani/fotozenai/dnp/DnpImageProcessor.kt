package com.srisarani.fotozenai.dnp

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.ImageDecoder
import android.graphics.Paint
import java.io.File
import kotlin.math.max
import kotlin.math.min

/**
 * Prepares a source photo for DNP printing — mirrors the Canon Selphy pipeline
 * (EXIF-aware decode, orientation, cover/contain-fit, filters, borders).
 *
 * When [memoryEfficient] is true (Android TV / low-RAM devices), decode is
 * subsampled and filters are applied in a single draw pass to limit peak RAM.
 */
object DnpImageProcessor {

    fun prepareBitmap(
        sourcePath: String,
        size: DnpPrintSize,
        filter: String,
        brightness: Int,
        bordered: Boolean,
        memoryEfficient: Boolean = false,
        networkPrintSize: String? = null,
    ): Bitmap {
        val targetW = size.width
        val targetH = size.height
        val maxDecodeSide = if (memoryEfficient) {
            max(targetW, targetH) * 2
        } else {
            max(targetW, targetH) * 3
        }

        val source = ImageDecoder.createSource(File(sourcePath))
        var bmp = ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            val srcW = info.size.width
            val srcH = info.size.height
            val longest = max(srcW, srcH)
            if (longest > maxDecodeSide) {
                val scale = maxDecodeSide.toFloat() / longest
                decoder.setTargetSize(
                    max(1, (srcW * scale).toInt()),
                    max(1, (srcH * scale).toInt()),
                )
            }
        }

        if (shouldRotateForPrint(networkPrintSize, bmp.width, bmp.height, targetW, targetH)) {
            val matrix = android.graphics.Matrix().apply { postRotate(90f) }
            val rotated = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, matrix, true)
            bmp.recycle()
            bmp = rotated
        }

        val srcW = bmp.width.toFloat()
        val srcH = bmp.height.toFloat()

        if (bordered) {
            val insetFraction = 0.06f
            val insetX = (targetW * insetFraction).toInt()
            val insetY = (targetH * insetFraction).toInt()
            val areaW = targetW - insetX * 2
            val areaH = targetH - insetY * 2
            val scale = min(areaW / srcW, areaH / srcH)
            val scaledW = max(1, (srcW * scale).toInt())
            val scaledH = max(1, (srcH * scale).toInt())
            val scaled = Bitmap.createScaledBitmap(bmp, scaledW, scaledH, true)
            bmp.recycle()

            val canvas = Bitmap.createBitmap(targetW, targetH, Bitmap.Config.ARGB_8888)
            val c = Canvas(canvas)
            c.drawColor(Color.WHITE)
            val left = insetX + (areaW - scaledW) / 2f
            val top = insetY + (areaH - scaledH) / 2f
            val paint = Paint(Paint.FILTER_BITMAP_FLAG)
            buildCombinedColorMatrix(filter, brightness)?.let { matrix ->
                paint.colorFilter = ColorMatrixColorFilter(matrix)
            }
            c.drawBitmap(scaled, left, top, paint)
            scaled.recycle()
            return canvas
        }

        // Borderless: contain-fit inside the DNP imageable area so footer/safe content
        // is not cropped (cover overscales when photo aspect ≠ driver print area).
        val areaW = size.imageableWidth
        val areaH = size.imageableHeight
        val insetX = (targetW - areaW) / 2
        val insetY = (targetH - areaH) / 2
        val scale = min(areaW / srcW, areaH / srcH)
        val scaledW = max(1, (srcW * scale).toInt())
        val scaledH = max(1, (srcH * scale).toInt())
        val scaled = Bitmap.createScaledBitmap(bmp, scaledW, scaledH, true)
        bmp.recycle()

        val canvas = Bitmap.createBitmap(targetW, targetH, Bitmap.Config.ARGB_8888)
        val c = Canvas(canvas)
        c.drawColor(Color.WHITE)
        val left = insetX + (areaW - scaledW) / 2f
        val top = insetY + (areaH - scaledH) / 2f
        val paint = Paint(Paint.FILTER_BITMAP_FLAG)
        buildCombinedColorMatrix(filter, brightness)?.let { matrix ->
            paint.colorFilter = ColorMatrixColorFilter(matrix)
        }
        c.drawBitmap(scaled, left, top, paint)
        scaled.recycle()

        return canvas
    }

    /**
     * Booth JPEGs are server-composed for WCM; USB must not re-orient landscape
     * composites (Classic 6×4) while portrait sheets (4×6 / dual strip) still
     * rotate to the DNP landscape raster buffer.
     */
    private fun shouldRotateForPrint(
        networkPrintSize: String?,
        srcW: Int,
        srcH: Int,
        targetW: Int,
        targetH: Int,
    ): Boolean {
        val srcIsLandscape = srcW > srcH
        val targetIsLandscape = targetW > targetH
        return when (networkPrintSize?.trim()?.lowercase()) {
            "s6x4" -> false
            "s6x2_2", "s4x6" -> !srcIsLandscape && targetIsLandscape
            else -> srcIsLandscape != targetIsLandscape
        }
    }

    private fun buildCombinedColorMatrix(filter: String, brightness: Int): ColorMatrix? {
        var matrix: ColorMatrix? = when (filter) {
            "B&W" -> ColorMatrix().apply { setSaturation(0f) }
            "Sepia" -> ColorMatrix().apply {
                set(
                    floatArrayOf(
                        0.393f, 0.769f, 0.189f, 0f, 0f,
                        0.349f, 0.686f, 0.168f, 0f, 0f,
                        0.272f, 0.534f, 0.131f, 0f, 0f,
                        0f, 0f, 0f, 1f, 0f,
                    ),
                )
            }
            "Vivid" -> ColorMatrix().apply { setSaturation(1.6f) }
            else -> null
        }

        if (brightness != 0) {
            val scaleFactor = 1f + brightness * 0.12f
            val brightMatrix = ColorMatrix().apply {
                setScale(scaleFactor, scaleFactor, scaleFactor, 1f)
            }
            matrix = if (matrix != null) {
                ColorMatrix().apply { setConcat(brightMatrix, matrix!!) }
            } else {
                brightMatrix
            }
        }

        return matrix
    }

    /**
     * Reads raster pixels for the DNP job stream.
     *
     * When [mirrorHorizontal] is true, each row is reversed so the physical print
     * matches the preview — DNP dye-sub heads scan in reverse without allocating
     * a second full-size bitmap (important on Android TV / low-RAM hosts).
     */
    fun bitmapToPixels(bitmap: Bitmap, mirrorHorizontal: Boolean = false): IntArray {
        val w = bitmap.width
        val h = bitmap.height
        val pixels = IntArray(w * h)
        if (!mirrorHorizontal) {
            bitmap.getPixels(pixels, 0, w, 0, 0, w, h)
            return pixels
        }
        val row = IntArray(w)
        for (y in 0 until h) {
            bitmap.getPixels(row, 0, w, 0, y, w, 1)
            val base = y * w
            for (x in 0 until w) {
                pixels[base + x] = row[w - 1 - x]
            }
        }
        return pixels
    }
}
