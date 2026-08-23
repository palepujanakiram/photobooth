package com.srisarani.fotozenai.canoncapture

import com.srisarani.fotozenai.R

/** Slot chrome for the native strip. Mirrors Flutter's `_StripThumbSlot`. */
internal object CanonCaptureThumbs {
    const val GAP_DP = 10
    const val NUMBER_ACTIVE = 0xFFFFE082.toInt()
    const val NUMBER_IDLE = 0x61FFFFFF

    fun backgroundRes(
        filled: Boolean,
        active: Boolean,
    ): Int =
        when {
            active -> R.drawable.bg_canon_thumb_slot_active
            filled -> R.drawable.bg_canon_thumb_slot_filled
            else -> R.drawable.bg_canon_thumb_slot_empty
        }

    fun numberColor(active: Boolean): Int = if (active) NUMBER_ACTIVE else NUMBER_IDLE

    fun endMarginDp(
        index: Int,
        shotCount: Int,
    ): Int = if (index == shotCount - 1) 0 else GAP_DP
}
