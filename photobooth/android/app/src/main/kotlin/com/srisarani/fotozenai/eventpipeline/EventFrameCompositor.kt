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
 * The photo is cover-fitted onto the print raster the same way
 * `DnpImageProcessor` does, so a framed print and an unframed one are composed
 * identically — otherwise the two would subtly disagree on crop.
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

    fun composite(
        context: Context,
        photoPath: String,
        framePath: String?,
        width: Int,
        height: Int,
        quality: Int,
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
        drawCoverFitted(canvas, photo, width, height)
        photo.recycle()

        if (!framePath.isNullOrBlank()) {
            val frame = decode(context, framePath, width, height)
            // Fitted, not stretched. A frame whose aspect ratio does not match
            // the print size letterboxes rather than distorting the artwork.
            drawFitted(canvas, frame, width, height)
            frame.recycle()
        }

        val stream = ByteArrayOutputStream()
        canvasBitmap.compress(Bitmap.CompressFormat.JPEG, quality, stream)
        canvasBitmap.recycle()

        return mapOf(
            "bytes" to stream.toByteArray(),
            "width" to width,
            "height" to height,
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
     * Fills the canvas, cropping the overflow — matching `DnpImageProcessor`.
     */
    private fun drawCoverFitted(
        canvas: Canvas,
        bitmap: Bitmap,
        width: Int,
        height: Int,
    ) {
        val srcRatio = bitmap.width.toDouble() / bitmap.height.toDouble()
        val dstRatio = width.toDouble() / height.toDouble()
        val src =
            if (srcRatio > dstRatio) {
                // Source is wider: crop its sides.
                val cropWidth = (bitmap.height * dstRatio).roundToInt()
                val inset = (bitmap.width - cropWidth) / 2
                Rect(inset, 0, inset + cropWidth, bitmap.height)
            } else {
                // Source is taller: crop top and bottom.
                val cropHeight = (bitmap.width / dstRatio).roundToInt()
                val inset = (bitmap.height - cropHeight) / 2
                Rect(0, inset, bitmap.width, inset + cropHeight)
            }
        canvas.drawBitmap(bitmap, src, Rect(0, 0, width, height), null)
    }

    /**
     * Fits the whole bitmap inside the canvas, centred, preserving aspect ratio.
     */
    private fun drawFitted(
        canvas: Canvas,
        bitmap: Bitmap,
        width: Int,
        height: Int,
    ) {
        val dst = fittedRect(bitmap.width, bitmap.height, width, height)
        canvas.drawBitmap(bitmap, null, dst, null)
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
