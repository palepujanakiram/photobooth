package com.srisarani.fotozenai

import android.view.View
import androidx.activity.ComponentActivity
import androidx.core.graphics.Insets
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.google.common.truth.Truth.assertThat
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

@RunWith(RobolectricTestRunner::class)
class EdgeToEdgeDisplayTest {
    @Test
    fun `system bar insets become view padding`() {
        val view = View(RuntimeEnvironment.getApplication())
        EdgeToEdgeDisplay.applySystemBarPadding(view, Insets.of(10, 48, 12, 72))
        assertThat(view.paddingLeft).isEqualTo(10)
        assertThat(view.paddingTop).isEqualTo(48)
        assertThat(view.paddingRight).isEqualTo(12)
        assertThat(view.paddingBottom).isEqualTo(72)
    }

    @Test
    fun `top chrome can omit the navigation-bar inset`() {
        val view = View(RuntimeEnvironment.getApplication())
        EdgeToEdgeDisplay.applySystemBarPadding(
            view,
            Insets.of(10, 48, 12, 72),
            includeBottom = false,
        )
        assertThat(view.paddingTop).isEqualTo(48)
        assertThat(view.paddingBottom).isEqualTo(0)
    }

    @Test
    fun `window insets are consumed after padding the view`() {
        val view = View(RuntimeEnvironment.getApplication())
        val insets =
            WindowInsetsCompat.Builder()
                .setInsets(
                    WindowInsetsCompat.Type.systemBars(),
                    Insets.of(0, 40, 0, 24),
                ).build()
        val remaining = EdgeToEdgeDisplay.applySystemBarPadding(view, insets)
        assertThat(remaining).isEqualTo(WindowInsetsCompat.CONSUMED)
        assertThat(view.paddingTop).isEqualTo(40)
        assertThat(view.paddingBottom).isEqualTo(24)
    }

    @Test
    fun `display cutout is included when it is larger than system bars`() {
        val view = View(RuntimeEnvironment.getApplication())
        val insets =
            WindowInsetsCompat.Builder()
                .setInsets(
                    WindowInsetsCompat.Type.systemBars(),
                    Insets.of(0, 24, 0, 0),
                ).setInsets(
                    WindowInsetsCompat.Type.displayCutout(),
                    Insets.of(0, 48, 0, 0),
                ).build()
        EdgeToEdgeDisplay.applySystemBarPadding(view, insets)
        assertThat(view.paddingTop).isEqualTo(48)
    }

    @Test
    fun `bindSystemBarPadding applies insets when they are dispatched`() {
        val view = View(RuntimeEnvironment.getApplication())
        EdgeToEdgeDisplay.bindSystemBarPadding(view)
        val insets =
            WindowInsetsCompat.Builder()
                .setInsets(
                    WindowInsetsCompat.Type.systemBars(),
                    Insets.of(4, 30, 6, 18),
                ).build()
        ViewCompat.dispatchApplyWindowInsets(view, insets)
        assertThat(view.paddingLeft).isEqualTo(4)
        assertThat(view.paddingTop).isEqualTo(30)
        assertThat(view.paddingRight).isEqualTo(6)
        assertThat(view.paddingBottom).isEqualTo(18)
    }

    @Test
    fun `bindSystemBarPadding can omit the bottom inset`() {
        val view = View(RuntimeEnvironment.getApplication())
        EdgeToEdgeDisplay.bindSystemBarPadding(view, includeBottom = false)
        val insets =
            WindowInsetsCompat.Builder()
                .setInsets(
                    WindowInsetsCompat.Type.systemBars(),
                    Insets.of(0, 30, 0, 18),
                ).build()
        ViewCompat.dispatchApplyWindowInsets(view, insets)
        assertThat(view.paddingTop).isEqualTo(30)
        assertThat(view.paddingBottom).isEqualTo(0)
    }

    @Test
    fun `enable does not throw on a ComponentActivity`() {
        val activity = Robolectric.buildActivity(ComponentActivity::class.java).setup().get()
        EdgeToEdgeDisplay.enable(activity)
    }
}
