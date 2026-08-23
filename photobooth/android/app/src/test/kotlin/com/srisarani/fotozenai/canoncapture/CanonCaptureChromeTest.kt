package com.srisarani.fotozenai.canoncapture

import android.view.View
import com.google.common.truth.Truth.assertThat
import org.junit.Test

class CanonCaptureChromeTest {

    @Test
    fun `uploads stay visible only before the first shot`() {
        assertThat(CanonCaptureChrome.uploadVisibility(allowed = true, beforeFirstShot = true))
            .isEqualTo(View.VISIBLE)
        assertThat(CanonCaptureChrome.uploadVisibility(allowed = true, beforeFirstShot = false))
            .isEqualTo(View.GONE)
        assertThat(CanonCaptureChrome.uploadVisibility(allowed = false, beforeFirstShot = true))
            .isEqualTo(View.GONE)
    }
}
