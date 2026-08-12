package com.srisarani.fotozenai.selphy

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorMatrixColorFilter
import android.graphics.ImageDecoder
import android.graphics.Paint
import com.srisarani.fotozenai.print.PrintColorMatrices
import java.io.File
import java.io.FileOutputStream

/**
 * Prepares a JPEG for Canon Selphy CP1500 (USB/Wi‑Fi SDK canvas + printable rect).
 */
internal object SelphyImageProcessor {
    fun resizeForPrinting(
        context: Context,
        input: SelphyResizeInput,
    ): File {
        val targetW = input.jpegSize.x
        val targetH = input.jpegSize.y

        val source = ImageDecoder.createSource(File(input.sourcePath))
        var bmp =
            ImageDecoder.decodeBitmap(source) { decoder, _, _ ->
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            }

        val srcIsLandscape = bmp.width > bmp.height
        val paperIsLandscape = targetW > targetH
        if (srcIsLandscape != paperIsLandscape) {
            val matrix = android.graphics.Matrix().apply { postRotate(90f) }
            val rotated =
                Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, matrix, true)
            bmp.recycle()
            bmp = rotated
        }

        val srcW = bmp.width.toFloat()
        val srcH = bmp.height.toFloat()
        val insetFraction = if (input.look.bordered) 0.06f else 0.025f
        val insetX = (input.printable.width() * insetFraction).toInt()
        val insetY = (input.printable.height() * insetFraction).toInt()
        val areaLeft = input.printable.left + insetX
        val areaTop = input.printable.top + insetY
        val areaW = input.printable.width() - insetX * 2
        val areaH = input.printable.height() - insetY * 2

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

        val colorMatrix =
            PrintColorMatrices.combined(input.look.filter, input.look.brightness)
        if (colorMatrix != null) {
            val paint = Paint().apply { colorFilter = ColorMatrixColorFilter(colorMatrix) }
            val adjusted = Bitmap.createBitmap(targetW, targetH, Bitmap.Config.ARGB_8888)
            Canvas(adjusted).drawBitmap(canvas, 0f, 0f, paint)
            canvas.recycle()
            canvas = adjusted
        }

        val outFile = File(context.cacheDir, "selphy_print_${System.currentTimeMillis()}.jpg")
        FileOutputStream(outFile).use { fos ->
            canvas.compress(Bitmap.CompressFormat.JPEG, 95, fos)
        }
        canvas.recycle()
        return outFile
    }
}
