package com.srisarani.fotozenai.canon

import android.util.Log

/**
 * Logging for the Canon PTP stack.
 *
 * The `android-camera-connection` POC this code was copied from logs through Timber. This
 * app has no Timber dependency, and adding a logging library to satisfy a find-and-replace
 * is not worth an extra artifact in the APK — so this shim stands in for it.
 *
 * The signatures deliberately mirror the Timber surface the stack actually uses
 * (`v`/`d`/`i`/`w`/`e`, each with an optional leading [Throwable] and printf-style args).
 * That keeps the copy from the POC a pure `Timber.` → `CanonLog.` substitution, so the two
 * trees stay diffable when something misbehaves on hardware and the POC has to be used as
 * a known-good reference.
 *
 * Formatting is applied lazily — [format] is only called once the level has passed
 * [isLoggable]. The USB layer logs per transaction and live view runs a poll loop at
 * millisecond intervals, so eagerly building strings that get discarded would be real
 * garbage on the target box.
 */
object CanonLog {

    /** One tag for the whole stack, so `adb logcat -s FotozenCanon` shows the session. */
    const val TAG = "FotozenCanon"

    fun v(message: String, vararg args: Any?) = log(Log.VERBOSE, null, message, args)

    fun v(t: Throwable?, message: String, vararg args: Any?) = log(Log.VERBOSE, t, message, args)

    fun d(message: String, vararg args: Any?) = log(Log.DEBUG, null, message, args)

    fun d(t: Throwable?, message: String, vararg args: Any?) = log(Log.DEBUG, t, message, args)

    fun i(message: String, vararg args: Any?) = log(Log.INFO, null, message, args)

    fun i(t: Throwable?, message: String, vararg args: Any?) = log(Log.INFO, t, message, args)

    fun w(message: String, vararg args: Any?) = log(Log.WARN, null, message, args)

    fun w(t: Throwable?, message: String, vararg args: Any?) = log(Log.WARN, t, message, args)

    fun e(message: String, vararg args: Any?) = log(Log.ERROR, null, message, args)

    fun e(t: Throwable?, message: String, vararg args: Any?) = log(Log.ERROR, t, message, args)

    private fun log(priority: Int, t: Throwable?, message: String, args: Array<out Any?>) {
        if (!isLoggable(priority)) return
        val text = format(message, args)
        val body = if (t == null) text else "$text\n${Log.getStackTraceString(t)}"
        Log.println(priority, TAG, body)
    }

    /**
     * `Log.isLoggable` throws if the tag exceeds 23 characters on older Android, and can
     * throw on some vendor builds regardless. A logging call must never be the thing that
     * takes down a capture session, so failure here means "log it".
     */
    private fun isLoggable(priority: Int): Boolean =
        runCatching { Log.isLoggable(TAG, priority) }.getOrDefault(true) || priority >= Log.INFO

    /**
     * A malformed format string is a typo in a log line, not a reason to lose the message
     * or kill the caller — fall back to the raw template with the arguments appended.
     */
    private fun format(message: String, args: Array<out Any?>): String {
        if (args.isEmpty()) return message
        return runCatching { String.format(message, *args) }
            .getOrElse { "$message ${args.joinToString(prefix = "[", postfix = "]")}" }
    }
}
