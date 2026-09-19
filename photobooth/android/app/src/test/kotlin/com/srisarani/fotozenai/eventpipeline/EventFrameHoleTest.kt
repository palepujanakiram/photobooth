package com.srisarani.fotozenai.eventpipeline

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Rect
import com.google.common.truth.Truth.assertThat
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class EventFrameHoleTest {

    @Test
    fun `caption-bar overlay yields an inset photo window`() {
        // 10×16 JustMarried-style: gold footer, transparent window above.
        val pixels = IntArray(10 * 16) { opaqueGold() }
        fillRect(pixels, 10, left = 1, top = 1, right = 9, bottom = 12, color = 0)
        val hole = EventFrameHole.findTransparentHole(10, 16, pixels)
        assertThat(hole).isEqualTo(EventFrameHole.Box(1, 1, 8, 11))
        assertThat(EventFrameHole.isPartialPhotoHole(hole!!, 10, 16)).isTrue()
    }

    @Test
    fun `full-bleed cutout keeps the legacy cover-the-sheet path`() {
        val pixels = IntArray(10 * 10) { 0 }
        fillRect(pixels, 10, 0, 0, 10, 10, 0)
        val hole = EventFrameHole.findTransparentHole(10, 10, pixels)
        assertThat(hole).isNotNull()
        assertThat(EventFrameHole.isPartialPhotoHole(hole!!, 10, 10)).isFalse()
    }

    @Test
    fun `opaque overlay has no hole`() {
        val pixels = IntArray(8 * 8) { opaqueGold() }
        assertThat(EventFrameHole.findTransparentHole(8, 8, pixels)).isNull()
    }

    @Test
    fun `cover-crop of a tall capture into a short window is centered`() {
        val crop = EventFrameHole.coverCropSource(srcW = 100, srcH = 200, destW = 80, destH = 80)
        assertThat(crop.width).isEqualTo(100)
        assertThat(crop.height).isEqualTo(100)
        assertThat(crop.top).isEqualTo(50)
    }

    @Test
    fun `cover-crop of a wide capture into a tall window crops the sides`() {
        val crop = EventFrameHole.coverCropSource(srcW = 200, srcH = 100, destW = 80, destH = 120)
        assertThat(crop.height).isEqualTo(100)
        assertThat(crop.left).isGreaterThan(0)
        assertThat(crop.right).isLessThan(200)
    }

    @Test
    fun `hole maps through a letterboxed dest`() {
        val hole = EventFrameHole.Box(10, 20, 80, 60)
        val mapped = EventFrameHole.mapToDest(
            hole,
            srcW = 100,
            srcH = 100,
            destLeft = 10,
            destTop = 20,
            destW = 50,
            destH = 50,
        )
        assertThat(mapped).isEqualTo(EventFrameHole.Box(15, 30, 40, 30))
    }

    @Test
    fun `photoDestOnCanvas ignores full-bleed frames`() {
        val frame = Bitmap.createBitmap(20, 20, Bitmap.Config.ARGB_8888)
        frame.eraseColor(Color.TRANSPARENT)
        val dest = EventFrameCompositor.fittedRect(20, 20, 20, 20)
        assertThat(EventFrameCompositor.photoDestOnCanvas(frame, dest)).isNull()
        frame.recycle()
    }

    @Test
    fun `photoDestOnCanvas maps a caption-bar hole onto the canvas`() {
        val frame = captionBarFrame(40, 60)
        val dest = Rect(0, 0, 40, 60)
        val hole = EventFrameCompositor.photoDestOnCanvas(frame, dest)
        assertThat(hole).isNotNull()
        assertThat(hole!!.top).isGreaterThan(0)
        assertThat(hole.bottom).isLessThan(60)
        assertThat(hole.height()).isGreaterThan(hole.top)
        frame.recycle()
    }

    @Test
    fun `overlay sample size stays a power of two`() {
        assertThat(EventFrameCompositor.overlaySampleSize(1000, 2000)).isEqualTo(1)
        assertThat(EventFrameCompositor.overlaySampleSize(4000, 2000)).isEqualTo(2)
        assertThat(EventFrameCompositor.overlaySampleSize(8000, 2000)).isEqualTo(4)
        assertThat(EventFrameCompositor.overlaySampleSize(16000, 2000)).isEqualTo(8)
    }

    @Test
    fun `fittedRect letterboxes a mismatched frame`() {
        val dest = EventFrameCompositor.fittedRect(10, 20, 100, 100)
        assertThat(dest.width()).isEqualTo(50)
        assertThat(dest.height()).isEqualTo(100)
        assertThat(dest.left).isEqualTo(25)
    }

    private fun captionBarFrame(width: Int, height: Int): Bitmap {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val inset = 2
        val footer = (height * 0.22).toInt()
        for (y in 0 until height) {
            for (x in 0 until width) {
                val inWindow =
                    x in inset until (width - inset) &&
                        y in inset until (height - footer)
                bitmap.setPixel(x, y, if (inWindow) Color.TRANSPARENT else opaqueGold())
            }
        }
        return bitmap
    }

    private fun fillRect(
        pixels: IntArray,
        stride: Int,
        left: Int,
        top: Int,
        right: Int,
        bottom: Int,
        color: Int,
    ) {
        for (y in top until bottom) {
            for (x in left until right) {
                pixels[y * stride + x] = color
            }
        }
    }

    private fun opaqueGold(): Int = (0xFF shl 24) or (0xC9 shl 16) or (0xB4 shl 8) or 0x7A
}
