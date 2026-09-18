package com.srisarani.fotozenai.dnp

import android.content.Context
import android.content.pm.ApplicationInfo
import android.os.SystemClock
import android.util.Log

/**
 * Debug-only timing trace for the print path.
 *
 * Everything between "job sent" and "printer active" used to be one 17-second
 * silence: the completion poller logs *after* `parseStatus()` returns, so a poll
 * that blocks on four stacked USB read timeouts leaves no trace at all, and the
 * delay could not be attributed after the fact. This makes each step say when it
 * started, not only when it finished.
 *
 * Off in release by design. The per-poll detail is far too chatty for a live
 * event, and the field diagnosis that matters there — the stage timings and
 * `waitForPrintComplete` — is already logged unconditionally. [enabled] is read
 * from the app's own debuggable flag rather than a constant, so a release build
 * cannot ship with it accidentally left on.
 */
internal object DnpTrace {
    private const val TAG = "DnpTrace"

    @Volatile
    var enabled: Boolean = false
        private set

    fun init(context: Context) {
        enabled = (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (enabled) Log.i(TAG, "DNP print tracing on (debuggable build)")
    }

    /** Milliseconds since boot, for correlating steps within one print. */
    fun now(): Long = SystemClock.elapsedRealtime()

    fun log(message: String) {
        if (enabled) Log.d(TAG, message)
    }

    /** Logs how long [block] took, whatever it returns or throws. */
    inline fun <T> timed(
        label: String,
        block: () -> T,
    ): T {
        if (!enabled) return block()
        val started = now()
        var outcome = "ok"
        try {
            return block()
        } catch (e: Throwable) {
            outcome = "threw ${e.javaClass.simpleName}"
            throw e
        } finally {
            log("$label: ${now() - started}ms ($outcome)")
        }
    }
}
