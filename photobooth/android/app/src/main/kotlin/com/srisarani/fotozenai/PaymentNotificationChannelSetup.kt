package com.srisarani.fotozenai

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build

object PaymentNotificationChannelSetup {
    private const val CHANNEL_ID = "payment_updates"

    fun registerIfNeeded(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channel =
            NotificationChannel(
                CHANNEL_ID,
                "Payment Updates",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "FotoZen payment confirmation alerts"
                enableLights(true)
                enableVibration(true)
            }
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }
}
