package com.srisarani.fotozenai.eventpipeline

import android.content.Context
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
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

            EventPipelineExecutors.import.execute {
                try {
                    // Holds a full-resolution bitmap, so it takes its turn with
                    // frame compositing rather than racing it into an OOM.
                    val output = EventPipelineExecutors.withBitmapMemory("downscale") {
                        downscale(appContext, uri, targetShortSide, maxLongSide, quality)
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

    fun downscale(
        context: Context,
        uri: String,
        targetShortSide: Int,
        maxLongSide: Int,
        quality: Int,
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
        bitmap.recycle()

        return mapOf(
            "bytes" to stream.toByteArray(),
            "width" to width,
            "height" to height,
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
