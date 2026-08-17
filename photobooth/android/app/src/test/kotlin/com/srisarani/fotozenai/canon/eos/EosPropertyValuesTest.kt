package com.srisarani.fotozenai.canon.eos

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class EosPropertyValuesTest {

    /**
     * Live corroboration from this body's event stream, 2026-08-13.
     *
     * The M4 capture log showed `PropertyChanged(propertyCode=53505, rawValue=[43,...])` —
     * 53505 is 0xD101 (Aperture) and 43 is 0x2B — while the lens was at f/4.5. Likewise
     * 0xD102 (ShutterSpeed) reported 0x70 for 1/125. Two independent points landing on the
     * transcribed table is meaningful evidence the encoding is right.
     */
    @Test
    fun `aperture and shutter match values observed on hardware`() {
        assertThat(EosPropertyValues.APERTURE[0x2B]).isEqualTo("f/4.5")
        assertThat(EosPropertyValues.SHUTTER[0x70]).isEqualTo("1/125")
    }

    /**
     * The encoding is systematic: within a scale each 1/3 stop is +3 and each full stop is
     * +8. Verifying that on known anchor points catches a mistyped entry, which is the
     * likeliest error in a hand-transcribed table.
     */
    @Test
    fun `aperture full stops are eight apart`() {
        // f/2.8 -> f/4 -> f/5.6 -> f/8 -> f/11 -> f/16 -> f/22
        assertThat(EosPropertyValues.APERTURE[0x20]).isEqualTo("f/2.8")
        assertThat(EosPropertyValues.APERTURE[0x28]).isEqualTo("f/4.0")
        assertThat(EosPropertyValues.APERTURE[0x30]).isEqualTo("f/5.6")
        assertThat(EosPropertyValues.APERTURE[0x38]).isEqualTo("f/8")
        assertThat(EosPropertyValues.APERTURE[0x40]).isEqualTo("f/11")
        assertThat(EosPropertyValues.APERTURE[0x48]).isEqualTo("f/16")
        assertThat(EosPropertyValues.APERTURE[0x50]).isEqualTo("f/22")
    }

    @Test
    fun `iso full stops are eight apart and double`() {
        assertThat(EosPropertyValues.ISO[0x48]).isEqualTo("100")
        assertThat(EosPropertyValues.ISO[0x50]).isEqualTo("200")
        assertThat(EosPropertyValues.ISO[0x58]).isEqualTo("400")
        assertThat(EosPropertyValues.ISO[0x60]).isEqualTo("800")
        assertThat(EosPropertyValues.ISO[0x68]).isEqualTo("1600")
        assertThat(EosPropertyValues.ISO[0x70]).isEqualTo("3200")
        assertThat(EosPropertyValues.ISO[0x78]).isEqualTo("6400")
    }

    @Test
    fun `shutter full stops halve the exposure time`() {
        assertThat(EosPropertyValues.SHUTTER[0x60]).isEqualTo("1/30")
        assertThat(EosPropertyValues.SHUTTER[0x68]).isEqualTo("1/60")
        assertThat(EosPropertyValues.SHUTTER[0x70]).isEqualTo("1/125")
        assertThat(EosPropertyValues.SHUTTER[0x78]).isEqualTo("1/250")
        assertThat(EosPropertyValues.SHUTTER[0x80]).isEqualTo("1/500")
        assertThat(EosPropertyValues.SHUTTER[0x88]).isEqualTo("1/1000")
    }

    /**
     * An unrecognised value must stay visible. What the camera is *actually* set to matters
     * more than our ability to name it — hiding it would make the UI lie.
     */
    @Test
    fun `unknown raw values render as hex rather than disappearing`() {
        assertThat(EosPropertyValues.label(EosPropertyValues.ISO, 0xFE)).isEqualTo("0xFE")
        assertThat(EosPropertyValues.label(EosPropertyValues.APERTURE, 0x99)).isEqualTo("0x99")
    }

    // ================================================================ stepping

    @Test
    fun `stepping moves one third-stop at a time`() {
        val next = EosPropertyValues.step(EosPropertyValues.APERTURE, 0x28, forward = true)

        assertThat(EosPropertyValues.APERTURE[next.toInt()]).isEqualTo("f/4.5")
    }

    @Test
    fun `stepping backwards moves the other way`() {
        val previous = EosPropertyValues.step(EosPropertyValues.APERTURE, 0x28, forward = false)

        assertThat(EosPropertyValues.APERTURE[previous.toInt()]).isEqualTo("f/3.5")
    }

    /** Stepping must clamp, not wrap: rolling f/32 round to f/1.0 would be alarming. */
    @Test
    fun `stepping clamps at both ends`() {
        val maxAperture = EosPropertyValues.APERTURE.keys.max().toLong()
        val minAperture = EosPropertyValues.APERTURE.keys.min().toLong()

        assertThat(EosPropertyValues.step(EosPropertyValues.APERTURE, maxAperture, true))
            .isEqualTo(maxAperture)
        assertThat(EosPropertyValues.step(EosPropertyValues.APERTURE, minAperture, false))
            .isEqualTo(minAperture)
    }

    @Test
    fun `canStep reports the ends correctly`() {
        val max = EosPropertyValues.APERTURE.keys.max().toLong()

        assertThat(EosPropertyValues.canStep(EosPropertyValues.APERTURE, max, forward = true)).isFalse()
        assertThat(EosPropertyValues.canStep(EosPropertyValues.APERTURE, max, forward = false)).isTrue()
    }

    @Test
    fun `stepping from an unknown value lands on a known one`() {
        val result = EosPropertyValues.step(EosPropertyValues.ISO, 0xFE, forward = true)

        assertThat(EosPropertyValues.ISO).containsKey(result.toInt())
    }

    // ================================================================ C-04

    /**
     * `C-04`: the mode dial is physical. In Auto and scene positions the camera owns
     * exposure and rejects writes with unhelpful errors, so the UI must gate on this
     * rather than let the user find out by failure.
     */
    @Test
    fun `exposure control is allowed only in the creative modes`() {
        // P, Tv, Av, M, Bulb
        listOf(0L, 1L, 2L, 3L, 4L).forEach {
            assertThat(EosPropertyValues.allowsExposureControl(it)).isTrue()
        }
        // Auto, scene modes
        listOf(9L, 11L, 12L, 13L, 21L).forEach {
            assertThat(EosPropertyValues.allowsExposureControl(it)).isFalse()
        }
    }

    @Test
    fun `shooting mode labels cover the dial positions we gate on`() {
        assertThat(EosPropertyValues.SHOOTING_MODE[3]).isEqualTo("M")
        assertThat(EosPropertyValues.SHOOTING_MODE[2]).isEqualTo("Av")
        assertThat(EosPropertyValues.SHOOTING_MODE[1]).isEqualTo("Tv")
    }

    /**
     * `P-20`: the low values are an enum, not a percentage. A 200D II with useful charge
     * reports raw 2; rendering that as "2%" reads as a dead battery and is the kind of
     * false alarm that gets a healthy battery swapped mid-event.
     */
    @Test
    fun `low battery values are levels, not percentages`() {
        assertThat(EosPropertyValues.batteryLabel(0)).isEqualTo("Empty")
        assertThat(EosPropertyValues.batteryLabel(1)).isEqualTo("Low")
        assertThat(EosPropertyValues.batteryLabel(2)).isEqualTo("Half")
        assertThat(EosPropertyValues.batteryLabel(3)).isEqualTo("Full")
    }

    @Test
    fun `battery values above the enum range render as a percentage`() {
        assertThat(EosPropertyValues.batteryLabel(75)).isEqualTo("75%")
    }

    /** Plan §2 locks the camera to sRGB; the label must make a wrong setting obvious. */
    @Test
    fun `colour space labels distinguish sRGB from AdobeRGB`() {
        assertThat(EosPropertyValues.COLOR_SPACE[1]).isEqualTo("sRGB")
        assertThat(EosPropertyValues.COLOR_SPACE[2]).isEqualTo("AdobeRGB")
    }

    @Test
    fun `tables are ordered so stepping follows the natural setting order`() {
        listOf(EosPropertyValues.ISO, EosPropertyValues.APERTURE, EosPropertyValues.SHUTTER)
            .forEach { table ->
                val keys = table.keys.toList()
                assertThat(keys).isEqualTo(keys.sorted())
            }
    }
}
