package com.srisarani.fotozenai.canoncapture

import com.srisarani.fotozenai.R

internal enum class ReviewOutcome { ACCEPT, RETAKE }

/**
 * Copy and timing for the still-review hold.
 *
 * Extracted from [CanonCaptureActivity] so the banner/when-trees do not inflate the
 * Activity's file complexity.
 */
internal object CanonCaptureReview {

    fun holdMs(request: CaptureSessionContract.Request, shotsTaken: Int): Int {
        val isLast = shotsTaken >= request.shotCount
        return if (isLast) request.finalReviewHoldMs else request.reviewHoldMs
    }

    fun retakeLabelRes(isStrip: Boolean): Int =
        if (isStrip) R.string.canon_capture_retake_last else R.string.canon_capture_retake

    fun shutterLabelRes(isStrip: Boolean, isLast: Boolean): Int = when {
        !isStrip -> R.string.canon_capture_continue
        isLast -> R.string.canon_capture_pick_look
        else -> R.string.canon_capture_next_shot
    }

    fun bannerText(
        secondsLeft: Int,
        isLast: Boolean,
        isStrip: Boolean,
        nextShot: Int,
        shotCount: Int,
        resolve: (Int, Array<out Any>) -> String,
    ): String {
        return if (isLast || !isStrip) {
            lastShotBanner(secondsLeft, resolve)
        } else {
            rearrangeBanner(secondsLeft, nextShot, shotCount, resolve)
        }
    }

    private fun lastShotBanner(
        secondsLeft: Int,
        resolve: (Int, Array<out Any>) -> String,
    ): String {
        return if (secondsLeft <= 0) {
            resolve(R.string.canon_review_last_shot, emptyArray())
        } else {
            resolve(R.string.canon_review_last_shot_countdown_format, arrayOf(secondsLeft))
        }
    }

    private fun rearrangeBanner(
        secondsLeft: Int,
        nextShot: Int,
        shotCount: Int,
        resolve: (Int, Array<out Any>) -> String,
    ): String {
        return if (secondsLeft <= 0) {
            resolve(R.string.canon_review_rearrange_format, arrayOf(nextShot, shotCount))
        } else {
            resolve(
                R.string.canon_review_rearrange_countdown_format,
                arrayOf(nextShot, shotCount, secondsLeft),
            )
        }
    }
}
