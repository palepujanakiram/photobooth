package com.srisarani.fotozenai.canon.eos

/**
 * Raw-value → human-label maps for EOS device properties.
 *
 * ⚠️ **Transcribed from libgphoto2's `config.c` encodings and NOT individually verified.**
 * Two of them do have live corroboration from this body's event stream (2026-08-13):
 * aperture reported `0x2B` while the lens was at f/4.5, and shutter reported `0x70` for
 * 1/125 — both match. That is encouraging but is not the same as checking all of them.
 *
 * The encoding is systematic rather than arbitrary: within a scale, each 1/3 stop is +3
 * and each full stop is +8. That is why the tables look sparse but regular, and it is a
 * useful sanity check when adding entries.
 *
 * An unknown raw value is rendered as hex rather than hidden — an unrecognised setting
 * must still be visible, because "the value the camera is actually on" matters more than
 * our ability to name it.
 */
object EosPropertyValues {

    /** ISO sensitivity. `0x00` is Auto. */
    val ISO = mapOf(
        0x00 to "Auto",
        0x40 to "50", 0x48 to "100", 0x4B to "125", 0x4D to "160",
        0x50 to "200", 0x53 to "250", 0x55 to "320",
        0x58 to "400", 0x5B to "500", 0x5D to "640",
        0x60 to "800", 0x63 to "1000", 0x65 to "1250",
        0x68 to "1600", 0x6B to "2000", 0x6D to "2500",
        0x70 to "3200", 0x73 to "4000", 0x75 to "5000",
        0x78 to "6400", 0x7B to "8000", 0x7D to "10000",
        0x80 to "12800", 0x88 to "25600",
    )

    /** Aperture (Av). */
    val APERTURE = mapOf(
        0x08 to "f/1.0", 0x0B to "f/1.1", 0x0D to "f/1.2",
        0x10 to "f/1.4", 0x13 to "f/1.6", 0x15 to "f/1.8",
        0x18 to "f/2.0", 0x1B to "f/2.2", 0x1D to "f/2.5",
        0x20 to "f/2.8", 0x23 to "f/3.2", 0x25 to "f/3.5",
        0x28 to "f/4.0", 0x2B to "f/4.5", 0x2D to "f/5.0",
        0x30 to "f/5.6", 0x33 to "f/6.3", 0x35 to "f/7.1",
        0x38 to "f/8", 0x3B to "f/9", 0x3D to "f/10",
        0x40 to "f/11", 0x43 to "f/13", 0x45 to "f/14",
        0x48 to "f/16", 0x4B to "f/18", 0x4D to "f/20",
        0x50 to "f/22", 0x53 to "f/25", 0x55 to "f/29",
        0x58 to "f/32",
    )

    /** Shutter speed (Tv). */
    val SHUTTER = mapOf(
        0x0C to "Bulb",
        0x10 to "30\"", 0x13 to "25\"", 0x15 to "20\"",
        0x18 to "15\"", 0x1B to "13\"", 0x1D to "10\"",
        0x20 to "8\"", 0x23 to "6\"", 0x25 to "5\"",
        0x28 to "4\"", 0x2B to "3\"2", 0x2D to "2\"5",
        0x30 to "2\"", 0x33 to "1\"6", 0x35 to "1\"3",
        0x38 to "1\"", 0x3B to "0\"8", 0x3D to "0\"6",
        0x40 to "0\"5", 0x43 to "0\"4", 0x45 to "0\"3",
        0x48 to "1/4", 0x4B to "1/5", 0x4D to "1/6",
        0x50 to "1/8", 0x53 to "1/10", 0x55 to "1/13",
        0x58 to "1/15", 0x5B to "1/20", 0x5D to "1/25",
        0x60 to "1/30", 0x63 to "1/40", 0x65 to "1/50",
        0x68 to "1/60", 0x6B to "1/80", 0x6D to "1/100",
        0x70 to "1/125", 0x73 to "1/160", 0x75 to "1/200",
        0x78 to "1/250", 0x7B to "1/320", 0x7D to "1/400",
        0x80 to "1/500", 0x83 to "1/640", 0x85 to "1/800",
        0x88 to "1/1000", 0x8B to "1/1250", 0x8D to "1/1600",
        0x90 to "1/2000", 0x93 to "1/2500", 0x95 to "1/3200",
        0x98 to "1/4000",
    )

    val WHITE_BALANCE = mapOf(
        0 to "Auto", 1 to "Daylight", 2 to "Cloudy", 3 to "Tungsten",
        4 to "Fluorescent", 5 to "Flash", 6 to "Custom", 8 to "Shade",
        9 to "Colour temp.", 15 to "Auto (white priority)",
    )

    val DRIVE_MODE = mapOf(
        0x00 to "Single", 0x01 to "Continuous", 0x02 to "Video",
        0x04 to "High speed", 0x05 to "Low speed", 0x07 to "Silent",
        0x10 to "Self-timer 10s", 0x11 to "Self-timer 2s",
        0x12 to "Self-timer cont.", 0x13 to "Silent single",
        0x14 to "Silent continuous",
    )

    val METERING_MODE = mapOf(
        1 to "Spot", 3 to "Evaluative", 4 to "Partial",
        5 to "Centre-weighted",
    )

    /**
     * Shooting mode — the physical mode dial. **Read-only.**
     *
     * `C-04`: in Auto and scene positions most properties become read-only and writes fail
     * with unhelpful errors. The UI gates on this rather than letting the user try.
     */
    val SHOOTING_MODE = mapOf(
        0 to "P", 1 to "Tv", 2 to "Av", 3 to "M", 4 to "Bulb",
        5 to "A-DEP", 6 to "DEP", 7 to "Custom",
        9 to "Auto (green)", 10 to "Night portrait", 11 to "Sports",
        12 to "Portrait", 13 to "Landscape", 14 to "Close-up",
        15 to "Flash off", 19 to "Creative auto", 21 to "Scene intelligent auto",
    )

    val COLOR_SPACE = mapOf(1 to "sRGB", 2 to "AdobeRGB")

    val FOCUS_MODE = mapOf(0 to "One Shot", 1 to "AI Servo", 2 to "AI Focus", 3 to "Manual")

    /**
     * Battery level.
     *
     * > ⚠️ **`P-20`, observed on hardware 2026-08-14: this is an enum, not a percentage.**
     * > A 200D II with plenty of charge reported raw `2`. Rendering that as "2%" sent us
     * > hunting for a charger the camera did not need — and worse, it would have a booth
     * > operator swapping a healthy battery mid-event. The earlier assumption that this
     * > property is 0–100 was wrong.
     *
     * Values 0–3 are the level enum used by EOS bodies. Anything above that is treated as a
     * percentage, since some bodies do report one; an actual 3% battery therefore shows as
     * "Low", which errs in the safe direction.
     */
    fun batteryLabel(raw: Long): String = when (raw) {
        0L -> "Empty"
        1L -> "Low"
        2L -> "Half"
        3L -> "Full"
        in 4..100 -> "$raw%"
        else -> "0x%02X".format(raw)
    }

    /**
     * Modes in which exposure properties are writable.
     *
     * In every other dial position the camera owns exposure and rejects writes (`C-04`).
     */
    private val MANUAL_CAPABLE_MODES = setOf(0, 1, 2, 3, 4)

    fun allowsExposureControl(shootingModeRaw: Long): Boolean =
        shootingModeRaw.toInt() in MANUAL_CAPABLE_MODES

    /** Looks up a label, falling back to hex so unknown values remain visible. */
    fun label(table: Map<Int, String>, raw: Long): String =
        table[raw.toInt()] ?: "0x%02X".format(raw)

    /**
     * Next value in a table, for the `←/→` stepper.
     *
     * Tables are ordered by raw value, which for these encodings is also the natural
     * ordering of the setting — brighter to darker, wider to narrower. That is why a
     * stepper works at all without a separate ordering list.
     */
    fun step(table: Map<Int, String>, current: Long, forward: Boolean): Long {
        val keys = table.keys.sorted()
        if (keys.isEmpty()) return current
        val index = keys.indexOf(current.toInt())
        if (index < 0) return keys.first().toLong()
        val next = if (forward) index + 1 else index - 1
        return keys[next.coerceIn(0, keys.size - 1)].toLong()
    }

    fun canStep(table: Map<Int, String>, current: Long, forward: Boolean): Boolean {
        val keys = table.keys.sorted()
        val index = keys.indexOf(current.toInt())
        if (index < 0) return true
        return if (forward) index < keys.size - 1 else index > 0
    }
}
