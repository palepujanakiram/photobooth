package com.srisarani.fotozenai.canoncapture

import android.graphics.Rect
import com.google.common.truth.Truth.assertThat
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Viewfinder letterboxing.
 *
 * This is fit, not fill, on purpose: a crop would hide part of what the sensor is going to
 * record, so guests would frame a shot against a lie.
 */
@RunWith(RobolectricTestRunner::class)
class LiveViewSurfaceRendererTest {

    private fun fit(sw: Int, sh: Int, dw: Int, dh: Int): Rect =
        LiveViewSurfaceRenderer.fitCentre(sw, sh, dw, dh, Rect())

    @Test
    fun `a 3-2 frame in a 16-9 surface is pillarboxed and centred`() {
        val r = fit(960, 640, 1920, 1080)
        assertThat(r.height()).isEqualTo(1080)
        assertThat(r.width()).isEqualTo(1620)
        assertThat(r.left).isEqualTo((1920 - 1620) / 2)
        assertThat(r.right - r.left).isEqualTo(1620)
    }

    @Test
    fun `a wide frame in a tall surface is letterboxed and centred`() {
        val r = fit(1920, 1080, 1080, 1920)
        assertThat(r.width()).isEqualTo(1080)
        assertThat(r.height()).isEqualTo(608)
        assertThat(r.top).isEqualTo((1920 - 608) / 2)
    }

    @Test
    fun `aspect ratio is preserved within a pixel`() {
        val r = fit(960, 640, 1000, 1000)
        val sourceRatio = 960.0 / 640.0
        val drawnRatio = r.width().toDouble() / r.height()
        assertThat(Math.abs(drawnRatio - sourceRatio)).isLessThan(0.01)
    }

    @Test
    fun `an exact-fit frame fills the surface with no offset`() {
        val r = fit(1920, 1080, 1920, 1080)
        assertThat(r.left).isEqualTo(0)
        assertThat(r.top).isEqualTo(0)
        assertThat(r.width()).isEqualTo(1920)
        assertThat(r.height()).isEqualTo(1080)
    }

    @Test
    fun `a small frame is scaled up to fit rather than left tiny`() {
        // Live view frames are a few hundred pixels wide; drawing them at natural size
        // would leave a postage stamp in the middle of the screen.
        val r = fit(480, 320, 1920, 1080)
        assertThat(r.height()).isEqualTo(1080)
        assertThat(r.width()).isEqualTo(1620)
    }

    @Test
    fun `degenerate inputs produce a safe rect instead of dividing by zero`() {
        // Called from a render loop; a throw here kills the viewfinder.
        assertThat(fit(0, 0, 1920, 1080).width()).isEqualTo(1920)
        assertThat(fit(960, 640, 0, 0).isEmpty).isTrue()
        assertThat(fit(-5, -5, 1920, 1080).width()).isEqualTo(1920)
    }
}
