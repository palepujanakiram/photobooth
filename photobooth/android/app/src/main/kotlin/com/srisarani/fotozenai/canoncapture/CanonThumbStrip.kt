package com.srisarani.fotozenai.canoncapture

import android.graphics.Bitmap
import android.view.LayoutInflater
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import com.srisarani.fotozenai.R

internal class CanonThumbStrip(
    private val strip: LinearLayout,
    private val inflater: LayoutInflater,
    private val density: Float,
) {
    fun buildSlots(shotCount: Int) {
        strip.removeAllViews()
        if (shotCount <= 1) {
            strip.visibility = View.GONE
            return
        }
        for (i in 0 until shotCount) {
            val slot = inflater.inflate(R.layout.view_canon_thumb_slot, strip, false)
            slot.findViewById<TextView>(R.id.canon_thumb_number).text = (i + 1).toString()
            (slot.layoutParams as? LinearLayout.LayoutParams)?.marginEnd =
                dip(CanonCaptureThumbs.endMarginDp(i, shotCount))
            strip.addView(slot)
        }
        strip.visibility = View.VISIBLE
        refreshStates(shotsTaken = 0)
    }

    fun refreshStates(shotsTaken: Int) {
        for (i in 0 until strip.childCount) {
            val slot = strip.getChildAt(i)
            val filled = i < shotsTaken
            val active = i == shotsTaken
            slot.setBackgroundResource(CanonCaptureThumbs.backgroundRes(filled, active))
            slot.findViewById<TextView>(R.id.canon_thumb_number).setTextColor(
                CanonCaptureThumbs.numberColor(active),
            )
        }
    }

    fun fillSlot(
        shotsTaken: Int,
        bitmap: Bitmap?,
    ) {
        if (strip.childCount == 0) return
        val slot = strip.getChildAt(shotsTaken - 1) ?: return
        refreshStates(shotsTaken)
        if (bitmap == null) return
        slot.findViewById<ImageView>(R.id.canon_thumb_image).apply {
            setImageBitmap(bitmap)
            visibility = View.VISIBLE
        }
        slot.findViewById<TextView>(R.id.canon_thumb_number).visibility = View.GONE
    }

    fun clearAt(
        index: Int,
        shotsTaken: Int,
    ) {
        val slot = strip.getChildAt(index) ?: return
        slot.findViewById<ImageView>(R.id.canon_thumb_image).apply {
            setImageDrawable(null)
            visibility = View.GONE
        }
        slot.findViewById<TextView>(R.id.canon_thumb_number).visibility = View.VISIBLE
        refreshStates(shotsTaken)
    }

    private fun dip(value: Int): Int = (value * density).toInt()
}
