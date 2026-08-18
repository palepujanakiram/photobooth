package com.srisarani.fotozenai.canoncapture

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.view.SurfaceHolder
import com.srisarani.fotozenai.canon.CanonLog

/**
 * Paints live-view frames onto a [SurfaceHolder].
 *
 * Frames go camera → Kotlin `Bitmap` → this `Canvas` and never enter Dart. Handing ~20 fps
 * of JPEG across a platform channel would mean a serialise, a copy and a decode per frame,
 * which is the cost the whole native-screen design exists to avoid.
 */
class LiveViewSurfaceRenderer(private val holder: SurfaceHolder) {

    private val paint = Paint().apply {
        isFilterBitmap = true
        isAntiAlias = true
    }
    private val destination = Rect()

    @Volatile
    var isSurfaceReady: Boolean = false

    /**
     * Draws [frame] letterboxed into the surface.
     *
     * Aspect ratio is preserved rather than filled: this is a framing viewfinder, and a
     * crop that hides what the sensor will actually record makes it lie about the shot.
     */
    fun draw(frame: Bitmap) {
        if (!isSurfaceReady || frame.isRecycled) return
        val canvas = try {
            holder.lockCanvas()
        } catch (e: IllegalStateException) {
            // The surface can go away between the readiness check and the lock.
            CanonLog.d("lockCanvas failed: %s", e.message ?: "surface gone")
            null
        } ?: return

        try {
            canvas.drawColor(Color.BLACK)
            fitCentre(frame.width, frame.height, canvas.width, canvas.height, destination)
            canvas.drawBitmap(frame, null, destination, paint)
        } finally {
            runCatching { holder.unlockCanvasAndPost(canvas) }
        }
    }

    /** Paints the surface black — used when live view stops, so no stale frame lingers. */
    fun clear() {
        if (!isSurfaceReady) return
        val canvas = runCatching { holder.lockCanvas() }.getOrNull() ?: return
        try {
            canvas.drawColor(Color.BLACK)
        } finally {
            runCatching { holder.unlockCanvasAndPost(canvas) }
        }
    }

    companion object {
        /** Largest centred rect of the source's aspect ratio that fits the target. */
        fun fitCentre(
            srcWidth: Int,
            srcHeight: Int,
            dstWidth: Int,
            dstHeight: Int,
            out: Rect,
        ): Rect {
            if (srcWidth <= 0 || srcHeight <= 0 || dstWidth <= 0 || dstHeight <= 0) {
                out.set(0, 0, dstWidth.coerceAtLeast(0), dstHeight.coerceAtLeast(0))
                return out
            }
            val scale = minOf(
                dstWidth.toDouble() / srcWidth,
                dstHeight.toDouble() / srcHeight,
            )
            val width = Math.round(srcWidth * scale).toInt().coerceAtLeast(1)
            val height = Math.round(srcHeight * scale).toInt().coerceAtLeast(1)
            val left = (dstWidth - width) / 2
            val top = (dstHeight - height) / 2
            out.set(left, top, left + width, top + height)
            return out
        }
    }
}
