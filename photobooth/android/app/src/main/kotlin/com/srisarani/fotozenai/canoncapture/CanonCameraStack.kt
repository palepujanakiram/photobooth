package com.srisarani.fotozenai.canoncapture

import android.content.Context

/**
 * Which Canon implementation drives the DSLR.
 *
 * The app carries two stacks, and **they must never run at the same time**. PTP is a
 * strictly serialised protocol over one USB endpoint; two clients corrupt each other's
 * transactions.
 *
 * Default is [EDSDK_SIDECAR] so existing Pi / Direct-USB booths keep working on a
 * universal APK. ZenAI `cameraConnectionMode=direct_ptp` (or a lab dart-define) persists
 * [PTP] into SharedPreferences via [setPreferred], so the next cold start skips the
 * EDSDK sidecar in [com.srisarani.fotozenai.MainActivity.onCreate].
 */
enum class CanonCameraStack {

    /**
     * Pure-Kotlin PTP over `UsbDeviceConnection`, with the native capture screen.
     */
    PTP,

    /**
     * Canon EDSDK forked sidecar on `127.0.0.1:8791` (same HTTP contract as the Pi).
     */
    EDSDK_SIDECAR,
    ;

    companion object {
        private const val PREFS = "canon_camera_stack"
        private const val KEY = "stack"
        private const val VALUE_PTP = "ptp"
        private const val VALUE_EDSDK = "edsdk"

        /** Safe default for production APKs that still serve Pi / EDSDK booths. */
        val defaultStack: CanonCameraStack = EDSDK_SIDECAR

        fun resolved(context: Context): CanonCameraStack {
            val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            return when (prefs.getString(KEY, VALUE_EDSDK)) {
                VALUE_PTP -> PTP
                else -> EDSDK_SIDECAR
            }
        }

        fun usesPtp(context: Context): Boolean = resolved(context) == PTP

        fun usesEdsdkSidecar(context: Context): Boolean = resolved(context) == EDSDK_SIDECAR

        fun setPreferred(context: Context, stack: CanonCameraStack) {
            val value = if (stack == PTP) VALUE_PTP else VALUE_EDSDK
            context.applicationContext
                .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY, value)
                .apply()
        }
    }
}
