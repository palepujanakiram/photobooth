package com.srisarani.fotozenai.canoncapture

import android.graphics.Bitmap
import com.srisarani.fotozenai.R
import com.srisarani.fotozenai.canon.CanonLog
import com.srisarani.fotozenai.canon.capture.CaptureQueue
import com.srisarani.fotozenai.canon.session.CameraSessionManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/**
 * One shutter cycle: fire, wait for the image, store the derivative.
 *
 * Extracted from [CanonCaptureActivity] so the Activity stays under Qlty's file-complexity
 * budget. Behaviour matches the previous inline methods.
 */
internal class CanonShotCapture(
    private val scope: CoroutineScope,
    private val shots: MutableList<CaptureSessionContract.Shot>,
    private val consumedHandles: MutableSet<Long>,
    private val host: Host,
) {
    interface Host {
        val request: CaptureSessionContract.Request

        fun string(
            id: Int,
            vararg args: Any,
        ): String

        fun setStatus(text: String)

        fun finishWith(result: CaptureSessionContract.Result)

        fun startIdleWatchdog()

        fun fillThumb(
            shotsTaken: Int,
            thumbnail: Bitmap?,
        )

        fun setShutterEnabled(enabled: Boolean)

        fun isCaptureJobActive(): Boolean

        fun isUiAlive(): Boolean

        fun playShutterSound()

        fun seedStaleReplay()
    }

    /** Fires one shot and stores it. Returns false when the shot did not land. */
    suspend fun runOneShot(): Boolean {
        val queue = CameraSessionManager.captureQueue
        if (queue == null) {
            host.finishWith(
                CaptureSessionContract.Result.error(
                    CaptureSessionContract.ERROR_CAPTURE_FAILED,
                    "Capture queue unavailable — the camera session is not fully open",
                ),
            )
            return false
        }

        host.setStatus(host.string(R.string.canon_status_capturing))
        host.playShutterSound()

        host.seedStaleReplay()

        // Subscribe BEFORE firing, and UNDISPATCHED so the collector is attached before
        // this line returns. A download can finish faster than a coroutine scheduled the
        // ordinary way would take to start collecting, and the event would be missed.
        val done =
            scope.async(start = CoroutineStart.UNDISPATCHED) {
                queue.completed.first { it.handle !in consumedHandles }
            }

        // Wait for the shutter to actually fire before waiting for an image. A release that
        // comes back DeviceBusy produces no photo, and treating that as "in flight" cost the
        // full CAPTURE_TIMEOUT_MS of blank screen per failed attempt — two in a row put a
        // guest through 106s of nothing before the third try worked (hardware 2026-08-18).
        if (!CameraSessionManager.triggerCapture(withAutofocus = true).await()) {
            done.cancel()
            markShotFailed("Shutter did not fire; not waiting for an image")
            return false
        }

        val completed = withTimeoutOrNull(CAPTURE_TIMEOUT_MS) { done.await() }
        done.cancel()

        if (completed == null) {
            markShotFailed("Capture timed out after ${CAPTURE_TIMEOUT_MS}ms")
            return false
        }

        consumedHandles += completed.handle
        val isLastCapture = shots.size + 1 >= host.request.shotCount

        // Off the main thread, but **awaited** — the one place this merge could not keep
        // main's shape.
        //
        // origin/main fires the derivative as a detached `scope.async` and only awaits it on
        // the final shot, to "overlap native display derivatives with rearrange". That
        // overlap has nothing left to overlap with: the rearrange window is now the review,
        // and the review *shows the still*, so its derivative is needed immediately rather
        // than at leisure. Leaving it detached meant `shots` was still empty when
        // reviewLastShot() read it, so the guest reviewed a blank card.
        //
        // Awaiting also removes the `capturesCompleted` counter main added to track "USB
        // done, derivative maybe not". With the await, `shots.size` is authoritative again —
        // which retake needs, because dropLastShot() shrinks `shots` and a separate counter
        // would drift from it and mis-terminate the strip.
        //
        // The decode still runs on Dispatchers.Default, so the viewfinder does not stutter;
        // the cost is ~250ms before the still appears, which is not perceptible.
        withContext(Dispatchers.Default) {
            processCapturedShot(completed, showProcessingStatus = isLastCapture)
        }
        return true
    }

    private fun markShotFailed(log: String) {
        host.setStatus(host.string(R.string.canon_status_capture_failed))
        host.setShutterEnabled(!host.request.autoStart)
        CanonLog.e(log)
    }

    private suspend fun processCapturedShot(
        done: CaptureQueue.Item.Done,
        showProcessingStatus: Boolean,
    ) {
        if (showProcessingStatus) {
            withContext(Dispatchers.Main.immediate) {
                host.setStatus(host.string(R.string.canon_status_processing))
            }
        }

        val original = done.image.file
        val derivative =
            DisplayDerivative.create(
                original = original,
                maxLongEdge = host.request.displayMaxLongEdge,
                jpegQuality = host.request.displayJpegQuality,
            )

        withContext(Dispatchers.Main.immediate) {
            if (!host.isUiAlive()) return@withContext
            shots +=
                CaptureSessionContract.Shot(
                    originalPath = original.absolutePath,
                    displayPath = derivative?.file?.absolutePath,
                    widthPx = derivative?.originalWidthPx ?: 0,
                    heightPx = derivative?.originalHeightPx ?: 0,
                    bytes = done.image.sizeBytes,
                    capturedAtMs = System.currentTimeMillis(),
                )

            CanonLog.i(
                "Shot %d/%d stored: %s (%d bytes, %dms)",
                shots.size,
                host.request.shotCount,
                original.name,
                done.image.sizeBytes,
                done.elapsedMs,
            )

            host.fillThumb(shots.size, derivative?.thumbnailBitmap)

            // A landed shot is proof the guest is still there, so the idle clock starts over.
            host.startIdleWatchdog()

            // Deliberately does NOT finish the session on the last shot.
            //
            // [CanonCaptureActivity] owns completion, because the final still has to sit in
            // review first with Retake and "Pick a look" available. Finishing here returned
            // to Dart the instant the shot landed, so the guest never saw their last shot
            // and could not retake it.
            if (shots.size < host.request.shotCount && !host.isCaptureJobActive()) {
                // Only hand the button back when nothing is driving the strip. Keyed on the job
                // rather than on autoStart because runShotSequence continues straight into the
                // next countdown, and re-enabling mid-strip would offer a press that does nothing.
                host.setStatus(
                    host.string(
                        R.string.canon_status_ready_format,
                        shots.size + 1,
                        host.request.shotCount,
                    ),
                )
                host.setShutterEnabled(true)
            }
        }
    }

    private companion object {
        /**
         * Shutter to image-on-disk.
         *
         * Wide because the body can answer `DeviceBusy` for ~8s after a release while the
         * image is still in its buffer (`P-18`), and the download itself follows.
         */
        const val CAPTURE_TIMEOUT_MS = 45_000L
    }
}
