package com.srisarani.fotozenai.canoncapture

import androidx.annotation.LayoutRes
import com.srisarani.fotozenai.R

/**
 * Which look the native capture screen wears.
 *
 * **To switch, change [current] and rebuild.** That is the whole mechanism, deliberately —
 * a one-line edit in Kotlin, with no Dart change, no config plumbing and no rebuild of the
 * Flutter side needed to compare the two side by side.
 *
 * Both layouts declare the **same view ids**, so [CanonCaptureActivity] binds either one
 * without a branch. Anything added to one must be added to the other, or the missing id
 * fails fast at `findViewById` rather than silently doing nothing.
 */
enum class CaptureScreenStyle(@LayoutRes val layoutRes: Int) {

    /**
     * Matches the Flutter capture chrome — centred "POSE" title, subtitle line, shot strip
     * under it, back chevron top-left. Use this in front of guests: switching between the
     * Flutter and native screens should not be visible to them.
     */
    BOOTH(R.layout.activity_canon_capture_booth),

    /**
     * Minimal black screen with plain labels. Nothing competes with the viewfinder, and the
     * status line says exactly what the camera is doing — which is what you want when
     * bringing hardware up, not booth copy.
     */
    DIAGNOSTIC(R.layout.activity_canon_capture),
    ;

    companion object {
        /** The style the capture screen uses. Change this line to switch. */
        val current: CaptureScreenStyle = BOOTH
    }
}
