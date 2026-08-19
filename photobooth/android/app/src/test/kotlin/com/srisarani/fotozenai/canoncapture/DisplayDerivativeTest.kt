package com.srisarani.fotozenai.canoncapture

import com.google.common.truth.Truth.assertThat
import org.junit.Test

/**
 * The subsample maths behind the display derivative.
 *
 * Worth pinning precisely: getting it wrong is not a visible bug but a memory one. Decoding
 * a 6000×4000 original one step too shallow is a 96 MB allocation on a box with a 256 MB
 * heap, and it fails as an OOM somewhere unrelated.
 */
class DisplayDerivativeTest {

    @Test
    fun `24MP original subsamples to just above the target`() {
        // 6000 / 2 = 3000, still >= 1920, so stop there. Going to 4 would give 1500 and
        // throw away detail the final scale needs.
        assertThat(DisplayDerivative.sampleSizeFor(6000, 4000, 1920)).isEqualTo(2)
    }

    @Test
    fun `an image already at the target is not subsampled`() {
        assertThat(DisplayDerivative.sampleSizeFor(1920, 1280, 1920)).isEqualTo(1)
    }

    @Test
    fun `an image smaller than the target is not subsampled`() {
        assertThat(DisplayDerivative.sampleSizeFor(800, 600, 1920)).isEqualTo(1)
    }

    @Test
    fun `sample sizes are powers of two`() {
        // BitmapFactory silently rounds a non-power-of-two down to 1, which would decode
        // the full original — the exact allocation this is meant to avoid.
        for (width in listOf(2000, 4000, 6000, 8000, 12000, 24000)) {
            val sample = DisplayDerivative.sampleSizeFor(width, width / 2, 1920)
            assertThat(sample and (sample - 1)).isEqualTo(0)
        }
    }

    @Test
    fun `portrait orientation uses the long edge`() {
        assertThat(DisplayDerivative.sampleSizeFor(4000, 6000, 1920)).isEqualTo(2)
    }

    @Test
    fun `degenerate dimensions fall back to no subsampling rather than dividing by zero`() {
        assertThat(DisplayDerivative.sampleSizeFor(0, 0, 1920)).isEqualTo(1)
        assertThat(DisplayDerivative.sampleSizeFor(6000, 4000, 0)).isEqualTo(1)
        assertThat(DisplayDerivative.sampleSizeFor(-1, -1, 1920)).isEqualTo(1)
    }

    @Test
    fun `scaled size hits the target long edge and keeps the aspect ratio`() {
        val (w, h) = DisplayDerivative.scaledSize(3000, 2000, 1920)
        assertThat(w).isEqualTo(1920)
        assertThat(h).isEqualTo(1280)
    }

    @Test
    fun `scaled size never upscales`() {
        // Upscaling would inflate the file with invented pixels and gain nothing.
        val (w, h) = DisplayDerivative.scaledSize(800, 600, 1920)
        assertThat(w).isEqualTo(800)
        assertThat(h).isEqualTo(600)
    }

    @Test
    fun `scaled size keeps portrait portrait`() {
        val (w, h) = DisplayDerivative.scaledSize(2000, 3000, 1920)
        assertThat(h).isEqualTo(1920)
        assertThat(w).isEqualTo(1280)
    }

    @Test
    fun `scaled size never collapses a very wide image to zero`() {
        val (w, h) = DisplayDerivative.scaledSize(10000, 3, 1920)
        assertThat(w).isEqualTo(1920)
        assertThat(h).isAtLeast(1)
    }

    @Test
    fun `the full pipeline lands within one step of the target`() {
        // What actually matters end to end: after subsample then scale, the long edge is
        // exactly the target and the decode never held more than 4x the final pixels.
        val sample = DisplayDerivative.sampleSizeFor(6000, 4000, 1920)
        val decodedW = 6000 / sample
        val decodedH = 4000 / sample
        val (finalW, finalH) = DisplayDerivative.scaledSize(decodedW, decodedH, 1920)

        assertThat(finalW).isEqualTo(1920)
        assertThat(finalH).isEqualTo(1280)
        assertThat(decodedW.toLong() * decodedH).isLessThan(finalW.toLong() * finalH * 4)
    }

    @Test
    fun `thumbnail bitmap downsamples for strip UI`() {
        val (w, h) = DisplayDerivative.scaledSize(1600, 1200, DisplayDerivative.THUMBNAIL_LONG_EDGE)
        assertThat(w).isEqualTo(DisplayDerivative.THUMBNAIL_LONG_EDGE)
        assertThat(h).isEqualTo(240)
    }
}
