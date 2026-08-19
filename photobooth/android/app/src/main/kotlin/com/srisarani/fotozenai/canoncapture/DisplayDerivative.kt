package com.srisarani.fotozenai.canoncapture

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.srisarani.fotozenai.canon.CanonLog
import java.io.File
import java.io.FileOutputStream

/**
 * Builds the small on-screen / upload copy of a capture.
 *
 * The original stays on disk untouched — it is what gets printed, and re-encoding it would
 * be generation loss on the one file that cannot be recovered. This produces a *separate*
 * file sized for the review screen and the zenai upload.
 *
 * ## Why the original never crosses into Dart
 *
 * A 6000×4000 JPEG is ~96 MB once decoded to ARGB_8888. The target box runs a 256 MB heap
 * with a Flutter engine and image caches already in it. So the decode happens here, in
 * Kotlin, subsampled — and Dart only ever receives a *path*.
 */
object DisplayDerivative {

    /** Long edge of the derivative. Matches the kiosk's existing normalize size. */
    const val DEFAULT_MAX_LONG_EDGE = 1920

    /** High enough that the review screen and the AI upload are not visibly soft. */
    const val DEFAULT_JPEG_QUALITY = 90

    /**
     * Largest power-of-two subsample that still leaves at least [maxLongEdge] pixels.
     *
     * Power-of-two because `BitmapFactory` silently rounds anything else down to one, so a
     * "cleverer" ratio would decode far more pixels than intended. Stopping *above* the
     * target rather than below is deliberate: the exact size comes from one high-quality
     * scale afterwards, and subsampling past the target throws away detail that scale
     * would have used.
     */
    fun sampleSizeFor(width: Int, height: Int, maxLongEdge: Int): Int {
        if (width <= 0 || height <= 0 || maxLongEdge <= 0) return 1
        val longEdge = maxOf(width, height)
        var sample = 1
        while (longEdge / (sample * 2) >= maxLongEdge) {
            sample *= 2
        }
        return sample
    }

    /** Target pixel size for [maxLongEdge], preserving aspect ratio. Never upscales. */
    fun scaledSize(width: Int, height: Int, maxLongEdge: Int): Pair<Int, Int> {
        val longEdge = maxOf(width, height)
        if (longEdge <= maxLongEdge || longEdge == 0) return width to height
        val ratio = maxLongEdge.toDouble() / longEdge
        return maxOf(1, Math.round(width * ratio).toInt()) to
            maxOf(1, Math.round(height * ratio).toInt())
    }

    /** Long edge for the native capture thumbnail strip (reuses derivative decode). */
    const val THUMBNAIL_LONG_EDGE = 320

    data class Result(
        val file: File,
        val widthPx: Int,
        val heightPx: Int,
        /** Pixel dimensions of the untouched original. */
        val originalWidthPx: Int,
        val originalHeightPx: Int,
        /** Small bitmap for the multi-shot thumbnail strip; avoids a second file decode. */
        val thumbnailBitmap: Bitmap? = null,
    )

    /** Downscale [source] for a UI thumbnail without re-reading the derivative JPEG. */
    fun thumbnailBitmap(
        source: Bitmap,
        maxLongEdge: Int = THUMBNAIL_LONG_EDGE,
    ): Bitmap {
        val longEdge = maxOf(source.width, source.height)
        if (longEdge <= maxLongEdge) {
            return source.copy(Bitmap.Config.ARGB_8888, false)
        }
        val (targetW, targetH) = scaledSize(source.width, source.height, maxLongEdge)
        return Bitmap.createScaledBitmap(source, targetW, targetH, true)
    }

    /**
     * Writes a downscaled JPEG next to [original], as `<name>.display.jpg`.
     *
     * Returns null rather than throwing: a missing derivative should cost the review
     * thumbnail, not the capture. The original is already safely on disk by this point.
     */
    fun create(
        original: File,
        maxLongEdge: Int = DEFAULT_MAX_LONG_EDGE,
        jpegQuality: Int = DEFAULT_JPEG_QUALITY,
    ): Result? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(original.absolutePath, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            CanonLog.e("Could not read image bounds from %s", original.name)
            return null
        }

        val options = BitmapFactory.Options().apply {
            inSampleSize = sampleSizeFor(bounds.outWidth, bounds.outHeight, maxLongEdge)
            // The camera's pixels are the reference; density scaling would resample them
            // behind our back and make the output size depend on the device's screen.
            inScaled = false
        }

        var decoded: Bitmap? = null
        var scaled: Bitmap? = null
        return try {
            decoded = BitmapFactory.decodeFile(original.absolutePath, options)
            if (decoded == null) {
                CanonLog.e("Decode returned null for %s", original.name)
                return null
            }

            val (targetW, targetH) =
                scaledSize(decoded.width, decoded.height, maxLongEdge)
            scaled = if (targetW == decoded.width && targetH == decoded.height) {
                decoded
            } else {
                Bitmap.createScaledBitmap(decoded, targetW, targetH, true)
            }

            val out = File(original.parentFile, "${original.nameWithoutExtension}.display.jpg")
            FileOutputStream(out).use { stream ->
                scaled.compress(Bitmap.CompressFormat.JPEG, jpegQuality, stream)
            }

            val thumb = thumbnailBitmap(scaled)

            CanonLog.i(
                "Display derivative: %s %dx%d -> %dx%d (sample=%d, %d bytes)",
                out.name,
                bounds.outWidth,
                bounds.outHeight,
                scaled.width,
                scaled.height,
                options.inSampleSize,
                out.length(),
            )

            Result(
                file = out,
                widthPx = scaled.width,
                heightPx = scaled.height,
                originalWidthPx = bounds.outWidth,
                originalHeightPx = bounds.outHeight,
                thumbnailBitmap = thumb,
            )
        } catch (e: Throwable) {
            // OutOfMemoryError is a Throwable, not an Exception, and is precisely the
            // failure worth surviving here.
            CanonLog.e(e, "Display derivative failed for %s", original.name)
            null
        } finally {
            if (scaled !== decoded) scaled?.recycle()
            decoded?.recycle()
        }
    }
}
