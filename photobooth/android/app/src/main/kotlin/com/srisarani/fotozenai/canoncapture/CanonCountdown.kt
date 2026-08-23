package com.srisarani.fotozenai.canoncapture

import android.view.View
import android.widget.TextView
import kotlinx.coroutines.delay

internal class CanonCountdownViews(
    val countdown: TextView,
    val headline: TextView,
    val scrim: View,
    val group: View,
)

internal class CanonCountdownActions(
    val isFinished: () -> Boolean,
    val setStatus: (String) -> Unit,
    val beep: () -> Unit,
    val introText: () -> String,
    val poseStatus: (Int, Int) -> String,
)

/**
 * Pose countdown overlay.
 *
 * Extracted from [CanonCaptureActivity] so the tick loop does not inflate the Activity's
 * file complexity. Timing and headline rules match the previous inline method.
 */
internal class CanonCountdown(
    private val views: CanonCountdownViews,
    private val actions: CanonCountdownActions,
) {

    suspend fun run(shotNumber: Int, request: CaptureSessionContract.Request) {
        // FotoZen only, and only on the first tick: Classic already says "shot X of Y" in the
        // subtitle and the status line, so repeating it over the preview is noise.
        // Mirrors `showAiIntro` in _buildCountdownOverlay.
        val showHeadline = request.showCountdownHeadline
        views.headline.text = actions.introText()

        for (remaining in request.countdownSeconds downTo 1) {
            if (actions.isFinished()) return
            views.scrim.visibility = View.VISIBLE
            views.group.visibility = View.VISIBLE
            views.headline.visibility =
                if (showHeadline && remaining == request.countdownSeconds) {
                    View.VISIBLE
                } else {
                    View.GONE
                }
            views.countdown.visibility = View.VISIBLE
            views.countdown.text = remaining.toString()
            actions.setStatus(actions.poseStatus(shotNumber, request.shotCount))
            if (remaining <= COUNTDOWN_BEEP_FROM) actions.beep()
            delay(1000)
        }
        hide()
    }

    fun hide() {
        views.countdown.visibility = View.GONE
        views.headline.visibility = View.GONE
        views.group.visibility = View.GONE
        views.scrim.visibility = View.GONE
    }

    private companion object {
        /** Beep only on the closing seconds — a beep every second for 10s is irritating. */
        const val COUNTDOWN_BEEP_FROM = 3
    }
}
