package com.srisarani.fotozenai.eventpipeline

import android.content.Context
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.media.ThumbnailUtils
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.util.Size
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Produces the print-ready derivative the device keeps at import.
 *
 * The original never leaves the card; only this output is stored, which is what
 * takes a 3,000-frame event from roughly 18 GB to 4 GB.
 *
 * Native rather than `package:image` for speed. Pure-Dart decode + resize +
 * encode of a 24 MP JPEG runs into seconds per frame on the Amlogic box, so 3,000
 * frames would be a two-hour import; `ImageDecoder` is hardware-assisted and
 * lands in the low hundreds of milliseconds. Same reasoning as
 * `DnpImageProcessor`, which does this shape already.
 *
 * `ImageDecoder` also applies EXIF orientation for free. That matters because the
 * re-encode drops the orientation tag, and a prints-sideways bug is invisible
 * until paper comes out of the printer.
 */
object EventImageDownscaler {
    private const val TAG = "EventDownscaler"
    const val CHANNEL_NAME = "com.srisarani.fotozenai/event_downscale"

    /** Grid thumbnails are ~30 KB; 80 is where a 320 px JPEG stops improving. */
    private const val THUMB_QUALITY = 80

    private val mainHandler = Handler(Looper.getMainLooper())


    fun register(
        flutterEngine: FlutterEngine,
        context: Context,
    ) {
        register(flutterEngine.dartExecutor.binaryMessenger, context)
    }

    fun register(
        messenger: BinaryMessenger,
        context: Context,
    ) {
        val appContext = context.applicationContext
        MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler { call, result ->
            if (call.method == "thumbnail") {
                handleThumbnail(appContext, call, result)
                return@setMethodCallHandler
            }
            if (call.method != "downscale") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val uri = call.argument<String>("uri")
            if (uri.isNullOrBlank()) {
                result.error("bad_args", "uri is required", null)
                return@setMethodCallHandler
            }
            val targetShortSide = call.argument<Int>("targetShortSide") ?: 1920
            val maxLongSide = call.argument<Int>("maxLongSide") ?: 4096
            val quality = call.argument<Int>("quality") ?: 88
            // 0 or absent means "print derivative only" — the frame compositor
            // re-emits the thumbnail later, so not every call needs one.
            val thumbShortSide = call.argument<Int>("thumbShortSide") ?: 0

            EventPipelineExecutors.import.execute {
                try {
                    // Holds a full-resolution bitmap, so it takes its turn with
                    // frame compositing rather than racing it into an OOM.
                    val output = EventPipelineExecutors.withBitmapMemory("downscale") {
                        downscale(appContext, uri, targetShortSide, maxLongSide, quality, thumbShortSide)
                    }
                    mainHandler.post { result.success(output) }
                } catch (e: Throwable) {
                    Log.e(TAG, "downscale failed for $uri", e)
                    mainHandler.post {
                        result.error("downscale_failed", e.message, null)
                    }
                }
            }
        }
    }

    /**
     * Preview thumbnail for the import picker, straight off the card.
     *
     * Separate from [downscale] because the import screen needs a picture
     * *before* anything is imported, and the print derivative it would otherwise
     * have to build costs roughly fifty times as much to produce and hold. An
     * operator scrolling a 3,000-frame card would be waiting on 2880 px encodes
     * nobody keeps.
     *
     * The decode is subsampled straight to the preview size, so peak memory is
     * the thumbnail rather than the 24 MP source.
     */
    private fun handleThumbnail(
        context: Context,
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val uri = call.argument<String>("uri")
        if (uri.isNullOrBlank()) {
            result.error("bad_args", "uri is required", null)
            return
        }
        val shortSide = call.argument<Int>("shortSide") ?: 256
        // The preview lane, never the import one: a picker being scrolled must
        // not queue behind — or compete with — an import that is already running.
        // No bitmap permit either; see EventPipelineExecutors.preview.
        EventPipelineExecutors.preview.execute {
            try {
                val bytes = thumbnail(context, uri, shortSide)
                mainHandler.post { result.success(bytes) }
            } catch (e: Throwable) {
                // A card full of odd files is normal; the tile falls back to an
                // icon rather than the screen failing.
                Log.w(TAG, "thumbnail failed for $uri", e)
                mainHandler.post { result.success(null) }
            }
        }
    }

    /**
     * A small JPEG for [uri], by the cheapest route that works.
     *
     * Decoding the original is the *fallback*, not the plan. A card item is a
     * MediaStore `content://`, and MediaStore already keeps a thumbnail for it —
     * asking for that is tens of milliseconds against the hundreds a 24 MP
     * subsampled decode costs, and the picker shows sixty tiles at once. Reading
     * sixty 6 MB originals off an SD card to draw sixty 160 dp squares is the
     * whole of the delay this avoids.
     */
    fun thumbnail(
        context: Context,
        uri: String,
        shortSide: Int,
    ): ByteArray {
        val started = System.currentTimeMillis()
        var source = "cache"
        var bitmap = cachedThumbnail(context, uri, shortSide)
        if (bitmap == null) {
            source = "decode"
            bitmap = decodeSubsampled(context, uri, shortSide)
        }
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, THUMB_QUALITY, out)
        bitmap.recycle()
        val elapsed = System.currentTimeMillis() - started
        // Timed because the difference between the two routes is the difference
        // between a picker that fills instantly and one that crawls.
        Log.d(TAG, "thumbnail $source ${elapsed}ms ${out.size()}B $uri")
        return out.toByteArray()
    }

    /**
     * The thumbnail the platform already has, or null if it has none.
     *
     * `loadThumbnail` reads MediaStore's cache for a `content://`; for a plain
     * path `createImageThumbnail` uses the JPEG's embedded EXIF thumbnail where
     * there is one. Either way the original is never fully decoded.
     */
    private fun cachedThumbnail(
        context: Context,
        uri: String,
        shortSide: Int,
    ): Bitmap? {
        val size = Size(shortSide, shortSide)
        return try {
            if (uri.startsWith("content://")) {
                context.contentResolver.loadThumbnail(Uri.parse(uri), size, null)
            } else {
                ThumbnailUtils.createImageThumbnail(File(uri), size, null)
            }
        } catch (e: Throwable) {
            // No cached thumbnail, an unindexed card, or a format with no EXIF
            // thumbnail. The caller falls back to a real decode.
            Log.d(TAG, "no cached thumbnail for $uri: ${e.message}")
            null
        }
    }

    /** Last resort: decode the original, subsampled to [shortSide]. */
    private fun decodeSubsampled(
        context: Context,
        uri: String,
        shortSide: Int,
    ): Bitmap {
        val source = decodeSource(context, uri)
        return ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            decoder.isMutableRequired = false
            val size = targetSize(info.size.width, info.size.height, shortSide, shortSide * 4)
            decoder.setTargetSize(size.first, size.second)
        }
    }

    /**
     * Decodes once and encodes up to twice.
     *
     * The grid thumbnail is produced from the bitmap already in hand rather than
     * by re-reading the original: a second decode of a 6 MB JPEG costs far more
     * than the few milliseconds this adds, and at 400 photos that difference is
     * the whole of the queue's responsiveness on a weak box.
     */
    fun downscale(
        context: Context,
        uri: String,
        targetShortSide: Int,
        maxLongSide: Int,
        quality: Int,
        thumbShortSide: Int = 0,
    ): Map<String, Any?> {
        val source = decodeSource(context, uri)
        var bitmap =
            ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
                // Software allocation so the bitmap can be read back for encoding;
                // a hardware bitmap has no pixel access.
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                decoder.isMutableRequired = false
                val size = targetSize(info.size.width, info.size.height, targetShortSide, maxLongSide)
                // Subsampling at decode time is what keeps peak memory near the
                // output size rather than the full 24 MP source.
                decoder.setTargetSize(size.first, size.second)
            }

        // setTargetSize is a hint the decoder may round; finish the job exactly.
        val exact = targetSize(bitmap.width, bitmap.height, targetShortSide, maxLongSide)
        if (bitmap.width != exact.first || bitmap.height != exact.second) {
            val scaled = Bitmap.createScaledBitmap(bitmap, exact.first, exact.second, true)
            if (scaled != bitmap) bitmap.recycle()
            bitmap = scaled
        }

        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, quality, stream)
        val width = bitmap.width
        val height = bitmap.height

        val thumb = encodeThumb(bitmap, thumbShortSide)
        bitmap.recycle()

        return mapOf(
            "bytes" to stream.toByteArray(),
            "width" to width,
            "height" to height,
            "thumbBytes" to thumb?.get("bytes"),
            "thumbWidth" to thumb?.get("width"),
            "thumbHeight" to thumb?.get("height"),
        )
    }

    /**
     * A small JPEG off a bitmap that is already decoded.
     *
     * Returns null when no thumbnail was asked for, or when the source is
     * already smaller than the target — upscaling a thumbnail would cost bytes
     * for no extra detail.
     */
    fun encodeThumb(bitmap: Bitmap, thumbShortSide: Int): Map<String, Any?>? {
        if (thumbShortSide <= 0) return null
        val shortSide = minOf(bitmap.width, bitmap.height)
        if (shortSide <= 0) return null
        val scale = thumbShortSide.toFloat() / shortSide.toFloat()
        if (scale >= 1f) return null
        val w = maxOf(1, Math.round(bitmap.width * scale))
        val h = maxOf(1, Math.round(bitmap.height * scale))
        val scaled = Bitmap.createScaledBitmap(bitmap, w, h, true)
        val out = ByteArrayOutputStream()
        scaled.compress(Bitmap.CompressFormat.JPEG, THUMB_QUALITY, out)
        if (scaled != bitmap) scaled.recycle()
        return mapOf(
            "bytes" to out.toByteArray(),
            "width" to w,
            "height" to h,
        )
    }

    private fun decodeSource(
        context: Context,
        uri: String,
    ): ImageDecoder.Source {
        // A card item arrives as content://; the folder source passes a path.
        return if (uri.startsWith("content://")) {
            ImageDecoder.createSource(context.contentResolver, Uri.parse(uri))
        } else {
            ImageDecoder.createSource(File(uri))
        }
    }

    /**
     * Scales so the **short side** reaches [targetShortSide], never upscaling and
     * never letting the long side exceed [maxLongSide].
     *
     * Short side is the constraint because `DnpImageProcessor` cover-fits onto the
     * print raster: at 300 dpi the DS-RX1's native width is 1920 px, so a
     * derivative whose short side reaches 1920 has full native quality at every
     * size the printer offers.
     */
    fun targetSize(
        srcWidth: Int,
        srcHeight: Int,
        targetShortSide: Int,
        maxLongSide: Int,
    ): Pair<Int, Int> {
        if (srcWidth <= 0 || srcHeight <= 0) return Pair(1, 1)
        val shortSide = min(srcWidth, srcHeight)
        // Never upscale — a small original stays small rather than being blown up.
        var scale = targetShortSide.toDouble() / shortSide.toDouble()
        if (scale > 1.0) scale = 1.0

        val longSide = max(srcWidth, srcHeight)
        val scaledLong = longSide * scale
        if (scaledLong > maxLongSide) {
            scale = maxLongSide.toDouble() / longSide.toDouble()
        }

        val width = max(1, (srcWidth * scale).roundToInt())
        val height = max(1, (srcHeight * scale).roundToInt())
        return Pair(width, height)
    }
}
