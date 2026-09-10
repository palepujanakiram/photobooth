package com.srisarani.fotozenai.canoncapture

/**
 * Carries accepted shots out of a running capture session, and messages back in.
 *
 * The capture screen normally reports once, through `startActivityForResult`,
 * when the whole session ends. That is right for a guest: one pose, one set of
 * photos, one await on the Dart side.
 *
 * An operator session never ends on its own — the photographer shoots all
 * evening — so each accepted frame has to reach Dart while the Activity is
 * still up. Both ends are in the same process, so a listener is enough; an
 * EventChannel would mean the Activity holding a Flutter binding it has no
 * other use for.
 *
 * Only [CanonPtpMethodChannel] sets [onShotAccepted], and only while it is
 * attached. Null means nothing is listening, which is the normal state for
 * every guest session.
 */
object CaptureShotBus {

    /**
     * Invoked on the main thread with one accepted shot.
     *
     * The session keeps running; this is a hand-off, not a completion.
     */
    @Volatile
    var onShotAccepted: ((CaptureSessionContract.Shot) -> Unit)? = null

    /**
     * Set by the capture screen so Dart can put a line on it — "Added to
     * queue", or why it was not.
     *
     * The screen owns its own status line, so it registers the way in rather
     * than Dart reaching for a view.
     */
    @Volatile
    var onMessage: ((String) -> Unit)? = null

    fun publish(shot: CaptureSessionContract.Shot) {
        onShotAccepted?.invoke(shot)
    }

    fun message(text: String) {
        onMessage?.invoke(text)
    }
}
