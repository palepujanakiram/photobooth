package com.srisarani.fotozenai.selphy

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.ImageDecoder
import android.graphics.Paint
import android.graphics.Point
import android.graphics.Rect
import java.io.File
import java.io.FileOutputStream

/**
 * Prepares a JPEG for Canon Selphy CP1500 (USB/Wi‑Fi SDK canvas + printable rect).
 * Ported from the canon-selphy-silent-print reference app.
 */
internal object SelphyImageProcessor {
    fun resizeForPrinting(
        context: Context,
        sourcePath: String,
        jpegSize: Point,
        printable: Rect,
        filter: String,
        brightness: Int,
        bordered: Boolean,
    ): File {
        val targetW = jpegSize.x
        val targetH = jpegSize.y

        val source = ImageDecoder.createSource(File(sourcePath))
        var bmp = ImageDecoder.decodeBitmap(source) { decoder, _, _ ->
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
        }

        val srcIsLandscape = bmp.width > bmp.height
        val paperIsLandscape = targetW > targetH
        if (srcIsLandscape != paperIsLandscape) {
            val matrix = android.graphics.Matrix().apply { postRotate(90f) }
            val rotated = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, matrix, true)
            bmp.recycle()
            bmp = rotated
        }

        val srcW = bmp.width.toFloat()
        val srcH = bmp.height.toFloat()
        val insetFraction = if (bordered) 0.06f else 0.025f
        val insetX = (printable.width() * insetFraction).toInt()
        val insetY = (printable.height() * insetFraction).toInt()
        val areaLeft = printable.left + insetX
        val areaTop = printable.top + insetY
        val areaW = printable.width() - insetX * 2
        val areaH = printable.height() - insetY * 2

        val scale = minOf(areaW / srcW, areaH / srcH)
        val scaledW = (srcW * scale).toInt()
        val scaledH = (srcH * scale).toInt()
        val scaled = Bitmap.createScaledBitmap(bmp, scaledW, scaledH, true)
        bmp.recycle()

        var canvas = Bitmap.createBitmap(targetW, targetH, Bitmap.Config.ARGB_8888)
        val c = Canvas(canvas)
        c.drawColor(Color.WHITE)
        val left = areaLeft + (areaW - scaledW) / 2f
        val top = areaTop + (areaH - scaledH) / 2f
        c.drawBitmap(scaled, left, top, Paint(Paint.FILTER_BITMAP_FLAG))
        scaled.recycle()

        if (brightness != 0) {
            val scale2 = 1f + brightness * 0.12f
            val brightMatrix = ColorMatrix().apply {
                setScale(scale2, scale2, scale2, 1f)
            }
            val paint = Paint().apply { colorFilter = ColorMatrixColorFilter(brightMatrix) }
            val adjusted = Bitmap.createBitmap(targetW, targetH, Bitmap.Config.ARGB_8888)
            Canvas(adjusted).drawBitmap(canvas, 0f, 0f, paint)
            canvas.recycle()
            canvas = adjusted
        }

        if (filter != "Off") {
            val colorMatrix = when (filter) {
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
            if (colorMatrix != null) {
                val paint = Paint().apply { colorFilter = ColorMatrixColorFilter(colorMatrix) }
                val filtered = Bitmap.createBitmap(targetW, targetH, Bitmap.Config.ARGB_8888)
                Canvas(filtered).drawBitmap(canvas, 0f, 0f, paint)
                canvas.recycle()
                canvas = filtered
            }
        }

        val outFile = File(context.cacheDir, "selphy_print_${System.currentTimeMillis()}.jpg")
        FileOutputStream(outFile).use { fos ->
            canvas.compress(Bitmap.CompressFormat.JPEG, 95, fos)
        }
        canvas.recycle()
        return outFile
    }
}
