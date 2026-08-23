package com.srisarani.fotozenai.canoncapture

import android.graphics.BitmapFactory
import android.view.View
import android.widget.Button
import android.widget.ImageView
import android.widget.TextView
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

internal class CanonReviewViews(
    val still: ImageView,
    val banner: TextView,
    val retake: Button,
    val shutter: Button,
)

internal class CanonReviewActions(
    val resolve: (Int, Array<out Any>) -> String,
    val isFinished: () -> Boolean,
    val isUiAlive: () -> Boolean,
    val clearStatus: () -> Unit,
    val restoreShutter: () -> Unit,
)

/**
 * Holds on the still just taken, offering Retake and the primary action.
 *
 * Three behaviours, chosen by Dart through [CaptureSessionContract.Request.reviewHoldMs]
 * and [CaptureSessionContract.Request.finalReviewHoldMs]:
 *
 * - **0** — wait indefinitely for a tap. FotoZen never auto-accepts.
 * - **mid-strip** — 8s rearrange window, then accept.
 * - **final shot** — 2s, then accept.
 */
internal class CanonShotReview(
    private val views: CanonReviewViews,
    private val actions: CanonReviewActions,
) {

    suspend fun present(
        request: CaptureSessionContract.Request,
        shots: List<CaptureSessionContract.Shot>,
    ): ReviewOutcome {
        val isLast = shots.size >= request.shotCount
        val holdMs = CanonCaptureReview.holdMs(request, shots.size)
        val isStrip = request.shotCount > 1

        showStill(shots.lastOrNull()?.displayPath)
        actions.clearStatus()
        applyReviewLabels(isStrip, isLast)

        val outcome = awaitChoice(holdMs, isLast, isStrip, request, shots.size)
        hideStill()
        actions.restoreShutter()
        return outcome
    }

    fun hideStill() {
        if (!actions.isUiAlive()) return
        views.still.visibility = View.GONE
        views.still.setImageDrawable(null)
    }

    private fun applyReviewLabels(isStrip: Boolean, isLast: Boolean) {
        if (!actions.isUiAlive()) return
        views.retake.text = actions.resolve(
            CanonCaptureReview.retakeLabelRes(isStrip),
            emptyArray(),
        )
        views.shutter.text = actions.resolve(
            CanonCaptureReview.shutterLabelRes(isStrip, isLast),
            emptyArray(),
        )
        // The shutter glyph belongs to "Take shot"; the review action is not a shutter.
        views.shutter.setCompoundDrawablesRelativeWithIntrinsicBounds(0, 0, 0, 0)
    }

    private suspend fun awaitChoice(
        holdMs: Int,
        isLast: Boolean,
        isStrip: Boolean,
        request: CaptureSessionContract.Request,
        shotsTaken: Int,
    ): ReviewOutcome {
        val choice = CompletableDeferred<ReviewOutcome>()
        if (!actions.isUiAlive()) return ReviewOutcome.ACCEPT
        views.retake.visibility = View.VISIBLE
        views.retake.isEnabled = true
        views.shutter.isEnabled = true
        views.retake.setOnClickListener { choice.complete(ReviewOutcome.RETAKE) }
        views.shutter.setOnClickListener { choice.complete(ReviewOutcome.ACCEPT) }
        views.shutter.requestFocus()

        try {
            return if (holdMs <= 0) {
                views.banner.visibility = View.GONE
                choice.await()
            } else {
                waitForHold(choice, holdMs, isLast, isStrip, request, shotsTaken)
            }
        } finally {
            if (actions.isUiAlive()) {
                views.retake.setOnClickListener(null)
                views.retake.visibility = View.GONE
                views.banner.visibility = View.GONE
            }
            if (!choice.isCompleted) choice.cancel()
        }
    }

    private suspend fun waitForHold(
        choice: CompletableDeferred<ReviewOutcome>,
        holdMs: Int,
        isLast: Boolean,
        isStrip: Boolean,
        request: CaptureSessionContract.Request,
        shotsTaken: Int,
    ): ReviewOutcome {
        val deadline = System.currentTimeMillis() + holdMs
        views.banner.visibility = View.VISIBLE
        while (!actions.isFinished() && System.currentTimeMillis() < deadline) {
            if (choice.isCompleted) break
            views.banner.text = bannerText(deadline, isLast, isStrip, request, shotsTaken)
            delay(REVIEW_TICK_MS)
        }
        return if (choice.isCompleted) choice.await() else ReviewOutcome.ACCEPT
    }

    private fun bannerText(
        deadlineMs: Long,
        isLast: Boolean,
        isStrip: Boolean,
        request: CaptureSessionContract.Request,
        shotsTaken: Int,
    ): String {
        val secondsLeft = ((deadlineMs - System.currentTimeMillis() + 999) / 1000).toInt()
        return CanonCaptureReview.bannerText(
            secondsLeft = secondsLeft,
            isLast = isLast,
            isStrip = isStrip,
            nextShot = shotsTaken + 1,
            shotCount = request.shotCount,
            resolve = actions.resolve,
        )
    }

    private suspend fun showStill(displayPath: String?) {
        val bitmap = displayPath?.let {
            withContext(Dispatchers.Default) {
                runCatching { BitmapFactory.decodeFile(it) }.getOrNull()
            }
        } ?: return
        if (!actions.isUiAlive()) return
        views.still.setImageBitmap(bitmap)
        views.still.visibility = View.VISIBLE
    }

    private companion object {
        const val REVIEW_TICK_MS = 200L
    }
}
