package com.srisarani.fotozenai.canoncapture

import com.google.common.truth.Truth.assertThat
import com.srisarani.fotozenai.R
import org.junit.Test

class CanonCaptureThumbsTest {
    @Test
    fun `active slot uses the amber chrome`() {
        assertThat(CanonCaptureThumbs.backgroundRes(filled = false, active = true))
            .isEqualTo(R.drawable.bg_canon_thumb_slot_active)
        assertThat(CanonCaptureThumbs.backgroundRes(filled = true, active = false))
            .isEqualTo(R.drawable.bg_canon_thumb_slot_filled)
        assertThat(CanonCaptureThumbs.backgroundRes(filled = false, active = false))
            .isEqualTo(R.drawable.bg_canon_thumb_slot_empty)
    }

    @Test
    fun `number color and last-slot margin`() {
        assertThat(CanonCaptureThumbs.numberColor(active = true))
            .isEqualTo(CanonCaptureThumbs.NUMBER_ACTIVE)
        assertThat(CanonCaptureThumbs.numberColor(active = false))
            .isEqualTo(CanonCaptureThumbs.NUMBER_IDLE)
        assertThat(CanonCaptureThumbs.endMarginDp(0, shotCount = 4)).isEqualTo(CanonCaptureThumbs.GAP_DP)
        assertThat(CanonCaptureThumbs.endMarginDp(3, shotCount = 4)).isEqualTo(0)
    }
}
