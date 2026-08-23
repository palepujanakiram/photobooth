package com.srisarani.fotozenai.canoncapture

import com.google.common.truth.Truth.assertThat
import com.srisarani.fotozenai.R
import org.junit.Test

class CanonCaptureReviewTest {
    private val request = CaptureSessionContract.Request(shotCount = 4, reviewHoldMs = 8000, finalReviewHoldMs = 2000)

    @Test
    fun `hold uses the final window on the last shot`() {
        assertThat(CanonCaptureReview.holdMs(request, shotsTaken = 3)).isEqualTo(8000)
        assertThat(CanonCaptureReview.holdMs(request, shotsTaken = 4)).isEqualTo(2000)
    }

    @Test
    fun `labels switch between continue retake and pick a look`() {
        assertThat(CanonCaptureReview.retakeLabelRes(isStrip = false))
            .isEqualTo(R.string.canon_capture_retake)
        assertThat(CanonCaptureReview.retakeLabelRes(isStrip = true))
            .isEqualTo(R.string.canon_capture_retake_last)
        assertThat(CanonCaptureReview.shutterLabelRes(isStrip = false, isLast = true))
            .isEqualTo(R.string.canon_capture_continue)
        assertThat(CanonCaptureReview.shutterLabelRes(isStrip = true, isLast = true))
            .isEqualTo(R.string.canon_capture_pick_look)
        assertThat(CanonCaptureReview.shutterLabelRes(isStrip = true, isLast = false))
            .isEqualTo(R.string.canon_capture_next_shot)
    }

    @Test
    fun `banner copy matches last-shot and rearrange windows`() {
        val seen = mutableListOf<Int>()
        val resolve: (Int, Array<out Any>) -> String = { id, args ->
            seen += id
            args.joinToString(",")
        }
        CanonCaptureReview.bannerText(
            ReviewBannerInput(0, isLast = true, isStrip = false, nextShot = 2, shotCount = 4),
            resolve,
        )
        assertThat(seen.last()).isEqualTo(R.string.canon_review_last_shot)

        CanonCaptureReview.bannerText(
            ReviewBannerInput(3, isLast = true, isStrip = false, nextShot = 2, shotCount = 4),
            resolve,
        )
        assertThat(seen.last()).isEqualTo(R.string.canon_review_last_shot_countdown_format)

        val rearrange =
            CanonCaptureReview.bannerText(
                ReviewBannerInput(0, isLast = false, isStrip = true, nextShot = 2, shotCount = 4),
                resolve,
            )
        assertThat(rearrange).isEqualTo("2,4")
        assertThat(seen.last()).isEqualTo(R.string.canon_review_rearrange_format)

        val counting =
            CanonCaptureReview.bannerText(
                ReviewBannerInput(5, isLast = false, isStrip = true, nextShot = 2, shotCount = 4),
                resolve,
            )
        assertThat(counting).isEqualTo("2,4,5")
        assertThat(seen.last()).isEqualTo(R.string.canon_review_rearrange_countdown_format)
    }
}
