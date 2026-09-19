package com.srisarani.fotozenai.eventpipeline

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ImageDecoder
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Composites an event frame over a photo, on device.
 *
 * AI needs WAN and stays a server call; framing is local, and that is what lets
 * an AI-off event finish its whole chain with no network at all.
 *
 * Occasion overlays with a caption bar (JustMarried) have a partial transparent
 * window. The capture is cover-fitted into that hole — same as zenai
 * `composeFrame` — so the subject fills the photo window instead of the whole
 * sheet (which would hide them behind the footer). Full-bleed borders and
 * frame-off jobs still cover the print raster like `DnpImageProcessor`.
 */
object EventFrameCompositor {
    private const val TAG = "EventFrameCompositor"
    const val CHANNEL_NAME = "com.srisarani.fotozenai/event_frame"

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
            if (call.method != "composite") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val photoPath = call.argument<String>("photoPath")
            val framePath = call.argument<String>("framePath")
            val width = call.argument<Int>("width") ?: 0
            val height = call.argument<Int>("height") ?: 0
            if (photoPath.isNullOrBlank() || width <= 0 || height <= 0) {
                result.error("bad_args", "photoPath, width and height are required", null)
                return@setMethodCallHandler
            }

            EventPipelineExecutors.frame.execute {
                try {
                    val output =
                        EventPipelineExecutors.withBitmapMemory("composite") {
                            composite(
                                appContext,
                                photoPath,
                                framePath,
                                width,
                                height,
                                call.argument<Int>("quality") ?: 88,
                                call.argument<Int>("thumbShortSide") ?: 0,
                            )
                        }
                    mainHandler.post { result.success(output) }
                } catch (e: Throwable) {
                    Log.e(TAG, "composite failed for $photoPath", e)
                    mainHandler.post { result.error("composite_failed", e.message, null) }
                }
            }
        }
    }

    /**
     * Draws the print, and optionally the grid thumbnail from the same canvas.
     *
     * The thumbnail is what the queue grid shows, so emitting it here is how the
     * operator sees the *framed* result rather than the raw import — and it
     * costs one extra encode off a bitmap already in hand, not a second decode.
     */
    fun composite(
        context: Context,
        photoPath: String,
        framePath: String?,
        width: Int,
        height: Int,
        quality: Int,
        thumbShortSide: Int = 0,
    ): Map<String, Any?> {
        // The frame is the design; the print follows it. A portrait frame on a
        // landscape raster would letterbox, leaving the cover-fitted photo
        // visible on both sides *outside* the artwork — not a printable result.
        // DNP media takes either orientation, so swap the canvas to match.
        val canvasSize = orientedCanvas(context, framePath, width, height)
        val width = canvasSize.first
        val height = canvasSize.second

        val canvasBitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(canvasBitmap)
        // White ground: a frame with transparent regions must not print black.
        canvas.drawColor(Color.WHITE)

        val photo = decode(context, photoPath, width, height)
        if (framePath.isNullOrBlank()) {
            drawCoverFitted(canvas, photo, width, height)
        } else {
            val frame = decodeOverlay(context, framePath, width, height)
            val dest = fittedRect(frame.width, frame.height, width, height)
            val hole = photoDestOnCanvas(frame, dest)
            if (hole != null) {
                drawCoverFitted(canvas, photo, hole)
            } else {
                drawCoverFitted(canvas, photo, width, height)
            }
            // Fitted, not stretched. A frame whose aspect ratio does not match
            // the print size letterboxes rather than distorting the artwork.
            canvas.drawBitmap(frame, null, dest, null)
            frame.recycle()
        }
        photo.recycle()

        val stream = ByteArrayOutputStream()
        canvasBitmap.compress(Bitmap.CompressFormat.JPEG, quality, stream)
        val thumb = EventImageDownscaler.encodeThumb(canvasBitmap, thumbShortSide)
        canvasBitmap.recycle()

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
     * Canvas dimensions matching the frame's orientation.
     *
     * Reads only the frame's header, so this costs nothing next to the decode.
     * Returns the raster unchanged when there is no frame, or when the two
     * already agree.
     */
    fun orientedCanvas(
        context: Context,
        framePath: String?,
        width: Int,
        height: Int,
    ): Pair<Int, Int> {
        if (framePath.isNullOrBlank()) return Pair(width, height)
        val bounds = frameBounds(context, framePath) ?: return Pair(width, height)
        val frameIsPortrait = bounds.second > bounds.first
        val canvasIsPortrait = height > width
        return if (frameIsPortrait == canvasIsPortrait) {
            Pair(width, height)
        } else {
            Pair(height, width)
        }
    }

    private fun frameBounds(
        context: Context,
        path: String,
    ): Pair<Int, Int>? {
        return try {
            val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            if (path.startsWith("content://")) {
                context.contentResolver.openInputStream(android.net.Uri.parse(path))
                    ?.use { BitmapFactory.decodeStream(it, null, options) }
            } else {
                BitmapFactory.decodeFile(path, options)
            }
            if (options.outWidth <= 0 || options.outHeight <= 0) {
                null
            } else {
                Pair(options.outWidth, options.outHeight)
            }
        } catch (e: Exception) {
            Log.d(TAG, "frame bounds unreadable for $path: ${e.message}")
            null
        }
    }

    private fun decode(
        context: Context,
        path: String,
        maxWidth: Int,
        maxHeight: Int,
    ): Bitmap {
        val source =
            if (path.startsWith("content://")) {
                ImageDecoder.createSource(context.contentResolver, android.net.Uri.parse(path))
            } else {
                ImageDecoder.createSource(File(path))
            }
        return ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            decoder.isMutableRequired = false
            // Bound the decode near the canvas so a large source cannot spike RAM.
            val limit = max(maxWidth, maxHeight) * 2
            val longest = max(info.size.width, info.size.height)
            if (longest > limit) {
                val scale = limit.toDouble() / longest.toDouble()
                decoder.setTargetSize(
                    max(1, (info.size.width * scale).roundToInt()),
                    max(1, (info.size.height * scale).roundToInt()),
                )
            }
        }
    }

    /**
     * Overlay PNG must keep its alpha. [ImageDecoder] can flatten that on some
     * API levels, which would hide the photo window and fall back to the old
     * cover-the-sheet crop.
     */
    private fun decodeOverlay(
        context: Context,
        path: String,
        maxWidth: Int,
        maxHeight: Int,
    ): Bitmap {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        decodeWithFactory(context, path, bounds)
        val longest = max(bounds.outWidth, bounds.outHeight)
        val limit = max(maxWidth, maxHeight) * 2
        val options =
            BitmapFactory.Options().apply {
                inJustDecodeBounds = false
                inPreferredConfig = Bitmap.Config.ARGB_8888
                inSampleSize = overlaySampleSize(longest, limit)
            }
        val decoded =
            decodeWithFactory(context, path, options)
                ?: error("Could not decode frame overlay $path")
        return if (decoded.config == Bitmap.Config.ARGB_8888) {
            decoded
        } else {
            decoded.copy(Bitmap.Config.ARGB_8888, false)?.also { decoded.recycle() }
                ?: decoded
        }
    }

    internal fun overlaySampleSize(longest: Int, limit: Int): Int {
        if (longest <= 0 || limit <= 0 || longest <= limit) return 1
        var sample = 1
        while (longest / (sample * 2) >= limit) {
            sample *= 2
        }
        return sample
    }

    private fun decodeWithFactory(
        context: Context,
        path: String,
        options: BitmapFactory.Options,
    ): Bitmap? {
        return if (path.startsWith("content://")) {
            context.contentResolver.openInputStream(android.net.Uri.parse(path))
                ?.use { BitmapFactory.decodeStream(it, null, options) }
        } else {
            BitmapFactory.decodeFile(path, options)
        }
    }

    /**
     * Canvas rectangle for the overlay's transparent photo window, or null
     * when the PNG is a full-bleed border (legacy cover-the-sheet path).
     */
    fun photoDestOnCanvas(frame: Bitmap, dest: Rect): Rect? {
        val hole = readTransparentHole(frame) ?: return null
        if (!EventFrameHole.isPartialPhotoHole(hole, frame.width, frame.height)) {
            return null
        }
        val mapped =
            EventFrameHole.mapToDest(
                hole,
                frame.width,
                frame.height,
                dest.left,
                dest.top,
                dest.width(),
                dest.height(),
            )
        if (mapped.width < 8 || mapped.height < 8) return null
        return Rect(mapped.left, mapped.top, mapped.right, mapped.bottom)
    }

    private fun readTransparentHole(frame: Bitmap): EventFrameHole.Box? {
        val readable =
            if (frame.config == Bitmap.Config.ARGB_8888) {
                frame
            } else {
                frame.copy(Bitmap.Config.ARGB_8888, false) ?: return null
            }
        val width = readable.width
        val height = readable.height
        val pixels = IntArray(width * height)
        readable.getPixels(pixels, 0, width, 0, 0, width, height)
        if (readable !== frame) readable.recycle()
        return EventFrameHole.findTransparentHole(width, height, pixels)
    }

    /** Fills [dest], cropping the overflow — matching `DnpImageProcessor`. */
    private fun drawCoverFitted(
        canvas: Canvas,
        bitmap: Bitmap,
        width: Int,
        height: Int,
    ) {
        drawCoverFitted(canvas, bitmap, Rect(0, 0, width, height))
    }

    private fun drawCoverFitted(
        canvas: Canvas,
        bitmap: Bitmap,
        dest: Rect,
    ) {
        val crop =
            EventFrameHole.coverCropSource(
                bitmap.width,
                bitmap.height,
                dest.width(),
                dest.height(),
            )
        val src = Rect(crop.left, crop.top, crop.right, crop.bottom)
        canvas.drawBitmap(bitmap, src, dest, null)
    }

    /** Extracted so the letterbox maths can be reasoned about on its own. */
    fun fittedRect(
        srcWidth: Int,
        srcHeight: Int,
        dstWidth: Int,
        dstHeight: Int,
    ): Rect {
        if (srcWidth <= 0 || srcHeight <= 0) return Rect(0, 0, dstWidth, dstHeight)
        val scale =
            minOf(
                dstWidth.toDouble() / srcWidth.toDouble(),
                dstHeight.toDouble() / srcHeight.toDouble(),
            )
        val drawWidth = max(1, (srcWidth * scale).roundToInt())
        val drawHeight = max(1, (srcHeight * scale).roundToInt())
        val left = (dstWidth - drawWidth) / 2
        val top = (dstHeight - drawHeight) / 2
        return Rect(left, top, left + drawWidth, top + drawHeight)
    }
}
